import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weekpact/src/home/home_backend.dart';

void main() {
  test(
    'nudge RPCs use authenticated sender and parse persistent cooldown',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String, dynamic>{};
      server.listen((request) async {
        requests[request.uri.path] = jsonDecode(
          await utf8.decoder.bind(request).join(),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('crew_nudge_status')
                ? [
                    {
                      'recipient_id': 'member',
                      'status': 'cooldown',
                      'next_allowed_at': '2026-09-15T13:00:00Z',
                    },
                  ]
                : {'status': 'sent', 'next_allowed_at': '2026-09-15T13:00:00Z'},
          ),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final backend = SupabaseHomeBackend(client);
      final states = await backend.fetchNudgeStates('crew');
      expect(states['member']!.status, CrewNudgeStatus.cooldown);
      expect(states['member']!.nextAllowedAt, DateTime.utc(2026, 9, 15, 13));
      final sent = await backend.sendNudge(
        crewId: 'crew',
        recipientId: 'member',
      );
      expect(sent.status, CrewNudgeStatus.sent);
      expect(requests['/rest/v1/rpc/crew_nudge_status'], {
        'target_crew_id': 'crew',
      });
      expect(requests['/rest/v1/rpc/send_crew_nudge'], {
        'target_crew_id': 'crew',
        'target_user_id': 'member',
      });
    },
  );
}

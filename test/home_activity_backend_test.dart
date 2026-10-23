import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weekpact/src/home/home_backend.dart';

void main() {
  test('history is crew-scoped across dates and paginates tied timestamps', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {
            'pact_id': '00000000-0000-0000-0000-000000000002',
            'user_id': '00000000-0000-0000-0000-000000000003',
            'completed_on': '2026-08-01',
            'created_at': '2026-08-01T12:00:00.123456Z',
            'crew_pacts': {'title': 'Older pact', 'crew_id': 'crew'},
          },
        ]),
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
    final first = await backend.fetchActivity('crew', limit: 1);
    expect(first.single.pactTitle, 'Older pact');
    expect(first.single.completedOn, '2026-08-01');
    await backend.fetchActivity('crew', before: first.single, limit: 1);
    for (final request in requests) {
      final query = request.queryParameters;
      expect(request.path, endsWith('/pact_check_ins'));
      expect(query['crew_pacts.crew_id'], 'eq.crew');
      expect(query['select'], contains('crew_pacts!inner(title,crew_id)'));
      expect(query['completed_on'], isNull);
      expect(query['offset'], isNull);
      expect(query['limit'], '1');
      expect(
        query['order'],
        'created_at.desc.nullslast,pact_id.desc.nullslast,user_id.desc.nullslast,completed_on.desc.nullslast',
      );
    }
    expect(requests.first.queryParameters['or'], isNull);
    final cursor = first.single;
    const timestamp = '2026-08-01T12:00:00.123456Z';
    expect(
      requests.last.queryParameters['or'],
      '(created_at.lt.$timestamp,'
      'and(created_at.eq.$timestamp,pact_id.lt.${cursor.pactId}),'
      'and(created_at.eq.$timestamp,pact_id.eq.${cursor.pactId},user_id.lt.${cursor.userId}),'
      'and(created_at.eq.$timestamp,pact_id.eq.${cursor.pactId},user_id.eq.${cursor.userId},completed_on.lt.2026-08-01))',
    );
  });

  for (final hasAny in [true, false]) {
    test(
      'this week arrives in one call with its activity, achievements and nudges, ${hasAny ? 'when there is a check-in' : 'or no check-in at all'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Uri>[];
        server.listen((request) async {
          requests.add(request.uri);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'today': '2026-09-14',
              'week_start': '2026-09-14',
              'timezone': 'Pacific/Auckland',
              'next_day_at': '2026-09-14T12:00:00+00:00',
              'pacts': [
                {
                  'id': 'pact',
                  'crew_id': 'crew',
                  'title': 'Hangboard',
                  'frequency': 'weekly',
                  'days_per_week': 5,
                },
              ],
              'members': [
                {
                  'user_id': 'member',
                  'email': 'm@example.com',
                  'display_name': 'Mirnes',
                },
              ],
              'check_ins': [
                {
                  'pact_id': 'pact',
                  'user_id': 'member',
                  'completed_on': '2026-09-13',
                },
              ],
              'latest_activity': hasAny
                  ? {
                      'pact_id': 'pact',
                      'user_id': 'member',
                      'created_at': '2026-09-13T18:30:00+02:00',
                      'photo_path': 'member/crew/pact/photo.png',
                    }
                  : null,
              'achievements': [],
              'nudges': [
                {
                  'recipient_id': 'member',
                  'status': 'cooldown',
                  'next_allowed_at': '2026-09-15T08:00:00+00:00',
                },
              ],
            }),
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
        final week = await SupabaseHomeBackend(client).fetchWeek('crew');
        // One round trip: nothing else is asked for after the week.
        expect(requests.map((uri) => uri.path), [
          endsWith('/rpc/crew_week_overview'),
        ]);
        expect(week.checkIns.single.day, '2026-09-13');
        expect(week.nextDayAt, DateTime.utc(2026, 9, 14, 12));
        expect(week.nudges?['member']?.status, CrewNudgeStatus.cooldown);
        expect(week.achievements, isEmpty);
        if (hasAny) {
          expect(week.latestActivity?.photoPath, 'member/crew/pact/photo.png');
          expect(
            week.latestActivity?.createdAt,
            DateTime.utc(2026, 9, 13, 16, 30),
          );
        } else {
          expect(week.latestActivity, isNull);
        }
      },
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weekpact/src/home/home_backend.dart';

import 'support/photo_fakes.dart';

void main() {
  for (final failUpload in [false, true]) {
    test(
      'photo upload ${failUpload ? 'failure does not save a check-in' : 'precedes a scoped save and private download'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <String>[];
        final bodies = <String, dynamic>{};
        List<int>? uploadBytes;
        String? uploadType;
        String? upsert;
        String? downloadAuthorization;
        server.listen((request) async {
          requests.add('${request.method} ${request.uri.path}');
          final bytes = await request.fold<List<int>>(
            [],
            (all, next) => all..addAll(next),
          );
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path.endsWith('/token')) {
            request.response.write(
              jsonEncode({
                'access_token': 'test-access-token',
                'refresh_token': 'refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': 'user',
                  'aud': 'authenticated',
                  'email': 'user@example.com',
                  'created_at': '2026-09-15T00:00:00Z',
                  'app_metadata': {},
                  'user_metadata': {},
                },
              }),
            );
          } else if (request.uri.path.contains('/storage/') &&
              request.method == 'POST') {
            uploadBytes = bytes;
            upsert = request.headers.value('x-upsert');
            uploadType = request.headers.contentType?.mimeType;
            if (failUpload) {
              request.response.statusCode = 400;
              request.response.write(
                jsonEncode({
                  'statusCode': '400',
                  'error': 'Upload failed',
                  'message': 'offline',
                }),
              );
            } else {
              request.response.write(
                jsonEncode({'Key': request.uri.path.split('/object/').last}),
              );
            }
          } else if (request.uri.path.contains('/storage/') &&
              request.method == 'GET') {
            downloadAuthorization = request.headers.value('authorization');
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(testCheckInPhoto);
          } else {
            bodies[request.uri.path.split('/').last] = jsonDecode(
              utf8.decode(bytes),
            );
            request.response.write('null');
          }
          await request.response.close();
        });
        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        addTearDown(() async {
          await client.dispose();
          await server.close(force: true);
        });
        await client.auth.signInWithPassword(
          email: 'user@example.com',
          password: 'password',
        );
        final backend = SupabaseHomeBackend(client);
        final saving = backend.saveCheckIns(
          crewId: 'crew',
          today: '2026-09-15',
          pactIds: {'pact', 'existing'},
          photos: {'pact': testCheckInPhoto},
        );
        if (failUpload) {
          await expectLater(saving, throwsA(isA<StorageException>()));
        } else {
          await saving;
        }
        expect(
          latin1.decode(uploadBytes!),
          contains(latin1.decode(testCheckInPhoto)),
        );
        expect(
          latin1.decode(uploadBytes!),
          contains('content-type: image/png'),
        );
        expect(uploadType, 'multipart/form-data');
        expect(upsert, 'false');
        final path =
            (bodies['discard_unused_check_in_photos']['paths'] as List).single
                as String;
        expect(path, matches(r'^user/crew/pact/2026-09-15/[0-9a-f]{32}\.png$'));
        if (failUpload) {
          expect(
            bodies.containsKey('save_pact_check_ins_with_photos'),
            isFalse,
          );
        } else {
          final save = bodies['save_pact_check_ins_with_photos'];
          expect(save['photos'], {'pact': path});
          expect(save['selected_pact_ids'], ['pact', 'existing']);
          expect(save['target_crew_id'], 'crew');
          expect(save['expected_today'], '2026-09-15');
          expect(
            requests[1],
            startsWith('POST /storage/v1/object/check-in-photos/'),
          );
          expect(
            requests[2],
            'POST /rest/v1/rpc/save_pact_check_ins_with_photos',
          );
          expect(await backend.fetchCheckInPhoto(path), testCheckInPhoto);
          expect(downloadAuthorization, 'Bearer test-access-token');
          expect(requests.last, 'GET /storage/v1/object/check-in-photos/$path');
        }
      },
    );
  }
}

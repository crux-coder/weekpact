import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/home/home_cache.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late Completer<Map<String, dynamic>> profile;
  var profileRequests = 0;

  setUp(() async {
    profileRequests = 0;
    profile = Completer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
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
              'app_metadata': {'provider': 'email'},
              'user_metadata': {},
            },
          }),
        );
      } else if (request.uri.path.endsWith('/users')) {
        profileRequests++;
        final row = await profile.future;
        final single = request.headers.value('accept')?.contains('object');
        request.response.write(jsonEncode(single == true ? row : [row]));
      } else {
        request.response.write('null');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'user@example.com',
      password: 'password',
    );
  });

  tearDown(() async {
    if (!profile.isCompleted) profile.complete({'id': 'user'});
    await client.dispose();
    await server.close(force: true);
  });

  Future<HomeCache> cache([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return HomeCache(await SharedPreferences.getInstance());
  }

  test('a kept profile opens the app without waiting on the network, and '
      'the fresh row replaces it behind', () async {
    final kept = await cache({
      'home_cache_profile:user': jsonEncode({
        'id': 'user',
        'first_name': 'Kept',
        'onboarding_step': 'done',
      }),
    });
    final backend = SupabaseAuthBackend(client, cache: kept);

    await backend.restoreProfile();

    expect(profile.isCompleted, isFalse, reason: 'nothing was waited on');
    expect(backend.currentUser!.profileLoaded, isTrue);
    expect(backend.currentUser!.firstName, 'Kept');

    profile.complete({
      'id': 'user',
      'first_name': 'Fresh',
      'onboarding_step': 'done',
    });
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(profileRequests, 1);
    expect(backend.currentUser!.firstName, 'Fresh');
    expect(kept.readProfile('user')?['first_name'], 'Fresh');
  });

  test('without a kept profile the first launch waits for the row and keeps '
      'it for the next', () async {
    final empty = await cache();
    final backend = SupabaseAuthBackend(client, cache: empty);

    final restoring = backend.restoreProfile();
    profile.complete({
      'id': 'user',
      'first_name': 'Ada',
      'onboarding_step': 'done',
    });
    await restoring;

    expect(backend.currentUser!.profileLoaded, isTrue);
    expect(backend.currentUser!.firstName, 'Ada');
    expect(empty.readProfile('user')?['first_name'], 'Ada');
  });

  test('a kept profile is not handed to another account', () async {
    final kept = await cache({
      'home_cache_profile:someone-else': jsonEncode({
        'id': 'someone-else',
        'first_name': 'Other',
      }),
    });
    final backend = SupabaseAuthBackend(client, cache: kept);

    final restoring = backend.restoreProfile();
    expect(backend.currentUser!.profileLoaded, isFalse);
    profile.complete({'id': 'user', 'first_name': 'Ada'});
    await restoring;

    expect(backend.currentUser!.firstName, 'Ada');
  });
}

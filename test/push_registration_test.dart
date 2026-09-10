import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/notifications/notification_service.dart';
import 'package:weekpact/src/notifications/push_registration.dart';

import 'notifications_test.dart' show FakeMessaging;
import 'widget_test.dart' show FakeAuthBackend;

class RegistrationAuth extends FakeAuthBackend {
  AuthUser? user = const AuthUser(id: 'user-a', email: 'a@example.com');
  final events = StreamController<AuthUser?>.broadcast(sync: true);
  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthUser?> get authStateChanges => events.stream;
}

class Registry implements PushDeviceRegistry {
  final calls = <String>[];
  bool fail = false;
  Completer<void>? barrier;
  @override
  Future<void> register(String token) async {
    calls.add('register:$token');
    if (fail) throw StateError('offline');
    await barrier?.future;
  }

  @override
  Future<void> unregister(String token) async {
    calls.add('remove:$token');
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  late RegistrationAuth auth;
  late FakeMessaging client;
  late NotificationService service;
  late Registry registry;
  late PushRegistration binding;
  setUp(() async {
    auth = RegistrationAuth();
    client = FakeMessaging();
    registry = Registry();
    service = NotificationService(
      createClient: () async => client,
      saveEnabled: (_) async {},
    );
    binding = PushRegistration(auth, service, registry)..start();
    await service.initialize();
  });
  tearDown(() async {
    await binding.dispose();
    service.dispose();
    await client.dispose();
    await auth.events.close();
    auth.dispose();
  });
  test(
    'registers signed-in device and removes old token on rotation',
    () async {
      await service.enable();
      await flush();
      client.tokens.add('rotated-token');
      await flush();
      expect(registry.calls, [
        'register:test-device-token',
        'remove:test-device-token',
        'register:rotated-token',
      ]);
    },
  );
  test(
    'logout waits for registration then unlinks and blocks late token events',
    () async {
      registry.barrier = Completer<void>();
      await service.enable();
      await flush();
      var done = false;
      final logout = binding.prepareSignOut().then((_) => done = true);
      await flush();
      expect(done, isFalse);
      registry.barrier!.complete();
      await logout;
      client.tokens.add('late-token');
      await flush();
      expect(registry.calls, [
        'register:test-device-token',
        'remove:test-device-token',
      ]);
      auth.user = null;
      auth.events.add(null);
      binding.resume();
      await flush();
      expect(registry.calls.length, 2);
    },
  );
  test(
    'registration failure retries even when the FCM token is unchanged',
    () async {
      registry.fail = true;
      await service.enable();
      await flush();
      expect(service.registrationError, isNotNull);
      registry.fail = false;
      await service.refresh();
      await flush();
      expect(service.registrationError, isNull);
      expect(registry.calls.length, 2);
    },
  );
  test('signed-out app does not register tokens with a user', () async {
    auth.user = null;
    auth.events.add(null);
    await service.enable();
    await flush();
    expect(registry.calls, isEmpty);
    auth.user = const AuthUser(id: 'user-b', email: 'b@example.com');
    auth.events.add(auth.user);
    await flush();
    expect(registry.calls, ['register:test-device-token']);
  });
}

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/notifications/messaging_client.dart';
import 'package:weekpact/src/notifications/notification_service.dart';

class FakeMessaging implements MessagingClient {
  final tokens = StreamController<String>.broadcast(sync: true);
  final messages = StreamController<RemoteMessage>.broadcast(sync: true);
  final opens = StreamController<RemoteMessage>.broadcast(sync: true);
  AuthorizationStatus status = AuthorizationStatus.notDetermined;
  AuthorizationStatus requested = AuthorizationStatus.authorized;
  bool ready = true;
  bool requiresAutoInitForApns = false;
  bool autoInit = false;
  bool failToken = false;
  int requests = 0;
  int tokenReads = 0;
  int deletes = 0;
  RemoteMessage? initial;
  @override
  Stream<String> get tokenChanges => tokens.stream;
  @override
  Stream<RemoteMessage> get foregroundMessages => messages.stream;
  @override
  Stream<RemoteMessage> get openedMessages => opens.stream;
  @override
  Future<AuthorizationStatus> permission({bool request = false}) async {
    if (request) {
      requests++;
      status = requested;
    }
    return status;
  }

  @override
  Future<bool> isDeviceReady() async =>
      ready && (!requiresAutoInitForApns || autoInit);
  @override
  Future<String?> getToken() async {
    tokenReads++;
    if (failToken) throw StateError('offline');
    return 'test-device-token';
  }

  @override
  Future<void> deleteToken() async {
    deletes++;
  }

  @override
  Future<void> setAutoInit(bool enabled) async {
    autoInit = enabled;
  }

  @override
  Future<RemoteMessage?> initialMessage() async => initial;
  Future<void> dispose() async {
    await tokens.close();
    await messages.close();
    await opens.close();
  }
}

void main() {
  late FakeMessaging client;
  late NotificationService service;
  late bool savedEnabled;
  setUp(() {
    client = FakeMessaging();
    savedEnabled = false;
    service = NotificationService(
      createClient: () async => client,
      saveEnabled: (value) async {
        savedEnabled = value;
      },
      delay: (_) async {},
    );
  });
  tearDown(() async {
    service.dispose();
    await client.dispose();
  });

  test('startup never prompts or generates a token before opt-in', () async {
    await service.initialize();
    expect(service.available, isTrue);
    expect(client.requests, 0);
    expect(client.tokenReads, 0);
    expect(client.autoInit, isFalse);
  });
  test('opt-in registers and token rotation reaches subscribers', () async {
    await service.initialize();
    final changes = <String?>[];
    final subscription = service.tokenChanges.listen(changes.add);
    await service.enable();
    expect(client.requests, 1);
    expect(savedEnabled, isTrue);
    expect(service.token, 'test-device-token');
    client.tokens.add('rotated-token');
    await Future<void>.delayed(Duration.zero);
    expect(service.token, 'rotated-token');
    expect(changes, ['test-device-token', 'rotated-token']);
    await subscription.cancel();
  });
  test('denied permission does not create a token', () async {
    client.requested = AuthorizationStatus.denied;
    await service.initialize();
    await service.enable();
    expect(client.tokenReads, 0);
    expect(savedEnabled, isFalse);
    expect(service.enabled, isFalse);
  });
  test(
    'opt-in starts Apple registration before waiting for the APNs token',
    () async {
      client.requiresAutoInitForApns = true;
      await service.initialize();
      expect(client.autoInit, isFalse);
      await service.enable();
      expect(service.token, 'test-device-token');
      expect(service.error, isNull);
    },
  );
  test('APNs delay prevents premature FCM calls and retry succeeds', () async {
    client.ready = false;
    await service.initialize();
    await service.enable();
    expect(client.tokenReads, 0);
    expect(service.error, contains('pending'));
    client.ready = true;
    await service.refresh();
    expect(service.token, 'test-device-token');
    expect(service.error, isNull);
    expect(client.requests, 1);
  });
  test('turning off deletes token and ignores late refresh events', () async {
    await service.initialize();
    await service.enable();
    final previousDeletes = client.deletes;
    await service.disable();
    client.tokens.add('late-token');
    expect(client.deletes, previousDeletes + 1);
    expect(client.autoInit, isFalse);
    expect(service.token, isNull);
    expect(savedEnabled, isFalse);
  });
  test(
    'permission changes in Settings clear token without prompting',
    () async {
      await service.initialize();
      await service.enable();
      client.status = AuthorizationStatus.denied;
      await service.refresh();
      expect(service.token, isNull);
      expect(client.autoInit, isFalse);
      expect(client.requests, 1);
    },
  );
  test('foreground, background tap and cold-start tap are retained', () async {
    client.initial = const RemoteMessage(messageId: 'cold');
    await service.initialize();
    expect(service.lastOpenedMessage?.messageId, 'cold');
    await service.enable();
    final received = <RemoteMessage>[];
    final opened = <RemoteMessage>[];
    final first = service.foregroundMessages.listen(received.add);
    final second = service.openedMessages.listen(opened.add);
    client.messages.add(const RemoteMessage(messageId: 'foreground'));
    client.opens.add(const RemoteMessage(messageId: 'background-tap'));
    await Future<void>.delayed(Duration.zero);
    expect(received.single.messageId, 'foreground');
    expect(opened.single.messageId, 'background-tap');
    expect(service.receivedCount, 1);
    await first.cancel();
    await second.cancel();
  });
  test('network failure keeps opt-in and allows registration retry', () async {
    client.failToken = true;
    await service.initialize();
    await service.enable();
    expect(service.enabled, isTrue);
    expect(service.error, isNotNull);
    expect(service.busy, isFalse);
    client.failToken = false;
    await service.refresh();
    expect(service.token, 'test-device-token');
  });
  test('missing Firebase config does not prevent app startup', () async {
    final unavailable = NotificationService(
      createClient: () async => throw UnsupportedError('unconfigured'),
      saveEnabled: (_) async {},
    );
    await unavailable.initialize();
    expect(unavailable.available, isFalse);
    expect(unavailable.error, contains('this build'));
    expect(unavailable.busy, isFalse);
    unavailable.dispose();
  });
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Transport seam for platform-independent permission and token lifecycle tests.
abstract interface class MessagingClient {
  Stream<String> get tokenChanges;
  Stream<RemoteMessage> get foregroundMessages;
  Stream<RemoteMessage> get openedMessages;
  Future<AuthorizationStatus> permission({bool request = false});
  Future<bool> isDeviceReady();
  Future<String?> getToken();
  Future<void> deleteToken();
  Future<void> setAutoInit(bool enabled);
  Future<RemoteMessage?> initialMessage();
}

class FirebaseMessagingClient implements MessagingClient {
  FirebaseMessagingClient(this._messaging);
  final FirebaseMessaging _messaging;

  static Future<MessagingClient> create() async {
    if (kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      throw UnsupportedError(
        'Push notifications are configured for iOS and Android.',
      );
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    return FirebaseMessagingClient(messaging);
  }

  @override
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;
  @override
  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;
  @override
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;
  @override
  Future<AuthorizationStatus> permission({bool request = false}) async =>
      (await (request
              ? _messaging.requestPermission(
                  alert: true,
                  badge: true,
                  sound: true,
                )
              : _messaging.getNotificationSettings()))
          .authorizationStatus;
  @override
  Future<bool> isDeviceReady() async =>
      defaultTargetPlatform != TargetPlatform.iOS ||
      await _messaging.getAPNSToken() != null;
  @override
  Future<String?> getToken() => _messaging.getToken();
  @override
  Future<void> deleteToken() => _messaging.deleteToken();
  @override
  Future<void> setAutoInit(bool enabled) =>
      _messaging.setAutoInitEnabled(enabled);
  @override
  Future<RemoteMessage?> initialMessage() => _messaging.getInitialMessage();
}

/// The OS displays notification payloads while backgrounded. Data-only work can
/// be added here later; never navigate or access main-isolate state here.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

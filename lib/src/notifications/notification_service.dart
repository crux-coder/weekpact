import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'messaging_client.dart';

/// Device-level FCM infrastructure. Tokens are not associated with accounts yet.
class NotificationService extends ChangeNotifier {
  NotificationService({
    required this._createClient,
    required this._saveEnabled,
    this._enabled = false,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final Future<MessagingClient> Function() _createClient;
  final Future<void> Function(bool) _saveEnabled;
  final Future<void> Function(Duration) _delay;
  MessagingClient? _client;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _opened = StreamController<RemoteMessage>.broadcast();
  final _tokens = StreamController<String?>.broadcast();
  bool _enabled;
  bool _busy = false;
  bool _disposed = false;
  bool get enabled => _enabled;
  bool get busy => _busy;
  bool get available => _client != null;
  AuthorizationStatus permission = AuthorizationStatus.notDetermined;
  String? token;
  String? error;
  String? registrationError;
  Future<void> Function()? beforeDisable;
  void setRegistrationError(String? value) {
    registrationError = value;
    _notify();
  }

  RemoteMessage? lastOpenedMessage;

  /// The tapped notification nobody has acted on yet. Kept apart from
  /// [lastOpenedMessage] so a cold-start tap is routed once, by whichever
  /// screen is ready to take it, and not again when that screen is rebuilt.
  RemoteMessage? _pendingOpen;

  /// Hands over the tapped notification, if one is waiting, and forgets it.
  RemoteMessage? takeOpenedMessage() {
    final message = _pendingOpen;
    _pendingOpen = null;
    return message;
  }

  int receivedCount = 0;
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;
  Stream<RemoteMessage> get openedMessages => _opened.stream;
  Stream<String?> get tokenChanges => _tokens.stream;
  bool get allowed =>
      permission == AuthorizationStatus.authorized ||
      permission == AuthorizationStatus.provisional;

  Future<void> initialize() => _run(() async {
    if (_client != null) return;
    final client = await _createClient();
    if (_disposed) return;
    _client = client;
    _subscriptions.add(
      client.tokenChanges.listen((value) {
        if (_enabled && allowed) _setToken(value);
      }, onError: (Object _) => _streamError()),
    );
    _subscriptions.add(
      client.foregroundMessages.listen((message) {
        if (_disposed || !_enabled || !allowed) return;
        receivedCount++;
        _foreground.add(message);
        _notify();
      }, onError: (Object _) => _streamError()),
    );
    _subscriptions.add(
      client.openedMessages.listen(
        _handleOpen,
        onError: (Object _) => _streamError(),
      ),
    );
    final initial = await client.initialMessage();
    if (initial != null && !_disposed) _handleOpen(initial);
    await _refresh();
  });

  Future<void> enable() => _run(() async {
    final client = _client;
    if (client == null) return;
    permission = await client.permission(request: true);
    if (!allowed) {
      _enabled = false;
      await _saveEnabled(false);
      _setToken(null);
      await client.setAutoInit(false);
      return;
    }
    await _saveEnabled(true);
    _enabled = true;
    await _register();
  });

  Future<void> disable() => _run(() async {
    await beforeDisable?.call();
    await _saveEnabled(false);
    _enabled = false;
    _setToken(null);
    await _client?.setAutoInit(false);
    if (_client != null && await _client!.isDeviceReady()) {
      await _client!.deleteToken();
    }
  });

  /// Recheck system Settings when returning to the app; never prompt here.
  Future<void> refresh() => _run(_refresh);

  Future<void> _refresh() async {
    final client = _client;
    if (client == null || _disposed) return;
    permission = await client.permission();
    if (_enabled && allowed) {
      await _register();
    } else {
      _setToken(null);
      await client.setAutoInit(false);
      if (await client.isDeviceReady()) await client.deleteToken();
    }
  }

  Future<void> _register() async {
    final client = _client!;
    // FlutterFire defers native APNs registration while auto-init is disabled.
    // Start it after opt-in, then wait for APNs before explicitly fetching FCM.
    await client.setAutoInit(true);
    // APNs registration can lag behind the iOS permission dialog.
    var ready = await client.isDeviceReady();
    for (var attempt = 0; !ready && attempt < 5 && !_disposed; attempt++) {
      await _delay(const Duration(milliseconds: 500));
      ready = await client.isDeviceReady();
    }
    if (_disposed) return;
    if (!ready) {
      error = 'Device registration is pending. Try again in a moment.';
      return;
    }
    _setToken(await client.getToken());
    if (token == null) error = 'Couldn’t register notifications. Please retry.';
  }

  void _handleOpen(RemoteMessage message) {
    if (_disposed) return;
    // Retain the cold start message until the signed-in screen is ready to
    // route it; see [takeOpenedMessage].
    lastOpenedMessage = message;
    _pendingOpen = message;
    _opened.add(message);
    _notify();
  }

  void _setToken(String? value) {
    if (_disposed) return;
    if (token == value) {
      if (value != null) _tokens.add(value);
      return;
    }
    token = value;
    _tokens.add(value);
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _disposed) return;
    _busy = true;
    error = null;
    _notify();
    try {
      await action();
    } on UnsupportedError {
      error = 'Notifications aren’t available in this build yet.';
    } catch (_) {
      error = 'Couldn’t update notifications. Check your connection and retry.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _streamError() {
    error = 'Notification connection interrupted. Please retry.';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_foreground.close());
    unawaited(_opened.close());
    unawaited(_tokens.close());
    super.dispose();
  }
}

/// The crew whose chat a tapped push is about, or null for any other push.
String? chatPushCrewId(RemoteMessage message) {
  final crewId = message.data['crew_id'];
  return message.data['type'] == 'chat_message' &&
          crewId is String &&
          crewId.isNotEmpty
      ? crewId
      : null;
}

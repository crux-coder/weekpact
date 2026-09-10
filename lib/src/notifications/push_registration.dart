import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../auth/auth_backend.dart';
import 'notification_service.dart';

abstract interface class PushDeviceRegistry {
  Future<void> register(String token);
  Future<void> unregister(String token);
}

class SupabasePushDeviceRegistry implements PushDeviceRegistry {
  SupabasePushDeviceRegistry(this.client);
  final SupabaseClient client;
  @override
  Future<void> register(String token) async {
    await client.rpc(
      'register_push_device',
      params: {
        'device_token': token,
        'device_platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      },
    );
  }

  @override
  Future<void> unregister(String token) async {
    await client.rpc('unregister_push_device', params: {'device_token': token});
  }
}

/// Serializes token rotation and logout so an old registration cannot finish
/// after logout cleanup. The server also checks the original login session.
class PushRegistration {
  PushRegistration(this.auth, this.notifications, this.registry);
  final AuthBackend auth;
  final NotificationService notifications;
  final PushDeviceRegistry registry;
  Future<void> _pending = Future.value();
  StreamSubscription<String?>? _tokens;
  StreamSubscription<AuthUser?>? _auth;
  String? _registeredToken;
  String? _registeredUser;
  bool _paused = false;

  void start() {
    _tokens = notifications.tokenChanges.listen((_) => _sync());
    _auth = auth.authStateChanges.listen(
      (user) {
        _paused = false;
        if (user == null) {
          _registeredToken = null;
          _registeredUser = null;
        }
        _sync();
      },
      onError: (Object _) {
        /* AuthGate handles invalid authentication links. */
      },
    );
    _sync();
  }

  void _sync() {
    if (_paused) return;
    final user = auth.currentUser?.id;
    final token = notifications.token;
    _pending = _pending
        .then((_) async {
          if (_paused || auth.currentUser?.id != user || user == null) return;
          final previous = _registeredToken;
          if (previous != null &&
              previous != token &&
              _registeredUser == user) {
            await registry.unregister(previous);
            _registeredToken = null;
          }
          if (token != null) {
            await registry.register(token);
            _registeredToken = token;
            _registeredUser = user;
          }
          notifications.setRegistrationError(null);
        })
        .catchError((Object _) {
          notifications.setRegistrationError(
            'Couldn’t connect this device to crew notifications. Please retry.',
          );
        });
  }

  Future<void> unregisterCurrentDevice() async {
    _paused = true;
    try {
      await _pending;
      final token = _registeredToken ?? notifications.token;
      if (token != null && auth.currentUser != null) {
        await registry.unregister(token);
      }
      _registeredToken = null;
      _registeredUser = null;
      notifications.setRegistrationError(null);
    } finally {
      _paused = false;
    }
  }

  Future<void> prepareSignOut() async {
    await unregisterCurrentDevice();
    _paused = true;
  }

  void resume() {
    _paused = false;
    _sync();
  }

  Future<void> dispose() async {
    await _tokens?.cancel();
    await _auth?.cancel();
  }
}

import 'dart:async';

import '../auth/auth_backend.dart';
import 'subscription_backend.dart';

/// Keeps the RevenueCat app user id in step with the signed-in Supabase
/// account, so entitlements follow the person across devices and reinstalls
/// rather than being stranded on one anonymous install.
///
/// Serialized like PushRegistration: a slow identify for a previous account
/// must not land after a newer sign-in.
class SubscriptionIdentity {
  SubscriptionIdentity(this.auth, this.subscriptions);

  final AuthBackend auth;
  final SubscriptionBackend subscriptions;

  Future<void> _pending = Future.value();
  StreamSubscription<AuthUser?>? _auth;
  String? _identified;

  void start() {
    _auth = auth.authStateChanges.listen(
      (_) => _sync(),
      onError: (Object _) {
        /* AuthGate handles invalid authentication links. */
      },
    );
    _sync();
  }

  void _sync() {
    final user = auth.currentUser?.id;
    _pending = _pending
        .then((_) async {
          // Bail out if the account changed again while this was queued.
          if (auth.currentUser?.id != user) return;
          if (user == null || user.isEmpty) {
            if (_identified == null) return;
            _identified = null;
            await subscriptions.forgetUser();
            return;
          }
          if (_identified == user) return;
          await subscriptions.identify(user);
          _identified = user;
        })
        .catchError((Object _) {
          // Identity is retried on the next auth change or refresh; a failure
          // here must never block sign-in.
          _identified = null;
        });
  }

  Future<void> dispose() async {
    await _auth?.cancel();
    _auth = null;
  }
}

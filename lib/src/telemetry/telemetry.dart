import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';

/// Optional device diagnostics. No account identifiers, free-form user content,
/// invitation URLs, or auth error messages are attached to crash reports.
class CrashReporting extends ValueNotifier<bool> {
  CrashReporting._() : super(false);
  static final instance = CrashReporting._();
  FirebaseCrashlytics? _client;
  SharedPreferences? _preferences;
  bool get available => _client != null;
  Future<void> initialize(SharedPreferences preferences) async {
    _preferences = preferences;
    if (kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _client = FirebaseCrashlytics.instance;
      value = preferences.getBool('diagnostics_enabled') ?? false;
      await _client!.setCrashlyticsCollectionEnabled(value && kReleaseMode);
      if (!value) await _client!.deleteUnsentReports();
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        previous?.call(details);
        capture(
          details.exception,
          details.stack ?? StackTrace.current,
          fatal: true,
        );
      };
      final previousAsync = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        capture(error, stack, fatal: true);
        return previousAsync?.call(error, stack) ?? false;
      };
    } catch (_) {
      _client = null;
      value = false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_client == null || _preferences == null) {
      throw StateError('Diagnostics unavailable');
    }
    await _client!.setCrashlyticsCollectionEnabled(enabled && kReleaseMode);
    if (!enabled) await _client!.deleteUnsentReports();
    if (!await _preferences!.setBool('diagnostics_enabled', enabled)) {
      await _client!.setCrashlyticsCollectionEnabled(false);
      value = false;
      throw StateError('Could not save diagnostics preference');
    }
    value = enabled;
  }

  void capture(Object error, StackTrace stack, {bool fatal = false}) {
    if (!value || !kReleaseMode || _client == null) return;
    unawaited(
      _client!
          .recordError(error.runtimeType.toString(), stack, fatal: fatal)
          .catchError((Object _) {}),
    );
  }
}

/// Funnel events come from successful database writes. This records only the
/// signed-in return visit, once per week server-side; it never delays the app.
class ProductAnalytics with WidgetsBindingObserver {
  ProductAnalytics(this.client);
  final SupabaseClient client;
  StreamSubscription<AuthState>? _auth;
  DateTime? _last;
  String? _user;
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _auth = client.auth.onAuthStateChange.listen(
      (_) => _record(),
      onError: (Object _) {},
    );
    _record();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _record();
  }

  void _record() {
    final user = client.auth.currentUser?.id;
    if (user == null) {
      _user = null;
      _last = null;
      return;
    }
    final now = DateTime.now();
    if (_user == user &&
        _last != null &&
        now.difference(_last!) < const Duration(minutes: 5)) {
      return;
    }
    _user = user;
    _last = now;
    unawaited(
      client.rpc('record_weekly_open').then<void>((_) {}).catchError((
        Object _,
      ) {
        _last = null;
      }),
    );
  }

  void dispose() {
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

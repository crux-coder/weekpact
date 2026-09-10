import 'home/home_backend.dart';

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notifications/notification_service.dart';
import 'notifications/notification_scope.dart';

import 'package:flutter/material.dart';

import 'goals/goals_backend.dart';

import 'auth/auth_backend.dart';
import 'auth/auth_gate.dart';
import 'crew/crew_backend.dart';
import 'invites/invite_links.dart';
import 'theme/weekpact_theme.dart';
import 'theme/theme_preference.dart';

class WeekPactApp extends StatefulWidget {
  const WeekPactApp({
    super.key,
    required this.authBackend,
    this.notifications,
    this.initialThemeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.crewBackend = const MissingCrewBackend(),
    this.goalsBackend = const MissingGoalsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.inviteLinkSource = const NoopInviteLinkSource(),
  });

  final ThemeMode initialThemeMode;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;
  final AuthBackend authBackend;
  final NotificationService? notifications;
  final CrewBackend crewBackend;
  final GoalsBackend goalsBackend;
  final HomeBackend homeBackend;
  final InviteLinkSource inviteLinkSource;

  @override
  State<WeekPactApp> createState() => _WeekPactAppState();
}

class _WeekPactAppState extends State<WeekPactApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode = widget.initialThemeMode;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = widget.notifications;
    if (notifications != null) {
      _foregroundSubscription = notifications.foregroundMessages.listen((
        message,
      ) {
        // iOS displays its native foreground banner. Android uses an in-app
        // banner while open, and the OS notification tray while backgrounded.
        if (defaultTargetPlatform != TargetPlatform.android) return;
        final notification = message.notification;
        if (notification == null) return;
        final text = [
          notification.title,
          notification.body,
        ].whereType<String>().where((part) => part.isNotEmpty).join('\n');
        if (text.isNotEmpty) {
          _messenger.currentState?.showSnackBar(SnackBar(content: Text(text)));
        }
      });
      unawaited(notifications.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final notifications = widget.notifications;
      if (notifications != null) unawaited(notifications.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_foregroundSubscription?.cancel());
    widget.notifications?.dispose();
    super.dispose();
  }

  void _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    try {
      await widget.onThemeModeChanged?.call(mode);
    } catch (error) {
      debugPrint('Could not persist theme preference: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemePreference(
      mode: _themeMode,
      onChanged: _setThemeMode,
      child: MaterialApp(
        scaffoldMessengerKey: _messenger,
        debugShowCheckedModeBanner: false,
        title: 'WeekPact',
        theme: WeekPactTheme.light,
        darkTheme: WeekPactTheme.dark,
        themeMode: _themeMode,
        builder: (context, child) {
          final content = WeekPactBackground(
            child: child ?? const SizedBox.shrink(),
          );
          final notifications = widget.notifications;
          return notifications == null
              ? content
              : NotificationScope(service: notifications, child: content);
        },
        home: AuthGate(
          authBackend: widget.authBackend,
          crewBackend: widget.crewBackend,
          goalsBackend: widget.goalsBackend,
          homeBackend: widget.homeBackend,
          inviteLinkSource: widget.inviteLinkSource,
        ),
      ),
    );
  }
}

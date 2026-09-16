import 'home/photo_check_in_sheet.dart';
import 'home/home_backend.dart';

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notifications/notification_service.dart';
import 'notifications/notification_scope.dart';

import 'package:flutter/material.dart';

import 'pacts/pacts_backend.dart';

import 'auth/auth_backend.dart';
import 'auth/auth_gate.dart';
import 'crew/crew_backend.dart';
import 'crew/crew_selection_store.dart';
import 'invites/invite_links.dart';
import 'theme/weekpact_theme.dart';

class WeekPactApp extends StatefulWidget {
  const WeekPactApp({
    super.key,
    required this.authBackend,
    this.notifications,
    this.crewSelectionStore,
    this.crewBackend = const MissingCrewBackend(),
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.captureCheckInPhoto,
    this.inviteLinkSource = const NoopInviteLinkSource(),
  });

  final AuthBackend authBackend;
  final NotificationService? notifications;
  final CrewSelectionStore? crewSelectionStore;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final CheckInPhotoCapture? captureCheckInPhoto;
  final InviteLinkSource inviteLinkSource;

  @override
  State<WeekPactApp> createState() => _WeekPactAppState();
}

class _WeekPactAppState extends State<WeekPactApp> with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      title: 'WeekPact',
      // One theme, regardless of the device's appearance setting.
      theme: WeekPactTheme.dark,
      themeMode: ThemeMode.dark,
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
        crewSelectionStore: widget.crewSelectionStore,
        authBackend: widget.authBackend,
        crewBackend: widget.crewBackend,
        pactsBackend: widget.pactsBackend,
        homeBackend: widget.homeBackend,
        captureCheckInPhoto: widget.captureCheckInPhoto,
        inviteLinkSource: widget.inviteLinkSource,
      ),
    );
  }
}

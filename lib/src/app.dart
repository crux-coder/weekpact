import 'home/photo_check_in_page.dart';
import 'home/home_backend.dart';

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import 'notifications/notification_service.dart';
import 'notifications/push_banner.dart';
import 'notifications/notification_scope.dart';

import 'package:flutter/material.dart';

import 'pacts/pacts_backend.dart';

import 'auth/auth_backend.dart';
import 'auth/auth_gate.dart';
import 'chat/chat_backend.dart';
import 'crew/crew_backend.dart';
import 'crew/crew_selection_store.dart';
import 'home/story_seen_store.dart';
import 'invites/invite_links.dart';
import 'onboarding/onboarding_draft.dart';
import 'subscriptions/subscription_scope.dart';
import 'theme/weekpact_theme.dart';
import 'updates/update_check.dart';
import 'updates/update_prompt.dart';

class WeekPactApp extends StatefulWidget {
  const WeekPactApp({
    super.key,
    required this.authBackend,
    this.notifications,
    this.crewSelectionStore,
    this.storySeenStore,
    this.onboardingDraftStore,
    this.crewBackend = const MissingCrewBackend(),
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.chatBackend = const MissingChatBackend(),
    this.captureCheckInPhoto,
    this.inviteLinkSource = const NoopInviteLinkSource(),
    this.subscriptions,
    this.updates,
  });

  final AuthBackend authBackend;
  final NotificationService? notifications;
  final CrewSelectionStore? crewSelectionStore;
  final StorySeenStore? storySeenStore;

  /// Where a new person's setup answers wait for their account. Null keeps
  /// them for the run of the app.
  final OnboardingDraftStore? onboardingDraftStore;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final ChatBackend chatBackend;
  final CheckInPhotoCapture? captureCheckInPhoto;
  final InviteLinkSource inviteLinkSource;
  final SubscriptionController? subscriptions;

  /// Whether this build is behind the store. Null never checks.
  final UpdateCheck? updates;

  @override
  State<WeekPactApp> createState() => _WeekPactAppState();
}

class _WeekPactAppState extends State<WeekPactApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _banner = GlobalKey<PushBannerHostState>();
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
        // iOS displays its native foreground banner. Android shows nothing
        // over the open app, so it gets an in-app banner that does what the
        // system one would, and the OS tray while backgrounded.
        if (defaultTargetPlatform != TargetPlatform.android) return;
        final notification = message.notification;
        final title = notification?.title ?? '';
        final body = notification?.body;
        if (title.isEmpty && (body == null || body.isEmpty)) return;
        final chat = chatPushCrewId(message) != null;
        _banner.currentState?.show(
          title: title.isEmpty ? body! : title,
          body: title.isEmpty ? null : body,
          icon: chat
              ? HugeIconsStrokeRounded.bubbleChat
              : HugeIconsStrokeRounded.notification02,
          onTap: () => notifications.openInApp(message),
        );
      });
      unawaited(notifications.initialize());
    }
    unawaited(widget.updates?.check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final notifications = widget.notifications;
      if (notifications != null) unawaited(notifications.refresh());
      // A subscription can be cancelled or lapse in the App Store while the
      // app is backgrounded, so re-read entitlements on the way back in.
      unawaited(widget.subscriptions?.refresh());
      // Throttled: a resume within a few hours of the last check is skipped.
      unawaited(widget.updates?.check());
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
        final content = PushBannerHost(
          key: _banner,
          child: WeekPactBackground(child: child ?? const SizedBox.shrink()),
        );
        final notifications = widget.notifications;
        final scoped = notifications == null
            ? content
            : NotificationScope(service: notifications, child: content);
        final subscriptions = widget.subscriptions;
        return subscriptions == null
            ? scoped
            : SubscriptionScope(controller: subscriptions, child: scoped);
      },
      home: _requiredUpdate(
        AuthGate(
          updates: widget.updates,
          crewSelectionStore: widget.crewSelectionStore,
          storySeenStore: widget.storySeenStore,
          onboardingDraftStore: widget.onboardingDraftStore,
          authBackend: widget.authBackend,
          crewBackend: widget.crewBackend,
          pactsBackend: widget.pactsBackend,
          homeBackend: widget.homeBackend,
          chatBackend: widget.chatBackend,
          captureCheckInPhoto: widget.captureCheckInPhoto,
          inviteLinkSource: widget.inviteLinkSource,
        ),
      ),
    );
  }

  Widget _requiredUpdate(Widget child) {
    final updates = widget.updates;
    return updates == null
        ? child
        : UpdatePrompt.required(updates: updates, child: child);
  }
}

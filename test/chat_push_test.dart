import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/home/story_viewer.dart';
import 'package:weekpact/src/notifications/messaging_client.dart';
import 'package:weekpact/src/notifications/notification_scope.dart';
import 'package:weekpact/src/notifications/notification_service.dart';
import 'package:weekpact/src/notifications/push_banner.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/chat_fakes.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

const viewer = 'user-id';

class _Messaging implements MessagingClient {
  final opens = StreamController<RemoteMessage>.broadcast(sync: true);
  RemoteMessage? initial;
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<RemoteMessage> get foregroundMessages => const Stream.empty();
  @override
  Stream<RemoteMessage> get openedMessages => opens.stream;
  @override
  Future<AuthorizationStatus> permission({bool request = false}) async =>
      AuthorizationStatus.notDetermined;
  @override
  Future<bool> isDeviceReady() async => false;
  @override
  Future<String?> getToken() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  Future<void> setAutoInit(bool enabled) async {}
  @override
  Future<RemoteMessage?> initialMessage() async => initial;
}

RemoteMessage chatPush(String crewId) => RemoteMessage(
  messageId: 'push-$crewId',
  data: {'version': '1', 'type': 'chat_message', 'crew_id': crewId},
);

void main() {
  late FakeChatServer server;
  late _Messaging messaging;
  late NotificationService notifications;
  late GlobalKey<PushBannerHostState> banner;

  setUp(() {
    server = FakeChatServer(
      crews: {
        'crew': {viewer, 'other'},
        'owls': {viewer, 'other'},
      },
    );
    messaging = _Messaging();
    banner = GlobalKey<PushBannerHostState>();
    notifications = NotificationService(
      createClient: () async => messaging,
      saveEnabled: (_) async {},
    );
  });

  Future<void> pumpHome(WidgetTester tester) async {
    final pacts = DashboardPacts()
      ..crews = [
        const PactCrew(
          id: 'crew',
          name: 'Early Birds',
          timezone: 'UTC',
          isOwner: true,
        ),
        const PactCrew(
          id: 'owls',
          name: 'Night Owls',
          timezone: 'UTC',
          isOwner: false,
        ),
      ];
    final home = DashboardBackend(pacts: pacts, viewerId: viewer);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => NotificationScope(
          service: notifications,
          child: PushBannerHost(key: banner, child: child!),
        ),
        home: HomePage(
          user: const AuthUser(email: 'person@example.com', id: viewer),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: const MissingCrewBackend(),
          initialCrewId: 'crew',
          pactsBackend: home.pacts,
          homeBackend: home,
          chatBackend: FakeChatBackend(server, viewer),
        ),
      ),
    );
    await tester.pumpUi();
  }

  test(
    'a tapped push is handed over once, and only chat pushes name a crew',
    () async {
      messaging.initial = chatPush('owls');
      await notifications.initialize();
      final taken = notifications.takeOpenedMessage();
      expect(taken?.messageId, 'push-owls');
      expect(notifications.takeOpenedMessage(), isNull);
      expect(chatPushCrewId(taken!), 'owls');
      expect(
        chatPushCrewId(
          const RemoteMessage(data: {'type': 'crew_nudge', 'crew_id': 'owls'}),
        ),
        isNull,
      );
      expect(
        chatPushCrewId(const RemoteMessage(data: {'type': 'chat_message'})),
        isNull,
      );
    },
  );

  testWidgets('a push that launched the app opens Chat on its crew', (
    tester,
  ) async {
    messaging.initial = chatPush('owls');
    await notifications.initialize();
    await pumpHome(tester);

    expect(find.text('Say hi to Night Owls.'), findsOneWidget);
    expect(notifications.takeOpenedMessage(), isNull, reason: 'routed once');
  });

  testWidgets('tapping a push while the app is open switches to that chat', (
    tester,
  ) async {
    await notifications.initialize();
    await pumpHome(tester);
    expect(find.text('Say hi to Night Owls.'), findsNothing);

    // Somewhere deeper than the tabs: the push brings them back to the top.
    unawaited(
      Navigator.of(tester.element(find.byType(HomePage))).push(
        MaterialPageRoute<void>(builder: (_) => const Text('Somewhere else')),
      ),
    );
    await tester.pumpUi();

    messaging.opens.add(chatPush('owls'));
    await tester.pumpUi();
    expect(find.text('Somewhere else'), findsNothing);
    expect(find.text('Say hi to Night Owls.'), findsOneWidget);
  });

  testWidgets('other pushes leave the tabs alone', (tester) async {
    await notifications.initialize();
    await pumpHome(tester);
    messaging.opens.add(
      const RemoteMessage(data: {'type': 'crew_nudge', 'crew_id': 'owls'}),
    );
    await tester.pumpUi();
    expect(find.text('Say hi to Night Owls.'), findsNothing);
  });

  testWidgets('the in-app banner opens the chat it is about when tapped', (
    tester,
  ) async {
    await notifications.initialize();
    await pumpHome(tester);

    banner.currentState!.show(
      title: 'Night Owls',
      body: 'Ana: running late',
      onTap: () => notifications.openInApp(chatPush('owls')),
    );
    await tester.pumpUi();
    expect(find.text('Ana: running late'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('push-banner')));
    await tester.pumpUi();
    expect(find.text('Say hi to Night Owls.'), findsOneWidget);
    expect(find.text('Ana: running late'), findsNothing);
  });

  testWidgets('the in-app banner goes by itself, or when swiped up', (
    tester,
  ) async {
    await notifications.initialize();
    await pumpHome(tester);

    banner.currentState!.show(title: 'Night Owls', body: 'Ana: hello');
    await tester.pumpUi();
    expect(find.text('Ana: hello'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpUi();
    expect(find.text('Ana: hello'), findsNothing);

    banner.currentState!.show(title: 'Night Owls', body: 'Ana: again');
    await tester.pumpUi();
    await tester.fling(
      find.byKey(const ValueKey('push-banner')),
      const Offset(0, -80),
      800,
    );
    await tester.pumpUi();
    expect(find.text('Ana: again'), findsNothing);
    // Nothing was tapped, so nothing was opened.
    expect(find.text('Say hi to Night Owls.'), findsNothing);
  });

  testWidgets('tapping a push about a check-in opens its story', (
    tester,
  ) async {
    await notifications.initialize();
    await pumpHome(tester);
    messaging.opens.add(
      const RemoteMessage(
        data: {
          'version': '1',
          'type': 'check_in_clapped',
          'crew_id': 'crew',
          'pact_id': 'read',
          'check_in_user_id': viewer,
          'check_in_day': '2026-09-09',
        },
      ),
    );
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}

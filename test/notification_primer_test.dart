import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/app.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/notifications/notification_primer_page.dart';
import 'package:weekpact/src/notifications/notification_scope.dart';
import 'package:weekpact/src/notifications/notification_service.dart';
import 'package:weekpact/src/onboarding/crew_setup_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'launch_flows_test.dart' show SharingCrew, SetupPacts;
import 'notifications_test.dart' show FakeMessaging;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart'
    show FakeAuthBackend, FakeCrewBackend, FakeInviteLinkSource, openLogin;

void main() {
  late FakeMessaging client;
  late NotificationService service;
  setUp(() {
    client = FakeMessaging();
    service = NotificationService(
      createClient: () async => client,
      saveEnabled: (_) async {},
      delay: (_) async {},
    );
  });
  tearDown(() async {
    await client.dispose();
  });

  Future<void> showPage(
    WidgetTester tester, {
    required NotificationPrimerReason reason,
    required VoidCallback onDone,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: NotificationScope(
          service: service,
          child: NotificationPrimerPage(
            crewName: 'Early Birds',
            reason: reason,
            onDone: onDone,
          ),
        ),
      ),
    );
    await tester.pumpUi();
  }

  test('the ask is made once, and only where there is a choice to make', () {
    expect(NotificationPrimerPage.wanted(null), isFalse);
    // Not yet initialised: nothing to ask with.
    expect(NotificationPrimerPage.wanted(service), isFalse);
  });

  testWidgets('turning notifications on asks the system once and moves on', (
    tester,
  ) async {
    addTearDown(service.dispose);
    await service.initialize();
    expect(NotificationPrimerPage.wanted(service), isTrue);
    var done = 0;
    await showPage(
      tester,
      reason: NotificationPrimerReason.joined,
      onDone: () => done++,
    );
    expect(find.text('Hear it when Early Birds shows up.'), findsOneWidget);
    await tester.tap(find.text('TURN ON NOTIFICATIONS'));
    await tester.pumpUi();
    expect(client.requests, 1);
    expect(service.enabled, isTrue);
    expect(done, 1);
    expect(NotificationPrimerPage.wanted(service), isFalse);
  });

  testWidgets('not now asks the system nothing, so Account can ask later', (
    tester,
  ) async {
    addTearDown(service.dispose);
    await service.initialize();
    var done = 0;
    await showPage(
      tester,
      reason: NotificationPrimerReason.invited,
      onDone: () => done++,
    );
    expect(find.text('Hear it when they join.'), findsOneWidget);
    await tester.ensureVisible(find.text('NOT NOW'));
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpUi();
    expect(client.requests, 0);
    expect(service.enabled, isFalse);
    expect(done, 1);
    // The system was never asked, so the next moment may ask again.
    expect(NotificationPrimerPage.wanted(service), isTrue);
  });

  testWidgets('a refusal is not asked about twice', (tester) async {
    addTearDown(service.dispose);
    client.requested = AuthorizationStatus.denied;
    await service.initialize();
    await service.enable();
    expect(NotificationPrimerPage.wanted(service), isFalse);
  });

  testWidgets('joining a crew asks, and either answer opens Home', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend()
      ..preview = const CrewInvitePreview(
        crewName: 'Early Birds',
        memberCount: 3,
        ownerName: 'Ada Lovelace',
      );
    addTearDown(auth.dispose);
    // The app owns the service it is given, and disposes it on the way out.
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
        notifications: service,
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?invite=share-token'),
        ),
      ),
    );
    await openLogin(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('LOG IN'));
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(crews.acceptedTokens, ['share-token']);
    expect(find.byType(NotificationPrimerPage), findsOneWidget);
    // Named after the crew the join actually returned, not the preview.
    expect(
      find.text('Hear it when Weekend Warriors shows up.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('TURN ON NOTIFICATIONS'));
    await tester.tap(find.text('TURN ON NOTIFICATIONS'));
    await tester.pumpUi();
    expect(client.requests, 1);
    expect(find.byType(NotificationPrimerPage), findsNothing);
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('without a notification service, joining goes straight to '
      'Home', (tester) async {
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?invite=share-token'),
        ),
      ),
    );
    await openLogin(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('LOG IN'));
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();
    expect(find.byType(NotificationPrimerPage), findsNothing);
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('the setup asks after a link has gone out, and not before', (
    tester,
  ) async {
    addTearDown(service.dispose);
    await service.initialize();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final crews = SharingCrew();
    await crews.createCrew(name: 'Early Birds', timezone: 'UTC');
    final pacts = SetupPacts();
    await pacts.addPact(
      crewId: 'crew',
      title: 'Read',
      frequency: PactFrequency.weekly,
      daysPerWeek: 3,
    );
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.light,
          home: NotificationScope(
            service: service,
            // A fresh page each time; the same tree would keep its step.
            child: CrewSetupPage(
              key: UniqueKey(),
              crewBackend: crews,
              pactsBackend: pacts,
              homeBackend: DashboardBackend(pacts: pacts),
              userId: '',
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(find.text('Step 3 of 4'), findsOneWidget);
    }

    // Nothing sent: nobody to hear from, so no ask.
    await open();
    await tester.ensureVisible(find.text('Continue to first check-in'));
    await tester.tap(find.text('Continue to first check-in'));
    await tester.pumpUi();
    expect(find.byType(NotificationPrimerPage), findsNothing);
    expect(find.text('Step 4 of 4'), findsOneWidget);

    await open();
    await tester.tap(find.text('Copy invite link'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('Continue to first check-in'));
    await tester.tap(find.text('Continue to first check-in'));
    await tester.pumpUi();
    expect(find.byType(NotificationPrimerPage), findsOneWidget);
    expect(find.text('Hear it when they join.'), findsOneWidget);
    await tester.ensureVisible(find.text('NOT NOW'));
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpUi();
    expect(client.requests, 0);
    expect(find.byType(NotificationPrimerPage), findsNothing);
    expect(find.text('Step 4 of 4'), findsOneWidget);
  });
}

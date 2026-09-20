import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/invites/invite_acceptance_page.dart';
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/pro_upgrade.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'multiple_crews_test.dart' show MultipleCrews;
import 'subscription_test.dart' show FakeSubscriptionBackend;
import 'support/pump_ui.dart';

/// What Postgres sends back when `private.enforce_crew_limit` refuses.
PostgrestException get refusal => const PostgrestException(
  message: 'WeekPact Pro is needed to be in more than one crew',
  code: crewLimitCode,
);

/// A crew backend that refuses every join the way the database does.
class LimitedCrews extends MultipleCrews {
  int attempts = 0;
  bool relentsAfterUpgrade = false;
  bool upgraded = false;

  @override
  Future<CrewDetails> acceptInvite(String token) async {
    attempts++;
    if (relentsAfterUpgrade && upgraded)
      return MultipleCrews.details('c', 'Joined');
    throw refusal;
  }

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    attempts++;
    if (relentsAfterUpgrade && upgraded)
      return super.createCrew(name: name, timezone: timezone);
    throw refusal;
  }
}

Future<SubscriptionController> pumpCrewPage(
  WidgetTester tester,
  CrewBackend backend, {
  required bool isPro,
  FakeSubscriptionBackend? store,
}) async {
  final subscriptions = store ?? FakeSubscriptionBackend();
  if (isPro) subscriptions.emit(const ProAccess(active: true, willRenew: true));
  final controller = SubscriptionController(subscriptions);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: SubscriptionScope(
        controller: controller,
        child: Scaffold(
          body: CrewPage(
            backend: backend,
            currentUserEmail: 'owner@example.com',
          ),
        ),
      ),
    ),
  );
  await tester.pumpUi();
  return controller;
}

void main() {
  group('recognising the database refusal', () {
    test('the Postgres error is understood by its code', () {
      expect(isCrewLimitError(refusal), isTrue);
    });
    test('other failures are left alone', () {
      for (final other in <Object>[
        const PostgrestException(message: 'Invite has expired', code: '22023'),
        const PostgrestException(
          message: 'You must be signed in',
          code: '42501',
        ),
        StateError('Supabase is not configured'),
        Exception('offline'),
      ]) {
        expect(isCrewLimitError(other), isFalse, reason: '$other');
      }
    });
  });

  testWidgets('a free account is offered Pro instead of the new-crew form', (
    tester,
  ) async {
    final backend = MultipleCrews();
    await pumpCrewPage(tester, backend, isPro: false);
    await tester.tap(find.byTooltip('Create another crew'));
    await tester.pumpUi();

    expect(find.text('One crew on the free plan'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsNothing);
    expect(backend.entries.length, 2, reason: 'nothing was created');
  });

  testWidgets('declining the offer leaves the form closed', (tester) async {
    final backend = MultipleCrews();
    await pumpCrewPage(tester, backend, isPro: false);
    await tester.tap(find.byTooltip('Create another crew'));
    await tester.pumpUi();
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpUi();

    expect(find.text('One crew on the free plan'), findsNothing);
    expect(find.text('CREATE CREW'), findsNothing);
  });

  testWidgets('taking the offer opens the paywall, and buying opens the form', (
    tester,
  ) async {
    final store = FakeSubscriptionBackend();
    await pumpCrewPage(tester, MultipleCrews(), isPro: false, store: store);
    await tester.tap(find.byTooltip('Create another crew'));
    await tester.pumpUi();
    await tester.tap(find.text('SEE WEEKPACT PRO'));
    await tester.pumpUi();
    expect(find.byType(PaywallPage), findsOneWidget);

    await tester.ensureVisible(find.text('START WEEKPACT PRO'));
    await tester.tap(find.text('START WEEKPACT PRO'));
    await tester.pumpUi();

    expect(store.purchases, 1);
    expect(find.byType(PaywallPage), findsNothing);
    expect(find.text('CREATE CREW'), findsOneWidget);
  });

  testWidgets('backing out of the paywall leaves the form closed', (
    tester,
  ) async {
    final store = FakeSubscriptionBackend();
    await pumpCrewPage(tester, MultipleCrews(), isPro: false, store: store);
    await tester.tap(find.byTooltip('Create another crew'));
    await tester.pumpUi();
    await tester.tap(find.text('SEE WEEKPACT PRO'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('paywall-close')));
    await tester.pumpUi();

    expect(store.purchases, 0);
    expect(find.byType(PaywallPage), findsNothing);
    expect(find.text('CREATE CREW'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the offer fits a 390pt phone at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SubscriptionScope(
            controller: SubscriptionController(FakeSubscriptionBackend()),
            child: Scaffold(
              body: CrewPage(
                backend: MultipleCrews(),
                currentUserEmail: 'owner@example.com',
              ),
            ),
          ),
        ),
      );
      await tester.pumpUi();
      await tester.tap(find.byTooltip('Create another crew'));
      await tester.pumpUi();

      expect(find.text('One crew on the free plan'), findsOneWidget);
      // Both actions stay reachable; the dialog scrolls rather than clipping.
      await tester.ensureVisible(find.text('NOT NOW'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a subscriber goes straight to the form', (tester) async {
    await pumpCrewPage(tester, MultipleCrews(), isPro: true);
    await tester.tap(find.byTooltip('Create another crew'));
    await tester.pumpUi();

    expect(find.text('One crew on the free plan'), findsNothing);
    expect(find.text('CREATE CREW'), findsOneWidget);
  });

  testWidgets(
    'the database has the last word when the client thinks it is Pro',
    (tester) async {
      // Entitlements lapse between opening the form and submitting it, so a
      // client that believes it has Pro still has to handle the refusal.
      final backend = LimitedCrews();
      await pumpCrewPage(tester, backend, isPro: true);
      await tester.tap(find.byTooltip('Create another crew'));
      await tester.pumpUi();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Weekend Walkers',
      );
      await tester.ensureVisible(find.text('CREATE CREW'));
      await tester.tap(find.text('CREATE CREW'));
      await tester.pumpUi();

      expect(backend.attempts, 1);
      expect(find.text('One crew on the free plan'), findsOneWidget);
    },
  );

  testWidgets('a refused invite offers Pro, and upgrading joins the crew', (
    tester,
  ) async {
    final backend = LimitedCrews()..relentsAfterUpgrade = true;
    final store = FakeSubscriptionBackend();
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: SubscriptionScope(
          controller: SubscriptionController(store),
          child: InviteAcceptancePage(
            email: 'friend@example.com',
            token: 'a' * 64,
            crewBackend: backend,
            onFinished: () => finished = true,
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(find.text('One crew on the free plan'), findsOneWidget);
    backend.upgraded = true;
    await tester.tap(find.text('SEE WEEKPACT PRO'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('START WEEKPACT PRO'));
    await tester.tap(find.text('START WEEKPACT PRO'));
    await tester.pumpUi();

    expect(store.purchases, 1);
    expect(
      backend.attempts,
      2,
      reason: 'the invite is retried after upgrading',
    );
    expect(finished, isTrue);
  });
}

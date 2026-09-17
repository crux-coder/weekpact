import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_page.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'subscription_test.dart' show FakeSubscriptionBackend;
import 'support/pump_ui.dart';

const appleManagement = 'https://apps.apple.com/account/subscriptions';

ProAccess renewing({
  String product = 'yearly',
  String? url = appleManagement,
}) => ProAccess(
  active: true,
  willRenew: true,
  productIdentifier: product,
  expiresAt: DateTime(2027, 3, 4),
  managementUrl: url,
);

Future<FakeSubscriptionBackend> pumpPage(
  WidgetTester tester, {
  required ProAccess access,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = FakeSubscriptionBackend(initial: access);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: SubscriptionScope(
        controller: SubscriptionController(store),
        child: const SubscriptionPage(),
      ),
    ),
  );
  await tester.pumpUi();
  return store;
}

void main() {
  testWidgets('a renewing subscription shows its plan and next charge', (
    tester,
  ) async {
    await pumpPage(tester, access: renewing());

    expect(find.text('Yearly plan'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Renews automatically on Mar 4, 2027.'), findsOneWidget);
  });

  testWidgets(
    'a cancelled subscription says when it ends, not that it is gone',
    (tester) async {
      await pumpPage(
        tester,
        access: ProAccess(
          active: true,
          willRenew: false,
          productIdentifier: 'monthly',
          expiresAt: DateTime(2027, 3, 4),
          managementUrl: appleManagement,
        ),
      );

      expect(find.text('Monthly plan'), findsOneWidget);
      expect(find.text('ENDING'), findsOneWidget);
      expect(
        find.text('Cancelled. Pro stays active until Mar 4, 2027.'),
        findsOneWidget,
      );
      // Cancelling twice is not a thing to offer.
      expect(find.text('Cancel subscription'), findsOneWidget);
      await tester.tap(find.text('Cancel subscription'));
      await tester.pumpUi();
      expect(find.text('Cancel in the App Store'), findsNothing);
    },
  );

  testWidgets('cancelling explains that Apple owns it before leaving the app', (
    tester,
  ) async {
    await pumpPage(tester, access: renewing());
    await tester.ensureVisible(find.text('Cancel subscription'));
    await tester.tap(find.text('Cancel subscription'));
    await tester.pumpUi();

    expect(find.text('Cancel in the App Store'), findsOneWidget);
    expect(find.textContaining('Apple handles cancellation'), findsOneWidget);
    // Nobody loses what they paid for by cancelling.
    expect(
      find.textContaining('until the date you have already paid'),
      findsOneWidget,
    );
    expect(find.text('OPEN APP STORE'), findsOneWidget);

    await tester.tap(find.text('NEVER MIND'));
    await tester.pumpUi();
    expect(find.text('Cancel in the App Store'), findsNothing);
  });

  testWidgets('a subscription the store cannot manage says so plainly', (
    tester,
  ) async {
    // Test Store purchases and promotional grants have no management screen.
    await pumpPage(tester, access: renewing(url: null));
    await tester.ensureVisible(find.text('Cancel subscription'));
    await tester.tap(find.text('Cancel subscription'));
    await tester.pumpUi();

    expect(find.text('Not managed by the App Store'), findsOneWidget);
    expect(find.text('OPEN APP STORE'), findsNothing);
  });

  testWidgets('changing plan opens the paywall even though they have Pro', (
    tester,
  ) async {
    await pumpPage(tester, access: renewing());
    await tester.ensureVisible(find.text('Switch to monthly'));
    await tester.tap(find.text('Switch to monthly'));
    await tester.pumpUi();

    expect(find.byType(PaywallPage), findsOneWidget);
  });

  testWidgets('the switch offers the plan they are not on', (tester) async {
    await pumpPage(tester, access: renewing(product: 'monthly'));
    expect(find.text('Switch to yearly'), findsOneWidget);
  });

  testWidgets('every row says something the title does not', (tester) async {
    await pumpPage(tester, access: renewing());

    for (final (title, body) in const [
      ('Switch to monthly', 'Pay month to month instead.'),
      // The reassurance, with the real date rather than the mechanism.
      ('Cancel subscription', 'You keep Pro until Mar 4, 2027.'),
      ('Terms', 'The legal bit.'),
      ('Privacy', 'What we keep, and never sell.'),
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.text(body), findsOneWidget, reason: body);
    }
  });

  testWidgets('a monthly subscriber is told what the year saves', (
    tester,
  ) async {
    await pumpPage(tester, access: renewing(product: 'monthly'));

    // 24.99 against 12 x 3.99, from the offering rather than a written-in
    // number that would go stale the moment prices change.
    expect(find.text('Save 48% paying once a year.'), findsOneWidget);
  });

  testWidgets('with no offering the switch still reads sensibly', (
    tester,
  ) async {
    final store = FakeSubscriptionBackend(
      initial: renewing(product: 'monthly'),
    )..offer = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: SubscriptionScope(
          controller: SubscriptionController(store),
          child: const SubscriptionPage(),
        ),
      ),
    );
    await tester.pumpUi();

    expect(find.text('Pay once a year instead.'), findsOneWidget);
  });

  testWidgets('managing is those choices and no others', (tester) async {
    await pumpPage(tester, access: renewing());

    // Restoring belongs on the paywall: this page is only reachable with Pro,
    // so there is nothing here to restore. Refunds go through Apple.
    expect(find.text('Restore purchases'), findsNothing);
    expect(find.text('Request a refund'), findsNothing);
  });

  testWidgets('a sandbox purchase is labelled as one', (tester) async {
    await pumpPage(
      tester,
      access: ProAccess(
        active: true,
        willRenew: true,
        productIdentifier: 'yearly',
        expiresAt: DateTime(2027, 3, 4),
        managementUrl: appleManagement,
        sandbox: true,
      ),
    );

    expect(find.textContaining('not a real charge'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the page fits a 390pt phone at text scale $scale', (
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
            controller: SubscriptionController(
              FakeSubscriptionBackend(initial: renewing()),
            ),
            child: const SubscriptionPage(),
          ),
        ),
      );
      await tester.pumpUi();

      await tester.ensureVisible(find.text('Privacy'));
      expect(tester.takeException(), isNull);
    });
  }
}

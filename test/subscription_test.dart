import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/subscription_page.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_control.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

class FakeSubscriptionBackend implements SubscriptionBackend {
  FakeSubscriptionBackend({ProAccess initial = ProAccess.locked})
    : _access = initial;

  final _controller = StreamController<ProAccess>.broadcast();
  ProAccess _access;

  int paywalls = 0;
  int purchases = 0;
  final purchasedPlans = <String>[];
  ProOffer? offer = const ProOffer([
    ProPlan(
      id: '\$rc_annual',
      period: PlanPeriod.yearly,
      price: '\$24.99',
      amount: 24.99,
      pricePerMonth: '\$2.08',
    ),
    ProPlan(
      id: '\$rc_monthly',
      period: PlanPeriod.monthly,
      price: '\$3.99',
      amount: 3.99,
    ),
  ]);
  SubscriptionFailure? purchaseFailure;
  PaywallOutcome paywallOutcome = PaywallOutcome.cancelled;
  int customerCenters = 0;
  int restores = 0;
  final identified = <String?>[];
  SubscriptionFailure? customerCenterFailure;

  void emit(ProAccess next) {
    _access = next;
    _controller.add(next);
  }

  @override
  ProAccess get access => _access;
  @override
  Stream<ProAccess> get accessChanges => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> identify(String userId) async => identified.add(userId);
  @override
  Future<void> forgetUser() async => identified.add(null);
  @override
  Future<ProAccess> refresh() async => _access;

  @override
  Future<ProOffer?> loadOffer() async => offer;

  @override
  Future<ProAccess> purchase(ProPlan plan) async {
    purchases++;
    purchasedPlans.add(plan.id);
    final failure = purchaseFailure;
    if (failure != null) throw failure;
    emit(const ProAccess(active: true, willRenew: true));
    return _access;
  }

  @override
  Future<PaywallOutcome> presentPaywall({bool onlyIfLocked = true}) async {
    paywalls++;
    return paywallOutcome;
  }

  @override
  Future<void> presentCustomerCenter() async {
    customerCenters++;
    final failure = customerCenterFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<ProAccess> restore() async {
    restores++;
    return _access;
  }

  @override
  Future<void> dispose() async => _controller.close();
}

Future<void> pumpControl(
  WidgetTester tester,
  SubscriptionController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: SubscriptionScope(
        controller: controller,
        child: const Scaffold(body: SubscriptionControl()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('locked access is the default and is not renewing', () {
    expect(ProAccess.locked.active, isFalse);
    expect(ProAccess.locked.cancelled, isFalse);
  });

  test('an active entitlement that will not renew reads as cancelled', () {
    const access = ProAccess(active: true, willRenew: false);
    expect(access.cancelled, isTrue);
    const renewing = ProAccess(active: true, willRenew: true);
    expect(renewing.cancelled, isFalse);
  });

  test('the yearly product is recognised from its identifier', () {
    const yearly = ProAccess(active: true, productIdentifier: 'yearly');
    const monthly = ProAccess(active: true, productIdentifier: 'monthly');
    expect(yearly.isYearly, isTrue);
    expect(monthly.isYearly, isFalse);
  });

  test('the controller follows entitlement changes from the store', () async {
    final backend = FakeSubscriptionBackend();
    final controller = SubscriptionController(backend);
    addTearDown(controller.dispose);

    expect(controller.isPro, isFalse);
    var notified = 0;
    controller.addListener(() => notified++);

    backend.emit(const ProAccess(active: true, willRenew: true));
    await Future<void>.delayed(Duration.zero);

    expect(controller.isPro, isTrue);
    expect(notified, 1);

    // An identical value must not churn the widget tree.
    backend.emit(const ProAccess(active: true, willRenew: true));
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
  });

  test(
    'the missing backend keeps everything locked without throwing',
    () async {
      const backend = MissingSubscriptionBackend();
      expect(backend.access.active, isFalse);
      expect(await backend.refresh(), ProAccess.locked);
      expect(await backend.presentPaywall(), PaywallOutcome.failed);
      await expectLater(backend.restore(), throwsA(isA<SubscriptionFailure>()));
    },
  );

  testWidgets('a locked account is offered the paywall', (tester) async {
    final backend = FakeSubscriptionBackend();
    final controller = SubscriptionController(backend);
    addTearDown(controller.dispose);
    await pumpControl(tester, controller);

    expect(find.text('Upgrade to Pro'), findsOneWidget);
    expect(find.text('WeekPact Pro'), findsNothing);

    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pumpAndSettle();

    // The app's own paywall, not the store-hosted one.
    expect(find.byType(PaywallPage), findsOneWidget);
    expect(find.text('START WEEKPACT PRO'), findsOneWidget);
    expect(backend.paywalls, 0);
    expect(backend.customerCenters, 0);
  });

  testWidgets('a subscriber is sent to the app’s own subscription page', (
    tester,
  ) async {
    final backend = FakeSubscriptionBackend(
      initial: ProAccess(
        active: true,
        willRenew: true,
        productIdentifier: 'yearly',
        expiresAt: DateTime(2027, 3, 4),
        managementUrl: 'https://apps.apple.com/account/subscriptions',
      ),
    );
    final controller = SubscriptionController(backend);
    addTearDown(controller.dispose);
    await pumpControl(tester, controller);

    expect(find.text('WeekPact Pro'), findsOneWidget);
    expect(find.textContaining('Renews Mar 4, 2027'), findsOneWidget);

    await tester.tap(find.text('WeekPact Pro'));
    await tester.pumpAndSettle();

    expect(find.byType(SubscriptionPage), findsOneWidget);
    // The store-hosted Customer Center is no longer how this is reached.
    expect(backend.customerCenters, 0);
    expect(backend.paywalls, 0);
  });

  testWidgets('the tile disappears when no subscription scope is present', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: const Scaffold(body: SubscriptionControl()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Pro'), findsNothing);
  });

  testWidgets('context.isPro reflects the scope', (tester) async {
    final backend = FakeSubscriptionBackend(
      initial: const ProAccess(active: true, willRenew: true),
    );
    final controller = SubscriptionController(backend);
    addTearDown(controller.dispose);

    late bool seen;
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              seen = context.isPro;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen, isTrue);
  });
}

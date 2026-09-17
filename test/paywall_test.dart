import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show PurchasesErrorCode;
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'subscription_test.dart' show FakeSubscriptionBackend;
import 'support/pump_ui.dart';

Future<void> pumpPaywall(
  WidgetTester tester,
  FakeSubscriptionBackend store,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: SubscriptionScope(
        controller: SubscriptionController(store),
        child: const PaywallPage(),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  group('restating a yearly price per month', () {
    test('keeps the store’s own currency and separators', () {
      expect(perMonth(r'$24.99', 24.99), r'$2.08');
      expect(perMonth('24,99 €', 24.99), '2,08 €');
      expect(perMonth('£24.00', 24.00), '£2.00');
    });
    test('handles a currency without decimals', () {
      expect(perMonth('¥2400', 2400), '¥200');
    });
    test('declines anything it cannot rewrite safely', () {
      // Grouped thousands: the first separator is not the decimal one.
      expect(perMonth('1.299,00 kr', 1299), isNull);
      expect(perMonth('Free', 0), isNull);
      expect(perMonth(r'$24.99', 0), isNull);
    });
  });

  group('what a store failure says', () {
    test('a declined payment names the payment method', () {
      final failure = failureFor(PurchasesErrorCode.purchaseInvalidError);
      expect(failure.message, contains('could not take that payment'));
      expect(failure.message, contains('payment method'));
      expect(failure.recoverable, isTrue);
    });

    test('a cancellation is not dressed up as an error', () {
      expect(
        failureFor(PurchasesErrorCode.purchaseCancelledError).message,
        'Purchase cancelled.',
      );
    });

    test('what cannot be retried says so', () {
      for (final code in [
        PurchasesErrorCode.purchaseNotAllowedError,
        PurchasesErrorCode.receiptAlreadyInUseError,
        PurchasesErrorCode.configurationError,
        PurchasesErrorCode.productNotAvailableForPurchaseError,
        PurchasesErrorCode.ineligibleError,
      ]) {
        expect(failureFor(code).recoverable, isFalse, reason: code.name);
      }
    });

    test('a simulated Test Store failure is never mistaken for a real one', () {
      final failure = failureFor(
        PurchasesErrorCode.testStoreSimulatedPurchaseError,
      );
      expect(failure.message, contains('Simulated'));
    });

    test('every code a person can hit is explained, not generic', () {
      // The codes that reach someone mid-purchase or mid-restore. Each has to
      // say something they can act on rather than fall through.
      const explained = [
        PurchasesErrorCode.purchaseCancelledError,
        PurchasesErrorCode.purchaseInvalidError,
        PurchasesErrorCode.paymentPendingError,
        PurchasesErrorCode.purchaseNotAllowedError,
        PurchasesErrorCode.insufficientPermissionsError,
        PurchasesErrorCode.productAlreadyPurchasedError,
        PurchasesErrorCode.receiptAlreadyInUseError,
        PurchasesErrorCode.receiptInUseByOtherSubscriberError,
        PurchasesErrorCode.ineligibleError,
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.offlineConnectionError,
        PurchasesErrorCode.storeProblemError,
        PurchasesErrorCode.unknownBackendError,
        PurchasesErrorCode.unexpectedBackendResponseError,
        PurchasesErrorCode.invalidReceiptError,
        PurchasesErrorCode.missingReceiptFileError,
        PurchasesErrorCode.operationAlreadyInProgressError,
        PurchasesErrorCode.productNotAvailableForPurchaseError,
        PurchasesErrorCode.configurationError,
        PurchasesErrorCode.invalidCredentialsError,
        PurchasesErrorCode.invalidAppleSubscriptionKeyError,
        PurchasesErrorCode.unsupportedError,
        PurchasesErrorCode.testStoreSimulatedPurchaseError,
      ];
      for (final code in explained) {
        final failure = failureFor(code);
        expect(
          failure.message,
          isNot('Something went wrong. Please try again.'),
          reason: code.name,
        );
        expect(failure.code, isNull, reason: code.name);
      }
    });

    test('an unmapped code still carries its name for diagnosis', () {
      final failure = failureFor(PurchasesErrorCode.unknownError);
      expect(failure.message, 'Something went wrong. Please try again.');
      expect(failure.code, 'unknownError');
      expect(failure.toString(), contains('unknownError'));
    });
  });

  testWidgets('plans come from the store, with the saving worked out', (
    tester,
  ) async {
    await pumpPaywall(tester, FakeSubscriptionBackend());

    expect(find.text(r'$24.99'), findsOneWidget);
    expect(find.text(r'$3.99'), findsOneWidget);
    expect(find.text(r'$2.08 / month'), findsOneWidget);
    // 24.99 against 12 x 3.99 is 48%.
    expect(find.text('SAVE 48%'), findsOneWidget);
  });

  testWidgets('the yearly plan is what continuing buys', (tester) async {
    final store = FakeSubscriptionBackend();
    await pumpPaywall(tester, store);
    await tester.ensureVisible(find.text('START WEEKPACT PRO'));
    await tester.tap(find.text('START WEEKPACT PRO'));
    await tester.pumpUi();

    expect(store.purchasedPlans, [r'$rc_annual']);
  });

  testWidgets('picking monthly buys monthly', (tester) async {
    final store = FakeSubscriptionBackend();
    await pumpPaywall(tester, store);
    await tester.tap(find.text('1 MONTH'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('START WEEKPACT PRO'));
    await tester.tap(find.text('START WEEKPACT PRO'));
    await tester.pumpUi();

    expect(store.purchasedPlans, [r'$rc_monthly']);
  });

  testWidgets('a failed purchase is explained and the paywall stays', (
    tester,
  ) async {
    final store = FakeSubscriptionBackend()
      ..purchaseFailure = const SubscriptionFailure(
        'The App Store is having trouble. Try again in a moment.',
      );
    await pumpPaywall(tester, store);
    await tester.ensureVisible(find.text('START WEEKPACT PRO'));
    await tester.tap(find.text('START WEEKPACT PRO'));
    await tester.pumpUi();

    expect(
      find.text('The App Store is having trouble. Try again in a moment.'),
      findsOneWidget,
    );
    expect(find.byType(PaywallPage), findsOneWidget);
  });

  testWidgets('a restore with nothing to restore says so', (tester) async {
    final store = FakeSubscriptionBackend();
    await pumpPaywall(tester, store);
    await tester.ensureVisible(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpUi();

    expect(store.restores, 1);
    expect(
      find.text('No previous purchase found on this Apple ID.'),
      findsOneWidget,
    );
  });

  testWidgets('with no offering, plans are unavailable but restore is not', (
    tester,
  ) async {
    final store = FakeSubscriptionBackend()..offer = null;
    await pumpPaywall(tester, store);

    expect(find.textContaining('Plans aren’t available'), findsOneWidget);
    // Nothing to buy, so no purchase button — but someone who already paid
    // must still be able to get their entitlement back.
    expect(find.text('START WEEKPACT PRO'), findsNothing);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('an empty offering is treated as none at all', (tester) async {
    final store = FakeSubscriptionBackend()..offer = const ProOffer([]);
    await pumpPaywall(tester, store);

    expect(find.textContaining('Plans aren’t available'), findsOneWidget);
    expect(find.text('START WEEKPACT PRO'), findsNothing);
  });

  testWidgets('Apple’s required links are all present', (tester) async {
    await pumpPaywall(tester, FakeSubscriptionBackend());

    for (final link in ['Restore', 'Terms', 'Privacy']) {
      expect(find.text(link), findsOneWidget, reason: link);
    }
    // Duration and price per period, which Apple also requires.
    expect(find.text('12 MONTHS'), findsOneWidget);
    expect(find.text('1 MONTH'), findsOneWidget);
    expect(find.text('billed monthly'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the paywall fits a 390pt phone at text scale $scale', (
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SubscriptionScope(
            controller: SubscriptionController(FakeSubscriptionBackend()),
            child: const PaywallPage(),
          ),
        ),
      );
      await tester.pumpUi();

      await tester.ensureVisible(find.text('START WEEKPACT PRO'));
      await tester.ensureVisible(find.text('Privacy'));
      expect(tester.takeException(), isNull);
    });
  }
}

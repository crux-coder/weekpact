import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Entitlement identifier configured in the RevenueCat dashboard. Both the
/// monthly and yearly products attach to this single entitlement, so adding
/// Google Play later is dashboard configuration rather than an app change.
const proEntitlement = 'weekpact_pro';

/// Product identifiers inside the WeekPact subscription group.
const monthlyProduct = 'monthly';
const yearlyProduct = 'yearly';

/// What the app knows about the signed-in account's Pro access.
///
/// Deliberately free of RevenueCat types so widgets, tests and any later
/// server-side check all speak the same vocabulary.
@immutable
class ProAccess {
  const ProAccess({
    this.active = false,
    this.willRenew = false,
    this.expiresAt,
    this.productIdentifier,
    this.managementUrl,
    this.sandbox = false,
  });

  /// The locked state, used before the first customer info arrives.
  static const locked = ProAccess();

  final bool active;
  final bool willRenew;
  final DateTime? expiresAt;
  final String? productIdentifier;

  /// Where the store manages this subscription. Apple gives no way to cancel
  /// from inside an app, so cancelling means sending someone here.
  ///
  /// Null when the store has no such screen, which is the case for Test Store
  /// purchases and for access granted by a promotion.
  final String? managementUrl;
  final bool sandbox;

  /// Whether the store can show a manage-subscription screen for this
  /// purchase, which is what makes cancelling reachable.
  bool get manageable => (managementUrl ?? '').isNotEmpty;

  /// Active but not renewing: the subscription runs out at [expiresAt].
  bool get cancelled => active && !willRenew;

  bool get isYearly => productIdentifier?.contains(yearlyProduct) ?? false;

  @override
  bool operator ==(Object other) =>
      other is ProAccess &&
      other.active == active &&
      other.willRenew == willRenew &&
      other.expiresAt == expiresAt &&
      other.productIdentifier == productIdentifier &&
      other.managementUrl == managementUrl &&
      other.sandbox == sandbox;

  @override
  int get hashCode => Object.hash(
    active,
    willRenew,
    expiresAt,
    productIdentifier,
    managementUrl,
    sandbox,
  );
}

/// The outcome of showing a paywall, with cancellation kept distinct from
/// failure so callers do not report an error when someone simply backs out.
enum PaywallOutcome { purchased, restored, cancelled, alreadyPro, failed }

/// How often a plan bills. Drives the paywall's wording, never the purchase.
enum PlanPeriod { monthly, yearly }

/// One buyable plan, as the paywall needs to render it.
///
/// [id] is the package identifier and is opaque to the UI: it goes back to the
/// backend to buy, so no RevenueCat type has to cross this interface.
@immutable
class ProPlan {
  const ProPlan({
    required this.id,
    required this.period,
    required this.price,
    required this.amount,
    this.pricePerMonth,
  });

  final String id;
  final PlanPeriod period;

  /// Already localized by the store — currency, symbol placement and
  /// separators are the device's, and must never be rebuilt by hand.
  final String price;
  final double amount;

  /// A yearly price restated per month, or null when it could not be derived
  /// from the store's own string.
  final String? pricePerMonth;
}

/// The plans currently on sale.
@immutable
class ProOffer {
  const ProOffer(this.plans);

  final List<ProPlan> plans;

  ProPlan? _of(PlanPeriod period) =>
      plans.where((plan) => plan.period == period).firstOrNull;

  ProPlan? get yearly => _of(PlanPeriod.yearly);
  ProPlan? get monthly => _of(PlanPeriod.monthly);
  bool get isEmpty => plans.isEmpty;

  /// Whole-percent saving of the yearly plan against twelve monthly ones, or
  /// null when both plans are not priced in a way that can be compared.
  int? get yearlySaving {
    final year = yearly, month = monthly;
    if (year == null || month == null) return null;
    final full = month.amount * 12;
    if (full <= 0 || year.amount >= full) return null;
    return ((1 - year.amount / full) * 100).round();
  }
}

/// Raised for purchase and restore failures that are worth showing to someone.
/// Cancellations never reach this.
class SubscriptionFailure implements Exception {
  const SubscriptionFailure(this.message, {this.recoverable = true, this.code});
  final String message;
  final bool recoverable;

  /// The store's own name for what went wrong. Never shown in a release
  /// build; it exists so an unmapped failure can be identified rather than
  /// disappearing behind a generic sentence.
  final String? code;

  /// What to put in front of someone: the sentence alone in a release build,
  /// with the store's code appended while debugging.
  String get display => kDebugMode ? toString() : message;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

abstract interface class SubscriptionBackend {
  /// The most recent known access, available synchronously for the first frame.
  ProAccess get access;

  /// Emits whenever entitlements change, including renewals and expirations
  /// that happen while the app is open.
  Stream<ProAccess> get accessChanges;

  /// Configures the store connection. Safe to call once at startup.
  Future<void> start();

  /// Ties purchases to a signed-in account so entitlements follow the person
  /// across devices and reinstalls.
  Future<void> identify(String userId);

  /// Returns to an anonymous identity after signing out.
  Future<void> forgetUser();

  /// Re-reads entitlements from the store.
  Future<ProAccess> refresh();

  /// The plans on sale, or null when the store has no offering configured.
  /// Never throws: the paywall shows its unavailable state instead.
  Future<ProOffer?> loadOffer();

  /// Buys [plan]. Throws [SubscriptionFailure] for anything worth showing,
  /// including cancellation, which callers separate by its own message.
  Future<ProAccess> purchase(ProPlan plan);

  /// Shows the RevenueCat-hosted paywall. The app draws its own, so this is
  /// kept only as a fallback when the dashboard should own the design.
  Future<PaywallOutcome> presentPaywall({bool onlyIfLocked = true});

  /// Shows the RevenueCat Customer Center. The app manages subscriptions on
  /// its own page, so this is kept only as a fallback.
  Future<void> presentCustomerCenter();

  /// Restores purchases made with the same Apple ID.
  Future<ProAccess> restore();

  Future<void> dispose();
}

class RevenueCatSubscriptionBackend implements SubscriptionBackend {
  RevenueCatSubscriptionBackend({
    required this.apiKey,
    this.debugLogging = kDebugMode,
  });

  final String apiKey;
  final bool debugLogging;

  final _controller = StreamController<ProAccess>.broadcast();
  ProAccess _access = ProAccess.locked;
  Map<String, Package> _packages = const {};
  bool _started = false;
  void Function(CustomerInfo)? _listener;

  @override
  ProAccess get access => _access;

  @override
  Stream<ProAccess> get accessChanges => _controller.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (debugLogging) await Purchases.setLogLevel(LogLevel.debug);

    // Configure anonymously; identify() attaches the Supabase user once known.
    // Configuring with a user id we do not have yet would create an alias that
    // later has to be merged.
    await Purchases.configure(PurchasesConfiguration(apiKey));

    // Renewals, expirations and purchases made outside the app all arrive here.
    _listener = (info) => _publish(_read(info));
    Purchases.addCustomerInfoUpdateListener(_listener!);
    await refresh();
  }

  @override
  Future<void> identify(String userId) async {
    if (!_started || userId.isEmpty) return;
    try {
      final result = await Purchases.logIn(userId);
      _publish(_read(result.customerInfo));
    } on PlatformException catch (error) {
      // A failed identify must not block sign-in; entitlements stay as they are
      // and the next refresh retries.
      _report('identify', error);
    }
  }

  @override
  Future<void> forgetUser() async {
    if (!_started) return;
    try {
      final info = await Purchases.logOut();
      _publish(_read(info));
    } on PlatformException catch (error) {
      _report('forgetUser', error);
      _publish(ProAccess.locked);
    }
  }

  @override
  Future<ProAccess> refresh() async {
    if (!_started) return _access;
    try {
      final info = await Purchases.getCustomerInfo();
      return _publish(_read(info));
    } on PlatformException catch (error) {
      // Offline or a store hiccup. Keep the last known access rather than
      // locking someone out of features they paid for.
      _report('refresh', error);
      return _access;
    }
  }

  @override
  Future<ProOffer?> loadOffer() async {
    if (!_started) return null;
    try {
      final offering = (await Purchases.getOfferings()).current;
      if (offering == null) return null;
      _packages = {
        for (final package in offering.availablePackages)
          package.identifier: package,
      };
      final plans = <ProPlan>[];
      for (final package in offering.availablePackages) {
        final period = _periodOf(package);
        if (period == null) continue;
        final product = package.storeProduct;
        plans.add(
          ProPlan(
            id: package.identifier,
            period: period,
            price: product.priceString,
            amount: product.price,
            pricePerMonth: period == PlanPeriod.yearly
                ? perMonth(product.priceString, product.price)
                : null,
          ),
        );
      }
      // Yearly first: the paywall leads with it and preselects it.
      plans.sort(
        (a, b) =>
            a.period == b.period ? 0 : (a.period == PlanPeriod.yearly ? -1 : 1),
      );
      return ProOffer(List.unmodifiable(plans));
    } on PlatformException catch (error) {
      _report('loadOffer', error);
      return null;
    }
  }

  @override
  Future<ProAccess> purchase(ProPlan plan) async {
    final package = _packages[plan.id];
    if (!_started || package == null) {
      throw const SubscriptionFailure('Purchases are unavailable right now.');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _publish(_read(result.customerInfo));
    } on PlatformException catch (error) {
      throw _failure(error, 'purchase');
    }
  }

  /// Only the two plans the app sells are recognised. Anything else in the
  /// offering is ignored rather than rendered as an unlabelled row.
  static PlanPeriod? _periodOf(Package package) =>
      switch (package.packageType) {
        PackageType.annual => PlanPeriod.yearly,
        PackageType.monthly => PlanPeriod.monthly,
        _ => null,
      };

  @override
  Future<PaywallOutcome> presentPaywall({bool onlyIfLocked = true}) async {
    if (!_started) return PaywallOutcome.failed;
    if (onlyIfLocked && _access.active) return PaywallOutcome.alreadyPro;
    try {
      final result = onlyIfLocked
          ? await RevenueCatUI.presentPaywallIfNeeded(proEntitlement)
          : await RevenueCatUI.presentPaywall();
      await refresh();
      return switch (result) {
        PaywallResult.purchased => PaywallOutcome.purchased,
        PaywallResult.restored => PaywallOutcome.restored,
        PaywallResult.cancelled => PaywallOutcome.cancelled,
        PaywallResult.notPresented => PaywallOutcome.alreadyPro,
        PaywallResult.error => PaywallOutcome.failed,
      };
    } on PlatformException catch (error) {
      _report('presentPaywall', error);
      return PaywallOutcome.failed;
    }
  }

  @override
  Future<void> presentCustomerCenter() async {
    if (!_started) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
      // Cancelling or changing a plan inside the Customer Center changes
      // entitlements, so read them back before the caller rebuilds.
      await refresh();
    } on PlatformException catch (error) {
      _report('presentCustomerCenter', error);
      throw const SubscriptionFailure('Could not open subscription settings.');
    }
  }

  @override
  Future<ProAccess> restore() async {
    if (!_started) {
      throw const SubscriptionFailure('Purchases are unavailable right now.');
    }
    try {
      return _publish(_read(await Purchases.restorePurchases()));
    } on PlatformException catch (error) {
      throw _failure(error, 'restore');
    }
  }

  @override
  Future<void> dispose() async {
    final listener = _listener;
    if (listener != null) Purchases.removeCustomerInfoUpdateListener(listener);
    _listener = null;
    await _controller.close();
  }

  ProAccess _read(CustomerInfo info) {
    final pro = info.entitlements.active[proEntitlement];
    if (pro == null) return ProAccess.locked;
    return ProAccess(
      active: true,
      willRenew: pro.willRenew,
      expiresAt: DateTime.tryParse(pro.expirationDate ?? '')?.toLocal(),
      productIdentifier: pro.productIdentifier,
      managementUrl: info.managementURL,
      sandbox: pro.isSandbox,
    );
  }

  ProAccess _publish(ProAccess next) {
    if (next == _access) return _access;
    _access = next;
    if (!_controller.isClosed) _controller.add(next);
    return next;
  }

  SubscriptionFailure _failure(PlatformException error, String action) {
    _report(action, error);
    return failureFor(PurchasesErrorHelper.getErrorCode(error));
  }

  void _report(String action, PlatformException error) {
    if (!debugLogging) return;
    debugPrint('RevenueCat $action failed: ${error.code} ${error.message}');
  }
}

/// Used when no RevenueCat key is configured, mirroring the other Missing
/// backends: everything stays locked and nothing throws during startup.
class MissingSubscriptionBackend implements SubscriptionBackend {
  const MissingSubscriptionBackend();

  @override
  ProAccess get access => ProAccess.locked;

  @override
  Stream<ProAccess> get accessChanges => const Stream<ProAccess>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> forgetUser() async {}

  @override
  Future<ProAccess> refresh() async => ProAccess.locked;

  @override
  Future<ProOffer?> loadOffer() async => null;

  @override
  Future<ProAccess> purchase(ProPlan plan) =>
      Future.error(const SubscriptionFailure('Purchases are not configured.'));

  @override
  Future<PaywallOutcome> presentPaywall({bool onlyIfLocked = true}) async =>
      PaywallOutcome.failed;

  @override
  Future<void> presentCustomerCenter() async =>
      throw const SubscriptionFailure('Purchases are not configured.');

  @override
  Future<ProAccess> restore() =>
      Future.error(const SubscriptionFailure('Purchases are not configured.'));

  @override
  Future<void> dispose() async {}
}

/// A yearly price restated per month, built by substituting the number inside
/// the store's own localized string so the currency symbol, its position and
/// the decimal separator all survive without a formatting library.
///
/// Returns null for anything it cannot read confidently — a grouped thousands
/// figure, say — because omitting the line is better than inventing a format
/// that is wrong in someone's currency.
String? perMonth(String price, double amount) {
  if (amount <= 0) return null;
  // The whole numeric run, separators included, so a grouped figure is seen
  // as one number rather than as its first group.
  final match = RegExp(r'\d+(?:[.,]\d+)*').firstMatch(price);
  if (match == null) return null;
  final number = price.substring(match.start, match.end);
  // More than one separator means grouping, which this cannot rewrite safely.
  if (RegExp(r'[.,]').allMatches(number).length > 1) return null;
  final decimals = number.contains(RegExp(r'[.,]')) ? 2 : 0;
  final separator = number.contains(',') ? ',' : '.';
  final monthly = (amount / 12)
      .toStringAsFixed(decimals)
      .replaceAll('.', separator);
  return price.replaceRange(match.start, match.end, monthly);
}

/// The sentence to show for a store failure.
///
/// Top-level so the mapping can be exercised without a live store: every code
/// the SDK can raise reaches a person as something they can act on, and only a
/// genuinely unknown one falls through carrying its name.
SubscriptionFailure failureFor(PurchasesErrorCode code) {
  return switch (code) {
    // Not a failure. Callers separate this one out rather than reporting it.
    PurchasesErrorCode.purchaseCancelledError => const SubscriptionFailure(
      'Purchase cancelled.',
    ),

    // Payment itself.
    PurchasesErrorCode.purchaseInvalidError => const SubscriptionFailure(
      'The App Store could not take that payment. Check the payment method '
      'on your Apple ID, then try again.',
    ),
    PurchasesErrorCode.paymentPendingError => const SubscriptionFailure(
      'Your payment is still being processed. Pro unlocks once it completes.',
    ),
    PurchasesErrorCode.purchaseNotAllowedError => const SubscriptionFailure(
      'This device is not allowed to make purchases. Check Screen Time '
      'restrictions.',
      recoverable: false,
    ),
    PurchasesErrorCode.insufficientPermissionsError =>
      const SubscriptionFailure(
        'Purchases are restricted on this device.',
        recoverable: false,
      ),

    // Already owned, or owned by someone else.
    PurchasesErrorCode.productAlreadyPurchasedError =>
      const SubscriptionFailure(
        'You already have this subscription. Try restoring purchases.',
      ),
    PurchasesErrorCode.receiptAlreadyInUseError ||
    PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
      const SubscriptionFailure(
        'These purchases belong to another WeekPact account.',
        recoverable: false,
      ),
    PurchasesErrorCode.ineligibleError => const SubscriptionFailure(
      'This offer is not available on your Apple ID.',
      recoverable: false,
    ),

    // Connectivity.
    PurchasesErrorCode.networkError ||
    PurchasesErrorCode.offlineConnectionError => const SubscriptionFailure(
      'No connection to the App Store. Try again once you are back online.',
    ),

    // The store or our backend is unhappy.
    PurchasesErrorCode.storeProblemError ||
    PurchasesErrorCode.unknownBackendError ||
    PurchasesErrorCode.unexpectedBackendResponseError =>
      const SubscriptionFailure(
        'The App Store is having trouble. Try again in a moment.',
      ),
    PurchasesErrorCode.invalidReceiptError ||
    PurchasesErrorCode.missingReceiptFileError => const SubscriptionFailure(
      'The App Store receipt could not be read. Try restoring purchases.',
    ),
    PurchasesErrorCode.operationAlreadyInProgressError =>
      const SubscriptionFailure(
        'A purchase is already in progress. Give it a moment to finish.',
      ),

    // Nothing to sell. Reachable before products are live, and in a build
    // whose keys or offering are wrong.
    PurchasesErrorCode.productNotAvailableForPurchaseError =>
      const SubscriptionFailure(
        'This plan is not available on the App Store yet.',
        recoverable: false,
      ),
    PurchasesErrorCode.configurationError ||
    PurchasesErrorCode.invalidCredentialsError ||
    PurchasesErrorCode.invalidAppleSubscriptionKeyError ||
    PurchasesErrorCode.unsupportedError => const SubscriptionFailure(
      'Purchases are not set up correctly in this build.',
      recoverable: false,
    ),

    // Test Store only, and deliberately blunt so it is never mistaken for a
    // real payment failure during testing.
    PurchasesErrorCode.testStoreSimulatedPurchaseError =>
      const SubscriptionFailure('Simulated Test Store failure.'),

    _ => SubscriptionFailure(
      'Something went wrong. Please try again.',
      code: code.name,
    ),
  };
}

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'subscription_backend.dart';

/// Keeps the current [ProAccess] in front of the widget tree and rebuilds
/// dependents when entitlements change, including renewals that land while the
/// app is open. Mirrors how NotificationService is exposed through
/// NotificationScope.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController(this.backend) {
    _access = backend.access;
    _changes = backend.accessChanges.listen((next) {
      if (next == _access) return;
      _access = next;
      notifyListeners();
    });
  }

  final SubscriptionBackend backend;
  StreamSubscription<ProAccess>? _changes;
  late ProAccess _access;

  ProAccess get access => _access;
  bool get isPro => _access.active;

  Future<void> refresh() async => backend.refresh();

  Future<ProOffer?> loadOffer() => backend.loadOffer();

  Future<ProAccess> purchase(ProPlan plan) => backend.purchase(plan);

  Future<PaywallOutcome> presentPaywall({bool onlyIfLocked = true}) =>
      backend.presentPaywall(onlyIfLocked: onlyIfLocked);

  Future<void> presentCustomerCenter() => backend.presentCustomerCenter();

  Future<ProAccess> restore() => backend.restore();

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _changes = null;
    super.dispose();
  }
}

class SubscriptionScope extends InheritedNotifier<SubscriptionController> {
  const SubscriptionScope({
    super.key,
    required SubscriptionController controller,
    required super.child,
  }) : super(notifier: controller);

  static SubscriptionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubscriptionScope>()?.notifier;
}

extension SubscriptionContext on BuildContext {
  /// Whether the signed-in account currently has Pro.
  ///
  /// This drives presentation only. Anything that must not be bypassed has to
  /// be enforced server-side as well, since a client check is trivially
  /// defeated on a jailbroken device.
  bool get isPro => SubscriptionScope.maybeOf(this)?.isPro ?? false;

  ProAccess get proAccess =>
      SubscriptionScope.maybeOf(this)?.access ?? ProAccess.locked;
}

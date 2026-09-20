import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import 'paywall_page.dart';
import 'subscription_page.dart';
import 'subscription_backend.dart';
import 'subscription_scope.dart';

/// Account-page row for subscription management.
///
/// Subscribers get the RevenueCat Customer Center, which handles cancellation,
/// plan changes, refund requests and restores natively, so none of that needs
/// custom UI. Everyone else gets the paywall.
class SubscriptionControl extends StatefulWidget {
  const SubscriptionControl({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<SubscriptionControl> createState() => _SubscriptionControlState();
}

class _SubscriptionControlState extends State<SubscriptionControl> {
  bool _busy = false;

  Future<void> _open(SubscriptionController controller, bool isPro) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (isPro) {
        await showSubscriptionPage(context);
      } else {
        await showProPaywall(context);
      }
    } on SubscriptionFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.display)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SubscriptionScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    final access = controller.access;
    final isPro = access.active;
    final enabled = widget.enabled && !_busy;

    return AppSurface(
      builder: (context) => ListTile(
        onTap: enabled ? () => _open(controller, isPro) : null,
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        leading: AppIcon(
          icon: isPro
              ? HugeIconsStrokeRounded.crown
              : HugeIconsStrokeRounded.sparkles,
          color: isPro ? WeekPactColors.warning : context.ink,
          size: 24,
        ),
        title: Text(
          isPro ? 'WeekPact Pro' : 'Upgrade to Pro',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(_subtitle(access), style: const TextStyle(fontSize: 13)),
        trailing: AppIcon(
          icon: HugeIconsStrokeRounded.arrowRight01,
          color: context.ink,
          size: 20,
        ),
      ),
    );
  }

  String _subtitle(ProAccess access) {
    if (!access.active) return 'Unlock everything WeekPact has to offer.';
    final expires = access.expiresAt;
    if (access.cancelled && expires != null) {
      return 'Ends ${_date(expires)} · Manage subscription';
    }
    if (expires != null) {
      return 'Renews ${_date(expires)} · Manage subscription';
    }
    return 'Manage subscription';
  }

  String _date(DateTime value) => formatSubscriptionDate(value);
}

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/account_actions.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/page_frame.dart';
import 'subscription_backend.dart';
import 'subscription_scope.dart';

const _gold = WeekPactColors.stone;
const _cream = WeekPactColors.cream;
const _ink = WeekPactColors.black;

/// Shows the app's own paywall and reports what came of it.
///
/// Returns [PaywallOutcome.cancelled] when someone backs out, including with
/// the system back gesture, so callers never treat a dismissal as a failure.
/// [allowWhenPro] is for changing plan, where a subscriber is meant to reach
/// the same screen and buy the other package.
Future<PaywallOutcome> showProPaywall(
  BuildContext context, {
  bool allowWhenPro = false,
}) async {
  final controller = SubscriptionScope.maybeOf(context);
  if (controller == null) return PaywallOutcome.failed;
  if (controller.isPro && !allowWhenPro) return PaywallOutcome.alreadyPro;
  final outcome = await Navigator.of(context).push<PaywallOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          SubscriptionScope(controller: controller, child: const PaywallPage()),
    ),
  );
  return outcome ?? PaywallOutcome.cancelled;
}

/// WeekPact Pro, drawn in the app's own design rather than the store's.
///
/// Prices are never composed here: every amount comes from the store already
/// localized, so currency, symbol placement and separators stay correct.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  ProOffer? _offer;
  String? _selectedId;
  String? _failure;
  bool _loading = true;
  bool _busy = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope cannot be read from initState, and the plans are wanted only
    // once however often dependencies change afterwards.
    if (_requested) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    final offer = await SubscriptionScope.maybeOf(context)?.loadOffer();
    if (!mounted) return;
    setState(() {
      _offer = offer;
      // The yearly plan leads, so it is what someone buys by just continuing.
      _selectedId = (offer?.yearly ?? offer?.plans.firstOrNull)?.id;
      _loading = false;
    });
  }

  Future<void> _buy() async {
    final controller = SubscriptionScope.maybeOf(context);
    final plan = _offer?.plans
        .where((plan) => plan.id == _selectedId)
        .firstOrNull;
    if (controller == null || plan == null || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await controller.purchase(plan);
      if (mounted) Navigator.pop(context, PaywallOutcome.purchased);
    } on SubscriptionFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.display);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final controller = SubscriptionScope.maybeOf(context);
    if (controller == null || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final access = await controller.restore();
      if (!mounted) return;
      if (access.active) {
        Navigator.pop(context, PaywallOutcome.restored);
        return;
      }
      setState(() => _failure = 'No previous purchase found on this Apple ID.');
    } on SubscriptionFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.display);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    return Scaffold(
      backgroundColor: WeekPactColors.darkCanvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _CloseButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.pop(context, PaywallOutcome.cancelled),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _Tile(
                  icon: HugeIconsStrokeRounded.crown,
                  size: 60,
                  radius: 16,
                  iconSize: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'WeekPact Pro',
                style: TextStyle(
                  color: WeekPactDarkCard.ink,
                  fontSize: 38,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const _Body(
                'One crew is free, forever. Pro is for everyone who keeps more '
                'than one week going at once.',
              ),
              const SizedBox(height: 26),
              const _Benefit(
                icon: HugeIconsStrokeRounded.userGroup02,
                title: 'Unlimited crews',
                body: 'One for the gym, one for work, one with friends.',
              ),
              const _Benefit(
                icon: HugeIconsStrokeRounded.calendar03,
                title: 'A separate week in each',
                body: 'Every crew keeps its own pacts, check-ins and streak.',
              ),
              const _Benefit(
                icon: HugeIconsStrokeRounded.favourite,
                title: 'Keeps WeekPact going',
                body: 'No ads, ever. Nothing sold on, ever.',
              ),
              const SizedBox(height: 10),
              if (_loading)
                const _PlansSkeleton()
              else if (offer == null || offer.isEmpty)
                const _Unavailable()
              else
                ..._plans(offer),
              if (_failure != null) ...[
                const SizedBox(height: 14),
                Text(
                  _failure!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: WeekPactColors.darkError,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (offer != null && !offer.isEmpty)
                AppButton(
                  label: 'START WEEKPACT PRO',
                  color: _gold,
                  foregroundColor: _ink,
                  isLoading: _busy,
                  onPressed: _buy,
                ),
              const SizedBox(height: 16),
              _Footer(onRestore: _busy ? null : _restore),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _plans(ProOffer offer) {
    final saving = offer.yearlySaving;
    return [
      for (final plan in offer.plans) ...[
        _Plan(
          plan: plan,
          selected: plan.id == _selectedId,
          badge: plan.period == PlanPeriod.yearly && saving != null
              ? 'SAVE $saving%'
              : null,
          onTap: _busy ? null : () => setState(() => _selectedId = plan.id),
        ),
        if (plan != offer.plans.last) const SizedBox(height: 10),
      ],
    ];
  }
}

/// A price row. The selected plan reads as a cream card; the other sits back
/// on the canvas.
class _Plan extends StatelessWidget {
  const _Plan({
    required this.plan,
    required this.selected,
    this.badge,
    this.onTap,
  });

  final ProPlan plan;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  String get _period => switch (plan.period) {
    PlanPeriod.yearly => '12 MONTHS',
    PlanPeriod.monthly => '1 MONTH',
  };

  String get _detail => switch (plan.period) {
    PlanPeriod.yearly =>
      plan.pricePerMonth == null
          ? 'billed yearly'
          : '${plan.pricePerMonth} / month',
    PlanPeriod.monthly => 'billed monthly',
  };

  @override
  Widget build(BuildContext context) {
    // A price cannot wrap — there is no space to break at — so past roughly
    // 1.4x the row is stacked instead of being pushed off the screen edge.
    final stacked = MediaQuery.textScalerOf(context).scale(24) > 34;
    final ink = selected ? _ink : WeekPactDarkCard.ink;
    final period = Text(
      _period,
      style: TextStyle(
        color: ink,
        fontSize: 12,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    );
    final price = Text(
      plan.price,
      style: TextStyle(
        color: ink,
        fontSize: 24,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
    final detail = Text(
      _detail,
      textAlign: stacked ? TextAlign.left : TextAlign.right,
      style: TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        color: selected ? WeekPactColors.mutedLight : WeekPactDarkCard.muted,
        fontSize: 13,
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      label: '$_period, ${plan.price}, $_detail',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppSurface(
            fillColor: selected ? _cream : WeekPactDarkCard.fill,
            resolveTone: false,
            borderWidth: selected ? 2 : 1,
            outlineColor: selected ? _ink : WeekPactDarkCard.outline,
            builder: (context) => InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          period,
                          const SizedBox(height: 4),
                          price,
                          const SizedBox(height: 6),
                          detail,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                period,
                                const SizedBox(height: 4),
                                price,
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(child: detail),
                        ],
                      ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -10,
              right: 14,
              child: AppSurface(
                fillColor: _gold,
                resolveTone: false,
                borderRadius: 8,
                builder: (context) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.size,
    required this.radius,
    required this.iconSize,
  });
  final List<List<dynamic>> icon;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: AppSurface(
      fillColor: _gold,
      resolveTone: false,
      borderRadius: radius,
      builder: (context) => Center(
        child: AppIcon(icon: icon, size: iconSize, color: _ink, strokeWidth: 2),
      ),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body});
  final List<List<dynamic>> icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Tile(icon: icon, size: 40, radius: 11, iconSize: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: WeekPactDarkCard.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              _Body(body, size: 13),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.size = 15});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: WeekPactType.secondary,
      fontFamilyFallback: WeekPactType.secondaryFallback,
      color: WeekPactDarkCard.muted,
      fontSize: size,
      height: 1.3,
    ),
  );
}

class _PlansSkeleton extends StatelessWidget {
  const _PlansSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading plans',
    child: Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          SkeletonBar(
            height: 74,
            radius: 18,
            color: WeekPactDarkCard.ink.withValues(alpha: .08),
          ),
          if (row == 0) const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

/// No offering reached the app. Restore stays available, because someone who
/// already paid must still be able to get their entitlement back.
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: WeekPactDarkCard.fill,
    resolveTone: false,
    outlineColor: WeekPactDarkCard.outline,
    builder: (context) => const Padding(
      padding: EdgeInsets.all(18),
      child: _Body(
        'Plans aren’t available right now. Check your connection and try '
        'again in a moment.',
      ),
    ),
  );
}

/// Restore, Terms and Privacy. Apple requires all three on a paywall.
class _Footer extends StatelessWidget {
  const _Footer({this.onRestore});
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _FooterLink(label: 'Restore', onTap: onRestore),
      const _FooterDot(),
      _FooterLink(
        label: 'Terms',
        onTap: () => openPublicLink(context, termsUrl),
      ),
      const _FooterDot(),
      _FooterLink(
        label: 'Privacy',
        onTap: () => openPublicLink(context, privacyUrl),
      ),
    ],
  );
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      '·',
      style: TextStyle(color: WeekPactDarkCard.muted, fontSize: 12),
    ),
  );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: WeekPactDarkCard.muted,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 12,
      ),
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 34,
    child: AppSurface(
      fillColor: WeekPactDarkCard.fill,
      resolveTone: false,
      borderRadius: 10,
      outlineColor: WeekPactDarkCard.outline,
      builder: (context) => Semantics(
        button: true,
        label: 'Close',
        child: InkWell(
          key: const ValueKey('paywall-close'),
          onTap: onPressed,
          child: const Center(
            child: AppIcon(
              icon: HugeIconsStrokeRounded.cancel01,
              size: 16,
              color: WeekPactDarkCard.muted,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/account_actions.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import 'paywall_page.dart';
import 'subscription_backend.dart';
import 'subscription_scope.dart';

const _gold = WeekPactColors.stone;
const _cream = WeekPactColors.cream;
const _ink = WeekPactColors.black;

/// Opens the app's own subscription management page.
Future<void> showSubscriptionPage(BuildContext context) async {
  final controller = SubscriptionScope.maybeOf(context);
  if (controller == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SubscriptionScope(
        controller: controller,
        child: const SubscriptionPage(),
      ),
    ),
  );
}

/// Where someone sees what they are paying for and cancels it.
///
/// Apple gives no way to cancel from inside an app, so cancelling means
/// handing over to the App Store. The page is honest about that rather than
/// pretending the button does it, and everything around it — status, renewal,
/// plan changes, restoring — is the app's own.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  // Only wanted for what the other plan saves. The row reads fine without it,
  // so nothing waits on this.
  ProOffer? _offer;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    SubscriptionScope.maybeOf(context)?.loadOffer().then((offer) {
      if (mounted) setState(() => _offer = offer);
    });
  }

  /// What the other plan is worth, once the offering says. Falls back to the
  /// plain fact while it loads, or if there is nothing to compare.
  String _switchBody(ProAccess access) {
    if (access.isYearly) return 'Pay month to month instead.';
    final saving = _offer?.yearlySaving;
    return saving == null
        ? 'Pay once a year instead.'
        : 'Save $saving% paying once a year.';
  }

  /// The reassurance, not the mechanism: nobody loses what they paid for.
  String _cancelBody(ProAccess access) {
    final expires = access.expiresAt;
    if (expires == null) return 'You keep Pro until it runs out.';
    return 'You keep Pro until ${formatSubscriptionDate(expires)}.';
  }

  /// Cancelling is Apple's screen, always. The confirmation exists so nobody
  /// is dropped into Settings without knowing why.
  Future<void> _cancel(ProAccess access) async {
    final url = access.managementUrl;
    if (url == null) {
      await showAppDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          icon: HugeIconsStrokeRounded.informationCircle,
          iconColor: WeekPactColors.coolGrey,
          title: 'Not managed by the App Store',
          message:
              'This subscription did not come from the App Store, so there is '
              'no subscription screen to open. Contact support and we will '
              'sort it out.',
          actions: [AppDialogDismiss(label: 'OK')],
        ),
      );
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: HugeIconsStrokeRounded.cancel01,
        iconColor: WeekPactColors.softCoral,
        title: 'Cancel in the App Store',
        message:
            'Apple handles cancellation, so this opens your subscription '
            'settings. You keep Pro until the date you have already paid '
            'through.',
        actions: [
          AppButton(
            label: 'OPEN APP STORE',
            onPressed: () => Navigator.pop(context, true),
          ),
          AppDialogDismiss(
            label: 'NEVER MIND',
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await openPublicLink(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final access =
        SubscriptionScope.maybeOf(context)?.access ?? ProAccess.locked;
    return Scaffold(
      backgroundColor: WeekPactColors.darkCanvas,
      appBar: AppBar(
        backgroundColor: WeekPactColors.darkCanvas,
        foregroundColor: _cream,
        elevation: 0,
        title: const Text(
          'Subscription',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(access: access),
              const SizedBox(height: 22),
              const _Heading('MANAGE'),
              const SizedBox(height: 10),
              _Action(
                icon: HugeIconsStrokeRounded.repeat,
                title: access.isYearly
                    ? 'Switch to monthly'
                    : 'Switch to yearly',
                body: _switchBody(access),
                onTap: () => showProPaywall(context, allowWhenPro: true),
              ),
              _Action(
                icon: HugeIconsStrokeRounded.cancel01,
                title: 'Cancel subscription',
                body: _cancelBody(access),
                tint: WeekPactColors.softCoral,
                // The status card already says it is ending; cancelling twice
                // is not something to offer.
                onTap: access.cancelled ? null : () => _cancel(access),
              ),
              const SizedBox(height: 22),
              const _Heading('ABOUT'),
              const SizedBox(height: 10),
              _Action(
                icon: HugeIconsStrokeRounded.file01,
                title: 'Terms',
                body: 'The legal bit.',
                onTap: () => openPublicLink(context, termsUrl),
              ),
              _Action(
                icon: HugeIconsStrokeRounded.shield01,
                title: 'Privacy',
                body: 'What we keep, and never sell.',
                onTap: () => openPublicLink(context, privacyUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What they have, in one cream card: the plan, whether it renews, and when.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.access});
  final ProAccess access;

  String get _plan => switch (access.productIdentifier) {
    null => 'WeekPact Pro',
    final id when id.contains(yearlyProduct) => 'Yearly plan',
    final id when id.contains(monthlyProduct) => 'Monthly plan',
    _ => 'WeekPact Pro',
  };

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: _cream,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 46,
                child: AppSurface(
                  fillColor: _gold,
                  resolveTone: false,
                  borderRadius: 13,
                  builder: (context) => const Center(
                    child: AppIcon(
                      icon: HugeIconsStrokeRounded.crown,
                      size: 24,
                      color: _ink,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _plan,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _Badge(access: access),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _renewal(access),
            style: const TextStyle(
              fontFamily: WeekPactType.secondary,
              fontFamilyFallback: WeekPactType.secondaryFallback,
              color: WeekPactColors.mutedLight,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          if (access.sandbox) ...[
            const SizedBox(height: 8),
            const Text(
              'Sandbox purchase — not a real charge.',
              style: TextStyle(
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                color: WeekPactColors.mutedLight,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  static String _renewal(ProAccess access) {
    final expires = access.expiresAt;
    if (!access.active) {
      return 'You do not have an active subscription.';
    }
    if (expires == null) return 'Your access does not expire.';
    return access.willRenew
        ? 'Renews automatically on ${formatSubscriptionDate(expires)}.'
        : 'Cancelled. Pro stays active until '
              '${formatSubscriptionDate(expires)}.';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.access});
  final ProAccess access;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (access) {
      ProAccess(active: false) => ('EXPIRED', WeekPactColors.neutralInset),
      ProAccess(cancelled: true) => ('ENDING', WeekPactColors.softCoral),
      _ => ('ACTIVE', WeekPactColors.mintGreen),
    };
    return AppSurface(
      fillColor: color,
      resolveTone: false,
      borderRadius: 8,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: _ink,
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.body,
    this.tint,
    this.onTap,
  });

  final List<List<dynamic>> icon;
  final String title;

  /// One short line. Enough to set an expectation, never a paragraph — the
  /// status card above has already explained the subscription itself.
  final String body;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: AppSurface(
          fillColor: WeekPactDarkCard.fill,
          resolveTone: false,
          outlineColor: WeekPactDarkCard.outline,
          builder: (context) => InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 38,
                    child: AppSurface(
                      fillColor: tint ?? _gold,
                      resolveTone: false,
                      borderRadius: 11,
                      builder: (context) => Center(
                        child: AppIcon(
                          icon: icon,
                          size: 19,
                          color: _ink,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
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
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: const TextStyle(
                            fontFamily: WeekPactType.secondary,
                            fontFamilyFallback: WeekPactType.secondaryFallback,
                            color: WeekPactDarkCard.muted,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AppIcon(
                    icon: HugeIconsStrokeRounded.arrowRight01,
                    size: 18,
                    color: WeekPactDarkCard.muted,
                    strokeWidth: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: WeekPactDarkCard.muted,
      fontSize: 11,
      letterSpacing: 2,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Shared by the page and the account tile so one date never reads differently
/// from the other.
String formatSubscriptionDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

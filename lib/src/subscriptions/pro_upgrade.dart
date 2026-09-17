import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import 'paywall_page.dart';
import 'subscription_backend.dart';
import 'subscription_scope.dart';

/// SQLSTATE raised by `private.enforce_crew_limit`. Postgres is the authority
/// on the limit; the client only recognises its refusal so it can offer the
/// upgrade instead of showing a database sentence.
const crewLimitCode = 'WPPRO';

/// Whether an error is Postgres refusing a second crew. Matched on the code
/// rather than the message, so wording can change without breaking this.
bool isCrewLimitError(Object error) => error.toString().contains(crewLimitCode);

/// Why the person hit the limit. Only the sentence differs.
enum CrewLimitReason { creating, joining }

/// Explains that crews beyond the first are a Pro feature, and opens the
/// paywall from the same sheet rather than sending someone off to find it.
///
/// Returns true when the person came back with Pro, so the caller can retry
/// what they were doing instead of making them tap it again.
Future<bool> showCrewLimitUpgrade(
  BuildContext context, {
  required CrewLimitReason reason,
}) async {
  final controller = SubscriptionScope.maybeOf(context);
  final wanted = await showAppDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      icon: HugeIconsStrokeRounded.crown,
      title: 'One crew on the free plan',
      message: reason == CrewLimitReason.creating
          ? 'You’re already in a crew. WeekPact Pro lets you run as many as '
                'you like — one for the gym, one for work, one with friends.'
          : 'You’re already in a crew. WeekPact Pro lets you join as many as '
                'you like, and keep a separate week going in each.',
      actions: [
        // Without a configured store there is nothing to show, so the upgrade
        // is not offered rather than opening a paywall that cannot load.
        if (controller != null)
          AppButton(
            label: 'SEE WEEKPACT PRO',
            onPressed: () => Navigator.pop(context, true),
          ),
        AppDialogDismiss(
          label: 'NOT NOW',
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    ),
  );
  if (wanted != true || controller == null || !context.mounted) return false;

  final outcome = await showProPaywall(context);
  return outcome == PaywallOutcome.purchased ||
      outcome == PaywallOutcome.restored ||
      outcome == PaywallOutcome.alreadyPro;
}

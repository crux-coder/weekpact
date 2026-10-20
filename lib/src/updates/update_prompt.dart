import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import 'update_check.dart';

/// Shows the update dialog over [child] when [UpdateCheck] finds one.
///
/// Two of these sit in the app. [UpdatePrompt.required] wraps everything,
/// signed out included: a build the backend no longer supports cannot sign
/// in either, so there is nothing for the dialog to interrupt. The optional
/// one, [UpdatePrompt.optional], wraps only Home, so a new release never
/// lands on top of someone halfway through signing in.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt.required({
    super.key,
    required this.updates,
    required this.child,
  }) : need = UpdateNeed.required;

  const UpdatePrompt.optional({
    super.key,
    required this.updates,
    required this.child,
  }) : need = UpdateNeed.optional;

  final UpdateCheck updates;
  final Widget child;

  /// The one need this prompt answers; the other is left to its sibling.
  final UpdateNeed need;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  BuildContext? _dialog;

  @override
  void initState() {
    super.initState();
    widget.updates.addListener(_changed);
    // The check may have finished before this part of the app was reached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(UpdatePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      oldWidget.updates.removeListener(_changed);
      widget.updates.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.updates.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final updates = widget.updates;
    final open = _dialog;
    if (open != null) {
      // A forced prompt lifts once the row no longer forces it.
      if (widget.need == UpdateNeed.required &&
          updates.need != UpdateNeed.required &&
          open != context &&
          open.mounted) {
        Navigator.pop(open);
      }
      return;
    }
    switch (widget.need) {
      case UpdateNeed.required:
        if (updates.need == UpdateNeed.required) unawaited(_show(forced: true));
      case UpdateNeed.optional:
        if (updates.shouldOfferOptional) {
          unawaited(updates.markOffered());
          unawaited(_show(forced: false));
        }
      case UpdateNeed.none:
        break;
    }
  }

  Future<void> _show({required bool forced}) async {
    final updates = widget.updates;
    final message = updates.release?.message;
    // Claimed before the route exists, so a second notification in the same
    // frame cannot open a second dialog.
    _dialog = context;
    await showAppDialog<void>(
      context: context,
      barrierDismissible: !forced,
      builder: (dialog) {
        _dialog = dialog;
        return PopScope(
          canPop: !forced,
          child: AppDialog(
            icon: HugeIconsStrokeRounded.download04,
            iconColor: WeekPactColors.lime,
            title: forced
                ? 'Update WeekPact to continue'
                : 'A new version of WeekPact is out',
            message:
                message ??
                (forced
                    ? 'This version of WeekPact no longer works. Update to '
                          'keep going.'
                    : 'Update for the latest fixes and improvements.'),
            actions: [
              AppButton(
                key: const ValueKey('update-now'),
                label: 'Update',
                onPressed: () {
                  // A forced prompt stays up behind the store; coming back
                  // without updating finds it still there.
                  if (!forced) Navigator.pop(dialog);
                  unawaited(updates.openUpdate());
                },
              ),
              if (!forced)
                const AppDialogDismiss(
                  key: ValueKey('update-later'),
                  label: 'Later',
                ),
            ],
          ),
        );
      },
    );
    _dialog = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

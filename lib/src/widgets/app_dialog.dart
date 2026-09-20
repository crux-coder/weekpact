import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import 'app_components.dart';
import 'app_icon.dart';

/// The app's own dialog: the same raised squircle as every other surface,
/// rather than Material's flat rounded rectangle.
///
/// Actions stack full width so each one is a real button with its own edge,
/// instead of the cramped text links an [AlertDialog] puts in a row. The first
/// action is the one being offered, so it sits on top.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.iconColor,
    this.content,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final List<List<dynamic>>? icon;
  final Color? iconColor;

  /// Anything richer than [message], placed between the text and the actions.
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AppSurface(
        fillColor: context.surface,
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: 52,
                    child: AppSurface(
                      fillColor: iconColor ?? context.yellow,
                      borderRadius: 14,
                      builder: (context) => Center(
                        child: AppIcon(
                          icon: icon,
                          size: 26,
                          color: WeekPactColors.black,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                title,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 27,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
              if (content != null) ...[const SizedBox(height: 18), content!],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                for (final action in actions) ...[
                  action,
                  if (action != actions.last) const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The quieter of two stacked [AppDialog] actions: still a raised button with
/// its own edge, but it does not compete with the one being offered.
class AppDialogDismiss extends StatelessWidget {
  const AppDialogDismiss({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    color: WeekPactColors.neutralInset,
    foregroundColor: WeekPactColors.black,
    onPressed: onPressed ?? () => Navigator.pop(context),
  );
}

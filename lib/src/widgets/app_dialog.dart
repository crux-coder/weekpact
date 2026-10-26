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
    this.emphasis,
    this.icon,
    this.iconColor,
    this.content,
    this.actions = const [],
    this.centered = false,
  });

  final String title;
  final String? message;

  /// A name inside [message], such as the pact being acted on, drawn bold
  /// in ink so the eye lands on what the dialog is about.
  final String? emphasis;
  final List<List<dynamic>>? icon;
  final Color? iconColor;

  /// Anything richer than [message], placed between the text and the actions.
  final Widget? content;
  final List<Widget> actions;

  /// Centres the icon, title and message: for a short question asked on its
  /// own, rather than a dialog that carries a form in [content].
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // The theme's dialog shape carries an outline, which would trace a plain
      // rounded rectangle around the squircle; the surface draws its own edge.
      shape: const RoundedRectangleBorder(),
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
                  alignment: centered ? Alignment.center : Alignment.centerLeft,
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
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 27,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text.rich(
                  _messageSpan(context, message!),
                  textAlign: centered ? TextAlign.center : TextAlign.start,
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

  TextSpan _messageSpan(BuildContext context, String message) {
    final emphasis = this.emphasis;
    final at = emphasis == null || emphasis.isEmpty
        ? -1
        : message.indexOf(emphasis);
    if (at < 0) return TextSpan(text: message);
    return TextSpan(
      children: [
        TextSpan(text: message.substring(0, at)),
        TextSpan(
          text: emphasis,
          style: TextStyle(color: context.ink, fontWeight: FontWeight.w600),
        ),
        TextSpan(text: message.substring(at + emphasis!.length)),
      ],
    );
  }
}

/// The quieter of two stacked [AppDialog] actions: still a raised button with
/// its own edge, but it does not compete with the one being offered.
///
/// With [plain] it drops the button altogether and is only its label, so the
/// action being offered is the one button in the dialog.
class AppDialogDismiss extends StatelessWidget {
  const AppDialogDismiss({
    super.key,
    required this.label,
    this.onPressed,
    this.plain = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed ?? () => Navigator.pop(context);
    if (!plain) {
      return AppButton(
        label: label,
        color: WeekPactColors.neutralInset,
        foregroundColor: WeekPactColors.black,
        onPressed: onPressed,
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: context.ink,
        textStyle: const TextStyle(
          fontFamily: WeekPactType.primary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';

class BrutalShadow extends StatelessWidget {
  const BrutalShadow({
    super.key,
    required this.child,
    this.fillColor,
    this.shadowOffset = WeekPactMetrics.shadow,
    this.borderWidth = WeekPactMetrics.border,
    this.borderRadius = 8,
    this.cornerRadius,
  });

  final Widget child;
  final Color? fillColor;
  final Offset shadowOffset;
  final double borderWidth;
  final double borderRadius;
  final BorderRadius? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final radius = cornerRadius ?? BorderRadius.circular(borderRadius);
    return Material(
      color: context.tone(fillColor ?? context.surface),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.border, width: borderWidth),
      ),
      borderOnForeground: true,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A raised card with an attached title tab and a square joining corner.
class BrutalTabbedCard extends StatelessWidget {
  const BrutalTabbedCard({
    super.key,
    required this.title,
    required this.tabColor,
    required this.child,
    this.fillColor,
    this.tabTrailing,
    this.tabs,
  });

  final String title;
  final Color tabColor;
  final Color? fillColor;
  final Widget child;
  final Widget? tabTrailing;
  final List<Widget>? tabs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (tabs != null)
              ...tabs!
            else
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 7),
                      decoration: BoxDecoration(
                        color: context.tone(tabColor),
                        border: Border(
                          top: BorderSide(
                            color: context.border,
                            width: WeekPactMetrics.border,
                          ),
                          left: BorderSide(
                            color: context.border,
                            width: WeekPactMetrics.border,
                          ),
                          right: BorderSide(
                            color: context.border,
                            width: WeekPactMetrics.border,
                          ),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        boxShadow: const [],
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (tabTrailing != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 9),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: tabTrailing!,
                  ),
                ),
              ),
            ],
          ],
        ),
        BrutalShadow(
          fillColor: fillColor,
          shadowOffset: WeekPactMetrics.shadow,
          cornerRadius: const BorderRadius.only(
            topRight: Radius.circular(8),
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}

class BrutalButton extends StatelessWidget {
  const BrutalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.foregroundColor,
    this.icon,
    this.isLoading = false,
    this.height = WeekPactMetrics.buttonHeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? foregroundColor;
  final List<List<dynamic>>? icon;
  final bool isLoading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.primary;
    final effectiveForeground = foregroundColor ?? context.ink;

    return BrutalShadow(
      fillColor: effectiveColor,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: height),
        child: TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            padding: WeekPactMetrics.buttonPadding,
            minimumSize: Size(0, height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: effectiveForeground,
            disabledForegroundColor: effectiveForeground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: const TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          child: isLoading
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    color: effectiveForeground,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      HugeIcon(
                        icon: icon!,
                        color: effectiveForeground,
                        size: 18,
                        strokeWidth: 2,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: Text(label, textAlign: TextAlign.center)),
                  ],
                ),
        ),
      ),
    );
  }
}

class BrutalNavigationItem {
  const BrutalNavigationItem({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;
}

class BrutalBottomNavigationBar extends StatelessWidget {
  const BrutalBottomNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.glass = false,
  });
  final bool glass;
  final List<BrutalNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: glass ? const Color(0xB3443C62) : context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: glass ? const Color(0x50FFFFFF) : WeekPactColors.outlineInk,
          width: 2,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final duration = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 320);
          final unit = constraints.maxWidth / (items.length + 1);
          return Row(
            children: [
              for (var i = 0; i < items.length; i++)
                TweenAnimationBuilder<double>(
                  key: ValueKey('nav-animation-${items[i].label}'),
                  tween: Tween<double>(
                    begin: selectedIndex == i ? 1 : 0,
                    end: selectedIndex == i ? 1 : 0,
                  ),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, amount, _) => SizedBox(
                    width: unit * (1 + amount),
                    child: Semantics(
                      selected: selectedIndex == i,
                      label: items[i].label,
                      child: Tooltip(
                        message: items[i].label,
                        child: Material(
                          color: Color.lerp(
                            glass ? Colors.transparent : context.surface,
                            glass
                                ? const Color(0xFFCAB8FA)
                                : WeekPactColors.salmon,
                            amount,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            key: ValueKey(
                              'nav-${items[i].label.toLowerCase()}',
                            ),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onSelected(i),
                            child: SizedBox(
                              height: 52,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  HugeIcon(
                                    icon: items[i].icon,
                                    color: Color.lerp(
                                      glass ? Colors.white : context.ink,
                                      WeekPactColors.outlineInk,
                                      amount,
                                    ),
                                    size: 25,
                                  ),
                                  if (amount > 0) ...[
                                    SizedBox(width: 7 * amount),
                                    Flexible(
                                      child: ClipRect(
                                        child: Align(
                                          widthFactor: amount,
                                          alignment: Alignment.centerLeft,
                                          child: Opacity(
                                            opacity: amount,
                                            child: ExcludeSemantics(
                                              child: Text(
                                                items[i].label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color:
                                                      WeekPactColors.outlineInk,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class BrutalTextField extends StatelessWidget {
  const BrutalTextField({
    super.key,
    this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onToggleObscure,
    this.autofillHints,
  });

  final String? label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
        ],
        BrutalShadow(
          child: TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            autofillHints: autofillHints,
            style: TextStyle(
              color: context.fieldInk,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: context.muted,
                fontWeight: FontWeight.w500,
              ),
              // The rounded BrutalShadow owns the fill and outline. A second
              // borderless input fill paints square corners over its interior.
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 17,
              ),
              suffixIcon: onToggleObscure == null
                  ? null
                  : IconButton(
                      onPressed: onToggleObscure,
                      tooltip: obscureText ? 'Show password' : 'Hide password',
                      icon: HugeIcon(
                        icon: obscureText
                            ? HugeIconsStrokeRounded.view
                            : HugeIconsStrokeRounded.viewOff,
                        color: context.fieldInk,
                        size: 24,
                        strokeWidth: 2,
                      ),
                    ),
              errorStyle: TextStyle(
                color: context.errorInk,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/keepup_theme.dart';

class BrutalShadow extends StatelessWidget {
  const BrutalShadow({
    super.key,
    required this.child,
    this.fillColor,
    this.shadowOffset = KeepUpMetrics.shadow,
    this.borderWidth = KeepUpMetrics.border,
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
    Radius inset(Radius corner) => Radius.elliptical(
      (corner.x - borderWidth).clamp(0.0, double.infinity),
      (corner.y - borderWidth).clamp(0.0, double.infinity),
    );

    return Container(
      decoration: BoxDecoration(
        color: context.tone(fillColor ?? context.surface),
        borderRadius: radius,
        border: Border.all(color: context.border, width: borderWidth),
        boxShadow: [BoxShadow(color: context.shadow, offset: shadowOffset)],
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: inset(radius.topLeft),
          topRight: inset(radius.topRight),
          bottomLeft: inset(radius.bottomLeft),
          bottomRight: inset(radius.bottomRight),
        ),
        child: child,
      ),
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
                            width: KeepUpMetrics.border,
                          ),
                          left: BorderSide(
                            color: context.border,
                            width: KeepUpMetrics.border,
                          ),
                          right: BorderSide(
                            color: context.border,
                            width: KeepUpMetrics.border,
                          ),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.shadow,
                            offset: KeepUpMetrics.shadow,
                          ),
                        ],
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
          shadowOffset: KeepUpMetrics.shadow,
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
    this.height = KeepUpMetrics.buttonHeight,
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
            padding: KeepUpMetrics.buttonPadding,
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
  });

  final List<BrutalNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: BrutalShadow(
        borderRadius: 12,
        shadowOffset: KeepUpMetrics.shadow,
        fillColor: context.shadow,
        child: SizedBox(
          height: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _BrutalNavigationButton(
                    key: ValueKey('nav-${items[index].label.toLowerCase()}'),
                    item: items[index],
                    selected: selectedIndex == index,
                    isFirst: index == 0,
                    isLast: index == items.length - 1,
                    showDivider: index != items.length - 1,
                    onPressed: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrutalNavigationButton extends StatefulWidget {
  const _BrutalNavigationButton({
    super.key,
    required this.item,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.showDivider,
    required this.onPressed,
  });

  final BrutalNavigationItem item;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final bool showDivider;
  final VoidCallback onPressed;

  @override
  State<_BrutalNavigationButton> createState() =>
      _BrutalNavigationButtonState();
}

class _BrutalNavigationButtonState extends State<_BrutalNavigationButton> {
  bool _isHeld = false;

  void _setHeld(bool value) {
    if (_isHeld == value) return;
    setState(() => _isHeld = value);
  }

  @override
  Widget build(BuildContext context) {
    final isPressed = widget.selected || _isHeld;

    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setHeld(true),
        onTapUp: (_) => _setHeld(false),
        onTapCancel: () => _setHeld(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          key: ValueKey('nav-key-${widget.item.label.toLowerCase()}'),
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            top: isPressed ? KeepUpMetrics.pressDepth : 0,
            bottom: isPressed ? 0 : KeepUpMetrics.pressDepth,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? context.tone(widget.item.color)
                : context.surface,
            borderRadius: BorderRadius.only(
              topLeft: widget.isFirst ? const Radius.circular(9) : Radius.zero,
              bottomLeft: widget.isFirst
                  ? const Radius.circular(9)
                  : Radius.zero,
              topRight: widget.isLast ? const Radius.circular(9) : Radius.zero,
              bottomRight: widget.isLast
                  ? const Radius.circular(9)
                  : Radius.zero,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(
                    icon: widget.item.icon,
                    color: context.ink,
                    size: 24,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 3),
                  Flexible(
                    child: Text(
                      widget.item.label.toUpperCase(),
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.showDivider)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: KeepUpMetrics.border,
                  child: ColoredBox(color: context.border),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

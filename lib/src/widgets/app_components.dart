import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_icon.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.builder,
    this.fillColor,
    this.borderWidth = WeekPactMetrics.border,
    this.borderRadius = WeekPactMetrics.cardCorner,
    this.cornerRadius,
    this.shape,
    this.outlineColor,
    this.resolveTone = true,
    this.raised = true,
  });

  final WidgetBuilder builder;
  final Color? fillColor;
  final double borderWidth;
  final double borderRadius;
  final BorderRadius? cornerRadius;
  final OutlinedBorder? shape;
  final Color? outlineColor;
  final bool resolveTone;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final radius = cornerRadius ?? BorderRadius.circular(borderRadius);
    final surfaceShape =
        shape ??
        (raised
            ? ContinuousRectangleBorder(
                borderRadius:
                    radius *
                    (WeekPactMetrics.cardCurve / WeekPactMetrics.cardCorner),
              )
            : RoundedRectangleBorder(borderRadius: radius));
    final face = resolveTone
        ? context.tone(fillColor ?? context.surface)
        : fillColor ?? context.surface;
    final dark = face.computeLuminance() < .18;
    final material = Material(
      color: face,
      shape: surfaceShape.copyWith(
        side: BorderSide(
          color:
              outlineColor ??
              Color.lerp(
                face,
                dark ? Colors.white : Colors.black,
                dark ? .12 : .28,
              )!,
          width: borderWidth,
        ),
      ),
      borderOnForeground: true,
      clipBehavior: Clip.antiAlias,
      child: AppSurfaceTheme(builder: builder),
    );
    if (!raised) return material;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: surfaceShape,
        shadows: [
          BoxShadow(
            color: Color.lerp(
              face,
              dark ? Colors.white : Colors.black,
              dark ? .12 : .24,
            )!,
            offset: WeekPactMetrics.raisedOffset,
          ),
        ],
      ),
      child: material,
    );
  }
}

/// A raised section surface with an integrated heading and optional actions.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.builder,
    this.fillColor,
    this.tabTrailing,
    this.tabs,
  });

  final String title;
  final Color? fillColor;
  final WidgetBuilder builder;
  final Widget? tabTrailing;
  final List<Widget>? tabs;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: fillColor,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: tabs == null
                    ? Text(
                        title,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .3,
                        ),
                      )
                    : Row(children: tabs!),
              ),
              if (tabTrailing != null) ...[
                const SizedBox(width: 12),
                tabTrailing!,
              ],
            ],
          ),
        ),
        builder(context),
      ],
    ),
  );
}

class AppButton extends StatelessWidget {
  const AppButton({
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
    final effectiveColor = color ?? context.ink;
    final effectiveForeground =
        foregroundColor ??
        (color == null ? context.canvas : WeekPactColors.black);

    return AppSurface(
      fillColor: effectiveColor,
      shape: WeekPactMetrics.buttonShape,
      borderRadius: WeekPactMetrics.controlRadius,
      builder: (context) => Container(
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
            shape: WeekPactMetrics.buttonShape,
            textStyle: const TextStyle(
              fontFamily: WeekPactType.primary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
                      AppIcon(
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

class AppNavigationItem {
  const AppNavigationItem({
    required this.label,
    required this.icon,
    required this.color,
    this.badge = false,
    this.avatar,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;

  /// Whether something there is waiting to be seen: a small dot on the icon.
  final bool badge;

  /// A picture shown in place of [icon] by a bar that draws one: the account's
  /// own photo on its tab.
  final Widget? avatar;
}

/// A floating glass tab bar, after Instagram's: a frosted squircle inset from
/// the page's edges, with content blurred behind it. Icons only, all in ink;
/// the selected one sits on a soft grey squircle that slides between
/// destinations and is drawn a little heavier, standing in for Instagram's
/// filled icon, which Hugeicons' stroke style has no counterpart for. A destination with an [AppNavigationItem.avatar] shows it
/// as a circle. A badge is a red dot at the icon's lower corner.
///
/// Meant for a Scaffold with `extendBody`, so content scrolls on behind it.
class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _height = 60.0;
  static const _inset = 5.0;
  static const _iconSize = 24.0;
  static const _avatarSize = 26.0;
  static const _maxWidth = 640.0;
  static const _red = Color(0xFFFF2D55);

  /// Continuous squircles, like the cards, at about as round a curve as a
  /// bar this short takes while keeping a straight stretch at each end; the highlight's curve is the bar's less the inset, so the
  /// two stay concentric.
  static const _barCurve = 40.0;
  static const _barShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(_barCurve)),
  );
  static const _highlightShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(_barCurve - _inset)),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = dark
        ? const Color(0xFF1C1C1E).withValues(alpha: .72)
        : Colors.white.withValues(alpha: .78);
    final rim = dark
        ? Colors.white.withValues(alpha: .14)
        : Colors.white.withValues(alpha: .9);
    final highlight = dark
        ? Colors.white.withValues(alpha: .16)
        : Colors.black.withValues(alpha: .09);
    final ink = dark ? Colors.white : const Color(0xFF0C0C0C);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, _maxWidth);
          final segment = items.isEmpty
              ? 0.0
              : (width - _inset * 2) / items.length;
          return Center(
            heightFactor: 1,
            child: Container(
              width: width,
              height: _height,
              decoration: ShapeDecoration(
                shape: _barShape,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .4 : .12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: const ShapeBorderClipper(shape: _barShape),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: glass,
                      shape: _barShape.copyWith(side: BorderSide(color: rim)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(_inset),
                      child: Stack(
                        children: [
                          AnimatedPositionedDirectional(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            start: segment * selectedIndex,
                            top: 0,
                            bottom: 0,
                            width: segment,
                            child: DecoratedBox(
                              key: const ValueKey('nav-sliding-highlight'),
                              decoration: ShapeDecoration(
                                color: highlight,
                                shape: _highlightShape,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < items.length; i++)
                                Expanded(child: _destination(i, ink, glass)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _destination(int i, Color ink, Color glass) {
    final item = items[i];
    final selected = selectedIndex == i;
    return Semantics(
      selected: selected,
      button: true,
      label: item.badge ? '${item.label}, new' : item.label,
      child: GestureDetector(
        key: ValueKey('nav-${item.label.toLowerCase()}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(i),
        // The label above says it all; an avatar's initials would only
        // repeat the person to them.
        child: ExcludeSemantics(
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                item.avatar != null
                    ? SizedBox.square(
                        dimension: _avatarSize,
                        child: ClipOval(child: item.avatar),
                      )
                    : HugeIcon(
                        icon: item.icon,
                        size: _iconSize,
                        color: ink,
                        strokeWidth: selected ? 1.9 : 1.5,
                      ),
                if (item.badge)
                  PositionedDirectional(
                    end: -4,
                    bottom: -3,
                    child: Container(
                      key: ValueKey('nav-badge-${item.label.toLowerCase()}'),
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the cursor at the end of [controller]'s text whenever [child] — a
/// text field — takes focus.
///
/// On iOS the tap that focuses a field lands the cursor on the nearer edge of
/// the word under it, so a tap in the field's left padding, or on the left of
/// a short word, opened a filled field with the cursor blinking before its
/// first letter: it read as that letter being cut off. Arriving in a field
/// now starts at the end of what is there; once in, a tap still places the
/// cursor where it lands.
///
/// The tap sets its selection before focus is applied, so this runs after it
/// and has the last word.
class CaretAtEndOnFocus extends StatelessWidget {
  const CaretAtEndOnFocus({
    super.key,
    required this.controller,
    required this.child,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (!focused) return;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    },
    child: child,
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
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
    this.minLines,
    this.maxLines = 1,
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

  /// Lines the field opens at and grows to, for text longer than a name.
  final int? minLines;
  final int? maxLines;

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
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
        ],
        AppSurface(
          raised: false,
          borderRadius: WeekPactMetrics.controlRadius,
          builder: (context) => CaretAtEndOnFocus(
            controller: controller,
            child: TextFormField(
              controller: controller,
              validator: validator,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              obscureText: obscureText,
              autofillHints: autofillHints,
              minLines: minLines,
              maxLines: maxLines,
              style: TextStyle(
                color: context.fieldInk,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: context.muted,
                  fontWeight: FontWeight.w500,
                ),
                // The rounded AppSurface owns the fill and outline. A second
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
                        tooltip: obscureText
                            ? 'Show password'
                            : 'Hide password',
                        icon: AppIcon(
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
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

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
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;

  /// Whether something there is waiting to be seen: a small dot on the icon.
  final bool badge;
}

/// A rounded bar that floats over the page's bottom edge, as wide as the page.
/// Unselected destinations show just their icon; the selected one sits on an
/// ink highlight that slides across and widens to show its label.
///
/// Meant for a Scaffold with `extendBody`, so content scrolls on behind it;
/// pages keep their last content clear of it with the bottom padding the
/// Scaffold then reports.
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

  static const _inset = 5.0;

  /// The bar and its highlight are continuous squircles, like the cards, but
  /// at a smaller curve than a card's: on a box this short a card's curve
  /// would round the ends away entirely, and the raised edge below would show
  /// along their sides. This is about as round as the bar gets while keeping
  /// a straight stretch at each end. The highlight's curve is the bar's less
  /// the inset, so the two stay concentric.
  static const _barCurve = 32.0;
  static const _barShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(_barCurve)),
  );
  static const _highlightShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(_barCurve - _inset)),
  );
  static const _height = 48.0;
  static const _iconSize = 22.0;
  static const _labelGap = 8.0;

  /// The narrowest a collapsed destination may get, before a long label at a
  /// large text scale is cut short to keep it.
  static const _minCollapsed = 52.0;

  /// No wider than the pages it sits under.
  static const _maxWidth = 640.0;

  TextStyle _labelStyle(Color color) => TextStyle(
    fontFamily: WeekPactType.secondary,
    fontFamilyFallback: WeekPactType.secondaryFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: color,
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 12),
    child: LayoutBuilder(
      builder: (context, constraints) => Center(
        heightFactor: 1,
        child: _pill(context, math.min(constraints.maxWidth, _maxWidth)),
      ),
    ),
  );

  Widget _pill(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    // Inside the border and inset.
    final inner = math.max(0.0, width - (_inset + 1) * 2);
    // Room left for the selected label once every destination has its icon;
    // a longer label, at a large text scale, is cut short with an ellipsis.
    final labelRoom = math.max(
      0.0,
      inner - _minCollapsed * items.length - _labelGap,
    );
    final labelWidths = [
      for (final item in items)
        (TextPainter(
          text: TextSpan(
            text: item.label,
            // As the Text below will draw it, inherited spacing and all.
            style: DefaultTextStyle.of(context).style
                .merge(_labelStyle(context.ink)),
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout()).width.ceilToDouble().clamp(0.0, labelRoom),
    ];
    final highlightColor = context.isDark
        ? WeekPactColors.navSelected
        : context.ink;
    final barColor = context.isDark
        ? WeekPactColors.darkSurface
        : WeekPactColors.cream;
    final barEdge = context.isDark
        ? WeekPactColors.darkBorder
        : WeekPactColors.pendingCheckIns;

    return Container(
      width: width,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: barColor,
        shape: _barShape.copyWith(side: BorderSide(color: barEdge)),
        shadows: [
          BoxShadow(color: barEdge, offset: WeekPactMetrics.raisedOffset),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: selectedIndex.toDouble(),
          end: selectedIndex.toDouble(),
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        builder: (context, position, _) {
          // How selected each destination is, 0 to 1, as the highlight
          // travels between them.
          final selection = [
            for (var i = 0; i < items.length; i++)
              (1 - (position - i).abs()).clamp(0.0, 1.0),
          ];
          // The selected destination grows by its label; the rest share
          // what is left of the bar equally.
          final growth = [
            for (var i = 0; i < items.length; i++)
              (_labelGap + labelWidths[i]) * selection[i],
          ];
          final share = items.isEmpty
              ? 0.0
              : (inner - growth.fold(0.0, (a, b) => a + b)) / items.length;
          final widths = [
            for (var i = 0; i < items.length; i++) share + growth[i],
          ];
          // The highlight starts part-way through the destination it is
          // leaving and spans the widths it is between, so it moves with
          // them and lands exactly on the selected one.
          var highlightStart = 0.0;
          var highlightWidth = 0.0;
          for (var i = 0; i < items.length; i++) {
            highlightStart += widths[i] * (position - i).clamp(0.0, 1.0);
            highlightWidth += widths[i] * selection[i];
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (items.isNotEmpty)
                PositionedDirectional(
                  start: highlightStart,
                  top: 0,
                  bottom: 0,
                  width: highlightWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('nav-sliding-highlight'),
                      decoration: ShapeDecoration(
                        color: highlightColor,
                        shape: _highlightShape,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    _destination(
                      context,
                      i,
                      widths[i],
                      selection[i],
                      labelWidths[i],
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    int i,
    double width,
    double selection,
    double labelWidth,
  ) {
    final item = items[i];
    final color = Color.lerp(context.ink, context.canvas, selection)!;
    return Semantics(
      selected: selectedIndex == i,
      button: true,
      label: item.badge ? '${item.label}, new' : item.label,
      child: Tooltip(
        message: item.label,
        child: Material(
          color: Colors.transparent,
          shape: _highlightShape,
          child: InkWell(
            key: ValueKey('nav-${item.label.toLowerCase()}'),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            customBorder: _highlightShape,
            onTap: () => onSelected(i),
            child: SizedBox(
              width: width,
              height: _height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      HugeIcon(
                        icon: item.icon,
                        size: _iconSize,
                        color: color,
                        strokeWidth: 1.6,
                      ),
                      if (item.badge)
                        PositionedDirectional(
                          top: -2,
                          end: -3,
                          child: Container(
                            key: ValueKey(
                              'nav-badge-${item.label.toLowerCase()}',
                            ),
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: WeekPactColors.salmon,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.isDark
                                    ? WeekPactColors.darkSurface
                                    : WeekPactColors.cream,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  ClipRect(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: selection,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: _labelGap,
                        ),
                        child: ExcludeSemantics(
                          child: SizedBox(
                            width: labelWidth,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: _labelStyle(color),
                            ),
                          ),
                        ),
                      ),
                    ),
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
          builder: (context) => TextFormField(
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
                      tooltip: obscureText ? 'Show password' : 'Hide password',
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
      ],
    );
  }
}

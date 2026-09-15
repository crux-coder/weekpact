import 'package:flutter/material.dart';

import 'app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.builder,
    this.fillColor,
    this.borderWidth = WeekPactMetrics.border,
    this.borderRadius = 18,
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
            ? ContinuousRectangleBorder(borderRadius: radius * (40 / 18))
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
                          fontWeight: FontWeight.w700,
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
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;
}

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
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: context.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.transparent, width: 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: selectedIndex.toDouble(),
            end: selectedIndex.toDouble(),
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          builder: (context, position, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              if (items.isNotEmpty)
                PositionedDirectional(
                  start: constraints.maxWidth / items.length * position,
                  top: 0,
                  bottom: 0,
                  width: constraints.maxWidth / items.length,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('nav-sliding-highlight'),
                      decoration: ShapeDecoration(
                        color: context.isDark
                            ? const Color(0xFFD8D3C8)
                            : context.ink,
                        shape: ContinuousRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: Color.lerp(
                              context.isDark
                                  ? const Color(0xFFD8D3C8)
                                  : context.ink,
                              context.canvas,
                              .28,
                            )!,
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: Color.lerp(
                              context.isDark
                                  ? const Color(0xFFD8D3C8)
                                  : context.ink,
                              context.canvas,
                              .24,
                            )!,
                            offset: WeekPactMetrics.raisedOffset,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: selectedIndex == i,
                        label: items[i].label,
                        child: Tooltip(
                          message: items[i].label,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              key: ValueKey(
                                'nav-${items[i].label.toLowerCase()}',
                              ),
                              splashFactory: NoSplash.splashFactory,
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => onSelected(i),
                              child: SizedBox(
                                height:
                                    42 +
                                    MediaQuery.textScalerOf(context).scale(14),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AppIcon(
                                      icon: items[i].icon,
                                      color: Color.lerp(
                                        context.ink,
                                        context.canvas,
                                        1 -
                                            (position - i).abs().clamp(
                                              0.0,
                                              1.0,
                                            ),
                                      ),
                                      size: 23,
                                    ),
                                    const SizedBox(height: 3),
                                    ExcludeSemantics(
                                      child: Text(
                                        items[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontFamilyFallback: const ['Arial'],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color.lerp(
                                            context.ink,
                                            context.canvas,
                                            1 -
                                                (position - i).abs().clamp(
                                                  0.0,
                                                  1.0,
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
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
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

import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';

const homeInk = WeekPactColors.black;
const homePaper = Color(0xFFECEDEC);

extension HomePanelTheme on BuildContext {
  Color get homePanel =>
      isDark ? WeekPactColors.activitySurface : WeekPactColors.stone;
}

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.canvas, child: child);
}

/// Solid color panels with an optional raised bottom edge.
class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.tint = WeekPactColors.stone,
    this.radius = WeekPactMetrics.cardRadius,
    this.shape,
    this.padding = EdgeInsets.zero,
    this.outlined = true,
    this.outlineColor,
    this.raised = false,
    this.depth = WeekPactMetrics.controlDepth,
  });
  final Widget child;
  final Color tint;
  final double radius;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry padding;
  final bool outlined;
  final Color? outlineColor;
  final bool raised;
  final double depth;
  @override
  Widget build(BuildContext context) {
    final surfaceShape =
        shape ??
        ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(radius * (40 / 18)),
        );
    final surface = AppSurface(
      fillColor: tint,
      raised: false,
      resolveTone: false,
      borderRadius: radius,
      shape: surfaceShape,
      borderWidth: outlined ? WeekPactMetrics.border : 0,
      outlineColor: outlined
          ? outlineColor ?? homeInk.withValues(alpha: .10)
          : Colors.transparent,
      builder: (context) => Padding(padding: padding, child: child),
    );
    if (!raised) return surface;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: surfaceShape,
        shadows: [
          BoxShadow(
            color: Color.lerp(tint, Colors.black, .24)!,
            offset: Offset(0, depth),
          ),
        ],
      ),
      child: surface,
    );
  }
}

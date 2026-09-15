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

/// Flat color panels with a subtle outline and no shadow.
class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.tint = WeekPactColors.stone,
    this.radius = WeekPactMetrics.cardRadius,
    this.padding = EdgeInsets.zero,
    this.outlined = true,
  });
  final Widget child;
  final Color tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool outlined;
  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: tint,
    resolveTone: false,
    borderRadius: radius,
    borderWidth: outlined ? WeekPactMetrics.border : 0,
    outlineColor: outlined
        ? homeInk.withValues(alpha: .10)
        : Colors.transparent,
    builder: (context) => Padding(padding: padding, child: child),
  );
}

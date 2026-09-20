import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';

const homeInk = WeekPactColors.black;

/// Light ink for Home's dark fills — the canvas colour, read as paper.
const homePaper = WeekPactColors.lightCanvas;

/// The inset every card on Home holds its content at, on all four sides. It is
/// `WeekPactMetrics.pageInset`, so a card's content sits the same distance from
/// the card's edge as the card sits from the screen's — the pact card and the
/// crew panel stacked above it then share one margin instead of each carrying
/// its own. Nothing on a Home card should spell its own padding.
const homeCardInset = EdgeInsets.all(WeekPactMetrics.pageInset);

/// Secondary ink on a pact tint: the card's own ink let down into the fill
/// rather than a fixed grey, so it stays in family — warm on lemon, cool on
/// lavender — instead of going muddy the way one neutral does across ten
/// tints.
///
/// `.6` lands it at 3.4:1 on the palette's deepest tint and 3.9:1 on its
/// lightest, which is the band `WeekPactColors.mutedLight` already occupies on
/// these same fills elsewhere in the app. Higher — `.72` clears 4.5:1 — and it
/// stops reading as secondary at all: near-black at 72% on lemon is still
/// near-black, and the hierarchy it is there to draw disappears.
final homeMutedInk = homeInk.withValues(alpha: .6);

extension HomePanelTheme on BuildContext {
  Color get homePanel => isDark ? WeekPactDarkCard.fill : WeekPactColors.stone;
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
    this.radius = WeekPactMetrics.controlRadius,
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
          borderRadius: BorderRadius.circular(WeekPactMetrics.curveFor(radius)),
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

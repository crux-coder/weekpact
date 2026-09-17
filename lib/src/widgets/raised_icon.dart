import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/weekpact_theme.dart';

/// An opt-in raised icon face; the enclosing control owns interaction.
class RaisedIcon extends StatelessWidget {
  const RaisedIcon({super.key, required this.icon, this.size = 24, this.color});

  final List<List<dynamic>> icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? context.ink;
    final dark = ink.computeLuminance() > .5;
    // The same neutral pair the rest of the app raises with: a pale face on
    // a muted edge, or the dark canvas on its own lighter border.
    final face = dark ? WeekPactColors.darkSurface : WeekPactColors.cream;
    final edge = dark ? WeekPactColors.darkBorder : WeekPactColors.pendingEdge;
    return SizedBox.square(
      dimension: size + 8,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: face,
          shape: WeekPactMetrics.buttonShape.copyWith(
            side: BorderSide(color: edge),
          ),
          shadows: [
            BoxShadow(color: edge, offset: WeekPactMetrics.raisedOffset),
          ],
        ),
        child: Center(
          child: HugeIcon(icon: icon, size: size, color: ink),
        ),
      ),
    );
  }
}

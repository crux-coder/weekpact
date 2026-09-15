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
    final face = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE4E4E4);
    final edge = dark ? const Color(0xFF5A5A5A) : const Color(0xFFA0A0A0);
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

/// Flat filled squircle for decorative pact icons.
ShapeDecoration pactIconDecoration(Color face, {double radius = 10}) =>
    ShapeDecoration(
      color: face,
      shape: ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(radius * 2.8),
      ),
    );

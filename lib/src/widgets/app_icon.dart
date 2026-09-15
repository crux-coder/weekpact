import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/weekpact_theme.dart';

/// A flat Hugeicons glyph with consistent spacing across controls and labels.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.5,
  });

  final List<List<dynamic>> icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size + 8,
    child: Center(
      child: HugeIcon(
        icon: icon,
        size: size,
        color: color ?? IconTheme.of(context).color ?? context.ink,
        strokeWidth: strokeWidth,
      ),
    ),
  );
}

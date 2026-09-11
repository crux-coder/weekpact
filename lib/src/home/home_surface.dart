import 'package:flutter/material.dart';

const homeInk = Color(0xFF191B19);
const homePaper = Color(0xFFECEDEC);

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: homeInk, child: child);
}

/// Flat color panels with a subtle outline and no shadow.
class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.tint = const Color(0xFFE1EDD6),
    this.radius = 12,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final Color tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: tint,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: homeInk.withValues(alpha: .10), width: 1),
    ),
    borderOnForeground: true,
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

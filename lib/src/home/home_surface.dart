import 'package:flutter/material.dart';

const homeInk = Color(0xFF191B19);
const homePaper = Color(0xFFECEDEC);

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF7F3E9),
    child: Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top + 10,
          child: const ColoredBox(color: Color(0xFF191B19)),
        ),
        child,
      ],
    ),
  );
}

/// Flat color panels with a subtle outline and no shadow.
class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.tint = const Color(0xFFE1EDD6),
    this.radius = 16,
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

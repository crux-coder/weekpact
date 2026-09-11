import 'dart:ui';

import 'package:flutter/material.dart';

/// A quiet, static backdrop: soft light pools without a scenic illustration.
class HomeGlassBackground extends StatelessWidget {
  const HomeGlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF29234D), Color(0xFF151B34), Color(0xFF101929)],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1, -.7),
                  radius: 1.15,
                  colors: [
                    const Color(0xFF9E78EB).withValues(alpha: .35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.1, .55),
                  radius: .85,
                  colors: [
                    const Color(0xFF64B9C3).withValues(alpha: .2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

/// A translucent surface with background blur and a subtle light-catching rim.
class HomeGlassSurface extends StatelessWidget {
  const HomeGlassSurface({
    super.key,
    required this.child,
    this.tint = const Color(0xFFB4A4EE),
    this.radius = 26,
    this.sheen = 0,
    this.backingOpacity = 0,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final Color tint;
  final double radius;
  final double sheen;
  final double backingOpacity;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                [
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: sheen),
                        Color.alphaBlend(
                          tint.withValues(alpha: .18),
                          const Color(0x183B405A),
                        ),
                      ),
                      const Color(0x303D355A),
                      const Color(0x18343952),
                    ]
                    .map(
                      (color) => Color.alphaBlend(
                        color,
                        const Color(0xFF292B45)
                            .withValues(alpha: backingOpacity),
                      ),
                    )
                    .toList(),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .19)),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A superellipse with exponent 3: rounder than a classic squircle, with continuously curved sides.
class AvatarShape extends OutlinedBorder {
  const AvatarShape({super.side});

  Path _outline(Rect rect) {
    final path = Path();
    // A true superellipse has continuously curved sides, without straight runs
    // or circular corner arcs. Dense samples keep small photo clips smooth.
    for (var i = 0; i < 256; i++) {
      final angle = 2 * math.pi * i / 256;
      final cosine = math.cos(angle);
      final sine = math.sin(angle);
      final x =
          rect.center.dx +
          rect.width / 2 * cosine.sign * math.pow(cosine.abs(), 2 / 3);
      final y =
          rect.center.dy +
          rect.height / 2 * sine.sign * math.pow(sine.abs(), 2 / 3);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none && !rect.isEmpty) {
      canvas.drawPath(_outline(rect.deflate(side.width / 2)), side.toPaint());
    }
  }

  @override
  AvatarShape scale(double t) => AvatarShape(side: side.scale(t));

  @override
  AvatarShape copyWith({BorderSide? side}) =>
      AvatarShape(side: side ?? this.side);
}

class AvatarClip extends StatelessWidget {
  const AvatarClip({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const ShapeBorderClipper(shape: AvatarShape()),
    child: child,
  );
}

class FlatAvatar extends StatelessWidget {
  const FlatAvatar({
    super.key,
    this.radius = 20,
    required this.backgroundColor,
    required this.child,
    this.foregroundColor,
  });
  final Color? foregroundColor;
  final double radius;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => AvatarClip(
    child: SizedBox.square(
      dimension: radius * 2,
      child: ColoredBox(
        color: backgroundColor,
        child: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: child,
          ),
        ),
      ),
    ),
  );
}

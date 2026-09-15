import 'package:flutter/widgets.dart';

/// A square photo with softly bowed edges and continuous rounded corners.
class CheckInPhotoFrame extends StatelessWidget {
  const CheckInPhotoFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ClipPath(clipper: const _PhotoClipper(), child: child),
  );
}

class _PhotoClipper extends CustomClipper<Path> {
  const _PhotoClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * .5, 0)
      ..cubicTo(w * .95, 0, w, h * .05, w, h * .5)
      ..cubicTo(w, h * .95, w * .95, h, w * .5, h)
      ..cubicTo(w * .05, h, 0, h * .95, 0, h * .5)
      ..cubicTo(0, h * .05, w * .05, 0, w * .5, 0)
      ..close();
  }

  @override
  bool shouldReclip(_PhotoClipper oldClipper) => false;
}

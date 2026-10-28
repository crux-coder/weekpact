import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// How every uploaded photo is encoded. A camera frame as JPEG is a tenth of
/// the same frame as PNG, and everyone in the crew downloads it.
const photoJpegQuality = 82;

/// Encodes [image] as a JPEG, off the UI isolate. Transparent pixels land on
/// white, since JPEG has no alpha and would otherwise turn them black.
Future<Uint8List> encodePhotoJpeg(ui.Image image) async {
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) throw StateError('Could not read the photo.');
  return compute(_encodeJpeg, (
    pixels: pixels.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  ));
}

Uint8List _encodeJpeg(({Uint8List pixels, int width, int height}) job) {
  final rgba = job.pixels;
  // Premultiplied, so a colour over white is the colour plus what alpha
  // leaves uncovered.
  for (var i = 0; i < rgba.length; i += 4) {
    final uncovered = 255 - rgba[i + 3];
    if (uncovered == 0) continue;
    rgba[i] += uncovered;
    rgba[i + 1] += uncovered;
    rgba[i + 2] += uncovered;
    rgba[i + 3] = 255;
  }
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: photoJpegQuality);
}

/// The content type of an uploaded photo, read from its bytes: JPEG from
/// this build, PNG from older ones and from tests.
String photoContentType(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
    ? 'image/jpeg'
    : 'image/png';

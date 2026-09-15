import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Prepares camera photos for the square check-in frame.
class CheckInCamera {
  /// Decoding and re-encoding strips EXIF, including location, before upload.
  static Future<Uint8List> prepare(Uint8List bytes) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw StateError('The photo is too large. Please retake it.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final maxSide = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = maxSide > 1920 ? 1920 / maxSide : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 1920),
        targetHeight: (descriptor.height * scale).round().clamp(1, 1920),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final source = frame.image;
          const ratio = 1.0;
          final width = source.width / source.height > ratio
              ? source.height * ratio
              : source.width.toDouble();
          final height = width / ratio;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawImageRect(
            source,
            ui.Rect.fromLTWH(
              (source.width - width) / 2,
              (source.height - height) / 2,
              width,
              height,
            ),
            const ui.Rect.fromLTWH(0, 0, 1024, 1024),
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(1024, 1024);
            try {
              final result = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (result == null || result.lengthInBytes > 5 * 1024 * 1024) {
                throw StateError('Please retake a smaller photo.');
              }
              return result.buffer.asUint8List();
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A picture just taken: what the camera handed over, to show at once, and
/// the upload-ready version, made in the background and awaited only when the
/// check-in is saved.
class CapturedPhoto {
  CapturedPhoto({required this.preview, required this.prepare});

  /// The bytes straight from the camera or the injected capture. Shown as
  /// soon as they exist, so the shutter feels instant.
  final Uint8List preview;

  /// Makes the upload-ready bytes. Callers go through [prepared] instead.
  final Future<Uint8List> Function() prepare;
  Future<Uint8List>? _prepared;

  /// The photo as it will be uploaded. Started on first read and cached, so
  /// a save that comes seconds after the shutter usually finds it done.
  Future<Uint8List> get prepared => _prepared ??= prepare();

  /// Kicks the preparation off without waiting for it; a failure surfaces
  /// again when [prepared] is awaited at save time.
  void warm() => prepared.ignore();
}

/// Prepares camera photos for upload: the whole frame the person saw, scaled
/// to a fixed long side so a check-in never outgrows the bucket.
class CheckInCamera {
  /// The longest side of a prepared photo, in pixels. A phone frame at this
  /// size encodes to roughly the same PNG the old 1024 square did.
  static const longSide = 1280;

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
      final scale = maxSide > longSide ? longSide / maxSide : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, longSide),
        targetHeight: (descriptor.height * scale).round().clamp(1, longSide),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final source = frame.image;
          final longest = source.width > source.height
              ? source.width
              : source.height;
          final width = (source.width * longSide / longest).round().clamp(
            1,
            longSide,
          );
          final height = (source.height * longSide / longest).round().clamp(
            1,
            longSide,
          );
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawImageRect(
            source,
            ui.Rect.fromLTWH(
              0,
              0,
              source.width.toDouble(),
              source.height.toDouble(),
            ),
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(width, height);
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

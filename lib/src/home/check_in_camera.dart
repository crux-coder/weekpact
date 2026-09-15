import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A camera-only capture, cropped to the same square frame shown before submission.
class CheckInCamera {
  static const _pendingKey = 'pending-check-in-camera';

  static Future<Uint8List?> capture({
    required String userId,
    required String crewId,
    required String pactId,
    required String today,
  }) async {
    final picker = ImagePicker();
    final prefs = await SharedPreferences.getInstance();
    final target = jsonEncode([userId, crewId, pactId, today]);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final pending = prefs.getString(_pendingKey);
      final recovered = await picker.retrieveLostData();
      if (pending == target && recovered.files?.isNotEmpty == true) {
        await prefs.remove(_pendingKey);
        return prepare(await recovered.files!.first.readAsBytes());
      }
    }
    await prefs.setString(_pendingKey, target);
    try {
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1440,
        maxHeight: 1920,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (photo == null) return null;
      if (await photo.length() > 20 * 1024 * 1024) {
        throw StateError('The photo is too large. Please retake it.');
      }
      return await prepare(await photo.readAsBytes());
    } finally {
      await prefs.remove(_pendingKey);
    }
  }

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

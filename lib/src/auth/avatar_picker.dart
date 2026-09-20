import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

/// How a screen asks for a photo. Tests hand in their own bytes rather than
/// waiting on a native picker that has no gallery to open.
typedef AvatarPicker = Future<Uint8List?> Function();

/// The one path a profile photo takes into the app: the picker, then bounded
/// PNG bytes. Onboarding and the profile editor both save through
/// `completeOnboarding`, so they both have to arrive at the same bytes.
Future<Uint8List?> pickAvatarPhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  return file == null ? null : prepareAvatarPhoto(file);
}

/// Re-encodes a bounded image so storage receives PNG bytes without photo
/// metadata.
Future<Uint8List> prepareAvatarPhoto(XFile file) async {
  if (await file.length() > 20 * 1024 * 1024) {
    throw StateError('Choose a photo smaller than 20 MB.');
  }
  final bytes = await file.readAsBytes();
  final descriptor = await ui.ImmutableBuffer.fromUint8List(bytes);
  final imageDescriptor = await ui.ImageDescriptor.encoded(descriptor);
  try {
    final maxSide = imageDescriptor.width > imageDescriptor.height
        ? imageDescriptor.width
        : imageDescriptor.height;
    final scale = maxSide > 512 ? 512 / maxSide : 1.0;
    final codec = await imageDescriptor.instantiateCodec(
      targetWidth: (imageDescriptor.width * scale).round().clamp(1, 512),
      targetHeight: (imageDescriptor.height * scale).round().clamp(1, 512),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null || data.lengthInBytes > 5 * 1024 * 1024) {
          throw StateError('Choose a smaller photo.');
        }
        return data.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    imageDescriptor.dispose();
    descriptor.dispose();
  }
}

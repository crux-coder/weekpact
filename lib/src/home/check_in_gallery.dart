import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// The gallery's way into a check-in: the system picker, then the chosen
/// picture's bytes, or null when the person backed out. The bytes are shown
/// as they are and prepared for upload the same way a camera shot is.
Future<Uint8List?> pickCheckInPhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1920,
    maxHeight: 1920,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw StateError('Choose a photo smaller than 20 MB.');
  }
  return file.readAsBytes();
}

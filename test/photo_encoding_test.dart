import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/photo_encoding.dart';

void main() {
  testWidgets('photos encode as JPEG, with transparency laid on white', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Left half solid red, right half fully transparent.
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 8, 16),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      picture.dispose();

      final jpeg = await encodePhotoJpeg(image);
      image.dispose();

      expect(photoContentType(jpeg), 'image/jpeg');
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 16);
      expect(frame.image.height, 16);
      final pixels = (await frame.image.toByteData())!;
      int channel(int x, int y, int c) => pixels.getUint8((y * 16 + x) * 4 + c);
      // Red stays red; the transparent half is white, not black.
      expect(channel(2, 8, 0), greaterThan(200));
      expect(channel(2, 8, 1), lessThan(60));
      for (var c = 0; c < 3; c++) {
        expect(channel(13, 8, c), greaterThan(230));
      }
      frame.image.dispose();
      codec.dispose();
    });
  });

  test('content type follows the bytes, so older PNGs still say so', () {
    expect(
      photoContentType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
      'image/png',
    );
    expect(
      photoContentType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class AppShare {
  Future<void> text(String text, Rect origin);
  Future<void> image(Uint8List png, Rect origin);
}

class NativeAppShare implements AppShare {
  const NativeAppShare();
  @override
  Future<void> text(String text, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  @override
  Future<void> image(Uint8List png, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png')],
        fileNameOverrides: ['weekpact-week.png'],
        sharePositionOrigin: origin,
      ),
    );
  }
}

Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

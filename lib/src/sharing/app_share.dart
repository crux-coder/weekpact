import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class AppShare {
  Future<void> text(String text, Rect origin);
}

class NativeAppShare implements AppShare {
  const NativeAppShare();
  @override
  Future<void> text(String text, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }
}

Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

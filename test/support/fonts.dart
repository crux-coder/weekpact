import 'dart:io';

import 'package:flutter/services.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

/// The app's real face, in every weight it ships.
///
/// The default test font has square, fixed metrics, so a layout that overflows
/// in the app can still fit in a test — and one that fits can overflow. Any
/// test measuring a real layout, or capturing a preview, loads this first.
Future<void> loadAppFont() async {
  final loader = FontLoader(WeekPactType.primary);
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final file = File('assets/fonts/${WeekPactType.primary}-$weight.ttf');
    if (file.existsSync()) {
      loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
}

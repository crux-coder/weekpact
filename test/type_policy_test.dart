import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app source stays inside the type scale', () {
    // 400 body, 500 label, 600 emphasis, 700 display. Nothing heavier ships,
    // so a weight above 700 would render as bold anyway while reading in the
    // source as though it were heavier — and Rubik at 800 or 900 was what made
    // the app shout in the first place.
    final tooHeavy = RegExp(r'FontWeight\.(w800|w900|bold|black|extraBold)\b');
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (tooHeavy.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

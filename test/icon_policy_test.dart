import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app source uses Hugeicons exclusively', () {
    final otherIcons = RegExp(
      r'\b(?:Icons|CupertinoIcons)\.|\bIcon\s*\(|\bIconData\b',
    );
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (otherIcons.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

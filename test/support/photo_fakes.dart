import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_ui.dart';

final testCheckInPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNYebIDAAQZAftlLZ1qAAAAAElFTkSuQmCC',
);
Future<Uint8List?> captureTestCheckInPhoto() async => testCheckInPhoto;
Future<void> takeTestPhoto(WidgetTester tester) async {
  final take = find.byKey(const ValueKey('take-picture'));
  await tester.ensureVisible(take);
  await tester.tap(take);
  await tester.pumpUi();
}

Future<void> submitTestPhoto(WidgetTester tester) async {
  if (find.byKey(const ValueKey('take-picture')).evaluate().isNotEmpty) {
    await takeTestPhoto(tester);
  }
  final submit = find.byKey(const ValueKey('submit-photo-check-in'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpUi();
}

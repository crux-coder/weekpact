import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_ui.dart';

final testCheckInPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNYebIDAAQZAftlLZ1qAAAAAElFTkSuQmCC',
);
Future<Uint8List?> captureTestCheckInPhoto() async => testCheckInPhoto;
Future<void> submitTestPhoto(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('submit-photo-check-in'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpUi();
}

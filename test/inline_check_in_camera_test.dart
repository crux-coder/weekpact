import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_photo_frame.dart';
import 'package:weekpact/src/home/inline_check_in_camera.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

const rear = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

class FakeCamera extends CameraController {
  FakeCamera(CameraDescription description)
    : super(description, ResolutionPreset.high, enableAudio: false);
  Completer<void>? initializing;
  Completer<XFile>? taking;
  Object? initializeError;
  int photos = 0;
  bool closed = false;
  @override
  Future<void> initialize() async {
    await initializing?.future;
    if (initializeError != null) throw initializeError!;
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }

  @override
  Widget buildPreview() => const ColoredBox(
    key: ValueKey('live-camera-feed'),
    color: Color(0xFF454B4E),
  );
  @override
  Future<XFile> takePicture() async {
    photos++;
    return taking?.future ??
        XFile.fromData(testCheckInPhoto, mimeType: 'image/png');
  }

  @override
  Future<void> dispose() async {
    closed = true;
    await super.dispose();
  }
}

Future<void> mountCamera(
  WidgetTester tester,
  CameraController Function(CameraDescription) create, {
  ValueChanged<Uint8List>? captured,
  ValueChanged<bool>? busy,
  Future<Uint8List> Function(Uint8List)? prepare,
  List<CameraDescription> cameras = const [rear, front],
}) async {
  VoidCallback? action;
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => Column(
            children: [
              InlineCheckInCamera(
                listCameras: () async => cameras,
                createController: create,
                preparePhoto: prepare ?? (bytes) async => bytes,
                onCaptured: captured ?? (_) {},
                onBusyChanged: busy ?? (_) {},
                onActionChanged: (next) => update(() => action = next),
              ),
              TextButton(onPressed: action, child: const Text('TAKE PICTURE')),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  testWidgets(
    'live preview is clipped and uses the parent shutter without camera switching',
    (tester) async {
      final cameras = <FakeCamera>[];
      await mountCamera(tester, (description) {
        final camera = FakeCamera(description);
        cameras.add(camera);
        return camera;
      });
      expect(cameras.single.description, rear);
      expect(cameras.single.enableAudio, isFalse);
      expect(
        find.descendant(
          of: find.byType(CheckInPhotoFrame),
          matching: find.byKey(const ValueKey('live-camera-feed')),
        ),
        findsOneWidget,
      );
      expect(find.text('TAKE PICTURE'), findsOneWidget);
      expect(find.byTooltip('Switch camera'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpUi();
      expect(cameras.last.closed, isTrue);
    },
  );
  testWidgets('permission denial stays in the drawer and retries', (
    tester,
  ) async {
    var count = 0;
    await mountCamera(
      tester,
      (description) => FakeCamera(description)
        ..initializeError = count++ == 0
            ? CameraException('CameraAccessDenied', 'denied')
            : null,
    );
    expect(
      find.textContaining('Allow camera access in Settings'),
      findsOneWidget,
    );
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
  });
  testWidgets('no camera shows a recoverable inline empty state', (
    tester,
  ) async {
    await mountCamera(tester, FakeCamera.new, cameras: []);
    expect(find.textContaining('No camera found'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsNothing);
  });
  testWidgets('capture processes the photo and guards repeated shutter taps', (
    tester,
  ) async {
    final camera = FakeCamera(rear)..taking = Completer<XFile>();
    final result = Completer<Uint8List>();
    final busy = <bool>[];
    await mountCamera(
      tester,
      (_) => camera,
      captured: result.complete,
      busy: busy.add,
      cameras: [rear],
    );
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    expect(camera.photos, 1);
    expect(busy, [true]);
    camera.taking!.complete(
      XFile.fromData(testCheckInPhoto, mimeType: 'image/png'),
    );
    await tester.pumpUi();
    expect(result.isCompleted, isTrue);
    expect(await result.future, testCheckInPhoto);
    await tester.pumpUi();
    expect(busy, [true, false]);
  });
  testWidgets('background releases camera, resume reopens it', (tester) async {
    final cameras = <FakeCamera>[];
    await mountCamera(tester, (description) {
      final camera = FakeCamera(description);
      cameras.add(camera);
      return camera;
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpUi();
    expect(cameras.first.closed, isTrue);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpUi();
    expect(cameras.length, 2);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
  });
  testWidgets('closing during initialization releases the late controller', (
    tester,
  ) async {
    final camera = FakeCamera(rear)..initializing = Completer<void>();
    await mountCamera(tester, (_) => camera);
    await tester.pumpWidget(const SizedBox());
    camera.initializing!.complete();
    await tester.pumpUi();
    expect(camera.closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}

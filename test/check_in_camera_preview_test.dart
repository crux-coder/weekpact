import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_camera.dart';
import 'package:weekpact/src/home/check_in_camera_preview.dart';
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
  bool paused = false;
  Object? pauseError;
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
  Future<void> pausePreview() async {
    if (pauseError != null) throw pauseError!;
    paused = true;
  }

  @override
  Future<void> resumePreview() async {
    paused = false;
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
  ValueChanged<CapturedPhoto>? captured,
  ValueChanged<bool>? busy,
  Future<Uint8List> Function(Uint8List)? prepare,
  List<CameraDescription> cameras = const [rear, front],
}) async {
  VoidCallback? action;
  VoidCallback? switchLens;
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => Column(
            children: [
              Expanded(
                child: CheckInCameraPreview(
                  listCameras: () async => cameras,
                  createController: create,
                  preparePhoto: prepare ?? (bytes) async => bytes,
                  onCaptured: captured ?? (_) {},
                  onBusyChanged: busy ?? (_) {},
                  onActionChanged: (next) => update(() => action = next),
                  onSwitchChanged: (next) => update(() => switchLens = next),
                ),
              ),
              TextButton(onPressed: action, child: const Text('TAKE PICTURE')),
              TextButton(
                onPressed: switchLens,
                child: const Text('SWITCH CAMERA'),
              ),
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
    'live preview fills its box, opens on the back lens and switches to the '
    'front one',
    (tester) async {
      final cameras = <FakeCamera>[];
      await mountCamera(tester, (description) {
        final camera = FakeCamera(description);
        cameras.add(camera);
        return camera;
      });
      expect(cameras.single.description, rear);
      expect(cameras.single.enableAudio, isFalse);
      expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
      // No square frame around the feed any more: it covers the whole box.
      expect(
        tester.widget<FittedBox>(find.byType(FittedBox)).fit,
        BoxFit.cover,
      );
      expect(find.text('TAKE PICTURE'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'SWITCH CAMERA'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('SWITCH CAMERA'));
      await tester.pumpUi();
      expect(cameras.length, 2);
      expect(cameras.first.closed, isTrue);
      expect(cameras.last.description, front);
      expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpUi();
      expect(cameras.last.closed, isTrue);
    },
  );
  testWidgets('a single lens offers no switch', (tester) async {
    await mountCamera(tester, FakeCamera.new, cameras: [rear]);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'SWITCH CAMERA'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('permission denial stays on the page and retries', (
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
  testWidgets('capture hands the raw picture over at once, prepares it in the '
      'background and guards repeated shutter taps', (tester) async {
    final camera = FakeCamera(rear)..taking = Completer<XFile>();
    final result = Completer<CapturedPhoto>();
    final busy = <bool>[];
    final preparing = Completer<Uint8List>();
    var prepared = 0;
    await mountCamera(
      tester,
      (_) => camera,
      captured: result.complete,
      busy: busy.add,
      cameras: [rear],
      prepare: (bytes) {
        prepared++;
        return preparing.future;
      },
    );
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    expect(camera.photos, 1);
    expect(busy, [true]);
    // The feed holds its last frame while the camera works on the picture.
    expect(camera.paused, isTrue);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
    camera.taking!.complete(
      XFile.fromData(testCheckInPhoto, mimeType: 'image/png'),
    );
    await tester.pumpUi();
    // The raw bytes are shown before any processing has finished.
    expect(result.isCompleted, isTrue);
    final photo = await result.future;
    expect(photo.preview, testCheckInPhoto);
    expect(busy, [true, false]);
    expect(prepared, 1, reason: 'preparation starts without being asked');
    preparing.complete(Uint8List.fromList([9, 9, 9]));
    expect(await photo.prepared, [9, 9, 9]);
    expect(prepared, 1, reason: 'the prepared photo is made once and kept');
  });
  testWidgets('a failed capture lets the feed move again', (tester) async {
    final camera = FakeCamera(rear)..taking = Completer<XFile>();
    await mountCamera(tester, (_) => camera, cameras: [rear]);
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    expect(camera.paused, isTrue);
    camera.taking!.completeError(CameraException('capture', 'failed'));
    await tester.pumpUi();
    expect(camera.paused, isFalse);
    expect(find.textContaining('Could not take the photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a camera that cannot pause still takes the picture', (
    tester,
  ) async {
    final camera = FakeCamera(rear)
      ..pauseError = CameraException('pause', 'unsupported');
    final result = Completer<CapturedPhoto>();
    await mountCamera(
      tester,
      (_) => camera,
      cameras: [rear],
      captured: result.complete,
    );
    await tester.tap(find.text('TAKE PICTURE'));
    await tester.pumpUi();
    expect(camera.photos, 1);
    expect(result.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
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

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_camera_preview.dart';
import 'package:weekpact/src/home/photo_check_in_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/open_app_settings.dart';

import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

const _rear = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// A camera that fails to open with whichever error the test hands it.
class RefusingCamera extends CameraController {
  RefusingCamera(CameraDescription description, this.error)
    : super(description, ResolutionPreset.high, enableAudio: false);

  final Object? error;

  @override
  Future<void> initialize() async {
    if (error != null) throw error!;
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('live-camera-feed'), color: Colors.black);
}

/// Mounts the preview alone and collects what it says about the refusal.
Future<List<bool>> mountCamera(WidgetTester tester, Object? error) async {
  final denied = <bool>[];
  final camera = RefusingCamera(_rear, error);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: CheckInCameraPreview(
          listCameras: () async => const [_rear],
          createController: (_) => camera,
          preparePhoto: (bytes) async => bytes,
          onCaptured: (_) {},
          onBusyChanged: (_) {},
          onActionChanged: (_) {},
          onDeniedChanged: denied.add,
        ),
      ),
    ),
  );
  await tester.pumpUi();
  return denied;
}

/// Opens the page with the camera injected, so the refusal can be raised
/// without a platform channel.
Future<void> openSheet(
  WidgetTester tester, {
  required CheckInPhotoCapture capture,
  OpenAppSettings openSettings = _noSettings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => presentPhotoCheckIn(
              context,
              (_) => PhotoCheckInPage(
                pactTitle: 'Move for 30 min',
                capturePhoto: capture,
                openSettings: openSettings,
                save: (_) async {},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpUi();
  await tester.tap(find.byKey(const ValueKey('take-picture')));
  await tester.pumpUi();
}

Future<void> _noSettings() async {}

void main() {
  testWidgets('a refused camera is reported as refused, and a broken one is '
      'not', (tester) async {
    expect(
      await mountCamera(tester, CameraException('CameraAccessDenied', 'no')),
      contains(true),
      reason: 'the OS will not ask twice, so only Settings can answer this',
    );
    // Everything else is answered by trying again, which the published action
    // already is.
    expect(
      await mountCamera(tester, CameraException('CameraAccessRestricted', 'x')),
      everyElement(isFalse),
    );
    expect(
      await mountCamera(tester, CameraException('NoCamera', 'none')),
      everyElement(isFalse),
    );
    expect(await mountCamera(tester, null), everyElement(isFalse));
  });

  testWidgets('a refused camera stops being refused once it opens', (
    tester,
  ) async {
    final denied = <bool>[];
    // A fresh controller per attempt, as the widget's own factory makes: the
    // one that was refused has already been disposed by the time the retry
    // comes round.
    Object? error = CameraException('CameraAccessDenied', 'no');
    VoidCallback? retry;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => CheckInCameraPreview(
              listCameras: () async => const [_rear],
              createController: (_) => RefusingCamera(_rear, error),
              preparePhoto: (bytes) async => bytes,
              onCaptured: (_) {},
              onBusyChanged: (_) {},
              onActionChanged: (next) => update(() => retry = next),
              onDeniedChanged: denied.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(denied.last, isTrue);
    error = null;
    retry!();
    await tester.pumpUi();
    expect(denied.last, isFalse);
    expect(find.byKey(const ValueKey('live-camera-feed')), findsOneWidget);
  });

  testWidgets('a refused camera offers Settings rather than the shutter', (
    tester,
  ) async {
    var opened = 0;
    await openSheet(
      tester,
      openSettings: () async => opened++,
      capture: () async =>
          throw PlatformException(code: 'camera_access_denied'),
    );
    expect(opened, 0);
    expect(find.byKey(const ValueKey('take-picture')), findsNothing);
    expect(
      find.textContaining('Allow camera access in Settings'),
      findsOneWidget,
    );
    // The sentence alone was the dead end: it named the door without opening
    // it, and the button under it reopened the camera instead.
    await tester.tap(find.byKey(const ValueKey('open-camera-settings')));
    await tester.pumpUi();
    expect(opened, 1);
    // The page stays where it is: the person comes back to it.
    expect(find.text('OPEN SETTINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the retry under it takes the camera again', (tester) async {
    var attempts = 0;
    await openSheet(
      tester,
      capture: () async {
        if (attempts++ == 0) {
          throw PlatformException(code: 'camera_access_denied');
        }
        return testCheckInPhoto;
      },
    );
    expect(find.byKey(const ValueKey('retry-camera')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-camera')));
    await tester.pumpUi();
    expect(attempts, 2);
    // Permission granted in Settings and the picture taken, so the page is
    // back on its one call to action.
    expect(find.byKey(const ValueKey('open-camera-settings')), findsNothing);
    expect(find.text('CHECK IN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

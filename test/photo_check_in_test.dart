import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_camera.dart';
import 'package:weekpact/src/home/check_in_photo_viewer.dart';
import 'package:weekpact/src/home/photo_check_in_sheet.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';
import 'package:weekpact/src/widgets/app_sheet.dart';

import 'support/home_fakes.dart';
import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

Future<void> openDrawer(
  WidgetTester tester, {
  required CheckInPhotoCapture capture,
  required Future<void> Function(Uint8List) save,
  double textScale = 1,
  bool takePicture = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<bool>(
              context: context,
              builder: (_) => PhotoCheckInSheet(
                pactTitle: 'Move for 30 min',
                capturePhoto: capture,
                save: save,
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
  if (takePicture) await takeTestPhoto(tester);
}

class PhotoBackend extends DashboardBackend {
  int attempts = 0;
  final paths = <String>[];
  @override
  Future<Uint8List> fetchCheckInPhoto(String path) async {
    paths.add(path);
    if (attempts++ == 0) throw StateError('offline');
    return testCheckInPhoto;
  }
}

void main() {
  testWidgets('one main CTA captures first, flips, then explicitly checks in', (
    tester,
  ) async {
    var captures = 0;
    var saves = 0;
    await openDrawer(
      tester,
      takePicture: false,
      capture: () async {
        captures++;
        return testCheckInPhoto;
      },
      save: (_) async {
        saves++;
      },
    );
    expect(captures, 0);
    expect(find.byType(AppButton), findsOneWidget);
    expect(find.text('TAKE PICTURE'), findsOneWidget);
    expect(find.text('CHECK IN'), findsNothing);
    expect(find.text('RETAKE PHOTO'), findsNothing);
    expect(find.byTooltip('Switch camera'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('take-picture')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(captures, 1);
    expect(saves, 0);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
    await tester.pumpUi();
    expect(find.text('TAKE PICTURE'), findsNothing);
    expect(find.text('CHECK IN'), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
    await submitTestPhoto(tester);
    expect(saves, 1);
  });

  testWidgets('cancelled camera cannot submit and can be reopened', (
    tester,
  ) async {
    var saves = 0;
    var captures = 0;
    await openDrawer(
      tester,
      capture: () async {
        captures++;
        return null;
      },
      save: (_) async {
        saves++;
      },
    );
    expect(captures, 1);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('take-picture')))
          .onPressed,
      isNotNull,
    );
    await takeTestPhoto(tester);
    await tester.pumpUi();
    expect(captures, 2);
    expect(saves, 0);
    await tester.tap(find.byTooltip('Close photo check-in'));
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInSheet), findsNothing);
  });
  testWidgets('permission error gives a recoverable camera action', (
    tester,
  ) async {
    await openDrawer(
      tester,
      capture: () async =>
          throw PlatformException(code: 'camera_access_denied'),
      save: (_) async => fail('No photo'),
    );
    expect(
      find.textContaining('Allow camera access in Settings'),
      findsOneWidget,
    );
    expect(find.text('TAKE PICTURE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'retake returns to capture and saving retries without another picture',
    (tester) async {
      var captures = 0;
      final saved = <Uint8List>[];
      await openDrawer(
        tester,
        capture: () async => ++captures == 2 ? null : testCheckInPhoto,
        save: (bytes) async {
          saved.add(bytes);
          if (saved.length == 1) throw StateError('offline');
        },
      );
      expect(saved, isEmpty);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        1,
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('RETAKE PHOTO'));
      await tester.pumpUi();
      expect(find.byType(Image), findsNothing);
      await takeTestPhoto(tester);
      expect(find.text('CHECK IN'), findsNothing);
      await takeTestPhoto(tester);
      expect(find.byType(Image), findsOneWidget);
      await submitTestPhoto(tester);
      expect(find.textContaining('Your picture is still here'), findsOneWidget);
      await submitTestPhoto(tester);
      expect(saved, [testCheckInPhoto, testCheckInPhoto]);
      expect(captures, 3);
      expect(find.byType(PhotoCheckInSheet), findsNothing);
    },
  );
  testWidgets('saving blocks duplicate submission and dismissal', (
    tester,
  ) async {
    final saving = Completer<void>();
    var calls = 0;
    await openDrawer(
      tester,
      capture: captureTestCheckInPhoto,
      save: (_) {
        calls++;
        return saving.future;
      },
    );
    await submitTestPhoto(tester);
    await submitTestPhoto(tester);
    expect(calls, 1);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    saving.complete();
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInSheet), findsNothing);
  });
  testWidgets('small screen and large text scroll to the submit action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openDrawer(
      tester,
      capture: captureTestCheckInPhoto,
      save: (_) async {},
      textScale: 2,
    );
    await submitTestPhoto(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(PhotoCheckInSheet), findsNothing);
  });
  testWidgets('viewer retries a private download with the same path', (
    tester,
  ) async {
    final backend = PhotoBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: CheckInPhotoViewer(
            backend: backend,
            path: 'crew/photo.png',
            title: 'Read',
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('Photo unavailable'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pumpUi();
    expect(find.byType(Image), findsOneWidget);
    expect(backend.paths, ['crew/photo.png', 'crew/photo.png']);
  });
  testWidgets(
    'camera processor encodes a real 1024 by 1024 PNG and rejects invalid input',
    (tester) async {
      await tester.runAsync(() async {
        final photo = await CheckInCamera.prepare(testCheckInPhoto);
        final codec = await ui.instantiateImageCodec(photo);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1024);
        expect(frame.image.height, 1024);
        expect(photo.length, lessThan(5 * 1024 * 1024));
        frame.image.dispose();
        codec.dispose();
        await expectLater(
          CheckInCamera.prepare(Uint8List.fromList([1, 2, 3])),
          throwsA(anything),
        );
      });
    },
  );
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_camera.dart';
import 'package:weekpact/src/home/check_in_photo_viewer.dart';
import 'package:weekpact/src/home/photo_check_in_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

import 'support/home_fakes.dart';
import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

Future<void> openDrawer(
  WidgetTester tester, {
  required CheckInPhotoCapture capture,
  required Future<void> Function(Uint8List) save,
  CheckInPhotoCapture? pick,
  int daysKept = 0,
  int daysPerWeek = 0,
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
            onPressed: () => presentPhotoCheckIn(
              context,
              (_) => PhotoCheckInPage(
                pactTitle: 'Move for 30 min',
                daysKept: daysKept,
                daysPerWeek: daysPerWeek,
                capturePhoto: capture,
                pickPhoto: pick ?? () async => fail('No gallery'),
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
  testWidgets('the shutter captures first, then one CTA explicitly checks in', (
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
    // The camera fills the page: no form button, a round shutter instead.
    expect(find.byType(AppButton), findsNothing);
    expect(find.byKey(const ValueKey('take-picture')), findsOneWidget);
    expect(find.bySemanticsLabel('Take picture'), findsOneWidget);
    expect(find.text('CHECK IN'), findsNothing);
    expect(find.text('RETAKE PHOTO'), findsNothing);
    // An injected capture has no other lens to offer.
    expect(find.byTooltip('Switch camera'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('take-picture')));
    await tester.pumpUi();
    expect(captures, 1);
    expect(saves, 0);
    // The picture takes the feed's place, full size, and the shutter goes.
    expect(find.byKey(const ValueKey('take-picture')), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(find.text('CHECK IN'), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
    await submitTestPhoto(tester);
    expect(saves, 1);
  });

  testWidgets('the strip says where the week stands and what today adds', (
    tester,
  ) async {
    Future<void> open(int kept, int target) async {
      // Each case gets a fresh page over a fresh button.
      await tester.pumpWidget(const SizedBox());
      await openDrawer(
        tester,
        takePicture: false,
        capture: captureTestCheckInPhoto,
        save: (_) async {},
        daysKept: kept,
        daysPerWeek: target,
      );
    }

    await open(3, 5);
    expect(find.text('3 of 5 days'), findsOneWidget);
    expect(find.text('Today makes it 4. One more after this.'), findsOneWidget);
    expect(find.bySemanticsLabel('3 of 5 days kept this week'), findsOneWidget);
    await open(1, 5);
    expect(find.text('Today makes it 2. 3 more after this.'), findsOneWidget);
    await open(4, 5);
    expect(find.text('Today makes it 5. That’s the week.'), findsOneWidget);
    await open(5, 5);
    expect(find.text('5 of 5 days'), findsOneWidget);
    expect(
      find.text('Your week is already kept. This one’s a bonus.'),
      findsOneWidget,
    );
    // Once the picture is in, the strip is for checking in.
    await takeTestPhoto(tester);
    expect(find.byKey(const ValueKey('week-progress')), findsNothing);
    expect(find.text('CHECK IN'), findsOneWidget);
    // No target means no readout, not a readout of nothing.
    await open(0, 0);
    expect(find.byKey(const ValueKey('week-progress')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a gallery picture stands in for a shot', (tester) async {
    var captures = 0;
    final saved = <Uint8List>[];
    var picks = 0;
    await openDrawer(
      tester,
      takePicture: false,
      capture: () async {
        captures++;
        return testCheckInPhoto;
      },
      pick: () async => ++picks == 1 ? null : testCheckInPhoto,
      save: (bytes) async => saved.add(bytes),
    );
    // The gallery sits to the shutter's left, inside the card.
    final gallery = find.byKey(const ValueKey('pick-photo'));
    final shutter = find.byKey(const ValueKey('take-picture'));
    expect(
      tester.getCenter(gallery).dx,
      lessThan(tester.getCenter(shutter).dx),
    );
    expect(
      tester.getCenter(gallery).dy,
      closeTo(tester.getCenter(shutter).dy, 1),
    );
    // Backing out of the picker leaves the camera as it was.
    await tester.tap(gallery);
    await tester.pumpUi();
    expect(find.byType(Image), findsNothing);
    expect(shutter, findsOneWidget);
    // Preparing the picture runs the real image codec, which needs real time,
    // and it starts the moment the picture is chosen.
    await tester.runAsync(() async {
      await tester.tap(gallery);
      await tester.pumpUi();
      expect(find.byType(Image), findsOneWidget);
      expect(shutter, findsNothing);
      expect(captures, 0);
      await submitTestPhoto(tester);
      // The codec works on its own time; give the save a moment to follow.
      for (var i = 0; i < 50 && saved.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pumpUi();
    // Upload bytes are the prepared picture, not the file as chosen.
    expect(saved, hasLength(1));
    expect(saved.single, isNot(equals(testCheckInPhoto)));
    expect(find.byType(PhotoCheckInPage), findsNothing);
  });
  testWidgets('a gallery picture that cannot be read says so', (tester) async {
    await openDrawer(
      tester,
      takePicture: false,
      capture: captureTestCheckInPhoto,
      pick: () async => throw StateError('too big'),
      save: (_) async => fail('No photo'),
    );
    await tester.tap(find.byKey(const ValueKey('pick-photo')));
    await tester.pumpUi();
    expect(find.textContaining('Could not open that photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('take-picture')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.byKey(const ValueKey('take-picture')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await takeTestPhoto(tester);
    await tester.pumpUi();
    expect(captures, 2);
    expect(saves, 0);
    await tester.tap(find.byTooltip('Close photo check-in'));
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInPage), findsNothing);
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
    // A shutter that quietly reopens a camera the OS has already refused can
    // only fail the same way, so the refusal offers Settings and a retry.
    // See check_in_camera_permission_test.dart.
    expect(find.byKey(const ValueKey('take-picture')), findsNothing);
    expect(find.text('OPEN SETTINGS'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    // The gallery stays open to someone whose camera is not.
    expect(find.text('CHOOSE FROM GALLERY'), findsOneWidget);
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
      // No square frame: the picture is shown whole, edge to edge.
      expect(find.byType(AspectRatio), findsNothing);
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
      expect(find.byType(PhotoCheckInPage), findsNothing);
    },
  );
  testWidgets('the drawer pulls down to dismiss, but not while saving', (
    tester,
  ) async {
    final saving = Completer<void>();
    await openDrawer(
      tester,
      capture: captureTestCheckInPhoto,
      save: (_) => saving.future,
    );
    await submitTestPhoto(tester);
    // Mid-save the pull is swallowed: the drawer stays where it is.
    await tester.fling(
      find.byType(PhotoCheckInPage),
      const Offset(0, 600),
      2000,
    );
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInPage), findsOneWidget);
    saving.complete();
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInPage), findsNothing);
    // Idle, the same pull closes it without a check-in.
    await tester.tap(find.text('Open'));
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInPage), findsOneWidget);
    await tester.fling(
      find.byType(PhotoCheckInPage),
      const Offset(0, 600),
      2000,
    );
    await tester.pumpUi();
    expect(find.byType(PhotoCheckInPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
    expect(find.byType(PhotoCheckInPage), findsNothing);
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
    expect(find.byType(PhotoCheckInPage), findsNothing);
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
    'camera processor keeps the whole frame at a 1280 long side and rejects '
    'invalid input',
    (tester) async {
      await tester.runAsync(() async {
        final photo = await CheckInCamera.prepare(testCheckInPhoto);
        final codec = await ui.instantiateImageCodec(photo);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1280);
        expect(frame.image.height, 1280);
        expect(photo.length, lessThan(5 * 1024 * 1024));
        frame.image.dispose();
        codec.dispose();
        // A phone frame is taller than it is wide, and stays that way: the
        // person keeps the picture they framed rather than a square cut from
        // its middle.
        final tall = await CheckInCamera.prepare(await _pngOf(3, 4));
        final tallCodec = await ui.instantiateImageCodec(tall);
        final tallFrame = await tallCodec.getNextFrame();
        expect(tallFrame.image.width, 960);
        expect(tallFrame.image.height, 1280);
        tallFrame.image.dispose();
        tallCodec.dispose();
        await expectLater(
          CheckInCamera.prepare(Uint8List.fromList([1, 2, 3])),
          throwsA(anything),
        );
      });
    },
  );
}

/// A solid PNG of the given size, for shape checks.
Future<Uint8List> _pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF454B4E),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

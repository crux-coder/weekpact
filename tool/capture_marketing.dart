import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import '../test/support/home_fakes.dart';
import '../test/support/pump_ui.dart';

class MarketingBackend extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId) async => CrewWeek(
    today: '2026-09-14',
    weekStart: '2026-09-14',
    timezone: 'UTC',
    pacts: pacts.pacts,
    streakWeeks: 3,
    latestActivity: CrewActivity(
      pactId: 'move',
      userId: 'mila',
      createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
    ),
    members: const [
      WeekMember('', '', displayName: 'Alex Morgan'),
      WeekMember('mila', '', displayName: 'Mila Jensen'),
      WeekMember('sam', '', displayName: 'Sam Rivera'),
      WeekMember('leo', '', displayName: 'Leo Martin'),
    ],
    checkIns: const [
      PactCheckIn('move', 'mila', '2026-09-14'),
      PactCheckIn('read', '', '2026-09-14'),
    ],
  );
  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async => {
    'sam': const CrewNudgeState(CrewNudgeStatus.ready),
    'leo': const CrewNudgeState(CrewNudgeStatus.ready),
  };
}

void main() {
  testWidgets('capture current app with fictional crew', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final regular = FontLoader('RobotoCondensed')
      ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf'));
    await regular.load();
    final text = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await text.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    final key = GlobalKey();
    final backend = MarketingBackend();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: WeekPactTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(top: 52, bottom: 20)),
            child: child!,
          ),
          home: HomePage(
            user: const AuthUser(email: '', id: ''),
            authBackend: const MissingConfigurationAuthBackend(),
            crewBackend: const MissingCrewBackend(),
            homeBackend: backend,
            pactsBackend: backend.pacts,
          ),
        ),
      ),
    );
    await tester.pumpUi();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('website/public/screenshots/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home');
    await tester.tap(find.byKey(const ValueKey('pending-tile')));
    await tester.pumpUi();
    await tester.pumpUi();
    await capture('crew');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

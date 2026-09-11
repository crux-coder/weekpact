import 'dart:io';

import 'package:weekpact/src/crew/crew_backend.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/theme/theme_preference.dart';
import 'package:weekpact/src/auth/auth_backend.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

void main() {
  for (final dark in [false, true]) {
    testWidgets('main screens render in ${dark ? 'dark' : 'light'} theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthBackend();
      addTearDown(auth.dispose);
      final backend = DashboardBackend();
      const capture = ValueKey('design-capture');
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        final font = FontLoader('RobotoCondensed')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf'));
        await tester.runAsync(() => font.load());
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() => icons.load());
      }
      await tester.pumpWidget(
        ThemePreference(
          mode: dark ? ThemeMode.dark : ThemeMode.light,
          onChanged: (_) {},
          child: MaterialApp(
            theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
            home: RepaintBoundary(
              key: capture,
              child: HomePage(
                user: const AuthUser(email: 'person@example.com'),
                authBackend: auth,
                crewBackend: FakeCrewBackend()
                  ..crew = CrewDetails(
                    id: 'crew',
                    name: 'Hangboardasi',
                    timezone: 'UTC',
                    ownerId: 'person',
                    currentUserRole: 'owner',
                    members: [
                      CrewMember(
                        userId: 'person',
                        email: 'person@example.com',
                        displayName: 'Jasmin',
                        role: 'owner',
                        joinedAt: DateTime(2026),
                      ),
                      CrewMember(
                        userId: 'two',
                        email: 'jasmin@example.com',
                        displayName: 'Jasmin',
                        role: 'member',
                        joinedAt: DateTime(2026),
                      ),
                      CrewMember(
                        userId: 'three',
                        email: 'mirnes@example.com',
                        displayName: 'Mirnes',
                        role: 'member',
                        joinedAt: DateTime(2026),
                      ),
                    ],
                    pendingInvites: [
                      CrewInvite(
                        id: 'invite',
                        email: 'alex@example.com',
                        expiresAt: DateTime(2027),
                      ),
                    ],
                  ),
                goalsBackend: backend.goals,
                homeBackend: backend,
              ),
            ),
          ),
        ),
      );
      for (final tab in ['home', 'goals', 'crews', 'account']) {
        await tester.tap(find.byKey(ValueKey('nav-$tab')));
        await tester.pumpUi();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/weekpact-${dark ? 'dark' : 'light'}-$tab.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

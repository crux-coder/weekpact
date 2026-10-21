import 'dart:io';

import 'package:weekpact/src/crew/crew_backend.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/auth/auth_backend.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';

import 'package:weekpact/src/pacts/pacts_backend.dart';

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
      backend.pacts.pacts.add(
        const CrewPact(
          id: 'stretch',
          crewId: 'crew',
          title: 'Stretch',
          frequency: PactFrequency.weekly,
          daysPerWeek: 3,
          iconKey: 'yoga',
        ),
      );
      const capture = ValueKey('design-capture');
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        await tester.runAsync(loadAppFont);
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() => icons.load());
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
          // Around the navigator rather than Home, so a crew's own page,
          // pushed over the tabs, is in the picture too.
          builder: (context, child) =>
              RepaintBoundary(key: capture, child: child!),
          home: HomePage(
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
              ),
            pactsBackend: backend.pacts,
            homeBackend: backend,
          ),
        ),
      );
      for (final tab in ['home', 'crews', 'crew', 'account']) {
        if (tab == 'crew') {
          // A crew's own page, pushed from the list rather than a tab.
          await tester.tap(find.byKey(const ValueKey('crew-card-crew')));
        } else {
          await tester.tap(find.byKey(ValueKey('nav-$tab')));
        }
        await tester.pumpUi();
        expect(tester.takeException(), isNull);
        expect(find.byType(Icon), findsNothing);
        if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
          for (final preview
              in tab == 'home'
                  ? ['home', 'home-middle', 'home-last', 'home-empty']
                  : tab == 'crew'
                  ? ['crew', 'crew-pacts']
                  : [tab]) {
            if (preview == 'crew-pacts') {
              await tester.tap(find.byKey(const ValueKey('crew-tab-1')));
              await tester.pumpUi();
              expect(tester.takeException(), isNull);
            }
            if (preview == 'home-empty') {
              backend.selected.clear();
              await tester.tap(find.byKey(const ValueKey('nav-crews')));
              await tester.pumpUi();
              await tester.tap(find.byKey(const ValueKey('nav-home')));
              await tester.pumpUi();
              expect(tester.takeException(), isNull);
            } else if (preview != tab && tab == 'home') {
              await tester.drag(
                find.byKey(const ValueKey('pact-stack')),
                const Offset(-320, 0),
              );
              await tester.pumpUi();
              expect(tester.takeException(), isNull);
            }
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(capture),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/tmp/weekpact-${dark ? 'dark' : 'light'}-$preview.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        if (tab == 'crew') {
          await tester.tap(find.byTooltip('Back to crews'));
          await tester.pumpUi();
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

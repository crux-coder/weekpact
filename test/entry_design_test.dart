import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/onboarding/onboarding_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend;

void main() {
  for (final dark in [false, true]) {
    testWidgets('entry screens fit ${dark ? 'dark' : 'light'} theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeAuthBackend();
      addTearDown(backend.dispose);
      const boundaryKey = ValueKey('entry-capture');
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        final font = FontLoader('RobotoCondensed')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf'));
        await tester.runAsync(() => font.load());
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() => icons.load());
      }
      Future<void> capture(String name) async {
        await tester.pumpUi();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/entry-${dark ? 'dark' : 'light'}-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      Widget app(Widget child) => MaterialApp(
        theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
        home: RepaintBoundary(key: boundaryKey, child: child),
      );
      await tester.pumpWidget(app(AuthPage(authBackend: backend)));
      await capture('login');
      await tester.ensureVisible(find.text('New here?  CREATE ACCOUNT'));
      await tester.tap(find.text('New here?  CREATE ACCOUNT'));
      await capture('register');
      await tester.pumpWidget(
        app(
          OnboardingPage(
            backend: backend,
            user: const AuthUser(email: 'person@example.com'),
            onCompleted: (_) {},
          ),
        ),
      );
      await capture('intro');
      await tester.ensureVisible(find.text('LET’S GET STARTED'));
      await tester.tap(find.text('LET’S GET STARTED'));
      await capture('profile');
    });
  }
}

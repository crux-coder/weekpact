import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'home skeleton fits small screens and respects reduced motion ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                disableAnimations: true,
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: RepaintBoundary(
                    key: ValueKey('skeleton-capture'),
                    child: SizedBox(height: 440, child: TodaySkeleton()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('skeleton-pact-card')),
          findsOneWidget,
        );
        final fade = tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(TodaySkeleton),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fade.opacity.value, 1);
        expect(fade.opacity.isAnimating, isFalse);
        final card = tester.getRect(
          find.byKey(const ValueKey('skeleton-pact-card')),
        );
        final board = tester.getRect(
          find.byKey(const ValueKey('skeleton-crew-panel')),
        );
        expect(card.center.dx, closeTo(board.center.dx - 12, 1));
        if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('skeleton-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/weekpact-skeleton-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}

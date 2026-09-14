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
                  child: SizedBox(height: 440, child: TodaySkeleton()),
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
      },
    );
  }
}

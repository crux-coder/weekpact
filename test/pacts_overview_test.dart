import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/pacts/pacts_overview.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets('weekly rhythm sums pact targets, not completed check-ins', (
    tester,
  ) async {
    final pacts = DashboardPacts().pacts;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(body: WeeklyRhythmCard(pacts: pacts)),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('weekly-rhythm-target')))
          .data,
      '10',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(body: WeeklyRhythmCard(pacts: pacts.take(1).toList())),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('weekly-rhythm-target')))
          .data,
      '7',
    );
  });

  for (final settings in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('pact cards stay square and editable at $settings', (
      tester,
    ) async {
      tester.view.physicalSize = Size(settings.$1, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? edited;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(settings.$2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: PactSquareGrid(
                  pacts: DashboardPacts().pacts,
                  onEdit: (pact) => edited = pact.id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final first = tester.getRect(
        find.byKey(const ValueKey('pact-management-move')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('pact-management-read')),
      );
      expect(first.width, first.height);
      expect(second.width, second.height);
      if (settings.$2 == 1) {
        expect(first.top, second.top);
      } else {
        expect(second.top, greaterThan(first.bottom));
      }
      await tester.tap(find.byTooltip('Edit Move for 30 min'));
      expect(edited, 'move');
    });
  }
}

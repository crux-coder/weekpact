import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/pacts/pacts_overview.dart';
import 'package:weekpact/src/widgets/app_components.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  CrewWeek sample({String today = '2026-09-16', bool empty = false}) =>
      CrewWeek(
        today: today,
        weekStart: '2026-09-14',
        timezone: 'Pacific/Auckland',
        pacts: empty ? [] : DashboardPacts().pacts,
        members: [],
        checkIns: [
          const PactCheckIn('move', 'me', '2026-09-14'),
          const PactCheckIn('move', 'me', '2026-09-14'), // Duplicate day.
          const PactCheckIn('move', 'other', '2026-09-15'),
          const PactCheckIn('move', 'me', '2026-09-13'), // Previous week.
          const PactCheckIn('move', 'me', '2026-09-21'), // Future week.
          for (final day in ['14', '15', '16', '17'])
            PactCheckIn('read', 'me', '2026-09-$day'),
        ],
      );

  Future<void> render(WidgetTester tester, CrewWeek week) => tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: YourWeekCard(week: week, userId: 'me'),
        ),
      ),
    ),
  );

  testWidgets('weekly progress uses personal distinct days capped per target', (
    tester,
  ) async {
    await render(tester, sample(today: '2026-09-17'));
    expect(find.text('Your week so far'), findsOneWidget);
    expect(find.text('4 of 10 check-ins done'), findsOneWidget);
    expect(find.text('1 / 7'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
      find.text('6 left · 4 days remaining, including today'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .4,
    );
  });

  testWidgets('week uses supplied crew date and handles empty pacts', (
    tester,
  ) async {
    await render(tester, sample(today: '2026-09-20'));
    expect(find.text('6 left · Today is the last day'), findsOneWidget);
    await render(tester, sample(empty: true));
    expect(find.text('Add a pact to start your week.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('completed week celebrates targets and handles large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final week = sample(today: '2026-09-20');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: YourWeekCard(
              userId: 'me',
              week: CrewWeek(
                today: week.today,
                weekStart: week.weekStart,
                timezone: week.timezone,
                pacts: week.pacts,
                members: [],
                checkIns: [
                  for (final pact in week.pacts)
                    for (var day = 14; day <= 20; day++)
                      PactCheckIn(pact.id, 'me', '2026-09-$day'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('10 of 10 check-ins done'), findsOneWidget);
    expect(find.text('All weekly targets met. Nice work!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final settings in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'pact bars stack, wear their own colour and stay editable at $settings',
      (tester) async {
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
                  child: PactBarList(
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
        // Every bar spans the page and they stack, whatever the text scale.
        expect(first.width, settings.$1 - 24);
        expect(second.width, first.width);
        expect(second.top, greaterThanOrEqualTo(first.bottom));
        // Each card is wholly its pact's own colour, taken by the pact's
        // place in the list — not a partial fill measuring the week.
        expect(find.byType(FractionallySizedBox), findsNothing);
        Color fillOf(String id) => tester
            .widget<AppSurface>(
              find
                  .descendant(
                    of: find.byKey(ValueKey('pact-management-$id')),
                    matching: find.byType(AppSurface),
                  )
                  .first,
            )
            .fillColor!;
        expect(fillOf('move'), WeekPactColors.pactTint(0));
        expect(fillOf('read'), WeekPactColors.pactTint(1));
        // The weekly count is the title's caption, not a column of its own.
        expect(find.text('7/week'), findsOneWidget);
        expect(find.text('3/week'), findsOneWidget);
        // Editing lives behind the bar's menu now, so the tap that used to
        // reach it has to open the menu first.
        await tester.tap(find.byTooltip('Move for 30 min options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit pact'));
        await tester.pumpAndSettle();
        expect(edited, 'move');
      },
    );
  }
}

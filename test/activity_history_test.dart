import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/activity_history.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/expandable_home_panels.dart';
import 'package:flutter/services.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

class HistoryBackend extends DashboardBackend {
  final cursors = <CrewActivity?>[];
  bool fail = false;
  Completer<List<CrewActivity>>? pending;
  final history = List.generate(
    25,
    (index) => CrewActivity(
      pactId: 'read',
      userId: '',
      completedOn: '2026-08-${(31 - index).toString().padLeft(2, '0')}',
      createdAt: DateTime.utc(2026, 8, 31 - index, 12),
      pactTitle: 'History entry $index',
    ),
  );

  @override
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  }) async {
    expect(crewId, 'crew');
    cursors.add(before);
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return history
        .skip(before == null ? 0 : history.indexOf(before) + 1)
        .take(limit)
        .toList();
  }
}

void main() {
  testWidgets(
    'date groups continue across pages without repeating dates per check-in',
    (tester) async {
      final backend = HistoryBackend();
      backend.history
        ..clear()
        ..addAll(
          List.generate(
            23,
            (index) => CrewActivity(
              pactId: 'pact-$index',
              userId: '',
              completedOn: index < 21 ? '2026-08-31' : '2026-08-30',
              createdAt: DateTime(2026, 8, index < 21 ? 31 : 30, 12),
              pactTitle: 'History entry $index',
            ),
          ),
        );
      final week = await backend.fetchWeek('crew');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityHistory(
              backend: backend,
              crewId: 'crew',
              week: week,
              userId: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstDay = find.byKey(
        ValueKey('activity-date-${DateTime(2026, 8, 31).toIso8601String()}'),
      );
      expect(firstDay, findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('activity-history-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('History entry 22'),
        400,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(backend.cursors, [null, backend.history[19]]);
      // The first day continues into page two; its heading stays at the start,
      // outside the viewport, rather than being repeated at the page boundary.
      expect(firstDay, findsNothing);
      expect(
        find.byKey(
          ValueKey('activity-date-${DateTime(2026, 8, 30).toIso8601String()}'),
        ),
        findsOneWidget,
      );
      expect(find.text('History entry 20'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
    },
  );

  testWidgets('heading history button opens and dismisses crew history', (
    tester,
  ) async {
    final backend = HistoryBackend()..selected.clear();
    await pumpHome(tester, backend);
    await tester.pumpUi();
    final button = find.byKey(const ValueKey('crew-history-button'));
    expect(find.byKey(const ValueKey('latest-activity')), findsNothing);
    expect(find.byKey(const ValueKey('crew-check-in-count')), findsNothing);
    final heading = tester.getRect(find.byKey(const ValueKey('crew-board')));
    expect(tester.getRect(button).top, heading.top);
    expect(tester.getSize(button).width, 44);
    await tester.tap(button);
    await tester.pumpUi();
    expect(find.byType(ActivityHistory), findsOneWidget);
    expect(find.text('History entry 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Close activity history'));
    await tester.pumpUi();
    expect(find.byType(ActivityHistory), findsNothing);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpUi();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpUi();
    expect(find.byType(ActivityHistory), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scroll loads older history once and stops at the end', (
    tester,
  ) async {
    final backend = HistoryBackend();
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityHistory(
            backend: backend,
            crewId: 'crew',
            week: week,
            userId: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.cursors, [null]);
    final list = find.byKey(const ValueKey('activity-history-list'));
    await tester.scrollUntilVisible(
      find.text('History entry 19'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(backend.cursors, [null, backend.history[19]]);
    await tester.scrollUntilVisible(
      find.text('You’re all caught up'),
      400,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(find.text('History entry 24'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(backend.cursors.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed older page preserves entries and retries the same cursor',
    (tester) async {
      final backend = HistoryBackend();
      final week = await backend.fetchWeek('crew');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityHistory(
              backend: backend,
              crewId: 'crew',
              week: week,
              userId: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      backend.fail = true;
      final list = find.byKey(const ValueKey('activity-history-list'));
      await tester.scrollUntilVisible(
        find.text('Could not load activity.'),
        400,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load activity.'), findsOneWidget);
      expect(find.text('History entry 19'), findsOneWidget);
      backend.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(backend.cursors, [null, backend.history[19], backend.history[19]]);
      expect(find.text('Could not load activity.'), findsNothing);
    },
  );

  testWidgets('initial error retries and dismissing during loading is safe', (
    tester,
  ) async {
    final backend = HistoryBackend()..fail = true;
    await pumpHome(tester, backend);
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('crew-history-button')));
    await tester.pumpUi();
    expect(find.text('Could not load activity.'), findsOneWidget);
    backend.fail = false;
    backend.pending = Completer<List<CrewActivity>>();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ActivityHistory),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close activity history'));
    await tester.pumpUi();
    backend.pending!.complete([]);
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'empty history fits small screens with large text and backdrop dismisses',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = HistoryBackend()..history.clear();
      final week = await backend.fetchWeek('crew');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ExpandableHomePanels(
              backend: backend,
              crewId: 'crew',
              week: week,
              userId: '',
              top: 72,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('crew-history-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No activity yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(20, 30));
      await tester.pumpAndSettle();
      expect(find.byType(ActivityHistory), findsNothing);
    },
  );
}

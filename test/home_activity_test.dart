import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/latest_activity_row.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  for (final entry in {
    const Duration(seconds: 20): 'Just now',
    const Duration(minutes: 2): '2m ago',
    const Duration(hours: 3): '3h ago',
  }.entries) {
    testWidgets(
      'activity stays compact with large text and shows ${entry.value}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final original = await DashboardBackend().fetchWeek('crew');
        final now = DateTime.utc(2026, 9, 14, 12);
        final week = CrewWeek(
          today: '2026-09-14',
          weekStart: '2026-09-14',
          timezone: original.timezone,
          pacts: original.pacts,
          checkIns: const [PactCheckIn('read', 'member', '2026-09-14')],
          members: const [
            WeekMember('member', 'm@example.com', displayName: 'Mirnes'),
          ],
          latestActivity: CrewActivity(
            pactId: 'read',
            userId: 'member',
            createdAt: now.subtract(entry.key),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: WeekPactTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: LatestActivityRow(week: week, userId: '', now: now),
              ),
            ),
          ),
        );
        expect(find.text('Mirnes checked in'), findsOneWidget);
        expect(find.text('Read 20 pages · ${entry.value}'), findsOneWidget);
        expect(tester.widget<Text>(find.text('Mirnes checked in')).maxLines, 1);
        expect(
          tester.getSize(find.byKey(const ValueKey('latest-activity'))).height,
          LatestActivityRow.height,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('no activity has an honest empty state', (tester) async {
    final backend = DashboardBackend()..selected.clear();
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LatestActivityRow(week: week, userId: ''),
        ),
      ),
    );
    expect(find.text('Be the first to check in today'), findsOneWidget);
    expect(find.textContaining('ago'), findsNothing);
  });
}

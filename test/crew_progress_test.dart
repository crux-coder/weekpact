import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets('crew fill counts members once and animates from empty to full', (
    tester,
  ) async {
    final original = await DashboardBackend().fetchWeek('crew');
    for (final count in [0, 1, 2]) {
      final week = CrewWeek(
        today: original.today,
        weekStart: original.weekStart,
        timezone: 'UTC',
        goals: original.goals,
        members: original.members,
        checkIns: [
          for (final member in original.members.take(count)) ...[
            GoalCheckIn('move', member.id, original.today),
            GoalCheckIn('read', member.id, original.today),
          ],
          GoalCheckIn('read', 'former-member', original.today),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: Scaffold(
            body: TodayCrewCard(week: week, userId: '', onOpen: () {}),
          ),
        ),
      );
      if (count > 0) {
        await tester.pump(const Duration(milliseconds: 150));
        final fraction = tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('crew-progress-fill')),
            )
            .widthFactor!;
        expect(fraction, greaterThan((count - 1) / 2));
        expect(fraction, lessThan(count / 2));
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('crew-progress-fill')),
            )
            .widthFactor,
        count / 2,
      );
      expect(find.text('Crew check-ins'), findsNothing);
      expect(
        find.text(
          [
            'Let’s get started',
            'One more to go',
            'Everyone checked in!',
          ][count],
        ),
        findsOneWidget,
      );
      expect(find.text('$count of 2 checked in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

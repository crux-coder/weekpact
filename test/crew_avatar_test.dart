import 'support/pump_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  test(
    'avatar initials come from display names, including the current user',
    () {
      expect(
        const WeekMember(
          'a',
          'email@example.com',
          displayName: ' Jane Doe ',
        ).initials,
        'JD',
      );
      expect(
        const WeekMember(
          'b',
          'email@example.com',
          displayName: 'Júlia',
        ).initials,
        'J',
      );
      expect(const WeekMember('c', 'email@example.com').initials, '?');
    },
  );
  testWidgets(
    'pending avatars stay on the unfilled side and all avatars stay compact',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = await DashboardBackend().fetchWeek('crew');
      final week = CrewWeek(
        today: original.today,
        weekStart: original.weekStart,
        timezone: 'UTC',
        goals: original.goals,
        members: const [
          WeekMember('a', 'a@example.com', displayName: 'Jane Doe'),
          WeekMember('b', 'b@example.com', displayName: 'Sam Lee'),
          WeekMember('c', 'c@example.com', displayName: 'Alex Park'),
        ],
        checkIns: [
          GoalCheckIn('read', 'a', original.today),
          GoalCheckIn('read', 'b', original.today),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.light,
          home: Scaffold(
            body: TodayCrewCard(week: week, userId: 'c', onOpen: () {}),
          ),
        ),
      );
      await tester.pumpUi();
      final boundary = tester
          .getTopLeft(find.byKey(const ValueKey('pending-members')))
          .dx;
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('crew-avatar-b'))).dx,
        lessThanOrEqualTo(boundary),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('crew-avatar-c'))).dx,
        greaterThanOrEqualTo(boundary),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('crew-avatar-c'))).width,
        lessThanOrEqualTo(48),
      );
      expect(find.text('AP'), findsOneWidget);
      expect(find.text('YOU'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

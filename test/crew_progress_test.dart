import 'support/pump_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets(
    'crew split counts members once and groups them by check-in status',
    (tester) async {
      final original = await DashboardBackend().fetchWeek('crew');
      for (final count in [0, 1, 2]) {
        final week = CrewWeek(
          today: original.today,
          weekStart: original.weekStart,
          timezone: 'UTC',
          pacts: original.pacts,
          members: original.members,
          checkIns: [
            for (final member in original.members.take(count)) ...[
              PactCheckIn('move', member.id, original.today),
              PactCheckIn('read', member.id, original.today),
            ],
            PactCheckIn('read', 'former-member', original.today),
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
        await tester.pumpUi();
        expect(find.text('Checked in · $count'), findsOneWidget);
        expect(find.text('Not yet · ${2 - count}'), findsOneWidget);
        final leftWidth = tester
            .getSize(find.byKey(const ValueKey('checked-tile')))
            .width;
        final rightWidth = tester
            .getSize(find.byKey(const ValueKey('pending-tile')))
            .width;
        if (count == 1) {
          expect(leftWidth, closeTo(rightWidth, .01));
        } else if (count == 0) {
          expect(leftWidth, lessThan(rightWidth));
          expect(leftWidth, greaterThanOrEqualTo(96));
        } else {
          expect(leftWidth, greaterThan(rightWidth));
          expect(rightWidth, greaterThanOrEqualTo(96));
        }
        final checkedGroup = find.byKey(const ValueKey('checked-members'));
        final pendingGroup = find.byKey(const ValueKey('pending-members'));
        for (var i = 0; i < original.members.length; i++) {
          final avatar = find.byKey(
            ValueKey('crew-avatar-${original.members[i].id}'),
          );
          expect(
            find.descendant(
              of: i < count ? checkedGroup : pendingGroup,
              matching: avatar,
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

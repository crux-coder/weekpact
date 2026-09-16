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
        expect(
          find.bySemanticsLabel(
            count == 2 ? 'Whole crew is in today' : 'Checked in today · $count',
          ),
          count == 0 ? findsNothing : findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            count == 0
                ? 'Nobody has checked in today · 2 to go'
                : 'Not yet today · ${2 - count}',
          ),
          count == 2 ? findsNothing : findsOneWidget,
        );
        final checkedTile = find.byKey(const ValueKey('checked-tile'));
        final pendingTile = find.byKey(const ValueKey('pending-tile'));
        final boardWidth = tester
            .getSize(find.byKey(const ValueKey('crew-board')))
            .width;
        if (count == 0) {
          expect(checkedTile, findsNothing);
          expect(tester.getSize(pendingTile).width, boardWidth);
          expect(find.text('0/2'), findsNothing);
          expect(find.text('be the first in today'), findsOneWidget);
          expect(find.byKey(const ValueKey('pending-count')), findsOneWidget);
        } else if (count == 2) {
          expect(pendingTile, findsNothing);
          expect(tester.getSize(checkedTile).width, boardWidth);
          expect(find.text('2/2'), findsNothing);
          expect(find.text('whole crew is in'), findsOneWidget);
          expect(find.byKey(const ValueKey('checked-count')), findsOneWidget);
        } else {
          expect(
            tester.getSize(checkedTile).width,
            closeTo(tester.getSize(pendingTile).width, .01),
          );
          expect(find.text('1/2'), findsNothing);
          expect(find.text('not yet'), findsOneWidget);
          expect(find.text('checked in'), findsOneWidget);
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

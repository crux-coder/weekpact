import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

class MembersBackend extends DashboardBackend {
  int completed = 2;

  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final week = await super.fetchWeek(crewId);
    final members = [
      const WeekMember('', '', displayName: 'Jasmin Hadžić'),
      const WeekMember('1', '', displayName: 'Mira Petrović'),
      for (var i = 2; i < 14; i++)
        WeekMember('$i', '', displayName: 'Crew member $i Full Family Name'),
    ];
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: members,
      checkIns: [
        for (final member in members.take(completed)) ...[
          PactCheckIn('read', member.id, week.today),
          PactCheckIn('move', member.id, week.today),
        ],
        const PactCheckIn('read', '2', '2026-09-08'),
        PactCheckIn('read', 'former-member', week.today),
      ],
    );
  }
}

Future<void> closeFromBackground(WidgetTester tester, Finder tile) async {
  final rect = tester.getRect(tile);
  final backdrop = tester.getRect(
    find.byKey(const ValueKey('crew-panel-backdrop')),
  );
  expect(backdrop.bottom - rect.bottom, greaterThan(40));
  await tester.tapAt(
    Offset(rect.center.dx, (rect.bottom + backdrop.bottom) / 2),
  );
  await tester.pumpUi();
}

void main() {
  testWidgets(
    'checked-in tile unfolds into full names, counts each person once, and collapses',
    (tester) async {
      await pumpHome(tester, MembersBackend());
      await tester.pumpUi();
      final tile = find.byKey(const ValueKey('checked-tile'));
      final original = tester.getRect(tile);
      final element = tester.element(tile);
      expect(find.bySemanticsLabel('Checked in today · 2'), findsOneWidget);
      await tester.tapAt(original.bottomRight - const Offset(10, 10));
      await tester.pumpUi();
      expect(tester.element(tile), same(element));
      expect(tester.getRect(tile).topLeft, original.topLeft);
      expect(tester.getSize(tile).width, greaterThan(original.width));
      expect(Navigator.of(tester.element(tile)).canPop(), isFalse);
      final list = find.byKey(const ValueKey('checked-members-list'));
      expect(
        find.descendant(of: list, matching: find.text('Jasmin Hadžić')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('Mira Petrović')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('You')),
        findsOneWidget,
      );
      expect(find.text('Crew member 2 Full Family Name'), findsNothing);
      await closeFromBackground(tester, tile);
      expect(list, findsNothing);
      expect(tester.getRect(tile), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'not-yet tile lists all pending names and scrolls with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester, MembersBackend());
      await tester.pumpUi();
      final tile = find.byKey(const ValueKey('pending-tile'));
      final original = tester.getRect(tile);
      await tester.tap(find.bySemanticsLabel('Not yet today · 12'));
      await tester.pumpUi();
      expect(tester.getRect(tile).top, original.top);
      expect(tester.getRect(tile).left, lessThan(original.left));
      final list = find.byKey(const ValueKey('pending-members-list'));
      expect(
        find.descendant(
          of: list,
          matching: find.text('Crew member 2 Full Family Name'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('Jasmin Hadžić')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Crew member 13 Full Family Name'),
        200,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        tester
            .widget<Text>(find.text('Crew member 13 Full Family Name'))
            .maxLines,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await closeFromBackground(tester, tile);
      expect(list, findsNothing);
      expect(tester.getRect(tile), original);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty checked group stays hidden and changing tabs closes expansion',
    (tester) async {
      final backend = MembersBackend()..completed = 0;
      await pumpHome(tester, backend);
      await tester.pumpUi();
      expect(find.byKey(const ValueKey('checked-tile')), findsNothing);
      final pending = find.byKey(const ValueKey('pending-tile'));
      expect(
        tester.getSize(pending).width,
        tester.getSize(find.byKey(const ValueKey('crew-board'))).width,
      );
      await tester.tap(pending);
      await tester.pumpUi();
      expect(
        find.byKey(const ValueKey('pending-members-list')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('nav-pacts')));
      await tester.pumpUi();
      backend.completed = 14;
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpUi();
      expect(find.byKey(const ValueKey('pending-tile')), findsNothing);
      final checked = find.byKey(const ValueKey('checked-tile'));
      expect(
        tester.getSize(checked).width,
        tester.getSize(find.byKey(const ValueKey('crew-board'))).width,
      );
      expect(find.text('14/14'), findsNothing);
      await tester.tap(checked);
      await tester.pumpUi();
      expect(
        find.byKey(const ValueKey('checked-members-list')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Collapse members'));
      await tester.pumpUi();
      expect(find.byKey(const ValueKey('checked-members-list')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

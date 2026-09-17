import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_roster.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

void main() {
  for (final config in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('roster stacks bands at ${config.$1} at scale ${config.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(config.$1, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var invited = false;
      final member = CrewMember(
        userId: 'one',
        email: 'long-email-address@example.com',
        displayName: 'A member with a very long name',
        role: 'owner',
        joinedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(config.$2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CrewRoster(
                    children: [
                      CrewPersonBand(
                        member: member,
                        isCurrentUser: true,
                        color: WeekPactColors.coolGrey,
                      ),
                      CrewInviteBand(onPressed: () => invited = true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final person = find.byType(CrewPersonBand);
      final invite = find.byType(CrewInviteBand);
      // Bands are full width and stacked, never side by side.
      expect(tester.getSize(person).width, config.$1 - 24);
      expect(tester.getSize(invite).width, config.$1 - 24);
      expect(
        tester.getTopLeft(invite).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(person).dy),
      );
      expect(find.text('OWNER'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(invite);
      await tester.tap(find.text('INVITE SOMEONE'));
      expect(invited, isTrue);
    });
  }

  testWidgets('avatar stack summarises the crew and counts the overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: CrewAvatarStack(
            limit: 2,
            members: [
              for (var i = 0; i < 5; i++)
                CrewMember(
                  userId: '$i',
                  email: 'member$i@example.com',
                  displayName: 'Member $i',
                  role: 'member',
                  joinedAt: DateTime(2026),
                ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CrewFace), findsNWidgets(2));
    expect(find.text('+3'), findsOneWidget);
  });
}

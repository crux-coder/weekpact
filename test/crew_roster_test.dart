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
      // Your own band names the tint rather than leaving colour to carry it.
      expect(find.text('YOU · OWNER'), findsOneWidget);
      expect(find.text('OWNER'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(invite);
      await tester.tap(find.text('INVITE SOMEONE'));
      expect(invited, isTrue);
    });
  }
}

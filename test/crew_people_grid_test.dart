import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_people_grid.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

void main() {
  for (final config in [(390.0, 1.0, true), (320.0, 2.0, false)]) {
    testWidgets(
      'people grid adapts at ${config.$1} with text scale ${config.$2}',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var invited = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: WeekPactTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(config.$2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: CrewPeopleGrid(
                      children: [
                        CrewPersonCard(
                          member: CrewMember(
                            userId: 'one',
                            email: 'long-email-address@example.com',
                            displayName: 'A member with a very long name',
                            role: 'owner',
                            joinedAt: DateTime(2026),
                          ),
                          isCurrentUser: true,
                          color: WeekPactColors.mintGreen,
                        ),
                        CrewInviteTile(onPressed: () => invited = true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final person = find.byType(CrewPersonCard);
        final invite = find.byType(CrewInviteTile);
        final size = tester.getSize(person);
        expect(size.width, size.height);
        expect(
          tester.getTopLeft(person).dy == tester.getTopLeft(invite).dy,
          config.$3,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(invite);
        await tester.tap(find.text('INVITE SOMEONE'));
        expect(invited, isTrue);
      },
    );
  }
}

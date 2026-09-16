import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';

List<WeekMember> crew(int size) => [
  for (var i = 0; i < size; i++)
    WeekMember('m$i', 'm$i@example.com', displayName: 'Member $i'),
];

Future<void> pumpTile(
  WidgetTester tester,
  List<WeekMember> members, {
  double width = 180,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: TodayCrewCard.groupHeight,
            child: CrewCheckInTile(
              members: members,
              done: true,
              userId: 'm0',
              onOpen: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

int facesOn(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('crew-member-'),
      ),
    )
    .length;

void main() {
  testWidgets('leads with the count for any crew size', (tester) async {
    for (final size in [1, 3, 9, 40]) {
      await pumpTile(tester, crew(size));
      expect(find.text('$size'), findsOneWidget, reason: 'crew of $size');
      expect(find.text('checked in'), findsOneWidget);
    }
  });

  testWidgets('shows every face while they fit', (tester) async {
    await pumpTile(tester, crew(3));

    expect(facesOn(tester), 3);
    expect(find.byKey(const ValueKey('crew-overflow')), findsNothing);
  });

  testWidgets('spills the remainder into one +n chip', (tester) async {
    await pumpTile(tester, crew(9));

    // Two faces plus the chip, never more faces than the cap.
    expect(facesOn(tester), 2);
    expect(find.text('+7'), findsOneWidget);
  });

  testWidgets('drops to the chip alone when the tile is narrow', (
    tester,
  ) async {
    await pumpTile(tester, crew(12), width: 104);

    expect(facesOn(tester), 0);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('keeps the count legible at large text sizes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: TodayCrewCard.groupHeight,
                child: CrewCheckInTile(
                  members: crew(6),
                  done: false,
                  userId: 'm0',
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();

    expect(tester.takeException(), isNull);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('not yet'), findsOneWidget);
  });
}

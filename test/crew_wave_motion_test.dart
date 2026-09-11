import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets(
    'wave moves independently of progress and stops for reduced motion',
    (tester) async {
      final original = await DashboardBackend().fetchWeek('crew');
      final week = CrewWeek(
        today: original.today,
        weekStart: original.weekStart,
        timezone: original.timezone,
        goals: original.goals,
        members: original.members,
        checkIns: [
          GoalCheckIn('move', original.members.first.id, original.today),
        ],
      );
      Future<void> show({bool reduced = false, bool active = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: TodayCrewCard(
                    week: week,
                    userId: '',
                    onOpen: () {},
                    animate: active,
                  ),
                ),
              ),
            ),
          );
      final fill = find.byKey(const ValueKey('crew-progress-fill'));
      Offset edge() {
        final clip = tester.widget<ClipPath>(
          find.descendant(of: fill, matching: find.byType(ClipPath)),
        );
        return clip.clipper!
            .getClip(const Size(100, 100))
            .computeMetrics()
            .first
            .getTangentForOffset(0)!
            .position;
      }

      await show();
      final before = edge();
      await tester.pump(const Duration(milliseconds: 800));
      expect(edge(), isNot(before));
      expect(tester.widget<FractionallySizedBox>(fill).widthFactor, .5);
      await show(reduced: true);
      final frozen = edge();
      await tester.pump(const Duration(seconds: 2));
      expect(edge(), frozen);
      await show(active: false);
      final inactive = edge();
      await tester.pump(const Duration(seconds: 2));
      expect(edge(), inactive);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_moment.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

void main() {
  List<String> listen(WidgetTester tester) {
    final kinds = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          kinds.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return kinds;
  }

  Widget stage({bool still = false}) => MaterialApp(
    theme: WeekPactTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: still),
      child: child!,
    ),
    home: const Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: CheckInCelebration(pactIndex: 0, iconKey: 'run'),
        ),
      ),
    ),
  );

  testWidgets('the flourish lands with the burst, once', (tester) async {
    final kinds = listen(tester);
    await tester.pumpWidget(stage());
    await tester.pump();
    expect(kinds, ['HapticFeedbackType.selectionClick']);
    await tester.pump(const Duration(milliseconds: 150));
    expect(kinds.length, 2);
    await tester.pump(const Duration(milliseconds: 400));
    expect(kinds.last, 'HapticFeedbackType.heavyImpact');
    expect(kinds.length, 4);
    await tester.pump(const Duration(seconds: 3));
    expect(kinds.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations off the badge stands and one tap is given', (
    tester,
  ) async {
    final kinds = listen(tester);
    await tester.pumpWidget(stage(still: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(kinds, ['HapticFeedbackType.heavyImpact']);
    expect(tester.takeException(), isNull);
  });
}

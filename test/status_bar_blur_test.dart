import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/theme/status_bar_blur.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

Widget _app({required double top, VoidCallback? onTap}) => MaterialApp(
  theme: WeekPactTheme.dark,
  home: MediaQuery(
    data: MediaQueryData(padding: EdgeInsets.only(top: top)),
    child: StatusBarBlur(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    ),
  ),
);

void main() {
  testWidgets('frosts the status bar without taking its taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(top: 47, onTap: () => taps++));

    expect(find.byType(BackdropFilter), findsWidgets);
    await tester.tapAt(const Offset(200, 20));
    expect(taps, 1);
  });

  testWidgets('draws nothing when there is no status bar', (tester) async {
    await tester.pumpWidget(_app(top: 0));

    expect(find.byType(BackdropFilter), findsNothing);
  });
}

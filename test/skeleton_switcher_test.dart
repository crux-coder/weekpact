import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/widgets/skeleton_switcher.dart';

const _skeleton = Text('skeleton');

Future<void> _pump(WidgetTester tester, Widget? child) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: SkeletonSwitcher(skeleton: _skeleton, child: child),
  ),
);

void main() {
  testWidgets('a quick load never shows the skeleton', (tester) async {
    await _pump(tester, null);
    await tester.pump(const Duration(milliseconds: 150));
    await _pump(tester, const Text('page'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('skeleton'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a slow load shows the skeleton for its minimum', (tester) async {
    await _pump(tester, null);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('skeleton'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    await _pump(tester, const Text('page'));
    await tester.pump(const Duration(milliseconds: 300));
    // Still inside the minimum, so the page waits its turn.
    expect(find.text('page'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('skeleton'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a reload holds the old page, untouchable, until it lands', (
    tester,
  ) async {
    var taps = 0;
    final old = TextButton(onPressed: () => taps++, child: const Text('old'));
    await _pump(tester, old);
    await _pump(tester, null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('old'), findsOneWidget);
    expect(find.text('skeleton'), findsNothing);
    await tester.tap(find.text('old'), warnIfMissed: false);
    expect(taps, 0);
    await _pump(tester, const Text('new', key: ValueKey('new')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('old'), findsNothing);
    expect(find.text('new'), findsOneWidget);
  });
}

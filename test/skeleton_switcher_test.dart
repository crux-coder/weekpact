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
  testWidgets('a quick load still shows the skeleton for its minimum', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.text('skeleton'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    await _pump(tester, const Text('page'));
    await tester.pump(const Duration(milliseconds: 300));
    // Still inside the minimum, so the page waits its turn.
    expect(find.text('page'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('skeleton'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a slow load zooms in over nothing', (tester) async {
    await _pump(tester, null);
    await tester.pump(const Duration(milliseconds: 600));
    await _pump(tester, const Text('page'));
    await tester.pump(const Duration(milliseconds: 60));
    // The skeleton is gone at once; the page is still coming into focus.
    expect(find.text('skeleton'), findsNothing);
    // Drawn smaller than it stands, so its corner sits inside its place.
    final growing = tester.getTopLeft(find.text('page'));
    await tester.pump(const Duration(milliseconds: 300));
    final settled = tester.getTopLeft(find.text('page'));
    expect(settled.dx, lessThan(growing.dx));
    expect(settled.dy, lessThan(growing.dy));
  });

  testWidgets('a reload goes back to the skeleton', (tester) async {
    await _pump(tester, const Text('old'));
    expect(find.text('skeleton'), findsNothing);
    await _pump(tester, null);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('old'), findsNothing);
    expect(find.text('skeleton'), findsOneWidget);
  });
}

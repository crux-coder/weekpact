import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/pact_deck.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

void main() {
  testWidgets('Home\'s next pact card stays out of Chat while the tabs slide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHome(tester, DashboardBackend());
    await tester.pumpUi();
    final next = find.descendant(
      of: find.byType(PactDeck),
      matching: find.text('Read 20 pages'),
    );
    expect(next, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    // Halfway through the slide, where the card used to show over Chat.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final card = tester.getRect(next);
    expect(card.left, lessThan(390), reason: 'the card is over the screen');
    // Something between the card and the screen clips it away entirely.
    RenderObject? node = tester.renderObject(next);
    var clipped = false;
    while (node != null && !clipped) {
      if (node is RenderClipRect &&
          node.hasSize &&
          node.clipBehavior != Clip.none) {
        final box = MatrixUtils.transformRect(
          node.getTransformTo(null),
          Offset.zero & node.size,
        );
        clipped = !box.overlaps(card);
      }
      node = node.parent;
    }
    expect(clipped, isTrue);
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
  });
}

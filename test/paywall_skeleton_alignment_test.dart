import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';
import 'package:weekpact/src/widgets/skeleton_switcher.dart';

import 'subscription_test.dart' show FakeSubscriptionBackend;
import 'support/fonts.dart';

/// Holds the offer back so the plans' skeleton can be measured.
class _SlowStore extends FakeSubscriptionBackend {
  final pending = Completer<ProOffer?>();

  @override
  Future<ProOffer?> loadOffer() => pending.future;
}

/// Every surface under [of], where it is drawn on screen.
List<Rect> _surfaces(WidgetTester tester, Finder of) => [
  for (final element
      in find.descendant(of: of, matching: find.byType(AppSurface)).evaluate())
    MatrixUtils.transformRect(
      (element.renderObject! as RenderBox).getTransformTo(null),
      Offset.zero & (element.renderObject! as RenderBox).size,
    ),
];

/// Run with --dart-define=CAPTURE_DESIGN=true to see both states.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Directory.systemTemp.path}/weekpact-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadAppFont);

  for (final scale in [1.0, 1.6]) {
    testWidgets('the plans arrive over their skeleton at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _SlowStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('capture'),
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: SubscriptionScope(
            controller: SubscriptionController(store),
            child: const PaywallPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await _capture(tester, 'paywall-loading-$scale');

      final skeleton = find.byKey(const ValueKey('paywall-plans-skeleton'));
      // Two plan cards and the yearly one's saving.
      final waiting = _surfaces(tester, skeleton);
      expect(waiting, hasLength(3));

      store.pending.complete(store.offer);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      await _capture(tester, 'paywall-loaded-$scale');
      expect(skeleton, findsNothing);

      final plans = _surfaces(tester, find.byType(SkeletonSwitcher));
      expect(plans, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(waiting[i].left, closeTo(plans[i].left, 1));
        expect(waiting[i].top, closeTo(plans[i].top, 1));
        expect(waiting[i].right, closeTo(plans[i].right, 1));
        expect(waiting[i].bottom, closeTo(plans[i].bottom, 1));
      }
    });
  }
}

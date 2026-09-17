// Renders the real paywall to design/paywall/ with the app's fonts loaded, so
// the design can be reviewed as an image. Run:
//   flutter test --dart-define=CAPTURE_DESIGN=true test/paywall_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/subscriptions/paywall_page.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_page.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'subscription_test.dart' show FakeSubscriptionBackend;
import 'support/pump_ui.dart';

final screens = <String, Widget>{
  'paywall': const PaywallPage(),
  'subscription': const SubscriptionPage(),
};

final access = <String, ProAccess>{
  'paywall': ProAccess.locked,
  'subscription': ProAccess(
    active: true,
    willRenew: true,
    productIdentifier: 'yearly',
    expiresAt: DateTime(2027, 3, 4),
    managementUrl: 'https://apps.apple.com/account/subscriptions',
  ),
};

void main() {
  screens.forEach((name, screen) {
    testWidgets('$name renders', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = ValueKey('capture');
      const capturing = bool.fromEnvironment('CAPTURE_DESIGN');
      if (capturing) {
        final condensed = FontLoader('RobotoCondensed')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf'));
        await tester.runAsync(() => condensed.load());
        final roboto = FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
        await tester.runAsync(() => roboto.load());
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: RepaintBoundary(
            key: capture,
            child: SubscriptionScope(
              controller: SubscriptionController(
                FakeSubscriptionBackend(initial: access[name]!),
              ),
              child: screen,
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(tester.takeException(), isNull);
      if (capturing) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('design/paywall/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}

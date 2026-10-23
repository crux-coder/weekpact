import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/notifications/notifications_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

import 'notification_inbox_test.dart' show notification;
import 'support/fonts.dart';
import 'support/home_fakes.dart';

/// Holds the first page of notifications until [hold] completes.
class _HeldNotifications extends DashboardBackend {
  final hold = Completer<void>();

  @override
  Future<List<NotificationEntry>> fetchNotifications({
    NotificationEntry? before,
    int limit = 20,
  }) async {
    await hold.future;
    return super.fetchNotifications(before: before, limit: limit);
  }
}

const _capture = ValueKey('notifications-skeleton-capture');

Future<void> _capturePng(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/weekpact-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadAppFont);

  // The skeleton is drawn as one flat tone, so what it promises is the
  // surface's outline: it has to stand where the day's surface lands, with
  // its rows the height of a one-line notice, or the list jumps as it fades
  // in.
  testWidgets('the notifications skeleton stands where the list lands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Notices whose sentence fits one line: nudges, which carry no pact.
    final backend = _HeldNotifications()
      ..notifications = [
        for (var i = 0; i < 5; i++)
          notification(i, type: 'crew_nudge', pactTitle: null, read: true),
      ];
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          theme: WeekPactTheme.light,
          home: NotificationsPage(backend: backend, viewerId: 'me'),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byType(AppSurface);
    expect(surface, findsOneWidget);
    final skeleton = tester.getRect(surface);
    await _capturePng(tester, 'notifications-loading');

    backend.hold.complete();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }
    await _capturePng(tester, 'notifications-loaded');

    final loaded = tester.getRect(
      find.byKey(const ValueKey('notifications-section-Today')),
    );
    expect(skeleton.left, loaded.left);
    expect(skeleton.width, loaded.width);
    expect(skeleton.top, closeTo(loaded.top, 1));
    // The skeleton stands four rows, the list five: the four it promises are
    // where the first four land, divider for divider.
    final rows = [
      for (var i = 0; i < 5; i++)
        tester.getRect(find.byKey(ValueKey('notification-event-$i'))),
    ];
    expect(skeleton.bottom, closeTo(rows[3].bottom, 1));
    expect(tester.takeException(), isNull);
  });
}

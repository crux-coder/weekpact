import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/notifications/notification_scope.dart';
import 'package:weekpact/src/notifications/notification_service.dart';
import 'package:weekpact/src/notifications/notification_settings_card.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'notifications_test.dart' show FakeMessaging;

void main() {
  late FakeMessaging client;
  late NotificationService service;
  setUp(() {
    client = FakeMessaging();
    service = NotificationService(
      createClient: () async => client,
      saveEnabled: (_) async {},
      delay: (_) async {},
    );
  });
  tearDown(() async {
    service.dispose();
    await client.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    required Future<void> Function() openSettings,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationScope(
              service: service,
              child: NotificationSettingsCard(openSettings: openSettings),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a refusal offers the settings it tells you to open', (
    tester,
  ) async {
    client.requested = AuthorizationStatus.denied;
    await service.initialize();
    await service.enable();
    var opened = 0;
    await show(tester, openSettings: () async => opened++);

    expect(
      find.textContaining('Allow notifications in your phone’s app settings'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('OPEN SETTINGS'));
    await tester.tap(find.text('OPEN SETTINGS'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('before anyone is asked there is nothing settings can do', (
    tester,
  ) async {
    await service.initialize();
    var opened = 0;
    await show(tester, openSettings: () async => opened++);

    expect(find.text('ENABLE NOTIFICATIONS'), findsOneWidget);
    expect(find.text('OPEN SETTINGS'), findsNothing);
    expect(opened, 0);
  });
}

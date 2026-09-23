import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/notifications/notifications_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

NotificationEntry notification(
  int index, {
  String type = 'pact_completed',
  bool read = false,
  int claps = 0,
  String name = 'Mirnes Halilovic',
  String crew = 'Early Birds',
  String? pactTitle = 'Climb twice',
}) => NotificationEntry(
  eventId: 'event-$index',
  type: type,
  // Newest first, an hour apart, so ordering and the cursor are both visible.
  createdAt: DateTime.now().toUtc().subtract(Duration(hours: index + 1)),
  read: read,
  crewId: 'crew',
  crewName: crew,
  actorId: 'member-$index',
  displayName: name,
  pactTitle: pactTitle,
  iconKey: 'run',
  clapCount: claps,
);

Future<void> pumpNotifications(
  WidgetTester tester,
  DashboardBackend backend, {
  Size size = const Size(390, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: NotificationsPage(backend: backend),
    ),
  );
  await tester.pumpUi();
}

/// The bell lives on Home now, in its top corner, so that is where it is
/// exercised: the whole page, as the person meets it.
Future<void> pumpHomeWithBell(
  WidgetTester tester,
  DashboardBackend backend,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com'),
        authBackend: const MissingConfigurationAuthBackend(),
        crewBackend: const MissingCrewBackend(),
        pactsBackend: backend.pacts,
        homeBackend: backend,
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  testWidgets('each type says who did what, and to which crew', (tester) async {
    final backend = DashboardBackend()
      ..notifications = [
        notification(0),
        notification(1, type: 'check_in_clapped', claps: 1, crew: 'Climbers'),
        notification(2, type: 'check_in_clapped', claps: 3),
        notification(3, type: 'crew_nudge', pactTitle: null),
      ];
    await pumpNotifications(tester, backend);

    expect(find.byTooltip('Close notifications'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(
      find.textContaining('completed Climb twice.'),
      findsOneWidget,
      reason: 'a crew check-in reads as what they did',
    );
    expect(
      find.textContaining('clapped your Climb twice check-in.'),
      findsNWidgets(2),
    );
    // One clap names one person; several name the first and count the rest.
    expect(
      find.textContaining('Mirnes Halilovic clapped your'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mirnes Halilovic and 2 others clapped your'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mirnes Halilovic is cheering you on.'),
      findsOneWidget,
    );
    expect(find.text('Climbers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unread entries are marked, read ones are not', (tester) async {
    final backend = DashboardBackend()
      ..notifications = [
        notification(0),
        notification(1, read: true),
        notification(2, read: true),
      ];
    await pumpNotifications(tester, backend);

    // Opening the list clears it, so every row settles as read.
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsNothing);
    expect(backend.markedReadUpTo, backend.notifications.first.createdAt);
  });

  testWidgets('opening clears only as far as the newest shown', (tester) async {
    final backend = DashboardBackend()
      ..unreadNotifications = 3
      ..notifications = List.generate(3, notification.call);
    await pumpNotifications(tester, backend);

    expect(backend.markedReadUpTo, isNotNull);
    expect(
      backend.markedReadUpTo!.isAtSameMomentAs(
        backend.notifications.first.createdAt,
      ),
      isTrue,
      reason: 'anything that arrives after this point is still unread',
    );
  });

  testWidgets('pages in as the list is scrolled', (tester) async {
    final backend = DashboardBackend()
      ..notifications = List.generate(45, notification.call);
    await pumpNotifications(tester, backend);

    expect(find.textContaining('completed'), findsWidgets);
    final firstPass = backend.notificationPages;
    expect(firstPass, greaterThanOrEqualTo(1));

    await tester.drag(
      find.byKey(const ValueKey('notifications-list')),
      const Offset(0, -4000),
    );
    await tester.pumpUi();
    expect(
      backend.notificationPages,
      greaterThan(firstPass),
      reason: 'reaching the end asks for the next page',
    );

    // A short final page ends the list rather than asking forever.
    await tester.drag(
      find.byKey(const ValueKey('notifications-list')),
      const Offset(0, -8000),
    );
    await tester.pumpUi();
    await tester.drag(
      find.byKey(const ValueKey('notifications-list')),
      const Offset(0, -8000),
    );
    await tester.pumpUi();
    expect(find.text('That’s everything'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    await pumpNotifications(tester, DashboardBackend());
    expect(find.text('Nothing yet.'), findsOneWidget);
    expect(find.textContaining('land here'), findsOneWidget);
  });

  testWidgets('a failed read offers another go', (tester) async {
    final backend = DashboardBackend()..failNotifications = true;
    await pumpNotifications(tester, backend);

    expect(find.text('Could not load notifications.'), findsOneWidget);
    backend.failNotifications = false;
    backend.notifications = [notification(0)];
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.textContaining('completed Climb twice.'), findsOneWidget);
  });

  testWidgets('home carries the badge and opens the list', (tester) async {
    final backend = DashboardBackend()
      ..unreadNotifications = 4
      ..notifications = [notification(0)];
    await pumpHomeWithBell(tester, backend);

    final badge = find.byKey(const ValueKey('notifications-badge'));
    expect(badge, findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    // Top right, across from the crew's name.
    final bell = tester.getRect(
      find.byKey(const ValueKey('home-notifications')),
    );
    final header = tester.getRect(find.byKey(const ValueKey('home-header')));
    expect(bell.right, closeTo(header.right, 1));
    expect(bell.top, closeTo(header.top, 2));
    // Clear of the crew's name, which keeps the page's own middle.
    expect(
      bell.left,
      greaterThan(tester.getRect(find.text('Early Birds')).right),
    );

    await tester.tap(
      find.ancestor(of: badge, matching: find.byType(IconButton)),
    );
    await tester.pumpUi();
    expect(find.byTooltip('Close notifications'), findsOneWidget);

    // Closing hands the bell what is still unread, so the badge settles.
    await tester.tap(find.byTooltip('Close notifications'));
    await tester.pumpUi();
    expect(find.byTooltip('Close notifications'), findsNothing);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('no badge when nothing is unread', (tester) async {
    await pumpHomeWithBell(tester, DashboardBackend());
    final badge = find.byKey(const ValueKey('notifications-badge'));
    expect(badge, findsOneWidget);
    // The bell is still there; it simply wears nothing.
    expect(tester.widget<Badge>(badge).isLabelVisible, isFalse);
  });
}

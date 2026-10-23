import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/notifications/notifications_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/home/story_viewer.dart';
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
  int? pactIndex,
  Duration? age,
}) => NotificationEntry(
  eventId: 'event-$index',
  type: type,
  // Newest first, an hour apart, so ordering and the cursor are both visible.
  createdAt: DateTime.now().toUtc().subtract(
    age ?? Duration(minutes: index + 1),
  ),
  read: read,
  crewId: crew,
  crewName: crew,
  actorId: 'member-$index',
  displayName: name,
  pactTitle: pactTitle,
  iconKey: 'run',
  pactIndex: pactIndex,
  clapCount: claps,
);

/// A row, found by what it says aloud: the sentence, then the crew and when.
Finder row(Pattern text) =>
    find.bySemanticsLabel(text is String ? RegExp(RegExp.escape(text)) : text);

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
      home: NotificationsPage(backend: backend, viewerId: 'me'),
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
    expect(find.text('Notifications'), findsOneWidget);
    expect(
      row('completed Climb twice'),
      findsOneWidget,
      reason: 'a crew check-in reads as what they did',
    );
    expect(row('clapped your Climb twice check-in'), findsNWidgets(2));
    // One clap names one person; several name the first and count the rest.
    expect(row('Mirnes Halilovic clapped your'), findsOneWidget);
    expect(row('Mirnes Halilovic and 2 others clapped your'), findsOneWidget);
    expect(row('Mirnes Halilovic is cheering you on'), findsOneWidget);
    // Two crews, so each row says which it came from.
    expect(find.textContaining('Climbers ·'), findsOneWidget);
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

    // Opening the list clears it on the server, but what was new keeps its
    // mark for this visit — that is what the mark is for.
    expect(
      find.byKey(const ValueKey('notification-unread-dot')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notification-event-0')),
        matching: find.byKey(const ValueKey('notification-unread-dot')),
      ),
      findsOneWidget,
    );
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

  testWidgets('the page is named, beside its close', (tester) async {
    await pumpNotifications(tester, DashboardBackend());
    final title = find.byKey(const ValueKey('notifications-title'));
    expect(title, findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    // Level with the close button, in the middle of the row.
    final close = tester.getRect(find.byTooltip('Close notifications'));
    expect(tester.getCenter(title).dy, closeTo(close.center.dy, 1));
    expect(close.left, greaterThanOrEqualTo(tester.getRect(title).right));
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
    expect(row('completed Climb twice'), findsOneWidget);
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

  test('notices file under today, yesterday, the weeks, then the month', () {
    // Thursday 22 October 2026.
    final now = DateTime(2026, 10, 22, 15);
    String at(int month, int day, [int year = 2026]) =>
        notificationSection(DateTime(year, month, day, 9), now);
    expect(at(10, 22), 'Today');
    expect(at(10, 21), 'Yesterday');
    expect(at(10, 19), 'This week', reason: 'Monday starts the week');
    expect(at(10, 18), 'Last week', reason: 'the Sunday before it');
    expect(at(10, 12), 'Last week');
    expect(at(10, 11), 'October', reason: 'before last week, this month');
    expect(at(9, 30), 'September');
    expect(at(1, 2), 'January');
    expect(at(12, 31, 2025), 'December 2025');

    // On a Monday, yesterday is Sunday: Yesterday, not Last week.
    final monday = DateTime(2026, 10, 19, 8);
    expect(
      notificationSection(DateTime(2026, 10, 18, 20), monday),
      'Yesterday',
    );
    expect(
      notificationSection(DateTime(2026, 10, 17, 20), monday),
      'Last week',
    );
    expect(notificationSection(DateTime(2026, 10, 11, 20), monday), 'October');
  });

  testWidgets('sections run newest first, one label each', (tester) async {
    final backend = DashboardBackend()
      ..notifications = [
        notification(0, age: const Duration(minutes: 5)),
        notification(1, age: const Duration(minutes: 6)),
        notification(2, age: const Duration(days: 9)),
        notification(3, age: const Duration(days: 60)),
      ];
    await pumpNotifications(tester, backend);
    final now = DateTime.now();
    final labels = {
      for (final e in backend.notifications)
        notificationSection(e.createdAt.toLocal(), now).toUpperCase(),
    }.toList();
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    final tops = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(tops, [...tops]..sort());
    expect(tester.takeException(), isNull);
  });

  testWidgets('crew tabs cut the list to one crew, with its new count', (
    tester,
  ) async {
    final backend = DashboardBackend()
      ..notifications = [
        notification(0, crew: 'Climbers'),
        notification(1, crew: 'Early Birds'),
        notification(2, crew: 'Climbers', read: true),
      ];
    await pumpNotifications(tester, backend);
    expect(find.byKey(const ValueKey('notifications-tab-all')), findsOneWidget);
    expect(find.bySemanticsLabel('All, 2 new'), findsOneWidget);
    expect(find.bySemanticsLabel('Climbers, 1 new'), findsOneWidget);
    expect(find.bySemanticsLabel('Early Birds, 1 new'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-event-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notifications-tab-Climbers')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('notification-event-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-event-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-event-1')), findsNothing);
    // Cut to one crew, the rows stop saying which crew.
    expect(find.textContaining('Climbers ·'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('notifications-tab-all')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('notification-event-1')), findsOneWidget);
  });

  testWidgets('one crew needs no tabs', (tester) async {
    final backend = DashboardBackend()
      ..notifications = [notification(0), notification(1)];
    await pumpNotifications(tester, backend);
    expect(find.byKey(const ValueKey('notifications-tab-all')), findsNothing);
  });

  testWidgets('a pact shows as a chip in its colours, a badge says what', (
    tester,
  ) async {
    final backend = DashboardBackend()
      ..notifications = [
        notification(0, pactIndex: 2),
        notification(1, type: 'check_in_clapped', claps: 1),
        notification(2, type: 'crew_nudge', pactTitle: null),
      ];
    await pumpNotifications(tester, backend);
    ShapeDecoration fill(String key) =>
        tester.widget<Container>(find.byKey(ValueKey(key))).decoration!
            as ShapeDecoration;
    expect(fill('notification-pact-event-0').color, WeekPactColors.pactTint(2));
    // A pact the server sent no colour for is still a chip, in a neutral
    // wash rather than someone else's colour.
    expect(
      fill('notification-pact-event-1').color,
      isNot(WeekPactColors.pactTint(0)),
    );
    expect(
      find.byKey(const ValueKey('notification-pact-event-2')),
      findsNothing,
    );
    expect(
      fill('notification-badge-event-0').color,
      WeekPactColors.pactBadge(2),
    );
    expect(fill('notification-badge-event-1').color, WeekPactColors.brass);
    expect(fill('notification-badge-event-2').color, WeekPactColors.lantern);
  });

  test('a notice reads the check-in it is about, when the server says', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
      'event_id': 'event-1',
      'type': 'check_in_clapped',
      'created_at': '2026-09-09T10:00:00Z',
      'crew_id': 'crew',
      'actor_id': 'member-1',
      ...extra,
    };
    final checkIn = NotificationEntry.fromJson(
      row({
        'pact_id': 'read',
        'check_in_user_id': 'me',
        'check_in_day': '2026-09-09',
      }),
    ).checkIn;
    expect(checkIn?.crewId, 'crew');
    expect(checkIn?.pactId, 'read');
    expect(checkIn?.userId, 'me');
    expect(checkIn?.day, '2026-09-09');
    expect(NotificationEntry.fromJson(row()).checkIn, isNull);
    expect(
      NotificationEntry.fromJson(row({'pact_id': 'read'})).checkIn,
      isNull,
      reason: 'half a check-in names none',
    );
  });

  testWidgets('tapping a notice about a check-in opens its story', (
    tester,
  ) async {
    final backend = DashboardBackend(viewerId: 'me')
      ..notifications = [
        NotificationEntry(
          eventId: 'event-1',
          type: 'check_in_clapped',
          createdAt: DateTime.now().toUtc(),
          read: false,
          crewId: 'crew',
          crewName: 'Early Birds',
          actorId: 'member-1',
          displayName: 'Mirnes Halilovic',
          pactTitle: 'Read 20 pages',
          clapCount: 1,
          checkIn: const CheckInRef(
            crewId: 'crew',
            pactId: 'read',
            userId: 'me',
            day: '2026-09-09',
          ),
        ),
        notification(2, type: 'crew_nudge', pactTitle: null),
      ];
    await pumpNotifications(tester, backend);

    // A nudge has nothing behind it.
    await tester.tap(row('is cheering you on'));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsNothing);

    await tester.tap(row('clapped your Read 20 pages check-in'));
    await tester.pumpUi();
    expect(backend.openedCheckIns.single.pactId, 'read');
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.byKey(const ValueKey('story-pact')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('a check-in taken back since says so rather than opening', (
    tester,
  ) async {
    final backend = DashboardBackend(viewerId: 'me')
      ..notifications = [
        NotificationEntry(
          eventId: 'event-1',
          type: 'pact_completed',
          createdAt: DateTime.now().toUtc(),
          read: false,
          crewId: 'crew',
          crewName: 'Early Birds',
          actorId: 'other',
          displayName: 'Friend',
          pactTitle: 'Move for 30 min',
          checkIn: const CheckInRef(
            crewId: 'crew',
            pactId: 'move',
            userId: 'other',
            day: '2026-09-09',
          ),
        ),
      ];
    await pumpNotifications(tester, backend);
    await tester.tap(row('completed Move for 30 min'));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsNothing);
    expect(find.text('This check-in is no longer here.'), findsOneWidget);
  });
}

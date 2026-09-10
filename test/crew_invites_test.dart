import 'dart:async';

import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/theme_preference.dart';

import 'support/home_fakes.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/goals/goals_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/brutal_widgets.dart';

import 'widget_test.dart' show FakeCrewBackend;

ReceivedCrewInvite invitation() => ReceivedCrewInvite(
  id: 'invite-1',
  crewId: 'crew-1',
  name: 'Early Birds',
  timezone: 'Europe/Sarajevo',
  expiresAt: DateTime.now().add(const Duration(days: 7)),
  members: [
    CrewMember(
      userId: 'owner',
      email: 'owner@example.com',
      role: 'owner',
      joinedAt: DateTime(2026),
    ),
  ],
  goals: const [
    CrewGoal(
      id: 'goal-1',
      crewId: 'crew-1',
      title: 'Morning walk',
      frequency: GoalFrequency.weekly,
      daysPerWeek: 3,
    ),
  ],
);

class InboxBackend extends FakeCrewBackend {
  List<ReceivedCrewInvite> inbox = [invitation()];
  final responses = <bool>[];
  Object? fetchError;
  Object? responseError;
  Completer<void>? pending;

  @override
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites() async {
    if (fetchError != null) throw fetchError!;
    return List.unmodifiable(inbox);
  }

  @override
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) async {
    responses.add(accept);
    if (pending != null) await pending!.future;
    if (responseError != null) throw responseError!;
    final selected = inbox.singleWhere((i) => i.id == inviteId);
    if (accept) {
      crew = CrewDetails(
        id: selected.crewId,
        name: selected.name,
        timezone: selected.timezone,
        ownerId: 'owner',
        currentUserRole: 'member',
        members: selected.members,
        pendingInvites: [],
      );
    }
    inbox.removeWhere((i) => i.id == inviteId);
  }
}

Future<void> showInbox(WidgetTester tester, InboxBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: CrewPage(
          backend: backend,
          currentUserEmail: 'member@example.com',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('INVITES'));
  await tester.pumpAndSettle();
}

Future<void> openPreview(WidgetTester tester) async {
  await tester.tap(find.text('VIEW CREW'));
  await tester.pumpAndSettle();
}

void main() {
  for (final outcome in ['accept', 'decline', 'failure']) {
    testWidgets(
      'inbox $outcome navigates Home only after successful acceptance',
      (tester) async {
        final crews = InboxBackend();
        if (outcome == 'failure') crews.responseError = StateError('offline');
        final goals = JoinedCrewGoals(crews);
        final home = DashboardBackend(goals: goals);
        await tester.pumpWidget(
          MaterialApp(
            theme: WeekPactTheme.light,
            builder: (context, child) => ThemePreference(
              mode: ThemeMode.light,
              onChanged: (_) {},
              child: child!,
            ),
            home: HomePage(
              user: const AuthUser(email: 'member@example.com'),
              authBackend: const MissingConfigurationAuthBackend(),
              crewBackend: crews,
              goalsBackend: goals,
              homeBackend: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(home.fetches, 0);
        await tester.tap(find.byKey(const ValueKey('nav-crews')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('INVITES'));
        await tester.pumpAndSettle();
        await openPreview(tester);
        final action = find.text(
          outcome == 'decline' ? 'DECLINE INVITE' : 'ACCEPT INVITE',
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BrutalBottomNavigationBar>(
                find.byType(BrutalBottomNavigationBar),
              )
              .selectedIndex,
          outcome == 'accept' ? 0 : 2,
        );
        if (outcome == 'accept') {
          expect(home.fetches, greaterThan(0));
          expect(
            find.byKey(const ValueKey('check-in-Move for 30 min')),
            findsOneWidget,
          );
          expect(find.text('EARLY BIRDS'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('opens a crew preview before accepting and updates Your crew', (
    tester,
  ) async {
    final backend = InboxBackend();
    await showInbox(tester, backend);
    expect(find.text('YOUR CREW'), findsOneWidget);
    expect(find.text('ACCEPT INVITE'), findsNothing);
    await openPreview(tester);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('3 days / week'), findsOneWidget);
    expect(backend.responses, isEmpty);
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpAndSettle();
    expect(backend.responses, [true]);
    expect(find.text('EARLY BIRDS'), findsOneWidget);
    expect(find.text('DECLINE INVITE'), findsNothing);
  });

  testWidgets('declines an invitation without joining the crew', (
    tester,
  ) async {
    final backend = InboxBackend();
    await showInbox(tester, backend);
    await openPreview(tester);
    await tester.ensureVisible(find.text('DECLINE INVITE'));
    await tester.tap(find.text('DECLINE INVITE'));
    await tester.pumpAndSettle();
    expect(backend.responses, [false]);
    expect(backend.crew, isNull);
    expect(find.text('NO INVITES YET'), findsOneWidget);
  });

  testWidgets('back from preview leaves the invitation pending', (
    tester,
  ) async {
    final backend = InboxBackend();
    await showInbox(tester, backend);
    await openPreview(tester);
    await tester.tap(find.text('ALL INVITES'));
    await tester.pumpAndSettle();
    expect(find.text('VIEW CREW'), findsOneWidget);
    expect(backend.responses, isEmpty);
  });

  testWidgets(
    'existing crew members can preview and decline but cannot accept',
    (tester) async {
      final backend = InboxBackend();
      await backend.createCrew(name: 'My existing crew', timezone: 'UTC');
      await showInbox(tester, backend);
      await openPreview(tester);
      final accept = tester.widget<BrutalButton>(
        find.ancestor(
          of: find.text('ACCEPT INVITE'),
          matching: find.byType(BrutalButton),
        ),
      );
      expect(accept.onPressed, isNull);
      expect(find.textContaining('only join one crew'), findsOneWidget);
      await tester.ensureVisible(find.text('DECLINE INVITE'));
      await tester.tap(find.text('DECLINE INVITE'));
      await tester.pumpAndSettle();
      expect(backend.crew!.name, 'My existing crew');
      expect(backend.responses, [false]);
    },
  );

  testWidgets('inbox fetch failure can be retried', (tester) async {
    final backend = InboxBackend()..fetchError = StateError('offline');
    await showInbox(tester, backend);
    expect(find.text('NO INVITES YET'), findsNothing);
    backend.fetchError = null;
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(find.text('VIEW CREW'), findsOneWidget);
  });

  testWidgets(
    'a revoked invitation shows an error and refresh removes the preview',
    (tester) async {
      final backend = InboxBackend()
        ..responseError = StateError('This invitation is no longer available');
      await showInbox(tester, backend);
      await openPreview(tester);
      await tester.ensureVisible(find.text('ACCEPT INVITE'));
      await tester.tap(find.text('ACCEPT INVITE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('was revoked'), findsOneWidget);
      expect(backend.crew, isNull);
      backend.inbox.clear();
      await tester.ensureVisible(find.text('RETRY'));
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(find.text('NO INVITES YET'), findsOneWidget);
    },
  );

  testWidgets('prevents double responses while accepting', (tester) async {
    final backend = InboxBackend()..pending = Completer<void>();
    await showInbox(tester, backend);
    await openPreview(tester);
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pump();
    final decline = tester.widget<BrutalButton>(
      find.ancestor(
        of: find.text('DECLINE INVITE'),
        matching: find.byType(BrutalButton),
      ),
    );
    expect(decline.onPressed, isNull);
    expect(backend.responses, [true]);
    backend.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('EARLY BIRDS'), findsOneWidget);
  });

  testWidgets('tabs and preview fit a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = InboxBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: CrewPage(
            backend: backend,
            currentUserEmail: 'member@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('INVITES'));
    await tester.pumpAndSettle();
    await openPreview(tester);
    await tester.ensureVisible(find.text('DECLINE INVITE'));
    expect(tester.takeException(), isNull);
  });
}

class JoinedCrewGoals extends DashboardGoals {
  JoinedCrewGoals(this.backend);
  final InboxBackend backend;
  @override
  Future<List<GoalCrew>> fetchCrews() async {
    final crew = backend.crew;
    return crew == null
        ? []
        : [
            GoalCrew(
              id: crew.id,
              name: crew.name,
              timezone: crew.timezone,
              isOwner: crew.isOwner,
            ),
          ];
  }
}

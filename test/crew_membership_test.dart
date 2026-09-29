import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'package:weekpact/src/home/home_backend.dart';

import 'support/home_fakes.dart';
import 'widget_test.dart' show FakeCrewBackend;

class MembershipBackend extends FakeCrewBackend implements CrewDeletionBackend {
  final removed = <String>[];
  final deleted = <String>[];
  String? successor;
  Object? failure;
  Object? deleteFailure;
  int leaves = 0;

  @override
  Future<void> deleteCrew(String crewId) async {
    if (deleteFailure != null) throw deleteFailure!;
    deleted.add(crewId);
    crew = null;
  }

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) async {
    if (failure != null) throw failure!;
    successor = successorId;
    leaves++;
    crew = null;
  }

  @override
  Future<void> removeMember({
    required String crewId,
    required String userId,
  }) async {
    if (failure != null) throw failure!;
    removed.add(userId);
    final c = crew!;
    crew = CrewDetails(
      id: c.id,
      name: c.name,
      timezone: c.timezone,
      ownerId: c.ownerId,
      currentUserRole: c.currentUserRole,
      members: c.members.where((m) => m.userId != userId).toList(),
      pendingInvites: [],
    );
  }
}

CrewDetails details({bool owner = false, bool alone = false}) => CrewDetails(
  id: 'crew',
  name: 'Early Birds',
  timezone: 'UTC',
  ownerId: 'owner',
  currentUserRole: owner ? 'owner' : 'member',
  members: [
    CrewMember(
      userId: 'owner',
      email: 'owner@example.com',
      displayName: 'Alex',
      role: 'owner',
      joinedAt: DateTime(2026),
    ),
    if (!alone)
      CrewMember(
        userId: 'member',
        email: 'member@example.com',
        displayName: 'Sam',
        role: 'member',
        joinedAt: DateTime(2026),
      ),
  ],
  pendingInvites: [],
);
Future<void> showCrew(
  WidgetTester tester,
  MembershipBackend backend, {
  VoidCallback? onLeft,
  HomeBackend? profileBackend,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: CrewPage(
          backend: backend,
          profileBackend: profileBackend,
          currentUserEmail: backend.crew!.isOwner
              ? 'owner@example.com'
              : 'member@example.com',
          onCrewLeft: onLeft,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapDelete(WidgetTester tester) async {
  await tester.ensureVisible(find.text('DELETE CREW').first);
  await tester.tap(find.text('DELETE CREW').first);
  await tester.pumpAndSettle();
}

Future<void> tapLeave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('LEAVE CREW'));
  await tester.tap(find.text('LEAVE CREW'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('member can cancel, then leave and refresh navigation', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details();
    var left = false;
    await showCrew(tester, backend, onLeft: () => left = true);
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
    await tapLeave(tester);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(backend.leaves, 0);
    await tapLeave(tester);
    await tester.tap(find.text('LEAVE'));
    await tester.pumpAndSettle();
    expect(backend.leaves, 1);
    expect(left, isTrue);
    expect(find.text('CREATE CREW'), findsOneWidget);
  });
  testWidgets('the create form asks for a name and nothing else', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: CrewPage(
            backend: backend,
            currentUserEmail: 'owner@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start your crew'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsOneWidget);
    // The crew's week runs on the zone of the device it is made on, so there
    // is nothing here to choose and nothing to show. It used to carry a
    // read-only box holding whatever zone the build was compiled with.
    expect(find.text('UTC'), findsNothing);
    expect(find.text('Europe/Sarajevo'), findsNothing);
    expect(find.text('WEEK STARTS MONDAY'), findsNothing);
    // One field, and it is the name.
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('owner confirms removal and member list refreshes', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    expect(find.byTooltip('Remove Alex'), findsNothing);
    await tester.tap(find.byTooltip('Remove Sam'));
    await tester.pumpAndSettle();
    expect(backend.removed, isEmpty);
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    expect(backend.removed, ['member']);
    expect(find.text('Sam'), findsNothing);
  });
  testWidgets('owner must choose a replacement to leave', (tester) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    await tapLeave(tester);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'LEAVE'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('member@example.com').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('LEAVE'));
    await tester.pumpAndSettle();
    expect(backend.successor, 'member');
    expect(backend.leaves, 1);
  });
  testWidgets('only member owner is given guidance without leaving', (
    tester,
  ) async {
    final backend = MembershipBackend()
      ..crew = details(owner: true, alone: true);
    await showCrew(tester, backend);
    await tapLeave(tester);
    expect(find.text('You’re the only member'), findsOneWidget);
    expect(backend.leaves, 0);
  });
  testWidgets('failed removal keeps the member visible and shows an error', (
    tester,
  ) async {
    final backend = MembershipBackend()
      ..crew = details(owner: true)
      ..failure = StateError('offline');
    await showCrew(tester, backend);
    await tester.tap(find.byTooltip('Remove Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });
  testWidgets('a member is offered no way to delete the crew', (tester) async {
    final backend = MembershipBackend()..crew = details();
    await showCrew(tester, backend);
    expect(find.text('LEAVE CREW'), findsOneWidget);
    expect(find.text('DELETE CREW'), findsNothing);
  });
  testWidgets('the owner is told what deleting costs and can keep the crew', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    await tapDelete(tester);
    expect(find.text('Delete Early Birds?'), findsOneWidget);
    expect(find.textContaining('loses the crew, its pacts'), findsOneWidget);
    await tester.tap(find.text('Keep crew'));
    await tester.pumpAndSettle();
    expect(backend.deleted, isEmpty);
    expect(find.text('Sam'), findsOneWidget);
  });
  testWidgets('deleting ends the crew and lands on the empty state', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    var left = false;
    await showCrew(tester, backend, onLeft: () => left = true);
    await tapDelete(tester);
    // The dialog's own action, not the button on the page behind it.
    await tester.tap(find.text('DELETE CREW').last);
    await tester.pumpAndSettle();
    expect(backend.deleted, ['crew']);
    expect(left, isTrue);
    expect(find.text('CREATE CREW'), findsOneWidget);
  });
  testWidgets('a delete that fails leaves the crew and says so', (
    tester,
  ) async {
    final backend = MembershipBackend()
      ..crew = details(owner: true)
      ..deleteFailure = StateError('offline');
    await showCrew(tester, backend);
    await tapDelete(tester);
    await tester.tap(find.text('DELETE CREW').last);
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });
  testWidgets('the sole owner is told they can delete as well as hand over', (
    tester,
  ) async {
    final backend = MembershipBackend()
      ..crew = details(owner: true, alone: true);
    await showCrew(tester, backend);
    await tapLeave(tester);
    expect(find.textContaining('or delete the crew'), findsOneWidget);
  });
  testWidgets('a week that never arrives leaves the card saying so, not '
      'a bar', (tester) async {
    final profiles = DashboardBackend()..failLoad = true;
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend, profileBackend: profiles);
    expect(find.text('Couldn’t load'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    // The page below the roster stays quiet: one failure, one message.
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    final asked = profiles.fetches;
    profiles.failLoad = false;
    await tester.ensureVisible(find.text('RETRY'));
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(profiles.fetches, greaterThan(asked));
    expect(find.text('Couldn’t load'), findsNothing);
    expect(find.text('—'), findsNothing);
  });
}

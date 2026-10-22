import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crews_page.dart';
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
);
Future<void> showCrew(
  WidgetTester tester,
  MembershipBackend backend, {
  VoidCallback? onLeft,
  HomeBackend? profileBackend,
  ThemeData? theme,
}) async {
  // Pushed over a page of its own, the way the Crews list opens it, so that
  // leaving or ending the crew has somewhere to go back to.
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? WeekPactTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CrewPage(
                    crewId: 'crew',
                    backend: backend,
                    profileBackend: profileBackend,
                    currentUserEmail: backend.crew!.isOwner
                        ? 'owner@example.com'
                        : 'member@example.com',
                    onCrewLeft: onLeft,
                  ),
                ),
              ),
              child: const Text('OPEN CREW'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN CREW'));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Crew options'));
  await tester.pumpAndSettle();
}

Future<void> tapDelete(WidgetTester tester) async {
  await openMenu(tester);
  await tester.tap(find.text('Delete crew'));
  await tester.pumpAndSettle();
}

Future<void> tapLeave(WidgetTester tester) async {
  await openMenu(tester);
  await tester.tap(find.text('Leave crew'));
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
    // The page is about a crew they are no longer in, so it closes.
    expect(find.byType(CrewPage), findsNothing);
    expect(find.text('You left the crew.'), findsOneWidget);
  });
  testWidgets('the create form asks for a name, a description and a photo', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: CrewsPage(
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
    // The name, and an optional line about the crew.
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('DESCRIPTION'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
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
    await openMenu(tester);
    expect(find.text('Leave crew'), findsOneWidget);
    expect(find.text('Delete crew'), findsNothing);
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
  testWidgets('deleting ends the crew and closes its page', (tester) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    var left = false;
    await showCrew(tester, backend, onLeft: () => left = true);
    await tapDelete(tester);
    await tester.tap(find.text('DELETE CREW'));
    await tester.pumpAndSettle();
    expect(backend.deleted, ['crew']);
    expect(left, isTrue);
    expect(find.byType(CrewPage), findsNothing);
    expect(find.text('Crew deleted.'), findsOneWidget);
  });
  testWidgets('a delete that fails leaves the crew and says so', (
    tester,
  ) async {
    final backend = MembershipBackend()
      ..crew = details(owner: true)
      ..deleteFailure = StateError('offline');
    await showCrew(tester, backend);
    await tapDelete(tester);
    await tester.tap(find.text('DELETE CREW'));
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

  testWidgets('the crew menu reads on its cream card over the dark canvas', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend, theme: WeekPactTheme.dark);
    await openMenu(tester);
    // The page's own inks are drawn for the canvas, light on dark; the menu
    // is cream, so its entries have to be the card's dark inks instead.
    for (final label in ['Leave crew', 'Delete crew']) {
      final color = tester.widget<Text>(find.text(label)).style!.color!;
      expect(
        color.computeLuminance(),
        lessThan(.2),
        reason: '$label is light text on the cream menu',
      );
    }
  });
}

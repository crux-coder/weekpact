import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'widget_test.dart' show FakeCrewBackend;

class MembershipBackend extends FakeCrewBackend {
  final removed = <String>[];
  String? successor;
  Object? failure;
  int leaves = 0;
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
      role: 'owner',
      joinedAt: DateTime(2026),
    ),
    if (!alone)
      CrewMember(
        userId: 'member',
        email: 'member@example.com',
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: CrewPage(
          backend: backend,
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
  testWidgets('owner confirms removal and member list refreshes', (
    tester,
  ) async {
    final backend = MembershipBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    expect(find.byTooltip('Remove owner@example.com'), findsNothing);
    await tester.tap(find.byTooltip('Remove member@example.com'));
    await tester.pumpAndSettle();
    expect(backend.removed, isEmpty);
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    expect(backend.removed, ['member']);
    expect(find.text('member@example.com'), findsNothing);
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
    await tester.tap(find.byTooltip('Remove member@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();
    expect(find.text('member@example.com'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });
}

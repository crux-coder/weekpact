import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crews_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'crew_membership_test.dart'
    show MembershipBackend, details, openMenu, showCrew;

/// A photo the picker hands back: the smallest valid PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class EditingBackend extends MembershipBackend implements CrewEditingBackend {
  final edits = <({String name, String? description, Uint8List? avatar})>[];

  @override
  Future<CrewDetails> updateCrew({
    required String crewId,
    required String name,
    String? description,
    Uint8List? avatar,
  }) async {
    edits.add((name: name, description: description, avatar: avatar));
    final c = crew!;
    crew = CrewDetails(
      id: c.id,
      name: name.trim(),
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      timezone: c.timezone,
      ownerId: c.ownerId,
      currentUserRole: c.currentUserRole,
      members: c.members,
    );
    return crew!;
  }
}

void main() {
  testWidgets('a member is offered no way to edit the crew', (tester) async {
    final backend = EditingBackend()..crew = details();
    await showCrew(tester, backend);
    expect(
      find.byKey(const ValueKey('crew-page-add-description')),
      findsNothing,
    );
    await openMenu(tester);
    expect(find.text('Edit crew'), findsNothing);
  });

  testWidgets('the owner renames the crew and describes it', (tester) async {
    final backend = EditingBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    await openMenu(tester);
    await tester.tap(find.text('Edit crew'));
    await tester.pumpAndSettle();

    final name = find.descendant(
      of: find.byKey(const ValueKey('crew-editor-name')),
      matching: find.byType(TextFormField),
    );
    expect(tester.widget<TextFormField>(name).controller!.text, 'Early Birds');
    await tester.enterText(name, 'Night Owls');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('crew-editor-description')),
        matching: find.byType(TextFormField),
      ),
      'Up late, still showing up.',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(backend.edits.single.name, 'Night Owls');
    expect(backend.edits.single.avatar, isNull);
    expect(find.byKey(const ValueKey('crew-page-title')), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('Up late, still showing up.'), findsOneWidget);
  });

  testWidgets('a name too short is not saved', (tester) async {
    final backend = EditingBackend()..crew = details(owner: true);
    await showCrew(tester, backend);
    await tester.tap(find.byKey(const ValueKey('crew-page-add-description')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('crew-editor-name')),
        matching: find.byType(TextFormField),
      ),
      'A',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 2 characters'), findsOneWidget);
    expect(backend.edits, isEmpty);
  });

  testWidgets('a new crew is made with its description and photo', (
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
            pickCrewAvatar: () async => _png,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    expect(find.text('Change photo'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Early Birds');
    await tester.enterText(fields.at(1), 'Five runs a week.');
    await tester.ensureVisible(find.text('CREATE CREW'));
    await tester.tap(find.text('CREATE CREW'));
    await tester.pumpAndSettle();

    expect(backend.createdCrews, ['Early Birds']);
    expect(backend.crew!.description, 'Five runs a week.');
    expect(backend.createdAvatar, _png);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/pacts/pacts_page.dart';
import 'package:weekpact/src/pacts/pact_icons.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

const ownerCrew = PactCrew(
  id: 'a',
  name: 'Early Birds',
  timezone: 'Europe/Sarajevo',
  isOwner: true,
);
const memberCrew = PactCrew(
  id: 'b',
  name: 'Weekend Crew',
  timezone: 'UTC',
  isOwner: false,
);

class FakePacts implements PactsBackend {
  List<PactCrew> crews = [ownerCrew, memberCrew];
  final pacts = <CrewPact>[];
  Completer<List<PactCrew>>? loading;
  bool failSave = false;
  final deleted = <String>[];
  bool failDelete = false;

  @override
  Future<void> deletePact({
    required String pactId,
    required String crewId,
  }) async {
    if (failDelete) throw Exception('offline');
    deleted.add(pactId);
    pacts.removeWhere((pact) => pact.id == pactId && pact.crewId == crewId);
  }
  @override
  Future<CrewPact> updatePact({
    required String pactId,
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
    required bool photoRequired,
  }) async {
    if (failSave) throw Exception('offline');
    final index = pacts.indexWhere(
      (pact) => pact.id == pactId && pact.crewId == crewId,
    );
    return pacts[index] = CrewPact(
      id: pactId,
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
      photoRequired: photoRequired,
    );
  }

  @override
  Future<List<PactCrew>> fetchCrews() => loading?.future ?? Future.value(crews);
  @override
  Future<List<CrewPact>> fetchPacts(String crewId) async =>
      pacts.where((pact) => pact.crewId == crewId).toList();
  @override
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
    bool photoRequired = true,
  }) async {
    if (failSave) throw Exception('offline');
    final pact = CrewPact(
      id: '${pacts.length}',
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
      photoRequired: photoRequired,
    );
    pacts.add(pact);
    return pact;
  }
}

/// Opens a bar's menu and picks one of its entries. Editing and deleting both
/// live behind the bar's one button, so every test that reaches either has to
/// go through here.
Future<void> openPactMenu(
  WidgetTester tester,
  String title,
  String entry,
) async {
  await tester.ensureVisible(find.byTooltip('$title options'));
  await tester.tap(find.byTooltip('$title options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

Future<void> pumpPacts(WidgetTester tester, FakePacts backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: PactsPage(
          backend: backend,
          userId: 'me',
          loadWeek: (id) async => CrewWeek(
            today: '2026-09-15',
            weekStart: '2026-09-14',
            timezone: 'UTC',
            pacts: await backend.fetchPacts(id),
            members: [],
            checkIns: [],
          ),
          onOpenCrews: () {},
        ),
      ),
    ),
  );
}

void main() {
  test('unknown and legacy icons fall back to target', () {
    expect(PactIcon.find('unknown').key, 'target');
    expect(
      CrewPact.fromJson({
        'id': '1',
        'crew_id': 'a',
        'title': 'Read',
        'frequency': 'daily',
        'days_per_week': 7,
      }).iconKey,
      'target',
    );
  });
  testWidgets(
    'owner edits an existing pact and retries without losing changes',
    (tester) async {
      final backend = FakePacts();
      backend.pacts.add(
        const CrewPact(
          id: 'g',
          crewId: 'a',
          title: 'Read',
          frequency: PactFrequency.weekly,
          daysPerWeek: 3,
          iconKey: 'book',
        ),
      );
      await pumpPacts(tester, backend);
      await tester.pumpAndSettle();
      await openPactMenu(tester, 'Read', 'Edit pact');
      expect(find.text('EDIT PACT'), findsOneWidget);
      expect(find.byTooltip('Change icon: Reading'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Read',
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Read every day',
      );
      await tester.tap(find.text('Every day'));
      backend.failSave = true;
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load or save'), findsOneWidget);
      expect(backend.pacts.single.title, 'Read');
      backend.failSave = false;
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(backend.pacts.single.id, 'g');
      expect(backend.pacts.single.title, 'Read every day');
      expect(backend.pacts.single.daysPerWeek, 7);
      expect(backend.pacts.single.iconKey, 'book');
      expect(find.text('Read every day'), findsNWidgets(2));
    },
  );

  testWidgets('members cannot see edit actions', (tester) async {
    final backend = FakePacts()..crews = [memberCrew];
    backend.pacts.add(
      const CrewPact(
        id: 'g',
        crewId: 'b',
        title: 'Read',
        frequency: PactFrequency.daily,
        daysPerWeek: 7,
      ),
    );
    await pumpPacts(tester, backend);
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsNWidgets(2));
    expect(find.byTooltip('Read options'), findsNothing);
  });

  testWidgets('shows skeleton while loading and a crew-specific empty state', (
    tester,
  ) async {
    final backend = FakePacts()..loading = Completer<List<PactCrew>>();
    await pumpPacts(tester, backend);
    expect(find.text('Pacts'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('ADD PACT'), findsNothing);
    backend.loading!.complete([ownerCrew]);
    await tester.pumpAndSettle();
    expect(find.text('Small steps start here.'), findsOneWidget);
    expect(find.text('ADD PACT'), findsOneWidget);
  });

  testWidgets('owner saves daily and weekly pacts to the selected crew', (
    tester,
  ) async {
    final backend = FakePacts();
    await pumpPacts(tester, backend);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ADD PACT'));
    await tester.tap(find.text('ADD PACT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE PACT'));
    await tester.pumpAndSettle();
    expect(find.text('Use 2–100 characters'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Read 20 pages');
    await tester.ensureVisible(find.byTooltip('Change icon: Target'));
    await tester.tap(find.byTooltip('Change icon: Target'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'read');
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsNothing);
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change icon: Reading'), findsOneWidget);
    await tester.ensureVisible(find.text('SAVE PACT'));
    await tester.tap(find.text('SAVE PACT'));
    await tester.pumpAndSettle();
    expect(backend.pacts.single.iconKey, 'book');
    expect(backend.pacts.single.daysPerWeek, 7);
    expect(backend.pacts.single.frequency, PactFrequency.daily);
    expect(backend.pacts.single.crewId, 'a');
    expect(find.text('Read 20 pages'), findsNWidgets(2));

    await tester.ensureVisible(find.text('ADD PACT'));
    await tester.tap(find.text('ADD PACT'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Go for a run');
    await tester.tap(find.text('Days per week'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SAVE PACT'));
    await tester.tap(find.text('SAVE PACT'));
    await tester.pumpAndSettle();
    expect(backend.pacts.last.frequency, PactFrequency.weekly);
    expect(backend.pacts.last.daysPerWeek, 3);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Go for a run. 3 days / week. Photo check-in',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byTooltip('Switch crew'));
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend Crew').last);
    await tester.pumpAndSettle();
    expect(find.text('Read 20 pages'), findsNothing);
    expect(find.text('ADD PACT'), findsNothing);
    expect(
      find.text('Your crew owner hasn’t added any pacts yet.'),
      findsOneWidget,
    );
  });

  testWidgets('failed save retains form and supports retry', (tester) async {
    final backend = FakePacts()..failSave = true;
    await pumpPacts(tester, backend);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ADD PACT'));
    await tester.tap(find.text('ADD PACT'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Walk outside');
    await tester.ensureVisible(find.text('SAVE PACT'));
    await tester.tap(find.text('SAVE PACT'));
    await tester.pumpAndSettle();
    expect(find.text('Walk outside'), findsOneWidget);
    expect(
      find.text(
        'Could not load or save pacts. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    backend.failSave = false;
    await tester.ensureVisible(find.text('SAVE PACT'));
    await tester.tap(find.text('SAVE PACT'));
    await tester.pumpAndSettle();
    expect(backend.pacts.length, 1);
    expect(find.text('ADD A PACT'), findsNothing);
  });

  testWidgets(
    'the photo requirement is a per-pact choice that survives an edit',
    (tester) async {
      final backend = FakePacts();
      await pumpPacts(tester, backend);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ADD PACT'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Tidy one thing');
      expect(find.text('Checking in takes a picture.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pact-photo-required')),
      );
      await tester.tap(find.byKey(const ValueKey('pact-photo-required')));
      await tester.pumpAndSettle();
      expect(find.text('A tap is enough. No picture needed.'), findsOneWidget);
      await tester.ensureVisible(find.text('SAVE PACT'));
      await tester.tap(find.text('SAVE PACT'));
      await tester.pumpAndSettle();
      expect(backend.pacts.single.photoRequired, isFalse);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Tidy one thing. Every day · 7 days / week. '
                      'No photo needed',
        ),
        findsOneWidget,
      );

      // Reopening the pact shows the saved choice, and it can be turned back on.
      await openPactMenu(tester, 'Tidy one thing', 'Edit pact');
      expect(find.text('A tap is enough. No picture needed.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pact-photo-required')),
      );
      await tester.tap(find.byKey(const ValueKey('pact-photo-required')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(backend.pacts.single.photoRequired, isTrue);
      // The bar no longer carries a camera badge, so the round trip is read
      // off the one place the setting is still spoken: the bar's semantics.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Tidy one thing. Every day · 7 days / week. Photo check-in',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('owner deletes a pact, after confirming and not before', (
    tester,
  ) async {
    final backend = FakePacts();
    backend.pacts.addAll(const [
      CrewPact(
        id: 'g',
        crewId: 'a',
        title: 'Read',
        frequency: PactFrequency.weekly,
        daysPerWeek: 3,
      ),
      CrewPact(
        id: 'h',
        crewId: 'a',
        title: 'Walk',
        frequency: PactFrequency.weekly,
        daysPerWeek: 2,
      ),
    ]);
    await pumpPacts(tester, backend);
    await tester.pumpAndSettle();

    // Backing out of the confirmation leaves the pact where it was.
    await openPactMenu(tester, 'Read', 'Delete pact');
    expect(find.text('Delete pact?'), findsOneWidget);
    expect(
      find.textContaining('every check-in the crew has ever made'),
      findsOneWidget,
    );
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(backend.deleted, isEmpty);
    expect(backend.pacts.length, 2);

    // A failed delete says so and keeps the pact.
    backend.failDelete = true;
    await openPactMenu(tester, 'Read', 'Delete pact');
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load or save'), findsOneWidget);
    expect(backend.pacts.length, 2);

    backend.failDelete = false;
    await openPactMenu(tester, 'Read', 'Delete pact');
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();
    expect(backend.deleted, ['g']);
    expect(backend.pacts.single.id, 'h');
    // The page reloads the week rather than trusting its own list, so the bar
    // is gone from the list and from the progress card above it.
    expect(find.text('Read'), findsNothing);
    expect(find.text('Walk'), findsNWidgets(2));
  });

  testWidgets('members are offered no pact menu at all', (tester) async {
    final backend = FakePacts()..crews = [memberCrew];
    backend.pacts.add(
      const CrewPact(
        id: 'g',
        crewId: 'b',
        title: 'Read',
        frequency: PactFrequency.daily,
        daysPerWeek: 7,
      ),
    );
    await pumpPacts(tester, backend);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pact-menu-g')), findsNothing);
  });

  testWidgets('users without crews get a crews action', (tester) async {
    await pumpPacts(tester, FakePacts()..crews = []);
    await tester.pumpAndSettle();
    expect(find.text('GO TO CREWS'), findsOneWidget);
    expect(find.text('ADD PACT'), findsNothing);
  });
}

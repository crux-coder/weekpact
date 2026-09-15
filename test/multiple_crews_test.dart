import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeCrewBackend;

class MultipleCrews extends FakeCrewBackend {
  final entries = <CrewDetails>[];
  final fetched = <String>[];
  MultipleCrews() {
    entries.add(details('crew', 'Early Birds'));
    entries.add(details('second', 'Night Owls'));
  }
  static CrewDetails details(String id, String name) => CrewDetails(
    id: id,
    name: name,
    timezone: 'UTC',
    ownerId: 'owner-id',
    currentUserRole: 'owner',
    members: [],
    pendingInvites: [],
  );
  @override
  Future<List<PactCrew>> fetchCrews() async => [
    for (final c in entries)
      PactCrew(
        id: c.id,
        name: c.name,
        timezone: c.timezone,
        isOwner: c.isOwner,
      ),
  ];
  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) async {
    final selected =
        entries.where((c) => c.id == crewId).firstOrNull ?? entries.first;
    fetched.add(selected.id);
    return selected;
  }

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    final c = details('third', name);
    entries.add(c);
    return c;
  }
}

class CrewPacts extends DashboardPacts {
  final requested = <String>[];
  @override
  Future<List<CrewPact>> fetchPacts(String crewId) async {
    requested.add(crewId);
    return super.fetchPacts(crewId);
  }
}

class CrewHome extends DashboardBackend {
  CrewHome(DashboardPacts pacts) : super(pacts: pacts);
  final requested = <String>[];
  @override
  Future<CrewWeek> fetchWeek(String crewId) {
    requested.add(crewId);
    return super.fetchWeek(crewId);
  }
}

void main() {
  testWidgets(
    'create another crew preserves the previous crews and selects the new one',
    (tester) async {
      final backend = MultipleCrews();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: Scaffold(
            body: CrewPage(
              backend: backend,
              currentUserEmail: 'owner@example.com',
              onCrewSelected: (id) => selected = id,
            ),
          ),
        ),
      );
      await tester.pumpUi();
      await tester.tap(find.byTooltip('Create another crew'));
      await tester.pumpUi();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Weekend Walkers',
      );
      await tester.ensureVisible(find.text('CREATE CREW'));
      await tester.tap(find.text('CREATE CREW'));
      await tester.pumpUi();
      expect(backend.entries.map((c) => c.name), [
        'Early Birds',
        'Night Owls',
        'Weekend Walkers',
      ]);
      expect(selected, 'third');
      expect(find.text('Weekend Walkers'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch crew'));
      await tester.pumpUi();
      await tester.tap(find.text('Early Birds').last);
      await tester.pumpUi();
      expect(backend.fetched.last, 'crew');
      expect(selected, 'crew');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('crew selection follows the user between Home, Pacts and Crews', (
    tester,
  ) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: HomePage(
          user: const AuthUser(email: 'owner@example.com'),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: crews,
          pactsBackend: pacts,
          homeBackend: home,
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Night Owls').last);
    await tester.pumpUi();
    expect(home.requested.last, 'second');
    await tester.tap(find.text('Pacts').last);
    await tester.pumpUi();
    expect(pacts.requested.last, 'second');
    await tester.tap(find.text('Crews').last);
    await tester.pumpUi();
    expect(crews.fetched.last, 'second');
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Early Birds').last);
    await tester.pumpUi();
    await tester.tap(find.text('Home').last);
    await tester.pumpUi();
    expect(home.requested.last, 'crew');
    expect(tester.takeException(), isNull);
  });
}

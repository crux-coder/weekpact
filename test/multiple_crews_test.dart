import 'dart:typed_data';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekpact/src/crew/crew_selection_store.dart';
import 'package:weekpact/src/crew/crew_switcher.dart';
import 'package:weekpact/src/crew/crew_page_layout.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crews_page.dart';
import 'package:weekpact/src/crew/crew_roster.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_backend.dart';
import 'package:weekpact/src/subscriptions/subscription_scope.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeCrewBackend;
import 'subscription_test.dart' show FakeSubscriptionBackend;

class MultipleCrews extends FakeCrewBackend {
  Completer<List<PactCrew>>? loading;

  /// Holds [fetchCrew] while set, the way [loading] holds the list.
  Completer<void>? crewLoading;
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
  );
  @override
  Future<List<PactCrew>> fetchCrews() async => loading != null
      ? await loading!.future
      : [
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
    await crewLoading?.future;
    final selected =
        entries.where((c) => c.id == crewId).firstOrNull ?? entries.first;
    fetched.add(selected.id);
    return selected;
  }

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
    String? description,
    Uint8List? avatar,
  }) async {
    final c = details('third', name);
    entries.add(c);
    return c;
  }
}

class CrewPacts extends DashboardPacts {
  Completer<List<PactCrew>>? loading;
  @override
  Future<List<PactCrew>> fetchCrews() => loading?.future ?? super.fetchCrews();
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
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) {
    requested.add(crewId);
    return super.fetchWeek(crewId);
  }
}

/// [MultipleCrews] with the one thing the crew page needs to offer the door.
class DeletableCrews extends MultipleCrews implements CrewDeletionBackend {
  @override
  Future<void> deleteCrew(String crewId) async {
    entries.removeWhere((c) => c.id == crewId);
  }
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'the crews list and a crew share the loading shell at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final crews = MultipleCrews()
          ..loading = Completer<List<PactCrew>>()
          ..crewLoading = Completer<void>();
        Future<void> render(Widget page) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: WeekPactTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(body: page),
            ),
          );
          await tester.pump();
        }

        await render(
          CrewsPage(backend: crews, currentUserEmail: 'owner@example.com'),
        );
        // Each page stands in for its own content, so only the shared shell
        // has to line up: opening a crew mid-load must not shift the page.
        final skeletonTop = tester.getTopLeft(find.byType(CrewPageSkeleton));
        // The list chooses the crew, so neither page carries a switcher.
        expect(find.byType(CrewSwitcher), findsNothing);
        expect(find.byType(CrewsListSkeleton), findsOneWidget);
        await render(
          CrewPage(
            crewId: 'crew',
            backend: crews,
            currentUserEmail: 'owner@example.com',
          ),
        );
        expect(tester.getTopLeft(find.byType(CrewPageSkeleton)), skeletonTop);
        expect(find.byType(CrewRosterSkeleton), findsOneWidget);
        expect(find.byType(CrewsListSkeleton), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'create another crew preserves the previous crews and selects the new one',
    (tester) async {
      final backend = MultipleCrews();
      String? selected;
      // A second crew is a Pro feature, so this flow only exists for a
      // subscriber; crew_limit_test covers what a free account sees instead.
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: SubscriptionScope(
            controller: SubscriptionController(
              FakeSubscriptionBackend(
                initial: const ProAccess(active: true, willRenew: true),
              ),
            ),
            child: Scaffold(
              body: CrewsPage(
                backend: backend,
                currentUserEmail: 'owner@example.com',
                onCrewSelected: (id) => selected = id,
              ),
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
      // Every crew is still listed, the new one with them.
      for (final name in ['Early Birds', 'Night Owls', 'Weekend Walkers']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.text('Early Birds'));
      await tester.pumpUi();
      expect(find.byType(CrewPage), findsOneWidget);
      expect(backend.fetched.last, 'crew');
      expect(selected, 'crew');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('crew selection follows the user between Home and Crews', (
    tester,
  ) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = CrewSelectionStore(preferences);
    Future<void> launch() => tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: HomePage(
          crewSelectionStore: store,
          user: const AuthUser(email: 'owner@example.com'),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: crews,
          pactsBackend: pacts,
          homeBackend: home,
        ),
      ),
    );
    await launch();
    await tester.pumpUi();
    // Opening a crew from the list makes it the crew Home shows.
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();
    await tester.tap(find.text('Night Owls'));
    await tester.pumpUi();
    expect(find.byType(CrewPage), findsOneWidget);
    expect(crews.fetched.last, 'second');
    await tester.tap(find.byTooltip('Back to crews'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpUi();
    expect(home.requested.last, 'second');
    expect(store.read('owner@example.com'), 'second');
    await tester.pumpWidget(const SizedBox());
    home.requested.clear();
    await launch();
    await tester.pumpUi();
    expect(home.requested, ['second']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the switcher opens on a tap, and only on a tap', (tester) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: HomePage(
          crewSelectionStore: CrewSelectionStore(preferences),
          user: const AuthUser(email: 'owner@example.com'),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: crews,
          pactsBackend: pacts,
          homeBackend: home,
        ),
      ),
    );
    await tester.pumpUi();
    final switcher = find.byType(CrewSwitcher);
    // A pull down the control's face is no longer a gesture it answers: the
    // crews stay in the hand and only the crew on the page is named.
    await tester.drag(switcher, const Offset(0, 220));
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsNothing);
    await tester.tap(switcher);
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsWidgets);
    // A second tap on the control sends the hand back. The fan redraws the
    // switcher over its own scrim, so the tap lands on the scrim rather than
    // on the control behind it — either way, the hand leaves.
    await tester.tap(switcher, warnIfMissed: false);
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home switches crews from its own selector', (tester) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = CrewSelectionStore(preferences);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: HomePage(
          crewSelectionStore: store,
          user: const AuthUser(email: 'owner@example.com'),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: crews,
          pactsBackend: pacts,
          homeBackend: home,
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('home-crew-switcher')), findsOneWidget);
    expect(find.text('Early Birds'), findsWidgets);
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Night Owls').last);
    await tester.pumpUi();
    // The week follows the switch, and the choice is kept for the other
    // destinations and for the next run.
    expect(home.requested.last, 'second');
    expect(store.read('owner@example.com'), 'second');
    expect(find.text('Night Owls'), findsWidgets);
    // The control keeps its slot in the heading through the switch, rather
    // than going down with the page while the new week loads.
    expect(find.byKey(const ValueKey('home-crew-switcher')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved crews are per account and unavailable crews fall back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'selected_crew:account-a': 'second',
    });
    final preferences = await SharedPreferences.getInstance();
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    Future<void> launch(String accountId, {String? initialCrewId}) async {
      await tester.pumpWidget(const SizedBox());
      home.requested.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            user: AuthUser(id: accountId, email: '$accountId@example.com'),
            initialCrewId: initialCrewId,
            crewSelectionStore: CrewSelectionStore(preferences),
            authBackend: const MissingConfigurationAuthBackend(),
            crewBackend: crews,
            pactsBackend: pacts,
            homeBackend: home,
          ),
        ),
      );
      await tester.pumpUi();
    }

    await launch('account-a');
    expect(home.requested, ['second']);
    await launch('account-b');
    expect(home.requested, ['crew']);
    await launch('account-a');
    expect(home.requested, ['second']);
    // Accepting an invitation explicitly selects that crew and remembers it.
    await launch('account-b', initialCrewId: 'second');
    await launch('account-b');
    expect(home.requested, ['second']);
    pacts.crews = [pacts.crews.first];
    await launch('account-a');
    // Home starts on the saved crew's week beside the crews list; the list
    // no longer has it, so the page falls back and shows the first crew.
    expect(home.requested, ['second', 'crew']);
    expect(find.text('Early Birds'), findsWidgets);
    expect(preferences.getString('selected_crew:account-a'), 'crew');
    expect(preferences.getString('selected_crew:account-b'), 'second');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading shapes stand where the loaded page\'s do', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final crews = MultipleCrews()..crewLoading = Completer<void>();
    crews.entries[0] = CrewDetails(
      id: 'crew',
      name: 'Early Birds',
      timezone: 'UTC',
      ownerId: 'owner-id',
      currentUserRole: 'owner',
      createdAt: DateTime(2026, 9, 7),
      members: [
        for (var i = 0; i < 3; i++)
          CrewMember(
            userId: 'member-$i',
            email: 'member-$i@example.com',
            displayName: 'Member $i',
            role: i == 0 ? 'owner' : 'member',
            joinedAt: DateTime(2026),
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: CrewPage(
            crewId: 'crew',
            backend: crews,
            currentUserEmail: 'member-0@example.com',
          ),
        ),
      ),
    );
    await tester.pump();

    // The skeleton opens on the summary card, not on the caption bar the page
    // used to open with, and the roster stands the same distance under it in
    // both states — so nothing jumps down the page when the crew lands.
    expect(find.byType(CrewRosterSkeleton), findsOneWidget);
    final card = find.byKey(const ValueKey('crew-summary-card'));
    expect(tester.getSize(card).height, CrewSummaryCard.height);
    expect(find.text('IN THE CREW'), findsOneWidget);
    final loadingDrop =
        tester.getTopLeft(find.byType(CrewBand).first).dy -
        tester.getTopLeft(card).dy;

    crews.crewLoading!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CrewRosterSkeleton), findsNothing);
    expect(find.byType(CrewPersonBand), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.byType(CrewPersonBand).first).dy -
          tester.getTopLeft(card).dy,
      loadingDrop,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deleting a crew from its page goes back to the list without it',
    (tester) async {
      final crews = DeletableCrews();
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: Scaffold(
            body: CrewsPage(
              backend: crews,
              currentUserEmail: 'owner@example.com',
              onCrewSelected: selected.add,
            ),
          ),
        ),
      );
      await tester.pumpUi();
      await tester.tap(find.text('Night Owls'));
      await tester.pumpUi();
      expect(selected.last, 'second');

      await tester.tap(find.byTooltip('Crew options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete crew'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DELETE CREW'));
      await tester.pumpAndSettle();

      // Back on the list, which has the crew that is left and not the one gone.
      expect(crews.entries.map((c) => c.id), ['crew']);
      expect(find.byType(CrewPage), findsNothing);
      expect(find.text('Early Birds'), findsOneWidget);
      expect(find.text('Night Owls'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

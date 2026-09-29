import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekpact/src/crew/crew_selection_store.dart';
import 'package:weekpact/src/crew/crew_switcher.dart';
import 'package:weekpact/src/crew/crew_page_layout.dart';
import 'package:weekpact/src/pacts/pacts_overview.dart';
import 'package:weekpact/src/pacts/pacts_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
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
      'Pacts and Crews share the loading shell at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final crews = MultipleCrews()..loading = Completer<List<PactCrew>>();
        final pacts = CrewPacts()..loading = Completer<List<PactCrew>>();
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
          PactsPage(
            backend: pacts,
            userId: '',
            loadWeek: DashboardBackend(pacts: pacts).fetchWeek,
            onOpenCrews: () {},
          ),
        );
        // Each page stands in for its own content, so only the shared shell
        // above the progress line has to line up: switching tabs mid-load must
        // not shift the progress line.
        final skeletonTop = tester.getTopLeft(find.byType(CrewPageSkeleton));
        final indicatorBounds = tester.getRect(
          find.byType(LinearProgressIndicator),
        );
        // The crew's name is the page's title now and lives in the header, so
        // the loading shell no longer stands a card in for a control that
        // lands somewhere else.
        expect(find.byType(CrewHeaderSurface), findsNothing);
        expect(find.byType(CrewSwitcher), findsNothing);
        expect(find.byType(PactsSkeletonBody), findsOneWidget);
        await render(
          CrewPage(backend: crews, currentUserEmail: 'owner@example.com'),
        );
        expect(tester.getTopLeft(find.byType(CrewPageSkeleton)), skeletonTop);
        expect(
          tester.getRect(find.byType(LinearProgressIndicator)),
          indicatorBounds,
        );
        expect(find.byType(CrewRosterSkeleton), findsOneWidget);
        expect(find.byType(PactsSkeletonBody), findsNothing);
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
              body: CrewPage(
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
    // The crew is switched from Pacts here, and Home is expected to have
    // followed it when you come back — Home carries a switcher of its own,
    // which the test below drives.
    await tester.tap(find.text('Pacts').last);
    await tester.pumpUi();
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Night Owls').last);
    await tester.pumpUi();
    await tester.tap(find.text('Home').last);
    await tester.pumpUi();
    expect(home.requested.last, 'second');
    expect(store.read('owner@example.com'), 'second');
    await tester.pumpWidget(const SizedBox());
    home.requested.clear();
    await launch();
    await tester.pumpUi();
    expect(home.requested, ['second']);
    await tester.drag(
      find.byKey(const ValueKey('home-refresh-viewport')),
      const Offset(0, 500),
    );
    await tester.pumpUi();
    expect(home.requested.last, 'second');
    final beforePacts = home.requested.length;
    await tester.tap(find.text('Pacts').last);
    await tester.pumpUi();
    expect(home.requested.length, greaterThan(beforePacts));
    expect(home.requested.last, 'second');
    // Where the crew's name actually lands, which is what somebody crossing
    // between tabs sees. The switcher's own box fills whatever slot the page
    // leaves it, and those differ — Crews keeps two controls clear at either
    // end of the row and Pacts keeps none — so the box is not the thing to
    // measure here.
    final pactsName = tester.getRect(find.text('Night Owls').hitTestable());
    final pactsSelectorBounds = tester.getRect(
      find.byType(CrewSwitcher).hitTestable(),
    );
    await tester.tap(find.text('Crews').last);
    await tester.pumpUi();
    expect(crews.fetched.last, 'second');
    // The name does not move between tabs: the controls are laid over the row
    // rather than set beside the name, and the row keeps the page's middle
    // either way.
    expect(tester.getRect(find.text('Night Owls').hitTestable()), pactsName);
    // And the slot itself stays on the page's middle, at one height.
    final crewsSelectorBounds = tester.getRect(
      find.byType(CrewSwitcher).hitTestable(),
    );
    expect(crewsSelectorBounds.center, pactsSelectorBounds.center);
    expect(crewsSelectorBounds.height, pactsSelectorBounds.height);
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Early Birds').last);
    await tester.pumpUi();
    await tester.tap(find.text('Home').last);
    await tester.pumpUi();
    expect(home.requested.last, 'crew');
    expect(store.read('owner@example.com'), 'crew');
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
    await tester.tap(find.text('Pacts').last);
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsWidgets);
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
    expect(home.requested, ['crew']);
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
    final crews = MultipleCrews()..loading = Completer<List<PactCrew>>();
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
      pendingInvites: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: CrewPage(
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

    final gate = crews.loading!;
    // Cleared before the gate opens: `fetchCrews` waits on this very completer
    // while it is set, so asking the fake for the answer it is about to give
    // would be asking it to wait for itself.
    crews.loading = null;
    gate.complete(await crews.fetchCrews());
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

  testWidgets('deleting the crew you are reading falls back to another one', (
    tester,
  ) async {
    final crews = DeletableCrews();
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: CrewPage(
            backend: crews,
            currentUserEmail: 'owner@example.com',
            selectedCrewId: 'second',
            onCrewSelected: selected.add,
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsOneWidget);

    await tester.ensureVisible(find.text('DELETE CREW').first);
    await tester.tap(find.text('DELETE CREW').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE CREW').last);
    await tester.pumpAndSettle();

    // The crew that is left, not the empty state and not the crew that is gone.
    expect(crews.entries.map((c) => c.id), ['crew']);
    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsNothing);
    expect(selected.last, 'crew');
    expect(tester.takeException(), isNull);
  });
}

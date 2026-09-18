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
  Future<CrewWeek> fetchWeek(String crewId) {
    requested.add(crewId);
    return super.fetchWeek(crewId);
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
        // not shift the selector or the progress line.
        final skeletonTop = tester.getTopLeft(find.byType(CrewPageSkeleton));
        final selectorBounds = tester.getRect(find.byType(CrewHeaderSurface));
        final indicatorBounds = tester.getRect(
          find.byType(LinearProgressIndicator),
        );
        expect(find.byType(PactsSkeletonBody), findsOneWidget);
        await render(
          CrewPage(backend: crews, currentUserEmail: 'owner@example.com'),
        );
        expect(tester.getTopLeft(find.byType(CrewPageSkeleton)), skeletonTop);
        expect(tester.getRect(find.byType(CrewHeaderSurface)), selectorBounds);
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

  testWidgets('a held finger is not a pull and leaves the hand away', (
    tester,
  ) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    final home = CrewHome(pacts);
    SharedPreferences.setMockInitialValues({});
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
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Switch crew')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpUi();
    expect(find.text('Switch to Night Owls'), findsNothing);
    // Pushing the card up is not a pull either — the page keeps that drag.
    await gesture.moveBy(const Offset(0, -60));
    await tester.pumpUi();
    expect(find.text('Switch to Night Owls'), findsNothing);
    await gesture.up();
    await tester.pumpUi();
    expect(
      find.descendant(
        of: find.byTooltip('Switch crew'),
        matching: find.text('Early Birds'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hand deals the crew you are on at the top', (tester) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
    SharedPreferences.setMockInitialValues({
      'selected_crew:owner@example.com': 'second',
    });
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
          homeBackend: CrewHome(pacts),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    // 'Night Owls' is the crew on the header, so its card is the one that
    // lands directly under the switcher.
    final owls = tester.getRect(find.text('Night Owls').last);
    final birds = tester.getRect(find.text('Early Birds').last);
    expect(owls.top, lessThan(birds.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pull deals the hand and leaves it out to choose from', (
    tester,
  ) async {
    final crews = MultipleCrews();
    final pacts = CrewPacts()..crews = await crews.fetchCrews();
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
          homeBackend: CrewHome(pacts),
        ),
      ),
    );
    await tester.pumpUi();
    // Anywhere on the card pulls, not only the grip at its foot.
    final pull = await tester.startGesture(
      tester.getCenter(find.byTooltip('Switch crew')),
    );
    await pull.moveBy(const Offset(0, 40));
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsWidgets);
    // Letting go of the pull is not an answer: the hand stays dealt, and the
    // cards that landed under the finger are not picked by lifting it.
    await pull.up();
    await tester.pumpUi();
    expect(find.text('Night Owls'), findsWidgets);
    expect(store.read('owner@example.com'), isNot('second'));
    await tester.tap(find.text('Night Owls').last);
    await tester.pumpUi();
    expect(store.read('owner@example.com'), 'second');
    expect(find.text('Night Owls'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Night Owls').last);
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
    final pactsSelectorBounds = tester.getRect(
      find.byType(CrewSwitcher).hitTestable(),
    );
    await tester.tap(find.text('Crews').last);
    await tester.pumpUi();
    expect(crews.fetched.last, 'second');
    expect(
      tester.getRect(find.byType(CrewSwitcher).hitTestable()),
      pactsSelectorBounds,
    );
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
}

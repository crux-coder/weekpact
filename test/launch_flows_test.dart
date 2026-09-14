import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_sharing.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/onboarding/crew_setup_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/recaps/weekly_recap.dart';
import 'package:weekpact/src/sharing/app_share.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

class SetupCrew extends MissingCrewBackend {
  CrewDetails? crew;
  int created = 0;
  @override
  Future<CrewDetails?> fetchCrew() async => crew;
  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    created++;
    return crew = CrewDetails(
      id: 'crew',
      name: name,
      timezone: timezone,
      ownerId: '',
      currentUserRole: 'owner',
      members: [
        CrewMember(
          userId: '',
          email: '',
          role: 'owner',
          joinedAt: DateTime.now(),
        ),
      ],
      pendingInvites: [],
    );
  }
}

class SetupPacts extends DashboardPacts {
  SetupPacts() {
    pacts = [];
  }
  bool fail = false;
  @override
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) async {
    if (fail) throw StateError('offline');
    final pact = CrewPact(
      id: 'new',
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
    );
    pacts.add(pact);
    return pact;
  }
}

class Sharing implements CrewSharingBackend {
  CrewShareLink? link;
  int created = 0;
  bool fail = false;
  @override
  Future<CrewShareLink?> manageShareLink(String crewId, String action) async {
    if (fail) throw StateError('offline');
    if (action == 'create') {
      created++;
      return link = CrewShareLink(
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        token: 'a' * 64,
      );
    }
    if (action == 'revoke') {
      link = null;
      return null;
    }
    return link;
  }
}

class ShareFake implements AppShare {
  final texts = <String>[];
  int images = 0;
  bool fail = false;
  @override
  Future<void> text(String text, Rect origin) async {
    if (fail) throw StateError('cancelled');
    texts.add(text);
  }

  @override
  Future<void> image(Uint8List png, Rect origin) async {
    images++;
  }
}

const recap = WeeklyRecap(
  weekStart: '2026-09-07',
  checkIns: 18,
  activeMembers: 3,
  completedPacts: 2,
  totalPacts: 3,
  earned: false,
);

class RecapHome extends DashboardBackend implements RecapBackend {
  bool seen = false;
  bool fail = false;
  int marks = 0;
  @override
  Future<WeeklyRecap?> fetchRecap(String crewId, {String? markSeen}) async {
    if (fail) throw StateError('offline');
    if (markSeen != null) {
      seen = true;
      marks++;
    }
    return WeeklyRecap(
      weekStart: recap.weekStart,
      checkIns: 18,
      activeMembers: 3,
      completedPacts: 2,
      totalPacts: 3,
      earned: false,
      seen: seen,
    );
  }
}

void main() {
  testWidgets('guided setup creates one crew, edits starter, and checks in', (
    tester,
  ) async {
    final crews = SetupCrew();
    final pacts = SetupPacts();
    final home = DashboardBackend(pacts: pacts);
    home.selected.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CrewSetupPage(
                  crewBackend: crews,
                  pactsBackend: pacts,
                  homeBackend: home,
                  userId: '',
                ),
              ),
            ),
            child: const Text('Begin'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Begin'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextField), 'Sunday People');
    await tester.tap(find.text('Create crew'));
    await tester.pumpUi();
    expect(crews.created, 1);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await tester.tap(find.text('Choose a starter pact'));
    await tester.pumpUi();
    await tester.tap(find.text('Read 20 pages'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextFormField), 'Read 10 pages');
    final save = find.text('SAVE PACT');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpUi();
    expect(pacts.pacts.single.title, 'Read 10 pages');
    expect(pacts.pacts.single.daysPerWeek, 4);
    await tester.ensureVisible(find.text('Continue to first check-in'));
    await tester.tap(find.text('Continue to first check-in'));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('I did it today'));
    await tester.tap(find.text('I did it today'));
    await tester.pumpUi();
    expect(home.selected, {'new'});
    expect(crews.created, 1);
    expect(find.text('Begin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('setup resumes saved crew and pact without recreating them', (
    tester,
  ) async {
    final crews = SetupCrew();
    await crews.createCrew(name: 'Crew', timezone: 'UTC');
    await tester.pumpWidget(
      MaterialApp(
        home: CrewSetupPage(
          crewBackend: crews,
          pactsBackend: DashboardPacts(),
          homeBackend: DashboardBackend(),
          userId: '',
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(crews.created, 1);
  });
  testWidgets('invite share retries the same token and can revoke it', (
    tester,
  ) async {
    final backend = Sharing();
    final share = ShareFake()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrewShareControls(
            backend: backend,
            crewId: 'crew',
            share: share,
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('Create & share link'));
    await tester.pumpUi();
    expect(backend.created, 1);
    expect(
      find.text('Could not share the link. Please try again.'),
      findsOneWidget,
    );
    share.fail = false;
    await tester.tap(find.text('Share invite link'));
    await tester.pumpUi();
    expect(backend.created, 1);
    expect(share.texts.single, contains('/invite/?invite='));
    await tester.tap(find.text('Revoke invite link'));
    await tester.pumpUi();
    expect(backend.link, isNull);
    expect(find.text('Create & share link'), findsOneWidget);
  });
  testWidgets(
    'recap appears on returning home, saves seen state and stays accessible',
    (tester) async {
      final backend = RecapHome();
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: HomePage(
            user: const AuthUser(email: ''),
            authBackend: const MissingConfigurationAuthBackend(),
            crewBackend: const MissingCrewBackend(),
            pactsBackend: backend.pacts,
            homeBackend: backend,
          ),
        ),
      );
      await tester.pumpUi();
      expect(find.byType(WeeklyRecapPage), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpUi();
      expect(backend.marks, 1);
      expect(find.byTooltip('Last week’s recap'), findsOneWidget);
      await tester.tap(find.byTooltip('Last week’s recap'));
      await tester.pumpUi();
      expect(find.byType(WeeklyRecapPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('recap failure never blocks today’s check-ins', (tester) async {
    final backend = RecapHome()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: HomePage(
          user: const AuthUser(email: ''),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: const MissingCrewBackend(),
          pactsBackend: backend.pacts,
          homeBackend: backend,
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.byType(WeeklyRecapPage), findsNothing);
    expect(find.text('Early Birds'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('recap fits $size with large text and anonymous totals', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const WeeklyRecapPage(recap: recap),
        ),
      );
      await tester.pumpUi();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('18'), findsOneWidget);
    });
  }
}

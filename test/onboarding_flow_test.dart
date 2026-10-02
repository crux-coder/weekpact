import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/app.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/invites/invite_acceptance_page.dart';
import 'package:weekpact/src/invites/invite_link_entry.dart';
import 'package:weekpact/src/onboarding/crew_setup_page.dart';
import 'package:weekpact/src/onboarding/crew_start_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'launch_flows_test.dart' show SetupCrew, SetupPacts;
import 'support/home_fakes.dart';
import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

const _preview = CrewInvitePreview(
  crewName: 'Early Birds',
  memberCount: 3,
  ownerName: 'Ada Lovelace',
);

Future<void> _signUp(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  await tester.enterText(find.byType(TextFormField).at(2), 'password123');
  await tester.ensureVisible(find.text('CREATE ACCOUNT'));
  await tester.tap(find.text('CREATE ACCOUNT'));
  await tester.pumpUi();
}

Future<void> _giveName(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'Mia');
  await tester.ensureVisible(find.text('LET’S GO'));
  await tester.tap(find.text('LET’S GO'));
  await tester.pumpUi();
}

void main() {
  test('a pasted link gives up its token in any of the shapes it is sent', () {
    expect(
      inviteTokenFromText('https://weekpact.app/invite?invite=abc123'),
      'abc123',
    );
    expect(
      inviteTokenFromText(' weekpact.app/invite/?invite=abc123 '),
      'abc123',
    );
    expect(inviteTokenFromText('weekpact://invite?invite=abc123'), 'abc123');
    expect(
      inviteTokenFromText('Qm7xk2pLw9vRt4sYd8nHf3'),
      'Qm7xk2pLw9vRt4sYd8nHf3',
    );
    expect(inviteTokenFromText('hello'), isNull);
    expect(inviteTokenFromText('https://weekpact.app/'), isNull);
    expect(inviteTokenFromText(''), isNull);
  });

  testWidgets('the front door leads a pasted link to its crew, and the crew '
      'to an account', (tester) async {
    final auth = FakeAuthBackend(onboardingCompleted: false);
    final crews = FakeCrewBackend()..preview = _preview;
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
      ),
    );
    await tester.pumpUi();
    expect(find.text('Good habits.\nGreat company.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('I HAVE AN INVITE LINK'));
    await tester.pumpUi();
    await tester.enterText(
      find.byType(TextFormField),
      'https://weekpact.app/invite?invite=share-token',
    );
    await tester.tap(find.text('FIND MY CREW'));
    await tester.pumpUi();

    // The crew, before any form: only what the invitation may say about it.
    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.text('3 members · started by Ada Lovelace'), findsOneWidget);
    await tester.tap(find.text('JOIN EARLY BIRDS'));
    await tester.pumpUi();
    expect(find.text('Make it official.'), findsOneWidget);
    expect(find.text('Joining Early Birds'), findsOneWidget);

    await _signUp(tester);
    expect(auth.lastEmailRedirectTo, 'weekpact://invite?invite=share-token');
    expect(find.text('JOINING EARLY BIRDS'), findsOneWidget);
    await _giveName(tester);

    // A joiner is never asked who they are doing this with.
    expect(find.byType(CrewStartPage), findsNothing);
    expect(find.byType(InviteAcceptancePage), findsOneWidget);
    expect(find.text('Join Early Birds'), findsOneWidget);
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();
    expect(crews.acceptedTokens, ['share-token']);
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('a new account with no link is asked who it is doing this '
      'with, and a pasted link there opens the invitation', (tester) async {
    final auth = FakeAuthBackend(onboardingCompleted: false);
    final crews = FakeCrewBackend()..preview = _preview;
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('START A NEW CREW'));
    await tester.pumpUi();
    await _signUp(tester);
    expect(find.text('ALMOST THERE'), findsOneWidget);
    await _giveName(tester);

    expect(find.byType(CrewStartPage), findsOneWidget);
    expect(find.text('Who are you doing this with, Mia?'), findsOneWidget);
    await tester.tap(find.text('I’ve got a link'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextFormField), 'not a link');
    await tester.tap(find.text('FIND MY CREW'));
    await tester.pumpUi();
    expect(
      find.text('That doesn’t look like a WeekPact invite link.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'weekpact.app/invite?invite=late-token',
    );
    await tester.tap(find.text('FIND MY CREW'));
    await tester.pumpUi();

    expect(find.byType(InviteAcceptancePage), findsOneWidget);
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();
    expect(crews.acceptedTokens, ['late-token']);
    expect(find.byType(CrewStartPage), findsNothing);
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('skipping the question opens Home, whose empty state asks it '
      'again', (tester) async {
    final auth = FakeAuthBackend(onboardingCompleted: false);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts()..crews = [],
        authBackend: auth,
        crewBackend: FakeCrewBackend(),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('START A NEW CREW'));
    await tester.pumpUi();
    await _signUp(tester);
    await _giveName(tester);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpUi();

    expect(find.byType(CrewStartPage), findsNothing);
    expect(find.text('START YOUR CREW'), findsOneWidget);
    await tester.tap(find.text('START YOUR CREW'));
    await tester.pumpUi();
    expect(find.byType(CrewStartPage), findsOneWidget);
    expect(find.text('I’ve got a link'), findsOneWidget);
  });

  testWidgets('going solo runs the setup without the invitation step', (
    tester,
  ) async {
    final crews = SetupCrew();
    final pacts = SetupPacts();
    final home = DashboardBackend(pacts: pacts);
    home.selected.clear();
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: CrewStartPage(
          crewBackend: crews,
          pactsBackend: pacts,
          homeBackend: home,
          userId: '',
          captureCheckInPhoto: captureTestCheckInPhoto,
          onInviteToken: (_) {},
          onDone: () => done++,
        ),
      ),
    );
    await tester.tap(find.text('Just me, for now'));
    await tester.pumpUi();
    expect(find.byType(CrewSetupPage), findsOneWidget);
    expect(find.text('Start solo'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Just you, for now.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'My week');
    await tester.tap(find.text('Create crew'));
    await tester.pumpUi();
    expect(crews.created, 1);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.tap(find.text('Choose a starter pact'));
    await tester.pumpUi();
    await tester.tap(find.text('Read 20 pages'));
    await tester.pumpUi();
    final save = find.text('SAVE PACT');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpUi();

    // Straight from the pact to the first check-in: nobody to invite yet.
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Continue to first check-in'), findsNothing);
    expect(find.text('I did it today'), findsOneWidget);
    await tester.ensureVisible(find.text('I did it today'));
    await tester.tap(find.text('I did it today'));
    await tester.pumpUi();
    await submitTestPhoto(tester);
    expect(home.selected, {'new'});
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logging out returns to the log-in form, not the front door', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.text('Already in?  LOG IN'));
    await tester.pumpUi();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpUi();
    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpUi();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('START A NEW CREW'), findsNothing);
    expect(auth.currentUser, isNull);
  });
}

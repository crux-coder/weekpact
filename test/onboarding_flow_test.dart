import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/app.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/onboarding/onboarding_draft.dart';

import 'launch_flows_test.dart' show SetupPacts;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart'
    show FakeAuthBackend, FakeCrewBackend, FakeInviteLinkSource;

const _inviter = '6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b';

const _preview = CrewInvitePreview(
  crewName: 'Early Birds',
  memberCount: 4,
  ownerName: 'Amra',
  inviterName: 'Edin',
  inviterInitials: 'EK',
  memberInitials: ['AM', 'EK', 'LS', 'NH'],
  pacts: [InvitePact(title: 'Go for a run', iconKey: 'run', daysPerWeek: 3)],
);

/// A phone-sized screen, the size the flow is designed for.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpUi();
}

void main() {
  group('invite codes', () {
    test('a code is six letters and digits, typed in any case', () {
      expect(normalizeInviteCode('7k2qxm'), '7K2QXM');
      expect(normalizeInviteCode(' 7K2 QXM '), '7K2QXM');
      expect(normalizeInviteCode('7K2-QXM'), '7K2QXM');
      // Look-alikes are not in the alphabet, so a typo is caught, not sent.
      expect(normalizeInviteCode('7K2QX0'), isNull);
      expect(normalizeInviteCode('7K2QXI'), isNull);
      expect(normalizeInviteCode('7K2QX'), isNull);
      expect(normalizeInviteCode('7K2QXMM'), isNull);
    });

    test('links carry the code and who shared it', () {
      expect(
        inviteFromUri(
          Uri.parse(
            'https://weekpact.codepeaktrail.dev/invite/?code=7k2qxm&from=$_inviter',
          ),
        ),
        const InviteRef('7K2QXM', from: _inviter),
      );
      expect(
        inviteFromUri(Uri.parse('weekpact://invite?code=7K2QXM&from=nope')),
        const InviteRef('7K2QXM'),
      );
      // Links shared before codes keep working until they expire.
      final legacy = 'a' * 64;
      expect(
        inviteFromUri(Uri.parse('weekpact://invite?invite=$legacy')),
        InviteRef(legacy),
      );
      expect(
        inviteFromUri(Uri.parse('weekpact://invite?invite=short')),
        isNull,
      );
    });

    test('typed text can be a code, a link, or a link without its scheme', () {
      expect(inviteFromText('7k2qxm'), const InviteRef('7K2QXM'));
      expect(
        inviteFromText('weekpact.codepeaktrail.dev/invite/?code=7K2QXM'),
        const InviteRef('7K2QXM'),
      );
      expect(inviteFromText('hello'), isNull);
      expect(inviteFromText(''), isNull);
    });

    test('the share link points at the invite page', () {
      expect(
        inviteUrl('7K2QXM', from: _inviter).toString(),
        'https://weekpact.codepeaktrail.dev/invite/?code=7K2QXM&from=$_inviter',
      );
    });
  });

  testWidgets('a new crew: name, pact, Apple, invite later, first check-in', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend(onboardingStep: OnboardingStep.profile);
    final crews = FakeCrewBackend();
    final pacts = SetupPacts();
    final home = DashboardBackend(viewerId: 'user-id', pacts: pacts);
    final drafts = OnboardingDraftStore.memory();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        crewBackend: crews,
        pactsBackend: pacts,
        homeBackend: home,
        onboardingDraftStore: drafts,
      ),
    );
    await tester.pumpUi();

    expect(find.text('Good habits.\nGreat company.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('get-started')));

    // Prefilled, so Continue works without typing.
    expect(find.text('Name your crew.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Morning Runners');
    await _tap(tester, find.byKey(const ValueKey('crew-name-continue')));
    expect(drafts.read()?.crewName, 'Morning Runners');

    expect(
      find.text('What will Morning Runners keep up first?'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Read'));
    await _tap(tester, find.byTooltip('More days'));
    await _tap(tester, find.byKey(const ValueKey('pact-continue')));
    expect(drafts.read()?.complete, isTrue);

    expect(find.text('Save your week.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('sign-in-apple')));

    expect(auth.providerSignIns, [SignInProvider.apple]);
    expect(crews.createdCrews, ['Morning Runners']);
    expect(pacts.pacts.single.title, 'Read');
    expect(pacts.pacts.single.daysPerWeek, 4);
    expect(pacts.pacts.single.photoRequired, isFalse);
    expect(drafts.read(), isNull, reason: 'the draft is now a crew');
    expect(auth.advancedSteps, [OnboardingStep.done]);

    expect(find.text('Bring your people.'), findsOneWidget);
    expect(find.text('7'), findsOneWidget, reason: 'the code is on screen');
    await _tap(tester, find.byKey(const ValueKey('invite-later')));

    expect(find.text('You’re in, Mia.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('first-check-in')));
    expect(home.selected, contains('new'));
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('a half-finished setup reopens where it was left', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend();
    final drafts = OnboardingDraftStore.memory();
    await drafts.save(const OnboardingDraft(crewName: 'Early Risers'));
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(authBackend: auth, onboardingDraftStore: drafts),
    );
    await tester.pumpUi();

    expect(find.text('What will Early Risers keep up first?'), findsOneWidget);
    await _tap(tester, find.byTooltip('Back'));
    expect(find.text('Name your crew.'), findsOneWidget);
    expect(find.text('Early Risers'), findsOneWidget);
  });

  testWidgets('closing the provider sheet keeps the person on Save', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend(cancelSignIn: true);
    final drafts = OnboardingDraftStore.memory();
    await drafts.save(
      const OnboardingDraft(
        crewName: 'Early Risers',
        pactTitle: 'Read',
        pactIcon: 'book',
        pactDays: 3,
      ),
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(authBackend: auth, onboardingDraftStore: drafts),
    );
    await tester.pumpUi();
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));

    expect(find.text('Save your week.'), findsOneWidget);
    expect(drafts.read()?.complete, isTrue);
  });

  testWidgets('Apple keeping the name private asks for a first name', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend(providerName: '');
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
      ),
    );
    await tester.pumpUi();
    await _tap(tester, find.byKey(const ValueKey('welcome-log-in')));
    await _tap(tester, find.byKey(const ValueKey('sign-in-apple')));

    expect(find.text('What should the crew call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Jasmin');
    await _tap(tester, find.byKey(const ValueKey('name-continue')));
    expect(auth.currentUser?.firstName, 'Jasmin');
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('an invite link: the inviter first, then one tap to join', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend()..preview = _preview;
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        crewBackend: crews,
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?code=7K2QXM&from=$_inviter'),
        ),
      ),
    );
    await tester.pumpUi();

    expect(crews.previewedFrom, contains(_inviter));
    expect(find.text('Edin invited you.'), findsOneWidget);
    expect(find.text('Go for a run'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('join-crew')));

    expect(find.text('Join Early Birds.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));

    // They tapped Join already; signing in is the join.
    expect(crews.acceptedTokens, ['7K2QXM']);
    expect(find.byKey(const ValueKey('home-crew-panel')), findsOneWidget);
  });

  testWidgets('a code that no longer works says so', (tester) async {
    _phone(tester);
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        crewBackend: crews,
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?code=7K2QXM'),
        ),
      ),
    );
    await tester.pumpUi();

    expect(find.text('This invite doesn’t work anymore.'), findsOneWidget);
    await _tap(tester, find.text('ENTER A DIFFERENT CODE'));
    expect(find.text('Enter your invite code.'), findsOneWidget);
  });

  testWidgets('a code typed on the crew-name screen opens that crew', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend()..preview = _preview;
    addTearDown(auth.dispose);
    await tester.pumpWidget(WeekPactApp(authBackend: auth, crewBackend: crews));
    await tester.pumpUi();
    await _tap(tester, find.byKey(const ValueKey('get-started')));
    await _tap(tester, find.text('Got an invite code instead?'));

    await tester.enterText(
      find.byKey(const ValueKey('invite-code-field')),
      '7k2qxm',
    );
    await _tap(tester, find.text('FIND MY CREW'));
    expect(find.text('Edin invited you.'), findsOneWidget);
  });

  testWidgets('logging out opens on Log in, not the front door', (
    tester,
  ) async {
    _phone(tester);
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
      ),
    );
    await tester.pumpUi();
    await _tap(tester, find.byKey(const ValueKey('welcome-log-in')));
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
    await auth.signOut();
    await tester.pumpUi();
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Good habits.\nGreat company.'), findsNothing);
  });
}

import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

import 'package:weekpact/src/pacts/pacts_backend.dart';

import 'package:weekpact/src/widgets/page_frame.dart';

import 'dart:typed_data';

import 'support/home_fakes.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:weekpact/src/app.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crew_sharing.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

void main() {
  testWidgets('account has no appearance setting and always uses dark theme', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpUi();
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Light'), findsNothing);
    expect(find.text('Dark'), findsNothing);
    expect(find.text('Device'), findsNothing);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpUi();
    expect(
      Theme.of(tester.element(find.text('Account').first)).brightness,
      Brightness.dark,
    );
  });

  testWidgets(
    'crew shows skeletons and preserves content during pull to refresh',
    (tester) async {
      final crews = DelayedCrewBackend();
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.light,
          home: Scaffold(
            body: CrewPage(
              backend: crews,
              currentUserEmail: 'owner@example.com',
            ),
          ),
        ),
      );
      expect(find.text('Crews'), findsWidgets);
      expect(find.byType(SkeletonBar), findsWidgets);
      expect(find.text('CREATE CREW'), findsNothing);
      expect(find.byTooltip('Refresh crew'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      crews.pending.complete(null);
      await tester.pumpUi();
      expect(find.text('CREATE CREW'), findsOneWidget);
      crews.pending = Completer<CrewDetails?>();
      await tester.dragFrom(const Offset(400, 80), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(crews.fetches, 2);
      expect(find.text('CREATE CREW'), findsOneWidget);
      crews.pending.completeError(Exception('Network unavailable'));
      await tester.pumpUi();
      expect(find.text('CREATE CREW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switches between login and signup', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('CONFIRM PASSWORD'), findsNothing);

    final modeButton = find.text('New here?  CREATE ACCOUNT');
    await tester.ensureVisible(modeButton);
    await tester.tap(modeButton);
    await tester.pumpUi();

    expect(find.text('Make it official.'), findsOneWidget);
    expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
  });

  testWidgets('validates login fields before calling Supabase', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.tap(find.text('LOG IN'));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('submits signup and handles email confirmation', (tester) async {
    final auth = FakeAuthBackend(
      signUpResult: SignUpResult.emailConfirmationRequired,
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    final modeButton = find.text('New here?  CREATE ACCOUNT');
    await tester.ensureVisible(modeButton);
    await tester.tap(modeButton);
    await tester.pumpUi();

    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    final submitButton = find.text('CREATE ACCOUNT');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpUi();

    expect(auth.signUpCalls, 1);
    expect(auth.lastEmailRedirectTo, 'weekpact://invite');
    expect(
      find.text('Check your email to confirm your account.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back.'), findsOneWidget);
    // Supabase emits the signed-in session after exchanging the email callback.
    auth.confirmEmail('new@example.com');
    await tester.pumpUi();
    expect(find.text('Welcome back.'), findsNothing);
    expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('signup confirmation retains the pending crew invitation', (
    tester,
  ) async {
    final auth = FakeAuthBackend(
      signUpResult: SignUpResult.emailConfirmationRequired,
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      WeekPactApp(
        authBackend: auth,
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?invite=crew-token'),
        ),
      ),
    );
    await tester.pumpUi();
    final mode = find.text('New here?  CREATE ACCOUNT');
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpUi();
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.ensureVisible(find.text('CREATE ACCOUNT'));
    await tester.tap(find.text('CREATE ACCOUNT'));
    await tester.pumpUi();
    expect(auth.lastEmailRedirectTo, 'weekpact://invite?invite=crew-token');
    auth.confirmEmail('new@example.com');
    await tester.pumpUi();
    expect(find.text('Your crew is waiting.'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('signs in, shows account, and signs out', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.bySemanticsLabel('Checked in today · 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Not yet today · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpUi();

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpUi();

    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('switches between signed-in destinations', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.text('Early Birds'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-pacts')));
    await tester.pumpUi();

    expect(find.text('Pacts'), findsWidgets);
    expect(find.text('Your pacts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();

    expect(find.text('Crews'), findsWidgets);
    expect(find.text('Start your crew'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpUi();

    expect(find.text('Account'), findsWidgets);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets(
    'shows every navigation label beneath an equally sized destination',
    (tester) async {
      final auth = FakeAuthBackend();
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        WeekPactApp(
          homeBackend: DashboardBackend(),
          pactsBackend: DashboardPacts(),
          authBackend: auth,
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'person@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.text('LOG IN'));
      await tester.pumpUi();

      final homeButton = find.byKey(const ValueKey('nav-home'));
      final homeIcon = find.descendant(
        of: homeButton,
        matching: find.byType(HugeIcon),
      );
      final homeLabel = find.descendant(
        of: homeButton,
        matching: find.text('Home'),
      );

      expect(
        tester.getCenter(homeIcon).dy,
        lessThan(tester.getCenter(homeLabel).dy),
      );
      for (final label in ['Crews', 'Pacts', 'Account']) {
        final destination = find.byKey(ValueKey('nav-${label.toLowerCase()}'));
        expect(
          tester.getSize(destination).width,
          tester.getSize(homeButton).width,
        );
        expect(
          find.descendant(of: destination, matching: find.text(label)),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('shows daily pacts and checks in directly', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        captureCheckInPhoto: captureTestCheckInPhoto,
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.text('Your pacts'), findsNothing);
    expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
    expect(find.text('Check in').hitTestable(), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
    );
    await tester.pumpUi();
    await submitTestPhoto(tester);
    expect(find.text('Checked in today'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
    );
    await tester.pumpUi();
    expect(find.text('Check in').hitTestable(), findsOneWidget);
  });

  testWidgets('slides horizontally between destinations', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    final initialHomeX = tester.getTopLeft(find.text('Early Birds')).dx;
    await tester.tap(find.byKey(const ValueKey('nav-pacts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.getTopLeft(find.text('Early Birds')).dx,
      lessThan(initialHomeX),
    );

    await tester.pumpUi();
    expect(find.text('Pacts'), findsWidgets);
  });

  testWidgets('keeps navigation icons aligned when switching tabs', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    final homeButton = find.byKey(const ValueKey('nav-home'));
    final crewsButton = find.byKey(const ValueKey('nav-crews'));
    final homeIcon = find.descendant(
      of: homeButton,
      matching: find.byType(HugeIcon),
    );
    final crewsIcon = find.descendant(
      of: crewsButton,
      matching: find.byType(HugeIcon),
    );
    final initialCrewsY = tester.getCenter(crewsIcon).dy;

    expect(tester.getCenter(homeIcon).dy, equals(initialCrewsY));

    final highlight = find.byKey(const ValueKey('nav-sliding-highlight'));
    final startX = tester.getCenter(highlight).dx;
    final endX = tester.getCenter(crewsButton).dx;
    await tester.tap(crewsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getCenter(highlight).dx, greaterThan(startX));
    expect(tester.getCenter(highlight).dx, lessThan(endX));
    await tester.pumpUi();
    expect(tester.getCenter(highlight).dx, closeTo(endX, 1));

    expect(tester.getCenter(crewsIcon).dy, equals(initialCrewsY));
    expect(
      tester.getCenter(homeIcon).dy,
      equals(tester.getCenter(crewsIcon).dy),
    );
    expect(find.text('Crews'), findsWidgets);
  });

  testWidgets('uses a rounded rectangle navigation container', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    final navigation = find.byType(AppBottomNavigationBar);
    final container = tester
        .widgetList<Container>(
          find.descendant(of: navigation, matching: find.byType(Container)),
        )
        .first;
    expect(
      (container.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(16),
    );
    expect(tester.getSize(navigation).height, lessThan(110));
  });

  testWidgets('applies the flat background at the app root', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );

    expect(find.byType(WeekPactBackground), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
      WeekPactColors.darkCanvas,
    );
  });

  testWidgets('uses dark theme regardless of device appearance', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(find.byIcon(Icons.light_mode), findsNothing);
    expect(find.byIcon(Icons.dark_mode), findsNothing);
  });

  testWidgets('creates a crew and opens link-only invitations', (tester) async {
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();

    await tester.enterText(find.byType(TextFormField), 'Weekend Warriors');
    await tester.tap(find.text('CREATE CREW'));
    await tester.pumpUi();

    if (find.text('Finish later').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Finish later'));
      await tester.tap(find.text('Finish later'));
      await tester.pumpUi();
      await tester.tap(find.byKey(const ValueKey('nav-crews')));
      await tester.pumpUi();
    }
    expect(find.text('You · Owner'), findsOneWidget);
    expect(find.text('Pending invites'), findsNothing);
    expect(find.text('INVITE SOMEONE'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.ensureVisible(find.text('INVITE SOMEONE'));
    await tester.tap(find.text('INVITE SOMEONE'));
    await tester.pumpUi();
    expect(find.text('INVITE TO YOUR CREW'), findsOneWidget);

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('SEND INVITE'), findsNothing);
    expect(find.text('Share invite link'), findsOneWidget);
    expect(find.text('Copy invite link'), findsOneWidget);
    expect(find.text('Show QR code'), findsOneWidget);
    expect(crews.invitedEmails, isEmpty);
  });

  testWidgets('keeps an invite through login and accepts it', (tester) async {
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend();
    final links = FakeInviteLinkSource(
      Uri.parse('weekpact://invite?invite=secret-token'),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
        inviteLinkSource: links,
      ),
    );
    await tester.pumpUi();

    expect(find.textContaining('Crew invite ready'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'member@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('LOG IN'));
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.text('Your crew is waiting.'), findsOneWidget);
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(crews.acceptedTokens, ['secret-token']);
    expect(find.text('Your crew is waiting.'), findsNothing);
    expect(find.text('Early Birds'), findsWidgets);
  });
}

class FakeAuthBackend implements AuthBackend {
  @override
  Future<void> requestPasswordReset(String email) async {}
  @override
  Future<void> resendConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async {}
  @override
  Future<void> updatePassword(String password) async {}
  @override
  Future<void> deleteAccount(String password) => signOut();
  FakeAuthBackend({this.signUpResult = SignUpResult.signedIn});

  final _controller = StreamController<AuthUser?>.broadcast();
  final SignUpResult signUpResult;
  AuthUser? _user;
  int signInCalls = 0;
  int signUpCalls = 0;
  String? lastEmailRedirectTo;

  void confirmEmail(String email) {
    _user = AuthUser(email: email, onboardingCompleted: true);
    _controller.add(_user);
  }

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    _user = AuthUser(email: email, onboardingCompleted: true);
    _controller.add(_user);
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  }) async {
    signUpCalls++;
    lastEmailRedirectTo = emailRedirectTo;
    if (signUpResult == SignUpResult.signedIn) {
      _user = AuthUser(email: email, onboardingCompleted: true);
      _controller.add(_user);
    }
    return signUpResult;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) async {
    _user = AuthUser(
      email: _user!.email,
      firstName: firstName,
      lastName: lastName,
      avatarPath: 'avatar.png',
      onboardingCompleted: true,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<Uint8List?> loadAvatar() async => null;

  Future<void> dispose() => _controller.close();
}

class FakeCrewBackend implements CrewBackend, CrewSharingBackend {
  @override
  Future<CrewShareLink?> manageShareLink(String crewId, String action) async =>
      CrewShareLink(
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        token: 'a' * 64,
      );

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) async {
    crew = null;
  }

  @override
  Future<void> removeMember({
    required String crewId,
    required String userId,
  }) async {}

  @override
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites() async => [];
  @override
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) async {}

  CrewDetails? crew;
  final invitedEmails = <String>[];
  final acceptedTokens = <String>[];

  CrewDetails _details({List<CrewInvite> invites = const []}) => CrewDetails(
    id: '11111111-1111-4111-8111-111111111111',
    name: crew?.name ?? 'Weekend Warriors',
    timezone: 'UTC',
    ownerId: 'owner-id',
    currentUserRole: 'owner',
    members: [
      CrewMember(
        userId: 'owner-id',
        email: 'owner@example.com',
        role: 'owner',
        joinedAt: DateTime(2026),
      ),
    ],
    pendingInvites: invites,
  );

  @override
  Future<List<PactCrew>> fetchCrews() async => crew == null
      ? []
      : [
          PactCrew(
            id: crew!.id,
            name: crew!.name,
            timezone: crew!.timezone,
            isOwner: crew!.isOwner,
          ),
        ];

  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) async => crew;

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    crew = CrewDetails(
      id: '11111111-1111-4111-8111-111111111111',
      name: name,
      timezone: timezone,
      ownerId: 'owner-id',
      currentUserRole: 'owner',
      members: _details().members,
      pendingInvites: const [],
    );
    return crew!;
  }

  @override
  Future<CrewDetails> inviteMember({
    required String crewId,
    required String email,
  }) async {
    invitedEmails.add(email);
    crew = CrewDetails(
      id: crew!.id,
      name: crew!.name,
      timezone: crew!.timezone,
      ownerId: crew!.ownerId,
      currentUserRole: crew!.currentUserRole,
      members: crew!.members,
      pendingInvites: [
        CrewInvite(
          id: 'invite-id',
          email: email,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
        ),
      ],
    );
    return crew!;
  }

  @override
  Future<CrewDetails> revokeInvite({
    required String crewId,
    required String inviteId,
  }) async {
    crew = _details();
    return crew!;
  }

  @override
  Future<CrewDetails> acceptInvite(String token) async {
    acceptedTokens.add(token);
    crew = _details();
    return crew!;
  }
}

class FakeInviteLinkSource implements InviteLinkSource {
  const FakeInviteLinkSource(this.initialLink);
  final Uri initialLink;

  @override
  Future<Uri?> getInitialLink() async => initialLink;

  @override
  Stream<Uri> get links => const Stream.empty();
}

class DelayedCrewBackend extends FakeCrewBackend {
  Completer<CrewDetails?> pending = Completer<CrewDetails?>();
  int fetches = 0;

  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) {
    fetches++;
    return pending.future;
  }
}

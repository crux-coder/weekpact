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
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/brutal_widgets.dart';

void main() {
  testWidgets('account switches between light, dark and device appearance', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    final saved = <ThemeMode>[];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
        onThemeModeChanged: (mode) async {
          saved.add(mode);
        },
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpAndSettle();
    for (final entry in [
      ('Light', ThemeMode.light, Brightness.light),
      ('Dark', ThemeMode.dark, Brightness.dark),
      ('Device', ThemeMode.system, Brightness.dark),
    ]) {
      await tester.ensureVisible(find.text(entry.$1));
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('ACCOUNT.'))).brightness,
        entry.$3,
      );
      expect(saved.last, entry.$2);
    }
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('ACCOUNT.'))).brightness,
      Brightness.light,
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
      expect(find.text('CREWS.'), findsOneWidget);
      expect(find.text('MEMBERS'), findsOneWidget);
      expect(find.text('CREATE CREW'), findsNothing);
      expect(find.byTooltip('Refresh crew'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      crews.pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('CREATE CREW'), findsOneWidget);
      crews.pending = Completer<CrewDetails?>();
      await tester.dragFrom(const Offset(400, 80), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(crews.fetches, 2);
      expect(find.text('CREATE CREW'), findsOneWidget);
      crews.pending.completeError(Exception('Network unavailable'));
      await tester.pumpAndSettle();
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
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('CONFIRM PASSWORD'), findsNothing);

    final modeButton = find.byType(TextButton).last;
    await tester.ensureVisible(modeButton);
    await tester.tap(modeButton);
    await tester.pumpAndSettle();

    expect(find.text('Make it official.'), findsOneWidget);
    expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
  });

  testWidgets('validates login fields before calling Supabase', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
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
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    final modeButton = find.byType(TextButton).last;
    await tester.ensureVisible(modeButton);
    await tester.tap(modeButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    final submitButton = find.text('CREATE ACCOUNT');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(auth.signUpCalls, 1);
    expect(auth.lastEmailRedirectTo, 'weekpact://invite');
    expect(
      find.text('Check your email to confirm your account.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back.'), findsOneWidget);
    // Supabase emits the signed-in session after exchanging the email callback.
    auth.confirmEmail('new@example.com');
    await tester.pumpAndSettle();
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
        goalsBackend: DashboardGoals(),
        inviteLinkSource: FakeInviteLinkSource(
          Uri.parse('weekpact://invite?invite=crew-token'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mode = find.byType(TextButton).last;
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.ensureVisible(find.text('CREATE ACCOUNT'));
    await tester.tap(find.text('CREATE ACCOUNT'));
    await tester.pumpAndSettle();
    expect(auth.lastEmailRedirectTo, 'weekpact://invite?invite=crew-token');
    auth.confirmEmail('new@example.com');
    await tester.pumpAndSettle();
    expect(find.text('JOIN THE CREW.'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('signs in, shows account, and signs out', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    expect(find.text('EARLY BIRDS'), findsOneWidget);
    expect(find.text('1 OF 2 CHECKED IN TODAY'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('LOG OUT'));
    await tester.tap(find.text('LOG OUT'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('switches between signed-in destinations', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    expect(find.text('EARLY BIRDS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-goals')));
    await tester.pumpAndSettle();

    expect(find.text('GOALS.'), findsOneWidget);
    expect(find.text('WEEKLY GOALS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpAndSettle();

    expect(find.text('CREWS.'), findsOneWidget);
    expect(find.text('START YOUR CREW'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpAndSettle();

    expect(find.text('ACCOUNT.'), findsOneWidget);
    expect(find.text('LOG OUT'), findsOneWidget);
  });

  testWidgets('places navigation icons above their labels', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    final homeButton = find.byKey(const ValueKey('nav-home'));
    final homeIcon = find.descendant(
      of: homeButton,
      matching: find.byType(HugeIcon),
    );
    final homeLabel = find.descendant(
      of: homeButton,
      matching: find.text('HOME'),
    );

    expect(
      tester.getCenter(homeIcon).dy,
      lessThan(tester.getCenter(homeLabel).dy),
    );
  });

  testWidgets('shows daily goals and checks in directly', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR GOALS'), findsOneWidget);
    expect(find.text('Move for 30 min'), findsOneWidget);
    expect(find.text('1 OF 2 DONE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('check-in-Move for 30 min')));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 2 DONE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('check-in-Move for 30 min')));
    await tester.pumpAndSettle();
    expect(find.text('1 OF 2 DONE'), findsOneWidget);
  });

  testWidgets('slides horizontally between destinations', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    final initialHomeX = tester.getTopLeft(find.text('EARLY BIRDS')).dx;
    await tester.tap(find.byKey(const ValueKey('nav-goals')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.getTopLeft(find.text('EARLY BIRDS')).dx,
      lessThan(initialHomeX),
    );

    await tester.pumpAndSettle();
    expect(find.text('GOALS.'), findsOneWidget);
  });

  testWidgets('keeps the current navigation key pressed', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

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

    expect(tester.getCenter(homeIcon).dy, greaterThan(initialCrewsY));

    await tester.tap(crewsButton);
    await tester.pumpAndSettle();

    expect(tester.getCenter(crewsIcon).dy, greaterThan(initialCrewsY));
    expect(
      tester.getCenter(homeIcon).dy,
      lessThan(tester.getCenter(crewsIcon).dy),
    );
    expect(find.text('CREWS.'), findsOneWidget);
  });

  testWidgets('rounds the outside navigation key corners', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    final firstKey = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('nav-key-home')),
    );
    final lastKey = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('nav-key-account')),
    );
    final firstRadius = (firstKey.decoration! as BoxDecoration).borderRadius;
    final lastRadius = (lastKey.decoration! as BoxDecoration).borderRadius;

    expect(
      firstRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(9),
        bottomLeft: Radius.circular(9),
      ),
    );
    expect(
      lastRadius,
      const BorderRadius.only(
        topRight: Radius.circular(9),
        bottomRight: Radius.circular(9),
      ),
    );
  });

  testWidgets('applies the grid background at the app root', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
        authBackend: auth,
      ),
    );

    expect(find.byType(WeekPactBackground), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
      Colors.transparent,
    );
  });

  testWidgets('follows the device dark mode without a manual toggle', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
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

  testWidgets('creates a crew and sends an email invite', (tester) async {
    final auth = FakeAuthBackend();
    final crews = FakeCrewBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(),
        goalsBackend: DashboardGoals(),
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Weekend Warriors');
    await tester.tap(find.text('CREATE CREW'));
    await tester.pumpAndSettle();

    expect(find.text('OWNER'), findsNWidgets(2));
    expect(find.text('INVITE SOMEONE'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.ensureVisible(find.text('INVITE SOMEONE'));
    await tester.tap(find.text('INVITE SOMEONE'));
    await tester.pumpAndSettle();
    expect(find.text('INVITE TO YOUR CREW'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'friend@example.com');
    await tester.tap(find.text('SEND INVITE'));
    await tester.pumpAndSettle();

    expect(crews.invitedEmails, ['friend@example.com']);
    expect(find.text('PENDING INVITES'), findsOneWidget);
    final crewCard = find.ancestor(
      of: find.text('YOUR CREW'),
      matching: find.byType(BrutalTabbedCard),
    );
    expect(
      find.descendant(of: crewCard, matching: find.text('PENDING INVITES')),
      findsOneWidget,
    );
    expect(find.text('friend@example.com'), findsWidgets);
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
        goalsBackend: DashboardGoals(),
        authBackend: auth,
        crewBackend: crews,
        inviteLinkSource: links,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('CREW INVITE READY'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'member@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('LOG IN'));
    await tester.tap(find.text('LOG IN'));
    await tester.pumpAndSettle();

    expect(find.text('JOIN THE CREW.'), findsOneWidget);
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpAndSettle();

    expect(crews.acceptedTokens, ['secret-token']);
    expect(find.text('JOIN THE CREW.'), findsNothing);
    expect(find.text('EARLY BIRDS'), findsWidgets);
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

class FakeCrewBackend implements CrewBackend {
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
  Future<CrewDetails?> fetchCrew() async => crew;

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
  Future<CrewDetails?> fetchCrew() {
    fetches++;
    return pending.future;
  }
}

import 'dart:math' as math;

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
import 'package:weekpact/src/onboarding/profile_avatar.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

/// Through the front door to the email log-in form, the way an account made
/// before Apple and Google sign-in gets back in.
Future<void> openLogin(WidgetTester tester) async {
  await tester.pumpUi();
  if (find.byKey(const ValueKey('email-log-in')).evaluate().isEmpty) {
    final logIn = find.byKey(const ValueKey('welcome-log-in'));
    await tester.ensureVisible(logIn);
    await tester.tap(logIn);
    await tester.pumpUi();
  }
  await tester.tap(find.byKey(const ValueKey('email-log-in')));
  await tester.pumpUi();
}

void main() {
  testWidgets('account has no appearance setting and one fixed theme', (
    tester,
  ) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
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
      Theme.of(tester.element(find.byKey(const ValueKey('nav-account'))))
          .brightness,
      Brightness.dark,
    );
  });

  testWidgets(
    'crew shows skeletons and preserves content during pull to refresh',
    (tester) async {
      final crews = DelayedCrewBackend()
        ..crew = CrewDetails(
          id: 'crew',
          name: 'Weekend Warriors',
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
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.light,
          home: CrewPage(
            crewId: 'crew',
            backend: crews,
            currentUserEmail: 'owner@example.com',
          ),
        ),
      );
      expect(find.byType(SkeletonBar), findsWidgets);
      expect(find.text('INVITE SOMEONE'), findsNothing);
      expect(find.byTooltip('Refresh crew'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      crews.pending.complete(crews.crew);
      await tester.pumpUi();
      expect(find.text('INVITE SOMEONE'), findsOneWidget);
      crews.pending = Completer<CrewDetails?>();
      await tester.dragFrom(const Offset(400, 80), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(crews.fetches, 2);
      expect(find.text('INVITE SOMEONE'), findsOneWidget);
      crews.pending.completeError(Exception('Network unavailable'));
      await tester.pumpUi();
      expect(find.text('INVITE SOMEONE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('validates login fields before calling Supabase', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.tap(find.text('LOG IN'));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('signs in, shows account, and signs out', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('home-streak-card')), findsOneWidget);

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
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('home-streak-card')), findsOneWidget);

    // Pacts are kept on each crew's own page, so there is no tab for them.
    expect(find.byKey(const ValueKey('nav-pacts')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();

    expect(find.text('Start your crew'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-account')));
    await tester.pumpUi();

    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('shows icons only, named for screen readers', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    final navigation = find.byType(AppBottomNavigationBar);
    for (final label in ['Home', 'Chat', 'Crews', 'Account']) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsNothing,
      );
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    // Account shows the person's own picture in place of an icon.
    final account = find.byKey(const ValueKey('nav-account'));
    expect(
      find.descendant(of: account, matching: find.byType(ProfileAvatar)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: account, matching: find.byType(HugeIcon)),
      findsNothing,
    );
  });

  testWidgets('shows daily pacts and checks in directly', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        captureCheckInPhoto: captureTestCheckInPhoto,
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('pacts-heading')), findsNothing);
    expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
    expect(find.text('Check in').hitTestable(), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
    );
    await tester.pumpUi();
    await submitTestPhoto(tester);
    expect(find.text('Checked in today'), findsWidgets);
    final hold = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1200));
    await hold.up();
    await tester.pumpUi();
    expect(find.text('Check in').hitTestable(), findsOneWidget);
  });

  testWidgets('cuts straight to the destination', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();

    final home = find.byKey(const ValueKey('home-streak-card'));
    expect(home.hitTestable(), findsOneWidget);
    // No slide: one frame later Home is already gone.
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pump();
    expect(home.hitTestable(), findsNothing);
    await tester.pumpUi();
    expect(find.text('Start your crew').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps navigation icons aligned when switching tabs', (
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
    await openLogin(tester);
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
    // The highlight lands on Crews.
    expect(
      tester.getCenter(highlight).dx,
      closeTo(tester.getCenter(crewsButton).dx, 1),
    );
    expect(
      tester.getSize(highlight).width,
      closeTo(tester.getSize(crewsButton).width, 1),
    );

    expect(tester.getCenter(crewsIcon).dy, equals(initialCrewsY));
    expect(
      tester.getCenter(homeIcon).dy,
      equals(tester.getCenter(crewsIcon).dy),
    );
  });

  testWidgets('floats a wide, rounded navigation bar over the page', (
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
    await openLogin(tester);
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
    // A squircle, like the cards, not a plain rounded rect.
    expect(
      (container.decoration! as ShapeDecoration).shape,
      isA<ContinuousRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(40),
      ),
    );
    expect(tester.getSize(navigation).height, lessThan(90));
    // As wide as the page, inset from its edges, floating over the content.
    final pill = find
        .descendant(of: navigation, matching: find.byType(Container))
        .first;
    expect(
      tester.getSize(pill).width,
      closeTo(math.min(tester.getSize(navigation).width - 44, 640), 1),
    );
    expect(
      tester
          .widget<Scaffold>(
            find
                .ancestor(of: navigation, matching: find.byType(Scaffold))
                .first,
          )
          .extendBody,
      isTrue,
    );
  });

  testWidgets('applies the flat background at the app root', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
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

  testWidgets('uses one theme regardless of device appearance', (tester) async {
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      WeekPactApp(
        homeBackend: DashboardBackend(viewerId: 'user-id'),
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
        homeBackend: DashboardBackend(viewerId: 'user-id'),
        pactsBackend: DashboardPacts(),
        authBackend: auth,
        crewBackend: crews,
      ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('LOG IN'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Weekend Warriors',
    );
    await tester.ensureVisible(find.text('CREATE CREW'));
    await tester.tap(find.text('CREATE CREW'));
    await tester.pumpUi();

    if (find.text('Finish later').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Finish later'));
      await tester.tap(find.text('Finish later'));
      await tester.pumpUi();
      await tester.tap(find.byKey(const ValueKey('nav-crews')));
      await tester.pumpUi();
    }
    await tester.tap(find.text('Weekend Warriors'));
    await tester.pumpUi();
    // Your own band names the tint: colour alone said 'you' while the label
    // said 'owner', and on a crew you started those land on the same row.
    expect(find.text('YOU · OWNER'), findsOneWidget);
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
    expect(find.text('7'), findsOneWidget);
  });

  for (final withLink in [false, true]) {
    testWidgets(
      withLink
          ? 'a broken auth stream with a pending link asks for a log in'
          : 'a broken auth stream without a link asks for a plain log in',
      (tester) async {
        final auth = FakeAuthBackend();
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          WeekPactApp(
            homeBackend: DashboardBackend(viewerId: 'user-id'),
            pactsBackend: DashboardPacts(),
            authBackend: auth,
            inviteLinkSource: withLink
                ? FakeInviteLinkSource(
                    Uri.parse('weekpact://invite?code=7K2QXM'),
                  )
                : const NoopInviteLinkSource(),
          ),
        );
        await tester.pumpUi();
        auth.failStream();
        await tester.pumpUi();

        // Only a failed email link is blamed on the link; anything else on
        // the stream asks for a plain log in, invite or not.
        expect(
          find.textContaining('This link could not be opened'),
          findsNothing,
        );
        expect(
          find.text('Could not confirm your sign-in. Please log in again.'),
          findsOneWidget,
        );
      },
    );
  }
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

  /// What the last deletion was confirmed with: the password, or null for an
  /// Apple or Google account.
  String? deletedWithPassword;
  int deletions = 0;

  @override
  Future<void> deleteAccount({String? password}) {
    deletions++;
    deletedWithPassword = password;
    return signOut();
  }

  FakeAuthBackend({
    this.onboardingStep = OnboardingStep.done,
    this.firstName = 'Mia',
    this.providerName = 'Mia',
    this.cancelSignIn = false,
  });

  final _controller = StreamController<AuthUser?>.broadcast();

  /// Where the account this backend hands back is in onboarding.
  final OnboardingStep onboardingStep;

  /// The name an email log-in comes back with.
  final String firstName;

  /// The name Apple or Google hands over. Empty is Apple's "hide my name".
  final String providerName;

  /// The person closes the provider's sheet.
  final bool cancelSignIn;

  /// Every step [advanceOnboarding] was asked to record, in order.
  final advancedSteps = <OnboardingStep>[];
  final providerSignIns = <SignInProvider>[];
  AuthUser? _user;
  int signInCalls = 0;

  /// A dropped session or a refused callback, as the SDK reports one.
  void failStream() => _controller.addError(StateError('auth stream failed'));

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _user;

  @override
  List<SignInProvider> get signInProviders => const [
    SignInProvider.apple,
    SignInProvider.google,
  ];

  @override
  Future<bool> signInWith(SignInProvider provider) async {
    providerSignIns.add(provider);
    if (cancelSignIn) return false;
    _user = AuthUser(
      id: 'user-id',
      email: '${provider.name}@example.com',
      firstName: providerName,
      onboardingStep: providerName.isEmpty
          ? OnboardingStep.profile
          : onboardingStep,
      hasPassword: false,
    );
    _controller.add(_user);
    return true;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    _user = AuthUser(
      id: 'user-id',
      email: email,
      firstName: firstName,
      onboardingStep: onboardingStep,
    );
    _controller.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  Uint8List? savedAvatar;

  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) async {
    if (avatar != null) savedAvatar = avatar;
    _user = AuthUser(
      id: _user!.id,
      email: _user!.email,
      firstName: firstName,
      lastName: lastName,
      avatarPath: 'avatar.png',
      onboardingStep: _user!.profileCompleted
          ? _user!.onboardingStep
          : OnboardingStep.crew,
      hasPassword: _user!.hasPassword,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> advanceOnboarding(OnboardingStep step) async {
    advancedSteps.add(step);
    final user = _user!;
    _user = AuthUser(
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarPath: user.avatarPath,
      onboardingStep: step,
      hasPassword: user.hasPassword,
    );
  }

  @override
  Future<Uint8List?> loadAvatar() async => null;

  Future<void> dispose() => _controller.close();
}

class FakeCrewBackend implements CrewBackend, CrewSharingBackend {
  String code = '7K2QXM';
  int resets = 0;

  @override
  Future<String> inviteCode(String crewId) async => code;

  @override
  Future<String> resetInviteCode(String crewId) async {
    resets++;
    code = 'NEWC0D'.replaceAll('0', 'Q');
    return code;
  }

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) async {
    crew = null;
  }

  @override
  Future<void> removeMember({
    required String crewId,
    required String userId,
  }) async {}

  CrewDetails? crew;
  final acceptedTokens = <String>[];
  final createdCrews = <String>[];

  /// Thrown by [acceptInvite] when set.
  Object? acceptError;

  CrewDetails _details() => CrewDetails(
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

  /// The photo the last crew was created with.
  Uint8List? createdAvatar;

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
    String? description,
    Uint8List? avatar,
  }) async {
    createdCrews.add(name);
    createdAvatar = avatar;
    crew = CrewDetails(
      id: '11111111-1111-4111-8111-111111111111',
      name: name,
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      timezone: timezone,
      ownerId: 'owner-id',
      currentUserRole: 'owner',
      members: _details().members,
    );
    return crew!;
  }

  @override
  Future<CrewDetails> acceptInvite(String code) async {
    acceptedTokens.add(code);
    final error = acceptError;
    if (error != null) throw error;
    crew = _details();
    return crew!;
  }

  CrewInvitePreview? preview;
  final previewedFrom = <String?>[];

  @override
  Future<CrewInvitePreview?> previewInvite(String code, {String? from}) async {
    previewedFrom.add(from);
    return preview;
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

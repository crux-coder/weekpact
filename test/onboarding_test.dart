import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/onboarding/onboarding_page.dart';
import 'package:weekpact/src/onboarding/onboarding_gate.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'widget_test.dart' show FakeAuthBackend;

class ProfileBackend extends FakeAuthBackend {
  AuthUser profile = const AuthUser(id: 'user-id', email: 'new@example.com');
  bool fail = false;
  int saves = 0;
  @override
  AuthUser get currentUser => profile;
  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) async {
    saves++;
    if (fail) throw StateError('offline');
    savedAvatar = avatar;
    profile = AuthUser(
      id: profile.id,
      email: profile.email,
      firstName: firstName,
      lastName: lastName,
      avatarPath: '${profile.id}/avatar.png',
      onboardingCompleted: true,
    );
    return profile;
  }
}

Future<void> start(
  WidgetTester tester,
  ProfileBackend backend, {
  Future<Uint8List?> Function()? picker,
  ValueChanged<AuthUser>? completed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: OnboardingPage(
        backend: backend,
        user: backend.profile,
        onCompleted: completed ?? (_) {},
        pickAvatar: picker ?? () async => null,
      ),
    ),
  );
  await tester.ensureVisible(find.text('LET’S GET STARTED'));
  await tester.tap(find.text('LET’S GET STARTED'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('LET’S GO'));
  await tester.tap(find.text('LET’S GO'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('focused profile fields keep their outline shape', (
    tester,
  ) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    await start(tester, backend);
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(TextFormField).first))
        .inputDecorationTheme;
    expect(theme.focusedBorder, theme.enabledBorder);
  });

  testWidgets('Done dismisses keyboard when saving without a photo', (
    tester,
  ) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    await start(tester, backend);
    await tester.enterText(find.byType(TextFormField).first, 'Ada');
    await tester.enterText(find.byType(TextFormField).last, 'Lovelace');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });
  testWidgets('display name is required but photo and surname are optional', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    await start(tester, backend);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Display name'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Last name (optional)'),
      findsOneWidget,
    );
    await save(tester);
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Choose an avatar photo to continue.'), findsNothing);
    expect(backend.saves, 0);
    await tester.enterText(find.byType(TextFormField).first, 'Ada');
    await save(tester);
    expect(backend.saves, 1);
    expect(backend.savedAvatar, isNull);
    expect(backend.profile.lastName, isEmpty);
  });
  testWidgets(
    'canceling photo selection keeps profile fields and does not complete',
    (tester) async {
      final backend = ProfileBackend();
      addTearDown(backend.dispose);
      await start(tester, backend);
      await tester.enterText(find.byType(TextFormField).first, 'Ada');
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsOneWidget);
      expect(backend.saves, 0);
    },
  );
  testWidgets(
    'save failure keeps input and avatar for retry; successful save completes',
    (tester) async {
      final backend = ProfileBackend()..fail = true;
      addTearDown(backend.dispose);
      final photo = File('assets/branding/weekpact-icon.png').readAsBytesSync();
      AuthUser? result;
      await start(
        tester,
        backend,
        picker: () async => photo,
        completed: (user) => result = user,
      );
      await tester.enterText(find.byType(TextFormField).first, ' Ada ');
      await tester.enterText(find.byType(TextFormField).last, ' Lovelace ');
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(result, isNull);
      expect(find.textContaining('couldn’t save your profile'), findsOneWidget);
      backend.fail = false;
      await tester.showKeyboard(find.byType(TextFormField).last);
      tester.testTextInput.log.clear();
      await save(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
        isTrue,
      );
      expect(result!.firstName, 'Ada');
      expect(result!.lastName, 'Lovelace');
      expect(result!.onboardingCompleted, isTrue);
      expect(backend.savedAvatar, photo);
    },
  );
  testWidgets('profile updates wait for save completion before opening Home', (
    tester,
  ) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    var completed = false;
    Widget gate(AuthUser user) => MaterialApp(
      theme: WeekPactTheme.light,
      home: OnboardingGate(
        user: user,
        backend: backend,
        onCompleted: () => completed = true,
        builder: (profile) => Text('HOME ${profile.firstName}'),
      ),
    );
    await tester.pumpWidget(gate(backend.profile));
    const saved = AuthUser(
      id: 'user-id',
      email: 'new@example.com',
      firstName: 'Ada',
      lastName: 'Lovelace',
      avatarPath: 'user-id/avatar.png',
      onboardingCompleted: true,
    );
    await tester.pumpWidget(gate(saved));
    expect(find.byType(OnboardingPage), findsOneWidget);
    tester
        .widget<OnboardingPage>(find.byType(OnboardingPage))
        .onCompleted(saved);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(find.text('HOME Ada'), findsOneWidget);
  });
  testWidgets('completed accounts skip onboarding and new accounts see intro', (
    tester,
  ) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    Widget gate(AuthUser user) => MaterialApp(
      theme: WeekPactTheme.light,
      home: OnboardingGate(
        key: ValueKey(user.id),
        user: user,
        backend: backend,
        onCompleted: () {},
        builder: (_) => const Text('HOME'),
      ),
    );
    await tester.pumpWidget(gate(backend.profile));
    await tester.pumpAndSettle();
    expect(find.text('Good habits.\nGreat company.'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    await tester.pumpWidget(
      gate(
        const AuthUser(
          id: 'returning',
          email: 'returning@example.com',
          onboardingCompleted: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('LET’S GET STARTED'), findsNothing);
  });
}

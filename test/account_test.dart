import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, FunctionException;
import 'package:weekpact/src/auth/account_actions.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/auth/auth_gate.dart';
import 'package:weekpact/src/auth/password_page.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

class AccountBackend extends FakeAuthBackend {
  final changes = StreamController<AuthUser?>.broadcast();
  AuthUser? user;
  String? resetEmail;
  String? resentEmail;
  String? redirect;
  String? updatedPassword;
  String? deletedPassword;
  bool fail = false;
  bool signedOut = false;
  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthUser?> get authStateChanges => changes.stream;
  void recover() {
    user = const AuthUser(
      email: 'user@example.com',
      passwordRecoveryRequired: true,
    );
    changes.add(user);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    if (fail) throw StateError('offline');
    resetEmail = email;
  }

  @override
  Future<void> resendConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async {
    resentEmail = email;
    redirect = emailRedirectTo;
  }

  @override
  Future<void> updatePassword(String password) async {
    if (fail) throw const AuthException('Password could not be updated');
    updatedPassword = password;
  }

  @override
  Future<void> deleteAccount(String password) async {
    if (fail) throw const FunctionException(status: 403);
    deletedPassword = password;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    user = null;
    changes.add(null);
  }

  @override
  Future<void> dispose() async {
    await changes.close();
    await super.dispose();
  }
}

Widget frame(Widget child) =>
    MaterialApp(theme: WeekPactTheme.light, home: child);

void main() {
  testWidgets(
    'recovery validates email, shows neutral confirmation and throttles repeat sends',
    (tester) async {
      final backend = AccountBackend();
      addTearDown(backend.dispose);
      await tester.pumpWidget(frame(PasswordPage(backend: backend)));
      await tester.tap(find.text('SEND RESET LINK'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(backend.resetEmail, isNull);
      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('SEND RESET LINK'));
      await tester.pumpAndSettle();
      expect(backend.resetEmail, 'user@example.com');
      expect(find.textContaining('If an account exists'), findsOneWidget);
      await tester.tap(find.text('Resend confirmation email'));
      await tester.pump();
      expect(backend.resentEmail, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('confirmation resend preserves invitation callback', (
    tester,
  ) async {
    final backend = AccountBackend();
    addTearDown(backend.dispose);
    await tester.pumpWidget(
      frame(
        PasswordPage(
          backend: backend,
          initialEmail: 'user@example.com',
          confirmationRedirect: 'weekpact://invite?invite=example',
        ),
      ),
    );
    await tester.tap(find.text('Resend confirmation email'));
    await tester.pumpAndSettle();
    expect(backend.resentEmail, 'user@example.com');
    expect(backend.redirect, 'weekpact://invite?invite=example');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'password mismatch and save failure stay recoverable; success requires fresh login',
    (tester) async {
      final backend = AccountBackend();
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        frame(PasswordPage(backend: backend, recovery: true)),
      );
      await tester.enterText(find.byType(TextFormField).first, 'new-password');
      await tester.enterText(find.byType(TextFormField).last, 'different');
      await tester.tap(find.text('SAVE PASSWORD'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(backend.updatedPassword, isNull);
      await tester.enterText(find.byType(TextFormField).last, 'new-password');
      backend.fail = true;
      await tester.tap(find.text('SAVE PASSWORD'));
      await tester.pumpAndSettle();
      expect(find.text('Password could not be updated'), findsOneWidget);
      backend.fail = false;
      await tester.tap(find.text('SAVE PASSWORD'));
      await tester.pumpAndSettle();
      expect(backend.updatedPassword, 'new-password');
      await tester.tap(find.text('BACK TO LOGIN'));
      await tester.pumpAndSettle();
      expect(backend.signedOut, isTrue);
    },
  );
  testWidgets(
    'recovery email link replaces a pushed request screen before onboarding',
    (tester) async {
      final backend = AccountBackend();
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        frame(
          AuthGate(
            authBackend: backend,
            crewBackend: FakeCrewBackend(),
            inviteLinkSource: const NoopInviteLinkSource(),
          ),
        ),
      );
      await tester.ensureVisible(
        find.text('Forgot password or need a confirmation email?'),
      );
      await tester.tap(
        find.text('Forgot password or need a confirmation email?'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account recovery'), findsOneWidget);
      backend.recover();
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.text('Account recovery'), findsNothing);
      expect(find.text('LET’S GET STARTED'), findsNothing);
    },
  );
  testWidgets(
    'invalid callback dismisses recovery request and explains how to retry',
    (tester) async {
      final backend = AccountBackend();
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        frame(
          AuthGate(
            authBackend: backend,
            crewBackend: FakeCrewBackend(),
            inviteLinkSource: const NoopInviteLinkSource(),
          ),
        ),
      );
      await tester.ensureVisible(
        find.text('Forgot password or need a confirmation email?'),
      );
      await tester.tap(
        find.text('Forgot password or need a confirmation email?'),
      );
      await tester.pumpAndSettle();
      backend.changes.addError(const AuthException('Expired link'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('It may be expired or already used'),
        findsOneWidget,
      );
      expect(find.text('Account recovery'), findsNothing);
    },
  );
  testWidgets(
    'deletion can be cancelled and requires password plus explicit confirmation',
    (tester) async {
      final backend = AccountBackend();
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        frame(
          Scaffold(
            body: AccountActions(backend: backend, showPasswordReset: false),
          ),
        ),
      );
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permanently delete'));
      await tester.pump();
      expect(backend.deletedPassword, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.deletedPassword, isNull);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'current-password');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Permanently delete'));
      await tester.pumpAndSettle();
      expect(backend.deletedPassword, 'current-password');
    },
  );
  testWidgets(
    'incorrect deletion password shows actionable error and permits retry',
    (tester) async {
      final backend = AccountBackend()..fail = true;
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        frame(Scaffold(body: AccountActions(backend: backend))),
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Permanently delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Incorrect password'), findsOneWidget);
      expect(backend.deletedPassword, isNull);
      expect(find.text('Delete account'), findsOneWidget);
    },
  );
}

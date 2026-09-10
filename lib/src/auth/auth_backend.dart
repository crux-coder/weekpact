import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  const AuthUser({
    required this.email,
    this.id = '',
    this.firstName = '',
    this.lastName = '',
    this.avatarPath,
    this.onboardingCompleted = false,
    this.passwordRecoveryRequired = false,
  });

  final String firstName;
  final String lastName;
  final String? avatarPath;
  final bool onboardingCompleted;
  final bool passwordRecoveryRequired;

  final String id;

  final String email;
}

enum SignUpResult { signedIn, emailConfirmationRequired }

abstract interface class AuthBackend {
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;

  Future<void> signIn({required String email, required String password});
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  });
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  });
  Future<Uint8List?> loadAvatar();
  Future<void> signOut();
  Future<void> requestPasswordReset(String email);
  Future<void> resendConfirmation(String email, {String? emailRedirectTo});
  Future<void> updatePassword(String password);
  Future<void> deleteAccount(String password);
}

class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client) {
    // Subscribe before other startup work so cold-start recovery links are retained.
    _client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (state.event == AuthChangeEvent.signedOut) _recovering = false;
      },
      onError: (Object _) {
        /* AuthGate displays callback errors. */
      },
    );
  }
  bool _recovering = false;
  Future<void> Function()? beforeSignOut;
  void Function()? afterSignOutAttempt;

  final SupabaseClient _client;

  @override
  AuthUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((event) {
        if (event.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (event.event == AuthChangeEvent.signedOut) _recovering = false;
        return _mapUser(event.session?.user);
      });

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
    );
    return response.session == null
        ? SignUpResult.emailConfirmationRequired
        : SignUpResult.signedIn;
  }

  @override
  Future<void> signOut() async {
    await beforeSignOut?.call();
    try {
      await _client.auth.signOut();
    } finally {
      afterSignOutAttempt?.call();
    }
  }

  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before setting up your profile.');
    }
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty || first.length > 60 || last.length > 60) {
      throw ArgumentError('Enter a display name (up to 60 characters).');
    }
    if (avatar != null && (avatar.isEmpty || avatar.length > 5 * 1024 * 1024)) {
      throw ArgumentError('Choose a photo smaller than 5 MB.');
    }
    final path = avatar == null
        ? currentUser?.avatarPath
        : '${user.id}/avatar.png';
    if (avatar != null) {
      await _client.storage
          .from('avatars')
          .uploadBinary(
            path!,
            avatar,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
    }
    final result = await _client.auth.updateUser(
      UserAttributes(
        data: {
          'first_name': first,
          'last_name': last,
          'avatar_path': path,
          'onboarding_completed': true,
        },
      ),
    );
    return _mapUser(result.user)!;
  }

  @override
  Future<void> requestPasswordReset(String email) => _client.auth
      .resetPasswordForEmail(email.trim(), redirectTo: 'weekpact://invite');

  @override
  Future<void> resendConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailRedirectTo ?? 'weekpact://invite',
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    if (password.length < 8) throw ArgumentError('Use at least 8 characters.');
    await _client.auth.updateUser(UserAttributes(password: password));
    // Keep the recovery screen active until the user signs out after success.
  }

  @override
  Future<void> deleteAccount(String password) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('Sign in before deleting your account.');
    }
    final deletingUserId = session.user.id;
    try {
      // Push cleanup is best effort here; server deletion removes every device.
      try {
        await beforeSignOut?.call();
      } catch (_) {}
      await _client.functions.invoke(
        'delete-account',
        body: {'password': password},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      // The server has deleted the account and its sessions. Clear this device.
      if (_client.auth.currentUser?.id == deletingUserId) {
        await _client.auth.signOut(scope: SignOutScope.local);
      }
    } finally {
      afterSignOutAttempt?.call();
    }
  }

  @override
  Future<Uint8List?> loadAvatar() async {
    final user = currentUser;
    if (user == null || user.avatarPath != '${user.id}/avatar.png') return null;
    return _client.storage.from('avatars').download(user.avatarPath!);
  }

  AuthUser? _mapUser(User? user) {
    if (user == null) return null;
    final data = user.userMetadata ?? {};
    final first = data['first_name'] is String
        ? (data['first_name'] as String).trim()
        : '';
    final last = data['last_name'] is String
        ? (data['last_name'] as String).trim()
        : '';
    final avatar = data['avatar_path'] is String
        ? data['avatar_path'] as String
        : null;
    return AuthUser(
      id: user.id,
      email: user.email ?? 'Signed-in user',
      firstName: first,
      lastName: last,
      avatarPath: avatar,
      onboardingCompleted:
          data['onboarding_completed'] == true && first.isNotEmpty,
      passwordRecoveryRequired: _recovering,
    );
  }
}

class MissingConfigurationAuthBackend implements AuthBackend {
  const MissingConfigurationAuthBackend();

  static const _message =
      'Supabase is not configured. Launch with SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY dart-defines.';

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) {
    throw StateError(_message);
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
  }) {
    throw StateError(_message);
  }

  @override
  Future<void> requestPasswordReset(String email) async =>
      throw StateError(_message);
  @override
  Future<void> resendConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async => throw StateError(_message);
  @override
  Future<void> updatePassword(String password) async =>
      throw StateError(_message);
  @override
  Future<void> deleteAccount(String password) async =>
      throw StateError(_message);

  @override
  Future<void> signOut() async {}

  @override
  Future<Uint8List?> loadAvatar() async => null;

  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) => throw StateError(_message);
}

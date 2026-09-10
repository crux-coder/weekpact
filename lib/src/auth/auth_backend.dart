import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  const AuthUser({required this.email, this.id = ''});

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
  Future<void> signOut();
}

class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client);

  final SupabaseClient _client;

  @override
  AuthUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _client.auth.onAuthStateChange.map(
    (event) => _mapUser(event.session?.user),
  );

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
  Future<void> signOut() => _client.auth.signOut();

  AuthUser? _mapUser(User? user) {
    if (user == null) return null;
    return AuthUser(id: user.id, email: user.email ?? 'Signed-in user');
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
  Future<void> signOut() async {}
}

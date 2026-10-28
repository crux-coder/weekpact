import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_cache.dart';
import '../home/photo_encoding.dart';
import '../notifications/notification_preferences.dart';

/// Where a person is in onboarding, as public.users.onboarding_step stores it.
/// `profile` is an account whose name is still missing (Apple can withhold
/// it), `crew` an account from the old flow that never answered the crew
/// question, and `done` everyone who has been through the setup.
enum OnboardingStep {
  profile,
  crew,
  done;

  static OnboardingStep parse(Object? value) =>
      values.firstWhere((step) => step.name == value, orElse: () => profile);
}

class AuthUser {
  const AuthUser({
    required this.email,
    this.id = '',
    this.firstName = '',
    this.lastName = '',
    this.avatarPath,
    this.onboardingStep = OnboardingStep.profile,
    this.passwordRecoveryRequired = false,
    this.profileLoaded = true,
    this.hasPassword = true,
  });

  /// Whether the account signs in with an email and password. Apple and
  /// Google accounts have no password to confirm a deletion with.
  final bool hasPassword;

  final String firstName;
  final String lastName;
  final String? avatarPath;
  final OnboardingStep onboardingStep;

  /// Whether the profile form is behind them, whatever comes next.
  bool get profileCompleted => onboardingStep != OnboardingStep.profile;
  final bool passwordRecoveryRequired;

  /// False while the profile row is still on its way. Until it arrives the
  /// name and onboarding fields are unknown, not empty.
  final bool profileLoaded;

  final String id;

  final String email;
}

/// Where every auth email comes back to. The build sets it, and both the
/// confirmation link and the recovery link read it from here: a recovery mail
/// pointing at a route the build does not answer opens nothing at all.
const inviteRedirectBase = String.fromEnvironment(
  'INVITE_REDIRECT_BASE',
  defaultValue: 'weekpact://invite',
);

/// The OAuth client Supabase verifies Google ID tokens against. Android asks
/// Google for a token on its behalf, so it has to be the web client.
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '705377133061-bu9bmehie9rnr19893854eoetlkr9p9o.apps.googleusercontent.com',
);

/// The iOS OAuth client. It must match GIDClientID and the reversed URL scheme
/// in ios/Runner/Info.plist.
const googleIosClientId = String.fromEnvironment(
  'GOOGLE_IOS_CLIENT_ID',
  defaultValue: '705377133061-ls6gpj0ssehgbvhbcgbif5gt5gd3qtqc.apps.googleusercontent.com',
);

/// The ways to make or open an account. Email and password is only for
/// accounts made before it was retired, so it is not one of these.
enum SignInProvider { apple, google }

abstract interface class AuthBackend {
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;

  /// The providers this device can offer, in the order they are shown. Apple
  /// is offered on iOS only.
  List<SignInProvider> get signInProviders;

  /// Signs in with [provider], making the account on first use. Returns false
  /// when the person closes the provider's sheet without choosing.
  Future<bool> signInWith(SignInProvider provider);

  Future<void> signIn({required String email, required String password});
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  });

  /// Records that the signed-in account has reached [step].
  Future<void> advanceOnboarding(OnboardingStep step);
  Future<Uint8List?> loadAvatar();
  Future<void> signOut();
  Future<void> requestPasswordReset(String email);
  Future<void> resendConfirmation(String email, {String? emailRedirectTo});
  Future<void> updatePassword(String password);

  /// Deletes the account. Email accounts confirm with their [password];
  /// Apple and Google accounts, which have none, confirm by typing DELETE.
  Future<void> deleteAccount({String? password});
}

class SupabaseAuthBackend
    implements AuthBackend, NotificationPreferencesBackend {
  SupabaseAuthBackend(this._client, {this._cache}) {
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

  /// Where the last profile row is kept, so a restored session opens on it.
  final HomeCache? _cache;

  /// The signed-in account's row in public.users, fetched once per account.
  /// Every auth event for the same account reuses it; only a different
  /// account, or a saved profile, replaces it.
  String? _profileUserId;
  Future<Map<String, dynamic>?>? _profileLoad;
  Map<String, dynamic>? _profile;
  bool _profileReady = false;

  Future<void> Function()? beforeSignOut;
  void Function()? afterSignOutAttempt;

  final SupabaseClient _client;

  @override
  AuthUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.asyncMap((event) async {
        if (event.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (event.event == AuthChangeEvent.signedOut) {
          _recovering = false;
          // The next sign-in, even by the same account, reads a fresh row.
          if (_profileUserId case final id?) _cache?.clearProfile(id);
          _profileUserId = null;
          _profileLoad = null;
          _profileReady = false;
          _profile = null;
        }
        final user = event.session?.user;
        if (user != null) await _loadProfile(user.id);
        return _mapUser(user);
      });

  /// Readies the restored session's profile before the first frame, so a
  /// returning account opens on Home rather than a loading screen. The row
  /// kept from the last launch is used at once and refreshed behind it; only
  /// a device with none waits on the network, and not for long. A failure
  /// here is left for the auth stream to retry and report.
  Future<void> restoreProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (_cache?.readProfile(user.id) case final kept?) {
      _profileUserId = user.id;
      _profile = kept;
      _profileReady = true;
      _loadProfile(user.id).ignore();
      return;
    }
    try {
      await _loadProfile(user.id).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadProfile(String userId) {
    if (_profileUserId == userId && _profileLoad != null) {
      return _profileLoad!;
    }
    // The same account's row stays up while a fresh one loads.
    final known = _profileUserId == userId && _profileReady;
    _profileUserId = userId;
    if (!known) {
      _profileReady = false;
      _profile = null;
    }
    final fetched = _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle()
        .then((row) {
          if (_profileUserId == userId) _keepProfile(userId, row);
          return row;
        });
    // With a row already showing, a failed refresh leaves it standing.
    final load = known ? fetched.catchError((Object _) => _profile) : fetched;
    _profileLoad = load;
    // A failed fetch is not remembered, so the next auth event asks again.
    fetched.catchError((Object _) {
      if (_profileLoad == load) _profileLoad = null;
      return null;
    });
    return load;
  }

  void _keepProfile(String userId, Map<String, dynamic>? row) {
    _profile = row;
    _profileReady = true;
    _cache?.writeProfile(userId, row);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  List<SignInProvider> get signInProviders => [
    if (!kIsWeb && Platform.isIOS) SignInProvider.apple,
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid))
      SignInProvider.google,
  ];

  @override
  Future<bool> signInWith(SignInProvider provider) => switch (provider) {
    SignInProvider.apple => _signInWithApple(),
    SignInProvider.google => _signInWithGoogle(),
  };

  Future<bool> _signInWithApple() async {
    // Apple signs a hash of the nonce into its token; Supabase is handed the
    // raw value and checks the two agree, so a token cannot be replayed.
    final rawNonce = _client.auth.generateRawNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple did not return a sign-in token. Try again.');
    }
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final user = response.user;
    if (user == null) return true;
    // Apple hands the name over on the very first sign-in only, and never
    // puts it in the token, so it is saved now or not at all.
    await _saveProviderName(
      user.id,
      first: credential.givenName,
      last: credential.familyName,
    );
    // The authorization code is what lets the server revoke Apple's token
    // when the account is deleted. It expires in minutes, so it goes now;
    // a failure only costs that revocation, not the sign-in.
    final code = credential.authorizationCode;
    unawaited(
      _client.functions
          .invoke('apple-token', body: {'authorizationCode': code})
          .then<void>((_) {}, onError: (Object _) {}),
    );
    return true;
  }

  bool _googleReady = false;

  Future<bool> _signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        clientId: !kIsWeb && Platform.isIOS ? googleIosClientId : null,
        serverClientId: googleWebClientId,
      );
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate(scopeHint: const ['email']);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return false;
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google did not return a sign-in token. Try again.');
    }
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    final user = response.user;
    if (user != null) {
      await _saveProviderName(
        user.id,
        first: _metadataString(user, const ['given_name']),
        last: _metadataString(user, const ['family_name']),
        full: _metadataString(user, const ['full_name', 'name']),
      );
      unawaited(_copyProviderPhoto(user).catchError((Object _) {}));
    }
    return true;
  }

  static String? _metadataString(User user, List<String> keys) {
    for (final key in keys) {
      final value = user.userMetadata?[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// Fills an empty profile name from what the provider said. A name the
  /// person has already set, here or in an earlier sign-in, is never replaced.
  Future<void> _saveProviderName(
    String userId, {
    String? first,
    String? last,
    String? full,
  }) async {
    var given = first?.trim() ?? '';
    var family = last?.trim() ?? '';
    if (given.isEmpty && full != null) {
      final parts = full.trim().split(RegExp(r'\s+'));
      given = parts.first;
      if (family.isEmpty && parts.length > 1) {
        family = parts.skip(1).join(' ');
      }
    }
    if (given.isEmpty) return;
    final profile = await _loadProfile(userId);
    final saved = profile?['first_name'];
    if (saved is String && saved.trim().isNotEmpty) return;
    await _saveProfile(userId, {
      'first_name': _clip(given),
      'last_name': _clip(family),
    });
    // The auth stream already reported this account, nameless. Touching the
    // user's metadata makes it report again, now with the saved name, so the
    // name screen is not asked for a name that has just arrived.
    await _client.auth
        .updateUser(UserAttributes(data: {'given_name': _clip(given)}))
        .then<void>((_) {}, onError: (Object _) {});
  }

  static String _clip(String value) =>
      value.length > 60 ? value.substring(0, 60) : value;

  /// Google's profile picture becomes the avatar when the account has none,
  /// so a new arrival is a face to the crew without being asked for one.
  Future<void> _copyProviderPhoto(User user) async {
    final picture = _metadataString(user, const ['avatar_url', 'picture']);
    if (picture == null) return;
    final profile = await _loadProfile(user.id);
    if (profile?['avatar_path'] is String) return;
    // Google serves a 96px thumbnail by default; ask for one worth showing.
    final uri = Uri.parse(picture.replaceFirst(RegExp(r'=s\d+-c$'), '=s400-c'));
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return;
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) return;
      final path = '${user.id}/avatar.png';
      await _client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType:
                  response.headers.contentType?.mimeType ?? 'image/jpeg',
              upsert: true,
            ),
          );
      await _saveProfile(user.id, {'avatar_path': path});
    } finally {
      client.close();
    }
  }

  @override
  Future<void> signOut() async {
    await beforeSignOut?.call();
    try {
      await _client.auth.signOut();
      // Without this Google quietly reuses the last account next time, and
      // somebody signing in as someone else is never asked which.
      if (_googleReady) {
        await GoogleSignIn.instance.signOut().catchError((Object _) {});
      }
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
            fileOptions: FileOptions(
              contentType: photoContentType(avatar),
              upsert: true,
            ),
          );
    }
    // The same form edits the profile later, from Account; only the first
    // save moves onboarding on.
    final firstSave = !(currentUser?.profileCompleted ?? false);
    await _saveProfile(user.id, {
      'first_name': first,
      'last_name': last,
      'avatar_path': path,
      if (firstSave) 'onboarding_step': OnboardingStep.crew.name,
    });
    return _mapUser(user)!;
  }

  @override
  Future<void> advanceOnboarding(OnboardingStep step) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in before continuing.');
    await _saveProfile(user.id, {'onboarding_step': step.name});
  }

  Future<void> _saveProfile(String userId, Map<String, Object?> fields) async {
    final row = await _client
        .from('users')
        .update(fields)
        .eq('id', userId)
        .select()
        .single();
    _profileUserId = userId;
    _profileLoad = Future.value(row);
    _keepProfile(userId, row);
  }

  @override
  Future<void> requestPasswordReset(String email) => _client.auth
      .resetPasswordForEmail(email.trim(), redirectTo: inviteRedirectBase);

  @override
  Future<void> resendConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailRedirectTo ?? inviteRedirectBase,
    );
  }

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() async =>
      NotificationPreferences.fromJson(
        Map<String, dynamic>.from(
          await _client.rpc('my_notification_preferences') as Map,
        ),
      );

  @override
  Future<NotificationPreferences> setNotificationPreference(
    NotificationKind kind,
    bool enabled,
  ) async => NotificationPreferences.fromJson(
    Map<String, dynamic>.from(
      await _client.rpc(
        'set_notification_preference',
        params: {'kind': kind.key, 'enabled': enabled},
      ) as Map,
    ),
  );

  @override
  Future<void> updatePassword(String password) async {
    if (password.length < 8) throw ArgumentError('Use at least 8 characters.');
    await _client.auth.updateUser(UserAttributes(password: password));
    // Keep the recovery screen active until the user signs out after success.
  }

  @override
  Future<void> deleteAccount({String? password}) async {
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
        body: password == null ? {'confirm': 'DELETE'} : {'password': password},
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
    final ready = _profileReady && _profileUserId == user.id;
    final data = ready ? _profile ?? const {} : const <String, dynamic>{};
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
      // A profile without a first name has not left the form, whatever the
      // row says.
      onboardingStep: first.isEmpty
          ? OnboardingStep.profile
          : OnboardingStep.parse(data['onboarding_step']),
      passwordRecoveryRequired: _recovering,
      hasPassword:
          user.identities?.any((identity) => identity.provider == 'email') ??
          user.appMetadata['provider'] == 'email',
      profileLoaded: ready,
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
  List<SignInProvider> get signInProviders => const [];

  @override
  Future<bool> signInWith(SignInProvider provider) =>
      throw StateError(_message);

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
  Future<void> deleteAccount({String? password}) async =>
      throw StateError(_message);

  @override
  Future<void> signOut() async {}

  @override
  Future<Uint8List?> loadAvatar() async => null;

  @override
  Future<void> advanceOnboarding(OnboardingStep step) async =>
      throw StateError(_message);

  @override
  Future<AuthUser> completeOnboarding({
    required String firstName,
    required String lastName,
    Uint8List? avatar,
  }) => throw StateError(_message);
}

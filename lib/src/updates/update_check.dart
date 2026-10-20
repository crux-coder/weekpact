import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// One store's row in `public.app_releases`: the newest build people can
/// download, and the oldest one that still works with the backend.
class AppRelease {
  const AppRelease({
    required this.latestVersion,
    required this.minVersion,
    this.message,
  });

  final String latestVersion;
  final String minVersion;

  /// Optional words for the prompt, such as what changed.
  final String? message;
}

abstract interface class UpdateBackend {
  /// The row for [platform] (`ios` or `android`), or null when there is none.
  Future<AppRelease?> fetchRelease(String platform);
}

class SupabaseUpdateBackend implements UpdateBackend {
  const SupabaseUpdateBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<AppRelease?> fetchRelease(String platform) async {
    final row = await _client
        .from('app_releases')
        .select('latest_version, min_version, message')
        .eq('platform', platform)
        .maybeSingle();
    if (row == null) return null;
    final message = (row['message'] as String?)?.trim();
    return AppRelease(
      latestVersion: row['latest_version'] as String,
      minVersion: row['min_version'] as String,
      message: message == null || message.isEmpty ? null : message,
    );
  }
}

/// No backend configured: there is never anything newer.
class MissingUpdateBackend implements UpdateBackend {
  const MissingUpdateBackend();

  @override
  Future<AppRelease?> fetchRelease(String platform) async => null;
}

/// How far behind the running build is.
enum UpdateNeed {
  /// Current, or nothing could be learned.
  none,

  /// Older than the newest release; offered once, and may be put off.
  optional,

  /// Older than the oldest build that still works; the app waits for it.
  required,
}

/// Compares `X.Y.Z` versions, ignoring a `+build` or `-pre` suffix. Null
/// when either side is not a version, so a bad row is never acted on.
int? compareVersions(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  if (left == null || right == null) return null;
  for (var i = 0; i < 3; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return 0;
}

List<int>? _parts(String version) {
  final core = version.trim().split(RegExp('[+-]')).first;
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) return null;
    numbers.add(number);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

/// Which release this device has already been told about, so the optional
/// prompt appears once per version rather than on every launch.
class UpdatePromptStore {
  UpdatePromptStore(this._preferences);

  /// Remembers for as long as the app is running, for tests.
  UpdatePromptStore.memory() : _preferences = null;

  static const _key = 'update_prompt_offered_version';

  final SharedPreferences? _preferences;
  String? _memory;

  String? get offeredVersion {
    final preferences = _preferences;
    if (preferences == null) return _memory;
    try {
      return preferences.getString(_key);
    } catch (_) {
      return null;
    }
  }

  Future<void> markOffered(String version) async {
    final preferences = _preferences;
    if (preferences == null) {
      _memory = version;
      return;
    }
    try {
      await preferences.setString(_key, version);
    } catch (_) {}
  }
}

/// Takes the person to the update.
abstract interface class UpdateLauncher {
  Future<void> openUpdate({required bool required});
}

/// Google Play's own update flow on Android, falling back to the store page;
/// the App Store page on iOS.
class StoreUpdateLauncher implements UpdateLauncher {
  const StoreUpdateLauncher({this.appStoreId = ''});

  static const androidPackage = 'dev.codepeaktrail.weekpact';

  /// The numeric Apple ID from App Store Connect. Without it the App Store
  /// opens on a search for the app instead of its page.
  final String appStoreId;

  Uri get storeUri {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Uri.https('play.google.com', '/store/apps/details', {
        'id': androidPackage,
      });
    }
    return appStoreId.isEmpty
        ? Uri.https('apps.apple.com', '/search', {'term': 'WeekPact'})
        : Uri.https('apps.apple.com', '/app/id$appStoreId');
  }

  @override
  Future<void> openUpdate({required bool required}) async {
    if (defaultTargetPlatform == TargetPlatform.android &&
        await _playUpdate(required: required)) {
      return;
    }
    try {
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// True when Play handled it, including the person saying no in Play's own
  /// sheet. False sends them to the store page instead: a sideloaded or test
  /// build, or a release Play has not offered this device yet.
  Future<bool> _playUpdate({required bool required}) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (required && info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        return result != AppUpdateResult.inAppUpdateFailed;
      }
      if (!required && info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          // Downloaded; installing restarts the app into the new version.
          await InAppUpdate.completeFlexibleUpdate();
        }
        return result != AppUpdateResult.inAppUpdateFailed;
      }
    } catch (_) {}
    return false;
  }
}

/// Whether this build is behind the store, read from the backend on launch
/// and again on resume when the last look is a few hours old.
///
/// Every failure is silent: offline, a missing row or an unreadable version
/// leaves the last answer in place, and the first answer is [UpdateNeed.none].
class UpdateCheck extends ChangeNotifier {
  UpdateCheck({
    required this._backend,
    required this._currentVersion,
    String? platform,
    UpdatePromptStore? store,
    this._launcher = const StoreUpdateLauncher(),
    DateTime Function()? now,
    this.interval = const Duration(hours: 4),
  }) : platform = platform ?? _devicePlatform(),
       _store = store ?? UpdatePromptStore.memory(),
       _now = now ?? DateTime.now;

  final UpdateBackend _backend;
  final Future<String> Function() _currentVersion;
  final UpdatePromptStore _store;
  final UpdateLauncher _launcher;
  final DateTime Function() _now;

  /// `ios` or `android`; anything else is never checked.
  final String platform;

  /// The least time between two checks that are not the first.
  final Duration interval;

  UpdateNeed _need = UpdateNeed.none;
  AppRelease? _release;
  DateTime? _lastCheck;
  Future<void>? _running;

  UpdateNeed get need => _need;
  AppRelease? get release => _release;

  /// Whether the optional prompt has a version this device has not been
  /// told about yet.
  bool get shouldOfferOptional =>
      _need == UpdateNeed.optional &&
      _release != null &&
      _store.offeredVersion != _release!.latestVersion;

  static String _devicePlatform() => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => '',
  };

  /// Asks the backend, unless a check ran less than [interval] ago.
  Future<void> check() {
    if (platform != 'ios' && platform != 'android') return Future.value();
    final running = _running;
    if (running != null) return running;
    final last = _lastCheck;
    if (last != null && _now().difference(last) < interval) {
      return Future.value();
    }
    _lastCheck = _now();
    return _running = _check().whenComplete(() => _running = null);
  }

  Future<void> _check() async {
    try {
      final release = await _backend.fetchRelease(platform);
      if (release == null) return;
      final current = await _currentVersion();
      final belowMin = compareVersions(current, release.minVersion);
      final belowLatest = compareVersions(current, release.latestVersion);
      if (belowMin == null || belowLatest == null) return;
      final need = belowMin < 0
          ? UpdateNeed.required
          : belowLatest < 0
          ? UpdateNeed.optional
          : UpdateNeed.none;
      _release = release;
      if (need == _need) {
        // The latest version can move while the need stays optional.
        if (need == UpdateNeed.optional) notifyListeners();
        return;
      }
      _need = need;
      notifyListeners();
    } catch (_) {}
  }

  /// Records that the current release has been offered, so it is not again.
  Future<void> markOffered() async {
    final release = _release;
    if (release != null) await _store.markOffered(release.latestVersion);
  }

  Future<void> openUpdate() =>
      _launcher.openUpdate(required: _need == UpdateNeed.required);
}

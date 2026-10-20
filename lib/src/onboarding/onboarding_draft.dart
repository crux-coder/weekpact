import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The answers a new person gives before there is an account to keep them in:
/// the crew's name and its first pact. They stay on the phone, written after
/// every screen, so closing the app halfway reopens it where it was, and they
/// become a real crew the moment sign-in succeeds.
class OnboardingDraft {
  const OnboardingDraft({
    this.crewName,
    this.pactTitle,
    this.pactIcon,
    this.pactDays,
    this.crewId,
  });

  final String? crewName;
  final String? pactTitle;
  final String? pactIcon;
  final int? pactDays;

  /// The crew made from this draft, once it exists. Saved before the pact is
  /// added so a retry after a failure never makes a second crew.
  final String? crewId;

  /// Enough to make a crew and its first pact.
  bool get complete =>
      (crewName?.trim().isNotEmpty ?? false) &&
      (pactTitle?.trim().isNotEmpty ?? false) &&
      pactIcon != null &&
      pactDays != null;

  OnboardingDraft copyWith({
    String? crewName,
    String? pactTitle,
    String? pactIcon,
    int? pactDays,
    String? crewId,
  }) => OnboardingDraft(
    crewName: crewName ?? this.crewName,
    pactTitle: pactTitle ?? this.pactTitle,
    pactIcon: pactIcon ?? this.pactIcon,
    pactDays: pactDays ?? this.pactDays,
    crewId: crewId ?? this.crewId,
  );

  Map<String, Object?> toJson() => {
    'crew_name': crewName,
    'pact_title': pactTitle,
    'pact_icon': pactIcon,
    'pact_days': pactDays,
    'crew_id': crewId,
  };

  static OnboardingDraft fromJson(Map<String, Object?> json) => OnboardingDraft(
    crewName: json['crew_name'] as String?,
    pactTitle: json['pact_title'] as String?,
    pactIcon: json['pact_icon'] as String?,
    pactDays: (json['pact_days'] as num?)?.toInt(),
    crewId: json['crew_id'] as String?,
  );
}

/// Where [OnboardingDraft] lives. One per phone rather than per account: the
/// draft exists before any account does.
class OnboardingDraftStore {
  OnboardingDraftStore(SharedPreferences preferences)
    : _preferences = preferences;

  /// Keeps the draft for the run of the app only, for tests and for a phone
  /// whose preferences could not be opened.
  OnboardingDraftStore.memory() : _preferences = null;

  static const _key = 'onboarding_draft';

  final SharedPreferences? _preferences;
  OnboardingDraft? _memory;

  OnboardingDraft? read() {
    final preferences = _preferences;
    if (preferences == null) return _memory;
    final raw = preferences.getString(_key);
    if (raw == null) return null;
    try {
      return OnboardingDraft.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Best effort: a draft that fails to save only costs the resume.
  Future<void> save(OnboardingDraft draft) async {
    _memory = draft;
    try {
      await _preferences?.setString(_key, jsonEncode(draft.toJson()));
    } catch (_) {}
  }

  Future<void> clear() async {
    _memory = null;
    try {
      await _preferences?.remove(_key);
    } catch (_) {}
  }
}

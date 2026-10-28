/// The kinds of push an account can turn off one at a time, each under the
/// key the server stores it by. A nudge is none of them and is always sent.
enum NotificationKind {
  checkIns('check_ins'),
  claps('claps'),
  chat('chat');

  const NotificationKind(this.key);
  final String key;
}

/// Which kinds of push the account wants. They follow the account to every
/// device it signs in on; the phone's own switch only decides whether this
/// device is sent anything at all.
class NotificationPreferences {
  const NotificationPreferences({
    this.checkIns = true,
    this.claps = true,
    this.chat = true,
  });

  /// A key the server leaves out is on, the way an account that never
  /// chose is sent everything.
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        checkIns: json['check_ins'] != false,
        claps: json['claps'] != false,
        chat: json['chat'] != false,
      );

  final bool checkIns;
  final bool claps;
  final bool chat;

  bool wants(NotificationKind kind) => switch (kind) {
    NotificationKind.checkIns => checkIns,
    NotificationKind.claps => claps,
    NotificationKind.chat => chat,
  };

  NotificationPreferences withKind(NotificationKind kind, bool enabled) =>
      NotificationPreferences(
        checkIns: kind == NotificationKind.checkIns ? enabled : checkIns,
        claps: kind == NotificationKind.claps ? enabled : claps,
        chat: kind == NotificationKind.chat ? enabled : chat,
      );
}

abstract interface class NotificationPreferencesBackend {
  Future<NotificationPreferences> fetchNotificationPreferences();

  /// Turns [kind] on or off and answers with all three as the server now
  /// has them.
  Future<NotificationPreferences> setNotificationPreference(
    NotificationKind kind,
    bool enabled,
  );
}

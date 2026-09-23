import 'package:shared_preferences/shared_preferences.dart';

/// Which of today's stories this device has already opened.
///
/// Per device, and only for today. Seeing a check-in is a glance rather than a
/// fact about the crew: nobody is told you looked, and the ring going grey is
/// for you alone. That makes a table, a write per tap and a policy to guard it
/// more machinery than the signal is worth — so it lives beside the crew
/// selection, in the same preferences.
///
/// The day is stored with the marks, so yesterday's rail cannot leave today's
/// looking read: a stored day that is not the day being asked about reads as
/// nothing seen, and the next mark replaces it.
class StorySeenStore {
  StorySeenStore(this._preferences);

  /// A store that remembers for as long as the app is running, for tests and
  /// for a launch where preferences could not be opened.
  StorySeenStore.memory() : _preferences = null;

  final SharedPreferences? _preferences;
  final Map<String, List<String>> _memory = {};

  String _key(String accountId) => 'seen_stories:$accountId';

  List<String> _read(String accountId) {
    final key = _key(accountId);
    final preferences = _preferences;
    if (preferences == null) return _memory[key] ?? const [];
    try {
      return preferences.getStringList(key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// The stories seen on [day], by [Story.id].
  Set<String> read(String accountId, String day) {
    final stored = _read(accountId);
    if (stored.isEmpty || stored.first != day) return const {};
    return stored.skip(1).toSet();
  }

  /// Marks [ids] seen. Best effort: a mark that cannot be written costs a grey
  /// ring, never a story, so it is not worth an error in front of the reader.
  Future<void> mark(String accountId, String day, Iterable<String> ids) async {
    final seen = read(accountId, day);
    if (ids.every(seen.contains)) return;
    final value = <String>[
      day,
      ...{...seen, ...ids},
    ];
    final key = _key(accountId);
    final preferences = _preferences;
    if (preferences == null) {
      _memory[key] = value;
      return;
    }
    try {
      await preferences.setStringList(key, value);
    } catch (_) {
      // Left unseen rather than lost: the rail simply shows the ring again.
    }
  }
}

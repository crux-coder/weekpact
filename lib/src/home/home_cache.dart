import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The crews list and the current week as the server last sent them, kept on
/// the device so the next launch opens on them while fresh ones load.
///
/// Rows are kept as they arrived, signed URLs left out, under the account
/// they were read for: nothing one account was shown is handed to the next.
/// Best effort throughout — a cache that cannot be read or written costs a
/// skeleton on the next launch, never an error.
class HomeCache {
  HomeCache(this._preferences);

  /// A cache that lasts as long as the app is running, for tests and for a
  /// launch where preferences could not be opened.
  HomeCache.memory() : _preferences = null;

  final SharedPreferences? _preferences;
  final Map<String, String> _memory = {};

  /// How many crews keep their week at once; past that the least recently
  /// written is dropped.
  static const _weeks = 4;

  String _crewsKey(String account) => 'home_cache_crews:$account';
  String _weeksKey(String account) => 'home_cache_weeks:$account';

  List<Map<String, dynamic>>? readCrews(String account) {
    final rows = _decode(_crewsKey(account));
    if (rows is! List) return null;
    return [for (final row in rows) Map<String, dynamic>.from(row as Map)];
  }

  void writeCrews(String account, List<Map<String, dynamic>> rows) =>
      _encode(_crewsKey(account), rows);

  Map<String, dynamic>? readWeek(String account, String crewId) {
    final weeks = _decode(_weeksKey(account));
    if (weeks is! Map || weeks[crewId] is! Map) return null;
    return Map<String, dynamic>.from(weeks[crewId] as Map);
  }

  void writeWeek(String account, String crewId, Map<String, dynamic> row) {
    final key = _weeksKey(account);
    final stored = _decode(key);
    final weeks = stored is Map
        ? Map<String, dynamic>.from(stored)
        : <String, dynamic>{};
    weeks
      ..remove(crewId)
      ..[crewId] = row;
    while (weeks.length > _weeks) {
      weeks.remove(weeks.keys.first);
    }
    _encode(key, weeks);
  }

  Object? _decode(String key) {
    try {
      final raw = _preferences == null
          ? _memory[key]
          : _preferences.getString(key);
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _encode(String key, Object value) {
    try {
      final raw = jsonEncode(value);
      final preferences = _preferences;
      if (preferences == null) {
        _memory[key] = raw;
      } else {
        preferences.setString(key, raw).ignore();
      }
    } catch (_) {
      // The next launch shows a skeleton instead.
    }
  }
}

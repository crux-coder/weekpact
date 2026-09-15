import 'package:shared_preferences/shared_preferences.dart';

/// Remembers each account's crew independently across app launches and sign-ins.
class CrewSelectionStore {
  CrewSelectionStore(this._preferences);

  final SharedPreferences _preferences;

  String? read(String accountId) =>
      _preferences.getString('selected_crew:$accountId');

  Future<void> save(String accountId, String crewId) async {
    if (!await _preferences.setString('selected_crew:$accountId', crewId)) {
      throw StateError('Could not remember the selected crew.');
    }
  }
}

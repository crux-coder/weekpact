import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceStore {
  const ThemePreferenceStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'theme_mode';

  ThemeMode get mode {
    final value = preferences.getString(key);
    return ThemeMode.values.where((mode) => mode.name == value).firstOrNull ??
        ThemeMode.system;
  }

  Future<void> save(ThemeMode mode) async {
    if (!await preferences.setString(key, mode.name)) {
      throw StateError('Could not save theme preference');
    }
  }
}

class ThemePreference extends InheritedWidget {
  const ThemePreference({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static ThemePreference of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemePreference>()!;

  @override
  bool updateShouldNotify(ThemePreference oldWidget) => oldWidget.mode != mode;
}

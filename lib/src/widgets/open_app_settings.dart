import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';

/// Opens this app's page in the system Settings, where a permission the
/// person declined at the prompt can be turned back on.
///
/// A denied camera or notification permission cannot be asked for twice by
/// the app; the OS only offers it again from Settings. Every screen that
/// tells someone to "allow it in Settings" should offer this rather than the
/// sentence alone, because the sentence is a dead end and this is the door.
///
/// Injected so a test can assert the door was opened without leaving the
/// process. Returns normally when the platform declines to open it, which
/// leaves the screen's copy to carry the instruction.
typedef OpenAppSettings = Future<void> Function();

Future<void> openAppSettings() async {
  try {
    await AppSettings.openAppSettings(type: AppSettingsType.settings);
  } catch (error, stack) {
    // The plugin has no channel in tests and on unsupported platforms; the
    // written instruction on screen still stands.
    if (kDebugMode) debugPrint('openAppSettings: $error\n$stack');
  }
}

import 'package:weekpact/src/updates/update_check.dart';

/// A release row that can be changed between checks, or made to fail.
class FakeUpdateBackend implements UpdateBackend {
  FakeUpdateBackend([this.release]);

  AppRelease? release;
  Object? error;
  int fetches = 0;

  @override
  Future<AppRelease?> fetchRelease(String platform) async {
    fetches++;
    final error = this.error;
    if (error != null) throw error;
    return release;
  }
}

class FakeUpdateLauncher implements UpdateLauncher {
  final opened = <bool>[];

  @override
  Future<void> openUpdate({required bool required}) async =>
      opened.add(required);
}

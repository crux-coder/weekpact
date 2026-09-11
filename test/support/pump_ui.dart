import 'package:flutter_test/flutter_test.dart';

extension PumpUi on WidgetTester {
  /// Allows finite page/data transitions to complete while the ambient wave
  /// keeps ticking. Continuous motion intentionally never settles.
  Future<void> pumpUi() async {
    for (var frame = 0; frame < 12; frame++) {
      await pump(const Duration(milliseconds: 100));
    }
  }
}

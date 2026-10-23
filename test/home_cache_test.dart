import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_cache.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// Crews the fake says this device kept from last time.
class KeptPacts extends DashboardPacts {
  @override
  List<PactCrew>? cachedCrews() => crews;
}

void main() {
  test('kept weeks are per account, last few crews only', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = HomeCache(await SharedPreferences.getInstance());
    for (final crew in ['a', 'b', 'c', 'd', 'e']) {
      cache.writeWeek('account', crew, {'today': crew});
    }
    expect(cache.readWeek('account', 'a'), isNull);
    expect(cache.readWeek('account', 'e'), {'today': 'e'});
    expect(cache.readWeek('someone-else', 'e'), isNull);
    cache.writeCrews('account', [
      {'role': 'owner'},
    ]);
    // Read back through a fresh store, as the next launch would.
    final next = HomeCache(await SharedPreferences.getInstance());
    expect(next.readCrews('account'), [
      {'role': 'owner'},
    ]);
    expect(next.readCrews('someone-else'), isNull);
  });

  testWidgets('Home opens on the kept week while the fresh one loads', (
    tester,
  ) async {
    final backend = DashboardBackend(pacts: KeptPacts());
    backend.cached = await backend.fetchWeek('crew');
    backend.loading = Completer<CrewWeek>();
    await pumpHome(tester, backend);
    await tester.pump();
    // No skeleton: the kept week is on screen before the server answers.
    expect(find.text('Move for 30 min'), findsWidgets);
    backend.loading!.complete(backend.cached);
    await tester.pumpUi();
    expect(find.text('Move for 30 min'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

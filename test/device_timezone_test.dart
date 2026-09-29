import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/device_timezone.dart';

const _channel = MethodChannel('flutter_timezone');

/// Stands in for the platform, answering `getLocalTimezone` with [answer] —
/// or, when it is null, the way a platform with no plugin behind the channel
/// does. Returns the number of calls that reached it.
int Function() _platform(Object? Function()? answer) {
  var calls = 0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls++;
        if (answer == null) throw MissingPluginException();
        return answer();
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return () => calls;
}

void main() {
  setUp(resetDeviceTimezone);
  tearDown(resetDeviceTimezone);

  test('takes the zone the platform is standing in', () async {
    _platform(() => 'Europe/Sarajevo');
    expect(await deviceTimezone(), 'Europe/Sarajevo');
  });

  test('asks the platform once and remembers the answer', () async {
    final calls = _platform(() => 'Europe/Sarajevo');
    expect(await deviceTimezone(), 'Europe/Sarajevo');
    expect(await deviceTimezone(), 'Europe/Sarajevo');
    expect(calls(), 1);
  });

  test('falls back to UTC with no plugin behind the channel', () async {
    _platform(null);
    expect(await deviceTimezone(), 'UTC');
  });

  test('falls back to UTC when the platform throws', () async {
    _platform(() => throw PlatformException(code: 'nope'));
    expect(await deviceTimezone(), 'UTC');
  });

  test('refuses a zone the crews column could not hold', () async {
    _platform(() => '   ');
    expect(await deviceTimezone(), 'UTC');
    resetDeviceTimezone();
    _platform(() => 'x' * 65);
    expect(await deviceTimezone(), 'UTC');
  });

  test(
    'does not remember a fallback, so a cold start is asked again',
    () async {
      _platform(null);
      expect(await deviceTimezone(), 'UTC');
      _platform(() => 'Europe/Sarajevo');
      expect(await deviceTimezone(), 'Europe/Sarajevo');
    },
  );

  testWidgets('a platform that never answers does not hold up a crew', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) => Completer<String>().future,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    String? zone;
    unawaited(deviceTimezone().then((value) => zone = value));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(zone, 'UTC');
  });
}

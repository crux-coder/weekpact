import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/updates/update_check.dart';
import 'package:weekpact/src/updates/update_prompt.dart';

import 'support/update_fakes.dart';

const _optionalTitle = 'A new version of WeekPact is out';
const _forcedTitle = 'Update WeekPact to continue';

void main() {
  late FakeUpdateBackend backend;
  late FakeUpdateLauncher launcher;
  late UpdatePromptStore store;
  late DateTime now;

  setUp(() {
    backend = FakeUpdateBackend();
    launcher = FakeUpdateLauncher();
    store = UpdatePromptStore.memory();
    now = DateTime(2026, 10, 20, 9);
  });

  UpdateCheck updates({String current = '1.2.0'}) => UpdateCheck(
    backend: backend,
    currentVersion: () async => current,
    platform: 'ios',
    store: store,
    launcher: launcher,
    now: () => now,
  );

  // The app's arrangement: the forced prompt over everything, the optional
  // one over Home only.
  Future<void> pumpApp(WidgetTester tester, UpdateCheck updates) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: UpdatePrompt.required(
          updates: updates,
          child: UpdatePrompt.optional(
            updates: updates,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );
    await updates.check();
    await tester.pumpAndSettle();
  }

  testWidgets('no prompt when the build is current', (tester) async {
    backend.release = const AppRelease(
      latestVersion: '1.2.0',
      minVersion: '1.0.0',
    );
    final check = updates();
    await pumpApp(tester, check);

    expect(check.need, UpdateNeed.none);
    expect(find.text(_optionalTitle), findsNothing);
    expect(find.text(_forcedTitle), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('optional prompt is shown once per release', (tester) async {
    backend.release = const AppRelease(
      latestVersion: '1.3.0',
      minVersion: '1.0.0',
      message: 'Faster check-ins.',
    );
    var check = updates();
    await pumpApp(tester, check);

    expect(find.text(_optionalTitle), findsOneWidget);
    expect(find.text('Faster check-ins.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
    expect(find.text(_optionalTitle), findsNothing);

    // A later launch of the same release stays quiet.
    await tester.pumpWidget(const SizedBox());
    check = updates();
    await pumpApp(tester, check);
    expect(check.need, UpdateNeed.optional);
    expect(find.text(_optionalTitle), findsNothing);

    // The next release is offered again, and Update opens the store.
    backend.release = const AppRelease(
      latestVersion: '1.4.0',
      minVersion: '1.0.0',
    );
    now = now.add(const Duration(hours: 5));
    await check.check();
    await tester.pumpAndSettle();
    expect(find.text(_optionalTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-now')));
    await tester.pumpAndSettle();
    expect(launcher.opened, [false]);
    expect(find.text(_optionalTitle), findsNothing);
  });

  testWidgets('optional prompt waits for Home', (tester) async {
    backend.release = const AppRelease(
      latestVersion: '1.3.0',
      minVersion: '1.0.0',
    );
    final check = updates();
    // Signed out, only the forced prompt is in the tree.
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: UpdatePrompt.required(
          updates: check,
          child: const Scaffold(body: Text('Sign in')),
        ),
      ),
    );
    await check.check();
    await tester.pumpAndSettle();
    expect(find.text(_optionalTitle), findsNothing);

    // Reaching Home, after the check already finished, offers it.
    await pumpApp(tester, check);
    expect(find.text(_optionalTitle), findsOneWidget);
  });

  testWidgets('forced prompt cannot be dismissed', (tester) async {
    backend.release = const AppRelease(
      latestVersion: '1.4.0',
      minVersion: '1.3.0',
    );
    final check = updates();
    await pumpApp(tester, check);

    expect(check.need, UpdateNeed.required);
    expect(find.text(_forcedTitle), findsOneWidget);
    expect(find.text(_optionalTitle), findsNothing);
    expect(find.byKey(const ValueKey('update-later')), findsNothing);

    // Neither the barrier nor back closes it, and Update leaves it up.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-now')));
    await tester.pumpAndSettle();
    expect(find.text(_forcedTitle), findsOneWidget);
    expect(launcher.opened, [true]);

    // Lowering min_version lifts it on the next check.
    backend.release = const AppRelease(
      latestVersion: '1.4.0',
      minVersion: '1.0.0',
    );
    now = now.add(const Duration(hours: 5));
    await check.check();
    await tester.pumpAndSettle();
    expect(find.text(_forcedTitle), findsNothing);
  });

  testWidgets('silent when the check fails or finds nothing', (tester) async {
    backend.error = Exception('offline');
    final check = updates();
    await pumpApp(tester, check);
    expect(check.need, UpdateNeed.none);
    expect(find.byType(Dialog), findsNothing);

    // No row, and a row that is not a version, are the same as offline.
    backend.error = null;
    now = now.add(const Duration(hours: 5));
    await check.check();
    backend.release = const AppRelease(latestVersion: 'soon', minVersion: '');
    now = now.add(const Duration(hours: 5));
    await check.check();
    await tester.pumpAndSettle();
    expect(check.need, UpdateNeed.none);
    expect(find.byType(Dialog), findsNothing);
  });

  test('resume checks are throttled', () async {
    backend.release = const AppRelease(
      latestVersion: '1.2.0',
      minVersion: '1.0.0',
    );
    final check = updates();
    await check.check();
    await check.check();
    expect(backend.fetches, 1);
    now = now.add(const Duration(hours: 3));
    await check.check();
    expect(backend.fetches, 1);
    now = now.add(const Duration(hours: 2));
    await check.check();
    expect(backend.fetches, 2);
  });

  test('versions compare by number and ignore build suffixes', () {
    expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
    expect(compareVersions('1.2.0+57', '1.2.0'), 0);
    expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.2.x', '1.2.0'), isNull);
    expect(compareVersions('', '1.0.0'), isNull);
  });
}

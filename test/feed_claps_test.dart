import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/feed/clap_control.dart';

import 'feed_test.dart' show FeedBackend, entry, pumpFeed;
import 'support/pump_ui.dart';

/// Posts are keyed by the check-in they show, so the whole card is a target
/// for the double tap.
Finder post(FeedBackend backend) =>
    find.byKey(ValueKey('feed-post-${backend.feed[0].id}'));

/// The clap tally is the only number on a post, so its text identifies it.
Finder tally(String count) => find.text(count);

Future<void> doubleTap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(target);
  await tester.pumpUi();
}

/// Every haptic the app asks the platform for, in order.
List<String> haptics(WidgetTester tester) {
  final buzzes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        buzzes.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return buzzes;
}

void main() {
  testWidgets('double tapping a photo bursts a clap over it', (tester) async {
    final backend = FeedBackend(entries: 1);
    backend.feed[0] = entry(0, claps: 1, clapped: true);
    await pumpFeed(tester, backend);
    expect(find.byType(ClapBurst), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClapBurst),
        matching: find.byType(HugeIcon),
      ),
      findsNothing,
    );

    await tester.tap(post(backend));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(post(backend));
    // One frame starts the burst, the next lands inside it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.descendant(
        of: find.byType(ClapBurst),
        matching: find.byType(HugeIcon),
      ),
      findsOneWidget,
    );

    // The burst is feedback, not state: it clears itself.
    await tester.pumpUi();
    expect(
      find.descendant(
        of: find.byType(ClapBurst),
        matching: find.byType(HugeIcon),
      ),
      findsNothing,
    );
  });

  testWidgets('the card gives under a double tap', (tester) async {
    final backend = FeedBackend(entries: 1);
    await pumpFeed(tester, backend);
    // The card's own scale is the outermost one; the clap icon has another.
    final card = find
        .descendant(of: post(backend), matching: find.byType(ScaleTransition))
        .first;
    expect(tester.widget<ScaleTransition>(card).scale.value, 1.0);

    await tester.tap(post(backend));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(post(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<ScaleTransition>(card).scale.value, isNot(1.0));

    // It settles back rather than leaving the card off its own size.
    await tester.pumpUi();
    expect(tester.widget<ScaleTransition>(card).scale.value, 1.0);
  });

  testWidgets('every clap gesture buzzes exactly once', (tester) async {
    final backend = FeedBackend(entries: 1);
    final buzzes = haptics(tester);
    await pumpFeed(tester, backend);

    await doubleTap(tester, post(backend));
    expect(buzzes, ['HapticFeedbackType.lightImpact']);

    // The post is clapped now, so this double tap writes nothing — it still
    // answers the finger.
    await doubleTap(tester, post(backend));
    expect(buzzes.length, 2);

    await tester.tap(find.byType(ClapButton));
    await tester.pumpUi();
    expect(buzzes.length, 3);
  });

  testWidgets('shows the clap count each check-in carries', (tester) async {
    final backend = FeedBackend(entries: 2);
    backend.feed[0] = entry(0, claps: 3, clapped: true);
    await pumpFeed(tester, backend);

    expect(tally('3'), findsOneWidget);
    // A check-in nobody clapped shows the icon alone, not a zero.
    expect(tally('0'), findsNothing);
    expect(find.byType(ClapButton), findsNWidgets(2));
  });

  testWidgets('double tapping a post claps it', (tester) async {
    final backend = FeedBackend(entries: 1);
    backend.feed[0] = entry(0, claps: 2);
    await pumpFeed(tester, backend);

    await doubleTap(tester, post(backend));

    expect(backend.clapWrites, [(backend.feed[0].id, true)]);
    expect(tally('3'), findsOneWidget);

    // A second double tap on a post already clapped leaves the clap alone
    // rather than quietly taking it back.
    await doubleTap(tester, post(backend));
    expect(backend.clapWrites.length, 1);
    expect(tally('3'), findsOneWidget);
  });

  testWidgets('the tally takes a clap back when tapped', (tester) async {
    final backend = FeedBackend(entries: 1);
    backend.feed[0] = entry(0, claps: 2, clapped: true);
    await pumpFeed(tester, backend);

    await tester.tap(find.byType(ClapButton));
    await tester.pumpUi();

    expect(backend.clapWrites, [(backend.feed[0].id, false)]);
    expect(tally('1'), findsOneWidget);

    // And tapping it again claps once more, never twice.
    await tester.tap(find.byType(ClapButton));
    await tester.pumpUi();
    expect(backend.clapWrites.last, (backend.feed[0].id, true));
    expect(tally('2'), findsOneWidget);
  });

  testWidgets('the tally answers the first tap, not the double-tap window', (
    tester,
  ) async {
    final backend = FeedBackend(entries: 1);
    backend.feed[0] = entry(0, claps: 2, clapped: true);
    await pumpFeed(tester, backend);

    await tester.tap(find.byType(ClapButton));
    await tester.pump(const Duration(milliseconds: 16));

    // The post's double tap must not hold the tally's tap hostage for the
    // 300ms it takes to rule a second tap out.
    expect(backend.clapWrites, isNotEmpty);
  });

  testWidgets('puts the post back when the clap cannot be saved', (
    tester,
  ) async {
    final backend = FeedBackend(entries: 1)..failClap = true;
    backend.feed[0] = entry(0, claps: 4);
    await pumpFeed(tester, backend);

    await doubleTap(tester, post(backend));

    expect(tally('4'), findsOneWidget);
    expect(find.text('Could not clap.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the server count rather than its own guess', (
    tester,
  ) async {
    final backend = FeedBackend(entries: 1);
    backend.feed[0] = entry(0, claps: 2);
    // Two other members clapped since the page was read.
    backend.claps[backend.feed[0].id] = 4;
    await pumpFeed(tester, backend);

    await tester.tap(find.byType(ClapButton));
    await tester.pumpUi();

    expect(tally('5'), findsOneWidget);
  });
}

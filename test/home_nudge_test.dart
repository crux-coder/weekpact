import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/nudge_sheet.dart';

import 'stories_test.dart' show StoriesBackend, pumpStoriesHome;
import 'support/pump_ui.dart';

/// The crew from [StoriesBackend]: you and Bea and Cai are in today, Eli is
/// not. Eli's tile is the dashed one, and the only one a press is offered on.
class NudgeFromRailBackend extends StoriesBackend {
  NudgeFromRailBackend({this.status = CrewNudgeStatus.ready});

  final CrewNudgeStatus status;
  bool failStates = false;
  bool failSend = false;
  Completer<CrewNudgeState>? pending;
  final sent = <String>[];
  int stateReads = 0;

  /// A cooldown that ends eighteen hours from now, wherever "now" happens to
  /// be: the sheet counts down to it, so a fixed date would read as a
  /// different span every day the suite is run.
  static final cooldownEnds = DateTime.now().add(
    const Duration(hours: 18, minutes: 4),
  );

  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async {
    stateReads++;
    if (failStates) throw StateError('offline');
    return {
      'eli': CrewNudgeState(
        status,
        nextAllowedAt: status == CrewNudgeStatus.cooldown ? cooldownEnds : null,
      ),
    };
  }

  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) async {
    sent.add(recipientId);
    if (failSend) throw StateError('offline');
    if (pending != null) return pending!.future;
    return CrewNudgeState(
      CrewNudgeStatus.sent,
      nextAllowedAt: DateTime.utc(2026, 9, 10, 9),
    );
  }
}

Finder _tile(String id) => find.byKey(ValueKey('story-tile-$id'));

void main() {
  group('the reason a nudge opens with', () {
    test('counts back from today in plain days', () {
      expect(
        nudgeReason(today: '2026-09-09', lastKept: null),
        'Nothing kept this week yet.',
      );
      expect(
        nudgeReason(today: '2026-09-09', lastKept: '2026-09-08'),
        'Last kept a pact yesterday.',
      );
      expect(
        nudgeReason(today: '2026-09-09', lastKept: '2026-09-07'),
        'Last kept a pact 2 days ago.',
      );
      // A day the week does not otherwise expect is still read as a date
      // rather than as an error.
      expect(
        nudgeReason(today: '2026-09-09', lastKept: '2026-09-09'),
        'Last kept a pact today.',
      );
    });
  });

  group('the wait before the next nudge', () {
    test('is a span rather than a date', () {
      expect(nudgeCountdown(const Duration(hours: 18)), 'in 18 hours');
      expect(nudgeCountdown(const Duration(minutes: 40)), 'in 40 minutes');
      expect(nudgeCountdown(const Duration(hours: 1)), 'in an hour');
      expect(nudgeCountdown(const Duration(hours: 24)), 'in a day');
    });

    test('never counts down to nothing', () {
      // The send is what decides, so a deadline already passed still reads as
      // a wait rather than as "in 0 minutes" or a negative one.
      expect(nudgeCountdown(const Duration(seconds: 20)), 'in a minute');
      expect(nudgeCountdown(Duration.zero), 'in a minute');
      expect(nudgeCountdown(const Duration(minutes: -5)), 'in a minute');
    });

    test('rounds up rather than sending someone back early', () {
      expect(nudgeCountdown(const Duration(minutes: 95)), 'in 2 hours');
      expect(nudgeCountdown(const Duration(seconds: 100)), 'in 2 minutes');
    });
  });

  testWidgets('a crewmate who is not in takes a press, and a nudge', (
    tester,
  ) async {
    final backend = NudgeFromRailBackend();
    await pumpStoriesHome(tester, backend: backend);
    // Fetched with the week, so the offer opens in the state it is really in
    // rather than loading under the finger.
    expect(backend.stateReads, 1);

    await tester.longPress(_tile('eli'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nudge-dialog')), findsOneWidget);
    expect(find.text('Eli Fisher hasn’t been out today'), findsOneWidget);
    expect(find.textContaining('Nothing kept this week yet.'), findsOneWidget);
    expect(
      find.textContaining('One nudge per person every 24 hours.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    expect(backend.sent, ['eli']);
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
    expect(find.text('Nudged Eli Fisher.'), findsOneWidget);
  });

  testWidgets('a plain tap on a dashed tile opens the same offer', (
    tester,
  ) async {
    // A long press was the only entrance on the one page that draws the rail,
    // and a gesture with no mark on it is a feature nobody finds. A dashed
    // tile has nothing else behind a tap, so the tap is the nudge.
    final backend = NudgeFromRailBackend();
    await pumpStoriesHome(tester, backend: backend);
    await tester.tap(_tile('eli'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nudge-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    expect(backend.sent, ['eli']);
  });

  testWidgets('the offer can be left without sending', (tester) async {
    final backend = NudgeFromRailBackend();
    await pumpStoriesHome(tester, backend: backend);
    await tester.longPress(_tile('eli'));
    await tester.pumpUi();
    await tester.tap(find.text('Not now'));
    await tester.pumpUi();
    expect(backend.sent, isEmpty);
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
  });

  testWidgets('a crewmate already nudged says when they can be nudged again', (
    tester,
  ) async {
    final backend = NudgeFromRailBackend(status: CrewNudgeStatus.cooldown);
    await pumpStoriesHome(tester, backend: backend);
    await tester.longPress(_tile('eli'));
    await tester.pumpUi();
    expect(find.text('ALREADY NUDGED'), findsOneWidget);
    // A span, not a date: the cooldown is 24 hours from the send, so "on Sep
    // 29" sends someone back at nine the next morning to be refused again.
    expect(
      find.textContaining('You can nudge again in 18 hours'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    expect(backend.sent, isEmpty);
  });

  testWidgets('a nudge that does not send says so and can be retried', (
    tester,
  ) async {
    final backend = NudgeFromRailBackend()..failSend = true;
    await pumpStoriesHome(tester, backend: backend);
    await tester.longPress(_tile('eli'));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    // The offer stays open on the failure rather than closing on a nudge that
    // never landed.
    expect(find.byKey(const ValueKey('nudge-dialog')), findsOneWidget);
    expect(find.textContaining('That nudge did not send.'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    backend.failSend = false;
    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    expect(backend.sent, ['eli', 'eli']);
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
  });

  testWidgets('states that will not load leave the nudge standing', (
    tester,
  ) async {
    // The send is what knows whether a nudge is allowed. A states call that
    // fell over should not take the feature down with it.
    final backend = NudgeFromRailBackend()..failStates = true;
    await pumpStoriesHome(tester, backend: backend);
    expect(tester.takeException(), isNull);
    await tester.longPress(_tile('eli'));
    await tester.pumpUi();
    expect(find.text('NUDGE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-nudge')));
    await tester.pumpUi();
    expect(backend.sent, ['eli']);
  });

  testWidgets('you cannot nudge yourself, or anyone already out', (
    tester,
  ) async {
    await pumpStoriesHome(tester, backend: NudgeFromRailBackend());
    // Your own tile is dashed until you have kept something, and it is still
    // not a tile to press: you cannot nudge yourself out of bed.
    await tester.longPress(_tile(''));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
    // Bea is in, so her tile's gestures are already spoken for: a press opens
    // nothing, and a tap opens her stories.
    await tester.longPress(_tile('bea'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
  });
}

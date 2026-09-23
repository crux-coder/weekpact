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

  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async {
    stateReads++;
    if (failStates) throw StateError('offline');
    return {
      'eli': CrewNudgeState(
        status,
        nextAllowedAt: status == CrewNudgeStatus.cooldown
            ? DateTime.utc(2026, 9, 10, 9)
            : null,
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
    expect(find.textContaining('You can nudge again on'), findsOneWidget);
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
    // Bea is in, so her tile's gesture is already spoken for: a press opens
    // nothing, and a tap opens her stories.
    await tester.longPress(_tile('bea'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
  });
}

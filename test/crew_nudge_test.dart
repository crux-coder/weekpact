import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/crew_member_list.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

class NudgeBackend extends DashboardBackend {
  int sends = 0;
  bool fail = false;
  bool failStatus = false;
  Completer<CrewNudgeState>? pending;
  CrewNudgeState state = const CrewNudgeState(CrewNudgeStatus.ready);
  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async {
    if (failStatus) throw StateError('offline');
    return {'other': state};
  }

  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) async {
    expect(crewId, 'crew');
    expect(recipientId, 'other');
    sends++;
    if (fail) throw StateError('offline');
    return state = pending != null
        ? await pending!.future
        : CrewNudgeState(
            CrewNudgeStatus.sent,
            nextAllowedAt: DateTime.now().add(const Duration(hours: 24)),
          );
  }
}

Future<void> showMembers(
  WidgetTester tester,
  NudgeBackend backend, {
  bool done = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: CrewMemberList(
          backend: backend,
          crewId: 'crew',
          userId: 'me',
          done: done,
          members: const [
            WeekMember('me', '', displayName: 'Jasmin Hadžić'),
            WeekMember('other', '', displayName: 'Mira Petrović'),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'only other pending members can be nudged; duplicate taps and reopening respect cooldown',
    (tester) async {
      final backend = NudgeBackend()..pending = Completer<CrewNudgeState>();
      await showMembers(tester, backend);
      expect(find.byKey(const ValueKey('nudge-me')), findsNothing);
      final button = find.byKey(const ValueKey('nudge-other'));
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      await tester.tap(button);
      expect(backend.sends, 1);
      backend.pending!.complete(
        CrewNudgeState(
          CrewNudgeStatus.sent,
          nextAllowedAt: DateTime.now().add(const Duration(hours: 24)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nudged'), findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      await showMembers(tester, backend);
      expect(find.text('Nudged'), findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      await showMembers(tester, backend, done: true);
      expect(button, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'status and send failures retry without falsely showing success',
    (tester) async {
      final backend = NudgeBackend()..failStatus = true;
      await showMembers(tester, backend);
      expect(find.text('Could not load nudges.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('nudge-other')))
            .onPressed,
        isNull,
      );
      backend.failStatus = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      backend.fail = true;
      await tester.tap(find.text('Nudge'));
      await tester.pumpAndSettle();
      expect(find.text('Could not send. Try again.'), findsOneWidget);
      expect(find.text('Nudged'), findsNothing);
      backend.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Nudged'), findsOneWidget);
      expect(backend.sends, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'server rejects stale eligibility and completing after close is safe',
    (tester) async {
      final backend = NudgeBackend()..pending = Completer<CrewNudgeState>();
      await showMembers(tester, backend);
      await tester.tap(find.text('Nudge'));
      backend.pending!.complete(
        const CrewNudgeState(CrewNudgeStatus.checkedIn),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('Nudged'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      backend.state = const CrewNudgeState(CrewNudgeStatus.ready);
      backend.pending = Completer<CrewNudgeState>();
      await showMembers(tester, backend);
      await tester.tap(find.text('Nudge'));
      await tester.pumpWidget(const SizedBox());
      backend.pending!.complete(
        const CrewNudgeState(CrewNudgeStatus.unavailable),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cooldown expiry refreshes server state while the list stays open',
    (tester) async {
      final backend = NudgeBackend()
        ..state = CrewNudgeState(
          CrewNudgeStatus.cooldown,
          nextAllowedAt: DateTime.now().add(const Duration(seconds: 2)),
        );
      await showMembers(tester, backend);
      expect(find.text('Nudged'), findsOneWidget);
      backend.state = const CrewNudgeState(CrewNudgeStatus.ready);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Nudge'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('nudge-other')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/invites/invite_acceptance_page.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeCrewBackend;

/// A crew backend whose join can fail, or succeed without the crew loading.
class InvitedCrews extends FakeCrewBackend {
  int accepts = 0;
  bool joinedWithoutDetails = false;

  @override
  Future<CrewDetails> acceptInvite(String code) async {
    accepts++;
    if (joinedWithoutDetails) {
      acceptedTokens.add(code);
      throw const CrewJoinedWithoutDetails('crew-without-details');
    }
    return super.acceptInvite(code);
  }
}

const _preview = CrewInvitePreview(
  crewName: 'Early Birds',
  memberCount: 3,
  ownerName: 'Amra',
  inviterName: 'Edin',
  pacts: [
    InvitePact(title: 'Read before bed', iconKey: 'book', daysPerWeek: 5),
  ],
);

class _Outcome {
  final joined = <String>[];
  var dismissed = 0;
  final newInvites = <InviteRef>[];
}

Future<_Outcome> _pump(
  WidgetTester tester,
  InvitedCrews backend, {
  CrewInvitePreview? preview = _preview,
  bool previewMissing = false,
  bool autoJoin = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final outcome = _Outcome();
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: InviteAcceptancePage(
        crewBackend: backend,
        invite: const InviteRef('7K2QXM'),
        preview: preview,
        previewMissing: previewMissing,
        autoJoin: autoJoin,
        onJoined: outcome.joined.add,
        onDismiss: () => outcome.dismissed++,
        onNewInvite: outcome.newInvites.add,
      ),
    ),
  );
  await tester.pumpUi();
  return outcome;
}

Future<void> _join(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('accept-invite'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpUi();
}

void main() {
  testWidgets('the invite leads with who sent it, then joins on one tap', (
    tester,
  ) async {
    final backend = InvitedCrews();
    final outcome = await _pump(tester, backend);

    expect(find.text('Edin invited you.'), findsOneWidget);
    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.text('Read before bed'), findsOneWidget);
    expect(find.text('JOIN EARLY BIRDS'), findsOneWidget);
    await _join(tester);

    expect(backend.acceptedTokens, ['7K2QXM']);
    expect(outcome.joined, hasLength(1));
  });

  testWidgets('somebody who tapped Join before signing in is not asked again', (
    tester,
  ) async {
    final backend = InvitedCrews();
    final outcome = await _pump(tester, backend, autoJoin: true);
    expect(backend.accepts, 1);
    expect(outcome.joined, hasLength(1));
  });

  testWidgets('a join whose crew will not load still counts as joined', (
    tester,
  ) async {
    final backend = InvitedCrews()..joinedWithoutDetails = true;
    final outcome = await _pump(tester, backend);
    await _join(tester);
    expect(outcome.joined, ['crew-without-details']);
  });

  testWidgets('a reset or mistyped code offers another code', (tester) async {
    final backend = InvitedCrews()
      ..acceptError = Exception('This invite code is no longer valid');
    final outcome = await _pump(tester, backend);
    await _join(tester);

    expect(find.text('This invite doesn’t work anymore.'), findsOneWidget);
    expect(outcome.joined, isEmpty);
    await tester.tap(find.text('START MY OWN CREW'));
    await tester.pumpUi();
    expect(outcome.dismissed, 1);
  });

  testWidgets('a preview that found nothing goes straight to the problem', (
    tester,
  ) async {
    final backend = InvitedCrews();
    await _pump(tester, backend, preview: null, previewMissing: true);
    expect(find.text('This invite doesn’t work anymore.'), findsOneWidget);
    expect(backend.accepts, 0);
  });

  testWidgets('a network failure is not blamed on the invite', (tester) async {
    final backend = InvitedCrews()..acceptError = StateError('offline');
    final outcome = await _pump(tester, backend);
    await _join(tester);

    expect(
      find.text(
        'Could not reach WeekPact. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('TRY AGAIN'), findsOneWidget);
    backend.acceptError = null;
    await _join(tester);
    expect(outcome.joined, hasLength(1));
  });

  testWidgets('a member opening their own crew’s invite is sent to it', (
    tester,
  ) async {
    final backend = InvitedCrews();
    final outcome = await _pump(
      tester,
      backend,
      preview: const CrewInvitePreview(
        crewName: 'Early Birds',
        memberCount: 3,
        ownerName: 'Amra',
        isMember: true,
      ),
    );
    expect(find.text('You’re already in.'), findsOneWidget);
    await tester.tap(find.text('GO TO EARLY BIRDS'));
    await tester.pumpUi();
    // Joining a crew you are in is not an error, and it hands back its id.
    expect(outcome.joined, hasLength(1));
  });
}

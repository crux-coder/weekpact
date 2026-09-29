import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/invites/invite_acceptance_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeCrewBackend;

/// A crew backend whose two answers to an invitation — the preview and the
/// join — can each be made to fail on their own.
class InvitedCrews extends FakeCrewBackend {
  Object? acceptError;
  bool previewThrows = false;
  int accepts = 0;

  @override
  Future<CrewInvitePreview?> previewInvite(String token) async {
    if (previewThrows) throw StateError('offline');
    return preview;
  }

  @override
  Future<CrewDetails> acceptInvite(String token) async {
    accepts++;
    final failure = acceptError;
    if (failure != null) throw failure;
    return super.acceptInvite(token);
  }
}

Future<List<String>> pumpInvite(
  WidgetTester tester,
  InvitedCrews backend, {
  VoidCallback? onFinished,
}) async {
  final joined = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: InviteAcceptancePage(
        email: 'friend@example.com',
        token: 'a' * 64,
        crewBackend: backend,
        onFinished: onFinished ?? () {},
        onAccepted: joined.add,
      ),
    ),
  );
  await tester.pumpUi();
  return joined;
}

void main() {
  testWidgets('a join the server accepted is not reported as a failure when '
      'the crew will not load', (tester) async {
    final backend = InvitedCrews()
      ..acceptError = const CrewJoinedWithoutDetails('crew-1');
    var finished = false;
    final joined = await pumpInvite(
      tester,
      backend,
      onFinished: () => finished = true,
    );
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(joined, ['crew-1'], reason: 'Home is told which crew to open');
    expect(finished, isTrue);
    expect(
      find.textContaining('ask the owner to resend'),
      findsNothing,
      reason: 'the person is already a member',
    );
    expect(find.textContaining('Could not reach WeekPact'), findsNothing);
  });

  testWidgets('the invitation names the crew and its size once the preview '
      'arrives', (tester) async {
    final backend = InvitedCrews()
      ..preview = const CrewInvitePreview(
        crewName: 'Early Birds',
        memberCount: 3,
        ownerName: 'Ada Lovelace',
      );
    await pumpInvite(tester, backend);

    expect(find.text('Join Early Birds'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsOneWidget);
    expect(find.text('Your crew is waiting.'), findsNothing);
  });

  testWidgets('a preview that fails leaves the invitation saying what it '
      'always said', (tester) async {
    await pumpInvite(tester, InvitedCrews()..previewThrows = true);

    expect(find.text('Your crew is waiting.'), findsOneWidget);
    expect(find.text('ACCEPT INVITE'), findsOneWidget);
  });

  testWidgets('an unreachable server offers a retry rather than blaming the '
      'invitation', (tester) async {
    final backend = InvitedCrews()
      ..acceptError = Exception('Connection closed');
    final joined = await pumpInvite(tester, backend);
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(
      find.text(
        'Could not reach WeekPact. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ask the owner to resend'), findsNothing);

    backend.acceptError = null;
    await tester.ensureVisible(find.text('TRY AGAIN'));
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();

    expect(backend.accepts, 2);
    expect(joined, isNotEmpty);
  });

  testWidgets('an expired link keeps its own wording and is not worth '
      'retrying', (tester) async {
    final backend = InvitedCrews()
      ..acceptError = Exception('This invite link has expired');
    await pumpInvite(tester, backend);
    await tester.ensureVisible(find.text('ACCEPT INVITE'));
    await tester.tap(find.text('ACCEPT INVITE'));
    await tester.pumpUi();

    expect(find.text('This invite link has expired'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import 'home_backend.dart';

/// The nudge, offered where you notice someone is missing.
///
/// The crew roster behind the crew strip's pull has carried nudges since they
/// were built, and Home does not draw that strip — so on the page people
/// actually open, the feature had no entrance at all. The stories rail has
/// one: a member who has not been out today is a dashed tile, which is the
/// only tile with nothing behind a tap, and the exact object the thought is
/// about.
///
/// It opens with a reason rather than only a button. "Last kept a pact three
/// days ago" is the difference between poking someone and noticing them, and
/// it is read off the week the page already holds.
Future<CrewNudgeState?> showNudge({
  required BuildContext context,
  required HomeBackend backend,
  required String crewId,
  required WeekMember member,
  required CrewNudgeState? state,
  required String today,
  required String? lastKept,
}) => showAppDialog<CrewNudgeState>(
  context: context,
  builder: (context) => _NudgeDialog(
    backend: backend,
    crewId: crewId,
    member: member,
    state: state,
    today: today,
    lastKept: lastKept,
  ),
);

/// How the week reads a member's last kept day, in plain days.
///
/// A weekday name would need a locale the app does not otherwise ask for, and
/// "three days ago" is the number the sentence is about anyway. Null when the
/// week holds nothing for them, which is its own sentence.
@visibleForTesting
String nudgeReason({required String today, String? lastKept}) {
  if (lastKept == null) return 'Nothing kept this week yet.';
  final days = DateTime.parse(today)
      .difference(DateTime.parse(lastKept))
      .inDays;
  return switch (days) {
    <= 0 => 'Last kept a pact today.',
    1 => 'Last kept a pact yesterday.',
    _ => 'Last kept a pact $days days ago.',
  };
}

class _NudgeDialog extends StatefulWidget {
  const _NudgeDialog({
    required this.backend,
    required this.crewId,
    required this.member,
    required this.state,
    required this.today,
    required this.lastKept,
  });

  final HomeBackend backend;
  final String crewId;
  final WeekMember member;
  final CrewNudgeState? state;
  final String today;
  final String? lastKept;

  @override
  State<_NudgeDialog> createState() => _NudgeDialogState();
}

class _NudgeDialogState extends State<_NudgeDialog> {
  bool _sending = false;
  bool _failed = false;

  String get _name {
    final full = widget.member.displayName.trim();
    return full.isEmpty || full == 'Crew member' ? 'Your crewmate' : full;
  }

  /// Nothing loaded is still offered. The send is the thing that knows whether
  /// a nudge is allowed — the state only saves the person a refusal — and a
  /// states call that failed should not take the feature down with it.
  bool get _ready =>
      widget.state == null || widget.state!.status == CrewNudgeStatus.ready;

  bool get _alreadyNudged =>
      widget.state?.status == CrewNudgeStatus.sent ||
      widget.state?.status == CrewNudgeStatus.cooldown;

  String get _label {
    if (_sending) return 'SENDING…';
    if (_failed) return 'TRY AGAIN';
    if (_alreadyNudged) return 'ALREADY NUDGED';
    return _ready ? 'NUDGE' : 'CANNOT NUDGE';
  }

  /// The second line: why they are being nudged, and what the nudge costs.
  String get _message {
    final reason = nudgeReason(today: widget.today, lastKept: widget.lastKept);
    if (_failed) return '$reason\n\nThat nudge did not send. Try again.';
    if (_alreadyNudged) {
      final deadline = widget.state?.nextAllowedAt?.toLocal();
      if (deadline == null) return '$reason\n\nYou have already nudged today.';
      final localizations = MaterialLocalizations.of(context);
      return '$reason\n\nYou can nudge again on '
          '${localizations.formatMediumDate(deadline)}.';
    }
    if (!_ready) return '$reason\n\nThey cannot be nudged right now.';
    return '$reason\n\nOne nudge per person every 24 hours.';
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      final result = await widget.backend.sendNudge(
        crewId: widget.crewId,
        recipientId: widget.member.id,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    key: const ValueKey('nudge-dialog'),
    icon: HugeIconsStrokeRounded.handPointingRight01,
    iconColor: WeekPactColors.crewProgress,
    title: '$_name hasn’t been out today',
    message: _message,
    actions: [
      AppButton(
        key: const ValueKey('send-nudge'),
        label: _label,
        isLoading: _sending,
        onPressed: (_ready || _failed) && !_sending ? _send : null,
      ),
      const AppDialogDismiss(label: 'Not now'),
    ],
  );
}

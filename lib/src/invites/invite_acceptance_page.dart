import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/onboarding_widgets.dart';
import '../onboarding/setup_pages.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import 'invite_code_entry.dart';
import 'invite_links.dart';

/// A signed-in account holding an invite.
///
/// Somebody who tapped Join before signing in has already decided, so with
/// [autoJoin] the join happens at once. Anyone else — a member opening a
/// friend's link, or a code typed on Home — sees the crew first and joins
/// with one tap.
class InviteAcceptancePage extends StatefulWidget {
  const InviteAcceptancePage({
    super.key,
    required this.crewBackend,
    required this.invite,
    required this.onJoined,
    required this.onDismiss,
    this.preview,
    this.previewMissing = false,
    this.autoJoin = false,
    this.notify = true,
    this.onNewInvite,
  });

  final CrewBackend crewBackend;
  final InviteRef invite;
  final CrewInvitePreview? preview;

  /// The preview answered nothing: an unknown or reset code.
  final bool previewMissing;
  final bool autoJoin;

  /// The notification switch's starting position.
  final bool notify;

  /// The crew that was joined, by id. It is the id rather than the crew
  /// itself because a join can succeed while the crew that follows it will
  /// not load, and Home only ever wanted the id.
  final ValueChanged<String> onJoined;

  /// Leaves the invite unused and goes on to Home.
  final VoidCallback onDismiss;

  /// A different code, typed after this one turned out not to work.
  final ValueChanged<InviteRef>? onNewInvite;

  @override
  State<InviteAcceptancePage> createState() => _InviteAcceptancePageState();
}

class _InviteAcceptancePageState extends State<InviteAcceptancePage> {
  bool _accepting = false;
  bool _invalid = false;
  String? _error;
  late bool _notify = widget.notify;

  @override
  void initState() {
    super.initState();
    if (widget.autoJoin && !widget.previewMissing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _accept();
      });
    }
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    String? crewId;
    try {
      crewId = (await widget.crewBackend.acceptInvite(widget.invite.code)).id;
    } on CrewJoinedWithoutDetails catch (joined) {
      // The membership exists; only the crew behind it would not load.
      // Saying the invite failed would send a member off for a fresh code.
      crewId = joined.crewId;
    } catch (error) {
      if (!mounted) return;
      setState(() => _accepting = false);
      if (_isDeadInvite(error)) {
        setState(() => _invalid = true);
        return;
      }
      setState(
        () => _error =
            'Could not reach WeekPact. Check your connection and try again.',
      );
      return;
    }
    if (!mounted) return;
    if (_notify && !(widget.preview?.isMember ?? false)) {
      await askForNotifications(context);
    }
    if (mounted) widget.onJoined(crewId);
  }

  Future<void> _enterAnother() async {
    final onNew = widget.onNewInvite;
    if (onNew == null) {
      widget.onDismiss();
      return;
    }
    final invite = await showAppSheet<InviteRef>(
      context: context,
      builder: (sheetContext) => AppSheet(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Join with a code',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InviteCodeEntry(
              onInvite: (invite) => Navigator.pop(context, invite),
            ),
          ],
        ),
      ),
    );
    if (invite != null && mounted) onNew(invite);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    if (_invalid || widget.previewMissing) {
      return InviteProblemView(
        problem: InviteProblem.invalid,
        onPrimary: _enterAnother,
        onSecondary: widget.onDismiss,
      );
    }
    if (preview?.isMember ?? false) {
      return InviteProblemView(
        problem: InviteProblem.member,
        crewName: preview!.crewName,
        onPrimary: _accept,
      );
    }
    if (widget.autoJoin && _error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return OnboardingScaffold(
      onBack: _accepting ? null : widget.onDismiss,
      title: preview == null
          ? 'Your crew is waiting.'
          : '${preview.inviterName} invited you.',
      subtitle: 'To keep each other honest, one small pact at a time.',
      body: [
        if (preview == null)
          const Center(child: CircularProgressIndicator())
        else
          InvitePreviewCard(preview: preview),
        const SizedBox(height: 10),
        NotifySwitchCard(
          title: 'Tell me when they check in',
          value: _notify,
          onChanged: (value) => setState(() => _notify = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        AppButton(
          key: const ValueKey('accept-invite'),
          label: _error != null
              ? 'TRY AGAIN'
              : preview == null
              ? 'JOIN THE CREW'
              : 'JOIN ${preview.crewName.toUpperCase()}',
          color: WeekPactColors.mintGreen,
          height: 56,
          isLoading: _accepting,
          onPressed: _accept,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _accepting ? null : widget.onDismiss,
          style: TextButton.styleFrom(foregroundColor: context.muted),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// The refusals that mean the invite itself is no good, as opposed to the
/// network having a bad minute.
bool _isDeadInvite(Object error) {
  final message = error.toString();
  return message.contains('no longer valid') ||
      message.contains('Invalid invite') ||
      message.contains('has expired') ||
      message.contains('already been used');
}

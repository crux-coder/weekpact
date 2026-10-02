import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
import '../notifications/notification_primer_page.dart';
import '../subscriptions/pro_upgrade.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';

class InviteAcceptancePage extends StatefulWidget {
  const InviteAcceptancePage({
    super.key,
    required this.email,
    required this.token,
    required this.crewBackend,
    required this.onFinished,
    this.onAccepted,
  });

  final String email;
  final String token;
  final CrewBackend crewBackend;
  final VoidCallback onFinished;

  /// The crew that was joined, by id. It is the id rather than the crew
  /// itself because a join can succeed while the crew that follows it will
  /// not load, and Home only ever wanted the id.
  final ValueChanged<String>? onAccepted;

  @override
  State<InviteAcceptancePage> createState() => _InviteAcceptancePageState();
}

class _InviteAcceptancePageState extends State<InviteAcceptancePage> {
  bool _accepting = false;
  String? _error;
  bool _canRetry = false;
  CrewInvitePreview? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  /// The card reads better with the crew's name on it, and it is only ever
  /// decoration: a preview that fails or answers nothing leaves the page
  /// saying what it said before, because the invitation is still good.
  Future<void> _loadPreview() async {
    try {
      final preview = await widget.crewBackend.previewInvite(widget.token);
      if (mounted && preview != null) setState(() => _preview = preview);
    } catch (_) {
      /* The invitation stands whether or not it can introduce itself. */
    }
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
      _canRetry = false;
    });
    try {
      final crew = await widget.crewBackend.acceptInvite(widget.token);
      if (mounted) await _joined(crew.id, crew.name);
    } on CrewJoinedWithoutDetails catch (joined) {
      // The membership exists; only the crew behind it would not load. Saying
      // the invitation failed would send a member off for a fresh link.
      if (mounted) await _joined(joined.crewId, _preview?.crewName);
    } catch (error) {
      if (!mounted) return;
      setState(() => _accepting = false);
      if (isCrewLimitError(error)) {
        if (await showCrewLimitUpgrade(
              context,
              reason: CrewLimitReason.joining,
            ) &&
            mounted) {
          await _accept();
        }
        return;
      }
      final known = _knownInviteProblem(error);
      if (mounted) {
        setState(() {
          _error = known ?? _unreachable;
          _canRetry = known == null;
        });
      }
    }
  }

  /// In. The one ask for notifications comes here, while the crew that will
  /// send them is the thing on screen, and Home follows either answer.
  Future<void> _joined(String crewId, String? crewName) async {
    widget.onAccepted?.call(crewId);
    await NotificationPrimerPage.show(
      context,
      crewName: crewName ?? 'the crew',
      reason: NotificationPrimerReason.joined,
    );
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      body: PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CREW INVITATION',
              style: TextStyle(
                color: context.muted,
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            AppSurface(
              fillColor: WeekPactColors.cream,
              borderWidth: 0,
              builder: (context) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WeekPactColors.coolGrey,
                          borderRadius: BorderRadius.circular(
                            WeekPactMetrics.controlRadius,
                          ),
                        ),
                        child: AppIcon(
                          icon: HugeIconsStrokeRounded.userGroup,
                          size: 32,
                          color: context.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      preview == null
                          ? 'Your crew is waiting.'
                          : 'Join ${preview.crewName}',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 38,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.7,
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        preview.memberCount == 1
                            ? '1 member'
                            : '${preview.memberCount} members',
                        style: TextStyle(
                          color: context.muted,
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      preview == null
                          ? 'Build your habits together. Join the crew to see its pacts and check in with your people.'
                          : '${preview.ownerName} is building habits with their people. Join to see the crew’s pacts and check in alongside them.',
                      style: TextStyle(
                        color: context.muted,
                        fontFamily: WeekPactType.secondary,
                        fontFamilyFallback: WeekPactType.secondaryFallback,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 26),
                    AppButton(
                      label: 'ACCEPT INVITE',
                      icon: HugeIconsStrokeRounded.arrowRight01,
                      isLoading: _accepting,
                      onPressed: _accept,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SIGNED IN AS',
              style: TextStyle(
                color: context.muted,
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.email,
              style: TextStyle(
                color: context.ink,
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontWeight: FontWeight.w400,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: context.errorInk,
                    fontFamily: WeekPactType.secondary,
                    fontFamilyFallback: WeekPactType.secondaryFallback,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              if (_canRetry) ...[
                const SizedBox(height: 12),
                AppButton(
                  label: 'TRY AGAIN',
                  isLoading: _accepting,
                  onPressed: _accept,
                ),
              ],
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: _accepting ? null : widget.onFinished,
              style: TextButton.styleFrom(foregroundColor: context.muted),
              child: const Text('NOT NOW'),
            ),
          ],
        ),
      ),
    );
  }
}

const _unreachable =
    'Could not reach WeekPact. Check your connection and try again.';

/// The refusals the database actually has a name for. Everything else — a
/// phone with no signal, a gateway having a bad minute — used to be told it
/// was a bad invitation, which sent people to the crew owner for a link that
/// was never the problem.
String? _knownInviteProblem(Object error) {
  final message = error.toString();
  for (final known in [
    'Invite is invalid or has already been used',
    'Invite has expired',
    'This invite link has expired',
    'Confirm your email before joining',
    'Sign in with the email address that received this invite',
  ]) {
    if (message.contains(known)) return known;
  }
  return null;
}

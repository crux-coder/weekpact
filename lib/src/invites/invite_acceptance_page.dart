import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
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
  final ValueChanged<CrewDetails>? onAccepted;

  @override
  State<InviteAcceptancePage> createState() => _InviteAcceptancePageState();
}

class _InviteAcceptancePageState extends State<InviteAcceptancePage> {
  bool _accepting = false;
  String? _error;

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final crew = await widget.crewBackend.acceptInvite(widget.token);
      if (mounted) {
        widget.onAccepted?.call(crew);
        widget.onFinished();
      }
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
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageFrame(
      header: const PageHeading(
        'Invitation',
        dotColor: WeekPactColors.coolGrey,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CREW INVITATION',
            style: TextStyle(
              color: context.muted,
              fontFamily: 'Roboto',
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
                          WeekPactMetrics.cardRadius,
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
                    'Your crew is waiting.',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 38,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Build your habits together. Join the crew to see its pacts and check in with your people.',
                    style: TextStyle(
                      color: context.muted,
                      fontFamily: 'Roboto',
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
              fontFamily: 'Roboto',
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
              fontFamily: 'Roboto',
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
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
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

String _friendlyError(Object error) {
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
  return 'Could not accept this invitation. Please ask the owner to resend it.';
}

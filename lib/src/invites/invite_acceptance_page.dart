import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
import '../theme/keepup_theme.dart';
import '../widgets/brutal_widgets.dart';

class InviteAcceptancePage extends StatefulWidget {
  const InviteAcceptancePage({
    super.key,
    required this.email,
    required this.token,
    required this.crewBackend,
    required this.onFinished,
  });

  final String email;
  final String token;
  final CrewBackend crewBackend;
  final VoidCallback onFinished;

  @override
  State<InviteAcceptancePage> createState() => _InviteAcceptancePageState();
}

class _InviteAcceptancePageState extends State<InviteAcceptancePage> {
  bool _accepting = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.crewBackend.acceptInvite(widget.token);
      if (mounted) widget.onFinished();
    } catch (error) {
      if (mounted) {
        setState(() {
          _accepting = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrutalShadow(
                    fillColor: context.mint,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 26,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: context.surface,
                              border: Border.all(
                                color: context.ink,
                                width: KeepUpMetrics.border,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: HugeIcon(
                              icon: HugeIconsStrokeRounded.userAdd01,
                              color: context.ink,
                              size: 40,
                              strokeWidth: 2.2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'JOIN THE CREW.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 37,
                              height: .95,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'This invitation was sent to ${widget.email}. Accept it to join the crew and start the next weekly loop together.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 16,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.errorInk,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  BrutalButton(
                    label: 'ACCEPT INVITE',
                    icon: HugeIconsStrokeRounded.tick02,
                    color: context.coral,
                    isLoading: _accepting,
                    onPressed: _accept,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _accepting ? null : widget.onFinished,
                    child: Text(
                      'NOT NOW',
                      style: TextStyle(
                        color: context.ink,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error.toString();
  for (final known in [
    'Invite is invalid or has already been used',
    'Invite has expired',
    'Sign in with the email address that received this invite',
    'You already belong to a crew',
  ]) {
    if (message.contains(known)) return known;
  }
  return 'Could not accept this invitation. Please ask the owner to resend it.';
}

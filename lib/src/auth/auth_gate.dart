import '../onboarding/onboarding_gate.dart';
import '../home/home_backend.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../goals/goals_backend.dart';

import '../crew/crew_backend.dart';
import '../home/home_page.dart';
import '../invites/invite_acceptance_page.dart';
import '../invites/invite_links.dart';
import 'auth_backend.dart';
import 'auth_page.dart';
import 'password_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authBackend,
    required this.crewBackend,
    this.goalsBackend = const MissingGoalsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    required this.inviteLinkSource,
  });

  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final GoalsBackend goalsBackend;
  final HomeBackend homeBackend;
  final InviteLinkSource inviteLinkSource;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingInviteToken;

  @override
  void initState() {
    super.initState();
    _pendingInviteToken = inviteTokenFromUri(Uri.base);
    _linkSubscription = widget.inviteLinkSource.links.listen(_receiveLink);
    _loadInitialLink();
  }

  Future<void> _loadInitialLink() async {
    final uri = await widget.inviteLinkSource.getInitialLink();
    if (mounted) _receiveLink(uri);
  }

  void _receiveLink(Uri? uri) {
    final token = inviteTokenFromUri(uri);
    if (token == null || token == _pendingInviteToken) return;
    setState(() => _pendingInviteToken = token);
  }

  void _clearInvite() => setState(() => _pendingInviteToken = null);

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: widget.authBackend.authStateChanges,
      initialData: widget.authBackend.currentUser,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
          return AuthPage(
            authBackend: widget.authBackend,
            pendingInviteToken: _pendingInviteToken,
            initialError: 'This sign-in link could not be opened. It may be expired or already used. Request a new email and try again.',
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return AuthPage(
            authBackend: widget.authBackend,
            pendingInviteToken: _pendingInviteToken,
          );
        }
        if (user.passwordRecoveryRequired) {
          // Email links can arrive while the request-email route is still open.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
          return PasswordPage(
            key: ValueKey('recovery:${user.id}'),
            backend: widget.authBackend,
            recovery: true,
          );
        }
        return OnboardingGate(
          key: ValueKey(user.id.isEmpty ? user.email : user.id),
          user: user,
          backend: widget.authBackend,
          // Received invitations remain available in Crews → Invites after onboarding.
          onCompleted: _clearInvite,
          builder: (profile) {
            final inviteToken = _pendingInviteToken;
            if (inviteToken != null) {
              return InviteAcceptancePage(
                email: user.email,
                token: inviteToken,
                crewBackend: widget.crewBackend,
                onFinished: _clearInvite,
              );
            }
            return HomePage(
              user: profile,
              authBackend: widget.authBackend,
              crewBackend: widget.crewBackend,
              goalsBackend: widget.goalsBackend,
              homeBackend: widget.homeBackend,
            );
          },
        );
      },
    );
  }
}

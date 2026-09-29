import '../home/photo_check_in_page.dart';
import '../onboarding/onboarding_gate.dart';
import '../home/home_backend.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../pacts/pacts_backend.dart';

import '../crew/crew_backend.dart';
import '../crew/crew_selection_store.dart';
import '../home/story_seen_store.dart';
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
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.captureCheckInPhoto,
    this.crewSelectionStore,
    this.storySeenStore,
    required this.inviteLinkSource,
  });

  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final CheckInPhotoCapture? captureCheckInPhoto;
  final CrewSelectionStore? crewSelectionStore;
  final StorySeenStore? storySeenStore;
  final InviteLinkSource inviteLinkSource;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingInviteToken;
  String? _joinedCrewId;
  String? _joinedUser;

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
            // The auth stream errors when an email link (sign-in, recovery,
            // confirmation) fails to open, which Supabase reports as an
            // AuthException. Anything else on the stream is not a link, and
            // used to be reported as an expired email, which sent people off
            // to request a new one for a problem logging in would fix.
            initialError:
                snapshot.error is AuthException || _pendingInviteToken != null
                ? 'This sign-in link could not be opened. It may be expired or already used. Request a new email and try again.'
                : 'Could not confirm your sign-in. Please log in again.',
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _joinedUser = null;
          _joinedCrewId = null;
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
          // The token outlives onboarding on purpose. Retiring it here left a
          // new arrival from a share link with nothing to accept: the Crews
          // inbox lists public.crew_invites, and a share-link token is not
          // one of those. It goes when the acceptance page is finished with.
          builder: (profile) {
            final inviteToken = _pendingInviteToken;
            if (inviteToken != null) {
              return InviteAcceptancePage(
                email: user.email,
                token: inviteToken,
                crewBackend: widget.crewBackend,
                onFinished: _clearInvite,
                onAccepted: (crewId) {
                  _joinedCrewId = crewId;
                  _joinedUser = user.id;
                },
              );
            }
            return HomePage(
              crewSelectionStore: widget.crewSelectionStore,
              storySeenStore: widget.storySeenStore,
              initialCrewId: _joinedUser == user.id ? _joinedCrewId : null,
              user: profile,
              authBackend: widget.authBackend,
              crewBackend: widget.crewBackend,
              pactsBackend: widget.pactsBackend,
              homeBackend: widget.homeBackend,
              captureCheckInPhoto: widget.captureCheckInPhoto,
            );
          },
        );
      },
    );
  }
}

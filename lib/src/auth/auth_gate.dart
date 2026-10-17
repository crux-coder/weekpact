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
import '../onboarding/crew_start_page.dart';
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
  CrewInvitePreview? _invitePreview;
  String? _joinedCrewId;
  String? _joinedUser;

  /// The account that answered the crew question on this run. Saving that
  /// answer is best effort: Home opens either way, and a save that failed
  /// asks the question again on the next launch rather than never.
  String? _finishedCrewStep;

  /// Whether an account has been signed in on this run. A phone that logs out
  /// is handed the log-in form, not the two doors a new phone gets.
  bool _hadSession = false;

  @override
  void initState() {
    super.initState();
    _receiveToken(inviteTokenFromUri(Uri.base));
    _linkSubscription = widget.inviteLinkSource.links.listen(_receiveLink);
    _loadInitialLink();
  }

  Future<void> _loadInitialLink() async {
    final uri = await widget.inviteLinkSource.getInitialLink();
    if (mounted) _receiveLink(uri);
  }

  void _receiveLink(Uri? uri) => _receiveToken(inviteTokenFromUri(uri));

  /// A token from anywhere: the launch URL, a link opened while running, or
  /// one pasted into the front door or the fork. An invitation answers the
  /// fork's question, so a fresh account with a token goes to the invite.
  void _receiveToken(String? token) {
    if (token == null || token == _pendingInviteToken) return;
    setState(() {
      _pendingInviteToken = token;
      _invitePreview = null;
    });
    unawaited(_loadPreview(token));
  }

  /// What the invitation may say about its crew, for the pages before the
  /// join. Decoration only: a preview that fails leaves them saying what they
  /// said before, because the invitation is still good.
  Future<void> _loadPreview(String token) async {
    try {
      final preview = await widget.crewBackend.previewInvite(token);
      if (mounted && token == _pendingInviteToken && preview != null) {
        setState(() => _invitePreview = preview);
      }
    } catch (_) {
      /* The invitation stands whether or not it can introduce itself. */
    }
  }

  /// The invitation has been answered, accepted or declined. Either way it
  /// answered the fork's question too: a member has Home, and somebody who
  /// declined is offered the same choices by Home's empty state.
  void _clearInvite() => setState(() {
    _pendingInviteToken = null;
    _invitePreview = null;
  });

  /// The crew question is answered, by setup or by an invitation.
  void _finishCrewStep(AuthUser user) {
    if (user.onboardingStep != OnboardingStep.crew) return;
    setState(() => _finishedCrewStep = user.id);
    unawaited(
      widget.authBackend
          .advanceOnboarding(OnboardingStep.done)
          .catchError((Object _) {}),
    );
  }

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
            invitePreview: _invitePreview,
            onInviteToken: _receiveToken,
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
            invitePreview: _invitePreview,
            onInviteToken: _receiveToken,
            returning: _hadSession,
          );
        }
        _hadSession = true;
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
        if (!user.profileLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return OnboardingGate(
          key: ValueKey(user.id.isEmpty ? user.email : user.id),
          user: user,
          backend: widget.authBackend,
          joiningCrewName: _invitePreview?.crewName,
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
                onFinished: () {
                  _clearInvite();
                  _finishCrewStep(profile);
                },
                onAccepted: (crewId) {
                  _joinedCrewId = crewId;
                  _joinedUser = user.id;
                },
              );
            }
            // Saved, so a launch between the profile form and this question
            // comes back to the question instead of an empty Home.
            if (profile.onboardingStep == OnboardingStep.crew &&
                _finishedCrewStep != user.id) {
              return CrewStartPage(
                crewBackend: widget.crewBackend,
                pactsBackend: widget.pactsBackend,
                homeBackend: widget.homeBackend,
                userId: user.id,
                firstName: profile.firstName,
                captureCheckInPhoto: widget.captureCheckInPhoto,
                onInviteToken: _receiveToken,
                onDone: () => _finishCrewStep(profile),
              );
            }
            return HomePage(
              onInviteToken: _receiveToken,
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

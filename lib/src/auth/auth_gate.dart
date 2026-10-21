import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../chat/chat_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_selection_store.dart';
import '../crew/crew_sharing.dart';
import '../crew/device_timezone.dart';
import '../home/home_backend.dart';
import '../home/home_page.dart';
import '../home/photo_check_in_page.dart';
import '../home/story_seen_store.dart';
import '../invites/invite_acceptance_page.dart';
import '../invites/invite_links.dart';
import '../onboarding/onboarding_draft.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/setup_pages.dart';
import '../pacts/pacts_backend.dart';
import '../subscriptions/pro_upgrade.dart';
import '../updates/update_check.dart';
import '../updates/update_prompt.dart';
import 'auth_backend.dart';
import 'password_page.dart';

/// How far a newly signed-in account is through turning its draft into a
/// crew, and the two screens that follow.
enum _Setup { idle, committing, failed, bringPeople, checkIn }

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authBackend,
    required this.crewBackend,
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.chatBackend = const MissingChatBackend(),
    this.captureCheckInPhoto,
    this.crewSelectionStore,
    this.storySeenStore,
    this.onboardingDraftStore,
    required this.inviteLinkSource,
    this.updates,
  });

  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final ChatBackend chatBackend;
  final CheckInPhotoCapture? captureCheckInPhoto;
  final CrewSelectionStore? crewSelectionStore;
  final StorySeenStore? storySeenStore;
  final OnboardingDraftStore? onboardingDraftStore;
  final InviteLinkSource inviteLinkSource;

  /// Offers a newer release once Home is showing. Null never offers one.
  final UpdateCheck? updates;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final OnboardingDraftStore _drafts =
      widget.onboardingDraftStore ?? OnboardingDraftStore.memory();
  StreamSubscription<Uri>? _linkSubscription;

  InviteRef? _invite;
  CrewInvitePreview? _invitePreview;
  bool _previewMissing = false;
  bool _previewLoading = false;

  /// Set when somebody tapped Join before signing in: the switch on that
  /// screen. The join then happens without asking again.
  bool? _joinIntent;

  String? _joinedCrewId;
  String? _joinedUser;

  /// Whether an account has been signed in on this run. A phone that logs out
  /// is handed Log in, not the front door a new phone gets.
  bool _hadSession = false;

  _Setup _setup = _Setup.idle;
  String? _setupUser;
  String? _setupError;
  CrewDetails? _newCrew;
  CrewPact? _newPact;

  /// Accounts whose onboarding step has been moved to done on this run, so it
  /// is written once rather than on every rebuild.
  final _advanced = <String>{};

  @override
  void initState() {
    super.initState();
    _receiveInvite(inviteFromUri(Uri.base));
    _linkSubscription = widget.inviteLinkSource.links.listen(_receiveLink);
    _loadInitialLink();
  }

  Future<void> _loadInitialLink() async {
    final uri = await widget.inviteLinkSource.getInitialLink();
    if (mounted) _receiveLink(uri);
  }

  void _receiveLink(Uri? uri) => _receiveInvite(inviteFromUri(uri));

  /// An invite from anywhere: the launch URL, a link opened while running,
  /// or a code typed in. It answers the "new crew or not" question, so it
  /// takes precedence over a half-made draft.
  void _receiveInvite(InviteRef? invite) {
    if (invite == null || invite == _invite) return;
    setState(() {
      _invite = invite;
      _invitePreview = null;
      _previewMissing = false;
      _previewLoading = true;
    });
    unawaited(_loadPreview(invite));
  }

  Future<void> _loadPreview(InviteRef invite) async {
    try {
      final preview = await widget.crewBackend.previewInvite(
        invite.code,
        from: invite.from,
      );
      if (!mounted || invite != _invite) return;
      setState(() {
        _invitePreview = preview;
        _previewMissing = preview == null;
      });
    } catch (_) {
      // A preview that cannot load leaves the invite standing: the join will
      // say whether the code is good.
    } finally {
      if (mounted && invite == _invite) {
        setState(() => _previewLoading = false);
      }
    }
  }

  void _clearInvite() => setState(() {
    _invite = null;
    _invitePreview = null;
    _previewMissing = false;
    _previewLoading = false;
    _joinIntent = null;
  });

  void _joined(String userId, String crewId) {
    _joinedCrewId = crewId;
    _joinedUser = userId;
    // Joining somebody else's crew answers the setup a draft was for.
    unawaited(_drafts.clear());
    _clearInvite();
  }

  /// The draft becomes a crew with its first pact. Safe to retry: the crew id
  /// is saved before the pact is added, and an existing pact is reused.
  Future<void> _commitDraft(AuthUser user) async {
    final draft = _drafts.read();
    if (draft == null || !draft.complete) return;
    setState(() {
      _setup = _Setup.committing;
      _setupUser = user.id;
      _setupError = null;
    });
    try {
      CrewDetails? crew;
      var crewId = draft.crewId;
      if (crewId != null) {
        crew = await widget.crewBackend.fetchCrew(crewId: crewId);
      }
      if (crew == null) {
        crew = await widget.crewBackend.createCrew(
          name: draft.crewName!.trim(),
          timezone: await deviceTimezone(),
        );
        crewId = crew.id;
        await _drafts.save(draft.copyWith(crewId: crewId));
      }
      final pacts = await widget.pactsBackend.fetchPacts(crew.id);
      final days = draft.pactDays!.clamp(1, 7);
      final pact = pacts.isNotEmpty
          ? pacts.first
          : await widget.pactsBackend.addPact(
              crewId: crew.id,
              title: draft.pactTitle!.trim(),
              iconKey: draft.pactIcon!,
              frequency: days >= 7 ? PactFrequency.daily : PactFrequency.weekly,
              daysPerWeek: days,
              photoRequired: false,
            );
      await _drafts.clear();
      _advance(user);
      if (!mounted) return;
      setState(() {
        _newCrew = crew;
        _newPact = pact;
        _joinedCrewId = crew!.id;
        _joinedUser = user.id;
        _setup = _Setup.bringPeople;
      });
    } catch (error) {
      if (!mounted) return;
      if (isCrewLimitError(error)) {
        // An existing account, already in a crew, that went through setup
        // before logging in. Its crew stays; the draft goes.
        await _drafts.clear();
        if (!mounted) return;
        setState(() => _setup = _Setup.idle);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Welcome back. You already have a crew, so we took you to it.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _setup = _Setup.failed;
        _setupError =
            'Check your connection and try again. Your answers are still here.';
      });
    }
  }

  /// Records that the account is through onboarding. Best effort: a failed
  /// write only means it is tried again on the next launch.
  void _advance(AuthUser user) {
    if (user.onboardingStep == OnboardingStep.done) return;
    if (user.firstName.trim().isEmpty || !_advanced.add(user.id)) return;
    unawaited(
      widget.authBackend
          .advanceOnboarding(OnboardingStep.done)
          .catchError((Object _) {}),
    );
  }

  void _finishSetup() => setState(() {
    _setup = _Setup.idle;
    _newCrew = null;
    _newPact = null;
  });

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Widget _signedOut({String? error}) => OnboardingFlow(
    key: const ValueKey('onboarding'),
    authBackend: widget.authBackend,
    draftStore: _drafts,
    invite: _invite,
    invitePreview: _invitePreview,
    previewMissing: _previewMissing,
    previewLoading: _previewLoading,
    onInvite: _receiveInvite,
    onClearInvite: _clearInvite,
    onJoinIntent: (notify) => _joinIntent = notify,
    returning: _hadSession,
    initialError: error,
  );

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
          // The auth stream errors when an email link (recovery) fails to
          // open, which Supabase reports as an AuthException.
          return _signedOut(
            error: snapshot.error is AuthException
                ? 'This link could not be opened. It may be expired or '
                      'already used. Request a new email and try again.'
                : 'Could not confirm your sign-in. Please log in again.',
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _joinedUser = null;
          _joinedCrewId = null;
          if (_setup != _Setup.idle) {
            _setup = _Setup.idle;
            _newCrew = null;
            _newPact = null;
          }
          return _signedOut();
        }
        _hadSession = true;
        if (user.passwordRecoveryRequired) {
          // Recovery links can arrive while the reset-request page is open.
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
        // Apple lets people keep their name to themselves; the crew still
        // needs something to call them.
        if (user.firstName.trim().isEmpty) {
          return NamePage(
            key: ValueKey('name:${user.id}'),
            backend: widget.authBackend,
            user: user,
            crewName: _invitePreview?.crewName,
            onSaved: (_) => setState(() {}),
          );
        }

        final invite = _invite;
        if (invite != null) {
          return InviteAcceptancePage(
            key: ValueKey('invite:${invite.code}'),
            crewBackend: widget.crewBackend,
            invite: invite,
            preview: _invitePreview,
            previewMissing: _previewMissing,
            autoJoin: _joinIntent != null,
            notify: _joinIntent ?? true,
            onJoined: (crewId) {
              _advance(user);
              _joined(user.id, crewId);
            },
            onDismiss: _clearInvite,
            onNewInvite: _receiveInvite,
          );
        }

        if (_setup == _Setup.idle || _setupUser != user.id) {
          final draft = _drafts.read();
          if (draft != null && draft.complete) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _setup != _Setup.committing) _commitDraft(user);
            });
            return const SetupStatusPage();
          }
        } else {
          switch (_setup) {
            case _Setup.committing:
              return const SetupStatusPage();
            case _Setup.failed:
              return SetupStatusPage(
                error: _setupError,
                onRetry: () => _commitDraft(user),
                onSkip: () {
                  unawaited(_drafts.clear());
                  setState(() => _setup = _Setup.idle);
                },
              );
            case _Setup.bringPeople:
              final crew = _newCrew!;
              final backend = widget.crewBackend;
              return BringPeoplePage(
                crew: crew,
                sharing: backend is CrewSharingBackend
                    ? backend as CrewSharingBackend
                    : null,
                inviterId: user.id,
                onDone: () => setState(() => _setup = _Setup.checkIn),
              );
            case _Setup.checkIn:
              return FirstCheckInPage(
                crew: _newCrew!,
                pact: _newPact!,
                homeBackend: widget.homeBackend,
                userId: user.id,
                firstName: user.firstName,
                onDone: _finishSetup,
              );
            case _Setup.idle:
              break;
          }
        }

        _advance(user);
        final home = HomePage(
          onInviteCode: _receiveInvite,
          crewSelectionStore: widget.crewSelectionStore,
          storySeenStore: widget.storySeenStore,
          initialCrewId: _joinedUser == user.id ? _joinedCrewId : null,
          user: user,
          authBackend: widget.authBackend,
          crewBackend: widget.crewBackend,
          pactsBackend: widget.pactsBackend,
          homeBackend: widget.homeBackend,
          chatBackend: widget.chatBackend,
          captureCheckInPhoto: widget.captureCheckInPhoto,
        );
        final updates = widget.updates;
        return updates == null
            ? home
            : UpdatePrompt.optional(updates: updates, child: home);
      },
    );
  }
}

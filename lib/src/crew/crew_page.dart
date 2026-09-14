import 'crew_sharing.dart';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'crew_invites_pane.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';
import '../home/home_backend.dart';
import 'crew_people_grid.dart';

const _appTimezone = String.fromEnvironment(
  'APP_TIMEZONE',
  defaultValue: 'UTC',
);

class CrewPage extends StatefulWidget {
  const CrewPage({
    super.key,
    required this.backend,
    required this.currentUserEmail,
    this.profileBackend,
    this.active = true,
    this.onInviteAccepted,
    this.onCrewLeft,
    this.onCrewCreated,
  });

  final HomeBackend? profileBackend;
  final bool active;
  final CrewBackend backend;
  final String currentUserEmail;
  final VoidCallback? onInviteAccepted;
  final VoidCallback? onCrewLeft;
  final ValueChanged<CrewDetails>? onCrewCreated;

  @override
  State<CrewPage> createState() => _CrewPageState();
}

class _CrewPageState extends State<CrewPage> with WidgetsBindingObserver {
  bool _invitesOpen = false;
  int _receivedInviteCount = 0;
  final _invitesKey = GlobalKey<CrewInvitesPaneState>();
  final _crewNameController = TextEditingController();
  final _createFormKey = GlobalKey<FormState>();

  CrewDetails? _crew;
  String? _profileCrewId;
  Map<String, WeekMember> _memberProfiles = {};
  bool _loading = false;
  Future<void>? _crewLoad;
  bool _hasLoaded = false;
  bool _creating = false;
  bool _changingMembership = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCrew();
    _loadInviteCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _crewNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCrew() =>
      _crewLoad ??= _fetchCrew().whenComplete(() => _crewLoad = null);

  Future<void> _fetchCrew() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final crew = await widget.backend.fetchCrew();
      if (crew?.id != _profileCrewId) {
        _memberProfiles = {};
        _profileCrewId = crew?.id;
      }
      if (crew != null && widget.profileBackend != null) {
        try {
          final week = await widget.profileBackend!.fetchWeek(crew.id);
          if (!mounted) return;
          _memberProfiles = {
            for (final member in week.members) member.id: member,
          };
        } catch (_) {
          if (mounted) {
            setState(
              () => _error =
                  'Could not refresh member profiles. Pull down to retry.',
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _crew = crew;
          _hasLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCrew() async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final crew = await widget.backend.createCrew(
        name: _crewNameController.text,
        timezone: _appTimezone,
      );
      if (mounted) {
        setState(() => _crew = crew);
        widget.onCrewCreated?.call(crew);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _changeMembership({CrewMember? member}) async {
    final crew = _crew;
    if (crew == null || _changingMembership) return;
    final leaving = member == null;
    final successors = crew.members
        .where((m) => m.userId != crew.ownerId)
        .toList();
    if (leaving && crew.isOwner && successors.isEmpty) {
      await showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('You’re the only member'),
          content: const Text(
            'Invite another member before leaving, then choose them as the new owner.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    String? successorId;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(leaving ? 'Leave crew?' : 'Remove member?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leaving
                    ? 'You’ll lose access to ${crew.name}. You’ll need a new invitation to rejoin.'
                    : 'Remove ${member.email} from ${crew.name}? They’ll lose access and need a new invitation to rejoin.',
              ),
              if (leaving && crew.isOwner) ...[
                const SizedBox(height: 16),
                const Text('Choose the new owner:'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  hint: const Text('Select a member'),
                  items: successors
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.userId,
                          child: Text(m.email, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => successorId = value),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: leaving && crew.isOwner && successorId == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(leaving ? 'LEAVE' : 'REMOVE'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || _changingMembership) return;
    setState(() {
      _changingMembership = true;
      _error = null;
    });
    try {
      if (leaving) {
        await widget.backend.leaveCrew(
          crewId: crew.id,
          successorId: successorId,
        );
      } else {
        await widget.backend.removeMember(
          crewId: crew.id,
          userId: member.userId,
        );
      }
      // Discard any fetch begun before the membership mutation.
      await _crewLoad;
      if (!mounted) return;
      if (leaving) setState(() => _crew = null);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(leaving ? 'You left the crew.' : 'Member removed.'),
        ),
      );
      if (leaving) widget.onCrewLeft?.call();
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _changingMembership = false);
    }
  }

  Future<void> _openInviteDrawer() async {
    final crew = _crew;
    if (crew == null || !crew.isOwner) return;
    final updated = await showAppSheet<CrewDetails>(
      context: context,
      builder: (context) => _InviteDrawer(
        crew: crew,
        backend: widget.backend,
        currentUserEmail: widget.currentUserEmail,
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _crew = updated;
      _error = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Invite sent.')));
  }

  @override
  void didUpdateWidget(covariant CrewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.active && !oldWidget.active) ||
        widget.profileBackend != oldWidget.profileBackend) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadCrew(),
      _loadInviteCount(),
      if (_invitesKey.currentState != null) _invitesKey.currentState!.refresh(),
    ]);
  }

  Future<void> _joinedCrew() async {
    // A refresh started before acceptance may still contain the old membership.
    await _crewLoad;
    if (!mounted) return;
    await _loadCrew();
    if (!mounted) return;
    if (_invitesOpen && _invitesKey.currentContext != null) {
      Navigator.of(_invitesKey.currentContext!).pop();
    }
    widget.onInviteAccepted?.call();
  }

  Widget _crewCard({required Widget child}) =>
      AppSectionCard(title: 'Your crew', builder: (_) => child);

  Future<void> _loadInviteCount() async {
    try {
      final invites = await widget.backend.fetchReceivedInvites();
      if (mounted) setState(() => _receivedInviteCount = invites.length);
    } catch (_) {
      // Keep the last badge state; the drawer provides retry and error feedback.
    }
  }

  Future<void> _openInvites() async {
    setState(() => _invitesOpen = true);
    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateDrawer) => AppSheet(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Invites',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close invites',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if ((_crew?.isOwner ?? false) &&
                  _crew!.pendingInvites.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Sent',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                for (final invite in _crew!.pendingInvites)
                  _InviteRow(
                    invite: invite,
                    onRevoke: () async {
                      await _revokeInvite(invite);
                      if (sheetContext.mounted) updateDrawer(() {});
                    },
                  ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: context.errorInk)),
              ],
              CrewInvitesPane(
                key: _invitesKey,
                backend: widget.backend,
                alreadyInCrew: _crew != null,
                onAccepted: _joinedCrew,
                showEmptyState: !(_crew?.pendingInvites.isNotEmpty ?? false),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _invitesOpen = false);
    await _loadInviteCount();
  }

  Future<void> _revokeInvite(CrewInvite invite) async {
    final crew = _crew;
    if (crew == null) return;
    try {
      final updated = await widget.backend.revokeInvite(
        crewId: crew.id,
        inviteId: invite.id,
      );
      if (mounted) setState(() => _crew = updated);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    }
  }

  String? _validateCrewName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'Use at least 2 characters';
    if (name.length > 60) return 'Use no more than 60 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      header: Row(
        children: [
          const Expanded(child: PageHeading('Crews')),
          IconButton(
            tooltip: 'Invites',
            onPressed: _invitesOpen ? null : _openInvites,
            icon: Badge(
              key: const ValueKey('crew-invites-badge'),
              isLabelVisible:
                  _receivedInviteCount > 0 ||
                  (_crew?.pendingInvites.isNotEmpty ?? false),
              backgroundColor: WeekPactColors.softYellow,
              child: const Icon(Icons.inbox_outlined),
            ),
          ),
        ],
      ),
      loading: !_hasLoaded && _loading,
      skeleton: const _CrewSkeleton(),
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_crew != null) ...[
            _buildCrewState(context, _crew!),
            if (_crew!.isOwner && widget.onCrewCreated != null)
              TextButton.icon(
                onPressed: () => widget.onCrewCreated!(_crew!),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Setup guide'),
              ),
            if (_crew!.isOwner && widget.backend is CrewSharingBackend) ...[
              const SizedBox(height: 16),
              AppSurface(
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(18),
                  child: CrewShareControls(
                    key: ValueKey(_crew!.id),
                    backend: widget.backend as CrewSharingBackend,
                    crewId: _crew!.id,
                  ),
                ),
              ),
            ],
          ] else if (_hasLoaded)
            AppSurfaceTheme(builder: (context) => _buildCreateState(context)),
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
            if (!_hasLoaded) ...[
              const SizedBox(height: 12),
              Text(
                'Pull down to try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCreateState(BuildContext context) {
    return Form(
      key: _createFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _crewCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Start your crew',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 20),
                  AppTextField(
                    label: 'CREW NAME',
                    hint: 'Early Birds',
                    controller: _crewNameController,
                    validator: _validateCrewName,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'WEEK STARTS MONDAY',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: context.mint,
                      border: Border.all(
                        color: context.border,
                        width: WeekPactMetrics.border,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: HugeIconsStrokeRounded.globe02,
                          color: context.ink,
                          size: 22,
                          strokeWidth: 2,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _appTimezone,
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  AppButton(
                    label: 'CREATE CREW',
                    icon: HugeIconsStrokeRounded.userGroup02,

                    isLoading: _creating,
                    onPressed: _createCrew,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  CrewMember _withProfile(CrewMember member) {
    final profile = _memberProfiles[member.userId];
    return CrewMember(
      userId: member.userId,
      email: member.email,
      role: member.role,
      joinedAt: member.joinedAt,
      displayName: profile?.displayName.trim().isNotEmpty == true
          ? profile!.displayName
          : member.displayName,
      avatarUrl: profile?.avatarUrl ?? member.avatarUrl,
    );
  }

  Widget _buildCrewState(BuildContext context, CrewDetails crew) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurface(
          builder: (context) => Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.people_outline, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    crew.name,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'YOUR PEOPLE · ${crew.members.length}',
          style: TextStyle(
            color: context.muted,
            fontSize: 14,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        CrewPeopleGrid(
          children: [
            for (var i = 0; i < crew.members.length; i++)
              CrewPersonCard(
                key: ValueKey(crew.members[i].userId),
                member: _withProfile(crew.members[i]),
                isCurrentUser:
                    crew.members[i].email.toLowerCase() ==
                    widget.currentUserEmail.toLowerCase(),
                color:
                    crew.members[i].email.toLowerCase() ==
                        widget.currentUserEmail.toLowerCase()
                    ? WeekPactColors.mintGreen
                    : (i.isEven
                          ? WeekPactColors.softYellow
                          : WeekPactColors.cream),
                onRemove:
                    crew.isOwner &&
                        !crew.members[i].isOwner &&
                        !_changingMembership
                    ? () => _changeMembership(member: crew.members[i])
                    : null,
              ),
            if (crew.isOwner)
              CrewInviteTile(
                onPressed: _changingMembership ? null : _openInviteDrawer,
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _changingMembership ? null : () => _changeMembership(),
          icon: const Icon(Icons.logout, size: 20),
          label: const Text('LEAVE CREW'),
          style: TextButton.styleFrom(
            foregroundColor: context.ink,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

class _InviteDrawer extends StatefulWidget {
  const _InviteDrawer({
    required this.crew,
    required this.backend,
    required this.currentUserEmail,
  });
  final CrewDetails crew;
  final CrewBackend backend;
  final String currentUserEmail;

  @override
  State<_InviteDrawer> createState() => _InviteDrawerState();
}

class _InviteDrawerState extends State<_InviteDrawer> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated = await widget.backend.inviteMember(
        crewId: widget.crew.id,
        email: _controller.text.trim(),
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: AppSheet(
        builder: (context) => Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'INVITE TO YOUR CREW',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close invite',
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.crew.name,
                style: TextStyle(color: context.muted, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Text(
                'Send an email invitation. They’ll sign in or create an account to join your crew.',
                style: TextStyle(color: context.ink, height: 1.4),
              ),
              const SizedBox(height: 22),
              AppTextField(
                label: 'EMAIL ADDRESS',
                hint: 'friend@example.com',
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'Enter a valid email';
                  }
                  if (email.toLowerCase() ==
                      widget.currentUserEmail.toLowerCase()) {
                    return 'You are already in this crew';
                  }
                  return null;
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: context.errorInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AppButton(
                label: 'SEND INVITE',
                icon: HugeIconsStrokeRounded.mailSend01,

                isLoading: _sending,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reserves the same square tiles as the loaded people grid.
class _CrewSkeleton extends StatelessWidget {
  const _CrewSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading crews',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            builder: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonBar(height: 30),
            ),
          ),
          const SizedBox(height: 22),
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBar(width: 120, height: 16),
          ),
          const SizedBox(height: 12),
          CrewPeopleGrid(
            children: [
              for (var i = 0; i < 4; i++)
                AppSurface(
                  fillColor: i == 0
                      ? WeekPactColors.mintGreen
                      : WeekPactColors.cream,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: SkeletonBar(height: 100, radius: 100),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        SkeletonBar(height: 15),
                        SizedBox(height: 8),
                        SkeletonBar(width: 60, height: 10),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, required this.onRevoke});
  final CrewInvite invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final remaining = invite.expiresAt.difference(DateTime.now()).inDays + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'EXPIRES IN $remaining ${remaining == 1 ? 'DAY' : 'DAYS'}',
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRevoke,
            style: TextButton.styleFrom(
              foregroundColor: context.ink,
              backgroundColor: context.pink,
              side: BorderSide(
                color: context.border,
                width: WeekPactMetrics.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            child: const Text(
              'REVOKE',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

String _messageFor(Object error) {
  final message = error.toString();
  if (message.contains('already belong to a crew') ||
      message.contains('crew_members_one_crew_per_user')) {
    return 'You already belong to a crew.';
  }
  if (message.contains('already in this crew')) {
    return 'That person is already in this crew.';
  }
  if (message.contains('Invite email is not configured')) {
    return 'Email invites are not configured yet.';
  }
  if (message.contains('Supabase is not configured')) {
    return 'Connect Supabase before creating a crew.';
  }
  if (message.contains('no longer in the crew') ||
      message.contains('new owner must belong')) {
    return 'Membership changed. Refresh the crew and try again.';
  }
  if (message.contains('Only the owner') ||
      message.contains('Choose another member')) {
    return 'Only the current owner can manage members. Choose a new owner before leaving.';
  }
  return 'Something went wrong. Please try again.';
}

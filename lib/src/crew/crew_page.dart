import 'crew_page_layout.dart';
import '../pacts/pacts_backend.dart';
import 'crew_switcher.dart';
import 'crew_sharing.dart';

import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'crew_invites_pane.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';
import '../home/home_backend.dart';
import 'crew_roster.dart';
import '../subscriptions/pro_upgrade.dart';
import '../subscriptions/subscription_scope.dart';

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
    this.selectedCrewId,
    this.onCrewSelected,
    this.onInviteAccepted,
    this.onCrewLeft,
    this.onCrewCreated,
  });

  final HomeBackend? profileBackend;
  final String? selectedCrewId;
  final ValueChanged<String>? onCrewSelected;
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
  List<PactCrew> _crews = [];
  String? _selectedCrewId;
  bool _showCreate = false;
  int _request = 0;
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

  Future<void> _loadCrew() => _crewLoad = _fetchCrew();

  Future<void> _fetchCrew() async {
    final request = ++_request;
    if (mounted && request == _request) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final crews = await widget.backend.fetchCrews();
      if (!mounted || request != _request) return;
      final wanted = _selectedCrewId ?? widget.selectedCrewId ?? _crew?.id;
      final selected =
          crews.where((c) => c.id == wanted).firstOrNull ?? crews.firstOrNull;
      final crew = await widget.backend.fetchCrew(crewId: selected?.id);
      if (!mounted || request != _request) return;
      _crews = crews;
      if (crew?.id != _profileCrewId) {
        _memberProfiles = {};
        _profileCrewId = crew?.id;
      }
      if (crew != null && widget.profileBackend != null) {
        try {
          final week = await widget.profileBackend!.fetchWeek(crew.id);
          if (!mounted || request != _request) return;
          _memberProfiles = {
            for (final member in week.members) member.id: member,
          };
        } catch (_) {
          if (mounted && request == _request) {
            setState(
              () => _error =
                  'Could not refresh member profiles. Pull down to retry.',
            );
          }
        }
      }

      if (mounted && request == _request) {
        setState(() {
          _crew = crew;
          _hasLoaded = true;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
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
        setState(() {
          _crew = crew;
          _selectedCrewId = crew.id;
          _showCreate = false;
        });
        _crewNameController.clear();
        widget.onCrewSelected?.call(crew.id);
        await _loadCrew();
        if (!mounted) return;
        widget.onCrewCreated?.call(crew);
      }
    } catch (error) {
      if (!mounted) return;
      // Postgres has the final say: entitlements can lapse between opening the
      // form and submitting it, and the SDK's view can be stale.
      if (isCrewLimitError(error)) {
        if (await showCrewLimitUpgrade(
              context,
              reason: CrewLimitReason.creating,
            ) &&
            mounted) {
          await _createCrew();
          return;
        }
        if (mounted) setState(() => _showCreate = false);
      } else {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Opens the new-crew form, or explains why it cannot be opened. Someone who
  /// upgrades from the dialog lands straight in the form.
  Future<void> _toggleCreate() async {
    if (_showCreate) {
      setState(() => _showCreate = false);
      return;
    }
    if (_crews.isNotEmpty && !context.isPro) {
      final upgraded = await showCrewLimitUpgrade(
        context,
        reason: CrewLimitReason.creating,
      );
      if (!upgraded || !mounted) return;
    }
    setState(() => _showCreate = true);
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
        builder: (context) => const AppDialog(
          icon: HugeIconsStrokeRounded.userGroup02,
          iconColor: WeekPactColors.coolGrey,
          title: 'You’re the only member',
          message:
              'Invite another member before leaving, then choose them as the '
              'new owner.',
          actions: [AppDialogDismiss(label: 'OK')],
        ),
      );
      return;
    }
    String? successorId;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AppDialog(
          icon: leaving
              ? HugeIconsStrokeRounded.logout01
              : HugeIconsStrokeRounded.userMinus01,
          iconColor: WeekPactColors.softCoral,
          title: leaving ? 'Leave crew?' : 'Remove member?',
          message: leaving
              ? 'You’ll lose access to ${crew.name}. You’ll need a new '
                    'invitation to rejoin.'
              : 'Remove ${member.email} from ${crew.name}? They’ll lose access '
                    'and need a new invitation to rejoin.',
          content: leaving && crew.isOwner
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CHOOSE THE NEW OWNER',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppSurface(
                      raised: false,
                      borderRadius: WeekPactMetrics.controlRadius,
                      builder: (context) => DropdownButtonFormField<String>(
                        icon: const AppIcon(
                          icon: HugeIconsStrokeRounded.arrowDown01,
                          size: 20,
                        ),
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(
                          WeekPactMetrics.controlRadius,
                        ),
                        hint: const Text('Select a member'),
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          // The surface owns the fill and the outline.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        items: successors
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.userId,
                                child: Text(
                                  m.email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => successorId = value),
                      ),
                    ),
                  ],
                )
              : null,
          actions: [
            AppButton(
              label: leaving ? 'LEAVE' : 'REMOVE',
              onPressed: leaving && crew.isOwner && successorId == null
                  ? null
                  : () => Navigator.pop(context, true),
            ),
            AppDialogDismiss(
              label: 'CANCEL',
              onPressed: () => Navigator.pop(context, false),
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
      if (leaving) {
        setState(() {
          _crew = null;
          _selectedCrewId = null;
        });
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(leaving ? 'You left the crew.' : 'Member removed.'),
        ),
      );
      if (leaving) {
        if (_crew != null) widget.onCrewSelected?.call(_crew!.id);
        widget.onCrewLeft?.call();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _changingMembership = false);
    }
  }

  Future<void> _openInviteDrawer() async {
    final crew = _crew;
    if (crew == null || !crew.isOwner) return;
    await showAppSheet<void>(
      context: context,
      builder: (context) => _InviteDrawer(crew: crew, backend: widget.backend),
    );
  }

  @override
  void didUpdateWidget(covariant CrewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCrewId != oldWidget.selectedCrewId) {
      _selectedCrewId = widget.selectedCrewId;
    }
    if ((widget.active &&
            (!oldWidget.active ||
                widget.selectedCrewId != oldWidget.selectedCrewId)) ||
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

  Future<void> _joinedCrew(String crewId) async {
    _selectedCrewId = crewId;
    widget.onCrewSelected?.call(crewId);
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
                    icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
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
      header: CrewPageHeading(
        title: 'Crews',
        dotColor: WeekPactColors.coolGrey,
        actions: [
          if (_crew != null)
            IconButton(
              tooltip: _showCreate ? 'Cancel new crew' : 'Create another crew',
              onPressed: _creating || _changingMembership
                  ? null
                  : _toggleCreate,
              icon: AppIcon(
                icon: _showCreate
                    ? HugeIconsStrokeRounded.cancel01
                    : HugeIconsStrokeRounded.add01,
              ),
            ),
          IconButton(
            tooltip: 'Invites',
            onPressed: _invitesOpen ? null : _openInvites,
            icon: Badge(
              key: const ValueKey('crew-invites-badge'),
              isLabelVisible:
                  _receivedInviteCount > 0 ||
                  (_crew?.pendingInvites.isNotEmpty ?? false),
              backgroundColor: WeekPactColors.stone,
              child: const AppIcon(icon: HugeIconsStrokeRounded.inbox),
            ),
          ),
        ],
      ),
      loading: !_hasLoaded && _loading,
      skeleton: const CrewPageSkeleton(),
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_crews.isNotEmpty && !_showCreate) ...[
            CrewSwitcher(
              compact: true,
              crews: _crews,
              loadWeek: widget.profileBackend?.fetchWeek,
              selectedId: _loading
                  ? (_selectedCrewId ?? widget.selectedCrewId ?? _crew?.id)
                  : _crew?.id,
              onSelected: _changingMembership || _loading
                  ? null
                  : (id) {
                      _selectedCrewId = id;
                      widget.onCrewSelected?.call(id);
                      _loadCrew();
                    },
            ),
            const SizedBox(height: 12),
          ],
          if (_loading && !_showCreate && _crew != null)
            const CrewPageSkeleton(showSelector: false)
          else if (_crew != null && !_showCreate) ...[
            _buildCrewState(context, _crew!),
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
                      color: WeekPactColors.stone,
                      border: Border.all(
                        color: context.border,
                        width: WeekPactMetrics.border,
                      ),
                      borderRadius: BorderRadius.circular(
                        WeekPactMetrics.controlRadius,
                      ),
                    ),
                    child: Row(
                      children: [
                        AppIcon(
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
    final members = [for (final member in crew.members) _withProfile(member)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CrewAvatarStack(members: members),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${crew.name.toUpperCase()} · ${crew.members.length} ${crew.members.length == 1 ? 'PERSON' : 'PEOPLE'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.muted,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CrewRoster(
          children: [
            for (var i = 0; i < members.length; i++)
              CrewPersonBand(
                key: ValueKey(members[i].userId),
                member: members[i],
                isCurrentUser: _isCurrentUser(members[i]),
                color: _isCurrentUser(members[i])
                    ? WeekPactColors.coolGrey
                    : WeekPactColors.cream,
                onRemove:
                    crew.isOwner && !members[i].isOwner && !_changingMembership
                    ? () => _changeMembership(member: crew.members[i])
                    : null,
              ),
            if (crew.isOwner)
              CrewInviteBand(
                onPressed: _changingMembership ? null : _openInviteDrawer,
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _changingMembership ? null : () => _changeMembership(),
          icon: const AppIcon(icon: HugeIconsStrokeRounded.logout01, size: 20),
          label: const Text('LEAVE CREW'),
          style: TextButton.styleFrom(
            foregroundColor: context.ink,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  bool _isCurrentUser(CrewMember member) =>
      member.email.toLowerCase() == widget.currentUserEmail.toLowerCase();
}

class _InviteDrawer extends StatelessWidget {
  const _InviteDrawer({required this.crew, required this.backend});

  final CrewDetails crew;
  final CrewBackend backend;

  @override
  Widget build(BuildContext context) => AppSheet(
    builder: (context) => Column(
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
              onPressed: () => Navigator.pop(context),
              icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
            ),
          ],
        ),
        Text(crew.name, style: TextStyle(color: context.muted, fontSize: 16)),
        const SizedBox(height: 20),
        if (backend is CrewSharingBackend)
          CrewShareControls(
            backend: backend as CrewSharingBackend,
            crewId: crew.id,
            showHeading: false,
          )
        else
          const Text(
            'Invitations are unavailable right now. Please try again later.',
          ),
      ],
    ),
  );
}

/// Reserves the same square tiles as the loaded people grid.
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
              shape: WeekPactMetrics.buttonShape,
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

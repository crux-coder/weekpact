import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'crew_invites_pane.dart';
import '../widgets/brutal_widgets.dart';
import '../widgets/brutal_drawer.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';

const _appTimezone = String.fromEnvironment(
  'APP_TIMEZONE',
  defaultValue: 'UTC',
);

class CrewPage extends StatefulWidget {
  const CrewPage({
    super.key,
    required this.backend,
    required this.currentUserEmail,
    this.active = true,
    this.onInviteAccepted,
    this.onCrewLeft,
  });

  final bool active;
  final CrewBackend backend;
  final String currentUserEmail;
  final VoidCallback? onInviteAccepted;
  final VoidCallback? onCrewLeft;

  @override
  State<CrewPage> createState() => _CrewPageState();
}

class _CrewPageState extends State<CrewPage> with WidgetsBindingObserver {
  bool _showInvites = false;
  final _invitesKey = GlobalKey<CrewInvitesPaneState>();
  final _crewNameController = TextEditingController();
  final _createFormKey = GlobalKey<FormState>();

  CrewDetails? _crew;
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
      if (mounted) setState(() => _crew = crew);
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
      await showDialog<void>(
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
    final confirmed = await showDialog<bool>(
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
    final updated = await showBrutalDrawer<CrewDetails>(
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
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadCrew(),
      if (_invitesKey.currentState != null) _invitesKey.currentState!.refresh(),
    ]);
  }

  Future<void> _joinedCrew() async {
    // A refresh started before acceptance may still contain the old membership.
    await _crewLoad;
    if (!mounted) return;
    await _loadCrew();
    if (!mounted) return;
    setState(() => _showInvites = false);
    widget.onInviteAccepted?.call();
  }

  Widget _crewCard({required Widget child}) => BrutalTabbedCard(
    title: 'YOUR CREW',
    tabColor: context.mint,
    tabs: [
      Flexible(
        child: Container(
          decoration: BoxDecoration(
            color: context.shadow,
            border: Border(
              top: BorderSide(
                color: context.border,
                width: WeekPactMetrics.border,
              ),
              left: BorderSide(
                color: context.border,
                width: WeekPactMetrics.border,
              ),
              right: BorderSide(
                color: context.border,
                width: WeekPactMetrics.border,
              ),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: _CrewTab(
                    label: 'YOUR CREW',
                    selected: !_showInvites,
                    isFirst: true,
                    onPressed: () => setState(() => _showInvites = false),
                  ),
                ),
                Container(width: WeekPactMetrics.border, color: context.border),
                Flexible(
                  child: _CrewTab(
                    label: 'INVITES',
                    selected: _showInvites,
                    isFirst: false,
                    onPressed: () => setState(() => _showInvites = true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    child: child,
  );

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
      header: const PageHeading('CREWS.'),
      loading: !_hasLoaded && _loading,
      skeleton: const _CrewSkeleton(),
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showInvites)
            _crewCard(
              child: CrewInvitesPane(
                key: _invitesKey,
                backend: widget.backend,
                alreadyInCrew: _crew != null,
                onAccepted: _joinedCrew,
              ),
            )
          else if (_crew != null)
            _buildCrewState(_crew!)
          else if (_hasLoaded)
            _buildCreateState(),
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

  Widget _buildCreateState() {
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
                    'START YOUR CREW',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 20),
                  BrutalTextField(
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
                  BrutalButton(
                    label: 'CREATE CREW',
                    icon: HugeIconsStrokeRounded.userGroup02,
                    color: context.coral,
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

  Widget _buildCrewState(CrewDetails crew) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _crewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: context.yellow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              crew.name.toUpperCase(),
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 26,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _StatusLabel(
                            text: crew.isOwner ? 'OWNER' : 'MEMBER',
                            color: context.surface,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${crew.members.length} ${crew.members.length == 1 ? 'member' : 'members'} · Showing up together',
                        style: TextStyle(
                          color: context.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(
                color: context.border,
                thickness: WeekPactMetrics.fineBorder,
                height: 2,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
                child: Text(
                  'MEMBERS',
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
              for (var index = 0; index < crew.members.length; index++) ...[
                _MemberRow(
                  member: crew.members[index],
                  onRemove:
                      crew.isOwner &&
                          !crew.members[index].isOwner &&
                          !_changingMembership
                      ? () => _changeMembership(member: crew.members[index])
                      : null,
                  isCurrentUser:
                      crew.members[index].email.toLowerCase() ==
                      widget.currentUserEmail.toLowerCase(),
                ),
                if (index != crew.members.length - 1)
                  Divider(
                    color: context.ink,
                    thickness: WeekPactMetrics.fineBorder,
                    height: 2,
                  ),
              ],
              if (crew.isOwner && crew.pendingInvites.isNotEmpty) ...[
                Divider(
                  color: context.ink,
                  thickness: WeekPactMetrics.fineBorder,
                  height: 2,
                ),
                ColoredBox(
                  color: context.yellow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      'PENDING INVITES',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                ),
                for (
                  var index = 0;
                  index < crew.pendingInvites.length;
                  index++
                ) ...[
                  _InviteRow(
                    invite: crew.pendingInvites[index],
                    onRevoke: () => _revokeInvite(crew.pendingInvites[index]),
                  ),
                  if (index != crew.pendingInvites.length - 1)
                    Divider(
                      color: context.ink,
                      thickness: WeekPactMetrics.fineBorder,
                      height: 2,
                    ),
                ],
              ],
              if (crew.isOwner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 18, 20),
                  child: BrutalButton(
                    label: 'INVITE SOMEONE',
                    icon: HugeIconsStrokeRounded.mailSend01,
                    color: context.coral,
                    onPressed: _changingMembership ? null : _openInviteDrawer,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 18, 16),
                child: BrutalButton(
                  label: 'LEAVE CREW',
                  color: context.surface,
                  isLoading: _changingMembership,
                  onPressed: _changingMembership
                      ? null
                      : () => _changeMembership(),
                ),
              ),
            ],
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
      child: BrutalDrawer(
        child: Form(
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
              BrutalTextField(
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
              BrutalButton(
                label: 'SEND INVITE',
                icon: HugeIconsStrokeRounded.mailSend01,
                color: context.coral,
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

/// Mirrors the grouped crew header and member list without assuming ownership.
class _CrewSkeleton extends StatelessWidget {
  const _CrewSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading crews',
    liveRegion: true,
    child: ExcludeSemantics(
      child: BrutalTabbedCard(
        title: 'YOUR CREW',
        tabColor: context.mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: context.yellow,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: SkeletonBar(height: 26)),
                        SizedBox(width: 32),
                        SkeletonBar(width: 65, height: 26),
                      ],
                    ),
                    SizedBox(height: 12),
                    SkeletonBar(width: 180, height: 14),
                  ],
                ),
              ),
            ),
            Divider(
              color: context.border,
              height: 2,
              thickness: WeekPactMetrics.fineBorder,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
              child: Text(
                'MEMBERS',
                style: TextStyle(
                  color: context.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            for (var index = 0; index < 3; index++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                child: Row(
                  children: [
                    SkeletonBar(width: 40, height: 40),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: .75,
                            child: SkeletonBar(height: 14),
                          ),
                          SizedBox(height: 9),
                          FractionallySizedBox(
                            widthFactor: .45,
                            child: SkeletonBar(height: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index < 2)
                Divider(
                  color: context.border,
                  height: 2,
                  thickness: WeekPactMetrics.fineBorder,
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isCurrentUser,
    this.onRemove,
  });
  final CrewMember member;
  final bool isCurrentUser;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final initial = member.email.substring(0, 1).toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrentUser ? context.mint : context.surface,
              border: Border.all(
                color: context.border,
                width: WeekPactMetrics.border,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: context.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isCurrentUser ? 'YOU · ${member.email}' : member.email,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (member.isOwner)
            _StatusLabel(text: 'OWNER', color: context.yellow),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove ${member.email}',
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined, size: 22),
            ),
        ],
      ),
    );
  }
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

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: context.border,
          width: WeekPactMetrics.border,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: context.ink,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
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

class _CrewTab extends StatefulWidget {
  const _CrewTab({
    required this.label,
    required this.selected,
    required this.isFirst,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final bool isFirst;
  final VoidCallback onPressed;

  @override
  State<_CrewTab> createState() => _CrewTabState();
}

class _CrewTabState extends State<_CrewTab> {
  bool _isHeld = false;

  @override
  Widget build(BuildContext context) {
    final depth = _isHeld || widget.selected ? WeekPactMetrics.pressDepth : 0.0;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (held) => setState(() => _isHeld = held),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            margin: EdgeInsets.only(
              top: depth,
              bottom: WeekPactMetrics.pressDepth - depth,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: widget.selected
                  ? context.mint
                  : Color.lerp(context.surface, context.mint, .15),
              borderRadius: BorderRadius.only(
                topLeft: widget.isFirst
                    ? const Radius.circular(5)
                    : Radius.zero,
                topRight: widget.isFirst
                    ? Radius.zero
                    : const Radius.circular(5),
              ),
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.selected ? context.ink : context.muted,
                fontSize: 15,
                fontWeight: widget.selected ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'crew_page_layout.dart';
import '../pacts/pact_editor.dart';
import '../pacts/pacts_backend.dart';
import '../pacts/pacts_overview.dart';
import 'crew_sharing.dart';

import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';
import '../home/home_backend.dart';
import 'crew_roster.dart';

/// The two halves of a crew's page, in the order its tabs stand.
enum CrewPageTab { members, pacts }

/// One crew's own page, opened from the Crews list: its pacts, the people in
/// it, and the ways out of it.
class CrewPage extends StatefulWidget {
  const CrewPage({
    super.key,
    required this.backend,
    required this.currentUserEmail,
    this.crewId,
    this.profileBackend,
    this.pactsBackend,
    this.onCrewLeft,
    this.initialTab = CrewPageTab.members,
  });

  /// The tab the page opens on. Members, unless the page was opened to read
  /// the pacts.
  final CrewPageTab initialTab;

  /// The crew this page is about. Null opens the first crew the account is
  /// in, which is what a screen showing only one crew wants.
  final String? crewId;
  final HomeBackend? profileBackend;

  /// Where the crew's pacts are saved. Null leaves the page without its pacts
  /// section, for the screens that only ever show the roster.
  final PactsBackend? pactsBackend;
  final CrewBackend backend;
  final String currentUserEmail;

  /// Told when the person reading the page is no longer in the crew, having
  /// left it or ended it. The page closes itself afterwards.
  final VoidCallback? onCrewLeft;

  @override
  State<CrewPage> createState() => _CrewPageState();
}

class _CrewPageState extends State<CrewPage> with WidgetsBindingObserver {
  CrewDetails? _crew;
  int _request = 0;
  String? _profileCrewId;
  Map<String, WeekMember> _memberProfiles = {};

  /// The crew's week, as the summary card reads it. The page already fetches
  /// the week to put names and faces on the roster; these two figures came in
  /// the same answer and used to be dropped on the floor.
  int? _pactCount;
  int? _streakWeeks;

  /// The crew's pacts, from the same week. Null until it has arrived.
  List<CrewPact>? _pacts;
  String? _deletingPact;

  /// Which half of the page is open.
  late CrewPageTab _tab = widget.initialTab;

  /// Whether that fetch was made and failed. Without it the two figures stay
  /// null, which the card reads as "still coming" and draws as a bar nobody is
  /// filling in.
  bool _weekFailed = false;
  bool _loading = false;
  Future<void>? _crewLoad;
  bool _hasLoaded = false;
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
      final crew = await widget.backend.fetchCrew(crewId: widget.crewId);
      if (!mounted || request != _request) return;
      if (crew?.id != _profileCrewId) {
        _memberProfiles = {};
        _pactCount = null;
        _streakWeeks = null;
        _pacts = null;
        _profileCrewId = crew?.id;
      }
      if (crew != null && widget.profileBackend != null) {
        try {
          final week = await widget.profileBackend!.fetchWeek(crew.id);
          if (!mounted || request != _request) return;
          _memberProfiles = {
            for (final member in week.members) member.id: member,
          };
          _pactCount = week.pacts.length;
          _pacts = week.pacts;
          _streakWeeks = week.streakWeeks;
          _weekFailed = false;
        } catch (_) {
          // The summary card carries this one rather than the page: the roster
          // still stands on the names the crew itself gave, and the two
          // figures that did not arrive are the only thing missing. A sentence
          // below the list would be a second message for one failure.
          if (mounted && request == _request) {
            setState(() => _weekFailed = true);
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
        setState(() => _error = crewErrorMessage(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  /// Out of the crew, by leaving it or by ending it: the person is told, the
  /// app is told, and the page — which is about a crew they are no longer in
  /// — closes.
  void _leftCrew(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    widget.onCrewLeft?.call();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
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
          // Both ways out, now that there are two: hand the crew on, or end
          // it. Told only the first, the sole owner of a crew nobody joined
          // had nothing they could do.
          message:
              'Invite another member before leaving, then choose them as the '
              'new owner — or delete the crew.',
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
          iconColor: WeekPactColors.sand,
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
                        fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w500,
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
        _leftCrew('You left the crew.');
        return;
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Member removed.')));
    } catch (error) {
      if (mounted) setState(() => _error = crewErrorMessage(error));
    } finally {
      if (mounted) setState(() => _changingMembership = false);
    }
  }

  /// The backend if it can end a crew at all, and null where it cannot.
  ///
  /// Deletion is a second interface rather than part of [CrewBackend], the way
  /// sharing is, so this is the one place that asks.

  CrewDeletionBackend? get _deletionBackend {
    final backend = widget.backend;
    return backend is CrewDeletionBackend
        ? backend as CrewDeletionBackend
        : null;
  }

  /// Ends the crew for everyone in it.
  ///
  /// The owner's counterpart to leaving, and the only way out for the person
  /// who started a crew nobody else joined — that one is told to hand the crew
  /// over before leaving, which is no help when there is nobody to hand it to.
  /// Afterwards the page is in the same position as after leaving, so it takes
  /// the same road back to the list.
  Future<void> _deleteCrew() async {
    final crew = _crew;
    final backend = _deletionBackend;
    if (crew == null ||
        !crew.isOwner ||
        _changingMembership ||
        backend == null) {
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: HugeIconsStrokeRounded.delete02,
        iconColor: WeekPactColors.sand,
        title: 'Delete ${crew.name}?',
        // Said plainly, because the cascade behind this is not something the
        // crew can undo and it does not only happen to the person tapping.
        message:
            'Everyone in ${crew.name} loses the crew, its pacts, every '
            'check-in made against them, and the week streak. This cannot be '
            'undone.',
        actions: [
          AppButton(
            label: 'DELETE CREW',
            onPressed: () => Navigator.pop(context, true),
          ),
          AppDialogDismiss(
            label: 'Keep crew',
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _changingMembership) return;
    setState(() {
      _changingMembership = true;
      _error = null;
    });
    try {
      await backend.deleteCrew(crew.id);
      // Discard any fetch begun before the deletion; it still holds the crew.
      await _crewLoad;
      if (!mounted) return;
      _leftCrew('Crew deleted.');
    } catch (error) {
      if (mounted) setState(() => _error = crewErrorMessage(error));
    } finally {
      if (mounted) setState(() => _changingMembership = false);
    }
  }

  PactCrew _pactCrew(CrewDetails crew) => PactCrew(
    id: crew.id,
    name: crew.name,
    timezone: crew.timezone,
    isOwner: crew.isOwner,
  );

  Future<void> _editPact([CrewPact? existing]) async {
    final crew = _crew;
    final backend = widget.pactsBackend;
    if (crew == null || !crew.isOwner || backend == null) return;
    final pact = await showAppSheet<CrewPact>(
      context: context,
      builder: (_) =>
          PactEditor(crew: _pactCrew(crew), backend: backend, pact: existing),
    );
    if (!mounted || pact == null || _crew?.id != pact.crewId) return;
    // Reload the week rather than splice the pact in: the summary card counts
    // the same pacts, and an overlapping load could otherwise hide the new one.
    await _loadCrew();
  }

  Future<void> _deletePact(CrewPact pact) async {
    final crew = _crew;
    final backend = widget.pactsBackend;
    if (crew == null ||
        !crew.isOwner ||
        backend == null ||
        _deletingPact != null) {
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: HugeIconsStrokeRounded.delete02,
        iconColor: WeekPactColors.sand,
        title: 'Delete pact?',
        // What goes with it, said plainly: the cascade behind this takes every
        // check-in ever made against the pact, for the whole crew, and that is
        // not something the crew can undo afterwards.
        message:
            '“${pact.title}” and every check-in the crew has ever made '
            'against it will be gone. This cannot be undone.',
        actions: [
          AppButton(
            label: 'DELETE',
            onPressed: () => Navigator.pop(context, true),
          ),
          AppDialogDismiss(
            label: 'CANCEL',
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingPact = pact.id;
      _error = null;
    });
    try {
      await backend.deletePact(pactId: pact.id, crewId: pact.crewId);
      if (!mounted) return;
      await _loadCrew();
    } catch (error) {
      if (mounted) setState(() => _error = pactErrorMessage(error));
    } finally {
      if (mounted) setState(() => _deletingPact = null);
    }
  }

  Widget _buildPacts(BuildContext context, CrewDetails crew) {
    final pacts = _pacts;
    final canEdit = crew.isOwner && _deletingPact == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pacts == null)
          // The week failed; the summary card above already says so and
          // carries the retry, so this only keeps the section's place.
          const SizedBox.shrink()
        else if (pacts.isEmpty)
          AppSurface(
            key: const ValueKey('crew-pacts-empty'),
            builder: (context) => Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Small steps start here.',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    crew.isOwner
                        ? 'Add your first shared pact. Choose every day or a few days each week.'
                        : 'Your crew owner hasn’t added any pacts yet.',
                  ),
                ],
              ),
            ),
          )
        else
          PactBarList(
            pacts: pacts,
            onEdit: canEdit ? (pact) => _editPact(pact) : null,
            onDelete: canEdit ? _deletePact : null,
          ),
        if (crew.isOwner && pacts != null) ...[
          const SizedBox(height: 14),
          AppButton(
            label: 'ADD PACT',
            icon: HugeIconsStrokeRounded.add01,
            onPressed: _changingMembership ? null : () => _editPact(),
          ),
        ],
      ],
    );
  }

  Future<void> _openInviteDrawer() async {
    final crew = _crew;
    if (crew == null || !crew.isOwner) return;
    await showAppSheet<void>(
      context: context,
      builder: (context) => _InviteDrawer(
        crew: crew,
        backend: widget.backend,
        inviterId: crew.members
            .where(_isCurrentUser)
            .map((member) => member.userId)
            .where((id) => id.isNotEmpty)
            .firstOrNull,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant CrewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.crewId != oldWidget.crewId ||
        widget.profileBackend != oldWidget.profileBackend) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await _loadCrew();
  }

  @override
  Widget build(BuildContext context) {
    final crew = _crew;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: PageFrame(
        header: CrewPageHeading(
          switcher: crew == null
              ? null
              : Text(
                  crew.name,
                  key: const ValueKey('crew-page-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          leading: [
            if (canPop)
              IconButton(
                tooltip: 'Back to crews',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const AppIcon(icon: HugeIconsStrokeRounded.arrowLeft01),
              ),
          ],
          actions: [if (crew != null) _crewMenu(context, crew)],
        ),
        loading: !_hasLoaded && _loading,
        skeleton: CrewPageSkeleton(
          body: CrewRosterSkeleton(tabs: widget.pactsBackend != null),
        ),
        onRefresh: _refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading && crew != null && !_hasLoaded)
              CrewPageSkeleton(
                body: CrewRosterSkeleton(tabs: widget.pactsBackend != null),
              )
            else if (crew != null)
              _buildCrewState(context, crew)
            else if (_hasLoaded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'This crew is no longer available.',
                  key: const ValueKey('crew-unavailable'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.muted, fontSize: 16),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.errorInk,
                  fontWeight: FontWeight.w600,
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
      ),
    );
  }

  /// The rare things done to a crew, kept off the page itself: they cannot be
  /// undone, and they used to stand under the roster on every visit.
  Widget _crewMenu(BuildContext context, CrewDetails crew) =>
      PopupMenuButton<VoidCallback>(
        key: const ValueKey('crew-menu'),
        tooltip: 'Crew options',
        enabled: !_changingMembership,
        color: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeekPactMetrics.cardCorner),
          side: BorderSide(color: context.border),
        ),
        position: PopupMenuPosition.under,
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: () => _changeMembership(),
            child: _menuEntry(
              context,
              icon: HugeIconsStrokeRounded.logout01,
              label: 'Leave crew',
            ),
          ),
          if (crew.isOwner && _deletionBackend != null)
            PopupMenuItem(
              value: _deleteCrew,
              child: _menuEntry(
                context,
                icon: HugeIconsStrokeRounded.delete02,
                label: 'Delete crew',
                destructive: true,
              ),
            ),
        ],
        icon: const AppIcon(icon: HugeIconsStrokeRounded.moreVertical),
      );

  /// One entry in the crew menu. The menu is a cream card opened from the
  /// dark canvas, so its entries take the card's inks rather than the page's,
  /// which are drawn for the canvas and vanish on cream.
  Widget _menuEntry(
    BuildContext context, {
    required List<List<dynamic>> icon,
    required String label,
    bool destructive = false,
  }) => AppSurfaceTheme(
    builder: (context) {
      final color = destructive ? context.errorInk : context.ink;
      return Row(
        children: [
          AppIcon(icon: icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    },
  );

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
        // The crew itself, where a caption used to repeat the header above it
        // and the faces below it.
        CrewSummaryCard(
          people: crew.members.length,
          startedAt: crew.createdAt,
          pacts: _pactCount,
          streakWeeks: _streakWeeks,
          weekFailed: _weekFailed,
          onRetry: _loading ? null : _loadCrew,
        ),
        const SizedBox(height: 18),
        if (widget.pactsBackend == null) ...[
          const CrewSectionLabel('IN THE CREW'),
          const SizedBox(height: 10),
          _buildMembers(context, crew, members),
        ] else ...[
          CrewPageTabs(
            labels: [
              'Members · ${members.length}',
              _pacts == null ? 'Pacts' : 'Pacts · ${_pacts!.length}',
            ],
            selected: _tab.index,
            onSelected: (tab) => setState(() => _tab = CrewPageTab.values[tab]),
          ),
          const SizedBox(height: 14),
          if (_tab == CrewPageTab.members)
            _buildMembers(context, crew, members)
          else
            _buildPacts(context, crew),
        ],
      ],
    );
  }

  Widget _buildMembers(
    BuildContext context,
    CrewDetails crew,
    List<CrewMember> members,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          ],
        ),
        // Inviting somebody is not a member of the crew, so it stands after
        // the roster rather than as its last row. It used to be the same band
        // at the same size inside the same list, in black.
        if (crew.isOwner) ...[
          const SizedBox(height: 14),
          CrewInviteBand(
            onPressed: _changingMembership ? null : _openInviteDrawer,
          ),
        ],
      ],
    );
  }

  bool _isCurrentUser(CrewMember member) =>
      member.email.toLowerCase() == widget.currentUserEmail.toLowerCase();
}

class _InviteDrawer extends StatelessWidget {
  const _InviteDrawer({
    required this.crew,
    required this.backend,
    this.inviterId,
  });

  final CrewDetails crew;
  final CrewBackend backend;
  final String? inviterId;

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
                  fontWeight: FontWeight.w700,
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
            crewName: crew.name,
            inviterId: inviterId,
            isOwner: crew.isOwner,
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

String crewErrorMessage(Object error) {
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
  // Ahead of the membership answer below, which shares its opening words and
  // would send someone off to pick a new owner for a crew they are ending.
  if (message.contains('delete a crew')) {
    return 'Only the crew’s owner can delete it.';
  }
  if (message.contains('Only the owner') ||
      message.contains('Choose another member')) {
    return 'Only the current owner can manage members. Choose a new owner before leaving.';
  }
  return 'Something went wrong. Please try again.';
}

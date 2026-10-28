import '../telemetry/diagnostics_control.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import 'auth_backend.dart';
import 'avatar_picker.dart';
import 'profile_editor.dart';
import 'profile_history.dart';
import 'profile_wall.dart';
import 'account_actions.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_page.dart';
import '../crew/crew_page_layout.dart';
import '../home/check_in_story.dart';
import '../home/home_backend.dart';
import '../home/nudge_sheet.dart';
import '../onboarding/profile_avatar.dart';
import '../notifications/notification_kind_controls.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/notification_scope.dart';
import '../notifications/notification_settings_card.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';

/// The Account tab: your own record, as a wall of every check-in you have
/// kept across your crews, under a header with your face, three figures and
/// Edit profile, and a strip of the crews themselves.
///
/// Settings, Log out and Delete account sit behind the gear in the corner:
/// the wall pages on as it scrolls, so nothing can stand at its foot.
///
/// Given a [member], it is that crewmate's profile instead, opened from their
/// face elsewhere: the same header and wall, scoped to the crews you share,
/// with a way back where the gear was and nothing to edit.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.user,
    required this.backend,
    required this.signingOut,
    required this.onSignOut,
    this.pickAvatar,
    this.homeBackend,
    this.crewBackend,
    this.pactsBackend,
    this.active = true,
    this.onCrewSelected,
    this.onCrewLeft,
    this.member,
    this.nudgeCrewId,
    this.onNudged,
  });

  /// Whoever is signed in, on their own profile or on a crewmate's.
  final AuthUser user;
  final AuthBackend backend;
  final bool signingOut;
  final VoidCallback onSignOut;

  /// Injected by tests, which have no gallery for the native picker to open.
  final AvatarPicker? pickAvatar;

  /// Opens a check-in as a story, and — when it is also a
  /// [ProfileHistoryBackend] — reads the wall. Null leaves the page as the
  /// profile and its settings alone.
  final HomeBackend? homeBackend;

  /// Where the crew strip comes from. Null leaves the strip out.
  final CrewBackend? crewBackend;
  final PactsBackend? pactsBackend;

  /// Whether the tab is the one showing; the page reloads as it comes back.
  final bool active;
  final ValueChanged<String>? onCrewSelected;
  final VoidCallback? onCrewLeft;

  /// The crewmate whose profile this is. Null for your own.
  final WeekMember? member;

  /// The crew a nudge to [member] goes out in: the one their face was seen
  /// in. Null, or a crew the two of you no longer share, falls back to the
  /// first crew you do.
  final String? nudgeCrewId;

  /// Hears of a nudge sent from the profile, so the page behind keeps step.
  final ValueChanged<CrewNudgeState>? onNudged;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AuthUser? _edited;
  // The photo the editor just uploaded. The avatar downloads the stored one
  // once, so a fresh pick has to be handed back rather than re-fetched.
  Uint8List? _avatar;

  static const _pageSize = 30;

  ProfileSummary? _summary;
  List<PactCrew>? _crews;
  final Map<String, List<WeekMember>> _members = {};
  List<ProfileCheckIn>? _checkIns;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _wallFailed = false;
  String? _pactFilter;
  int _request = 0;

  /// The nudge on a crewmate's profile: the crew it goes out in, that crew's
  /// week for the dialog's reason, and whether one is allowed. The button
  /// waits for the week; a state that will not load leaves it standing, since
  /// the send is what decides.
  String? _nudgeCrew;
  CrewWeek? _nudgeWeek;
  CrewNudgeState? _nudgeState;

  ProfileHistoryBackend? get _history => switch (widget.homeBackend) {
    final ProfileHistoryBackend history => history,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    await Future.wait([
      _loadSummary(request),
      _loadCrews(request),
      _loadWall(request),
    ]);
  }

  Future<void> _loadSummary(int request) async {
    final history = _history;
    if (history == null) return;
    try {
      final summary = await history.fetchProfileSummary(
        userId: widget.member?.id,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _summary = summary;
        // A pact the filter was on may have gone with its crew.
        if (!summary.pacts.any((p) => p.id == _pactFilter)) _pactFilter = null;
      });
      await _loadNudge(request, summary);
    } catch (_) {
      // The figures keep their dashes; the wall says what failed.
    }
  }

  Future<void> _loadNudge(int request, ProfileSummary summary) async {
    final member = widget.member;
    final backend = widget.homeBackend;
    final shared = summary.crewIds ?? const <String>[];
    if (member == null || backend == null || member.id == widget.user.id) {
      return;
    }
    final hint = widget.nudgeCrewId;
    final crewId = shared.contains(hint) ? hint : shared.firstOrNull;
    if (crewId == null) {
      setState(() => _nudgeCrew = null);
      return;
    }
    final states = backend
        .fetchNudgeStates(crewId)
        .then<CrewNudgeState?>((states) => states[member.id])
        .catchError((Object _) => null);
    try {
      final week = await backend.fetchWeekBrief(crewId);
      final state = await states;
      if (!mounted || request != _request) return;
      setState(() {
        _nudgeCrew = crewId;
        _nudgeWeek = week;
        _nudgeState = state;
      });
    } catch (_) {
      // No week, no reason to give: the button stays away until a refresh.
    }
  }

  Future<void> _loadCrews(int request) async {
    final backend = widget.crewBackend;
    if (backend == null) return;
    try {
      final crews = await backend.fetchCrews();
      if (!mounted || request != _request) return;
      setState(() => _crews = crews);
      final weeks = widget.homeBackend;
      if (weeks == null) return;
      // Each pill's faces fill in on its own, as the Crews tab's cards do.
      await Future.wait([
        for (final crew in crews)
          weeks
              .fetchWeekBrief(crew.id)
              .then((week) {
                if (!mounted || request != _request) return;
                setState(() => _members[crew.id] = week.members);
              })
              .catchError((Object _) {}),
      ]);
    } catch (_) {
      // The strip is a shortcut to the Crews tab; it can stay away.
    }
  }

  Future<void> _loadWall(int request) async {
    final history = _history;
    if (history == null) return;
    setState(() => _wallFailed = false);
    try {
      final page = await history.fetchMyCheckIns(
        pactId: _pactFilter,
        limit: _pageSize,
        userId: widget.member?.id,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _checkIns = page;
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _wallFailed = true);
    }
  }

  Future<void> _loadMore() async {
    final history = _history;
    final loaded = _checkIns;
    if (history == null || loaded == null || !_hasMore || _loadingMore) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await history.fetchMyCheckIns(
        before: loaded.last,
        pactId: _pactFilter,
        limit: _pageSize,
        userId: widget.member?.id,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _checkIns = [...loaded, ...page];
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      // The next scroll to the end asks again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _filter(String? pactId) {
    if (pactId == _pactFilter) return;
    final request = ++_request;
    setState(() {
      _pactFilter = pactId;
      _checkIns = null;
      _hasMore = false;
    });
    _loadWall(request);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 600) {
      _loadMore();
    }
    return false;
  }

  Future<void> _edit() async {
    final updated = await showAppSheet<ProfileEdit>(
      context: context,
      builder: (_) => ProfileEditor(
        user: _edited ?? widget.user,
        backend: widget.backend,
        pickAvatar: widget.pickAvatar,
      ),
    );
    if (mounted && updated != null) {
      setState(() {
        _edited = updated.user;
        _avatar = updated.avatar ?? _avatar;
      });
    }
  }

  Future<void> _nudge() async {
    final crewId = _nudgeCrew;
    final week = _nudgeWeek;
    final member = widget.member;
    final backend = widget.homeBackend;
    if (crewId == null || week == null || member == null || backend == null) {
      return;
    }
    final kept =
        week.checkIns
            .where((i) => i.userId == member.id)
            .map((i) => i.day)
            .toList()
          ..sort();
    final result = await showNudge(
      context: context,
      backend: backend,
      crewId: crewId,
      member: member,
      state: _nudgeState,
      today: week.today,
      lastKept: kept.lastOrNull,
    );
    if (!mounted || result == null) return;
    setState(() => _nudgeState = result);
    // Only the crew the page behind was showing is its business.
    if (crewId == widget.nudgeCrewId) widget.onNudged?.call(result);
    final name = member.displayName.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nudged ${name.isEmpty ? 'your crewmate' : name}.'),
      ),
    );
  }

  Future<void> _openSettings() => showAppSheet<void>(
    context: context,
    builder: (sheetContext) => AppSheet(
      builder: (context) => _AccountSettings(
        backend: widget.backend,
        enabled: !widget.signingOut,
        onSignOut: () {
          // The sheet goes first, so it does not stand over the sign-in page.
          Navigator.pop(sheetContext);
          widget.onSignOut();
        },
      ),
    ),
  );

  Future<void> _openCrew(PactCrew crew) async {
    final backend = widget.crewBackend;
    if (backend == null) return;
    widget.onCrewSelected?.call(crew.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewPage(
          crewId: crew.id,
          backend: backend,
          profileBackend: widget.homeBackend,
          pactsBackend: widget.pactsBackend,
          currentUserEmail: widget.user.email,
          onCrewLeft: widget.onCrewLeft,
        ),
      ),
    );
    // Back from the crew: its pacts or the crew itself may have changed.
    if (mounted) await _refresh();
  }

  void _openCheckIn(ProfileCheckIn checkIn) {
    final backend = widget.homeBackend;
    if (backend == null) return;
    unawaited(
      openCheckInStory(
        context,
        checkIn: checkIn.ref,
        // On your own wall the check-in's author is you, whatever id the
        // signed-in user arrived with.
        viewerId: widget.member == null ? checkIn.ref.userId : widget.user.id,
        backend: backend,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final user = _edited ?? widget.user;
    final name = member == null
        ? '${user.firstName} ${user.lastName}'.trim()
        : member.displayName.trim();
    final initials = [user.firstName, user.lastName]
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim().characters.first.toUpperCase())
        .join();
    final summary = _summary;
    // A crewmate's strip is the crews you share, which only the summary knows.
    final shared = summary?.crewIds;
    final crews = (_crews ?? const <PactCrew>[])
        .where(
          (crew) =>
              member == null || (shared != null && shared.contains(crew.id)),
        )
        .toList();
    final history = _history != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageFrame(
        topPadding: 4,
        onRefresh: history || widget.crewBackend != null ? _refresh : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (member == null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: AppIcon(
                    icon: HugeIconsStrokeRounded.settings01,
                    color: context.ink,
                    size: 24,
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: AppIcon(
                    icon: HugeIconsStrokeRounded.arrowLeft01,
                    color: context.ink,
                    size: 24,
                  ),
                ),
              ),
            Row(
              key: const ValueKey('account-profile'),
              children: [
                // Pale-card scope, so the initials are card ink on the mint
                // rather than the canvas's light ink.
                Theme(
                  data: WeekPactTheme.light,
                  child: member == null
                      ? ProfileAvatar(
                          backend: widget.backend,
                          size: 84,
                          initials: initials,
                          backgroundColor: WeekPactColors.mintGreen,
                          photo: _avatar,
                        )
                      : _MemberAvatar(member: member, size: 84),
                ),
                if (history) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(
                          child: ProfileFigure(
                            value: summary?.checkIns,
                            label: 'check-ins',
                          ),
                        ),
                        Flexible(
                          child: ProfileFigure(
                            value: summary?.pacts.length,
                            label: 'pacts',
                          ),
                        ),
                        Flexible(
                          child: ProfileFigure(
                            value: summary?.crews,
                            label: 'crews',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // A crewmate's nudge stands beside their name, small: the page is
            // about them, and the button is one thing you might do there.
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isNotEmpty
                        ? name
                        : member == null
                        ? 'Your profile'
                        : 'Crew member',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (member != null)
                  if (_nudgeButton() case final button?) ...[
                    const SizedBox(width: 12),
                    button,
                  ],
              ],
            ),
            // A crewmate's address is theirs; the crews you share say enough.
            if (member == null) ...[
              const SizedBox(height: 2),
              Text(
                user.email,
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
              const SizedBox(height: 14),
              Tooltip(
                message: 'Edit profile',
                child: FilledButton.icon(
                  onPressed: widget.signingOut ? null : _edit,
                  style: FilledButton.styleFrom(
                    backgroundColor: WeekPactColors.cream,
                    foregroundColor: WeekPactColors.black,
                    minimumSize: const Size.fromHeight(44),
                    shape: WeekPactMetrics.buttonShape,
                  ),
                  icon: const AppIcon(
                    icon: HugeIconsStrokeRounded.pencilEdit02,
                    size: 20,
                  ),
                  label: const Text(
                    'Edit profile',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
            if (crews.isNotEmpty) ...[
              const SizedBox(height: WeekPactMetrics.sectionGap),
              const CrewSectionLabel('CREWS'),
              const SizedBox(height: 10),
              SizedBox(
                height: ProfileCrewPill.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: crews.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ProfileCrewPill(
                    key: ValueKey('account-crew-${crews[i].id}'),
                    crew: crews[i],
                    members: _members[crews[i].id],
                    onTap: () => _openCrew(crews[i]),
                  ),
                ),
              ),
            ],
            if (history) ...[
              const SizedBox(height: WeekPactMetrics.sectionGap),
              const CrewSectionLabel('CHECK-INS'),
              const SizedBox(height: 10),
              if ((summary?.pacts.length ?? 0) > 1) ...[
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    children: [
                      ProfileFilterChip(
                        label: 'All',
                        selected: _pactFilter == null,
                        onTap: () => _filter(null),
                      ),
                      for (final pact in summary!.pacts) ...[
                        const SizedBox(width: 6),
                        ProfileFilterChip(
                          key: ValueKey('account-filter-${pact.id}'),
                          label: pact.title,
                          pact: pact,
                          selected: _pactFilter == pact.id,
                          onTap: () => _filter(pact.id),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _buildWall(context),
            ],
          ],
        ),
      ),
    );
  }

  /// The nudge, a small pill beside a crewmate's name. Gone once they are in
  /// or cannot be nudged; still there once nudged, so the dialog can say when
  /// the next one is allowed.
  Widget? _nudgeButton() {
    if (_nudgeCrew == null || _nudgeWeek == null) return null;
    final status = _nudgeState?.status;
    if (status == CrewNudgeStatus.checkedIn ||
        status == CrewNudgeStatus.unavailable) {
      return null;
    }
    final nudged =
        status == CrewNudgeStatus.sent || status == CrewNudgeStatus.cooldown;
    return FilledButton.icon(
      key: const ValueKey('profile-nudge'),
      onPressed: _nudge,
      style: FilledButton.styleFrom(
        backgroundColor: nudged
            ? context.ink.withValues(alpha: .12)
            : WeekPactColors.cream,
        foregroundColor: nudged ? context.ink : WeekPactColors.black,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.compact,
        shape: WeekPactMetrics.buttonShape,
      ),
      icon: const AppIcon(icon: HugeIconsStrokeRounded.zap, size: 16),
      label: Text(
        nudged ? 'Nudged' : 'Nudge',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildWall(BuildContext context) {
    final checkIns = _checkIns;
    if (checkIns == null && _wallFailed) {
      return _WallMessage(
        text: widget.member == null
            ? 'Your check-ins could not load.'
            : 'These check-ins could not load.',
        action: 'Try again',
        onAction: () => _loadWall(_request),
      );
    }
    if (checkIns == null) {
      return ProfileWallGrid(
        itemCount: 9,
        itemBuilder: (context, _) => DecoratedBox(
          decoration: ShapeDecoration(
            color: context.ink.withValues(alpha: .06),
            shape: ProfileWallTile.shape,
          ),
        ),
      );
    }
    if (checkIns.isEmpty) {
      return _WallMessage(
        text: _pactFilter != null
            ? 'Nothing kept for this pact yet.'
            : widget.member == null
            ? 'Every check-in you keep collects here. Keep a pact on Home '
                  'and it is the first.'
            : 'Nothing kept in your crews yet.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileWallGrid(
          itemCount: checkIns.length,
          itemBuilder: (context, i) => ProfileWallTile(
            key: ValueKey(
              'account-check-in-${checkIns[i].ref.pactId}-${checkIns[i].day}',
            ),
            checkIn: checkIns[i],
            onTap: () => _openCheckIn(checkIns[i]),
          ),
        ),
        if (_hasMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// A crewmate's face in the header: their photo, or their initials on the
/// mint your own wears.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, required this.size});

  final WeekMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = Center(
      child: Text(
        member.initials,
        style: TextStyle(
          color: context.ink,
          fontSize: size * .35,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final url = member.avatarUrl;
    return Container(
      width: size,
      height: size,
      decoration: const ShapeDecoration(
        shape: AvatarShape(),
        color: WeekPactColors.mintGreen,
      ),
      child: AvatarClip(
        child: url == null || url.trim().isEmpty
            ? initials
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => initials,
              ),
      ),
    );
  }
}

class _WallMessage extends StatelessWidget {
  const _WallMessage({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.muted, fontSize: 15),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// Everything Account used to hold under the profile: notifications, crash
/// reports, Support and Privacy, Log out and Delete account.
class _AccountSettings extends StatelessWidget {
  const _AccountSettings({
    required this.backend,
    required this.enabled,
    required this.onSignOut,
  });

  final AuthBackend backend;
  final bool enabled;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
          ),
        ],
      ),
      const SizedBox(height: 12),
      AppSurface(
        key: const ValueKey('account-preferences'),
        builder: (context) => Column(
          children: [
            _NotificationControl(enabled: enabled),
            // What the account is sent, once this phone is sent anything.
            if (backend case final NotificationPreferencesBackend preferences)
              if (NotificationScope.maybeOf(context)?.enabled ?? false)
                NotificationKindControls(
                  backend: preferences,
                  enabled: enabled,
                ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1),
            ),
            DiagnosticsControl(enabled: enabled),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const PublicAccountLinks(asTiles: true),
      const SizedBox(height: 12),
      AppSurface(
        builder: (context) => ListTile(
          onTap: enabled ? onSignOut : null,
          enabled: enabled,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 2,
          ),
          leading: AppIcon(
            icon: HugeIconsStrokeRounded.logout01,
            color: context.ink,
            size: 24,
          ),
          title: Text(
            enabled ? 'Log out' : 'Logging out…',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          trailing: AppIcon(
            icon: HugeIconsStrokeRounded.arrowRight01,
            color: context.ink,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Divider(height: 1, color: context.border.withValues(alpha: .3)),
      const SizedBox(height: 4),
      AccountActions(
        backend: backend,
        enabled: enabled,
        showPasswordReset: false,
        showPublicLinks: false,
        asRows: true,
      ),
    ],
  );
}

class _NotificationControl extends StatelessWidget {
  const _NotificationControl({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final service = NotificationScope.maybeOf(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      secondary: const AppIcon(
        icon: HugeIconsStrokeRounded.notification02,
        size: 26,
      ),
      title: const Text(
        'Notifications',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      activeTrackColor: WeekPactColors.coolGrey,
      activeThumbColor: WeekPactColors.black,
      value: service?.enabled ?? false,
      onChanged: !enabled || service == null || service.busy
          ? null
          : (enabled) async {
              if (enabled) {
                await service.enable();
              } else {
                await service.disable();
              }
              if (context.mounted &&
                  (service.error != null ||
                      service.registrationError != null ||
                      !service.available ||
                      (enabled && !service.allowed))) {
                await showAppSheet<void>(
                  context: context,
                  builder: (_) => AppSheet(
                    builder: (_) => const NotificationSettingsCard(),
                  ),
                );
              }
            },
    );
  }
}

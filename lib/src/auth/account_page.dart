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
import '../onboarding/profile_avatar.dart';
import '../notifications/notification_scope.dart';
import '../notifications/notification_settings_card.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';

/// The Account tab: your own record, as a wall of every check-in you have
/// kept across your crews, under a header with your face, three figures and
/// Edit profile, and a strip of the crews themselves.
///
/// Settings, Log out and Delete account sit behind the gear in the corner:
/// the wall pages on as it scrolls, so nothing can stand at its foot.
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
  });
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
      final summary = await history.fetchProfileSummary();
      if (!mounted || request != _request) return;
      setState(() {
        _summary = summary;
        // A pact the filter was on may have gone with its crew.
        if (!summary.pacts.any((p) => p.id == _pactFilter)) _pactFilter = null;
      });
    } catch (_) {
      // The figures keep their dashes; the wall says what failed.
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
        viewerId: checkIn.ref.userId,
        backend: backend,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _edited ?? widget.user;
    final name = '${user.firstName} ${user.lastName}'.trim();
    final initials = [user.firstName, user.lastName]
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim().characters.first.toUpperCase())
        .join();
    final summary = _summary;
    final crews = _crews ?? const <PactCrew>[];
    final history = _history != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageFrame(
        topPadding: 4,
        onRefresh: history || widget.crewBackend != null ? _refresh : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            ),
            Row(
              key: const ValueKey('account-profile'),
              children: [
                // Pale-card scope, so the initials are card ink on the mint
                // rather than the canvas's light ink.
                Theme(
                  data: WeekPactTheme.light,
                  child: ProfileAvatar(
                    backend: widget.backend,
                    size: 84,
                    initials: initials,
                    backgroundColor: WeekPactColors.mintGreen,
                    photo: _avatar,
                  ),
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
            Text(
              name.isEmpty ? 'Your profile' : name,
              style: TextStyle(
                color: context.ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
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

  Widget _buildWall(BuildContext context) {
    final checkIns = _checkIns;
    if (checkIns == null && _wallFailed) {
      return _WallMessage(
        text: 'Your check-ins could not load.',
        action: 'Try again',
        onAction: () => _loadWall(_request),
      );
    }
    if (checkIns == null) {
      return ProfileWallGrid(
        itemCount: 9,
        itemBuilder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: context.ink.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          ),
        ),
      );
    }
    if (checkIns.isEmpty) {
      return _WallMessage(
        text: _pactFilter == null
            ? 'Every check-in you keep collects here. Keep a pact on Home '
                  'and it is the first.'
            : 'Nothing kept for this pact yet.',
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
        builder: (_) => Column(
          children: [
            _NotificationControl(enabled: enabled),
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

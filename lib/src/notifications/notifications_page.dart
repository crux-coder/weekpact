import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_month_calendar.dart';
import '../crew/crew_page_layout.dart';
import '../home/check_in_story.dart';
import '../home/clap_control.dart';
import '../home/home_backend.dart';
import '../home/stories.dart';
import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';
import '../widgets/skeleton_switcher.dart';

/// Opens the list and reports how many notifications are still unread when it
/// closes, so the badge behind it settles without a second round trip. Backing
/// out with the system gesture reports nothing, and the caller reads the count
/// itself rather than the page holding the gesture hostage to answer.
Future<int?> showNotificationsPage(
  BuildContext context, {
  required HomeBackend backend,
  required String viewerId,
}) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    builder: (_) => NotificationsPage(backend: backend, viewerId: viewerId),
  ),
);

/// The bell, and what it wears: how many of the crew's notices are unread,
/// and the way into the list of them.
///
/// The bell is Home's — top right, across from the crew's name, which is the
/// corner an app's notifications live in and the one place on Home nothing
/// else is asking for.
///
/// It keeps its own count rather than taking one from the page around it: the
/// count has nothing to do with the crew's week, survives a crew switch
/// untouched, and a page that threaded it through would have to refresh it for
/// reasons that are not its own.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({
    super.key,
    required this.backend,
    required this.viewerId,
    this.active = true,
  });

  final HomeBackend backend;

  /// The person holding the phone, whom a check-in opened from the list is
  /// shown to.
  final String viewerId;

  /// Whether the page carrying the bell is the one on screen. Coming back to
  /// it re-reads the count, the way returning to any tab re-reads its page.
  final bool active;

  /// The bell's tap target, which is also the height a header has to give the
  /// row it sits in.
  static const size = 44.0;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell>
    with WidgetsBindingObserver {
  /// What the bell wears. A failed count leaves the badge as it was rather
  /// than claiming the crew has gone quiet.
  int _unread = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_count());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NotificationsBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(_count());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(_count());
    }
  }

  Future<void> _count() async {
    try {
      final unread = await widget.backend.fetchUnreadNotificationCount();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      // The page is the page; the badge is not worth an error state.
    }
  }

  /// The list hands back what is still unread when it closes, so the badge
  /// settles on the way out instead of on the next read. Backing out with the
  /// system gesture answers nothing, and the count is read again instead.
  Future<void> _openList() async {
    setState(() => _opening = true);
    final remaining = await showNotificationsPage(
      context,
      backend: widget.backend,
      viewerId: widget.viewerId,
    );
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (remaining != null) _unread = remaining;
    });
    if (remaining == null) await _count();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: NotificationsBell.size,
    child: IconButton(
      tooltip: 'Notifications',
      onPressed: _opening ? null : () => unawaited(_openList()),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: NotificationsBell.size,
        height: NotificationsBell.size,
      ),
      icon: Badge(
        key: const ValueKey('notifications-badge'),
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        backgroundColor: WeekPactColors.salmon,
        textColor: WeekPactColors.black,
        child: const AppIcon(icon: HugeIconsStrokeRounded.notification02),
      ),
    ),
  );
}

/// The section a notice from [at] is filed under, read by the phone's own
/// calendar at [now]: Today, Yesterday, This week (from Monday), Last week,
/// and then the month by name — with its year once it is not this year's.
///
/// Yesterday wins over Last week on a Monday, and a month only takes what
/// the weeks have not.
String notificationSection(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final monday = mondayOf(today);
  if (!day.isBefore(today)) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  if (!day.isBefore(monday)) return 'This week';
  if (!day.isBefore(DateTime(monday.year, monday.month, monday.day - 7))) {
    return 'Last week';
  }
  final month = crewMonthNames[day.month - 1];
  return day.year == today.year ? month : '$month ${day.year}';
}

/// Everything the crew has told this person, newest first.
///
/// The page reads itself in pages keyed on the last entry, so a notification
/// arriving mid-scroll cannot shift what is below the fold. Opening it marks read only as far as the first page reached: anything
/// that lands while it is open is still unread when it closes.
///
/// A notice about a check-in opens that check-in's story when tapped.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.backend,
    required this.viewerId,
  });

  final HomeBackend backend;
  final String viewerId;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _pageSize = 20;
  final _scroll = ScrollController();
  final _entries = <NotificationEntry>[];
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = true;
  bool _failed = false;

  /// Whether the list has taken over from its skeleton.
  bool _listShown = false;

  /// What the badge should read once this page closes. It is the count the
  /// server had, less what opening the page cleared.
  int _unread = 0;

  /// The notices that were unread when they arrived, which keep their mark
  /// for this visit even though opening the page marks them read: the point
  /// of the mark is to show what is new since last time.
  final _fresh = <String>{};

  /// The crew the list is cut to, or null for every crew.
  String? _crew;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    unawaited(_open());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await _loadMore();
    await _markRead();
  }

  /// Clears everything down to the newest notification actually shown. A read
  /// that failed leaves the badge alone rather than guessing.
  Future<void> _markRead() async {
    final newest = _entries.firstOrNull;
    if (newest == null) return;
    try {
      await widget.backend.markNotificationsRead(upTo: newest.createdAt);
      final remaining = await widget.backend.fetchUnreadNotificationCount();
      if (!mounted) return;
      setState(() {
        _unread = remaining;
        for (var index = 0; index < _entries.length; index++) {
          if (!_entries[index].createdAt.isAfter(newest.createdAt)) {
            _entries[index] = _entries[index].copyWith(read: true);
          }
        }
      });
    } catch (_) {
      // The list still reads; only the badge behind it stays as it was.
    }
  }

  void _loadNearEnd() {
    // Not while the skeleton stands in: it is shorter than the list, and
    // would read as a list that needs its next page.
    if (!_listShown) return;
    if (_scroll.hasClients && _scroll.position.extentAfter < 600 && !_failed) {
      unawaited(_loadMore());
    }
  }

  Future<void> _refresh() async {
    _hasMore = true;
    final fresh = await _read();
    if (fresh == null || !mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(fresh);
      _fresh.addAll(fresh.where((e) => !e.read).map((e) => e.eventId));
    });
    await _markRead();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final page = await _read(before: _entries.lastOrNull);
    if (page == null || !mounted) return;
    setState(() {
      _entries.addAll(page);
      _fresh.addAll(page.where((e) => !e.read).map((e) => e.eventId));
    });
    // Fill a tall viewport without requiring a scroll gesture first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNearEnd();
    });
  }

  /// Returns null when the read failed; state carries the error either way.
  Future<List<NotificationEntry>?> _read({NotificationEntry? before}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.backend.fetchNotifications(
        before: before,
        limit: _pageSize,
      );
      if (!mounted) return null;
      setState(() {
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loaded = true;
      });
      return page;
    } catch (_) {
      if (!mounted) return null;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return null;
    }
  }

  /// Every crew the loaded notices come from, in the order they first
  /// appear — newest activity first.
  List<({String id, String name})> get _crews {
    final seen = <String>{};
    return [
      for (final e in _entries)
        if (seen.add(e.crewId)) (id: e.crewId, name: e.crewName),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final crews = _crews;
    // A crew none of whose notices are loaded any more (after a refresh)
    // puts the list back on every crew.
    final crew = crews.any((c) => c.id == _crew) ? _crew : null;
    final shown = crew == null
        ? _entries
        : _entries.where((e) => e.crewId == crew).toList();
    final showEmpty = _loaded && shown.isEmpty && !_failed;
    final top = MediaQuery.paddingOf(context).top;
    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: WeekPactMetrics.sectionGap),
        child: CrewPageHeading(
          switcher: Text(
            'Notifications',
            key: const ValueKey('notifications-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.ink,
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Close notifications',
              onPressed: () => Navigator.of(context).pop(_unread),
              icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
            ),
          ],
        ),
      ),
      // One tab per crew, once there is more than one to tell apart.
      if (crews.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _CrewTabs(
            crews: crews,
            selected: crew,
            unread: {
              for (final c in crews)
                c.id: _entries
                    .where(
                      (e) => e.crewId == c.id && _fresh.contains(e.eventId),
                    )
                    .length,
            },
            all: _entries.where((e) => _fresh.contains(e.eventId)).length,
            onSelected: (id) => setState(() => _crew = id),
          ),
        ),
      // The list itself, one slot under the heading, so the first load
      // fades in over its skeleton rather than cutting.
      SkeletonSwitcher(
        skeleton: const _NotificationsSkeleton(),
        onShown: () {
          _listShown = true;
          _loadNearEnd();
        },
        child: _loading && _entries.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (label, entries) in _sections(shown)) ...[
                    _SectionLabel(label),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppSurface(
                        key: ValueKey('notifications-section-$label'),
                        borderRadius: 18,
                        builder: (context) => Column(
                          children: [
                            for (final (i, entry) in entries.indexed) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 64,
                                  color: context.ink.withValues(alpha: .08),
                                ),
                              _NotificationRow(
                                key: ValueKey('notification-${entry.eventId}'),
                                entry: entry,
                                fresh: _fresh.contains(entry.eventId),
                                showCrew: crew == null && crews.length > 1,
                                onTap: switch (entry.checkIn) {
                                  final checkIn? => () => openCheckInStory(
                                    context,
                                    checkIn: checkIn,
                                    viewerId: widget.viewerId,
                                    backend: widget.backend,
                                  ),
                                  null => null,
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  _trailing(showEmpty),
                ],
              ),
      ),
    ];
    return Scaffold(
      backgroundColor: context.canvas,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              edgeOffset: top,
              onRefresh: _refresh,
              color: WeekPactColors.black,
              backgroundColor: WeekPactColors.cream,
              child: ListView.builder(
                key: const ValueKey('notifications-list'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  12,
                  top + 16,
                  12,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => items[index],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [entries], newest first, cut into runs that share a
  /// [notificationSection].
  static List<(String, List<NotificationEntry>)> _sections(
    List<NotificationEntry> entries,
  ) {
    final now = DateTime.now();
    final out = <(String, List<NotificationEntry>)>[];
    for (final e in entries) {
      final l = notificationSection(e.createdAt.toLocal(), now);
      if (out.isEmpty || out.last.$1 != l) out.add((l, []));
      out.last.$2.add(e);
    }
    return out;
  }

  Widget _trailing(bool showEmpty) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              'Could not load notifications.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ink),
            ),
            TextButton(
              onPressed: () => unawaited(_loadMore()),
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      );
    }
    if (showEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Text(
              'Nothing yet.',
              style: TextStyle(
                color: context.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check-ins, claps and nudges from your crews land here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted),
            ),
          ],
        ),
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Loading more notifications',
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'That’s everything',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.muted),
      ),
    );
  }
}

/// One notification: who, what, which crew, and how long ago.
///
/// An unread one carries a dot rather than a different background, because the
/// list is read top to bottom and a block of tinted rows says less about what
/// is new than one mark against each does.
/// A section's name over its notices: small spaced capitals in the muted ink.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .9,
        ),
      ),
    ),
  );
}

/// All the crews, then one tab per crew, each with how many of its notices
/// are new. Scrolls sideways once there are more than fit.
class _CrewTabs extends StatelessWidget {
  const _CrewTabs({
    required this.crews,
    required this.selected,
    required this.unread,
    required this.all,
    required this.onSelected,
  });

  final List<({String id, String name})> crews;
  final String? selected;
  final Map<String, int> unread;
  final int all;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      children: [
        _tab(context, null, 'All', all),
        for (final c in crews) ...[
          const SizedBox(width: 6),
          _tab(context, c.id, c.name, unread[c.id] ?? 0),
        ],
      ],
    ),
  );

  Widget _tab(BuildContext context, String? id, String name, int count) {
    final on = id == selected;
    return Semantics(
      button: true,
      selected: on,
      label: count > 0 ? '$name, $count new' : name,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('notifications-tab-${id ?? 'all'}'),
        onTap: () => onSelected(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: ShapeDecoration(
            color: on
                ? WeekPactColors.cream
                : context.ink.withValues(alpha: .06),
            shape: ContinuousRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              side: BorderSide(
                color: on
                    ? WeekPactColors.cream
                    : context.ink.withValues(alpha: .12),
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: on ? WeekPactColors.black : context.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: WeekPactColors.salmon,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: WeekPactColors.black,
                      fontSize: 10.5,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One notice: who, with a badge on their face saying what happened, the
/// sentence with the pact as a chip in its own colours, and where and when.
/// A notice that is new this visit wears a warm wash and a dot.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.entry,
    required this.fresh,
    required this.showCrew,
    this.onTap,
  });

  final NotificationEntry entry;
  final bool fresh;

  /// What a tap opens; null for a notice with nothing behind it.
  final VoidCallback? onTap;

  /// Whether to say which crew it came from: not when the list is already
  /// cut to one crew, or there is only one.
  final bool showCrew;

  @override
  Widget build(BuildContext context) {
    final when = _ago(entry.createdAt.toLocal());
    // Its own node, so a section of rows is read one notice at a time
    // rather than run together.
    return Semantics(
      container: true,
      button: onTap != null,
      label:
          '${entry.subject} ${entry.action} · ${entry.crewName} · $when'
          '${fresh ? ' · unread' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: fresh
                  ? LinearGradient(
                      colors: [
                        WeekPactColors.salmon.withValues(alpha: .12),
                        WeekPactColors.salmon.withValues(alpha: 0),
                      ],
                      stops: const [0, .7],
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BadgedAvatar(entry: entry),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: entry.subject,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ..._action(),
                            ],
                          ),
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 14.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          showCrew ? '${entry.crewName} · $when' : when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: WeekPactType.secondary,
                            fontFamilyFallback: WeekPactType.secondaryFallback,
                            color: context.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fresh) ...[
                    const SizedBox(width: 10),
                    Container(
                      key: const ValueKey('notification-unread-dot'),
                      margin: const EdgeInsets.only(top: 6),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: WeekPactColors.salmon,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What they did, with the pact drawn as a chip where there is one.
  List<InlineSpan> _action() {
    if (entry.pactTitle != null) {
      final chip = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _PactChip(entry: entry),
      );
      switch (entry.type) {
        case 'check_in_clapped':
          return [
            const TextSpan(text: ' clapped your '),
            chip,
            const TextSpan(text: ' check-in'),
          ];
        case 'pact_completed':
          return [const TextSpan(text: ' completed '), chip];
      }
    }
    return [TextSpan(text: ' ${entry.action}')];
  }

  static String _ago(DateTime at) {
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
    if (gap.inHours < 24) return '${gap.inHours}h ago';
    if (gap.inDays < 7) return '${gap.inDays}d ago';
    return '${(gap.inDays / 7).floor()}w ago';
  }
}

/// The pact, in the sentence, as the pact card in miniature: its tint with
/// its own badge. A pact whose colour the server did not send is drawn in a
/// neutral wash instead.
class _PactChip extends StatelessWidget {
  const _PactChip({required this.entry});

  final NotificationEntry entry;

  static const _shape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    final index = entry.pactIndex;
    final tint = index == null
        ? context.ink.withValues(alpha: .1)
        : WeekPactColors.pactTint(index);
    final badge = index == null
        ? context.ink.withValues(alpha: .14)
        : WeekPactColors.pactBadge(index);
    final ink = index == null ? context.ink : WeekPactColors.black;
    return Container(
      key: ValueKey('notification-pact-${entry.eventId}'),
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
      decoration: ShapeDecoration(color: tint, shape: _shape),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: ShapeDecoration(color: badge, shape: _shape),
            child: Center(
              child: HugeIcon(
                icon: PactIcon.find(entry.iconKey ?? '').data,
                color: ink,
                size: 11,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              entry.pactTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The person's face with a corner badge saying what happened: a heart in
/// brass for a clap, the trophy or the camera for an achievement or a story,
/// the sun for a nudge, and the pact's own badge for a pact finished.
class _BadgedAvatar extends StatelessWidget {
  const _BadgedAvatar({required this.entry});

  final NotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final (glyph, color) = switch (entry.type) {
      'check_in_clapped' => (HugeIconsStrokeRounded.favourite, clapInk),
      'achievement_clapped' => (
        achievementIcon,
        WeekPactColors.achievementBadge,
      ),
      'story_clapped' => (
        HugeIconsStrokeRounded.camera02,
        WeekPactColors.storyBadge,
      ),
      'crew_nudge' => (HugeIconsStrokeRounded.sun01, WeekPactColors.lantern),
      _ => (
        PactIcon.find(entry.iconKey ?? '').data,
        entry.pactIndex == null
            ? WeekPactColors.stone
            : WeekPactColors.pactBadge(entry.pactIndex!),
      ),
    };
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _Avatar(entry: entry),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              key: ValueKey('notification-badge-${entry.eventId}'),
              width: 20,
              height: 20,
              decoration: ShapeDecoration(
                color: color,
                shape: ContinuousRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  // Cut out of the card it sits on, so it reads as a badge on
                  // the face rather than a sticker beside it.
                  side: BorderSide(color: context.surface, width: 2),
                ),
              ),
              child: Center(
                child: HugeIcon(
                  icon: glyph,
                  color: WeekPactColors.black,
                  size: 11,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry});
  final NotificationEntry entry;

  @override
  Widget build(BuildContext context) => FlatAvatar(
    radius: 18,
    backgroundColor: context.ink.withValues(alpha: .12),
    child: AvatarClip(
      child: entry.avatarUrl == null
          ? Text(entry.initials, style: TextStyle(color: context.ink))
          : Image.network(
              entry.avatarUrl!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Text(entry.initials, style: TextStyle(color: context.ink)),
            ),
    ),
  );
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading notifications',
    liveRegion: true,
    child: ExcludeSemantics(
      // Drawn as the list draws a day: its label, then one surface of rows.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 10),
            child: SkeletonBar(width: 48, height: 9),
          ),
          AppSurface(
            borderRadius: 18,
            builder: (context) => Column(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 64,
                      color: context.ink.withValues(alpha: .08),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(width: 36, height: 36, radius: 12),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBar(height: 13),
                              SizedBox(height: 8),
                              SkeletonBar(width: 90, height: 9),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

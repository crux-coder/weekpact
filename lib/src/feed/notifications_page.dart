import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_page_layout.dart';
import '../home/home_backend.dart';
import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';

/// Opens the list and reports how many notifications are still unread when it
/// closes, so the badge behind it settles without a second round trip. Backing
/// out with the system gesture reports nothing, and the caller reads the count
/// itself rather than the page holding the gesture hostage to answer.
Future<int?> showNotificationsPage(
  BuildContext context, {
  required HomeBackend backend,
}) => Navigator.of(context).push<int>(
  MaterialPageRoute(builder: (_) => NotificationsPage(backend: backend)),
);

/// Everything the crew has told this person, newest first.
///
/// The page reads itself in pages keyed on the last entry, the way the feed
/// does, so a notification arriving mid-scroll cannot shift what is below the
/// fold. Opening it marks read only as far as the first page reached: anything
/// that lands while it is open is still unread when it closes.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.backend});

  final HomeBackend backend;

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

  /// What the badge should read once this page closes. It is the count the
  /// server had, less what opening the page cleared.
  int _unread = 0;

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
    });
    await _markRead();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final page = await _read(before: _entries.lastOrNull);
    if (page == null || !mounted) return;
    setState(() => _entries.addAll(page));
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

  @override
  Widget build(BuildContext context) {
    final showEmpty = _loaded && _entries.isEmpty && !_failed;
    return Scaffold(
      backgroundColor: context.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: WeekPactColors.black,
              backgroundColor: WeekPactColors.cream,
              child: ListView.builder(
                key: const ValueKey('notifications-list'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                // Heading, entries, then the trailing status row.
                itemCount: _entries.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: WeekPactMetrics.sectionGap,
                      ),
                      child: CrewPageHeading(
                        title: 'Notifications',
                        dotColor: WeekPactColors.lime,
                        actions: [
                          IconButton(
                            tooltip: 'Close notifications',
                            onPressed: () =>
                                Navigator.of(context).pop(_unread),
                            icon: const AppIcon(
                              icon: HugeIconsStrokeRounded.cancel01,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (index == _entries.length + 1) {
                    return _trailing(showEmpty);
                  }
                  final entry = _entries[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NotificationRow(
                      key: ValueKey('notification-${entry.eventId}'),
                      entry: entry,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
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
    if (_loading && _entries.isEmpty) return const _NotificationsSkeleton();
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
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({super.key, required this.entry});

  final NotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final when = _ago(entry.createdAt.toLocal());
    return AppSurface(
      borderRadius: 16,
      builder: (context) => Semantics(
        label: '${entry.subject} ${entry.action} · ${entry.crewName} · $when'
            '${entry.read ? '' : ' · unread'}',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(entry: entry),
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
                            TextSpan(text: ' ${entry.action}.'),
                          ],
                        ),
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          HugeIcon(
                            icon: _glyph(entry),
                            color: context.muted,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              entry.crewName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: WeekPactType.secondary,
                                fontFamilyFallback:
                                    WeekPactType.secondaryFallback,
                                color: context.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            ' · $when',
                            style: TextStyle(
                              fontFamily: WeekPactType.secondary,
                              fontFamilyFallback: WeekPactType.secondaryFallback,
                              color: context.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!entry.read) ...[
                  const SizedBox(width: 10),
                  Container(
                    key: const ValueKey('notification-unread-dot'),
                    margin: const EdgeInsets.only(top: 5),
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
    );
  }

  /// A clap and a nudge have no pact of their own to stand for, so they wear
  /// the gesture; a check-in wears the pact it was.
  static List<List<dynamic>> _glyph(NotificationEntry entry) =>
      switch (entry.type) {
        'check_in_clapped' => HugeIconsStrokeRounded.favourite,
        'crew_nudge' => HugeIconsStrokeRounded.sun01,
        _ => PactIcon.find(entry.iconKey ?? '').data,
      };

  static String _ago(DateTime at) {
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
    if (gap.inHours < 24) return '${gap.inHours}h ago';
    if (gap.inDays < 7) return '${gap.inDays}d ago';
    return '${(gap.inDays / 7).floor()}w ago';
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
      child: Column(
        children: List.generate(
          4,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSurface(
              borderRadius: 16,
              builder: (context) => const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(width: 36, height: 36, radius: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBar(height: 14),
                          SizedBox(height: 8),
                          SkeletonBar(width: 120, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

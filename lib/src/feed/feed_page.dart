import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_page_layout.dart';
import '../home/check_in_photo_frame.dart';
import '../home/home_backend.dart';
import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';
import 'clap_control.dart';
import 'notifications_page.dart';

/// Check-ins from every crew the member belongs to, newest first, as a photo
/// feed. Paging is keyed on the last entry, so new posts never shift a page.
class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
    required this.backend,
    required this.userId,
    this.active = true,
  });

  final HomeBackend backend;
  final String userId;
  final bool active;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _pageSize = 12;
  final _scroll = ScrollController();
  final _entries = <FeedEntry>[];
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = true;
  bool _failed = false;

  /// What the bell wears. A failed count leaves the badge as it was rather
  /// than claiming the crew has gone quiet.
  int _unread = 0;
  bool _notificationsOpen = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    unawaited(_loadMore());
    unawaited(_countUnread());
  }

  @override
  void didUpdateWidget(covariant FeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Returning to the tab should show check-ins posted since it was left.
    if (widget.active && !oldWidget.active && !_loading) {
      unawaited(_refresh());
      unawaited(_countUnread());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _loadNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600 && !_failed) {
      unawaited(_loadMore());
    }
  }

  Future<void> _countUnread() async {
    try {
      final unread = await widget.backend.fetchUnreadNotificationCount();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      // The feed is the page; the badge is not worth an error state.
    }
  }

  /// The list hands back what is still unread when it closes, so the badge
  /// settles on the way out instead of on the next read. Backing out with the
  /// system gesture answers nothing, and the count is read again instead.
  Future<void> _openNotifications() async {
    setState(() => _notificationsOpen = true);
    final remaining = await showNotificationsPage(
      context,
      backend: widget.backend,
    );
    if (!mounted) return;
    setState(() {
      _notificationsOpen = false;
      if (remaining != null) _unread = remaining;
    });
    if (remaining == null) await _countUnread();
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

  /// Claps or unclaps one post. The tally moves first and the write follows,
  /// so the tap lands immediately; a failure puts the post back as it was.
  Future<void> _clap(FeedEntry entry, bool clapped) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0 || _entries[index].clapped == clapped) return;
    final before = _entries[index];
    _replace(
      entry.id,
      before.copyWith(
        clapped: clapped,
        clapCount: math.max(0, before.clapCount + (clapped ? 1 : -1)),
      ),
    );
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    try {
      final count = await widget.backend.setClap(
        pactId: entry.pactId,
        userId: entry.userId,
        day: entry.day,
        clapped: clapped,
      );
      if (!mounted) return;
      // The server's count includes claps from other members since the page
      // was read, so it replaces the guess rather than adding to it.
      final at = _entries.indexWhere((e) => e.id == entry.id);
      if (at >= 0) {
        _replace(
          entry.id,
          _entries[at].copyWith(clapCount: count, clapped: clapped),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _replace(entry.id, before);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(clapped ? 'Could not clap.' : 'Could not unclap.'),
        ),
      );
    }
  }

  void _replace(String id, FeedEntry entry) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    setState(() => _entries[index] = entry);
  }

  /// Returns null when the read failed; state carries the error either way.
  Future<List<FeedEntry>?> _read({FeedEntry? before}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.backend.fetchFeed(
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
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: () {
              unawaited(
                HapticFeedback.mediumImpact().catchError((Object _) {}),
              );
              return _refresh();
            },
            // The indicator disc is cream in both themes, so its arrow stays
            // dark rather than following the canvas ink.
            color: WeekPactColors.black,
            backgroundColor: WeekPactColors.cream,
            child: ListView.builder(
              key: const ValueKey('feed-list'),
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
                      title: 'Feed',
                      dotColor: WeekPactColors.lime,
                      actions: [
                        IconButton(
                          tooltip: 'Notifications',
                          onPressed: _notificationsOpen
                              ? null
                              : () => unawaited(_openNotifications()),
                          icon: Badge(
                            key: const ValueKey('feed-notifications-badge'),
                            isLabelVisible: _unread > 0,
                            label: Text(_unread > 99 ? '99+' : '$_unread'),
                            backgroundColor: WeekPactColors.salmon,
                            textColor: WeekPactColors.black,
                            child: const AppIcon(
                              icon: HugeIconsStrokeRounded.notification02,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (index == _entries.length + 1) return _trailing(showEmpty);
                final entry = _entries[index - 1];
                final previous = index >= 2 ? _entries[index - 2] : null;
                final date = entry.createdAt.toLocal();
                final startsDay =
                    previous == null ||
                    !DateUtils.isSameDay(date, previous.createdAt.toLocal());
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (startsDay) _DayHeading(date: date),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FeedPost(
                        key: ValueKey('feed-post-${entry.id}'),
                        entry: entry,
                        isMine: entry.userId == widget.userId,
                        onClap: (clapped) => _clap(entry, clapped),
                      ),
                    ),
                  ],
                );
              },
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
              'Could not load the feed.',
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
    if (_loading && _entries.isEmpty) return const _FeedSkeleton();
    if (showEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Text(
              'No check-ins yet.',
              style: TextStyle(
                color: context.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos from every crew you’re in land here.',
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
              semanticsLabel: 'Loading more check-ins',
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'You’re all caught up',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.muted),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final label = DateUtils.isSameDay(date, today)
        ? 'Today'
        : DateUtils.isSameDay(date, yesterday)
        ? 'Yesterday'
        : '${MaterialLocalizations.of(context).formatMediumDate(date)}'
              '${date.year == today.year ? '' : ', ${date.year}'}';
    return Semantics(
      header: true,
      child: Padding(
        key: ValueKey(
          'feed-date-${DateUtils.dateOnly(date).toIso8601String()}',
        ),
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: context.muted,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: context.ink.withValues(alpha: .12))),
          ],
        ),
      ),
    );
  }
}

/// A single check-in: who kept it and when at the top, the photo in the
/// middle in the same squircle the check-in camera uses, and the pact and crew
/// beneath. The card is offblack so the photo is the only bright thing on it.
///
/// Double-tapping the post claps for it; the tally at the foot takes the clap
/// back. A double tap on a post already clapped replays the burst and leaves
/// the one clap where it is, so the gesture never quietly undoes itself.
class FeedPost extends StatefulWidget {
  const FeedPost({
    super.key,
    required this.entry,
    this.isMine = false,
    this.onClap,
  });

  final FeedEntry entry;
  final bool isMine;

  /// Asked to clap (true) or take the clap back (false). Null means the post
  /// cannot be clapped at all.
  final void Function(bool clapped)? onClap;

  @override
  State<FeedPost> createState() => _FeedPostState();
}

class _FeedPostState extends State<FeedPost>
    with SingleTickerProviderStateMixin {
  late final _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// The card gives a little under the double tap while the clap swells over
  /// it — enough to feel answered, not enough to shove its neighbours.
  late final _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: .985,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: .985,
        end: 1.012,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.012,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
  ]).animate(CurvedAnimation(parent: _burst, curve: const Interval(0, .6)));

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _doubleTap() {
    final onClap = widget.onClap;
    if (onClap == null) return;
    if (!MediaQuery.disableAnimationsOf(context)) _burst.forward(from: 0);
    if (!widget.entry.clapped) {
      // The clap itself buzzes as it is written, so only the double tap that
      // changes nothing has to buzz for itself.
      onClap(true);
    } else {
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    }
  }

  /// Everything but the tally answers the double tap, including a photo-free
  /// check-in's text. The tally stays outside it, so tapping the tally lands
  /// at once rather than waiting out the double-tap window.
  Widget _clappable(Widget child) => GestureDetector(
    onDoubleTap: widget.onClap == null ? null : _doubleTap,
    behavior: HitTestBehavior.opaque,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final date = entry.createdAt.toLocal();
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final name = widget.isMine ? 'You' : entry.displayName;
    return ScaleTransition(
      scale: _pop,
      child: _card(context, entry: entry, name: name, time: time),
    );
  }

  Widget _card(
    BuildContext context, {
    required FeedEntry entry,
    required String name,
    required String time,
  }) {
    return AppSurface(
      borderRadius: 16,
      fillColor: WeekPactDarkCard.fill,
      resolveTone: false,
      builder: (context) => Semantics(
        label:
            '$name checked in · ${entry.pactTitle} · ${entry.crewName} · $time',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _clappable(
                ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _Avatar(entry: entry),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WeekPactDarkCard.ink,
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: const TextStyle(
                              fontFamily: WeekPactType.secondary,
                              fontFamilyFallback:
                                  WeekPactType.secondaryFallback,
                              color: WeekPactDarkCard.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                      if (entry.photoPath != null) ...[
                        const SizedBox(height: 12),
                        CheckInPhotoFrame(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _Photo(
                                key: ValueKey('feed-photo-${entry.id}'),
                                url: entry.photoUrl,
                              ),
                              ClapBurst(animation: _burst),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _clappable(
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            // The pact's icon leads its own name, the way the
                            // avatar leads the author's.
                            HugeIcon(
                              icon: PactIcon.find(entry.iconKey).data,
                              color: WeekPactDarkCard.muted,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    entry.pactTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: WeekPactDarkCard.ink,
                                      fontSize: 15,
                                      height: 1.2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    entry.crewName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: WeekPactType.secondary,
                                      fontFamilyFallback:
                                          WeekPactType.secondaryFallback,
                                      fontSize: 11,
                                      height: 1.35,
                                      color: WeekPactDarkCard.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ClapButton(
                    key: ValueKey('feed-clap-${entry.id}'),
                    count: entry.clapCount,
                    clapped: entry.clapped,
                    onPressed: widget.onClap == null
                        ? null
                        : () => widget.onClap!(!entry.clapped),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry});
  final FeedEntry entry;

  @override
  Widget build(BuildContext context) => FlatAvatar(
    radius: 15,
    backgroundColor: WeekPactDarkCard.ink.withValues(alpha: .12),
    child: AvatarClip(
      child: entry.avatarUrl == null
          ? Text(
              entry.initials,
              style: const TextStyle(color: WeekPactDarkCard.ink),
            )
          : Image.network(
              entry.avatarUrl!,
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(
                entry.initials,
                style: const TextStyle(color: WeekPactDarkCard.ink),
              ),
            ),
    ),
  );
}

/// Keeps the photo slot filled while loading, and honest when the signed URL
/// has expired or the image cannot be fetched.
class _Photo extends StatelessWidget {
  const _Photo({super.key, required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _PhotoPlaceholder(failed: true);
    return Image.network(
      url!,
      fit: BoxFit.cover,
      semanticLabel: 'Check-in photo',
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PhotoPlaceholder(),
      errorBuilder: (_, _, _) => const _PhotoPlaceholder(failed: true),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.failed = false});
  final bool failed;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WeekPactDarkCard.ink.withValues(alpha: .08),
    child: Center(
      child: failed
          ? HugeIcon(
              icon: HugeIconsStrokeRounded.image01,
              color: WeekPactDarkCard.ink.withValues(alpha: .35),
              size: 26,
            )
          : const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WeekPactDarkCard.muted,
                semanticsLabel: 'Loading check-in photo',
              ),
            ),
    ),
  );
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('feed-skeleton'),
    children: [
      for (var index = 0; index < 2; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppSurface(
            borderRadius: 16,
            fillColor: WeekPactDarkCard.fill,
            resolveTone: false,
            builder: (context) {
              final bone = WeekPactDarkCard.ink.withValues(alpha: .1);
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SkeletonBar(
                          height: 30,
                          width: 30,
                          shape: const AvatarShape(),
                          color: bone,
                        ),
                        const SizedBox(width: 10),
                        SkeletonBar(height: 12, width: 110, color: bone),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CheckInPhotoFrame(child: ColoredBox(color: bone)),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(height: 12, width: 130, color: bone),
                        const SizedBox(height: 6),
                        SkeletonBar(height: 9, width: 90, color: bone),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
    ],
  );
}

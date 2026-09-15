import '../widgets/avatar_shape.dart';
import '../widgets/raised_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_sheet.dart';
import 'check_in_photo_viewer.dart';

import 'package:flutter/material.dart';

import 'home_backend.dart';
import 'home_surface.dart';
import '../theme/weekpact_theme.dart';

class ActivityHistory extends StatefulWidget {
  const ActivityHistory({
    super.key,
    required this.backend,
    required this.crewId,
    required this.week,
    required this.userId,
  });

  final HomeBackend backend;
  final String crewId;
  final CrewWeek week;
  final String userId;

  @override
  State<ActivityHistory> createState() => _ActivityHistoryState();
}

class _ActivityHistoryState extends State<ActivityHistory> {
  static const _pageSize = 20;
  final _scroll = ScrollController();
  final _entries = <CrewActivity>[];
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _loadNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 240 && !_failed) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.backend.fetchActivity(
        widget.crewId,
        before: _entries.lastOrNull,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
      // Fill tall viewports without requiring a scroll gesture first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNearEnd();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('activity-history'),
    color: WeekPactColors.cream,
    textStyle: Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: homeInk, fontSize: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'RECENT CHECK-INS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF555B55),
              ),
            ),
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _loading
                        ? const _ActivityLoading()
                        : _failed
                        ? _retry()
                        : const Text(
                            'No activity yet.\nYour crew’s check-ins will appear here.',
                            textAlign: TextAlign.center,
                          ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('activity-history-list'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: _entries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _entries.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _failed
                            ? _retry()
                            : _hasMore
                            ? const _ActivityLoading()
                            : const Text(
                                'You’re all caught up',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF555B55)),
                              ),
                      );
                    }
                    final activity = _entries[index];
                    final date = activity.createdAt.toLocal();
                    final startsDay =
                        index == 0 ||
                        !DateUtils.isSameDay(
                          date,
                          _entries[index - 1].createdAt.toLocal(),
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (startsDay) _dateHeading(context, date),
                        _entry(context, activity),
                      ],
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _dateHeading(BuildContext context, DateTime date) {
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
          'activity-date-${DateUtils.dateOnly(date).toIso8601String()}',
        ),
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF555B55),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: homeInk.withValues(alpha: .1))),
          ],
        ),
      ),
    );
  }

  Widget _retry() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Could not load activity.', textAlign: TextAlign.center),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: homeInk),
        onPressed: _loadMore,
        child: const Text('Try again'),
      ),
    ],
  );

  Widget _entry(BuildContext context, CrewActivity activity) {
    final member = widget.week.members
        .where((member) => member.id == activity.userId)
        .firstOrNull;
    final name = activity.userId == widget.userId
        ? 'You'
        : member == null || member.displayName.trim().isEmpty
        ? 'A crew member'
        : member.displayName.trim();
    final title =
        activity.pactTitle ??
        widget.week.pacts
            .where((pact) => pact.id == activity.pactId)
            .firstOrNull
            ?.title ??
        'Pact';
    final date = activity.createdAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      key: ValueKey(
        'activity-${activity.pactId}-${activity.userId}-${activity.completedOn}',
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE1E5DC),
            child: AvatarClip(
              child: member?.avatarUrl == null
                  ? Text(
                      member?.initials ?? '?',
                      style: const TextStyle(color: homeInk),
                    )
                  : Image.network(
                      member!.avatarUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Text(
                        member.initials,
                        style: const TextStyle(color: homeInk),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '$name checked in',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF555B55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title),
                if (activity.photoPath != null)
                  TextButton.icon(
                    onPressed: () => showAppSheet<void>(
                      context: context,
                      builder: (_) => CheckInPhotoViewer(
                        backend: widget.backend,
                        path: activity.photoPath!,
                        title: title,
                      ),
                    ),
                    icon: const RaisedIcon(
                      icon: HugeIconsStrokeRounded.image01,
                      size: 18,
                    ),
                    label: const Text('VIEW PHOTO'),
                    style: TextButton.styleFrom(
                      foregroundColor: homeInk,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: homeInk,
        semanticsLabel: 'Loading activity',
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import 'home_backend.dart';
import 'stories.dart';
import 'story_viewer.dart';

/// Opens [checkIn] as a story, the way the rail would: what a tap on a
/// notification about a check-in, or on its push, leads to.
///
/// The page is up at once and reads the check-in behind its own dark screen,
/// so the tap answers before the network does.
Future<void> openCheckInStory(
  BuildContext context, {
  required CheckInRef checkIn,
  required String viewerId,
  required HomeBackend backend,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => CheckInStoryPage(
      checkIn: checkIn,
      viewerId: viewerId,
      backend: backend,
    ),
  ),
);

/// One check-in's story, read from the crew's week around it.
class CheckInStoryPage extends StatefulWidget {
  const CheckInStoryPage({
    super.key,
    required this.checkIn,
    required this.viewerId,
    required this.backend,
  });

  final CheckInRef checkIn;
  final String viewerId;
  final HomeBackend backend;

  /// The member's day holding [checkIn] in [week], or null when the check-in
  /// is not there: taken back since, or its pact or member gone.
  static MemberDay? read(CrewWeek week, CheckInRef checkIn, String viewerId) {
    final at = week.pacts.indexWhere((p) => p.id == checkIn.pactId);
    final kept = week.checkIns.where(checkIn.matches).firstOrNull;
    final member = week.members
        .where((m) => m.id == checkIn.userId)
        .firstOrNull;
    if (at < 0 || kept == null || member == null) return null;
    final pact = week.pacts[at];
    return MemberDay(
      member: member,
      stories: [
        PactStory(
          checkIn: kept,
          pact: pact,
          tint: WeekPactColors.pactTint(at),
          badge: WeekPactColors.pactBadge(at),
          week: StoryWeek.read(
            // Read as of the check-in's own day, so the tally marks it as
            // the day the story is about.
            CrewWeek(
              today: checkIn.day,
              weekStart: week.weekStart,
              timezone: week.timezone,
              pacts: week.pacts,
              members: week.members,
              checkIns: week.checkIns,
            ),
            pact,
            member.id,
          ),
        ),
      ],
      seen: false,
      isViewer: member.id == viewerId,
    );
  }

  @override
  State<CheckInStoryPage> createState() => _CheckInStoryPageState();
}

class _CheckInStoryPageState extends State<CheckInStoryPage> {
  /// The day once read; null while reading, and after a read that failed or
  /// found nothing, which [_missing] tells apart.
  MemberDay? _day;
  bool _failed = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _missing = false;
    });
    try {
      final week = await widget.backend.fetchCheckInWeek(widget.checkIn);
      if (!mounted) return;
      final day = CheckInStoryPage.read(week, widget.checkIn, widget.viewerId);
      setState(() {
        _day = day;
        _missing = day == null;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    if (day != null) {
      return StoryViewer(
        days: [day],
        viewerId: widget.viewerId,
        backend: widget.backend,
      );
    }
    final waiting = !_failed && !_missing;
    return Scaffold(
      key: const ValueKey('check-in-story-loading'),
      backgroundColor: WeekPactColors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: waiting
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WeekPactColors.cream,
                        semanticsLabel: 'Loading check-in',
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _missing
                                ? 'This check-in is no longer here.'
                                : 'Could not load this check-in.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: WeekPactColors.cream,
                              fontSize: 16,
                            ),
                          ),
                          if (_failed)
                            TextButton(
                              onPressed: _load,
                              child: const Text('TRY AGAIN'),
                            ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const AppIcon(
                  icon: HugeIconsStrokeRounded.cancel01,
                  color: WeekPactColors.cream,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

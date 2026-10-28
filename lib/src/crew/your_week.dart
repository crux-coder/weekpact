import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/pact_icon_badge.dart';
import 'crew_switcher.dart';

/// Where one of the viewer's pacts stands this week.
enum PactPaceState {
  /// Kept as many days as the pact asks.
  done,

  /// More days left than days still to keep.
  onTrack,

  /// Every day left has to be a kept one.
  everyDay,

  /// Not enough days left to finish it.
  outOfReach,
}

/// One of the viewer's pacts, as the week has gone so far.
class PactPace {
  const PactPace({
    required this.pact,
    required this.kept,
    required this.openDays,
  });

  final CrewPact pact;

  /// Days kept this week, never more than the pact asks: a sixth day on a
  /// five-day pact is not counted twice.
  final int kept;

  /// The days left on which this pact can still be kept: the rest of the
  /// week, and today while it is still open.
  final int openDays;

  int get goal => pact.daysPerWeek;
  int get toGo => goal - kept;

  PactPaceState get state => toGo <= 0
      ? PactPaceState.done
      : toGo > openDays
      ? PactPaceState.outOfReach
      : toGo == openDays
      ? PactPaceState.everyDay
      : PactPaceState.onTrack;
}

/// The podium's headline: where the viewer stands, and what would move it.
class PodiumLine {
  const PodiumLine(this.title, this.detail, {required this.mood});
  final String title;
  final String detail;

  /// How the line feels, which picks the colour and icon it is drawn with.
  final PodiumMood mood;

  @override
  String toString() => '$title · $detail';
}

/// The feel of a podium headline: one per situation [YourWeek.headline]
/// tells apart, so a lead, a chase and a finished week each look like what
/// they are rather than like the same line of grey text.
enum PodiumMood {
  /// A week nobody has started.
  fresh,

  /// The viewer has kept everything.
  done,

  /// A crew of one, partway through.
  going,

  /// The whole crew on one figure.
  level,

  /// The lead, shared.
  sharedLead,

  /// The lead, alone.
  leading,

  /// The last day, a check-in or two off the lead.
  lastDay,

  /// One check-in off the lead.
  close,

  /// Last place.
  behind,

  /// Somewhere in the middle.
  climbing,
}

/// The viewer's own week in one crew: what the podium cannot say about one
/// person. Worked out from the week the page already has, so it needs nothing
/// from the server of its own.
class YourWeek {
  YourWeek(this.week, this.userId);

  final CrewWeek week;
  final String userId;

  int get completed => week.completed(userId);
  int get target => week.target;

  /// The week's seven days, Monday first, and whether the viewer kept
  /// anything on each.
  late final List<bool> keptDays = [
    for (final day in week.weekDays)
      week.checkIns.any((i) => i.userId == userId && i.day == day),
  ];

  /// Today's place in the week, Monday being 0.
  int get todayIndex => math.max(0, week.weekDays.indexOf(week.today));

  /// The days left in the week, today among them.
  int get daysLeft => 7 - todayIndex;

  late final List<PactPace> pacts = [
    for (final pact in week.pacts)
      PactPace(
        pact: pact,
        kept: math.min(pact.daysPerWeek, week.days(pact.id, userId)),
        openDays:
            6 -
            todayIndex +
            (week.checkedToday(userId).contains(pact.id) ? 0 : 1),
      ),
  ];

  /// How many claps the viewer's check-ins this week have had.
  int get claps => week.checkIns
      .where(
        (i) =>
            i.userId == userId &&
            i.day.compareTo(week.weekStart) >= 0 &&
            i.day.compareTo(week.today) <= 0,
      )
      .fold(0, (sum, i) => sum + i.clapCount);

  /// The viewer's place, or null in a crew of one, where a place says
  /// nothing.
  CrewStanding? get standing => week.members.length < 2
      ? null
      : week.standings(userId).where((s) => s.isViewer).firstOrNull;

  /// What the place line says next to the place: who is next to pass and by
  /// how much, or by how much the viewer leads.
  String? get placeNote {
    final mine = standing;
    if (mine == null) return null;
    final others = week.members.where((m) => m.id != userId).toList();
    if (mine.place == 1) {
      // Whoever is next: everyone on the best count after the viewer's own,
      // which is the viewer's own count when the lead is shared.
      final best = others.map((m) => week.completed(m.id)).fold(0, math.max);
      final next = _names(others.where((m) => week.completed(m.id) == best));
      final lead = completed - best;
      return lead == 0
          ? 'Tied with $next'
          : '$lead ${lead == 1 ? 'check-in' : 'check-ins'} ahead of $next';
    }
    // The member just above: the fewest check-ins still more than the
    // viewer's. Passing them takes one more than the gap.
    final above = others.where((m) => week.completed(m.id) > completed).toList()
      ..sort((a, b) => week.completed(a.id).compareTo(week.completed(b.id)));
    final next = above.firstOrNull;
    if (next == null) return null;
    final need = week.completed(next.id) - completed + 1;
    return '$need ${need == 1 ? 'check-in' : 'check-ins'} to pass ${_firstName(next)}';
  }

  /// What the podium's headline says about the viewer's place: one line on
  /// the week and one on what would change it.
  ///
  /// The situations are read in order and the first that fits is the one
  /// said, so two never compete: a week nobody has started, a crew all on
  /// one figure, a week the viewer has finished, a shared lead, a lead, a
  /// close race on the last day, one behind the lead, last place, and
  /// anywhere in between. It speaks to the viewer alone, and when it names
  /// somebody it is the one just ahead or just behind, never the whole table.
  PodiumLine get headline {
    final others = week.members.where((m) => m.id != userId).toList();
    String count(int n) => '$n ${n == 1 ? 'check-in' : 'check-ins'}';
    if (others.isEmpty) {
      final left = target - completed;
      return completed == 0
          ? const PodiumLine(
              'Fresh week',
              'Your first check-in starts it',
              mood: PodiumMood.fresh,
            )
          : left <= 0
          ? const PodiumLine(
              'Week done',
              'Every pact kept',
              mood: PodiumMood.done,
            )
          : PodiumLine(
              '${week.percent(userId)}% of your week',
              '${count(left)} to go',
              mood: PodiumMood.going,
            );
    }
    int of(WeekMember m) => week.completed(m.id);
    if (completed == 0 && others.every((m) => of(m) == 0)) {
      return PodiumLine(
        todayIndex == 0 ? 'Fresh week' : 'Nobody’s on the board yet',
        'The first check-in takes the lead',
        mood: PodiumMood.fresh,
      );
    }
    if (target > 0 && completed >= target) {
      return const PodiumLine(
        'Week done',
        'Every pact kept. Cheer the rest on',
        mood: PodiumMood.done,
      );
    }
    if (others.every((m) => of(m) == completed)) {
      return PodiumLine(
        'All square',
        'The whole crew is on ${week.percent(userId)}%',
        mood: PodiumMood.level,
      );
    }
    final best = others.map(of).fold(0, math.max);
    if (completed == best) {
      final tied = others.where((m) => of(m) == best);
      return PodiumLine(
        'Neck and neck',
        'You and ${_names(tied)} share the top',
        mood: PodiumMood.sharedLead,
      );
    }
    if (completed > best) {
      final next = _names(others.where((m) => of(m) == best));
      return PodiumLine(
        'You’re out in front',
        '${count(completed - best)} ahead of $next',
        mood: PodiumMood.leading,
      );
    }
    final behind = best - completed;
    final leader = _firstName(others.firstWhere((m) => of(m) == best));
    if (daysLeft == 1 && behind <= 2) {
      return PodiumLine(
        'Last day, $behind behind',
        '${behind == 1 ? 'One check-in ties' : 'Two check-ins tie'} it with $leader',
        mood: PodiumMood.lastDay,
      );
    }
    if (behind == 1) {
      return PodiumLine(
        'Right on $leader’s heels',
        'One check-in ties the lead',
        mood: PodiumMood.close,
      );
    }
    // The one to pass: the fewest check-ins still more than the viewer's.
    final above = others.where((m) => of(m) > completed).toList()
      ..sort((a, b) => of(a).compareTo(of(b)));
    final next = above.first;
    final pass =
        '${count(of(next) - completed + 1)} to pass ${_firstName(next)}';
    if (others.every((m) => of(m) > completed)) {
      return PodiumLine(
        daysLeft >= 3 ? 'Plenty of week left' : 'Still time',
        pass,
        mood: PodiumMood.behind,
      );
    }
    return PodiumLine(
      'You’re ${_ordinal(standing!.place)} of ${week.members.length}',
      pass,
      mood: PodiumMood.climbing,
    );
  }

  static String _firstName(WeekMember member) {
    final name = member.displayName.trim();
    if (name.isEmpty || name == 'Crew member') return 'a crewmate';
    return name.split(RegExp(r'\s+')).first;
  }

  /// [members] by first name, as a line has room for: one or two names, or
  /// the first and how many more.
  static String _names(Iterable<WeekMember> members) {
    final names = members.map(_firstName).toList();
    return switch (names.length) {
      0 => 'the crew',
      1 => names.first,
      2 => '${names.first} and ${names.last}',
      _ => '${names.first} and ${names.length - 1} others',
    };
  }
}

const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _ordinal(int place) =>
    '$place${switch (place % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (place % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    }}';

/// The viewer's card under the podium: their headline on top — where they
/// stand and what would move it ([YourWeek.headline]) — and under a rule
/// their seven days and how many check-ins of the week's they have.
///
/// The two stood as separate cards, which read as two unrelated things about
/// the same person. The whole card is one tap, into [YourWeekSheet], where
/// the rest of their week is.
class YourWeekPanel extends StatelessWidget {
  const YourWeekPanel({super.key, required this.week, required this.userId});

  /// The loading state: the same card, its badge and lines not yet filled.
  const YourWeekPanel.loading({super.key}) : week = null, userId = '';

  final CrewWeek? week;
  final String userId;

  static const _headline = 54.0;
  static const _rule = 1.0;
  static const _row = 40.0;

  static const height = _headline + _rule + _row;

  @override
  Widget build(BuildContext context) {
    final crew = week;
    final mine = crew == null ? null : YourWeek(crew, userId);
    final line = mine?.headline;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headline,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: _scaledDown(
              Align(
                alignment: Alignment.centerLeft,
                child: line == null
                    ? const _HeadlineLoading()
                    : _Headline(line),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ColoredBox(
            key: const ValueKey('your-week-rule'),
            color: context.ink.withValues(alpha: .10),
            child: const SizedBox(height: _rule),
          ),
        ),
        SizedBox(
          height: _row,
          child: mine == null
              ? null
              : Padding(
                  // In line with the headline's badge above.
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                  child: _scaledDown(
                    Row(
                      children: [
                        Text(
                          'You',
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 14),
                        for (var i = 0; i < 7; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _Pip(
                            kept: mine.keptDays[i],
                            today: i == mine.todayIndex,
                            future: i > mine.todayIndex,
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${mine.completed} / ${mine.target}',
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        AppIcon(
                          icon: HugeIconsStrokeRounded.arrowRight01,
                          size: 18,
                          color: context.muted,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
    return SizedBox(
      height: height,
      child: CrewHeaderSurface(
        child: mine == null
            ? content
            : Semantics(
                button: true,
                label: 'Your week',
                value:
                    '${line!.title}. ${line.detail}. '
                    '${mine.completed} of ${mine.target} check-ins. '
                    'Opens your breakdown.',
                child: ExcludeSemantics(
                  child: InkWell(
                    key: const ValueKey('your-week-row'),
                    onTap: () {
                      unawaited(
                        HapticFeedback.lightImpact().catchError((Object _) {}),
                      );
                      showYourWeekSheet(
                        context: context,
                        week: crew!,
                        userId: userId,
                        dark: context.isDark,
                      );
                    },
                    child: content,
                  ),
                ),
              ),
      ),
    );
  }
}

/// [child] at its own size when there is room, and scaled down into its box
/// when larger system text would push it out.
Widget _scaledDown(Widget child) => LayoutBuilder(
  builder: (context, box) {
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: box.maxWidth * scale,
        height: box.maxHeight * scale,
        child: child,
      ),
    );
  },
);

/// One of the row's days: filled where the viewer kept something, ringed for
/// today, faint for the days still to come.
class _Pip extends StatelessWidget {
  const _Pip({required this.kept, required this.today, required this.future});
  final bool kept;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: kept
          ? WeekPactColors.keptDay
          : context.ink.withValues(alpha: future ? .06 : .14),
      border: today
          ? Border.all(color: context.ink, width: 2)
          : kept
          ? Border.all(
              color: Color.lerp(WeekPactColors.keptDay, Colors.black, .28)!,
            )
          : null,
    ),
  );
}

Future<void> showYourWeekSheet({
  required BuildContext context,
  required CrewWeek week,
  required String userId,
  bool dark = false,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => YourWeekSheet(week: week, userId: userId, dark: dark),
);

/// The viewer's week, pact by pact: how far along each one is and what it
/// still needs, then where they stand in the crew.
class YourWeekSheet extends StatelessWidget {
  const YourWeekSheet({
    super.key,
    required this.week,
    required this.userId,
    this.dark = false,
  });
  final CrewWeek week;
  final String userId;

  /// Draws the sheet on the dark card surface, for a page in the dark theme:
  /// it opens over the crew's week and reads as part of it, not as a pale
  /// panel dropped on top.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final mine = YourWeek(week, userId);
    final standing = mine.standing;
    final note = mine.placeNote;
    final left = mine.daysLeft;
    return AppSheet(
      dark: dark,
      builder: (context) => Column(
        key: const ValueKey('your-week-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR WEEK',
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close your week',
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
              ),
            ],
          ),
          Text(
            '${_weekdays[mine.todayIndex]} · '
            '${left == 1 ? 'last day' : '$left days left'} · '
            '${mine.completed} of ${mine.target} check-ins',
            style: TextStyle(color: context.muted, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _DayTile(
                    letter: _letters[i],
                    kept: mine.keptDays[i],
                    today: i == mine.todayIndex,
                    future: i > mine.todayIndex,
                  ),
                ),
              ],
            ],
          ),
          if (mine.pacts.isNotEmpty) ...[
            const SizedBox(height: WeekPactMetrics.sectionGap),
            const _SectionLabel('Pace'),
            for (final (index, pace) in mine.pacts.indexed)
              _PaceRow(pace: pace, badge: WeekPactColors.pactBadge(index)),
          ],
          const SizedBox(height: WeekPactMetrics.sectionGap),
          const _SectionLabel('Crew'),
          if (standing != null)
            _FactRow(
              icon: HugeIconsStrokeRounded.ranking,
              label: '${_ordinal(standing.place)} place',
              value: note,
            ),
          _FactRow(
            icon: HugeIconsStrokeRounded.handsClapping,
            label: 'Claps',
            value: mine.claps == 0
                ? 'None yet this week'
                : '${mine.claps} this week',
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    ),
  );
}

/// One of the sheet's days, lettered, in the crew card's day-cell colours.
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.letter,
    required this.kept,
    required this.today,
    required this.future,
  });
  final String letter;
  final bool kept;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final face = kept
        ? WeekPactColors.keptDay
        : today
        // White on the pale sheet, as the crew card's cell; on the dark one a
        // white tile glared, so today is the ring alone over a faint fill.
        ? (context.isDark ? context.ink.withValues(alpha: .10) : Colors.white)
        : context.ink.withValues(alpha: future ? .03 : .06);
    return Column(
      children: [
        Text(
          letter,
          style: TextStyle(
            color: today ? context.ink : context.muted,
            fontSize: 13,
            fontWeight: today ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: face,
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(
                  WeekPactMetrics.curveFor(WeekPactMetrics.controlRadius),
                ),
                side: BorderSide(
                  color: kept
                      ? Color.lerp(WeekPactColors.keptDay, Colors.black, .28)!
                      : today
                      ? context.ink
                      : context.ink.withValues(alpha: future ? .05 : .10),
                  width: today && !kept ? 1.5 : 1,
                ),
              ),
            ),
            child: kept
                ? const Center(
                    child: HugeIcon(
                      icon: HugeIconsStrokeRounded.tick02,
                      size: 18,
                      color: WeekPactColors.black,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _PaceRow extends StatelessWidget {
  const _PaceRow({required this.pace, required this.badge});
  final PactPace pace;
  final Color badge;

  @override
  Widget build(BuildContext context) {
    final (note, color) = switch (pace.state) {
      // The done green is deep enough for the pale sheet; on the dark one
      // the kept day's own green reads instead.
      PactPaceState.done => (
        'Done for the week',
        context.isDark ? WeekPactColors.keptDay : WeekPactColors.doneMark,
      ),
      PactPaceState.onTrack => ('${pace.toGo} to go', context.muted),
      PactPaceState.everyDay => (
        pace.openDays == 1 ? 'Needs the last day' : 'Needs every day left',
        context.isDark
            ? WeekPactColors.lantern
            : Color.lerp(WeekPactColors.warning, Colors.black, .3)!,
      ),
      PactPaceState.outOfReach => ('Out of reach this week', context.muted),
    };
    final done = pace.state == PactPaceState.done;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          PactIconBadge(
            icon: PactIcon.find(pace.pact.iconKey).data,
            tint: badge,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pace.pact.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  note,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: done || pace.state == PactPaceState.everyDay
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (done)
            const _DoneMark()
          else
            Text(
              '${pace.kept} / ${pace.goal}',
              style: TextStyle(
                color: context.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
    return Semantics(
      label:
          '${pace.pact.title}: ${pace.kept} of ${pace.goal} days. '
          '$note.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          // A finished pact sits on the kept day's green, which runs a little
          // past the column either side so its badge and words stay in line
          // with the rows still open.
          child: done
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -8,
                      right: -8,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        key: const ValueKey('pace-done'),
                        decoration: ShapeDecoration(
                          color: WeekPactColors.keptDay.withValues(
                            alpha: context.isDark ? .16 : .45,
                          ),
                          // The panel curve: a card's is deeper than half a
                          // row this short, and pinches its sides in.
                          shape: ContinuousRectangleBorder(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(WeekPactMetrics.panelCurve),
                            ),
                            side: BorderSide(
                              color: context.isDark
                                  ? WeekPactColors.keptDay.withValues(
                                      alpha: .45,
                                    )
                                  : Color.lerp(
                                      WeekPactColors.keptDay,
                                      Colors.black,
                                      .12,
                                    )!,
                            ),
                          ),
                        ),
                      ),
                    ),
                    row,
                  ],
                )
              : row,
        ),
      ),
    );
  }
}

/// A finished pact's mark where its count would stand: the done green, cut to
/// the same squircle as the pact's badge and raised like it, with a tick.
class _DoneMark extends StatelessWidget {
  const _DoneMark();

  static const _size = 28.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: WeekPactColors.doneMark,
      // The badge's corner share, so the two read as one family.
      shape: ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(
          WeekPactMetrics.curveFor(_size * .28),
        ),
      ),
      shadows: [
        BoxShadow(
          color: Color.lerp(WeekPactColors.doneMark, Colors.black, .3)!,
          offset: WeekPactMetrics.raisedOffset,
        ),
      ],
    ),
    child: const SizedBox.square(
      dimension: _size,
      child: Center(
        child: HugeIcon(
          icon: HugeIconsStrokeRounded.tick02,
          size: 18,
          color: Colors.white,
          strokeWidth: 2.5,
        ),
      ),
    ),
  );
}

/// A line about the viewer in the crew, set like a pace row: the icon where
/// the pact's badge stands, and the detail under the label rather than beside
/// it, so a long one such as two names has the row's width to itself.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.label, this.value});
  final List<List<dynamic>> icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 36,
          child: Center(
            child: HugeIcon(icon: icon, size: 22, color: context.ink),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.muted, fontSize: 14),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The podium's headline: the mood's icon on a raised squircle of its colour,
/// the same object a pact's badge is, then where the viewer stands and what
/// would move it, the second line in the mood's colour too.
///
/// It was two lines of ink and grey, which read as a form's caption rather
/// than as news about your week.
class _Headline extends StatelessWidget {
  const _Headline(this.line);
  final PodiumLine line;

  static const _badge = 36.0;

  /// Each mood's colour and icon. Pale tints, so the badge's dark glyph reads
  /// on every one; gold stays the colour of a week fully kept, as on the bars.
  static (Color, List<List<dynamic>>) _look(PodiumMood mood) => switch (mood) {
    PodiumMood.fresh => (WeekPactColors.sky, HugeIconsStrokeRounded.sparkles),
    PodiumMood.done => (WeekPactColors.gold, HugeIconsStrokeRounded.medal01),
    PodiumMood.going => (WeekPactColors.lime, HugeIconsStrokeRounded.flag02),
    PodiumMood.level => (
      WeekPactColors.lavender,
      HugeIconsStrokeRounded.balanceScale,
    ),
    PodiumMood.sharedLead => (
      WeekPactColors.lime,
      HugeIconsStrokeRounded.fire02,
    ),
    PodiumMood.leading => (WeekPactColors.lime, HugeIconsStrokeRounded.crown),
    PodiumMood.lastDay => (
      WeekPactColors.salmon,
      HugeIconsStrokeRounded.alarmClock,
    ),
    PodiumMood.close => (WeekPactColors.lantern, HugeIconsStrokeRounded.fire),
    PodiumMood.behind => (WeekPactColors.sky, HugeIconsStrokeRounded.rocket01),
    PodiumMood.climbing => (
      WeekPactColors.lavender,
      HugeIconsStrokeRounded.chartIncrease,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (tint, icon) = _look(line.mood);
    // The tint itself on the dark card; on the pale one it is too light to
    // read as text, so it is taken most of the way to black.
    final accent = context.isDark ? tint : Color.lerp(tint, Colors.black, .55)!;
    return Row(
      key: ValueKey('podium-headline-${line.mood.name}'),
      children: [
        PactIconBadge(icon: icon, tint: tint, size: _badge),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            key: const ValueKey('podium-headline'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                line.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 18,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                line.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The headline while the week loads: its badge's squircle and two quiet bars
/// where its lines will be.
class _HeadlineLoading extends StatelessWidget {
  const _HeadlineLoading();

  @override
  Widget build(BuildContext context) {
    final fill = context.ink.withValues(alpha: .08);
    return Row(
      children: [
        // The badge's place, cut to its squircle.
        DecoratedBox(
          decoration: ShapeDecoration(
            color: fill,
            shape: ContinuousRectangleBorder(
              borderRadius: BorderRadius.circular(
                WeekPactMetrics.curveFor(_Headline._badge * .28),
              ),
            ),
          ),
          child: const SizedBox.square(dimension: _Headline._badge),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (width, height) in const [
              (140.0, 15.0),
              (190.0, 10.0),
            ]) ...[
              if (height < 15) const SizedBox(height: 7),
              Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: WeekPactMetrics.pill,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

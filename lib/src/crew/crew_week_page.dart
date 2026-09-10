import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../goals/goal_icons.dart';
import '../goals/goals_backend.dart';
import '../home/home_backend.dart';
import '../theme/keepup_theme.dart';
import '../widgets/brutal_widgets.dart';
import '../widgets/page_frame.dart';

class CrewWeekPage extends StatefulWidget {
  const CrewWeekPage({
    super.key,
    required this.crew,
    required this.backend,
    required this.userId,
  });
  final GoalCrew crew;
  final HomeBackend backend;
  final String userId;
  @override
  State<CrewWeekPage> createState() => _CrewWeekPageState();
}

class _CrewWeekPageState extends State<CrewWeekPage> {
  CrewWeek? _week;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final week = await widget.backend.fetchWeek(widget.crew.id);
      if (mounted && request == _request) {
        setState(() {
          _week = week;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load crew activity. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    final members = [...?week?.members]
      ..sort((a, b) {
        if (a.id == b.id) return 0;
        if (a.id == widget.userId) return -1;
        if (b.id == widget.userId) return 1;
        return a.email.compareTo(b.email);
      });
    return Scaffold(
      body: KeepUpBackground(
        child: PageFrame(
          topPadding: 12,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to home',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.crew.name.toUpperCase(),
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'THIS WEEK',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              if (week != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_dateLabel(DateTime.parse(week.weekStart))} – ${_dateLabel(DateTime.parse(week.weekStart).add(const Duration(days: 6)))}',
                  style: TextStyle(color: context.muted, fontSize: 15),
                ),
              ],
            ],
          ),
          onRefresh: _refresh,
          loading: week == null && _error == null,
          skeleton: const Column(
            children: [
              SkeletonBar(height: 180),
              SizedBox(height: 26),
              SkeletonBar(height: 180),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: context.errorInk)),
                TextButton(onPressed: _refresh, child: const Text('TRY AGAIN')),
                const SizedBox(height: 16),
              ],
              if (week != null && week.goals.isEmpty)
                const Text(
                  'No goals yet. Your crew’s weekly activity will appear here.',
                  style: TextStyle(fontSize: 19),
                ),
              if (week != null && week.goals.isNotEmpty && members.isEmpty)
                const Text('No members to show.'),
              if (week != null && week.goals.isNotEmpty)
                for (final member in members) ...[
                  BrutalTabbedCard(
                    title: member.id == widget.userId ? 'YOU' : member.email,
                    tabColor: member.id == widget.userId
                        ? context.yellow
                        : context.mint,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${week.completed(member.id)} / ${week.target} WEEKLY CHECK-INS',
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (
                            var index = 0;
                            index < week.goals.length;
                            index++
                          ) ...[
                            _MemberGoalWeek(
                              week: week,
                              member: member,
                              goal: week.goals[index],
                            ),
                            if (index < week.goals.length - 1) ...[
                              const SizedBox(height: 16),
                              Divider(color: context.border, height: 1),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

class _MemberGoalWeek extends StatelessWidget {
  const _MemberGoalWeek({
    required this.week,
    required this.member,
    required this.goal,
  });
  final CrewWeek week;
  final WeekMember member;
  final CrewGoal goal;
  @override
  Widget build(BuildContext context) {
    final dates = week.checkIns
        .where((i) => i.userId == member.id && i.goalId == goal.id)
        .map((i) => i.day)
        .toSet();
    final completed = week.days(goal.id, member.id);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final start = DateTime.parse(week.weekStart);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            HugeIcon(
              icon: GoalIcon.find(goal.iconKey).data,
              size: 26,
              color: context.ink,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                goal.title,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$completed / ${goal.daysPerWeek} days${completed >= goal.daysPerWeek ? ' · Target reached' : ''}',
          style: TextStyle(color: context.muted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(7, (index) {
            final day = start.add(Duration(days: index));
            final key = day.toIso8601String().substring(0, 10);
            final future = key.compareTo(week.today) > 0;
            final done = !future && dates.contains(key);
            final today = key == week.today;
            final status = future
                ? 'Upcoming'
                : done
                ? 'Completed'
                : today
                ? 'Not checked in yet'
                : 'No check-in';
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 6 ? 0 : 5),
                child: Semantics(
                  label:
                      '${member.email}, ${goal.title}, ${_dateLabel(day)}: $status',
                  child: Tooltip(
                    message: '${_dateLabel(day)} · $status',
                    child: Column(
                      children: [
                        Text(
                          labels[index],
                          style: TextStyle(
                            color: context.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: done
                                ? context.mint
                                : today
                                ? context.yellow
                                : context.surface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: future
                                  ? context.border.withValues(alpha: .35)
                                  : context.border,
                              width: today
                                  ? KeepUpMetrics.border
                                  : KeepUpMetrics.fineBorder,
                            ),
                          ),
                          child: done
                              ? Icon(Icons.check, size: 19, color: context.ink)
                              : Text(
                                  future ? '·' : '–',
                                  style: TextStyle(color: context.muted),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

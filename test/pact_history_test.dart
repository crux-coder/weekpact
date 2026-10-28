import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/pact_history.dart';

PactHistory history({
  String today = '2026-10-28',
  String? firstDay,
  List<PactWeek> weeks = const [],
  int daysPerWeek = 3,
}) => PactHistory(
  pactId: 'run',
  crewId: 'crew',
  crewName: 'Climbers',
  title: 'Run',
  iconKey: 'run',
  pactIndex: 0,
  daysPerWeek: daysPerWeek,
  today: today,
  firstDay: firstDay,
  weeks: weeks,
);

void main() {
  test('a pact never kept has no age and says so', () {
    final h = history();
    expect(h.ageWeeks, 0);
    expect(h.daysKept, 0);
    expect(h.run, 0);
    expect(h.summary, 'Not kept yet');
  });

  test('age runs from the first week kept through this one', () {
    final h = history(
      firstDay: '2026-10-08', // A Thursday, four weeks back.
      weeks: const [
        PactWeek(start: '2026-10-05', kept: 3),
        PactWeek(start: '2026-10-12', kept: 1),
        PactWeek(start: '2026-10-19', kept: 3),
        PactWeek(start: '2026-10-26', kept: 2),
      ],
    );
    expect(h.ageWeeks, 4);
    expect(h.daysKept, 9);
    expect(h.weeksMet, 2);
    expect(h.summary, '4 weeks in · 9 days · on target 2 of 4');
  });

  test('the run ends at last week while this one is in progress', () {
    final h = history(
      firstDay: '2026-10-05',
      weeks: const [
        PactWeek(start: '2026-10-05', kept: 3),
        PactWeek(start: '2026-10-12', kept: 3),
        PactWeek(start: '2026-10-19', kept: 3),
        PactWeek(start: '2026-10-26', kept: 1),
      ],
    );
    expect(h.run, 3);
    // Once this week is there, it joins the run.
    final met = history(
      firstDay: '2026-10-05',
      weeks: const [
        PactWeek(start: '2026-10-12', kept: 3),
        PactWeek(start: '2026-10-19', kept: 3),
        PactWeek(start: '2026-10-26', kept: 3),
      ],
    );
    expect(met.run, 3);
    // A week missed outright breaks it.
    final gap = history(
      firstDay: '2026-10-05',
      weeks: const [
        PactWeek(start: '2026-10-05', kept: 3),
        PactWeek(start: '2026-10-19', kept: 3),
      ],
    );
    expect(gap.run, 1);
  });

  test('the calendar is sixteen Mondays ending this week', () {
    final mondays = history().calendarMondays;
    expect(mondays.length, PactHistory.calendarWeeks);
    expect(mondays.last, '2026-10-26');
    expect(mondays.first, '2026-07-13');
  });

  test('the record is read off the server’s row', () {
    final h = PactHistory.fromJson({
      'pact_id': 'run',
      'crew_id': 'crew',
      'crew_name': 'Climbers',
      'title': 'Run',
      'icon_key': 'run',
      'pact_index': 2,
      'days_per_week': 3,
      'today': '2026-10-28',
      'first_day': '2026-10-19',
      'weeks': [
        {'start': '2026-10-19', 'kept': 3},
      ],
      'days': ['2026-10-19', '2026-10-21', '2026-10-23'],
    });
    expect(h.pactIndex, 2);
    expect(h.weekStart, '2026-10-26');
    expect(h.summary, '2 weeks in · 3 days · on target 1 of 2');
    expect(h.days, hasLength(3));
  });
}

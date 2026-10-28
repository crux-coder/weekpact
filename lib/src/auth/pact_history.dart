/// One week of a person's record on a pact: its Monday, and how many of its
/// days they kept the pact.
class PactWeek {
  const PactWeek({required this.start, required this.kept});

  /// `yyyy-MM-dd`, a Monday in the crew's calendar.
  final String start;
  final int kept;

  factory PactWeek.fromJson(Map<String, dynamic> row) => PactWeek(
    start: row['start'] as String,
    kept: (row['kept'] as num?)?.toInt() ?? 0,
  );
}

/// A person's record on one pact, as their profile tells it: how long they
/// have kept it, how many days, which weeks met its target, and the days of
/// the last [calendarWeeks] weeks for a calendar.
///
/// The server sends the weeks and the days; everything said about them is
/// read here, so what the profile says can be checked without a database.
class PactHistory {
  const PactHistory({
    required this.pactId,
    required this.crewId,
    required this.crewName,
    required this.title,
    required this.iconKey,
    required this.pactIndex,
    required this.daysPerWeek,
    required this.today,
    this.firstDay,
    this.weeks = const [],
    this.days = const [],
  });

  /// How many weeks the calendar shows, the current one last.
  static const calendarWeeks = 16;

  final String pactId;
  final String crewId;
  final String crewName;
  final String title;
  final String iconKey;

  /// The pact's place in its crew's list, which its colours are read from.
  final int pactIndex;
  final int daysPerWeek;

  /// Today in the crew's calendar, `yyyy-MM-dd`.
  final String today;

  /// The first day the person kept the pact; null when they never have.
  final String? firstDay;

  /// Every week with a day kept, oldest first.
  final List<PactWeek> weeks;

  /// The days kept inside the calendar's window, oldest first.
  final List<String> days;

  factory PactHistory.fromJson(Map<String, dynamic> row) => PactHistory(
    pactId: row['pact_id'] as String,
    crewId: row['crew_id'] as String,
    crewName: row['crew_name'] as String? ?? '',
    title: row['title'] as String? ?? '',
    iconKey: row['icon_key'] as String? ?? 'target',
    pactIndex: (row['pact_index'] as num?)?.toInt() ?? 0,
    daysPerWeek: (row['days_per_week'] as num?)?.toInt() ?? 7,
    today: row['today'] as String,
    firstDay: row['first_day'] as String?,
    weeks: [
      for (final week in row['weeks'] as List? ?? const [])
        PactWeek.fromJson(Map<String, dynamic>.from(week as Map)),
    ],
    days: [for (final day in row['days'] as List? ?? const []) day as String],
  );

  /// The Monday of the week [day] falls in.
  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  static String isoDay(DateTime day) => day.toIso8601String().substring(0, 10);

  /// The current week's Monday, `yyyy-MM-dd`.
  String get weekStart => isoDay(mondayOf(DateTime.parse(today)));

  /// Days kept, ever.
  int get daysKept => weeks.fold(0, (sum, week) => sum + week.kept);

  /// How many weeks the person has been on the pact, counting from the week
  /// they first kept it through this one. Zero before the first day.
  int get ageWeeks {
    final first = firstDay;
    if (first == null) return 0;
    final from = mondayOf(DateTime.parse(first));
    final to = mondayOf(DateTime.parse(today));
    return to.difference(from).inDays ~/ 7 + 1;
  }

  bool met(PactWeek week) => week.kept >= daysPerWeek;

  /// Weeks that met the pact's target, this one included once it has.
  int get weeksMet => weeks.where(met).length;

  /// The weeks on target in a row, ending at this week if it is already
  /// there, otherwise at last week. A week in progress is not a miss.
  int get run {
    final byStart = {for (final week in weeks) week.start: week};
    var monday = mondayOf(DateTime.parse(today));
    final current = byStart[isoDay(monday)];
    if (current == null || !met(current)) {
      monday = monday.subtract(const Duration(days: 7));
    }
    var count = 0;
    while (true) {
      final week = byStart[isoDay(monday)];
      if (week == null || !met(week)) return count;
      count++;
      monday = monday.subtract(const Duration(days: 7));
    }
  }

  /// The Mondays the calendar draws, oldest first and this week last.
  List<String> get calendarMondays {
    final last = mondayOf(DateTime.parse(today));
    return [
      for (var i = calendarWeeks - 1; i >= 0; i--)
        isoDay(last.subtract(Duration(days: 7 * i))),
    ];
  }

  /// The line under the pact's name: how long, how much, how often on
  /// target. A pact never kept says so instead.
  String get summary {
    if (firstDay == null) return 'Not kept yet';
    final age = ageWeeks;
    final kept = daysKept;
    return '$age ${age == 1 ? 'week' : 'weeks'} in · '
        '$kept ${kept == 1 ? 'day' : 'days'} · '
        'on target $weeksMet of $age';
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/check_in_moment.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';

const _run = CrewPact(
  id: 'run',
  crewId: 'crew',
  title: 'Run',
  frequency: PactFrequency.weekly,
  daysPerWeek: 3,
);
const _read = CrewPact(
  id: 'read',
  crewId: 'crew',
  title: 'Read',
  frequency: PactFrequency.daily,
  daysPerWeek: 7,
);

CrewWeek week({
  required List<WeekMember> members,
  required List<PactCheckIn> checkIns,
  List<CrewPact> pacts = const [_run, _read],
}) => CrewWeek(
  today: '2026-10-28',
  weekStart: '2026-10-26',
  timezone: 'UTC',
  pacts: pacts,
  members: members,
  checkIns: checkIns,
);

const me = WeekMember('me', 'me@example.com');
const ana = WeekMember('ana', 'ana@example.com');
const bo = WeekMember('bo', 'bo@example.com');

void main() {
  test('the first check-in of the crew’s day says so', () {
    final moment = CheckInMoment.read(
      week(
        members: const [me, ana, bo],
        checkIns: const [PactCheckIn('run', 'me', '2026-10-28')],
      ),
      userId: 'me',
      pactId: 'run',
    );
    expect(moment.headline, 'First in the crew today.');
    expect(moment.detail, 'Run: 1 of 3 this week · 1 more pact today');
  });

  test('crewmates already in are counted, and a finished week is said', () {
    final moment = CheckInMoment.read(
      week(
        members: const [me, ana, bo],
        checkIns: const [
          PactCheckIn('run', 'me', '2026-10-26'),
          PactCheckIn('run', 'me', '2026-10-27'),
          PactCheckIn('run', 'me', '2026-10-28'),
          PactCheckIn('read', 'me', '2026-10-28'),
          PactCheckIn('read', 'ana', '2026-10-28'),
          PactCheckIn('run', 'ana', '2026-10-28'),
        ],
      ),
      userId: 'me',
      pactId: 'run',
    );
    expect(moment.headline, 'You and 1 crewmate are in today.');
    expect(moment.detail, 'Run: week done · today done');
  });

  test('the whole crew in is its own line', () {
    final moment = CheckInMoment.read(
      week(
        members: const [me, ana],
        checkIns: const [
          PactCheckIn('read', 'me', '2026-10-28'),
          PactCheckIn('run', 'ana', '2026-10-28'),
        ],
      ),
      userId: 'me',
      pactId: 'read',
    );
    expect(moment.headline, 'The whole crew is in today.');
  });

  test('a crew of one hears about the week instead of the crew', () {
    final moment = CheckInMoment.read(
      week(
        members: const [me],
        checkIns: const [
          PactCheckIn('run', 'me', '2026-10-26'),
          PactCheckIn('run', 'me', '2026-10-28'),
        ],
      ),
      userId: 'me',
      pactId: 'run',
    );
    expect(moment.headline, 'Day 2 of 3 for Run.');
    expect(moment.detail, '1 more pact today.');
    final done = CheckInMoment.read(
      week(
        members: const [me],
        pacts: const [_run],
        checkIns: const [
          PactCheckIn('run', 'me', '2026-10-26'),
          PactCheckIn('run', 'me', '2026-10-27'),
          PactCheckIn('run', 'me', '2026-10-28'),
        ],
      ),
      userId: 'me',
      pactId: 'run',
    );
    expect(done.headline, 'Run done for the week.');
    expect(done.detail, 'That’s everything for today.');
  });
}

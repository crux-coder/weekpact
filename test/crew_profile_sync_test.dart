import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_people_grid.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

class ProfileDashboard extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final week = await super.fetchWeek(crewId);
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      checkIns: week.checkIns,
      members: const [
        WeekMember(
          'owner',
          'owner@example.com',
          displayName: 'Jasmin',
          avatarUrl: 'https://example.com/avatar.png',
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'Crews uses the available Home profile even when roster has no profile fields',
    (tester) async {
      final auth = FakeAuthBackend();
      addTearDown(auth.dispose);
      final home = ProfileDashboard();
      final crews = FakeCrewBackend()
        ..crew = CrewDetails(
          id: 'crew',
          name: 'Hangboardasi',
          timezone: 'UTC',
          ownerId: 'owner',
          currentUserRole: 'owner',
          members: [
            CrewMember(
              userId: 'owner',
              email: 'owner@example.com',
              role: 'owner',
              joinedAt: DateTime(2026),
            ),
          ],
          pendingInvites: [],
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.light,
          home: HomePage(
            user: const AuthUser(email: 'owner@example.com'),
            authBackend: auth,
            crewBackend: crews,
            pactsBackend: home.pacts,
            homeBackend: home,
          ),
        ),
      );
      await tester.pumpUi();
      await tester.tap(find.byKey(const ValueKey('nav-crews')));
      await tester.pumpUi();
      final member = tester
          .widget<CrewPersonCard>(find.byType(CrewPersonCard))
          .member;
      expect(member.displayName, 'Jasmin');
      expect(member.avatarUrl, 'https://example.com/avatar.png');
      expect(find.text('Crew member'), findsNothing);
    },
  );
}

import 'package:flutter/material.dart';

import '../crew/crew_backend.dart';
import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import 'account_page.dart';
import 'auth_backend.dart';
import 'profile_history.dart';

/// What a crewmate's profile is drawn from, held above the navigator so a
/// face anywhere in the app — a story, a chat message, a crew's roster — can
/// open one without each page in between carrying the backends down.
class ProfileScope extends InheritedWidget {
  const ProfileScope({
    super.key,
    required this.authBackend,
    required this.homeBackend,
    required this.crewBackend,
    required this.pactsBackend,
    required super.child,
  });

  final AuthBackend authBackend;
  final HomeBackend homeBackend;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;

  /// Opens [member]'s profile, or null where there is none to open: no scope
  /// above (a test, a preview), nobody signed in, or no wall to read.
  ///
  /// [crewId] is the crew the face was seen in, which the profile's nudge is
  /// sent within; [onNudged] hears of a nudge sent from it.
  static VoidCallback? opener(
    BuildContext context,
    WeekMember? member, {
    String? crewId,
    ValueChanged<CrewNudgeState>? onNudged,
  }) {
    final scope = context.getInheritedWidgetOfExactType<ProfileScope>();
    final user = scope?.authBackend.currentUser;
    if (scope == null ||
        user == null ||
        member == null ||
        scope.homeBackend is! ProfileHistoryBackend) {
      return null;
    }
    return () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: AccountPage(
            key: ValueKey('profile-${member.id}'),
            user: user,
            member: member,
            nudgeCrewId: crewId,
            onNudged: onNudged,
            backend: scope.authBackend,
            signingOut: false,
            onSignOut: () {},
            homeBackend: scope.homeBackend,
            crewBackend: scope.crewBackend,
            pactsBackend: scope.pactsBackend,
          ),
        ),
      ),
    );
  }

  @override
  bool updateShouldNotify(ProfileScope oldWidget) =>
      authBackend != oldWidget.authBackend ||
      homeBackend != oldWidget.homeBackend ||
      crewBackend != oldWidget.crewBackend ||
      pactsBackend != oldWidget.pactsBackend;
}

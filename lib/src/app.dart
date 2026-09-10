import 'home/home_backend.dart';

import 'package:flutter/material.dart';

import 'goals/goals_backend.dart';

import 'auth/auth_backend.dart';
import 'auth/auth_gate.dart';
import 'crew/crew_backend.dart';
import 'invites/invite_links.dart';
import 'theme/keepup_theme.dart';
import 'theme/theme_preference.dart';

class KeepUpApp extends StatefulWidget {
  const KeepUpApp({
    super.key,
    required this.authBackend,
    this.initialThemeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.crewBackend = const MissingCrewBackend(),
    this.goalsBackend = const MissingGoalsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.inviteLinkSource = const NoopInviteLinkSource(),
  });

  final ThemeMode initialThemeMode;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;
  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final GoalsBackend goalsBackend;
  final HomeBackend homeBackend;
  final InviteLinkSource inviteLinkSource;

  @override
  State<KeepUpApp> createState() => _KeepUpAppState();
}

class _KeepUpAppState extends State<KeepUpApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    try {
      await widget.onThemeModeChanged?.call(mode);
    } catch (error) {
      debugPrint('Could not persist theme preference: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemePreference(
      mode: _themeMode,
      onChanged: _setThemeMode,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'WeekPact',
        theme: KeepUpTheme.light,
        darkTheme: KeepUpTheme.dark,
        themeMode: _themeMode,
        builder: (context, child) =>
            KeepUpBackground(child: child ?? const SizedBox.shrink()),
        home: AuthGate(
          authBackend: widget.authBackend,
          crewBackend: widget.crewBackend,
          goalsBackend: widget.goalsBackend,
          homeBackend: widget.homeBackend,
          inviteLinkSource: widget.inviteLinkSource,
        ),
      ),
    );
  }
}

import 'src/home/home_backend.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/theme/theme_preference.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/notifications/messaging_client.dart';
import 'src/notifications/notification_service.dart';
import 'src/notifications/push_registration.dart';
import 'src/goals/goals_backend.dart';
import 'src/auth/auth_backend.dart';
import 'src/crew/crew_backend.dart';
import 'src/invites/invite_links.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final GoalsBackend goalsBackend;
  final HomeBackend homeBackend;
  if (_supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    authBackend = SupabaseAuthBackend(Supabase.instance.client);
    crewBackend = SupabaseCrewBackend(Supabase.instance.client);
    goalsBackend = SupabaseGoalsBackend(Supabase.instance.client);
    homeBackend = SupabaseHomeBackend(Supabase.instance.client);
  } else {
    authBackend = const MissingConfigurationAuthBackend();
    crewBackend = const MissingCrewBackend();
    goalsBackend = const MissingGoalsBackend();
    homeBackend = const MissingHomeBackend();
  }

  final preferences = await SharedPreferences.getInstance();
  final themePreference = ThemePreferenceStore(preferences);
  final notifications = NotificationService(
    createClient: FirebaseMessagingClient.create,
    enabled: preferences.getBool('notifications_enabled') ?? false,
    saveEnabled: (enabled) async {
      if (!await preferences.setBool('notifications_enabled', enabled)) {
        throw StateError('Could not save notification preference.');
      }
    },
  );
  if (authBackend is SupabaseAuthBackend) {
    final registration = PushRegistration(
      authBackend,
      notifications,
      SupabasePushDeviceRegistry(Supabase.instance.client),
    );
    registration.start();
    authBackend.beforeSignOut = registration.prepareSignOut;
    authBackend.afterSignOutAttempt = registration.resume;
    notifications.beforeDisable = registration.unregisterCurrentDevice;
  }

  runApp(
    WeekPactApp(
      authBackend: authBackend,
      notifications: notifications,
      initialThemeMode: themePreference.mode,
      onThemeModeChanged: themePreference.save,
      crewBackend: crewBackend,
      goalsBackend: goalsBackend,
      homeBackend: homeBackend,
      inviteLinkSource: AppLinksInviteLinkSource(),
    ),
  );
}

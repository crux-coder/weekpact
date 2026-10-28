import 'src/telemetry/telemetry.dart';
import 'src/home/home_backend.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/crew/crew_selection_store.dart';
import 'src/home/home_cache.dart';
import 'src/home/story_seen_store.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/chat/chat_backend.dart';
import 'src/notifications/messaging_client.dart';
import 'src/notifications/notification_service.dart';
import 'src/notifications/push_registration.dart';
import 'src/pacts/pacts_backend.dart';
import 'src/auth/auth_backend.dart';
import 'src/crew/crew_backend.dart';
import 'src/invites/invite_links.dart';
import 'src/onboarding/onboarding_draft.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  await CrashReporting.instance.initialize(preferences);

  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final ChatBackend chatBackend;
  if (_supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    // The last profile, crews and week, for opening on them while fresh ones
    // load.
    final homeCache = HomeCache(preferences);
    final supabaseAuth = SupabaseAuthBackend(
      Supabase.instance.client,
      cache: homeCache,
    );
    await supabaseAuth.restoreProfile();
    authBackend = supabaseAuth;
    crewBackend = SupabaseCrewBackend(Supabase.instance.client);
    pactsBackend = SupabasePactsBackend(
      Supabase.instance.client,
      cache: homeCache,
    );
    homeBackend = SupabaseHomeBackend(
      Supabase.instance.client,
      cache: homeCache,
    );
    chatBackend = SupabaseChatBackend(Supabase.instance.client);
  } else {
    authBackend = const MissingConfigurationAuthBackend();
    crewBackend = const MissingCrewBackend();
    pactsBackend = const MissingPactsBackend();
    homeBackend = const MissingHomeBackend();
    chatBackend = const MissingChatBackend();
  }

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
    ProductAnalytics(Supabase.instance.client).start();
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
      crewSelectionStore: CrewSelectionStore(preferences),
      storySeenStore: StorySeenStore(preferences),
      onboardingDraftStore: OnboardingDraftStore(preferences),
      authBackend: authBackend,
      notifications: notifications,
      crewBackend: crewBackend,
      pactsBackend: pactsBackend,
      homeBackend: homeBackend,
      chatBackend: chatBackend,
      inviteLinkSource: AppLinksInviteLinkSource(),
    ),
  );
}

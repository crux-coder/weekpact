import 'src/telemetry/telemetry.dart';
import 'src/home/home_backend.dart';

import 'package:flutter/foundation.dart';
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
import 'src/subscriptions/subscription_backend.dart';
import 'src/subscriptions/subscription_identity.dart';
import 'src/subscriptions/subscription_scope.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

// Public RevenueCat SDK keys. The Test Store key routes purchases away from
// the App Store for local work; the SDK deliberately crashes a release build
// configured with one, so release builds always use the Apple key.
const _revenueCatAppleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
const _revenueCatTestKey = String.fromEnvironment('REVENUECAT_TEST_KEY');

String get _revenueCatKey {
  if (kReleaseMode) return _revenueCatAppleKey;
  return _revenueCatTestKey.isNotEmpty
      ? _revenueCatTestKey
      : _revenueCatAppleKey;
}

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
    final supabaseAuth = SupabaseAuthBackend(Supabase.instance.client);
    await supabaseAuth.restoreProfile();
    authBackend = supabaseAuth;
    crewBackend = SupabaseCrewBackend(Supabase.instance.client);
    // The last crews and week, for opening on them while fresh ones load.
    final homeCache = HomeCache(preferences);
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

  final SubscriptionBackend subscriptions = _revenueCatKey.isEmpty
      ? const MissingSubscriptionBackend()
      : RevenueCatSubscriptionBackend(apiKey: _revenueCatKey);
  // Failing to reach the store must not stop the app from launching; access
  // stays locked and refreshes once the store answers.
  await subscriptions.start().catchError((Object _) {});
  SubscriptionIdentity(authBackend, subscriptions).start();

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
      subscriptions: SubscriptionController(subscriptions),
    ),
  );
}

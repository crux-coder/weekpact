# Firebase Messaging setup

## What is implemented

WeekPact has the mobile FCM transport infrastructure. Account → Notifications
requests permission on demand, remembers device opt-in, registers and refreshes
the FCM token, and supports turning notifications off. Returning from system
Settings rechecks authorization without prompting. iOS registration waits for
APNs readiness; failed registration can be retried.

On iOS, foreground notifications use the native banner. On Android, foreground
notification payloads use an in-app banner; background notifications use the
`weekpact_general` channel and a white notification icon. Tapping a notification
opens the app normally. Both background taps and cold-start taps are captured.
The top-level background handler is registered and retained in release builds;
data-only messages currently have no business action.

## Crew goal notifications

A successful daily check-in queues `goal_completed` for every other current crew
member with an opted-in registered device and an active login session. The sender
is excluded. Weekly goals also emit on each day's check-in, not only when their
weekly target is reached. One goal/user/crew-date combination emits at most once,
even after unchecking and rechecking. Historical check-ins are not backfilled.

Example: **A goal checked off!** — “Ada completed Read.”

Each type uses the same internal `private.enqueue_crew_notification` API, durable
outbox, per-device delivery records, worker, and FCM transport. Templates live in
`supabase/functions/dispatch-notifications/templates.ts`. To add a type, create
its template and a trusted database event producer that supplies a stable event
key, crew, actor and payload. Do not let clients supply arbitrary recipients or
notification text. Payloads include version, type, notification ID, crew ID and
an optional goal ID. Tapping currently opens the app normally.

The outbox commits atomically with the check-in. A transactional `pg_net` wake-up
requests immediate delivery; `pg_cron` retries due work every minute. Workers claim
up to 20 deliveries with locks and two-minute leases. Transient errors retry with
exponential backoff, up to eight attempts. Jobs older than 24 hours are cancelled.
Leaving a crew, deleting/undoing the check-in, or losing the login session makes
queued deliveries ineligible. Invalid FCM tokens are removed. Membership is checked
when claimed; a change after a request is handed to FCM cannot retract that push.
Delivery is at-least-once: if FCM accepts a message but recording success fails,
a retry can repeat it. Stable Android tags/APNs collapse IDs reduce duplicates.

The app registers refreshed tokens against the signed-in Supabase session. Logout
waits for pending registration and unlinks the device before signing out; turning
notifications off also unlinks it. A failed unlink leaves logout/disable retryable.
Returning to the app retries account registration even if the FCM token is unchanged.
Token tables are private with no direct client access; only scoped RPCs are callable.

### Deploying the sender

```bash
supabase db push
python3 tool/deploy_notifications.py /absolute/path/to/firebase-service-account.json
```

The deployment script stores `FIREBASE_SERVICE_ACCOUNT` and a random
`NOTIFICATION_DISPATCH_SECRET` as Supabase Edge Function secrets, deploys the worker,
and stores its dispatch credential in Vault. It configures the restricted wake-up
function and minute schedule. Set `SUPABASE_ACCESS_TOKEN` in your shell to authorize the CLI and scheduler Management API setup; the script does not read your keychain.
Private keys are never written to the repo or printed. This deployment is already
complete for the linked WeekPact Supabase project.

For testing, both users must run the updated mobile build and enable notifications.
Keep the receiving app in the background and check off a goal that has not already
emitted an event today. No new Firebase or Apple configuration is needed.

## 1. Create the Firebase project and configure the app

Create/select a project in the [Firebase console](https://console.firebase.google.com/).
Firebase Authentication and Firestore are not needed for this stage; WeekPact
continues using Supabase for accounts.

Install the CLIs once, then sign in:

```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

From this repository run:

```bash
npm run firebase:configure
# or: pnpm firebase:configure
```

Select your Firebase project and allow the CLI to replace `lib/firebase_options.dart`.
The shortcut configures iOS and Android, both using `dev.codepeaktrail.weekpact`.
It generates the real Firebase options and platform configuration. The repository is currently configured for the `week-pact` project using the
downloaded iOS and Android configuration files.

Check that the generated `ios/Runner/GoogleService-Info.plist` belongs to the
Runner target and is included in its resources. Android should have
`android/app/google-services.json` and the Google Services Gradle plugin applied
by FlutterFire. Keep the generated config and project changes together.
These client configuration files contain public project identifiers, not sending credentials.
[Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup),
[FlutterFire CLI options](https://github.com/invertase/flutterfire_cli).

## 2. Enable Apple push delivery

In [Apple Developer](https://developer.apple.com/account/), open Certificates,
Identifiers & Profiles → Identifiers → `dev.codepeaktrail.weekpact` and enable
Push Notifications for that App ID. This requires Apple Developer Program membership.

Under Keys, create a key with Apple Push Notification service enabled. Configure
its environment and scope; if topic-specific, include `dev.codepeaktrail.weekpact`.
You need coverage for Sandbox/development for local testing and Production for
TestFlight/App Store. Create a corresponding key for the other environment if needed.
Record its Key ID and download the `.p8` file. Store that private file securely
outside the repo; Apple permits downloading it only once.
[Apple key instructions](https://developer.apple.com/help/account/keys/create-a-private-key).

In Firebase → Project settings → Cloud Messaging → Apple app configuration,
upload the APNs key into the matching development/production slot with its Key ID
and Apple Team ID. This repo currently uses team `R5L8RZTV6R`; use the team that
owns your App ID and key. The `.p8` belongs in Firebase, never inside the mobile app.
[Firebase APNs setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

## 3. Check Xcode signing

Open `ios/Runner.xcworkspace`, select Runner → Signing & Capabilities.
The repo already includes:

- Push Notifications and `Runner.entitlements` for all build configurations.
- Background Modes: Background fetch and Remote notifications.
- Firebase's notification delegate setup for the app's UIScene lifecycle.

Select the correct team and keep automatic signing enabled. Allow Xcode to refresh
the provisioning profile after enabling push on the App ID. If manually signing,
regenerate the profile with push support. The source entitlement uses development;
Xcode's distribution signing/export selects the production APNs environment from
the distribution profile. Do not disable Firebase app-delegate swizzling.
[Firebase iOS lifecycle requirement](https://pub.dev/packages/firebase_messaging),
[Apple signing workflow](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html).

## 4. Test on your iPhone

Rebuild fully after configuration (hot reload is insufficient):

```bash
flutter run -d 00008101-001E59E41A51003A \
  --dart-define-from-file=.env.json
```

1. Sign in, finish onboarding, then open Account → Notifications → Enable Notifications.
2. Accept the iOS prompt. If already denied, allow notifications in iPhone Settings
   → Apps → WeekPact → Notifications, then return to the app.
3. Tap **Copy FCM test token** (debug builds only).
4. Put WeekPact in the background. In Firebase Messaging, create a notification
   message, choose **Send test message**, paste the token, and send the test.
5. Tap the delivered notification. It should open WeekPact. Also test while the app
   is open; debug diagnostics show foreground deliveries and notification opens.

For release testing use `pnpm release` or `npm run release` after configuring the
production APNs key. Use a device/emulator with Google Play services for Android.
The Android channel and notification permission declaration are already included.
[Firebase message testing](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

If registration remains pending, check the signing profile, push capability, device
network, and Firebase app's bundle ID. If there is a token but no visible notification,
check notification permission/Focus mode and the matching APNs key environment.
Use a notification payload for initial testing; silent data delivery is OS-controlled
and the current background handler intentionally performs no app actions.

## Verification and next stage

`flutter analyze` and `flutter test` cover opt-in, denied permissions, APNs delays,
token replacement/deletion, retries, and foreground/background/cold-start events.
The iOS release build compiles without signing. Live delivery requires your real
Firebase configuration and APNs credentials and has not yet been verified.

The sender and scheduler are deployed. Firebase OAuth/FCM access was checked with
`validate_only`, and the scheduler's recorded executions succeed. The new crew
event still needs a two-account device test after installing the updated app.
Tests cover event fanout, deduplication, session/membership checks, lease recovery,
retry outcomes, invalid token pruning, templates, OAuth signing and registration races.

Never put sending credentials in `.env.json` or any mobile client files.

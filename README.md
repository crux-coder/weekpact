# WeekPact

WeekPact is a Flutter crew-pact app with Supabase authentication, crew
membership, owner-managed email invitations, and deep-link invite acceptance.

Crew pact check-ins notify other crew members through Firebase Messaging. Device
opt-in is available under Account → Notifications; delivery uses a reusable event
queue, templates, and a Supabase worker with retries.
Follow [the Firebase and Apple setup guide](docs/notifications.md) to connect your
project and test delivery. Run `npm run firebase:configure` after installing the CLIs.

## What is implemented

- Each user can belong to exactly one crew.
- A crew owner can create a crew, invite an email address, list members, and
  revoke pending invitations.
- Invitations expire after seven days, are stored as SHA-256 hashes, can only
  be used once, and can only be accepted by the email address invited.
- The invite survives login and signup. If email confirmation is enabled, the
  confirmation redirects back to the original crew invite.
- Database access is protected with RLS. Email delivery happens in an
  authenticated Edge Function; no AWS or Supabase secret key is shipped in
  the Flutter app.

## Pact terminology migration

Recurring commitments are **pacts**. The app, RPC payloads, notifications, and
current database schema use that term; goals are reserved for a future feature.
The rename migration updates existing tables in place to `crew_pacts` and
`pact_check_ins`, with `pact_id` references and the `save_pact_check_ins` RPC.
Record IDs, history, ownership, and user-entered titles are preserved.
Previously applied migration files retain their original names and definitions.

Apply the rename together with the updated app and notification worker, then
restart the app. Older builds use the previous API names and must be updated.
During rollout, let the worker accept both event formats before applying the
migration; queued event IDs and delivery records are retained. Deploy the final
worker after the database cutover.

## Crew pacts

The Pacts page lists your crews and stores recurring pacts under the selected
crew. Owners can add and edit pacts, including their Hugeicons icon; all crew members can read them. Choose **Every day**
(seven days per week) or **Days per week** (one to seven distinct days). Schedules
repeat Monday through Sunday in the crew timezone. The Home screen loads the current crew, pacts, members, and saved check-ins.
Members can select or unselect their own pacts for today, once per pact per day.
The server determines today and the current week using the crew timezone.

Weekly percentages sum completed member-days, capped at each pact’s weekly
target. “On track” means the member can still reach every target with the days
remaining this week (including today if not yet checked in). Editing a target
recalculates current-week progress without deleting existing check-ins.

Home includes skeleton loading, empty/error states, pull to refresh, and refresh
when returning to the page or resuming the app. While visible it refreshes every
minute. A crew streak counts consecutive weeks in which every eligible member meets
every pact target. The current week only joins the streak once completed and
does not break it while in progress. Completed weeks use saved aggregate results, so target edits and membership
changes cannot erase earned history. The current week stays live; members/pacts
are excluded from weeks before they joined/were created.

Apply the pact table and its access policies before using the page:

```sh
supabase db push
```

Restart the Flutter app after updating this code so the Pacts backend is wired
into the application. The crew selector supports a list, but the existing
one-crew-per-user database constraint remains until multi-crew membership is added.

Pact widgets are covered by `flutter test`. Database permission and constraint
tests can also run against PGlite without touching a Supabase project:

```sh
npm install --prefix /tmp/weekpact-pacts-sql @electric-sql/pglite@0.5.8
PGLITE_MODULE=/tmp/weekpact-pacts-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_pacts_database.mjs
```

## 1. Local prerequisites

Install Flutter, Docker Desktop (or another Docker-compatible daemon), and the
Supabase CLI. Docker must be running for the local Supabase stack.

Create the app configuration:

```sh
cp .env.example .env
```

For local Supabase, replace the URL and publishable key in `.env` with the
values printed by `supabase status`. Keep `APP_TIMEZONE` as the crew owner's
IANA timezone, such as `Europe/Sarajevo`.

Create the local Edge Function configuration:

```sh
cp supabase/functions/.env.example supabase/functions/.env.local
```

Add AWS API credentials, the SES region, and an SES-verified sender (see below). For immediate
iPhone development, use `APP_BASE_URL=weekpact://invite` for crew emails.
Authentication callbacks use `weekpact://invite`. Add `weekpact://invite` and
`weekpact://invite?invite=*` to the Supabase Auth redirect allow-list.

## 2. Start and test locally

```sh
supabase start
supabase db reset
supabase functions serve --env-file supabase/functions/.env.local
flutter run --dart-define-from-file=.env
```

Local Supabase Auth emails appear in Inbucket at
`http://127.0.0.1:54324`. Crew invitations themselves are sent through AWS SES.

To open a test invite directly in the iOS Simulator:

```sh
xcrun simctl openurl booted "weekpact://invite?invite=YOUR_RAW_INVITE_TOKEN"
```

The raw token only exists in the sent email. The database stores its hash.

## 3. Deploy Supabase

Log in, link the repository to your project, apply the migration, configure
function secrets, and deploy the function:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set --env-file supabase/functions/.env.production
supabase secrets set 'EMAIL_FROM=WeekPact <invites@YOUR_DOMAIN.com>'
supabase secrets set APP_BASE_URL=https://app.YOUR_DOMAIN.com/
supabase secrets set ALLOWED_ORIGIN=https://app.YOUR_DOMAIN.com
supabase functions deploy invite-crew-member --use-api
```

In Supabase Dashboard:

1. Enable Email under **Authentication → Providers**.
2. Under **Authentication → URL Configuration**, set your production site URL
   and allow `weekpact://invite` and `weekpact://invite?invite=*` as
   redirect URLs for the mobile app.
3. Confirm the migration appears under **Database → Migrations**.
4. Confirm the invitation configuration values appear under **Edge Functions → Secrets**.

Only the publishable key belongs in `.env` or your client build configuration.
Never add a secret/service-role key or AWS credentials to the Flutter build.

## Account confirmation email

`supabase/templates/confirmation.html` styles Supabase's **Confirm sign up** email
like the crew invitation. Its button uses `{{ .ConfirmationURL }}`, which verifies
the email with Supabase before returning to the callback supplied by the app.
The template is configured locally in `supabase/config.toml` and deployed separately
to hosted Auth email settings.

Every sign-up now passes `weekpact://invite`, retaining `?invite=TOKEN` when joining
through a crew invitation. Supabase Flutter handles the callback, exchanges the
PKCE code for a session, and the app opens Home (or the pending crew invitation).
Open the confirmation on the same phone/app installation used to sign up. On
another device, or after reinstalling the app, confirm the email and log in using
the password instead. The website does not process authentication callbacks.

Rebuild the app after changing this flow. Already-sent confirmation emails retain
their original callback and template.

## AWS SES for crew invitations

Crew invitations use the SES v2 API from `invite-crew-member`. Supabase Auth
SMTP (signup confirmations and password resets) is configured independently.

1. Verify your sender domain in SES and complete its DKIM DNS setup. Choose
   the same region in SES and `AWS_REGION`.
2. Request SES production access in that region to invite arbitrary recipients.
   While in the sandbox, recipients must also be verified (or use the SES mailbox simulator).
3. Create AWS API credentials with the policy below, substituting your region,
   AWS account ID, verified domain, and sender email. These are AWS access keys,
   **not SES SMTP credentials**.
4. Copy `supabase/functions/.env.example` to
   `supabase/functions/.env.production`, then fill in the values. Use
   `AWS_SESSION_TOKEN` only with temporary credentials; replace those
   credentials before they expire. An optional `SES_CONFIGURATION_SET`
   enables your configured SES event tracking and must exist in the same region.
5. Upload that file with `supabase secrets set --env-file
   supabase/functions/.env.production`, then deploy `invite-crew-member` using
   the command above. Keep all AWS credentials out of Flutter's `.env` and `.env.json`.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "ses:SendEmail",
    "Resource": "arn:aws:ses:REGION:ACCOUNT_ID:identity/YOUR_DOMAIN.com",
    "Condition": {
      "StringEquals": { "ses:FromAddress": "invites@YOUR_DOMAIN.com" }
    }
  }]
}
```

Test from a crew owner's account by inviting a recipient, opening the link,
and accepting with the invited email address. SES acceptance is not a delivery
guarantee; use SES bounce/complaint monitoring for delivery issues. The function
disables automatic send retries because SES SendEmail has no idempotency key.
If sending fails or times out, the matching invite is removed and the owner can
retry. A timeout can mean SES accepted the email, so that email's link may be
invalid and a fresh invitation is needed.

[SES API reference](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_SendEmail.html)

## 4. Production app links

The custom `weekpact://` scheme is configured for iOS and Android and is useful
for development. Production emails should use an HTTPS universal/app link so
the link opens the installed app and falls back to the static invitation webpage.
The Astro site in [`website/`](website/README.md) includes the product homepage,
invitation handoff, SEO metadata, and configurable domain settings. See its README
for deployment and native association setup.

### In-app invitation inbox

The **Crews** page has **Your crew** and **Invites** tabs. Signed-in users with a
confirmed email see active invitations sent to that email, including invitations
sent before they registered. Open a crew to preview its members and pact schedules,
then accept or decline. No email link or hosted page is needed for this flow.

The inbox refreshes when opened, when returning to Crews or resuming the app, and
on pull-to-refresh. Expired, revoked, accepted, and declined invitations disappear.
Declining invalidates the email link; the owner can send a new invitation later.
The existing one-crew-per-user rule still applies.

Apply `20260910091518_add_received_crew_invites.sql` and rebuild the mobile app.
The preview RPC exposes only crew membership and pact definitions to the verified
recipient; normal member-only table access and check-in privacy stay intact.
Email delivery and token-based acceptance continue to work as before.

```sh
PGLITE_MODULE=/tmp/weekpact-pacts-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_invites_database.mjs
```

### Leaving and managing membership

Members can choose **Leave crew**. Owners can remove non-owner members using the
remove icon next to their name. Both actions require confirmation. An owner who
leaves chooses a replacement from current members; a sole owner must first invite
another member. Leaving returns to Home. Former members lose crew access and need
a fresh invitation to rejoin; existing check-in history stays stored.

Apply `20260910104118_add_crew_membership_actions.sql` and rebuild the mobile app.
Membership permissions are checked by the database, including owner transfer.

```sh
PGLITE_MODULE=/tmp/weekpact-pacts-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_membership_database.mjs
```

### iOS

1. Give the app a production bundle identifier and Apple development team.
2. Add the Associated Domains capability in Xcode with
   `applinks:app.YOUR_DOMAIN.com`.
3. Host `https://app.YOUR_DOMAIN.com/.well-known/apple-app-site-association`
   with content type `application/json` and no filename extension:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["YOUR_TEAM_ID.YOUR_BUNDLE_ID"],
        "components": [{ "/": "/", "?": { "invite": "*" } }]
      }
    ]
  }
}
```

### Android

1. Give the app a production application ID.
2. Add an `android:autoVerify="true"` HTTPS `VIEW` intent filter for
   `app.YOUR_DOMAIN.com` in `android/app/src/main/AndroidManifest.xml`.
3. Host `https://app.YOUR_DOMAIN.com/.well-known/assetlinks.json` containing
   the application ID and the SHA-256 signing-certificate fingerprint.

For production builds, update `.env`:

```dotenv
INVITE_REDIRECT_BASE=https://app.YOUR_DOMAIN.com/
```

The configuration above applies when hosting an app that handles authentication
callbacks. For the static Astro site, change only the crew email `APP_BASE_URL`
after deployment; keep `INVITE_REDIRECT_BASE` on the working custom scheme. The
static site does not process Supabase Auth callbacks. See `website/README.md`.

## 5. Run the Flutter web build

```sh
flutter run -d chrome --dart-define-from-file=.env
```

For hosting, build with:

```sh
flutter build web --release --dart-define-from-file=.env
```

Do not commit `.env`, `supabase/functions/.env.local`, or
`supabase/functions/.env.production`.

## iOS release shortcut

From the repository root, run:

```sh
npm run release
# Or: pnpm release
```

This builds a signed release and opens the new archive in Xcode Organizer.
It uses `.env.json` when present, otherwise `.env`, and reads the release version
from `pubspec.yaml`. It increments the highest local build number and preserves
an archive under `build/ios/releases/`. It does not upload automatically.

In Organizer, select the archive → **Distribute App → App Store Connect → Upload**
(the exact labels can vary by Xcode version). Review signing and finish the upload.
After Apple processes it, select it in TestFlight or attach it to your App Store
release in App Store Connect.

Options:

```sh
npm run release -- --env .env.production
npm run release -- --build-number 10
npm run release -- --no-open
```

With pnpm, pass options directly, for example `pnpm release --build-number 10`.
No root dependency installation is needed. The shell script can also be run directly.

If another machine uploaded a higher build, supply a number above it. The local
counter lives in `.dart_tool/ios-release-build-number`; failed builds also consume
a number. Set a new marketing version (for example `1.1.0+1`) in `pubspec.yaml`
when preparing the next App Store version. Build numbers continue increasing.

Requires macOS, Flutter on PATH, Xcode selected as the developer directory, and
your Apple Developer account/team set up in Xcode. If signing fails, open
`ios/Runner.xcworkspace`, check **Runner → Signing & Capabilities**, then rerun.
If IPA export fails but Flutter reports an archive was created, you can distribute
that archive from Xcode; the script verifies it is fresh before opening it.

## Checks

### Crew nudges

Open **Not yet** on Home to send a motivating push notification with **Nudge**.
Only other members who have not checked in on the current crew date are eligible.
Each sender can nudge the same recipient once every **24 hours**, including after
changing crews. The database owns the cooldown; reopening the list or using another
device does not reset it. The **Nudged** tooltip shows when another nudge is allowed.

Nudges use the existing notification outbox and target only the selected member's
active registered devices. If no eligible device is registered, the action is
unavailable and no cooldown is consumed. Queued nudges are cancelled when the crew
day changes, the recipient checks in, membership changes, or device sessions expire.
The notification reads: “Jasmin is cheering you on. A small step on one pact today
counts. You've got this!” (using the sender's display name).

For a new environment, deploy the updated `dispatch-notifications` function
before applying `20260914133722_add_crew_nudges.sql`; the existing notification
credentials and dispatcher schedule are reused.

```sh
node tool/test_notification_sender.mjs
PGLITE_MODULE=/tmp/weekpact-pacts-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_nudges_database.mjs
flutter test test/crew_nudge_test.dart test/crew_nudge_backend_test.dart
```

### General checks

```sh
deno test --config supabase/functions/invite-crew-member/deno.json --allow-env supabase/functions/invite-crew-member/ses_test.ts
deno check --config supabase/functions/invite-crew-member/deno.json supabase/functions/invite-crew-member/index.ts
flutter analyze
flutter test
supabase db lint --local --fail-on error
```
# First-login onboarding

Signed-in accounts without a completed profile see an introduction, then one page
containing their optional avatar photo, required display name, and optional surname.
Successful completion opens Home; received crew invitations remain in Crews → Invites.
Existing development accounts will also see this flow once.

Names, `avatar_path`, and `onboarding_completed` are saved in Supabase Auth user
metadata. This metadata is used for presentation only, never authorization.
Photos are resized to at most 512 pixels and re-encoded as PNG without photo
metadata. The private `avatars` bucket allows each account to read and replace
only its own `<user-id>/avatar.png`. The Account screen displays the saved profile.

Deploy `20260910110607_create_avatar_storage.sql` with `supabase db push` before
using onboarding against a new Supabase environment. iOS photo-library usage
text is included; rebuild the native app after installing the image-picker dependency.

## Account settings and App Review

Account deletion, password recovery, confirmation resend, and privacy/support pages
are implemented. See [the account deployment and review guide](docs/app-review-accounts.md)
for the required migration/function deployment, reviewer-account provisioning,
and device verification steps.

## Launch features

Guided crew setup, native share invitations, immutable weekly results,
first-party product metrics, and optional Crashlytics are described in
[the launch feature guide](docs/launch-features.md). That guide includes migration
order, screenshot generation, metric queries, and release verification.

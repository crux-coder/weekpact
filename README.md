# WeekPact

WeekPact is a Flutter crew-goal app with Supabase authentication, crew
membership, owner-managed email invitations, and deep-link invite acceptance.

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

## Crew goals

The Goals page lists your crews and stores recurring goals under the selected
crew. Owners can add and edit goals, including their Hugeicons icon; all crew members can read them. Choose **Every day**
(seven days per week) or **Days per week** (one to seven distinct days). Schedules
repeat Monday through Sunday in the crew timezone. The Home screen loads the current crew, goals, members, and saved check-ins.
Members can select or unselect their own goals for today, once per goal per day.
The server determines today and the current week using the crew timezone.

Weekly percentages sum completed member-days, capped at each goal’s weekly
target. “On track” means the member can still reach every target with the days
remaining this week (including today if not yet checked in). Editing a target
recalculates current-week progress without deleting existing check-ins.

Home includes skeleton loading, empty/error states, pull to refresh, and refresh
when returning to the page or resuming the app. While visible it refreshes every
minute. A crew streak counts consecutive weeks in which every eligible member meets
every goal target. The current week only joins the streak once completed and
does not break it while in progress. Streaks use current members and goal
targets, so changing targets recalculates history; members/goals are excluded
from weeks before they joined/were created.

Apply the goal table and its access policies before using the page:

```sh
supabase db push
```

Restart the Flutter app after updating this code so the Goals backend is wired
into the application. The crew selector supports a list, but the existing
one-crew-per-user database constraint remains until multi-crew membership is added.

Goal widgets are covered by `flutter test`. Database permission and constraint
tests can also run against PGlite without touching a Supabase project:

```sh
npm install --prefix /tmp/keepup-goals-sql @electric-sql/pglite@0.5.8
PGLITE_MODULE=/tmp/keepup-goals-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_goals_database.mjs
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
The app also accepts legacy `keepup://invite` links. Keep the Auth redirect
setting on its existing scheme until the deployed Auth allow-list is updated.

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
xcrun simctl openurl booted "keepup://invite?invite=YOUR_RAW_INVITE_TOKEN"
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
   and allow both `keepup://invite` and
   `https://app.YOUR_DOMAIN.com/**` as redirect URLs.
3. Confirm the migration appears under **Database → Migrations**.
4. Confirm the invitation configuration values appear under **Edge Functions → Secrets**.

Only the publishable key belongs in `.env` or your client build configuration.
Never add a secret/service-role key or AWS credentials to the Flutter build.

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

The custom `weekpact://` scheme (with `keepup://` compatibility) is configured for iOS and Android and is useful
for development. Production emails should use an HTTPS universal/app link so
the link opens the installed app and falls back to the static invitation webpage.
The Astro site in [`website/`](website/README.md) includes the product homepage,
invitation handoff, SEO metadata, and configurable domain settings. See its README
for deployment and native association setup.

### In-app invitation inbox

The **Crews** page has **Your crew** and **Invites** tabs. Signed-in users with a
confirmed email see active invitations sent to that email, including invitations
sent before they registered. Open a crew to preview its members and goal schedules,
then accept or decline. No email link or hosted page is needed for this flow.

The inbox refreshes when opened, when returning to Crews or resuming the app, and
on pull-to-refresh. Expired, revoked, accepted, and declined invitations disappear.
Declining invalidates the email link; the owner can send a new invitation later.
The existing one-crew-per-user rule still applies.

Apply `20260910091518_add_received_crew_invites.sql` and rebuild the mobile app.
The preview RPC exposes only crew membership and goal definitions to the verified
recipient; normal member-only table access and check-in privacy stay intact.
Email delivery and token-based acceptance continue to work as before.

```sh
PGLITE_MODULE=/tmp/keepup-goals-sql/node_modules/@electric-sql/pglite/dist/index.js node tool/test_invites_database.mjs
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

```sh
deno test --config supabase/functions/invite-crew-member/deno.json --allow-env supabase/functions/invite-crew-member/ses_test.ts
deno check --config supabase/functions/invite-crew-member/deno.json supabase/functions/invite-crew-member/index.ts
flutter analyze
flutter test
supabase db lint --local --fail-on error
```

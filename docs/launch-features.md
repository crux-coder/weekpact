# Launch features

## Website

The Astro home page now uses the app's charcoal, sage, yellow, condensed type,
rounded panels, and subtle borders. The iPhone frame and floating motion are CSS;
the screen images are actual Flutter renders using fictional crew data. A screen
switcher shows Home and the expanded crew list. Motion respects reduced-motion
preferences. Existing installation, invitation, privacy and support routes remain.

Regenerate the three screenshots after future UI changes:

```sh
flutter test tool/capture_marketing.dart
```

The website uses `website/public/screenshots/home.png`, `crew.png`, and `recap.png`. The initial
visual concepts were generated with the built-in Image Gen tool: charcoal hero,
large “Good habits. Great company.” headline, angled iPhone with real screenshots;
sage three-step section; charcoal closing call to action. Screen content is taken
from Flutter, not generated UI. Build with `ASTRO_TELEMETRY_DISABLED=1 npm run build`
in `website`. Configure real store/TestFlight links using its existing site config.

## Guided activation and sharing

Home's empty state opens a four-step setup: crew, editable starter pact,
invitation, and an optional first check-in. Creating a crew from Crews also
continues into this setup. Progress resumes from saved crew/pact data. Owners can reopen Setup guide in Crews. Members
can finish later; marking a check-in explicitly means they did the pact today.

The pact editor has three editable starters. Owners can share an invitation
through the native share sheet from setup or Crews. Links use the existing HTTPS
invitation landing page and custom-scheme handoff; no automatic message is sent.
Recipients install/sign in, return to the original link, then explicitly accept.

A crew has one active share link. It expires after seven days. Creating another
replaces the old link; revoking invalidates it immediately. Anyone with the link
can join with a confirmed account, subject to the existing one-crew-per-account
rule. A retry by someone already in that crew is harmless. Email-bound invites
remain supported. Tokens are stored only as SHA-256 hashes. The raw link stays
in the owner's current UI state, not in analytics or persisted device settings.

`APP_SITE_URL` controls share-link origin; default is the existing WeekPact site.

## Frozen weeks and recaps

`20260914170113_add_launch_foundations.sql` adds private immutable weekly
aggregates. The crew's timezone determines Monday and Sunday. Each completed
week stores check-in count, distinct active member count, completed pact count,
number of pacts, and whether the crew earned its streak. A pact is complete when
all eligible members meet its target, matching existing crew-streak semantics.
No names, photos, individual check-ins, or member IDs are stored in the aggregate.

The migration backfills historical weeks from the data and targets available at
migration time. It cannot reconstruct old targets or deleted history that were
never stored. From then on, completed weeks are protected before pact/membership/
check-in/timezone mutations, and streaks read those saved results. The current
week remains live and can change when people undo a check-in or edit a target.

The database job `weekpact-weekly-recaps` runs every 15 minutes, covering crew
local timezones including quarter-hour offsets. It is idempotent. Foreground
recap/streak requests also finalize missing weeks, so a delayed job does not
block the feature. This is a Supabase pg_cron job, not a Codex automation.

The latest completed week opens on the member's first visit in the new week.
Seen state is per account and stored server-side. Recaps are available again
through the Home recap icon. New members do not receive recaps for weeks that
ended before they joined. Returning after several weeks shows the most recent
week rather than presenting a backlog. No recap push notification is sent.

Sharing renders only the recap card to PNG and opens the native share sheet.
It contains date and aggregate totals; no crew name, member names, or photos.
Finalized aggregates persist for the crew after individual account deletion.
The full crew's deletion removes them. Personal recap-view records are deleted
with their account.

## Analytics and crash reporting

Product events are first-party, in `private.product_events`; there is no Firebase
Analytics or advertising SDK. Database triggers record successful signup, crew
creation, invitation creation, invitation acceptance, first check-in, and weekly
check-in. The app records a signed-in weekly return on launch/resume. Server keys
deduplicate repeat events. Records include internal IDs and dates, not names,
emails, pact text, or raw invitation tokens. They are inaccessible to app roles
and cascade away with the account or crew. Tracking begins at deployment; prior
signups are not fabricated. Invitation creation measures creation, not confirmed
delivery or whether a share-sheet recipient actually opened a message.

`tool/product_metrics.sql` provides administrator-only queries for the funnel,
weekly crews with at least two people checking in, and crew week-two/week-four
retention. Recent cohorts need time to mature; don't interpret an unfinished
retention window as a failure.

Crashlytics is pinned to 5.3.0 to match the existing Firebase iOS SDK 12.18.0.
Native collection starts disabled; Account → Share crash reports opts in.
Only release builds report. Dart error types and stacks are captured without
free-form exception messages or account identifiers. Disabling deletes unsent
reports and stops collection. Android's Gradle plugin and the iOS release symbol
upload phase are configured. The simulator/debug build sends no crash report.
A release-device smoke report must still be verified in Firebase before launch;
compilation and unit tests alone cannot verify remote delivery/symbolication.

## Deployment order and validation

These launch changes are local until deployed. The final remote dry run confirms
only `20260914170113_add_launch_foundations.sql` remains pending; the earlier nudge
migration is already present remotely, and the notification worker is version 4.
Apply the launch migration, publish the website, and release the new app. The launch migration preserves existing public RPC names;
old app versions still use the original invitation and snapshot endpoints.

Check `cron.job` for `weekpact-weekly-recaps` and `cron.job_run_details` after
migration. The migration installs/schedules pg_cron when available (PGlite tests
omit the extension). Confirm the job exists in the target before release.

```sh
flutter analyze
flutter test
PGLITE_MODULE=/path/to/pglite/dist/index.js node tool/test_launch_database.mjs
PGLITE_MODULE=/path/to/pglite/dist/index.js node tool/test_pacts_database.mjs
```

Verify on a release device: installation via an invite, acceptance, link revocation,
native sharing to Messages/WhatsApp, first check-in, recap at local Monday rollover,
crash-report opt-in/opt-out, and the first symbolicated Firebase smoke report.

Validation in this workspace: all 144 Flutter tests, database regression suites,
website build/tests, and the iOS simulator build pass. Android compilation could
not run because no Android SDK is installed on this machine.

The production security advisor was read as a baseline, not as validation of the
undeployed schema. It reports existing exposed security-definer helper warnings
([Supabase guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable))
and disabled leaked-password protection
([configuration guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)).
The new migration keeps privileged workers private, authorizes public wrappers,
and is covered by local access-control tests; run advisors again after deployment.

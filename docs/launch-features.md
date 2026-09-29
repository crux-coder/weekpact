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

The website uses `website/public/screenshots/home.png`, and `crew.png`. The initial
visual concepts were generated with the built-in Image Gen tool: charcoal hero,
large “Good habits. Great company.” headline, angled iPhone with real screenshots;
sage three-step section; charcoal closing call to action. Screen content is taken
from Flutter, not generated UI. Build with `ASTRO_TELEMETRY_DISABLED=1 npm run build`
in `website`. Configure real store/TestFlight links using its existing site config.

## Guided activation and sharing

Home's empty state opens a four-step setup: crew, editable starter pact,
invitation, and an optional first check-in. Creating a crew from Crews also
continues into this setup. Progress resumes from saved crew/pact data. Members
can finish later; marking a check-in explicitly means they did the pact today.

The pact editor has three editable starters. Owners can share an invitation
through the native share sheet or copy a link from setup and the Invite someone
drawer in Crews. The drawer offers Share, Copy, and Show QR code; its card comes
first in the people grid. Email invitation creation is hidden in the UI; existing
email invitations and backend support remain intact. QR codes encode the same
HTTPS invite route for scanning with a phone camera. Links use the existing HTTPS
invitation landing page and custom-scheme handoff; no automatic message is sent.
Recipients install/sign in, return to the original link, then explicitly accept.
A pending token survives onboarding: somebody arriving on a share link who has
to create an account and set up a profile first lands on the acceptance screen
afterwards, rather than on Home. Crews → Invites lists `public.crew_invites`
only, so a share link never appears there, and the handoff pages say to reopen
the link instead of sending people to that inbox.

`20260928120000_add_crew_invite_preview.sql` adds `preview_crew_invite`, which
answers a valid unexpired token — share link or email invite, matched by its
SHA-256 hash — with the crew's name, its member count and its owner's display
name, and null for anything else. Nothing else about the crew is readable
before joining. The acceptance screen leads with "Join &lt;crew name&gt;" and
the member count when the preview arrives, and keeps its generic copy when it
does not.

Every copy, share, or newly shown QR code creates a new invite link, active for
seven days.
Earlier links retain their own expiry; there is no revoke action. Anyone with the link
can join with a confirmed account, subject to the existing one-crew-per-account
rule. A retry by someone already in that crew is harmless. Email-bound invites
remain supported. Tokens are stored only as SHA-256 hashes. The raw link is passed only to the clipboard or share sheet, not in analytics or persisted device settings.

`APP_SITE_URL` controls share-link origin; default is the existing WeekPact site.

## Frozen weeks

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

The database job `weekpact-finalize-crew-weeks` runs every 15 minutes, covering crew
local timezones including quarter-hour offsets. It is idempotent. Foreground
streak requests also finalize missing weeks, so a delayed job does not
block the feature. This is a Supabase pg_cron job, not a Codex automation.

Finalized aggregates persist for the crew after individual account deletion.
The full crew's deletion removes them. Weekly recap UI, automatic prompts,
image sharing, RPCs, and view tracking were removed by
`20260914181828_remove_weekly_recap.sql`. The finalization job remains solely
for preserving completed-week streaks.

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

### Android release signing

The release build type used to sign with the debug keystore, which Google Play
rejects on upload. It now reads `android/key.properties` — `storeFile`,
`storePassword`, `keyAlias`, `keyPassword` — and signs with the keystore that
file names. `android/key.properties.example` is the template;
`android/.gitignore` already holds `key.properties` and `**/*.jks`, so neither
the file nor the keystore is committed. Without `key.properties` the build still
runs, signed with the debug keys, and Gradle warns that it did. Keep the
keystore and its passwords outside the repository and backed up: losing it means
never updating the Play listing again, since Play identifies an app by the key
that signed it.

Make one upload keystore, once, and reuse it for every release:

```sh
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then copy the template and fill it in (`storeFile` may be absolute, or relative
to `android/`):

```sh
cp android/key.properties.example android/key.properties
```

`flutter build appbundle` then produces a signed bundle. Confirm the signer
before the first upload — `keytool -printcert -jarfile <bundle>` should show
your own certificate rather than the Android debug one. Android's Gradle build
cannot be run in this workspace (no Android SDK), so the configuration has not
been executed here.

## Deployment order and validation

The launch-foundation and independent-invite migrations are applied remotely.
On September 14, 2026, `20260914181828_remove_weekly_recap.sql` was also applied:
the recap RPCs and view records are gone, while finalized streak history remains.
The updated app was built and installed in the local simulator. Website changes
still need publishing and distributed app builds need a new release.

Two migrations from September 28, 2026 are not yet applied remotely and the app
build that carries them depends on both:
`20260928120000_add_crew_invite_preview.sql` (the invite page names its crew)
and `20260928120500_add_week_check_in_claps.sql` (stories open on the claps
they already have). Apply them with `supabase db push` before shipping that
build; an app without them still works, an app with them against a database
without them shows the fallback invite copy and zero claps.

Check `cron.job` for `weekpact-finalize-crew-weeks` and `cron.job_run_details` after
migration. The migration installs/schedules pg_cron when available (PGlite tests
omit the extension). Confirm the job exists in the target before release.

```sh
flutter analyze
flutter test
PGLITE_MODULE=/path/to/pglite/dist/index.js node tool/test_launch_database.mjs
PGLITE_MODULE=/path/to/pglite/dist/index.js node tool/test_pacts_database.mjs
```

Verify on a release device: installation via an invite, acceptance, independent seven-day link expiry and QR scanning,
native sharing to Messages/WhatsApp, first check-in, preserved streaks at local Monday rollover,
crash-report opt-in/opt-out, and the first symbolicated Firebase smoke report.

Validation in this workspace: all 144 Flutter tests, database regression suites,
website build/tests, and the iOS simulator build pass. Android compilation could
not run because no Android SDK is installed on this machine.

The production security advisor was read before the recap removal. It reports existing exposed security-definer helper warnings
([Supabase guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable))
and disabled leaked-password protection
([configuration guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)).
The new migration keeps privileged workers private, authorizes public wrappers,
and is covered by local access-control tests; run advisors again after deployment.

The invite-link update also requires `20260914174347_independent_crew_invite_links.sql`.
It preserves existing tokens and allows multiple links with independent expiry.

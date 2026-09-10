# Account readiness for App Review

Implemented account flows:

- Email/password signup, login, email confirmation resend and password recovery.
- Password recovery links open a dedicated new-password screen before onboarding.
  Successful recovery asks the user to sign out and sign in with the new password.
- Display name is required; surname and avatar are optional. Existing metadata
  remains compatible (`first_name` is now the display name).
- Account settings and onboarding expose privacy, support and account deletion.
- Deletion verifies the current password server-side, removes the avatar through
  Storage, then hard-deletes the Auth account. A database trigger atomically
  transfers owned crews to their longest-standing remaining member (ties use
  user ID), or deletes empty crews; deletes authored goals and their check-ins;
  removes invitations addressed to the deleted email; and relies on foreign-key
  cascades for memberships, own check-ins, sent invites, sessions and push data.
  Notification events referencing deleted goals are also removed. A restrictive
  Storage policy stops deleted accounts from uploading with unexpired JWTs.
- Goals authored by a deleted user are removed even in crews they previously
  left. This also deletes other members' check-ins on those goals, as explicitly
  disclosed before deletion. Other goals and their members' check-ins remain.
- A failed Storage deletion leaves Auth intact. A later Auth failure can leave
  the avatar removed; retrying deletion is safe. Cross-service removal is not one
  transaction. Delivered email/push messages cannot be recalled from recipients.

## Deployment

Apply the migration and deploy the function before distributing the new app:

```sh
supabase db push
supabase functions deploy delete-account --use-api
```

The function uses platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key in Flutter config.
It validates the bearer token itself and reauthenticates using the current
password, so its gateway JWT check is disabled intentionally. It accepts no
client-supplied account ID or email. Password verification uses an isolated
Auth client and immediately revokes its temporary verification session.

Keep `weekpact://invite` on the hosted Supabase Auth redirect allow-list, alongside
`weekpact://invite?invite=*` for invitation confirmation. Recovery reuses this
already registered native callback; the SDK distinguishes recovery from signup.
Auth SMTP must deliver both confirmation and recovery emails. The static website
does not exchange authentication codes. Request and open a reset on the same app
installation; an expired, used or cross-installation link may need a fresh request.

Publish `website/` with its normal static hosting workflow. The app defaults to:

- Privacy: `https://weekpact.codepeaktrail.dev/privacy/`
- Support: `https://weekpact.codepeaktrail.dev/support/`
- Support email: `codepeaktrail@gmail.com`

`PRIVACY_URL` and `SUPPORT_URL` Dart defines can override the HTTPS URLs for a
separate deployment. Put the public URLs into App Store Connect's Privacy Policy
and Support URL fields. Pages use WeekPact as the operator/app label and do not
claim incorporation. Confirm actual provider retention, hosting/SMTP arrangements
and any region-specific operator details before submission; the text is based on
this repository rather than an audit of production provider settings.

## Review account

Provision a dedicated confirmed account on the backend used by the submitted app:

```sh
# Set these variables securely; do not commit them or paste secrets into logs:
# SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, REVIEW_EMAIL, REVIEW_PASSWORD
node tool/create_review_account.mjs
```

Choose a new email and a password of at least 12 characters. The script never
changes an existing account, prints no credentials, and creates a fictional crew,
two goals and a check-in. Setup failure attempts to roll back only the account
created by that invocation. Add the chosen login to App Store Connect Review
Information, along with these suggested notes:

> WeekPact uses accounts for persistent shared crews and goal progress. The demo
> credentials have a confirmed email and a completed profile. Account settings
> include password recovery, privacy/support links and permanent account deletion.
> Photo and surname are optional. Notifications are optional. To test signup,
> create another account and confirm its email. To test deletion without losing
> the main demo login, use that newly created account. Goal creation is available
> to the crew owner.

The provisioning script has not been run against a hosted project by this change.
Recreate the reviewer account if it is deleted during review. Keep the backend and
email delivery live throughout review. No Google/social login was added, so this
change does not add Sign in with Apple.

## Validation

```sh
flutter analyze
flutter test
PGLITE_MODULE=/path/to/@electric-sql/pglite/dist/index.js node tool/test_account_deletion.mjs
deno test --config supabase/functions/delete-account/deno.json supabase/functions/delete-account/service_test.ts
deno check --config supabase/functions/delete-account/deno.json supabase/functions/delete-account/index.ts
ASTRO_TELEMETRY_DISABLED=1 npm --prefix website run build
npm --prefix website test
```

Before submission, run an end-to-end check on a disposable account on an actual
phone: signup → confirmation → optional-profile onboarding → password reset
(warm and cold app) → new login → account deletion → verify login and old session
access fail. Test both a sole crew owner and an owner with other members. PGlite
and service fakes validate application logic; they do not substitute for hosted
Auth, Storage, SMTP or device-level callback testing.

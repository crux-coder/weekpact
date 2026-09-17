# Subscriptions

WeekPact Pro is a per-account subscription sold through RevenueCat. Apple is
live first; Google Play attaches to the same entitlement later and is a
dashboard change rather than an app change.

## Shape

`lib/src/subscriptions/` follows the backend pattern used elsewhere:

- `SubscriptionBackend` — the interface. No RevenueCat types cross it, so
  widgets and tests never import the SDK.
- `RevenueCatSubscriptionBackend` — the real implementation.
- `MissingSubscriptionBackend` — used when no key is configured. Everything
  stays locked and nothing throws at startup, matching `MissingPactsBackend`.
- `SubscriptionController` / `SubscriptionScope` — an `InheritedNotifier`
  mirroring `NotificationScope`, so `context.isPro` rebuilds on renewal,
  expiry, or a purchase made outside the app.
- `SubscriptionIdentity` — keeps the RevenueCat app user id equal to the
  Supabase user id, serialized the way `PushRegistration` is.

`ProAccess` is the only value the app reads: `active`, `willRenew`,
`expiresAt`, `productIdentifier`, `manageable`, `sandbox`, plus `cancelled`
for active-but-ending.

## Dashboard configuration

Entitlement `weekpact_pro`, with both products attached:

| Product   | App Store Connect                 |
| --------- | --------------------------------- |
| `monthly` | Auto-renewing, WeekPact Pro group |
| `yearly`  | Auto-renewing, WeekPact Pro group |

Both live in one subscription group so people can move between plans without a
second purchase. The default offering needs a `$rc_monthly` and `$rc_annual`
package, which is what the Paywall editor renders.

## Keys

`REVENUECAT_APPLE_KEY` (`appl_…`) and `REVENUECAT_TEST_KEY` (`test_…`) come
from Project settings → API keys and are passed by `--dart-define-from-file`
like the Supabase values.

The Test Store key routes purchases away from the App Store, so debug builds
can exercise purchase, renewal and cancellation without App Store Connect
products or a sandbox account. The SDK deliberately crashes a release build
configured with a test key, so `lib/main.dart` selects the Apple key whenever
`kReleaseMode` is set. Never put a `test_` key in a TestFlight or App Store
build.

Both keys are public SDK keys. A secret `sk_` key must never reach the app.

## Paywall and Customer Center

The paywall is the app's own screen, `lib/src/subscriptions/paywall_page.dart`,
drawn in the design system rather than built in the dashboard. `showProPaywall`
presents it and reports a [PaywallOutcome]; backing out, including with the
system back gesture, is `cancelled` rather than a failure.

The dashboard still owns what is sold. `loadOffer()` reads the current
offering's `$rc_annual` and `$rc_monthly` packages, so products and prices
change remotely; only copy and layout are in the binary. Prices are never
composed here — `priceString` arrives localized, and the monthly restatement of
a yearly price is built by substituting the number inside that string so the
currency, symbol position and separators survive. A figure it cannot rewrite
safely, such as a grouped thousands amount, omits the line instead of inventing
a format. The saving badge is computed from the two amounts.

Apple requires a subscription screen to show each plan's duration and price and
to offer Restore, Terms and Privacy. All five are on the page; `TERMS_URL`
defaults to Apple's standard EULA so the link is never missing at review.

`RevenueCatUI.presentPaywall` is still wired as `presentPaywall()` in case the
dashboard should own the design again, but nothing calls it.

## Managing and cancelling

Account → WeekPact Pro opens `lib/src/subscriptions/subscription_page.dart`,
the app's own page rather than the RevenueCat Customer Center: a status card
with the plan, a badge and whether it renews or ends, then two choices —
switch plan and cancel, then Terms and Privacy.

Each row's second line says something its title does not, and two of them are
real data rather than copy: a monthly subscriber is told what the year saves,
computed from the offering so it cannot go stale when prices change, and
cancelling is answered with the date access actually runs to. Neither line
explains a mechanism — that the App Store handles it is the dialog's job, and
nobody needs telling twice.

Apple exposes no way to cancel from inside an app. Cancelling opens the App
Store subscription screen at `ProAccess.managementUrl`, behind a dialog that
says so, because someone dropped into Settings with no explanation assumes the
app is broken. Cancelling is disabled once the subscription is already ending.

`managementUrl` is null for a Test Store purchase and for a promotional grant,
so the page says the subscription is not managed by the App Store rather than
offering a button that goes nowhere.

Switching plan opens the paywall with `allowWhenPro`, and buying the other
package in the same subscription group is the upgrade or downgrade — the App
Store prorates it.

Restoring lives on the paywall and not here. Entitlements follow the Supabase
account through `SubscriptionIdentity`, so signing in is normally enough, and
this page is only reachable by someone who already has Pro. The paywall keeps
its Restore because Apple requires one and because a stranded purchase — made
before signing in, or left behind by a failed identify — is recovered from the
locked side, not this one.

`presentCustomerCenter()` is still wired as a fallback, but nothing calls it.

## When a purchase fails

`failureFor` maps every `PurchasesErrorCode` the SDK can raise to a sentence
someone can act on — a declined card names the payment method, a pending
payment says Pro unlocks when it clears, Screen Time restrictions are named as
such, and a build with no products says so rather than blaming the person.

Only a genuinely unknown code falls through to "Something went wrong", and it
carries `code` so it can be identified. `SubscriptionFailure.display` appends
that name in a debug build and never in a release one, so an unmapped failure
is diagnosable without leaking store internals to a user.

`testStoreSimulatedPurchaseError` is worded bluntly as a simulated failure, so
a Test Store experiment is never mistaken for a real payment problem.

## Enforcement

`context.isPro` drives presentation only. Any limit that must hold is decided
in Postgres, from a row only RevenueCat can write.

`private.subscriptions` mirrors the entitlement per account. A gate calls
`private.is_pro(user)` inside the RPC or RLS policy that performs the action —
never in the client alone. `public.pro_status()` returns the server's view of
the signed-in account, so a disagreement with the SDK is visible rather than
silent.

Events reach it through `supabase/functions/revenuecat-webhook`, which checks a
shared `Authorization` header and hands the payload to
`public.apply_subscription_event`, granted to `service_role` only. The function
decides, rather than trusting the event name:

- Cancellation means "will not renew". Access runs to `expires_at`; only
  `EXPIRATION` and `SUBSCRIPTION_PAUSED` end it outright.
- A billing retry keeps access while `grace_expires_at` is in the future.
- A replayed event id is a no-op and an event older than the stored one is
  dropped, because webhooks retry and can arrive out of order.
- A `TRANSFER` revokes the entitlement on every account it came from and
  carries that account's terms to the new owner, since the event itself has
  none. A missing expiry never reads as unlimited access; only
  `NON_RENEWING_PURCHASE` is open-ended.
- An event whose `app_user_id` is still anonymous resolves through `aliases`.
  If no alias matches an account it is acknowledged and parked, and the next
  renewal applies it.

### What Pro unlocks

One crew per account without Pro, counting crews you own and crews you joined.

`private.enforce_crew_limit` runs `before insert on public.crew_members`, which
is where every route into a crew ends: creating one through the
`add_crew_owner` trigger, an email invite, the invitation inbox, and a share
link. A route added later cannot skip it, and a refused creation rolls the crew
back in the same transaction. Two invitations accepted at the same moment are
serialized by an advisory lock on the account, so neither slips through.

Anyone already in more than one crew keeps them — the limit only applies to
joining another — as does anyone whose subscription lapses.

The trigger raises SQLSTATE `WPPRO`. `isCrewLimitError` in
`lib/src/subscriptions/pro_upgrade.dart` recognises it and
`showCrewLimitUpgrade` offers the paywall, then retries what the person was
doing if they come back with Pro. `CrewPage` also checks `context.isPro` before
opening the new-crew form, so the common case never needs a round trip; the
database still decides, because entitlements lapse and the SDK's view goes
stale.

The free limit is `private.free_crew_limit()`, one place to change.

### Webhook setup

Set the secret on the project, then point RevenueCat at the function:

```sh
supabase secrets set REVENUECAT_WEBHOOK_SECRET="$(openssl rand -hex 32)"
supabase functions deploy revenuecat-webhook
```

In RevenueCat, Integrations → Webhooks: the URL is
`https://<project>.supabase.co/functions/v1/revenuecat-webhook` and the
Authorization header value is that same secret, verbatim and with no `Bearer`
prefix. The function rejects everything until the secret is set, so deploy in
that order. "Send test event" should answer `{"outcome":"test"}`.

## Verifying

```sh
flutter analyze
flutter test test/subscription_test.dart
flutter test test/paywall_test.dart test/subscription_page_test.dart
deno test supabase/functions/revenuecat-webhook/service_test.ts
```

`test/paywall_test.dart` covers the plans as the store reports them, the
computed saving, buying either plan, a failed purchase, a restore with nothing
to restore, the no-offering state, the required links, and the layout at double
text size. `test/crew_limit_test.dart` covers the offer a free account sees, declining it,
buying from it, and the refusal arriving from Postgres after the client thought
it had Pro. `service_test.ts` covers the header check, the payloads that must never reach
Postgres, and that a database failure propagates so RevenueCat retries.
`test/subscription_test.dart` runs against a fake backend and covers the
locked/subscribed/cancelled tiles, entitlement changes arriving from the store,
failure reporting, and the no-scope case.

On a device, still confirm: purchase, restore on a second install, cancellation
reflected after backgrounding and resuming, and that the Customer Center opens.
Test Store renewals are accelerated, so a monthly plan renews in minutes, and a
test subscription renews at most five times before it cancels itself.

The Customer Center's "User ID" row shows `originalAppUserId` — the first
identity RevenueCat ever saw for that customer, which is the anonymous id from
before sign-in. That is expected after a normal alias and does not mean
identification failed. The current identity is `Purchases.appUserID`, which
`SubscriptionIdentity` keeps equal to the Supabase user id.

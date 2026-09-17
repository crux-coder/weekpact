-- Server-side mirror of RevenueCat entitlements.
--
-- The app already knows whether someone has Pro; this table exists because a
-- client check is trivially defeated. Any limit that costs capacity has to be
-- decided here, from a row only RevenueCat's webhook can write.

create table private.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  entitlement text not null,
  active boolean not null default false,
  will_renew boolean not null default false,
  expires_at timestamptz,
  -- Billing-retry grace: access continues past expires_at while Apple retries.
  grace_expires_at timestamptz,
  product_id text,
  store text,
  period_type text,
  environment text not null default 'PRODUCTION',
  -- Webhooks retry and can arrive out of order, so the last applied event is
  -- kept to make replays no-ops and to drop events older than what is stored.
  last_event_id text,
  last_event_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.subscriptions enable row level security;
create policy subscriptions_no_direct_access on private.subscriptions
  for all to authenticated using (false) with check (false);

-- Access outlives expires_at only for as long as the store says it does.
create function private.subscription_until(s private.subscriptions)
returns timestamptz language sql immutable set search_path = '' as $$
  select greatest(
    coalesce(s.expires_at, 'infinity'::timestamptz),
    coalesce(s.grace_expires_at, '-infinity'::timestamptz)
  );
$$;

-- The one question every server-side gate asks. Absent row means free.
create function private.is_pro(target_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from private.subscriptions s
    where s.user_id = target_user
      and s.active
      and s.entitlement = 'weekpact_pro'
      and private.subscription_until(s) > now()
  );
$$;

-- What the server believes, so a mismatch with the SDK is visible rather than
-- silent. Presentation still follows the SDK; limits follow this.
create function private.pro_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(
    (
      select jsonb_build_object(
        'active', s.active and private.subscription_until(s) > now(),
        'will_renew', s.will_renew,
        'expires_at', s.expires_at,
        'grace_expires_at', s.grace_expires_at,
        'product_id', s.product_id,
        'store', s.store,
        'period_type', s.period_type,
        'environment', s.environment,
        'updated_at', s.updated_at
      )
      from private.subscriptions s
      where s.user_id = (select auth.uid())
    ),
    jsonb_build_object('active', false, 'will_renew', false)
  );
$$;

create function public.pro_status()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.pro_status();
$$;

-- RevenueCat identifies a customer by whichever id the SDK had at the time, so
-- an event can arrive under the anonymous id with the Supabase id as an alias.
create function private.subscription_account(event jsonb)
returns uuid language sql stable set search_path = '' as $$
  select u.id
  from jsonb_array_elements_text(
    jsonb_build_array(event->>'app_user_id', event->>'original_app_user_id')
    || coalesce(event->'aliases', '[]'::jsonb)
  ) as candidate(value)
  join auth.users u
    on u.id = (case when candidate.value ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then candidate.value::uuid end)
  limit 1;
$$;

-- Applies one RevenueCat webhook event. Returns what it did, so the function
-- can log an outcome without the caller re-deriving it.
create function private.apply_subscription_event(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  event jsonb := coalesce(payload->'event', payload);
  event_id text := event->>'id';
  event_type text := upper(coalesce(event->>'type', ''));
  event_at timestamptz := coalesce(
    to_timestamp((event->>'event_timestamp_ms')::bigint / 1000.0), now());
  target uuid;
  existing private.subscriptions%rowtype;
  source private.subscriptions%rowtype;
  expires timestamptz := to_timestamp(
    nullif(event->>'expiration_at_ms', '')::bigint / 1000.0);
  grace timestamptz := to_timestamp(
    nullif(event->>'grace_period_expiration_at_ms', '')::bigint / 1000.0);
  is_active boolean;
begin
  if event_type = 'TEST' then
    return jsonb_build_object('outcome', 'test');
  end if;

  -- Only the Pro entitlement is enforced here. Other entitlements, and events
  -- that carry none at all, are acknowledged and ignored.
  if not coalesce(
    event->'entitlement_ids' ? 'weekpact_pro',
    event->>'entitlement_id' = 'weekpact_pro',
    false) then
    return jsonb_build_object('outcome', 'ignored', 'type', event_type);
  end if;

  target := private.subscription_account(event);
  if target is null then
    -- A purchase made before sign-in. RevenueCat re-sends the entitlement on
    -- the next renewal, and the alias arrives once the account identifies.
    return jsonb_build_object('outcome', 'unknown_account', 'type', event_type);
  end if;

  select * into existing from private.subscriptions
  where user_id = target for update;

  if found then
    if existing.last_event_id is not distinct from event_id then
      return jsonb_build_object('outcome', 'duplicate', 'type', event_type);
    end if;
    if existing.last_event_at > event_at then
      return jsonb_build_object('outcome', 'stale', 'type', event_type);
    end if;
  end if;

  if event_type = 'TRANSFER' then
    -- A TRANSFER states only that the entitlement moved. Its terms have to
    -- come from the account it left, or the new owner would be recorded with
    -- no expiry at all, which reads as access that never ends.
    select * into source from private.subscriptions s
    where s.user_id in (
      select u.id from jsonb_array_elements_text(
        coalesce(event->'transferred_from', '[]'::jsonb)) as moved(value)
      join auth.users u on u.id::text = moved.value)
    order by private.subscription_until(s) desc
    limit 1;
  end if;

  -- An event that carries no terms inherits them rather than replacing them
  -- with nothing.
  expires := coalesce(expires, source.expires_at, existing.expires_at);

  -- Cancellation means "will not renew", not "lost access": the entitlement
  -- runs to expiration. Only expiry and a pause end access outright.
  is_active := event_type not in ('EXPIRATION', 'SUBSCRIPTION_PAUSED')
    and case
      -- Only a one-off purchase is open-ended. Anywhere else a missing expiry
      -- means the terms are unknown, which must not read as unlimited access.
      when expires is null then event_type = 'NON_RENEWING_PURCHASE'
      else greatest(expires, coalesce(grace, '-infinity'::timestamptz)) > now()
    end;

  if event_type = 'TRANSFER' then
    -- Revoke the entitlement everywhere it came from.
    update private.subscriptions s
    set active = false, will_renew = false,
        last_event_id = event_id, last_event_at = event_at, updated_at = now()
    where s.user_id in (
      select u.id from jsonb_array_elements_text(
        coalesce(event->'transferred_from', '[]'::jsonb)) as moved(value)
      join auth.users u on u.id::text = moved.value)
      and s.user_id is distinct from target;
  end if;

  insert into private.subscriptions as s (
    user_id, entitlement, active, will_renew, expires_at, grace_expires_at,
    product_id, store, period_type, environment,
    last_event_id, last_event_at, updated_at)
  values (
    target, 'weekpact_pro', is_active,
    is_active and event_type not in ('CANCELLATION', 'EXPIRATION', 'SUBSCRIPTION_PAUSED'),
    expires, grace,
    coalesce(event->>'product_id', source.product_id, existing.product_id),
    upper(coalesce(event->>'store', source.store, existing.store, 'APP_STORE')),
    coalesce(event->>'period_type', source.period_type, existing.period_type),
    upper(coalesce(event->>'environment', source.environment, existing.environment, 'PRODUCTION')),
    event_id, event_at, now())
  on conflict (user_id) do update set
    entitlement = excluded.entitlement,
    active = excluded.active,
    will_renew = excluded.will_renew,
    expires_at = excluded.expires_at,
    grace_expires_at = excluded.grace_expires_at,
    product_id = excluded.product_id,
    store = excluded.store,
    period_type = excluded.period_type,
    environment = excluded.environment,
    last_event_id = excluded.last_event_id,
    last_event_at = excluded.last_event_at,
    updated_at = now();

  return jsonb_build_object('outcome', 'applied', 'type', event_type, 'active', is_active);
end;
$$;

create function public.apply_subscription_event(payload jsonb)
returns jsonb language sql volatile security definer set search_path = '' as $$
  select private.apply_subscription_event(payload);
$$;

revoke all on function public.apply_subscription_event(jsonb) from public, anon, authenticated;
grant execute on function public.apply_subscription_event(jsonb) to service_role;
revoke all on function public.pro_status() from public, anon;
grant execute on function public.pro_status() to authenticated;

-- Telling someone their crew applauded them.
--
-- A clap is the only gesture in the app whose whole point is to reach another
-- person, and until now it reached nobody: the tally moved in a feed the author
-- had to reopen and happen to look at. This queues a push to the author, through
-- the same outbox, worker and transport every other notification uses.
--
-- The thing a clap needs that a check-in or a nudge does not is a window. A
-- check-in fires once per pact per day and a nudge is rationed per sender, but a
-- post can be clapped by everyone in the crew inside the same minute, and five
-- pushes saying almost the same thing is worse than none. So each check-in gets
-- at most one clap push per window, and claps arriving while that push is still
-- queued are folded into it rather than dropped.

-- One row per clapped check-in, tracking the window rather than each clap.
--
-- `counted_from` is the previous notification's time, so the count in the next
-- push is the claps the author has not been told about yet — including the ones
-- a throttled window swallowed. Nothing goes unannounced, it just waits.
create table private.check_in_clap_notices (
  pact_id uuid not null,
  check_in_user_id uuid not null,
  completed_on date not null,
  notified_at timestamptz not null,
  counted_from timestamptz not null,
  event_id uuid references private.notification_events(id) on delete set null,
  primary key (pact_id, check_in_user_id, completed_on),
  constraint check_in_clap_notices_check_in_fkey
    foreign key (pact_id, check_in_user_id, completed_on)
    references public.pact_check_ins(pact_id, user_id, completed_on)
    on delete cascade
);
alter table private.check_in_clap_notices enable row level security;
revoke all on private.check_in_clap_notices from public, anon, authenticated;
create policy check_in_clap_notices_no_direct_access on private.check_in_clap_notices
  for all to authenticated using (false) with check (false);

-- One place to change how often a single check-in may interrupt its author.
create function private.clap_notice_window() returns interval
language sql immutable set search_path = '' as $$ select interval '1 hour' $$;
revoke all on function private.clap_notice_window() from public, anon, authenticated;

create function private.notify_check_in_clap(
  target_pact_id uuid,
  author uuid,
  target_day date,
  actor uuid,
  crew uuid,
  at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  device_ids uuid[];
  window_start timestamptz;
  queued uuid;
  fresh integer;
  actor_name text;
  pact_title text;
  event uuid;
begin
  -- Checked before the window is touched, so an author with no device to reach
  -- does not burn a window that a later clap could have used.
  select array_agg(d.id) into device_ids
  from private.push_devices d
  join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
  where d.user_id = author and d.updated_at > at - interval '60 days';
  if device_ids is null then return; end if;

  -- Opening a window is the same conditional upsert the nudge cooldown uses, so
  -- simultaneous claps cannot both decide they are the first one.
  insert into private.check_in_clap_notices(
    pact_id, check_in_user_id, completed_on, notified_at, counted_from)
  values (target_pact_id, author, target_day, at, '-infinity')
  on conflict (pact_id, check_in_user_id, completed_on) do update
    set counted_from = private.check_in_clap_notices.notified_at,
        notified_at = excluded.notified_at,
        event_id = null
    where private.check_in_clap_notices.notified_at
      <= excluded.notified_at - private.clap_notice_window()
  returning counted_from into window_start;

  if window_start is null then
    -- Inside the window. If the last push is still sitting in the outbox, the
    -- claps that arrived behind it belong in that push, not in a second one.
    select n.event_id, n.counted_from into queued, window_start
    from private.check_in_clap_notices n
    where n.pact_id = target_pact_id and n.check_in_user_id = author
      and n.completed_on = target_day;
    if queued is null or exists (
      select 1 from private.notification_deliveries d
      where d.event_id = queued and d.status <> 'pending'
    ) then return; end if;
    select count(*) into fresh from public.check_in_claps c
    where c.pact_id = target_pact_id and c.check_in_user_id = author
      and c.completed_on = target_day and c.actor_id <> author
      and c.created_at > window_start;
    update private.notification_events
      set payload = payload || jsonb_build_object('clap_count', fresh)
      where id = queued;
    return;
  end if;

  select count(*) into fresh from public.check_in_claps c
  where c.pact_id = target_pact_id and c.check_in_user_id = author
    and c.completed_on = target_day and c.actor_id <> author
    and c.created_at > window_start;

  -- Metadata supplies display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(raw_user_meta_data->>'first_name'), 60), ''), 'A crew member')
    into actor_name from auth.users where id = actor;
  select left(p.title, 120) into pact_title from public.crew_pacts p where p.id = target_pact_id;

  event := gen_random_uuid();
  insert into private.notification_events(id, dedupe_key, type, crew_id, actor_id, payload)
  values (event, 'check_in_clapped:' || event, 'check_in_clapped', crew, actor,
    jsonb_build_object(
      'recipient_id', author, 'pact_id', target_pact_id,
      'pact_title', coalesce(pact_title, 'a pact'), 'completed_on', target_day,
      'actor_name', coalesce(actor_name, 'A crew member'), 'clap_count', fresh));
  insert into private.notification_deliveries(event_id, device_id, recipient_id)
    select event, device_id, author from unnest(device_ids) device_id;
  update private.check_in_clap_notices set event_id = event
    where pact_id = target_pact_id and check_in_user_id = author
      and completed_on = target_day;
  perform private.wake_notification_dispatcher();
end;
$$;
revoke all on function private.notify_check_in_clap(uuid, uuid, date, uuid, uuid, timestamptz)
  from public, anon, authenticated;

-- Unchanged except for the notification: a clap that was already there notifies
-- nobody, and neither does applauding yourself.
create or replace function private.set_check_in_clap(
  target_pact_id uuid,
  target_check_in_user uuid,
  target_day date,
  clapped boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  crew uuid;
  added integer := 0;
begin
  if viewer is null or clapped is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- Membership in the crew that owns the pact is the only thing that
  -- authorizes a clap, and it is re-checked here rather than trusted from
  -- whichever feed page the tap came from.
  select p.crew_id into crew
  from public.pact_check_ins i
  join public.crew_pacts p on p.id = i.pact_id
  join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
  where i.pact_id = target_pact_id
    and i.user_id = target_check_in_user
    and i.completed_on = target_day;
  if crew is null then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  -- Both directions are idempotent, so a double tap on an already-clapped
  -- post and a repeated unclap both settle on the state the caller asked for.
  if clapped then
    insert into public.check_in_claps(
      pact_id, check_in_user_id, completed_on, actor_id)
    values (target_pact_id, target_check_in_user, target_day, viewer)
    on conflict do nothing;
    get diagnostics added = row_count;
    if added = 1 and viewer <> target_check_in_user then
      perform private.notify_check_in_clap(
        target_pact_id, target_check_in_user, target_day, viewer, crew, now());
    end if;
  else
    delete from public.check_in_claps c
    where c.pact_id = target_pact_id
      and c.check_in_user_id = target_check_in_user
      and c.completed_on = target_day
      and c.actor_id = viewer;
  end if;
  return jsonb_build_object(
    'clap_count', (
      select count(*) from public.check_in_claps c
      where c.pact_id = target_pact_id
        and c.check_in_user_id = target_check_in_user
        and c.completed_on = target_day),
    'viewer_clapped', clapped);
end;
$$;

-- A queued clap push is only worth sending while a clap it announces survives.
-- Taking every clap back before the worker runs, or losing the check-in itself,
-- cancels it the way an undone check-in cancels its own notification.
create or replace function public.claim_notification_deliveries(batch_size integer default 20)
returns table(delivery_id uuid, lease uuid, device_token text, event_type text, event_id uuid, crew_id uuid, payload jsonb)
language plpgsql security definer set search_path = '' as $$
begin
  -- Invalidate queued work if membership/session/pact state changed after enqueue.
  update private.notification_deliveries d set status = 'cancelled', last_error = 'recipient_or_event_unavailable'
  from private.notification_events e, private.push_devices p
  where d.event_id=e.id and d.device_id=p.id and d.status in ('pending','sending')
    and (e.created_at < now()-interval '24 hours' or p.user_id <> d.recipient_id
      or not exists(select 1 from auth.sessions s where s.id=p.session_id and s.user_id=p.user_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=d.recipient_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=e.actor_id)
      or (e.type='pact_completed' and not exists(select 1 from public.pact_check_ins i
        where i.pact_id=(e.payload->>'pact_id')::uuid and i.user_id=e.actor_id and i.completed_on=(e.payload->>'completed_on')::date))
      or (e.type='check_in_clapped' and (
        d.recipient_id is distinct from (e.payload->>'recipient_id')::uuid
        or not exists(select 1 from public.check_in_claps c
          where c.pact_id=(e.payload->>'pact_id')::uuid
            and c.check_in_user_id=(e.payload->>'recipient_id')::uuid
            and c.completed_on=(e.payload->>'completed_on')::date
            and c.actor_id <> (e.payload->>'recipient_id')::uuid)))
      or (e.type='crew_nudge' and (
        d.recipient_id is distinct from (e.payload->>'recipient_id')::uuid
        or (e.payload->>'completed_on')::date is distinct from (
          select (now() at time zone coalesce(t.name,'UTC'))::date
          from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=e.crew_id)
        or exists(select 1 from public.pact_check_ins i join public.crew_pacts p2 on p2.id=i.pact_id
          where p2.crew_id=e.crew_id and i.user_id=d.recipient_id and i.completed_on=(e.payload->>'completed_on')::date)
      )));
  update private.notification_deliveries set status='failed',last_error='retry_limit'
    where status in ('pending','sending') and available_at <= now() and attempts >= 8;
  return query with picked as (
    select d.id from private.notification_deliveries d
    where d.status in ('pending','sending') and d.available_at <= now() and d.attempts < 8
    order by d.available_at,d.id for update skip locked limit greatest(1,least(batch_size,50))
  ), claimed as (
    update private.notification_deliveries d set status='sending', attempts=d.attempts+1,
      available_at=now()+interval '2 minutes',lease_id=gen_random_uuid()
    from picked where d.id=picked.id returning d.*
  ) select d.id,d.lease_id,p.token,e.type,e.id,e.crew_id,e.payload
    from claimed d join private.push_devices p on p.id=d.device_id
    join private.notification_events e on e.id=d.event_id;
end;
$$;

-- The notifications someone can read back, rather than only be interrupted by.
--
-- Push delivery already exists, but it is keyed on devices: a person who never
-- turned notifications on has no delivery rows at all, and one who did has a
-- row per device. Neither is a list anybody can read. The inbox is its own
-- fanout — one row per person per event, written whether or not that person
-- can be pushed to — so the list is the same on a phone with notifications off
-- as on one with them on, and read state belongs to the person, not the device.
create table private.notification_inbox (
  event_id uuid not null references private.notification_events(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  primary key (event_id, recipient_id)
);
-- The page order and the unread count are the only two reads.
create index notification_inbox_recipient_idx
  on private.notification_inbox(recipient_id, created_at desc, event_id desc);
alter table private.notification_inbox enable row level security;
revoke all on private.notification_inbox from public, anon, authenticated;
create policy notification_inbox_no_direct_access on private.notification_inbox
  for all to authenticated using (false) with check (false);

-- Crew fanout now reaches everyone it is about, not only registered devices.
create or replace function private.enqueue_crew_notification(
  event_type text, event_key text, target_crew uuid, actor uuid, event_payload jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare created_event uuid;
begin
  insert into private.notification_events(dedupe_key,type,crew_id,actor_id,payload)
  values(event_key,event_type,target_crew,actor,event_payload)
  on conflict(dedupe_key) do nothing returning id into created_event;
  if created_event is not null then
    insert into private.notification_inbox(event_id,recipient_id)
    select created_event,m.user_id from public.crew_members m
    where m.crew_id=target_crew and m.user_id<>actor;
    insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select created_event,d.id,m.user_id from public.crew_members m
      join private.push_devices d on d.user_id=m.user_id
      join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    where m.crew_id=target_crew and m.user_id<>actor and d.updated_at>now()-interval '60 days';
    perform private.wake_notification_dispatcher();
  end if;
  return created_event;
end;
$$;

-- A clap is worth recording even when there is nothing to push it to.
--
-- The window still decides how often a check-in may interrupt its author, and
-- now also how often it may add a line to their list: one entry per check-in
-- per window, with the claps behind it folded into that entry's count. What
-- changes is that a missing device no longer means a missing notification.
create or replace function private.notify_check_in_clap(
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
    -- Inside the window. If the last notification has not gone out yet, the
    -- claps that arrived behind it belong in it, not in a second one.
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
  insert into private.notification_inbox(event_id, recipient_id) values (event, author);
  select array_agg(d.id) into device_ids
  from private.push_devices d
  join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
  where d.user_id = author and d.updated_at > at - interval '60 days';
  if device_ids is not null then
    insert into private.notification_deliveries(event_id, device_id, recipient_id)
      select event, device_id, author from unnest(device_ids) device_id;
    perform private.wake_notification_dispatcher();
  end if;
  update private.check_in_clap_notices set event_id = event
    where pact_id = target_pact_id and check_in_user_id = author
      and completed_on = target_day;
end;
$$;

-- A nudge with nowhere to land is still not sent: the point of a nudge is the
-- interruption, so an unreachable recipient stays 'unavailable' and costs the
-- sender no cooldown. What changes is that a sent one is also written down.
create or replace function private.send_crew_nudge(target_crew_id uuid, target_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); today date; members_count integer;
  device_ids uuid[]; sent_at timestamptz; next_at timestamptz;
  event_id uuid := gen_random_uuid(); actor_name text; request_time timestamptz := now();
begin
  if uid is null or target_user_id is null or uid=target_user_id then
    raise exception 'Choose another crew member' using errcode='42501';
  end if;
  -- Stable lock order also serializes recipient check-ins and membership removal.
  perform m.user_id from public.crew_members m
    where m.crew_id=target_crew_id and m.user_id in (uid,target_user_id)
    order by m.user_id for update;
  get diagnostics members_count = row_count;
  if members_count<>2 then raise exception 'Crew membership required' using errcode='42501'; end if;
  select (request_time at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=target_crew_id;
  if exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
      where p.crew_id=target_crew_id and i.user_id=target_user_id and i.completed_on=today) then
    return jsonb_build_object('status','checked_in');
  end if;
  select array_agg(d.id) into device_ids from private.push_devices d
    join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    where d.user_id=target_user_id and d.updated_at>request_time-interval '60 days';
  if device_ids is null or not exists(select 1 from public.crew_pacts p where p.crew_id=target_crew_id) then
    return jsonb_build_object('status','unavailable');
  end if;
  -- The unique pair plus conditional update makes repeated/concurrent taps atomic.
  insert into private.crew_nudge_cooldowns(actor_id,recipient_id,last_sent_at)
    values(uid,target_user_id,request_time)
    on conflict(actor_id,recipient_id) do update set last_sent_at=excluded.last_sent_at
      where private.crew_nudge_cooldowns.last_sent_at <= request_time-interval '24 hours'
    returning last_sent_at into sent_at;
  if sent_at is null then
    select n.last_sent_at+interval '24 hours' into next_at from private.crew_nudge_cooldowns n
      where n.actor_id=uid and n.recipient_id=target_user_id;
    return jsonb_build_object('status','cooldown','next_allowed_at',next_at);
  end if;
  -- Profile metadata is display text only, never an authorization source.
  select coalesce(nullif(left(trim(raw_user_meta_data->>'first_name'),60),''),'A crew member')
    into actor_name from auth.users where id=uid;
  insert into private.notification_events(id,dedupe_key,type,crew_id,actor_id,payload)
    values(event_id,'crew_nudge:'||event_id,'crew_nudge',target_crew_id,uid,
      jsonb_build_object('actor_name',coalesce(actor_name,'A crew member'),'recipient_id',target_user_id,'completed_on',today));
  insert into private.notification_inbox(event_id,recipient_id) values(event_id,target_user_id);
  insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select event_id,device_id,target_user_id from unnest(device_ids) device_id;
  perform private.wake_notification_dispatcher();
  return jsonb_build_object('status','sent','next_allowed_at',sent_at+interval '24 hours');
end;
$$;

-- One page of the reader's own notifications, newest first.
--
-- Names and avatars are read live rather than from the payload, so the list
-- ages the way the feed does; the pact title comes from the payload, because
-- that is the only copy that survives the pact being deleted.
create function private.notification_inbox(
  before_created_at timestamptz,
  before_event uuid,
  page_limit int
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  result jsonb;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- A cursor is the complete sort key, or nothing at all.
  if (before_created_at is null) <> (before_event is null) then
    raise exception 'Invalid notification cursor' using errcode = '22023';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(entry) order by entry.created_at desc, entry.event_id desc),
    '[]'::jsonb
  ) into result
  from (
    select
      n.event_id,
      n.created_at,
      n.read_at is not null as read,
      e.type,
      e.crew_id,
      c.name as crew_name,
      e.actor_id,
      coalesce(nullif(trim(concat_ws(' ',
        nullif(trim(u.raw_user_meta_data->>'first_name'), ''),
        nullif(trim(u.raw_user_meta_data->>'last_name'), ''))), ''),
        'Crew member') as display_name,
      case
        when u.raw_user_meta_data->>'avatar_path' = u.id::text || '/avatar.png'
        then u.id::text || '/avatar.png'
      end as avatar_path,
      e.payload->>'pact_title' as pact_title,
      p.icon_key,
      coalesce((e.payload->>'clap_count')::int, 0) as clap_count
    from private.notification_inbox n
    join private.notification_events e on e.id = n.event_id
    join public.crews c on c.id = e.crew_id
    join auth.users u on u.id = e.actor_id
    left join public.crew_pacts p on p.id = (e.payload->>'pact_id')::uuid
    where n.recipient_id = viewer
      and (before_created_at is null
        or (n.created_at, n.event_id) < (before_created_at, before_event))
    order by n.created_at desc, n.event_id desc
    limit least(greatest(coalesce(page_limit, 20), 1), 50)
  ) entry;
  return result;
end;
$$;
revoke all on function private.notification_inbox(timestamptz,uuid,int) from public, anon;
grant execute on function private.notification_inbox(timestamptz,uuid,int) to authenticated;
create function public.notification_inbox(
  before_created_at timestamptz, before_event uuid, page_limit int
) returns jsonb language sql security invoker set search_path = '' as $$
  select private.notification_inbox(before_created_at, before_event, page_limit);
$$;
revoke all on function public.notification_inbox(timestamptz,uuid,int) from public, anon;
grant execute on function public.notification_inbox(timestamptz,uuid,int) to authenticated;

-- What the badge counts. Capped, because past a point the number stops meaning
-- anything and the query should not pay for the rest.
create function private.unread_notification_count() returns integer
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := (select auth.uid());
begin
  if viewer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return (select count(*) from (
    select 1 from private.notification_inbox n
    where n.recipient_id = viewer and n.read_at is null
    limit 100) capped);
end;
$$;
revoke all on function private.unread_notification_count() from public, anon;
grant execute on function private.unread_notification_count() to authenticated;
create function public.unread_notification_count() returns integer
language sql security invoker set search_path = '' as $$
  select private.unread_notification_count();
$$;
revoke all on function public.unread_notification_count() from public, anon;
grant execute on function public.unread_notification_count() to authenticated;

-- Reading the list clears it to the point the reader actually saw, so a
-- notification that arrived while the page was open is still unread after.
create function private.mark_notifications_read(up_to timestamptz)
returns integer language plpgsql security definer set search_path = '' as $$
declare viewer uuid := (select auth.uid()); cleared integer;
begin
  if viewer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update private.notification_inbox n set read_at = now()
  where n.recipient_id = viewer and n.read_at is null
    and (up_to is null or n.created_at <= up_to);
  get diagnostics cleared = row_count;
  return cleared;
end;
$$;
revoke all on function private.mark_notifications_read(timestamptz) from public, anon;
grant execute on function private.mark_notifications_read(timestamptz) to authenticated;
create function public.mark_notifications_read(up_to timestamptz default null)
returns integer language sql security invoker set search_path = '' as $$
  select private.mark_notifications_read(up_to);
$$;
revoke all on function public.mark_notifications_read(timestamptz) from public, anon;
grant execute on function public.mark_notifications_read(timestamptz) to authenticated;

-- Existing events keep whatever history their delivery records preserve: those
-- rows named the actual recipients at the time, which current membership does
-- not. Everyone who had no device registered then has no history to recover,
-- and all of it arrives read — a list that opens with months of unread counts
-- is a worse first impression than one that opens quiet.
insert into private.notification_inbox(event_id, recipient_id, created_at, read_at)
select d.event_id, d.recipient_id, min(e.created_at), now()
from private.notification_deliveries d
join private.notification_events e on e.id = d.event_id
group by d.event_id, d.recipient_id
on conflict do nothing;

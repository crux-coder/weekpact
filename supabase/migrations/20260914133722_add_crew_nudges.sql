-- One cooldown per sender/recipient, even when they share several crews.
create table private.crew_nudge_cooldowns (
  actor_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  last_sent_at timestamptz not null,
  primary key (actor_id, recipient_id),
  check (actor_id <> recipient_id)
);
create index crew_nudge_cooldowns_recipient_idx on private.crew_nudge_cooldowns(recipient_id);
alter table private.crew_nudge_cooldowns enable row level security;
revoke all on private.crew_nudge_cooldowns from public, anon, authenticated;
create policy crew_nudge_cooldowns_no_direct_access on private.crew_nudge_cooldowns
  for all to authenticated using(false) with check(false);

-- Private definers own narrowly scoped authorization. Exposed RPCs are invokers.
create function private.crew_nudge_status(target_crew_id uuid)
returns table(recipient_id uuid, status text, next_allowed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); today date;
begin
  if uid is null or not exists(select 1 from public.crew_members m where m.crew_id=target_crew_id and m.user_id=uid) then
    raise exception 'Crew membership required' using errcode='42501';
  end if;
  select (now() at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=target_crew_id;
  return query
    select m.user_id,
      case
        when exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
          where p.crew_id=target_crew_id and i.user_id=m.user_id and i.completed_on=today) then 'checked_in'
        when n.last_sent_at > now()-interval '24 hours' then 'cooldown'
        when not exists(select 1 from public.crew_pacts p where p.crew_id=target_crew_id)
          or not exists(select 1 from private.push_devices d join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
            where d.user_id=m.user_id and d.updated_at>now()-interval '60 days') then 'unavailable'
        else 'ready'
      end,
      case when n.last_sent_at > now()-interval '24 hours' then n.last_sent_at+interval '24 hours' end
    from public.crew_members m left join private.crew_nudge_cooldowns n on n.actor_id=uid and n.recipient_id=m.user_id
    where m.crew_id=target_crew_id and m.user_id<>uid;
end;
$$;
revoke all on function private.crew_nudge_status(uuid) from public, anon;
grant execute on function private.crew_nudge_status(uuid) to authenticated;
create function public.crew_nudge_status(target_crew_id uuid)
returns table(recipient_id uuid, status text, next_allowed_at timestamptz)
language sql security invoker set search_path = '' as $$
  select * from private.crew_nudge_status(target_crew_id);
$$;
revoke all on function public.crew_nudge_status(uuid) from public, anon;
grant execute on function public.crew_nudge_status(uuid) to authenticated;

create function private.send_crew_nudge(target_crew_id uuid, target_user_id uuid)
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
  insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select event_id,device_id,target_user_id from unnest(device_ids) device_id;
  perform private.wake_notification_dispatcher();
  return jsonb_build_object('status','sent','next_allowed_at',sent_at+interval '24 hours');
end;
$$;
revoke all on function private.send_crew_nudge(uuid,uuid) from public, anon;
grant execute on function private.send_crew_nudge(uuid,uuid) to authenticated;
create function public.send_crew_nudge(target_crew_id uuid, target_user_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.send_crew_nudge(target_crew_id,target_user_id);
$$;
revoke all on function public.send_crew_nudge(uuid,uuid) from public, anon;
grant execute on function public.send_crew_nudge(uuid,uuid) to authenticated;

-- Drop stale nudges before delivery if the person already checked in or the crew day changed.
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


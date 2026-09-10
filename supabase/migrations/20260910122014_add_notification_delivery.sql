-- Devices and delivery data are server-only; authenticated clients use narrow RPCs.
create table private.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  token text not null unique check (length(token) between 20 and 4096),
  platform text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);
create index push_devices_user_idx on private.push_devices(user_id);
alter table private.push_devices enable row level security;

create table private.notification_events (
  id uuid primary key default gen_random_uuid(),
  dedupe_key text not null unique,
  type text not null,
  crew_id uuid not null references public.crews(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
alter table private.notification_events enable row level security;
create table private.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references private.notification_events(id) on delete cascade,
  device_id uuid not null references private.push_devices(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','sending','sent','failed','cancelled')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  lease_id uuid,
  sent_at timestamptz,
  last_error text,
  unique(event_id, device_id)
);
create index notification_delivery_queue_idx on private.notification_deliveries(available_at)
  where status in ('pending','sending');
alter table private.notification_deliveries enable row level security;
revoke all on private.push_devices, private.notification_events, private.notification_deliveries from public, anon, authenticated;

create function public.register_push_device(device_token text, device_platform text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sid uuid := (auth.jwt()->>'session_id')::uuid;
begin
  if uid is null or not exists (select 1 from auth.sessions where id = sid and user_id = uid) then
    raise exception 'Active session required' using errcode = '42501';
  end if;
  if length(device_token) not between 20 and 4096 or device_token is null or device_platform not in ('ios','android') or device_platform is null then
    raise exception 'Invalid push registration' using errcode = '22023';
  end if;
  insert into private.push_devices(user_id, session_id, token, platform)
  values(uid, sid, device_token, device_platform)
  on conflict(token) do update set user_id = uid, session_id = sid, platform = excluded.platform, updated_at = now()
  where private.push_devices.user_id = uid or not exists (
    select 1 from auth.sessions s where s.id = private.push_devices.session_id and s.user_id = private.push_devices.user_id
  );
  if not found then raise exception 'Device belongs to another active session' using errcode = '42501'; end if;
end;
$$;
create function public.unregister_push_device(device_token text)
returns void language sql security definer set search_path = '' as $$
  delete from private.push_devices where token = device_token and user_id = (select auth.uid());
$$;
revoke all on function public.register_push_device(text,text), public.unregister_push_device(text) from public, anon;
grant execute on function public.register_push_device(text,text), public.unregister_push_device(text) to authenticated;

-- Replaced by the deployment scheduler setup; saving check-ins never needs cloud credentials.
create function private.wake_notification_dispatcher() returns void language plpgsql set search_path = '' as $$ begin return; end; $$;
revoke all on function private.wake_notification_dispatcher() from public, anon, authenticated;

create function private.notify_goal_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare event_id uuid; crew uuid; goal_title text; actor_name text;
begin
  select g.crew_id, g.title into crew, goal_title from public.crew_goals g where g.id = new.goal_id;
  -- Metadata supplies display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(raw_user_meta_data->>'first_name'),60),''),'A crew member') into actor_name
    from auth.users where id = new.user_id;
  insert into private.notification_events(dedupe_key,type,crew_id,actor_id,payload)
  values('goal_completed:'||new.goal_id||':'||new.user_id||':'||new.completed_on,
    'goal_completed',crew,new.user_id,jsonb_build_object('goal_id',new.goal_id,'goal_title',left(goal_title,120),
      'actor_name',coalesce(actor_name,'A crew member'),'completed_on',new.completed_on))
  on conflict(dedupe_key) do nothing returning id into event_id;
  if event_id is not null then
    insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select event_id,d.id,m.user_id from public.crew_members m
      join private.push_devices d on d.user_id = m.user_id
      join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
    where m.crew_id = crew and m.user_id <> new.user_id
      and d.updated_at > now() - interval '60 days';
    perform private.wake_notification_dispatcher();
  end if;
  return new;
end;
$$;
revoke all on function private.notify_goal_completed() from public, anon, authenticated;
create trigger goal_completed_notification after insert on public.goal_check_ins
for each row execute function private.notify_goal_completed();

create function public.claim_notification_deliveries(batch_size integer default 20)
returns table(delivery_id uuid, lease uuid, device_token text, event_type text, event_id uuid, crew_id uuid, payload jsonb)
language plpgsql security definer set search_path = '' as $$
begin
  -- Invalidate queued work if membership/session/goal state changed after enqueue.
  update private.notification_deliveries d set status = 'cancelled', last_error = 'recipient_or_event_unavailable'
  from private.notification_events e, private.push_devices p
  where d.event_id=e.id and d.device_id=p.id and d.status in ('pending','sending')
    and (e.created_at < now()-interval '24 hours' or p.user_id <> d.recipient_id
      or not exists(select 1 from auth.sessions s where s.id=p.session_id and s.user_id=p.user_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=d.recipient_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=e.actor_id)
      or (e.type='goal_completed' and not exists(select 1 from public.goal_check_ins i
        where i.goal_id=(e.payload->>'goal_id')::uuid and i.user_id=e.actor_id and i.completed_on=(e.payload->>'completed_on')::date)));
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

create function public.finish_notification_delivery(delivery uuid, lease uuid, outcome text, failure_code text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if outcome not in ('sent','retry','failed','unregistered') then raise exception 'Invalid outcome'; end if;
  if outcome='unregistered' then
    delete from private.push_devices p using private.notification_deliveries d
      where d.id=delivery and d.lease_id=lease and d.status='sending' and d.device_id=p.id;
    return;
  end if;
  update private.notification_deliveries d set
    status=case when outcome='retry' and attempts<8 then 'pending' when outcome='retry' then 'failed' else outcome end,
    available_at=now()+make_interval(secs => least(3600,30*power(2,attempts)::integer)),
    sent_at=case when outcome='sent' then now() else null end,
    last_error=left(failure_code,100), lease_id=null
  where d.id=delivery and d.lease_id=lease and d.status='sending';
end;
$$;
revoke all on function public.claim_notification_deliveries(integer), public.finish_notification_delivery(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.claim_notification_deliveries(integer), public.finish_notification_delivery(uuid,uuid,text,text) to service_role;

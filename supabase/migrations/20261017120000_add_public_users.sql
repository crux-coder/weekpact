-- Profiles move out of Auth's user metadata into a table of their own.
--
-- Names, avatars and whether onboarding is done used to live in
-- raw_user_meta_data, which only Auth could write and which nobody could reset
-- without editing the auth schema. public.users holds them instead, one row
-- per Auth user under the same id. A trigger creates the row when Auth creates
-- the user, copying whatever metadata the sign-up carried; the foreign key
-- removes it when Auth deletes the user, in the same transaction, so there is
-- never a profile without an account or an account without a profile.
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  first_name text not null default '',
  last_name text not null default '',
  avatar_path text,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint users_first_name_length check (char_length(first_name) <= 60),
  constraint users_last_name_length check (char_length(last_name) <= 60),
  -- The avatar bucket is keyed by owner, so the only path a profile may name
  -- is its own.
  constraint users_avatar_path_own check (avatar_path is null or avatar_path = id::text || '/avatar.png'),
  -- Onboarding is the form that asks for a first name; finishing it without one
  -- is not finishing it.
  constraint users_onboarding_needs_name check (not onboarding_completed or first_name <> '')
);

alter table public.users enable row level security;
revoke all on public.users from public, anon, authenticated;
grant select on public.users to authenticated;
-- Email and id follow Auth; a person edits only what the profile form asks.
grant update (first_name, last_name, avatar_path, onboarding_completed) on public.users to authenticated;
create policy users_read_own on public.users for select to authenticated
  using (id = (select auth.uid()));
create policy users_update_own on public.users for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create function private.touch_user() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger touch_user before update on public.users
for each row execute function private.touch_user();

-- Metadata is read once, at creation, and trimmed to what the table accepts.
-- After that the table is the only copy anything reads.
create function private.insert_user_profile(user_id uuid, user_email text, meta jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.users(id, email, first_name, last_name, avatar_path, onboarding_completed)
  values (
    user_id,
    user_email,
    left(coalesce(trim(meta->>'first_name'), ''), 60),
    left(coalesce(trim(meta->>'last_name'), ''), 60),
    case when meta->>'avatar_path' = user_id::text || '/avatar.png' then meta->>'avatar_path' end,
    coalesce(meta->>'onboarding_completed' = 'true', false) and coalesce(trim(meta->>'first_name'), '') <> ''
  )
  on conflict (id) do nothing;
$$;
revoke all on function private.insert_user_profile(uuid, text, jsonb) from public, anon, authenticated;

create function private.create_user_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.insert_user_profile(new.id, new.email, coalesce(new.raw_user_meta_data, '{}'::jsonb));
  return new;
end;
$$;
revoke all on function private.create_user_profile() from public, anon, authenticated;
create trigger create_user_profile after insert on auth.users
for each row execute function private.create_user_profile();

-- A confirmed email change in Auth is the only way the address moves.
create function private.sync_user_email() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.users set email = new.email where id = new.id;
  return new;
end;
$$;
revoke all on function private.sync_user_email() from public, anon, authenticated;
create trigger sync_user_email after update of email on auth.users
for each row when (old.email is distinct from new.email)
execute function private.sync_user_email();

-- Everyone who signed up before this migration.
select private.insert_user_profile(u.id, u.email, coalesce(u.raw_user_meta_data, '{}'::jsonb))
from auth.users u;

-- Every read of a name or avatar now goes to the table. The bodies below are
-- unchanged apart from where those fields come from.

create or replace function private.crew_member_profile(target_crew uuid, target_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'display_name', coalesce(nullif(trim(concat_ws(' ', nullif(trim(u.first_name), ''), nullif(trim(u.last_name), ''))), ''), 'Crew member'),
    'avatar_path', case when u.avatar_path = u.id::text || '/avatar.png' then u.id::text || '/avatar.png' else null end
  ) from public.users u
  where u.id = target_user and (select auth.uid()) is not null
    and exists (select 1 from public.crew_members m where m.crew_id = target_crew and m.user_id = (select auth.uid()))
    and exists (select 1 from public.crew_members m where m.crew_id = target_crew and m.user_id = target_user);
$$;

create or replace function private.notify_pact_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare crew uuid; pact_title text; actor_name text;
begin
  select g.crew_id,g.title into crew,pact_title from public.crew_pacts g where g.id=new.pact_id;
  select coalesce(nullif(left(trim(first_name),60),''),'A crew member')
    into actor_name from public.users where id=new.user_id;
  perform private.enqueue_crew_notification('pact_completed',
    'pact_completed:'||new.pact_id||':'||new.user_id||':'||new.completed_on,
    crew,new.user_id,jsonb_build_object('pact_id',new.pact_id,'pact_title',left(pact_title,120),
      'actor_name',coalesce(actor_name,'A crew member'),'completed_on',new.completed_on));
  return new;
end;
$$;

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

  -- Names supply display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(first_name), 60), ''), 'A crew member')
    into actor_name from public.users where id = actor;
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
  -- Profile names are display text only, never an authorization source.
  select coalesce(nullif(left(trim(first_name),60),''),'A crew member')
    into actor_name from public.users where id=uid;
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

create or replace function private.notification_inbox(
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
        nullif(trim(u.first_name), ''),
        nullif(trim(u.last_name), ''))), ''),
        'Crew member') as display_name,
      case
        when u.avatar_path = u.id::text || '/avatar.png'
        then u.id::text || '/avatar.png'
      end as avatar_path,
      e.payload->>'pact_title' as pact_title,
      p.icon_key,
      coalesce((e.payload->>'clap_count')::int, 0) as clap_count
    from private.notification_inbox n
    join private.notification_events e on e.id = n.event_id
    join public.crews c on c.id = e.crew_id
    join public.users u on u.id = e.actor_id
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

create or replace function private.preview_crew_invite(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare digest text; target uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to view this invite' using errcode='42501'; end if;
  -- An unknown or expired token is not an error here: the page falls back to
  -- its own copy, and a token that is merely wrong should say no more than
  -- one that is right about a crew the viewer cannot see.
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then return null; end if;
  digest := encode(extensions.digest(p_token,'sha256'),'hex');
  select crew_id into target from private.crew_share_links
    where token_hash=digest and expires_at>now();
  if target is null then
    select crew_id into target from public.crew_invites
      where token_hash=digest and accepted_at is null and expires_at>now();
  end if;
  if target is null then return null; end if;
  return (select jsonb_build_object(
    'crew_name', c.name,
    'member_count', (select count(*) from public.crew_members m where m.crew_id=c.id),
    'owner_name', coalesce(nullif(trim(concat_ws(' ',
      nullif(trim(u.first_name),''),
      nullif(trim(u.last_name),''))),''), 'Crew member')
  ) from public.crews c join public.users u on u.id=c.owner_id where c.id=target);
end;
$$;


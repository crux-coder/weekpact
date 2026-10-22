-- Achievements: a win a member posts to their crew outside any pact — a first
-- 6c, a five mile run. They sit in Home's stories rail beside the day's
-- check-ins and take claps the way a check-in does, but they are their own
-- rows: a pact check-in is a promise kept, and an achievement keeps nothing,
-- so it never counts toward a week, a streak or a nudge.
--
-- An achievement belongs to the crew it was posted to, and to the crew's day
-- it was posted on, so the rail shows it for exactly as long as it shows a
-- check-in made at the same moment.
create table public.crew_achievements (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid not null references public.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  posted_on date not null,
  created_at timestamptz not null default now(),
  constraint crew_achievements_body_length
    check (char_length(body) between 1 and 160 and body = trim(body))
);
-- The rail's one read: a crew's day.
create index crew_achievements_crew_day_idx
  on public.crew_achievements(crew_id, posted_on, created_at);
create index crew_achievements_user_idx on public.crew_achievements(user_id);
alter table public.crew_achievements enable row level security;
revoke all on public.crew_achievements from public, anon, authenticated;
grant all on public.crew_achievements to service_role;
-- Posting, reading and deleting go through the functions below, which check
-- crew membership and authorship themselves.
create policy crew_achievements_no_direct_access on public.crew_achievements
  for all to authenticated using (false) with check (false);

-- One clap per member per achievement, as `check_in_claps` is per check-in.
create table public.achievement_claps (
  achievement_id uuid not null references public.crew_achievements(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (achievement_id, actor_id)
);
create index achievement_claps_actor_idx on public.achievement_claps(actor_id);
alter table public.achievement_claps enable row level security;
revoke all on public.achievement_claps from public, anon, authenticated;
grant all on public.achievement_claps to service_role;
create policy achievement_claps_no_direct_access on public.achievement_claps
  for all to authenticated using (false) with check (false);

-- The crew's day in achievements, oldest first, each with its claps.
create function private.crew_achievements(target_crew_id uuid, on_day date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if not private.is_crew_member(target_crew_id, viewer) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', a.id, 'user_id', a.user_id, 'posted_on', a.posted_on,
        'body', a.body, 'created_at', a.created_at,
        'clap_count', (select count(*) from public.achievement_claps k
          where k.achievement_id = a.id),
        'viewer_clapped', exists(select 1 from public.achievement_claps k
          where k.achievement_id = a.id and k.actor_id = viewer))
      order by a.created_at, a.id)
    from public.crew_achievements a
    where a.crew_id = target_crew_id and a.posted_on = on_day
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.crew_achievements(uuid, date) from public, anon;
grant execute on function private.crew_achievements(uuid, date) to authenticated;

create function public.crew_achievements(target_crew_id uuid, on_day date)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.crew_achievements(target_crew_id, on_day);
$$;
revoke all on function public.crew_achievements(uuid, date) from public, anon;
grant execute on function public.crew_achievements(uuid, date) to authenticated;

-- Posts an achievement to a crew, dated by the crew's own clock the way a
-- check-in is. Capped per member per crew day, so the rail stays a day's
-- highlights rather than a feed.
create function private.post_crew_achievement(target_crew_id uuid, achievement_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  cleaned text := trim(coalesce(achievement_body, ''));
  today date;
  posted public.crew_achievements;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not private.is_crew_member(target_crew_id, viewer) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if char_length(cleaned) not between 1 and 160 then
    raise exception 'An achievement is 1 to 160 characters' using errcode = '22023';
  end if;
  select (now() at time zone coalesce(t.name, 'UTC'))::date into today
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone
  where c.id = target_crew_id;
  -- Serializes one member's posts to one crew, so two at once cannot both
  -- slip under the cap.
  perform pg_advisory_xact_lock(hashtextextended(target_crew_id::text || viewer::text, 0));
  if (select count(*) from public.crew_achievements a
      where a.crew_id = target_crew_id and a.user_id = viewer and a.posted_on = today) >= 5 then
    raise exception 'That is five achievements today' using errcode = '23514';
  end if;
  insert into public.crew_achievements(crew_id, user_id, body, posted_on)
  values (target_crew_id, viewer, cleaned, today)
  returning * into posted;
  return jsonb_build_object(
    'id', posted.id, 'user_id', posted.user_id, 'posted_on', posted.posted_on,
    'body', posted.body, 'created_at', posted.created_at,
    'clap_count', 0, 'viewer_clapped', false);
end;
$$;
revoke all on function private.post_crew_achievement(uuid, text) from public, anon;
grant execute on function private.post_crew_achievement(uuid, text) to authenticated;

create function public.post_crew_achievement(target_crew_id uuid, achievement_body text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.post_crew_achievement(target_crew_id, achievement_body);
$$;
revoke all on function public.post_crew_achievement(uuid, text) from public, anon;
grant execute on function public.post_crew_achievement(uuid, text) to authenticated;

-- Only its author takes an achievement down; its claps go with it.
create function private.delete_crew_achievement(target_achievement_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  delete from public.crew_achievements a
  where a.id = target_achievement_id and a.user_id = (select auth.uid());
end;
$$;
revoke all on function private.delete_crew_achievement(uuid) from public, anon;
grant execute on function private.delete_crew_achievement(uuid) to authenticated;

create function public.delete_crew_achievement(target_achievement_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.delete_crew_achievement(target_achievement_id);
$$;
revoke all on function public.delete_crew_achievement(uuid) from public, anon;
grant execute on function public.delete_crew_achievement(uuid) to authenticated;

-- Tells an achievement's author that someone clapped it.
--
-- Simpler than the check-in clap's window: one notification per clapper per
-- achievement, ever, keyed in the event's dedupe key. An achievement is posted
-- once and clapped by a handful of people, so there is no stream of claps to
-- fold together, and taking a clap back and giving it again does not knock
-- twice.
create function private.notify_achievement_clap(target_achievement_id uuid, actor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  author uuid;
  crew uuid;
  achievement_text text;
  actor_name text;
  event uuid;
begin
  select a.user_id, a.crew_id, left(a.body, 120)
    into author, crew, achievement_text
  from public.crew_achievements a where a.id = target_achievement_id;
  if author is null or author = actor then return; end if;
  -- Names supply display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(first_name), 60), ''), 'A crew member')
    into actor_name from public.users where id = actor;
  insert into private.notification_events(dedupe_key, type, crew_id, actor_id, payload)
  values ('achievement_clapped:' || target_achievement_id || ':' || actor,
    'achievement_clapped', crew, actor,
    jsonb_build_object(
      'recipient_id', author, 'achievement_id', target_achievement_id,
      'achievement_text', achievement_text,
      'actor_name', coalesce(actor_name, 'A crew member')))
  on conflict (dedupe_key) do nothing
  returning id into event;
  if event is null then return; end if;
  insert into private.notification_inbox(event_id, recipient_id) values (event, author);
  insert into private.notification_deliveries(event_id, device_id, recipient_id)
    select event, d.id, author
    from private.push_devices d
    join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
    where d.user_id = author and d.updated_at > now() - interval '60 days';
  if found then perform private.wake_notification_dispatcher(); end if;
end;
$$;
revoke all on function private.notify_achievement_clap(uuid, uuid) from public, anon, authenticated;

create function private.set_achievement_clap(target_achievement_id uuid, clapped boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  inserted integer := 0;
begin
  if viewer is null or clapped is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- Membership in the achievement's crew is re-checked here rather than
  -- trusted from whichever page the tap came from.
  if not exists (
    select 1 from public.crew_achievements a
    join public.crew_members m on m.crew_id = a.crew_id and m.user_id = viewer
    where a.id = target_achievement_id
  ) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  -- Both directions are idempotent, as a check-in clap's are.
  if clapped then
    insert into public.achievement_claps(achievement_id, actor_id)
    values (target_achievement_id, viewer)
    on conflict do nothing;
    get diagnostics inserted = row_count;
    if inserted > 0 then
      perform private.notify_achievement_clap(target_achievement_id, viewer);
    end if;
  else
    delete from public.achievement_claps c
    where c.achievement_id = target_achievement_id and c.actor_id = viewer;
  end if;
  return jsonb_build_object(
    'clap_count', (select count(*) from public.achievement_claps c
      where c.achievement_id = target_achievement_id),
    'viewer_clapped', clapped);
end;
$$;
revoke all on function private.set_achievement_clap(uuid, boolean) from public, anon;
grant execute on function private.set_achievement_clap(uuid, boolean) to authenticated;

create function public.set_achievement_clap(target_achievement_id uuid, clapped boolean)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.set_achievement_clap(target_achievement_id, clapped);
$$;
revoke all on function public.set_achievement_clap(uuid, boolean) from public, anon;
grant execute on function public.set_achievement_clap(uuid, boolean) to authenticated;

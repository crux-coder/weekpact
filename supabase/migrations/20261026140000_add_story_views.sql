-- Who saw a story. Until now "seen" lived only on the device that saw it, to
-- grey a ring; the poster now opens their own story on the crewmates who saw
-- it and who clapped, so a view becomes a row the poster can read back.
--
-- One table per kind of story, keyed the way its claps are, so taking down a
-- check-in or an achievement (or the account that saw it) takes its views
-- with it.
create table public.check_in_views (
  pact_id uuid not null,
  check_in_user_id uuid not null,
  completed_on date not null,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key (pact_id, check_in_user_id, completed_on, viewer_id),
  constraint check_in_views_check_in_fkey
    foreign key (pact_id, check_in_user_id, completed_on)
    references public.pact_check_ins(pact_id, user_id, completed_on)
    on delete cascade
);
create index check_in_views_viewer_idx on public.check_in_views(viewer_id);
alter table public.check_in_views enable row level security;
revoke all on public.check_in_views from public, anon, authenticated;
grant all on public.check_in_views to service_role;
create policy check_in_views_no_direct_access on public.check_in_views
  for all to authenticated using (false) with check (false);

create table public.achievement_views (
  achievement_id uuid not null references public.crew_achievements(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key (achievement_id, viewer_id)
);
create index achievement_views_viewer_idx on public.achievement_views(viewer_id);
alter table public.achievement_views enable row level security;
revoke all on public.achievement_views from public, anon, authenticated;
grant all on public.achievement_views to service_role;
create policy achievement_views_no_direct_access on public.achievement_views
  for all to authenticated using (false) with check (false);

-- Marks a check-in seen by the caller. Crew membership authorizes it, as it
-- does a clap; the poster's own look is not a view and is not written.
-- Idempotent: the first look is the one kept.
create function private.mark_check_in_seen(
  target_pact_id uuid, target_check_in_user uuid, target_day date
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.pact_check_ins i
    join public.crew_pacts p on p.id = i.pact_id
    join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
    where i.pact_id = target_pact_id
      and i.user_id = target_check_in_user
      and i.completed_on = target_day
  ) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if viewer = target_check_in_user then return; end if;
  insert into public.check_in_views(pact_id, check_in_user_id, completed_on, viewer_id)
  values (target_pact_id, target_check_in_user, target_day, viewer)
  on conflict do nothing;
end;
$$;
revoke all on function private.mark_check_in_seen(uuid, uuid, date) from public, anon;
grant execute on function private.mark_check_in_seen(uuid, uuid, date) to authenticated;

create function public.mark_check_in_seen(
  target_pact_id uuid, target_check_in_user uuid, target_day date
)
returns void language sql security invoker set search_path = '' as $$
  select private.mark_check_in_seen(target_pact_id, target_check_in_user, target_day);
$$;
revoke all on function public.mark_check_in_seen(uuid, uuid, date) from public, anon;
grant execute on function public.mark_check_in_seen(uuid, uuid, date) to authenticated;

create function private.mark_achievement_seen(target_achievement_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  poster uuid;
begin
  if viewer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select a.user_id into poster from public.crew_achievements a
  join public.crew_members m on m.crew_id = a.crew_id and m.user_id = viewer
  where a.id = target_achievement_id;
  if poster is null then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if viewer = poster then return; end if;
  insert into public.achievement_views(achievement_id, viewer_id)
  values (target_achievement_id, viewer)
  on conflict do nothing;
end;
$$;
revoke all on function private.mark_achievement_seen(uuid) from public, anon;
grant execute on function private.mark_achievement_seen(uuid) to authenticated;

create function public.mark_achievement_seen(target_achievement_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.mark_achievement_seen(target_achievement_id);
$$;
revoke all on function public.mark_achievement_seen(uuid) from public, anon;
grant execute on function public.mark_achievement_seen(uuid) to authenticated;

-- A story's audience, for its poster alone: everyone who saw it or clapped
-- it, each with their name and avatar and whether they clapped, claps first
-- and then the most recent.
-- A clap counts as a look, so claps given before views were recorded still
-- show who was there. The poster's own clap, which older builds allowed, is
-- left out.
create function private.check_in_audience(
  target_pact_id uuid, target_check_in_user uuid, target_day date
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or viewer <> target_check_in_user then
    raise exception 'Only the poster sees who saw it' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'user_id', people.user_id, 'seen_at', people.seen_at,
        'clapped', people.clapped,
        'display_name', coalesce(nullif(trim(concat_ws(' ',
          nullif(trim(u.first_name), ''), nullif(trim(u.last_name), ''))), ''),
          'Crew member'),
        'avatar_path', case when u.avatar_path = u.id::text || '/avatar.png'
          then u.avatar_path end)
      order by people.clapped desc, people.seen_at desc, people.user_id)
    from (
      select who.user_id, max(who.at) as seen_at, bool_or(who.clapped) as clapped
      from (
        select v.viewer_id as user_id, v.seen_at as at, false as clapped
        from public.check_in_views v
        where v.pact_id = target_pact_id
          and v.check_in_user_id = target_check_in_user
          and v.completed_on = target_day
        union all
        select k.actor_id, k.created_at, true
        from public.check_in_claps k
        where k.pact_id = target_pact_id
          and k.check_in_user_id = target_check_in_user
          and k.completed_on = target_day
      ) who
      where who.user_id <> viewer
      group by who.user_id
    ) people
    left join public.users u on u.id = people.user_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.check_in_audience(uuid, uuid, date) from public, anon;
grant execute on function private.check_in_audience(uuid, uuid, date) to authenticated;

create function public.check_in_audience(
  target_pact_id uuid, target_check_in_user uuid, target_day date
)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.check_in_audience(target_pact_id, target_check_in_user, target_day);
$$;
revoke all on function public.check_in_audience(uuid, uuid, date) from public, anon;
grant execute on function public.check_in_audience(uuid, uuid, date) to authenticated;

create function private.achievement_audience(target_achievement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not exists (
    select 1 from public.crew_achievements a
    where a.id = target_achievement_id and a.user_id = viewer
  ) then
    raise exception 'Only the poster sees who saw it' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'user_id', people.user_id, 'seen_at', people.seen_at,
        'clapped', people.clapped,
        'display_name', coalesce(nullif(trim(concat_ws(' ',
          nullif(trim(u.first_name), ''), nullif(trim(u.last_name), ''))), ''),
          'Crew member'),
        'avatar_path', case when u.avatar_path = u.id::text || '/avatar.png'
          then u.avatar_path end)
      order by people.clapped desc, people.seen_at desc, people.user_id)
    from (
      select who.user_id, max(who.at) as seen_at, bool_or(who.clapped) as clapped
      from (
        select v.viewer_id as user_id, v.seen_at as at, false as clapped
        from public.achievement_views v
        where v.achievement_id = target_achievement_id
        union all
        select k.actor_id, k.created_at, true
        from public.achievement_claps k
        where k.achievement_id = target_achievement_id
      ) who
      where who.user_id <> viewer
      group by who.user_id
    ) people
    left join public.users u on u.id = people.user_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.achievement_audience(uuid) from public, anon;
grant execute on function private.achievement_audience(uuid) to authenticated;

create function public.achievement_audience(target_achievement_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.achievement_audience(target_achievement_id);
$$;
revoke all on function public.achievement_audience(uuid) from public, anon;
grant execute on function public.achievement_audience(uuid) to authenticated;

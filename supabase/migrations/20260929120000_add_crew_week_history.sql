-- The crew week page learns to look back.
--
-- `crew_week_snapshot` gains a second form that takes a week: the same row it
-- has always returned, cut to that week's Monday to Sunday instead of to the
-- week we are in. `today` stays the real today, so a past week carries no
-- today marker and no future days, and the app renders it read-only without
-- being told to.
--
-- `crew_week_history` is the list under the page: one summary per finished
-- week, newest first, walking back from a week the caller names. It is
-- measured the way the streak is measured — against the crew's current pacts
-- and members, each counted from the week it arrived — so a crew that added a
-- pact in June is not marked down for every week before it.

drop function private.crew_week_snapshot(uuid);

create function private.crew_week_snapshot(target_crew_id uuid, target_week_start date)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  crew_zone text;
  today date;
  week_start date;
  week_end date;
  result jsonb;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(t.name, 'UTC') into crew_zone from public.crews c
  left join pg_catalog.pg_timezone_names t on t.name = c.timezone where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  week_start := date_trunc('week', today::timestamp)::date;
  if target_week_start is not null then
    if target_week_start > week_start + 6 then
      raise exception 'That week has not started' using errcode = '22023';
    end if;
    week_start := date_trunc('week', target_week_start::timestamp)::date;
  end if;
  week_end := least(week_start + 6, today);
  select jsonb_build_object(
    'streak_weeks', public.crew_weekly_streak(target_crew_id),
    'today', today, 'week_start', week_start, 'timezone', crew_zone,
    'pacts', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_pacts g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) || coalesce(private.crew_member_profile(target_crew_id, m.user_id), '{}'::jsonb) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on, 'photo_path', i.photo_path, 'created_at', i.created_at,
      'clap_count', (select count(*) from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on),
      'viewer_clapped', exists(select 1 from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on
          and k.actor_id = viewer))) from public.pact_check_ins i join public.crew_pacts g on g.id = i.pact_id where g.crew_id = target_crew_id and i.completed_on between week_start and week_end), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke all on function private.crew_week_snapshot(uuid, date) from public, anon;
grant execute on function private.crew_week_snapshot(uuid, date) to authenticated;

create or replace function public.crew_week_snapshot(target_crew_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $$
  select private.crew_week_snapshot(target_crew_id, null);
$$;
revoke all on function public.crew_week_snapshot(uuid) from public, anon;
grant execute on function public.crew_week_snapshot(uuid) to authenticated;

create function public.crew_week_snapshot(target_crew_id uuid, target_week_start date)
returns jsonb language sql volatile security invoker set search_path = '' as $$
  select private.crew_week_snapshot(target_crew_id, target_week_start);
$$;
revoke all on function public.crew_week_snapshot(uuid, date) from public, anon;
grant execute on function public.crew_week_snapshot(uuid, date) to authenticated;

-- Finished weeks before `before_week`, newest first, at most `week_count` of
-- them and never earlier than the crew's first week. Each carries the crew's
-- percentage for the week, figured as the app figures it (each person's kept
-- days capped at the pact's target, over everyone's targets together), and
-- the share of the crew that was out on each of the seven days.
create function private.crew_week_history(target_crew_id uuid, before_week date, week_count integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  crew_zone text;
  today date;
  current_week date;
  first_week date;
  last_week date;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if week_count < 1 or week_count > 52 then
    raise exception 'Ask for between 1 and 52 weeks' using errcode = '22023';
  end if;
  select coalesce(t.name, 'UTC'), date_trunc('week', c.created_at at time zone coalesce(t.name, 'UTC'))::date
    into crew_zone, first_week
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone
  where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  current_week := date_trunc('week', today::timestamp)::date;
  last_week := least(date_trunc('week', coalesce(before_week, current_week)::timestamp)::date, current_week) - 7;
  return coalesce((
    select jsonb_agg(jsonb_build_object('week_start', w.week_start, 'percent', w.percent, 'days', w.days) order by w.week_start desc)
    from (
      select s.week_start,
        coalesce((
          select round(100.0 * sum(least(g.days_per_week, (
            select count(distinct i.completed_on) from public.pact_check_ins i
            where i.pact_id = g.id and i.user_id = m.user_id
              and i.completed_on between s.week_start and s.week_start + 6
          ))) / nullif(sum(g.days_per_week), 0))::integer
          from public.crew_pacts g cross join public.crew_members m
          where g.crew_id = target_crew_id and m.crew_id = target_crew_id
            and (g.created_at at time zone crew_zone)::date <= s.week_start + 6
            and (m.joined_at at time zone crew_zone)::date <= s.week_start + 6
        ), 0) as percent,
        (
          select jsonb_agg(coalesce((
            select count(distinct i.user_id)::numeric from public.pact_check_ins i
            join public.crew_pacts g on g.id = i.pact_id
            join public.crew_members m on m.crew_id = g.crew_id and m.user_id = i.user_id
            where g.crew_id = target_crew_id and i.completed_on = s.week_start + d
          ) / nullif((select count(*) from public.crew_members m where m.crew_id = target_crew_id), 0), 0) order by d)
          from generate_series(0, 6) d
        ) as days
      from (
        select generate_series(last_week, greatest(first_week, last_week - 7 * (week_count - 1)), interval '-7 days')::date as week_start
      ) s
    ) w
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.crew_week_history(uuid, date, integer) from public, anon;
grant execute on function private.crew_week_history(uuid, date, integer) to authenticated;

create function public.crew_week_history(target_crew_id uuid, before_week date default null, week_count integer default 12)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.crew_week_history(target_crew_id, before_week, week_count);
$$;
revoke all on function public.crew_week_history(uuid, date, integer) from public, anon;
grant execute on function public.crew_week_history(uuid, date, integer) to authenticated;

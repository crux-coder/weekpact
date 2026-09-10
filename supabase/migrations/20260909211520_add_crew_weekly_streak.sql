-- Streaks use current goal targets and current members, starting with each
-- goal/member's first week. The unfinished current week is not a broken week.
create function public.crew_weekly_streak(target_crew_id uuid)
returns integer language plpgsql stable security invoker set search_path = '' as $$
declare
  crew_zone text;
  today date;
  current_week date;
  candidate date;
  first_week date;
  earned boolean;
  streak integer := 0;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(t.name, 'UTC'), date_trunc('week', c.created_at at time zone coalesce(t.name, 'UTC'))::date
    into crew_zone, first_week
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone
  where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  current_week := date_trunc('week', today::timestamp)::date;
  candidate := current_week;
  while candidate >= first_week loop
    select count(*) > 0 and bool_and(completed >= days_per_week) into earned
    from (
      select g.days_per_week, (
        select count(*) from public.goal_check_ins i
        where i.goal_id = g.id and i.user_id = m.user_id
          and i.completed_on between candidate and least(candidate + 6, today)
      ) as completed
      from public.crew_goals g cross join public.crew_members m
      where g.crew_id = target_crew_id and m.crew_id = target_crew_id
        and (g.created_at at time zone crew_zone)::date <= least(candidate + 6, today)
        and (m.joined_at at time zone crew_zone)::date <= least(candidate + 6, today)
    ) requirements;
    if earned then
      streak := streak + 1;
    elsif candidate <> current_week then
      exit;
    end if;
    candidate := candidate - 7;
  end loop;
  return streak;
end;
$$;
revoke all on function public.crew_weekly_streak(uuid) from public, anon;
grant execute on function public.crew_weekly_streak(uuid) to authenticated;

create or replace function public.crew_week_snapshot(target_crew_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  crew_zone text;
  today date;
  week_start date;
  result jsonb;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(t.name, 'UTC') into crew_zone from public.crews c
  left join pg_catalog.pg_timezone_names t on t.name = c.timezone where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  week_start := date_trunc('week', today::timestamp)::date;
  select jsonb_build_object(
    'streak_weeks', public.crew_weekly_streak(target_crew_id),
    'today', today, 'week_start', week_start, 'timezone', crew_zone,
    'goals', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_goals g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('goal_id', i.goal_id, 'user_id', i.user_id, 'completed_on', i.completed_on)) from public.goal_check_ins i join public.crew_goals g on g.id = i.goal_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;


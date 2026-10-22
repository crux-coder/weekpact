-- Each day of a finished week also says which pact the crew kept most, so the
-- streak card's month can colour a day by that pact.
--
-- `top_pacts` sits beside `days`: seven pact ids, Monday first, null for a
-- day nobody kept. The most check-ins wins; a tie goes to the older pact,
-- the one earlier in the crew's list. Counted the way `days` counts — current
-- members only — so a day reads the same in both.
--
-- Additive: the row keeps every key it had, so an app that does not know
-- `top_pacts` reads it as before.

create or replace function private.crew_week_history(target_crew_id uuid, before_week date, week_count integer)
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
    select jsonb_agg(jsonb_build_object('week_start', w.week_start, 'percent', w.percent, 'days', w.days, 'top_pacts', w.top_pacts) order by w.week_start desc)
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
        ) as days,
        (
          select jsonb_agg((
            select g.id from public.pact_check_ins i
            join public.crew_pacts g on g.id = i.pact_id
            join public.crew_members m on m.crew_id = g.crew_id and m.user_id = i.user_id
            where g.crew_id = target_crew_id and i.completed_on = s.week_start + d
            group by g.id, g.created_at
            order by count(*) desc, g.created_at, g.id
            limit 1
          ) order by d)
          from generate_series(0, 6) d
        ) as top_pacts
      from (
        select generate_series(last_week, greatest(first_week, last_week - 7 * (week_count - 1)), interval '-7 days')::date as week_start
      ) s
    ) w
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.crew_week_history(uuid, date, integer) from public, anon;
grant execute on function private.crew_week_history(uuid, date, integer) to authenticated;

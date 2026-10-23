-- Home loads its week in one call.
--
-- Home used to ask for the week, then the crew's latest check-in, then today's
-- achievements, then who can be nudged: four round trips, one after another.
-- `crew_week_overview` is the current week's snapshot with those three beside
-- it, so the page fills from a single reply. The calls it replaces stay as
-- they are, for apps that still make them.
--
-- The streak stops taking the finalize lock on every load. It used to run
-- `finalize_crew_weeks` each time, which serializes every member's load of a
-- crew behind one advisory lock; now it does so only when last week has not
-- been recorded yet, and counts the recorded weeks in one query rather than
-- one week at a time.

-- The latest check-in among a crew's pacts, newest first.
create index if not exists pact_check_ins_pact_created_idx
  on public.pact_check_ins (pact_id, created_at desc);

create or replace function private.frozen_crew_streak(p_crew uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare zone text; first_week date; candidate date; earned_now boolean; result integer;
begin
  if auth.uid() is null or not private.is_crew_member(p_crew,auth.uid()) then raise exception 'Crew membership required' using errcode='42501'; end if;
  select c.timezone, date_trunc('week', c.created_at at time zone c.timezone)::date
    into zone, first_week from public.crews c where c.id=p_crew;
  candidate:=date_trunc('week',now() at time zone zone)::date;
  if candidate > first_week and not exists(
      select 1 from private.crew_week_results r where r.crew_id=p_crew and r.week_start=candidate-7) then
    perform private.finalize_crew_weeks(p_crew);
  end if;
  select r.earned into earned_now from private.calculate_crew_week(p_crew,candidate,zone) r;
  -- Recorded weeks walking back from last week; the streak ends at the first
  -- one missed or missing.
  with weeks as (
    select r.week_start, r.earned, (row_number() over (order by r.week_start desc))::integer as back
    from private.crew_week_results r where r.crew_id=p_crew and r.week_start<candidate
  )
  select coalesce(
    (select min(back) from weeks where not earned or week_start <> candidate - 7 * back),
    (select count(*)::integer from weeks) + 1) - 1
  into result;
  return result + case when earned_now then 1 else 0 end;
end;
$$;

create function private.crew_week_overview(target_crew_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  week jsonb;
begin
  -- The snapshot checks membership, so everything after it is the crew's own.
  week := private.crew_week_snapshot(target_crew_id, null);
  return week || jsonb_build_object(
    'latest_activity', (
      select jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id,
        'created_at', i.created_at, 'photo_path', i.photo_path)
      from public.pact_check_ins i
      join public.crew_pacts g on g.id = i.pact_id
      join public.crew_members m on m.crew_id = g.crew_id and m.user_id = i.user_id
      where g.crew_id = target_crew_id
      order by i.created_at desc, i.pact_id desc, i.user_id desc
      limit 1),
    'achievements', private.crew_achievements(target_crew_id, (week->>'today')::date),
    'nudges', coalesce((
      select jsonb_agg(jsonb_build_object('recipient_id', n.recipient_id,
        'status', n.status, 'next_allowed_at', n.next_allowed_at))
      from private.crew_nudge_status(target_crew_id) n), '[]'::jsonb));
end;
$$;
revoke all on function private.crew_week_overview(uuid) from public, anon;
grant execute on function private.crew_week_overview(uuid) to authenticated;

create function public.crew_week_overview(target_crew_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $$
  select private.crew_week_overview(target_crew_id);
$$;
revoke all on function public.crew_week_overview(uuid) from public, anon;
grant execute on function public.crew_week_overview(uuid) to authenticated;

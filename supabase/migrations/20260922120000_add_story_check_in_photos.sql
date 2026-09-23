-- Home's stories rail opens a member's check-ins for today, so the week
-- snapshot has to say which of them carry a photo and when each was kept.
-- Both already sit on the check-in row; the snapshot simply stopped short of
-- them. The path is signed by the client, and only for today's check-ins —
-- the rest of the week is carried so the week still reads as one fetch.
--
-- Declared volatile, as `20260914170113_add_launch_foundations` made it: the
-- streak it folds in is volatile, and `create or replace` would otherwise put
-- the original `stable` back.
create or replace function public.crew_week_snapshot(target_crew_id uuid)
returns jsonb language plpgsql volatile security invoker set search_path = '' as $$
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
    'pacts', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_pacts g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) || coalesce(private.crew_member_profile(target_crew_id, m.user_id), '{}'::jsonb) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on, 'photo_path', i.photo_path, 'created_at', i.created_at)) from public.pact_check_ins i join public.crew_pacts g on g.id = i.pact_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

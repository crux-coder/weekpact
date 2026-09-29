-- Claps were write-only. Home's stories are built from the week snapshot, and
-- the snapshot said nothing about claps — so a check-in with five of them
-- opened reading "Clap", and a clap the viewer gave yesterday looked as though
-- it had never been given. The count only appeared once this session's own
-- write answered with one, which is a tally of the tap rather than of the
-- crew.
--
-- `check_in_claps` has no direct read path: it is revoked from authenticated
-- and its one policy refuses everything, because clapping goes through
-- `set_check_in_clap`. A `security invoker` snapshot therefore cannot see a
-- single row. So the body moves into `private` as a definer, the way
-- `private.set_check_in_clap` and `private.check_in_feed` already do it, and
-- `public.crew_week_snapshot` becomes the invoker wrapper callers keep using.
-- Crew membership is still what authorizes the whole answer, and it is still
-- checked first.
--
-- Declared volatile, as `20260914170113_add_launch_foundations` made it: the
-- streak it folds in is volatile, and `create or replace` would otherwise put
-- the original `stable` back.
create function private.crew_week_snapshot(target_crew_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
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
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on, 'photo_path', i.photo_path, 'created_at', i.created_at,
      'clap_count', (select count(*) from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on),
      'viewer_clapped', exists(select 1 from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on
          and k.actor_id = viewer))) from public.pact_check_ins i join public.crew_pacts g on g.id = i.pact_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke all on function private.crew_week_snapshot(uuid) from public, anon;
grant execute on function private.crew_week_snapshot(uuid) to authenticated;

create or replace function public.crew_week_snapshot(target_crew_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $$
  select private.crew_week_snapshot(target_crew_id);
$$;
revoke all on function public.crew_week_snapshot(uuid) from public, anon;
grant execute on function public.crew_week_snapshot(uuid) to authenticated;

-- Only expose display fields for members of the requested, shared crew.
create function private.crew_member_profile(target_crew uuid, target_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'display_name', coalesce(nullif(trim(concat_ws(' ', nullif(trim(u.raw_user_meta_data->>'first_name'), ''), nullif(trim(u.raw_user_meta_data->>'last_name'), ''))), ''), 'Crew member'),
    'avatar_path', case when u.raw_user_meta_data->>'avatar_path' = u.id::text || '/avatar.png' then u.id::text || '/avatar.png' else null end
  ) from auth.users u
  where u.id = target_user and (select auth.uid()) is not null
    and exists (select 1 from public.crew_members m where m.crew_id = target_crew and m.user_id = (select auth.uid()))
    and exists (select 1 from public.crew_members m where m.crew_id = target_crew and m.user_id = target_user);
$$;
revoke all on function private.crew_member_profile(uuid, uuid) from public, anon;
grant execute on function private.crew_member_profile(uuid, uuid) to authenticated;

create function private.can_read_crew_avatar(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.crew_members viewer
    join public.crew_members subject on subject.crew_id = viewer.crew_id
    where viewer.user_id = (select auth.uid())
      and object_name = subject.user_id::text || '/avatar.png'
  );
$$;
revoke all on function private.can_read_crew_avatar(text) from public, anon;
grant execute on function private.can_read_crew_avatar(text) to authenticated;
create policy avatars_read_shared_crew on storage.objects for select to authenticated
using (bucket_id = 'avatars' and private.can_read_crew_avatar(name));

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
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) || coalesce(private.crew_member_profile(target_crew_id, m.user_id), '{}'::jsonb) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('goal_id', i.goal_id, 'user_id', i.user_id, 'completed_on', i.completed_on)) from public.goal_check_ins i join public.crew_goals g on g.id = i.goal_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;


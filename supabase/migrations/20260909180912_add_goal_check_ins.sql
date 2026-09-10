create table public.goal_check_ins (
  goal_id uuid not null references public.crew_goals(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  completed_on date not null,
  created_at timestamptz not null default now(),
  primary key (goal_id, user_id, completed_on)
);
create index goal_check_ins_user_idx on public.goal_check_ins(user_id);
alter table public.goal_check_ins enable row level security;
revoke all on public.goal_check_ins from public, anon, authenticated;
grant select on public.goal_check_ins to authenticated;
grant all on public.goal_check_ins to service_role;
create policy check_ins_read_for_crew on public.goal_check_ins
for select to authenticated using (exists (
  select 1 from public.crew_goals g where g.id = goal_id
  and private.is_crew_member(g.crew_id, (select auth.uid()))
));

create function public.crew_week_snapshot(target_crew_id uuid)
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
    'today', today, 'week_start', week_start, 'timezone', crew_zone,
    'goals', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_goals g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('goal_id', i.goal_id, 'user_id', i.user_id, 'completed_on', i.completed_on)) from public.goal_check_ins i join public.crew_goals g on g.id = i.goal_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

-- Save today's entire selection atomically; callers cannot supply another user or backdate it.
create function public.save_goal_check_ins(target_crew_id uuid, expected_today date, selected_goal_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
  today date;
begin
  perform 1 from public.crew_members where crew_id = target_crew_id and user_id = current_user_id for update;
  if not found then raise exception 'Crew membership required' using errcode = '42501'; end if;
  select (now() at time zone coalesce(t.name, 'UTC'))::date into today
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone where c.id = target_crew_id;
  if expected_today is distinct from today then raise exception 'The day changed. Refresh before checking in.' using errcode = '22023'; end if;
  if selected_goal_ids is null or exists (
    select 1 from unnest(selected_goal_ids) selected(goal_id) where selected.goal_id is null or not exists (
      select 1 from public.crew_goals g where g.id = selected.goal_id and g.crew_id = target_crew_id
    )
  ) then raise exception 'Invalid goal selection' using errcode = '22023'; end if;
  delete from public.goal_check_ins i using public.crew_goals g
  where i.goal_id = g.id and g.crew_id = target_crew_id and i.user_id = current_user_id
    and i.completed_on = today and not (i.goal_id = any(selected_goal_ids));
  insert into public.goal_check_ins(goal_id, user_id, completed_on)
  select distinct id, current_user_id, today from unnest(selected_goal_ids) id
  on conflict do nothing;
end;
$$;
revoke all on function public.crew_week_snapshot(uuid) from public, anon;
revoke all on function public.save_goal_check_ins(uuid, date, uuid[]) from public, anon;
grant execute on function public.crew_week_snapshot(uuid) to authenticated;
grant execute on function public.save_goal_check_ins(uuid, date, uuid[]) to authenticated;

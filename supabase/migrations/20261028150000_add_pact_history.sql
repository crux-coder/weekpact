-- A person's record on each pact, for the history under their profile: every
-- week they kept it and how many days, the days of the last sixteen weeks for
-- a calendar, and the day they first kept it. Only adds things, so builds
-- that never ask for it are untouched.
--
-- Your own covers every pact in every crew you are in; a crewmate's covers
-- the pacts of the crews you share, the way their wall does, and asked about
-- somebody you share no crew with it refuses. Weeks run Monday to Sunday in
-- the crew's own calendar, as the check-ins' days already do, and a week is
-- measured against the pact's target as it stands now.
create function private.pact_history(target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if target_user_id is null
    or (target_user_id <> viewer and not exists (
      select 1 from public.crew_members x
      join public.crew_members y on y.crew_id = x.crew_id
      where x.user_id = viewer and y.user_id = target_user_id)) then
    raise exception 'Not a crewmate' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'pact_id', p.id,
      'crew_id', p.crew_id,
      'crew_name', c.name,
      'title', p.title,
      'icon_key', p.icon_key,
      'pact_index', (select count(*)::int from public.crew_pacts q
        where q.crew_id = p.crew_id and (q.created_at, q.id) < (p.created_at, p.id)),
      'days_per_week', p.days_per_week,
      'today', (now() at time zone c.timezone)::date,
      'first_day', (select min(i.completed_on) from public.pact_check_ins i
        where i.pact_id = p.id and i.user_id = target_user_id),
      'weeks', coalesce((select jsonb_agg(
          jsonb_build_object('start', w.week_start, 'kept', w.kept)
          order by w.week_start)
        from (
          select date_trunc('week', i.completed_on)::date as week_start,
            count(distinct i.completed_on)::int as kept
          from public.pact_check_ins i
          where i.pact_id = p.id and i.user_id = target_user_id
          group by 1
        ) w), '[]'::jsonb),
      'days', coalesce((select jsonb_agg(d.completed_on order by d.completed_on)
        from (
          select distinct i.completed_on from public.pact_check_ins i
          where i.pact_id = p.id and i.user_id = target_user_id
            and i.completed_on >=
              date_trunc('week', (now() at time zone c.timezone)::date)::date - 7 * 15
        ) d), '[]'::jsonb)
    ) order by m.joined_at, m.crew_id, p.created_at, p.id)
    from public.crew_pacts p
    join public.crews c on c.id = p.crew_id
    join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
    join public.crew_members t on t.crew_id = p.crew_id and t.user_id = target_user_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function private.pact_history(uuid) from public, anon;
grant execute on function private.pact_history(uuid) to authenticated;

create function public.my_pact_history()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.pact_history((select auth.uid()));
$$;
revoke all on function public.my_pact_history() from public, anon;
grant execute on function public.my_pact_history() to authenticated;

create function public.member_pact_history(target_user_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.pact_history(target_user_id);
$$;
revoke all on function public.member_pact_history(uuid) from public, anon;
grant execute on function public.member_pact_history(uuid) to authenticated;

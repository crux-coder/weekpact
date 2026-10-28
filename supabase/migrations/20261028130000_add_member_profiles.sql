-- A crewmate's profile: their check-ins and the summary that heads them, the
-- same wall Account shows you of yourself. Only adds things, so builds that
-- never ask for either are untouched.
--
-- You see only what you already could: check-ins kept in crews the two of you
-- are both still in, the way the feed and the photo bucket already scope them.
-- Asked about somebody you share no crew with, both refuse.
create function private.member_check_ins(
  target_user_id uuid,
  before_created_at timestamptz,
  before_pact uuid,
  before_day date,
  target_pact_id uuid,
  page_limit int
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  result jsonb;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if target_user_id is null
    or (target_user_id <> viewer and not private.shares_crew(viewer, target_user_id)) then
    raise exception 'Not a crewmate' using errcode = '42501';
  end if;
  if (before_created_at is null) <> (before_pact is null)
    or (before_created_at is null) <> (before_day is null) then
    raise exception 'Invalid check-in cursor' using errcode = '22023';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(entry) order by
      entry.created_at desc, entry.pact_id desc, entry.completed_on desc),
    '[]'::jsonb
  ) into result
  from (
    select
      i.pact_id,
      i.user_id,
      i.completed_on,
      i.created_at,
      i.photo_path,
      p.crew_id,
      c.name as crew_name,
      p.title as pact_title,
      p.icon_key,
      (select count(*)::int from public.crew_pacts q
        where q.crew_id = p.crew_id and (q.created_at, q.id) < (p.created_at, p.id)
      ) as pact_index,
      (select count(*)::int from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id
          and k.completed_on = i.completed_on) as clap_count
    from public.pact_check_ins i
    join public.crew_pacts p on p.id = i.pact_id
    join public.crews c on c.id = p.crew_id
    join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
    join public.crew_members t on t.crew_id = p.crew_id and t.user_id = target_user_id
    where i.user_id = target_user_id
      and (target_pact_id is null or i.pact_id = target_pact_id)
      and (before_created_at is null
        or (i.created_at, i.pact_id, i.completed_on)
           < (before_created_at, before_pact, before_day))
    order by i.created_at desc, i.pact_id desc, i.completed_on desc
    limit least(greatest(coalesce(page_limit, 30), 1), 60)
  ) entry;
  return result;
end;
$$;
revoke all on function private.member_check_ins(uuid, timestamptz, uuid, date, uuid, int) from public, anon;
grant execute on function private.member_check_ins(uuid, timestamptz, uuid, date, uuid, int) to authenticated;

create function public.member_check_ins(
  target_user_id uuid,
  before_created_at timestamptz default null,
  before_pact uuid default null,
  before_day date default null,
  target_pact_id uuid default null,
  page_limit int default 30
)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.member_check_ins(target_user_id, before_created_at, before_pact, before_day, target_pact_id, page_limit);
$$;
revoke all on function public.member_check_ins(uuid, timestamptz, uuid, date, uuid, int) from public, anon;
grant execute on function public.member_check_ins(uuid, timestamptz, uuid, date, uuid, int) to authenticated;

-- The header over a crewmate's wall: their check-ins and crews counted within
-- the crews you share, which crews those are, and the pacts they keep.
create function private.member_profile_summary(target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if target_user_id is null
    or (target_user_id <> viewer and not private.shares_crew(viewer, target_user_id)) then
    raise exception 'Not a crewmate' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'check_ins', (select count(*)::int
      from public.pact_check_ins i
      join public.crew_pacts p on p.id = i.pact_id
      join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
      join public.crew_members t on t.crew_id = p.crew_id and t.user_id = target_user_id
      where i.user_id = target_user_id),
    'crews', (select count(*)::int
      from public.crew_members m
      join public.crew_members t on t.crew_id = m.crew_id and t.user_id = target_user_id
      where m.user_id = viewer),
    'crew_ids', coalesce((select jsonb_agg(m.crew_id order by m.joined_at, m.crew_id)
      from public.crew_members m
      join public.crew_members t on t.crew_id = m.crew_id and t.user_id = target_user_id
      where m.user_id = viewer), '[]'::jsonb),
    'pacts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'crew_id', p.crew_id,
        'title', p.title,
        'icon_key', p.icon_key,
        'pact_index', (select count(*)::int from public.crew_pacts q
          where q.crew_id = p.crew_id and (q.created_at, q.id) < (p.created_at, p.id)))
      order by m.joined_at, m.crew_id, p.created_at, p.id)
      from public.crew_pacts p
      join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
      join public.crew_members t on t.crew_id = p.crew_id and t.user_id = target_user_id), '[]'::jsonb)
  );
end;
$$;
revoke all on function private.member_profile_summary(uuid) from public, anon;
grant execute on function private.member_profile_summary(uuid) to authenticated;

create function public.member_profile_summary(target_user_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.member_profile_summary(target_user_id);
$$;
revoke all on function public.member_profile_summary(uuid) from public, anon;
grant execute on function public.member_profile_summary(uuid) to authenticated;

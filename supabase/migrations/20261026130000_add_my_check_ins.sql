-- Account's photo wall: the viewer's own check-ins across every crew they are
-- still in, newest first, and the summary that heads it. Only adds things, so
-- builds that never ask for either are untouched.
--
-- A crew the viewer has left drops out of both, the way it drops out of the
-- feed: the wall is what you keep with the crews you keep it with.
create index if not exists pact_check_ins_user_created_idx on public.pact_check_ins
  (user_id, created_at desc, pact_id desc, completed_on desc);

create function private.my_check_ins(
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
  -- The viewer is the user on every row, so a cursor is the rest of the
  -- primary key plus its timestamp, or nothing at all.
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
      -- The pact's place in its crew's list, which is what its colour is
      -- read from everywhere else in the app.
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
    where i.user_id = viewer
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
revoke all on function private.my_check_ins(timestamptz, uuid, date, uuid, int) from public, anon;
grant execute on function private.my_check_ins(timestamptz, uuid, date, uuid, int) to authenticated;

create function public.my_check_ins(
  before_created_at timestamptz default null,
  before_pact uuid default null,
  before_day date default null,
  target_pact_id uuid default null,
  page_limit int default 30
)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.my_check_ins(before_created_at, before_pact, before_day, target_pact_id, page_limit);
$$;
revoke all on function public.my_check_ins(timestamptz, uuid, date, uuid, int) from public, anon;
grant execute on function public.my_check_ins(timestamptz, uuid, date, uuid, int) to authenticated;

-- The wall's header: how many check-ins, in how many crews, and the pacts
-- those crews keep, each with what it needs to be drawn as a filter.
create function private.my_profile_summary()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'check_ins', (select count(*)::int
      from public.pact_check_ins i
      join public.crew_pacts p on p.id = i.pact_id
      join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
      where i.user_id = viewer),
    'crews', (select count(*)::int from public.crew_members m where m.user_id = viewer),
    'pacts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'crew_id', p.crew_id,
        'title', p.title,
        'icon_key', p.icon_key,
        'pact_index', (select count(*)::int from public.crew_pacts q
          where q.crew_id = p.crew_id and (q.created_at, q.id) < (p.created_at, p.id)))
      order by m.joined_at, m.crew_id, p.created_at, p.id)
      from public.crew_pacts p
      join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer), '[]'::jsonb)
  );
end;
$$;
revoke all on function private.my_profile_summary() from public, anon;
grant execute on function private.my_profile_summary() to authenticated;

create function public.my_profile_summary()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.my_profile_summary();
$$;
revoke all on function public.my_profile_summary() from public, anon;
grant execute on function public.my_profile_summary() to authenticated;

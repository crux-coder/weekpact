-- Claps: one per member per check-in, applauding someone for keeping a pact.
-- The clap is keyed on the check-in's own primary key, so deleting a check-in
-- (or the account that posted it) takes its claps with it.
create table public.check_in_claps (
  pact_id uuid not null,
  check_in_user_id uuid not null,
  completed_on date not null,
  actor_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (pact_id, check_in_user_id, completed_on, actor_id),
  constraint check_in_claps_check_in_fkey
    foreign key (pact_id, check_in_user_id, completed_on)
    references public.pact_check_ins(pact_id, user_id, completed_on)
    on delete cascade
);
-- Account deletion and "which of these did I clap" both read by actor.
create index check_in_claps_actor_idx on public.check_in_claps(actor_id);
alter table public.check_in_claps enable row level security;
revoke all on public.check_in_claps from public, anon, authenticated;
grant all on public.check_in_claps to service_role;
-- Clapping goes through the RPC below, which re-checks crew membership.
create policy check_in_claps_no_direct_access on public.check_in_claps
  for all to authenticated using (false) with check (false);

create function private.set_check_in_clap(
  target_pact_id uuid,
  target_check_in_user uuid,
  target_day date,
  clapped boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  crew uuid;
begin
  if viewer is null or clapped is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- Membership in the crew that owns the pact is the only thing that
  -- authorizes a clap, and it is re-checked here rather than trusted from
  -- whichever feed page the tap came from.
  select p.crew_id into crew
  from public.pact_check_ins i
  join public.crew_pacts p on p.id = i.pact_id
  join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
  where i.pact_id = target_pact_id
    and i.user_id = target_check_in_user
    and i.completed_on = target_day;
  if crew is null then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  -- Both directions are idempotent, so a double tap on an already-clapped
  -- post and a repeated unclap both settle on the state the caller asked for.
  if clapped then
    insert into public.check_in_claps(
      pact_id, check_in_user_id, completed_on, actor_id)
    values (target_pact_id, target_check_in_user, target_day, viewer)
    on conflict do nothing;
  else
    delete from public.check_in_claps c
    where c.pact_id = target_pact_id
      and c.check_in_user_id = target_check_in_user
      and c.completed_on = target_day
      and c.actor_id = viewer;
  end if;
  return jsonb_build_object(
    'clap_count', (
      select count(*) from public.check_in_claps c
      where c.pact_id = target_pact_id
        and c.check_in_user_id = target_check_in_user
        and c.completed_on = target_day),
    'viewer_clapped', clapped);
end;
$$;
revoke all on function private.set_check_in_clap(uuid, uuid, date, boolean)
  from public, anon;
grant execute on function private.set_check_in_clap(uuid, uuid, date, boolean)
  to authenticated;

create function public.set_check_in_clap(
  target_pact_id uuid,
  target_check_in_user uuid,
  target_day date,
  clapped boolean
)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.set_check_in_clap(
    target_pact_id, target_check_in_user, target_day, clapped);
$$;
revoke all on function public.set_check_in_clap(uuid, uuid, date, boolean)
  from public, anon;
grant execute on function public.set_check_in_clap(uuid, uuid, date, boolean)
  to authenticated;

-- The feed carries each post's clap count and whether the viewer clapped it,
-- so a page renders its claps without a second round trip.
create or replace function private.check_in_feed(
  before_created_at timestamptz,
  before_pact uuid,
  before_user uuid,
  before_day date,
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
  -- A cursor is the complete primary key plus its timestamp, or nothing at all.
  if (before_created_at is null) <> (before_pact is null)
    or (before_created_at is null) <> (before_user is null)
    or (before_created_at is null) <> (before_day is null) then
    raise exception 'Invalid feed cursor' using errcode = '22023';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(entry) order by
      entry.created_at desc, entry.pact_id desc,
      entry.user_id desc, entry.completed_on desc),
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
      p.title as pact_title,
      p.icon_key,
      c.name as crew_name,
      coalesce(nullif(trim(concat_ws(' ',
        nullif(trim(u.raw_user_meta_data->>'first_name'), ''),
        nullif(trim(u.raw_user_meta_data->>'last_name'), ''))), ''),
        'Crew member') as display_name,
      case
        when u.raw_user_meta_data->>'avatar_path' = u.id::text || '/avatar.png'
        then u.id::text || '/avatar.png'
      end as avatar_path,
      (select count(*) from public.check_in_claps k
        where k.pact_id = i.pact_id
          and k.check_in_user_id = i.user_id
          and k.completed_on = i.completed_on) as clap_count,
      exists(select 1 from public.check_in_claps k
        where k.pact_id = i.pact_id
          and k.check_in_user_id = i.user_id
          and k.completed_on = i.completed_on
          and k.actor_id = viewer) as viewer_clapped
    from public.pact_check_ins i
    join public.crew_pacts p on p.id = i.pact_id
    join public.crews c on c.id = p.crew_id
    join public.crew_members m on m.crew_id = p.crew_id and m.user_id = viewer
    join auth.users u on u.id = i.user_id
    where before_created_at is null
      or (i.created_at, i.pact_id, i.user_id, i.completed_on)
         < (before_created_at, before_pact, before_user, before_day)
    order by i.created_at desc, i.pact_id desc, i.user_id desc, i.completed_on desc
    limit least(greatest(coalesce(page_limit, 20), 1), 50)
  ) entry;
  return result;
end;
$$;

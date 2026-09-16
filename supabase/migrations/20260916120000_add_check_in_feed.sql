-- One paginated feed of check-ins across every crew the viewer belongs to.
-- Membership is re-checked per row, so leaving a crew removes its posts.
create index pact_check_ins_feed_idx on public.pact_check_ins
  (created_at desc, pact_id desc, user_id desc, completed_on desc);

create function private.check_in_feed(
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
      end as avatar_path
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
revoke all on function private.check_in_feed(timestamptz, uuid, uuid, date, int)
  from public, anon;
grant execute on function private.check_in_feed(timestamptz, uuid, uuid, date, int)
  to authenticated;

create function public.check_in_feed(
  before_created_at timestamptz default null,
  before_pact uuid default null,
  before_user uuid default null,
  before_day date default null,
  page_limit int default 20
)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.check_in_feed(
    before_created_at, before_pact, before_user, before_day, page_limit);
$$;
revoke all on function public.check_in_feed(timestamptz, uuid, uuid, date, int)
  from public, anon;
grant execute on function public.check_in_feed(timestamptz, uuid, uuid, date, int)
  to authenticated;

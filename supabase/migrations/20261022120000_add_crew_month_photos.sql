-- The streak card's month drawer shows the crew's month in photos: every
-- check-in that kept a photo in the calendar month holding `month_start`,
-- with the claps it has. The week snapshot only reaches back to Monday, and
-- `check_in_claps` has no direct read path, so this is a definer in
-- `private` behind an invoker wrapper, the way `crew_week_snapshot` is.
-- Crew membership authorizes the whole answer and is checked first.
create function private.crew_month_photos(target_crew_id uuid, month_start date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  first_day date := date_trunc('month', month_start::timestamp)::date;
  result jsonb;
begin
  if not private.is_crew_member(target_crew_id, viewer) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on,
      'photo_path', i.photo_path, 'created_at', i.created_at,
      'clap_count', (select count(*) from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on),
      'viewer_clapped', exists(select 1 from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on
          and k.actor_id = viewer))
    order by i.completed_on, i.created_at), '[]'::jsonb)
  into result
  from public.pact_check_ins i
  join public.crew_pacts g on g.id = i.pact_id
  where g.crew_id = target_crew_id
    and i.photo_path is not null
    and i.completed_on >= first_day
    and i.completed_on < (first_day + interval '1 month')::date;
  return result;
end;
$$;
revoke all on function private.crew_month_photos(uuid, date) from public, anon;
grant execute on function private.crew_month_photos(uuid, date) to authenticated;

create function public.crew_month_photos(target_crew_id uuid, month_start date)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.crew_month_photos(target_crew_id, month_start);
$$;
revoke all on function public.crew_month_photos(uuid, date) from public, anon;
grant execute on function public.crew_month_photos(uuid, date) to authenticated;

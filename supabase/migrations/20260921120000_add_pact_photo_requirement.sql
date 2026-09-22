-- Photo evidence becomes the pact's own choice. Existing pacts keep requiring a
-- picture, so nothing a crew already agreed to loosens underneath them.
alter table public.crew_pacts add column photo_required boolean not null default true;
grant update (photo_required) on public.crew_pacts to authenticated;

-- A pact that asks for no photo checks in on the selection alone. One that does
-- keeps the original evidence rules: the path must be this member's upload for
-- this pact today, and it is held against removal until the check-in commits.
create or replace function private.save_pact_check_ins_with_photos(target_crew_id uuid,expected_today date,selected_pact_ids uuid[],photos jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); today date; pact uuid; photo text; needs_photo boolean;
begin
  perform 1 from public.crew_members where crew_id=target_crew_id and user_id=uid for update;
  if not found then raise exception 'Crew membership required' using errcode='42501'; end if;
  select (now() at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=target_crew_id;
  if expected_today is distinct from today then raise exception 'The day changed. Refresh before checking in.' using errcode='22023'; end if;
  if selected_pact_ids is null or photos is null or jsonb_typeof(photos)<>'object' or exists(
    select 1 from unnest(selected_pact_ids) s(id) where s.id is null or not exists(
      select 1 from public.crew_pacts p where p.id=s.id and p.crew_id=target_crew_id)) then
    raise exception 'Invalid pact selection' using errcode='22023';
  end if;
  for pact in select distinct unnest(selected_pact_ids) loop
    if exists(select 1 from public.pact_check_ins where pact_id=pact and user_id=uid and completed_on=today) then continue; end if;
    select p.photo_required into needs_photo from public.crew_pacts p where p.id=pact;
    photo:=photos->>pact::text;
    if photo is null and not needs_photo then
      insert into public.pact_check_ins(pact_id,user_id,completed_on) values(pact,uid,today);
      continue;
    end if;
    if photo is null or photo !~ ('^'||uid::text||'/'||target_crew_id::text||'/'||pact::text||'/'||today::text||'/[a-f0-9]{32}\.png$') then
      raise exception 'Take a photo to check in.' using errcode='22023';
    end if;
    -- Hold the object against a concurrent removal until the check-in commits.
    perform 1 from storage.objects where bucket_id='check-in-photos' and name=photo for update;
    if not found or exists(select 1 from private.check_in_photo_cleanup where path=photo) then
      raise exception 'The check-in photo is unavailable. Take another photo.' using errcode='22023';
    end if;
    insert into public.pact_check_ins(pact_id,user_id,completed_on,photo_path) values(pact,uid,today,photo);
  end loop;
  delete from public.pact_check_ins i using public.crew_pacts p
    where i.pact_id=p.id and p.crew_id=target_crew_id and i.user_id=uid
    and i.completed_on=today and not(i.pact_id=any(selected_pact_ids));
end;
$$;

-- Historical check-ins remain valid. All new client check-ins require an uploaded photo.
alter table public.pact_check_ins add column photo_path text unique;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('check-in-photos','check-in-photos',false,5242880,array['image/png']);

create function private.can_upload_check_in_photo(object_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare crew uuid; pact uuid; today date;
begin
  if auth.uid() is null or not private.account_exists() then return false; end if;
  if object_name !~ ('^'||auth.uid()::text||'/[a-f0-9-]{36}/[a-f0-9-]{36}/[0-9]{4}-[0-9]{2}-[0-9]{2}/[a-f0-9]{32}\.png$') then return false; end if;
  crew:=split_part(object_name,'/',2)::uuid;
  pact:=split_part(object_name,'/',3)::uuid;
  if not private.is_crew_member(crew,auth.uid()) or not exists(select 1 from public.crew_pacts where id=pact and crew_id=crew) then return false; end if;
  select (now() at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=crew;
  return split_part(object_name,'/',4)=today::text;
exception when invalid_text_representation then return false;
end;
$$;
revoke all on function private.can_upload_check_in_photo(text) from public,anon;
grant execute on function private.can_upload_check_in_photo(text) to authenticated;

create policy check_in_photos_upload on storage.objects for insert to authenticated
with check(bucket_id='check-in-photos' and private.can_upload_check_in_photo(name));
create policy check_in_photos_read on storage.objects for select to authenticated
using(bucket_id='check-in-photos' and (
  (split_part(name,'/',1)=(select auth.uid())::text and (select private.account_exists()))
  or exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
    where i.photo_path=name and private.is_crew_member(p.crew_id,(select auth.uid())))
));
-- No client UPDATE or DELETE policies: posted evidence cannot be replaced or removed.

create table private.check_in_photo_cleanup(
  path text primary key,
  queued_at timestamptz not null default now()
);
alter table private.check_in_photo_cleanup enable row level security;
revoke all on private.check_in_photo_cleanup from public,anon,authenticated;
create function private.queue_check_in_photo_cleanup()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.photo_path is not null then
    insert into private.check_in_photo_cleanup(path) values(old.photo_path) on conflict do nothing;
  end if;
  return old;
end;
$$;
revoke all on function private.queue_check_in_photo_cleanup() from public,anon,authenticated;
create trigger queue_check_in_photo_cleanup after delete on public.pact_check_ins
for each row execute function private.queue_check_in_photo_cleanup();

create function private.save_pact_check_ins_with_photos(target_crew_id uuid,expected_today date,selected_pact_ids uuid[],photos jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); today date; pact uuid; photo text;
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
    photo:=photos->>pact::text;
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
revoke all on function private.save_pact_check_ins_with_photos(uuid,date,uuid[],jsonb) from public,anon;
grant execute on function private.save_pact_check_ins_with_photos(uuid,date,uuid[],jsonb) to authenticated;
create function public.save_pact_check_ins_with_photos(target_crew_id uuid,expected_today date,selected_pact_ids uuid[],photos jsonb)
returns void language sql security invoker set search_path='' as $$
  select private.save_pact_check_ins_with_photos(target_crew_id,expected_today,selected_pact_ids,photos);
$$;
revoke all on function public.save_pact_check_ins_with_photos(uuid,date,uuid[],jsonb) from public,anon;
grant execute on function public.save_pact_check_ins_with_photos(uuid,date,uuid[],jsonb) to authenticated;
-- Serialize discarding drafts with attaching evidence. Storage deletion is service-only.
create function private.discard_unused_check_in_photos(paths text[])
returns void language plpgsql security definer set search_path='' as $$
declare photo text; uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if cardinality(paths)>100 then raise exception 'Too many photos' using errcode='22023'; end if;
  for photo in select distinct unnest(paths) loop
    if split_part(photo,'/',1)<>uid::text then continue; end if;
    perform 1 from storage.objects where bucket_id='check-in-photos' and name=photo for update;
    if found and not exists(select 1 from public.pact_check_ins where photo_path=photo) then
      insert into private.check_in_photo_cleanup(path) values(photo) on conflict do nothing;
    end if;
  end loop;
end;
$$;
revoke all on function private.discard_unused_check_in_photos(text[]) from public,anon;
grant execute on function private.discard_unused_check_in_photos(text[]) to authenticated;
create function public.discard_unused_check_in_photos(paths text[]) returns void
language sql security invoker set search_path='' as $$
  select private.discard_unused_check_in_photos(paths);
$$;
revoke all on function public.discard_unused_check_in_photos(text[]) from public,anon;
grant execute on function public.discard_unused_check_in_photos(text[]) to authenticated;

-- Keep undo and existing clients readable, but remove their photo-free write bypass.
create or replace function public.save_pact_check_ins(target_crew_id uuid,expected_today date,selected_pact_ids uuid[])
returns void language sql security invoker set search_path='' as $$
  select private.save_pact_check_ins_with_photos(target_crew_id,expected_today,selected_pact_ids,'{}'::jsonb);
$$;

grant usage on schema private to service_role;

-- The dispatcher deletes bytes through the Storage API, never by deleting metadata.
create function private.pending_check_in_photo_cleanup()
returns table(path text) language plpgsql security definer set search_path='' as $$
begin
  insert into private.check_in_photo_cleanup(path)
    select o.name from storage.objects o where o.bucket_id='check-in-photos'
      and o.created_at<now()-interval '24 hours'
      and not exists(select 1 from public.pact_check_ins i where i.photo_path=o.name)
    for update of o skip locked
    on conflict do nothing;
  return query select q.path from private.check_in_photo_cleanup q
    where not exists(select 1 from public.pact_check_ins i where i.photo_path=q.path)
    order by q.queued_at limit 100;
end;
$$;
create function private.finish_check_in_photo_cleanup(paths text[])
returns void language sql security definer set search_path='' as $$
  delete from private.check_in_photo_cleanup where path=any(paths);
$$;
create function private.account_check_in_photo_paths(target_user uuid)
returns table(path text) language sql stable security definer set search_path='' as $$
  select name from storage.objects where bucket_id='check-in-photos' and split_part(name,'/',1)=target_user::text limit 100;
$$;

revoke all on function private.pending_check_in_photo_cleanup() from public,anon,authenticated;
grant execute on function private.pending_check_in_photo_cleanup() to service_role;
create function public.pending_check_in_photo_cleanup() returns table(path text) language sql security invoker set search_path='' as $$
  select * from private.pending_check_in_photo_cleanup();
$$;
revoke all on function public.pending_check_in_photo_cleanup() from public,anon,authenticated;
grant execute on function public.pending_check_in_photo_cleanup() to service_role;

revoke all on function private.finish_check_in_photo_cleanup(text[]) from public,anon,authenticated;
grant execute on function private.finish_check_in_photo_cleanup(text[]) to service_role;
create function public.finish_check_in_photo_cleanup(paths text[]) returns void language sql security invoker set search_path='' as $$
  select private.finish_check_in_photo_cleanup(paths);
$$;
revoke all on function public.finish_check_in_photo_cleanup(text[]) from public,anon,authenticated;
grant execute on function public.finish_check_in_photo_cleanup(text[]) to service_role;

revoke all on function private.account_check_in_photo_paths(uuid) from public,anon,authenticated;
grant execute on function private.account_check_in_photo_paths(uuid) to service_role;
create function public.account_check_in_photo_paths(target_user uuid) returns table(path text) language sql security invoker set search_path='' as $$
  select * from private.account_check_in_photo_paths(target_user);
$$;
revoke all on function public.account_check_in_photo_paths(uuid) from public,anon,authenticated;
grant execute on function public.account_check_in_photo_paths(uuid) to service_role;

-- Preserve the installed dispatch URL/secret setup while waking for photo work too.
create function private.check_in_photo_cleanup_needed() returns boolean
language sql stable security invoker set search_path='' as $$
  select exists(select 1 from private.check_in_photo_cleanup)
    or exists(select 1 from storage.objects o where o.bucket_id='check-in-photos'
      and o.created_at<now()-interval '24 hours'
      and not exists(select 1 from public.pact_check_ins i where i.photo_path=o.name));
$$;
revoke all on function private.check_in_photo_cleanup_needed() from public,anon,authenticated;
do $migration$
declare definition text;
begin
  select pg_get_functiondef('private.wake_notification_dispatcher()'::regprocedure) into definition;
  if position('then return; end if;' in definition)>0 then
    execute replace(definition,
      'available_at<=now()) then return; end if;',
      'available_at<=now()) and not private.check_in_photo_cleanup_needed() then return; end if;');
  end if;
end;
$migration$;

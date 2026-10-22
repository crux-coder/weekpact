-- A crew's own face: a line about what it is for, and a photo. Both are the
-- owner's to set, through the same update policy that already guards the name.
alter table public.crews
  add column description text
    check (description is null or char_length(btrim(description)) between 1 and 280),
  add column avatar_path text
    check (avatar_path is null or avatar_path ~ ('^' || id::text || '/[0-9]+\.png$'));

-- Each upload gets a new name (`<crew>/<millis>.png`) so a signed URL, and the
-- image cache behind it, never outlives the photo it was made for.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('crew-avatars', 'crew-avatars', false, 5242880, array['image/png']);

-- The crew an object belongs to, or null for a name that is not one of ours.
-- Matched before the cast so a stray name never raises inside a policy.
create function private.crew_avatar_crew(object_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case
    when object_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9]+\.png$'
    then split_part(object_name, '/', 1)::uuid
  end;
$$;
revoke all on function private.crew_avatar_crew(text) from public, anon;
grant execute on function private.crew_avatar_crew(text) to authenticated;

create policy crew_avatars_read_members on storage.objects for select to authenticated
using (
  bucket_id = 'crew-avatars'
  and private.is_crew_member(private.crew_avatar_crew(name), (select auth.uid()))
);
create policy crew_avatars_insert_owner on storage.objects for insert to authenticated
with check (
  bucket_id = 'crew-avatars'
  and private.is_crew_owner(private.crew_avatar_crew(name), (select auth.uid()))
);
create policy crew_avatars_update_owner on storage.objects for update to authenticated
using (
  bucket_id = 'crew-avatars'
  and private.is_crew_owner(private.crew_avatar_crew(name), (select auth.uid()))
)
with check (
  bucket_id = 'crew-avatars'
  and private.is_crew_owner(private.crew_avatar_crew(name), (select auth.uid()))
);
create policy crew_avatars_delete_owner on storage.objects for delete to authenticated
using (
  bucket_id = 'crew-avatars'
  and private.is_crew_owner(private.crew_avatar_crew(name), (select auth.uid()))
);

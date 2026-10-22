-- Reading the check-in photo bucket failed outright.
--
-- `20261022170000` let the crew read an achievement's photo by adding an
-- `exists (select ... from public.crew_achievements ...)` to the bucket's
-- read policy. A policy runs with the reader's own privileges, and
-- `crew_achievements` grants signed-in users nothing — it is reached only
-- through definer functions — so every query the policy guarded failed with
-- "permission denied for table crew_achievements" rather than answering no.
-- That took down every achievement photo upload, which Storage follows with
-- a read, and every read of the bucket by anyone.
--
-- The achievement half moves into a definer function, the way crew
-- membership is already asked through `private.is_crew_member`.
create function private.can_read_achievement_photo(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.crew_achievements a
    where a.photo_path = object_name
      and private.is_crew_member(a.crew_id, (select auth.uid())));
$$;
revoke all on function private.can_read_achievement_photo(text) from public, anon;
grant execute on function private.can_read_achievement_photo(text) to authenticated;

drop policy check_in_photos_read on storage.objects;
create policy check_in_photos_read on storage.objects for select to authenticated
using(bucket_id='check-in-photos' and (
  (split_part(name,'/',1)=(select auth.uid())::text and (select private.account_exists()))
  or exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
    where i.photo_path=name and private.is_crew_member(p.crew_id,(select auth.uid())))
  or (split_part(name,'/',3)='achievements' and private.can_read_achievement_photo(name))
));

-- Auth's admin deletion invokes this in the same transaction as user removal.
-- Storage bytes are removed through the Storage API before calling Auth.
create function private.prepare_account_deletion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  crew record;
  successor uuid;
begin
  for crew in select id from public.crews where owner_id = old.id order by id for update loop
    select user_id into successor from public.crew_members
      where crew_id = crew.id and user_id <> old.id
      order by joined_at, user_id limit 1 for update;
    if successor is null then
      delete from public.crews where id = crew.id;
    else
      update public.crews set owner_id = successor where id = crew.id;
      update public.crew_members set role = 'owner' where crew_id = crew.id and user_id = successor;
    end if;
  end loop;
  -- Includes authored goals in crews the user previously left. Their dependent
  -- check-ins are removed by FK cascade, as disclosed in the confirmation UI.
  delete from private.notification_events where payload->>'goal_id' in (
    select id::text from public.crew_goals where created_by = old.id
  );
  delete from public.crew_goals where created_by = old.id;
  delete from public.crew_invites where email = lower(btrim(old.email));
  -- FK cascades remove memberships, own check-ins, sent invites, push devices,
  -- notification events/deliveries and Auth sessions when Auth removes the user.
  return old;
end;
$$;
revoke all on function private.prepare_account_deletion() from public, anon, authenticated;
create trigger prepare_account_deletion before delete on auth.users
for each row execute function private.prepare_account_deletion();

-- An unexpired JWT belonging to a deleted account must not recreate an avatar.
create function private.account_exists()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from auth.users where id = auth.uid());
$$;
revoke all on function private.account_exists() from public, anon;
grant execute on function private.account_exists() to authenticated;
create policy avatars_require_account on storage.objects as restrictive
for all to authenticated
using (bucket_id <> 'avatars' or (select private.account_exists()))
with check (bucket_id <> 'avatars' or (select private.account_exists()));

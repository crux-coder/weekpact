-- Membership mutations use a narrow privileged function; table writes remain unavailable.
create function private.remove_crew_member(p_crew_id uuid, p_user_id uuid, p_successor_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  owner uuid;
  member_email text;
begin
  if actor is null then raise exception 'You must be signed in' using errcode = '42501'; end if;
  select owner_id into owner from public.crews where id = p_crew_id for update;
  if not found or (actor is distinct from p_user_id and actor is distinct from owner) then
    raise exception 'Only the owner can remove another member' using errcode = '42501';
  end if;
  select email into member_email from public.crew_members
    where crew_id = p_crew_id and user_id = p_user_id for update;
  if not found then raise exception 'This person is no longer in the crew' using errcode = '22023'; end if;
  if p_user_id = owner then
    if p_successor_id is null or p_successor_id = owner then
      raise exception 'Choose another member to become owner before leaving' using errcode = '22023';
    end if;
    perform 1 from public.crew_members where crew_id = p_crew_id and user_id = p_successor_id for update;
    if not found then raise exception 'The new owner must belong to this crew' using errcode = '22023'; end if;
    update public.crews set owner_id = p_successor_id where id = p_crew_id;
    update public.crew_members set role = 'owner' where crew_id = p_crew_id and user_id = p_successor_id;
  elsif p_successor_id is not null then
    raise exception 'Only a departing owner can transfer ownership' using errcode = '42501';
  end if;
  -- Require a fresh invitation before someone can rejoin, including through an old email.
  delete from public.crew_invites where crew_id = p_crew_id and email = member_email;
  delete from public.crew_members where crew_id = p_crew_id and user_id = p_user_id;
end;
$$;
revoke all on function private.remove_crew_member(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function private.remove_crew_member(uuid, uuid, uuid) to authenticated;

create function public.leave_crew(p_crew_id uuid, p_successor_id uuid default null)
returns void language sql security invoker set search_path = '' as $$
  select private.remove_crew_member(p_crew_id, (select auth.uid()), p_successor_id);
$$;
create function public.remove_crew_member(p_crew_id uuid, p_user_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.remove_crew_member(p_crew_id, p_user_id);
$$;
revoke all on function public.leave_crew(uuid, uuid) from public, anon;
revoke all on function public.remove_crew_member(uuid, uuid) from public, anon;
grant execute on function public.leave_crew(uuid, uuid) to authenticated;
grant execute on function public.remove_crew_member(uuid, uuid) to authenticated;

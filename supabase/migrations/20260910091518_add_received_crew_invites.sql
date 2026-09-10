-- An inbox uses the account's verified email rather than possession of a URL.
-- Only these narrow operations expose a preview; normal membership RLS stays intact.
create function private.received_crew_invites()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  recipient text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in' using errcode = '42501';
  end if;
  select lower(email) into recipient from auth.users
  where id = auth.uid() and email_confirmed_at is not null;
  if recipient is null then
    raise exception 'Confirm your email to view invitations' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id, 'crew_id', c.id, 'name', c.name,
      'timezone', c.timezone, 'expires_at', i.expires_at,
      'members', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', m.user_id,
          'email', m.email, 'role', m.role, 'joined_at', m.joined_at)
          order by m.joined_at, m.user_id)
        from public.crew_members m where m.crew_id = c.id
      ), '[]'::jsonb),
      'goals', coalesce((
        select jsonb_agg(jsonb_build_object('id', g.id, 'crew_id', g.crew_id,
          'title', g.title, 'frequency', g.frequency,
          'days_per_week', g.days_per_week, 'icon_key', g.icon_key)
          order by g.created_at, g.id)
        from public.crew_goals g where g.crew_id = c.id
      ), '[]'::jsonb)
    ) order by i.created_at desc, i.id)
    from public.crew_invites i join public.crews c on c.id = i.crew_id
    where i.email = recipient and i.accepted_at is null and i.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

create function private.respond_to_crew_invite(p_invite_id uuid, p_accept boolean)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  recipient text;
  current_user_id uuid := auth.uid();
  invitation public.crew_invites%rowtype;
begin
  if current_user_id is null then
    raise exception 'You must be signed in' using errcode = '42501';
  end if;
  if p_accept is null then
    raise exception 'Choose accept or decline' using errcode = '22023';
  end if;
  -- Serialize inbox responses for this user, including invitations to different crews.
  select lower(email) into recipient from auth.users
  where id = current_user_id and email_confirmed_at is not null for update;
  if recipient is null then
    raise exception 'Confirm your email to view invitations' using errcode = '42501';
  end if;
  select * into invitation from public.crew_invites
  where id = p_invite_id and email = recipient
    and accepted_at is null and expires_at > now()
  for update;
  if not found then
    raise exception 'This invitation is no longer available' using errcode = '22023';
  end if;
  if not p_accept then
    -- As with revocation, deletion invalidates the email token and permits a fresh invite.
    delete from public.crew_invites where id = invitation.id;
    return null;
  end if;
  if exists (select 1 from public.crew_members where user_id = current_user_id) then
    raise exception 'You already belong to a crew' using errcode = '23505';
  end if;
  insert into public.crew_members (crew_id, user_id, email, role)
  values (invitation.crew_id, current_user_id, recipient, 'member');
  update public.crew_invites set accepted_at = now() where id = invitation.id;
  return invitation.crew_id;
end;
$$;

-- Keep privileged implementations out of the exposed schema.
create function public.received_crew_invites()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.received_crew_invites(); $$;
create function public.respond_to_crew_invite(p_invite_id uuid, p_accept boolean)
returns uuid language sql security invoker set search_path = ''
as $$ select private.respond_to_crew_invite(p_invite_id, p_accept); $$;

revoke all on function private.received_crew_invites() from public, anon, authenticated;
revoke all on function private.respond_to_crew_invite(uuid, boolean) from public, anon, authenticated;
revoke all on function public.received_crew_invites() from public, anon, authenticated;
revoke all on function public.respond_to_crew_invite(uuid, boolean) from public, anon, authenticated;
grant execute on function private.received_crew_invites() to authenticated;
grant execute on function private.respond_to_crew_invite(uuid, boolean) to authenticated;
grant execute on function public.received_crew_invites() to authenticated;
grant execute on function public.respond_to_crew_invite(uuid, boolean) to authenticated;

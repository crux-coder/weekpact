-- Membership remains unique within each crew; a user may belong to many crews.
alter table public.crew_members drop constraint crew_members_one_crew_per_user;
create index crew_members_user_id_idx on public.crew_members(user_id);

-- INSERT RETURNING checks visibility before the AFTER INSERT owner-membership
-- trigger runs. The creator may read their own crew during that insertion.
alter policy crews_select_for_members on public.crews
using (owner_id = (select auth.uid()) or private.is_crew_member(id, (select auth.uid())));

create or replace function private.accept_email_crew_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  invite_row public.crew_invites%rowtype;
begin
  if current_user_id is null then
    raise exception 'You must be signed in to accept an invite';
  end if;

  if p_token is null or char_length(p_token) < 20 then
    raise exception 'Invalid invite';
  end if;

  select * into invite_row
  from public.crew_invites
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and accepted_at is null
  for update;

  if not found then
    raise exception 'Invite is invalid or has already been used';
  end if;

  if invite_row.expires_at <= now() then
    raise exception 'Invite has expired';
  end if;

  select lower(email) into current_email
  from auth.users
  where id = current_user_id;

  if current_email is distinct from invite_row.email then
    raise exception 'Sign in with the email address that received this invite';
  end if;

  insert into public.crew_members (crew_id, user_id, email, role)
  values (invite_row.crew_id, current_user_id, current_email, 'member')
  on conflict (crew_id, user_id) do nothing;

  update public.crew_invites
  set accepted_at = now()
  where id = invite_row.id;

  return invite_row.crew_id;
end;
$$;

create or replace function private.respond_to_crew_invite(p_invite_id uuid, p_accept boolean)
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
  insert into public.crew_members (crew_id, user_id, email, role)
  values (invitation.crew_id, current_user_id, recipient, 'member')
  on conflict (crew_id, user_id) do nothing;
  update public.crew_invites set accepted_at = now() where id = invitation.id;
  return invitation.crew_id;
end;
$$;

create or replace function private.accept_any_crew_invite(p_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare link private.crew_share_links%rowtype; recipient text;
begin
  if auth.uid() is null then raise exception 'Sign in to join this crew' using errcode='42501'; end if;
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid invite'; end if;
  select lower(email) into recipient from auth.users where id=auth.uid() and email_confirmed_at is not null;
  if recipient is null then raise exception 'Confirm your email before joining' using errcode='42501'; end if;
  select * into link from private.crew_share_links where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if not found then return private.accept_email_crew_invite(p_token); end if;
  if link.expires_at<=now() then raise exception 'This invite link has expired'; end if;
  insert into public.crew_members(crew_id,user_id,email,role) values(link.crew_id,auth.uid(),recipient,'member') on conflict (crew_id,user_id) do nothing;
  return link.crew_id;
end;
$$;

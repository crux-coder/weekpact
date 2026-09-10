create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.crews (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 60),
  timezone text not null default 'UTC' check (char_length(timezone) between 1 and 64),
  owner_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.crew_members (
  crew_id uuid not null references public.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null check (email = lower(btrim(email))),
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (crew_id, user_id),
  constraint crew_members_one_crew_per_user unique (user_id)
);

create table public.crew_invites (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid not null references public.crews(id) on delete cascade,
  email text not null check (email = lower(btrim(email))),
  token_hash text not null unique check (char_length(token_hash) = 64),
  invited_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint crew_invites_one_email_per_crew unique (crew_id, email),
  constraint crew_invites_expiry_after_creation check (expires_at > created_at)
);

create index crews_owner_id_idx on public.crews (owner_id);
create index crew_members_crew_id_idx on public.crew_members (crew_id);
create index crew_invites_crew_id_idx on public.crew_invites (crew_id);
create index crew_invites_invited_by_idx on public.crew_invites (invited_by);
create index crew_invites_pending_email_idx
  on public.crew_invites (email)
  where accepted_at is null;

create function private.is_crew_member(target_crew_id uuid, target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.crew_members
    where crew_id = target_crew_id and user_id = target_user_id
  );
$$;

create function private.is_crew_owner(target_crew_id uuid, target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.crews
    where id = target_crew_id and owner_id = target_user_id
  );
$$;

revoke all on function private.is_crew_member(uuid, uuid) from public, anon;
revoke all on function private.is_crew_owner(uuid, uuid) from public, anon;
grant execute on function private.is_crew_member(uuid, uuid) to authenticated;
grant execute on function private.is_crew_owner(uuid, uuid) to authenticated;

create function private.add_crew_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_email text;
begin
  select lower(email) into owner_email
  from auth.users
  where id = new.owner_id;

  if owner_email is null then
    raise exception 'The crew owner must have an email address';
  end if;

  insert into public.crew_members (crew_id, user_id, email, role)
  values (new.id, new.owner_id, owner_email, 'owner');
  return new;
end;
$$;

revoke all on function private.add_crew_owner() from public, anon, authenticated;

create trigger crews_add_owner
after insert on public.crews
for each row execute function private.add_crew_owner();

alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.crew_invites enable row level security;

create policy crews_select_for_members
on public.crews for select
to authenticated
using (private.is_crew_member(id, (select auth.uid())));

create policy crews_insert_for_owner
on public.crews for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy crews_update_for_owner
on public.crews for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy crews_delete_for_owner
on public.crews for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy crew_members_select_for_members
on public.crew_members for select
to authenticated
using (private.is_crew_member(crew_id, (select auth.uid())));

create policy crew_invites_select_for_owner
on public.crew_invites for select
to authenticated
using (private.is_crew_owner(crew_id, (select auth.uid())));

create policy crew_invites_insert_for_owner
on public.crew_invites for insert
to authenticated
with check (
  invited_by = (select auth.uid())
  and private.is_crew_owner(crew_id, (select auth.uid()))
);

create policy crew_invites_update_for_owner
on public.crew_invites for update
to authenticated
using (private.is_crew_owner(crew_id, (select auth.uid())))
with check (
  invited_by = (select auth.uid())
  and private.is_crew_owner(crew_id, (select auth.uid()))
);

create policy crew_invites_delete_for_owner
on public.crew_invites for delete
to authenticated
using (private.is_crew_owner(crew_id, (select auth.uid())));

create function public.accept_crew_invite(p_token text)
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

  if exists (
    select 1 from public.crew_members where user_id = current_user_id
  ) then
    raise exception 'You already belong to a crew';
  end if;

  insert into public.crew_members (crew_id, user_id, email, role)
  values (invite_row.crew_id, current_user_id, current_email, 'member');

  update public.crew_invites
  set accepted_at = now()
  where id = invite_row.id;

  return invite_row.crew_id;
end;
$$;

revoke all on function public.accept_crew_invite(text) from public, anon;
grant execute on function public.accept_crew_invite(text) to authenticated;

revoke all on public.crews, public.crew_members, public.crew_invites from anon;
revoke all on public.crews, public.crew_members, public.crew_invites from authenticated;

grant select, insert, update, delete on public.crews to authenticated;
grant select on public.crew_members to authenticated;
grant select, insert, update, delete on public.crew_invites to authenticated;

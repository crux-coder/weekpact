-- One invite code per crew, replacing seven-day links and address-locked email invites.
--
-- A crew's code is six characters from an alphabet without the look-alikes
-- 0/O, 1/I/L, so it can be read aloud or typed from a screenshot. It stays the
-- same until a crew owner resets it; the reset is how a leaked code is retired.
-- Anyone signed in can join with it, so the preview that names the crew is
-- open to anon as well: the invitee sees who is asking before making an
-- account. 31^6 codes keep guessing a live one impractical.
--
-- Hex share links made before this migration keep working until they expire.

create table private.crew_invite_codes (
  crew_id uuid primary key references public.crews(id) on delete cascade,
  code text not null unique check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$'),
  -- Whoever created or last reset the code; the code outlives their account.
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index crew_invite_codes_created_by on private.crew_invite_codes(created_by);
alter table private.crew_invite_codes enable row level security;
revoke all on private.crew_invite_codes from public, anon, authenticated;

-- Six characters drawn from a CSPRNG. Bytes at or above 248 (8 * 31) are
-- skipped so every character is equally likely; the version and variant
-- bytes of each UUID (6 and 8) are skipped because they are not random.
create function private.new_invite_code()
returns text language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text := '';
  bytes bytea;
  b integer;
begin
  while char_length(code) < 6 loop
    bytes := uuid_send(gen_random_uuid());
    for i in 0..15 loop
      continue when i in (6, 8);
      b := get_byte(bytes, i);
      continue when b >= 248;
      code := code || substr(alphabet, b % 31 + 1, 1);
      exit when char_length(code) = 6;
    end loop;
  end loop;
  return code;
end;
$$;
revoke all on function private.new_invite_code() from public, anon, authenticated;

-- Codes are typed by hand, so case and stray spaces do not matter. Anything
-- that cannot be a code comes back null.
create function private.normalize_invite_code(p_code text)
returns text language sql immutable set search_path = '' as $$
  select c from (select upper(btrim(p_code)) c) n
  where c ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$';
$$;
revoke all on function private.normalize_invite_code(text) from public, anon, authenticated;

-- Stores a fresh code for the crew, replacing any earlier one. A collision
-- with another crew's code is retried with a new draw.
create function private.store_invite_code(p_crew uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare fresh text;
begin
  loop
    fresh := private.new_invite_code();
    begin
      insert into private.crew_invite_codes(crew_id, code, created_by)
        values (p_crew, fresh, auth.uid())
        on conflict (crew_id) do update
          set code = excluded.code, created_by = excluded.created_by, created_at = now();
      return fresh;
    exception when unique_violation then
      -- Another crew holds this code; draw again.
    end;
  end loop;
end;
$$;
revoke all on function private.store_invite_code(uuid) from public, anon, authenticated;

create function private.crew_invite_code(p_crew uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare existing text;
begin
  if auth.uid() is null or not private.is_crew_member(p_crew, auth.uid()) then
    raise exception 'Crew member required' using errcode = '42501';
  end if;
  -- Two members opening the share sheet at once must see the same code.
  perform 1 from public.crews where id = p_crew for update;
  select code into existing from private.crew_invite_codes where crew_id = p_crew;
  if existing is not null then return existing; end if;
  return private.store_invite_code(p_crew);
end;
$$;
revoke all on function private.crew_invite_code(uuid) from public, anon;
grant execute on function private.crew_invite_code(uuid) to authenticated;
create function public.crew_invite_code(p_crew uuid)
returns text language sql volatile security invoker set search_path = '' as $$
  select private.crew_invite_code(p_crew);
$$;
revoke all on function public.crew_invite_code(uuid) from public, anon;
grant execute on function public.crew_invite_code(uuid) to authenticated;

create function private.reset_crew_invite_code(p_crew uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_crew_owner(p_crew, auth.uid()) then
    raise exception 'Crew owner required' using errcode = '42501';
  end if;
  perform 1 from public.crews where id = p_crew for update;
  return private.store_invite_code(p_crew);
end;
$$;
revoke all on function private.reset_crew_invite_code(uuid) from public, anon;
grant execute on function private.reset_crew_invite_code(uuid) to authenticated;
create function public.reset_crew_invite_code(p_crew uuid)
returns text language sql volatile security invoker set search_path = '' as $$
  select private.reset_crew_invite_code(p_crew);
$$;
revoke all on function public.reset_crew_invite_code(uuid) from public, anon;
grant execute on function public.reset_crew_invite_code(uuid) to authenticated;

-- A code, or a live legacy share token, names one crew; anything else names none.
create function private.invited_crew(p_code text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare normalized text := private.normalize_invite_code(p_code); target uuid;
begin
  if normalized is not null then
    select crew_id into target from private.crew_invite_codes where code = normalized;
  elsif p_code ~ '^[a-f0-9]{64}$' then
    select crew_id into target from private.crew_share_links
      where token_hash = encode(extensions.digest(p_code, 'sha256'), 'hex') and expires_at > now();
  end if;
  return target;
end;
$$;
revoke all on function private.invited_crew(text) from public, anon, authenticated;

create function private.display_name(p_first text, p_last text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(nullif(trim(concat_ws(' ',
    nullif(trim(p_first), ''), nullif(trim(p_last), ''))), ''), 'Crew member');
$$;
revoke all on function private.display_name(text, text) from public, anon, authenticated;

create function private.initials(p_first text, p_last text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(nullif(upper(left(trim(coalesce(p_first, '')), 1) || left(trim(coalesce(p_last, '')), 1)), ''), '?');
$$;
revoke all on function private.initials(text, text) from public, anon, authenticated;

-- What the invite screen shows before anyone joins: the crew, who is asking,
-- the members as initials and the pacts. No emails or ids leave here. An
-- unknown or reset code is null rather than an error, so a wrong guess and a
-- right one about someone else's crew look alike.
drop function public.preview_crew_invite(text);
drop function private.preview_crew_invite(text);
create function private.preview_crew_invite(p_code text, p_from uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare target uuid := private.invited_crew(p_code); inviter uuid;
begin
  if target is null then return null; end if;
  -- A link names whoever shared it; a forged or stale `from` falls back to the owner.
  select coalesce(
    (select m.user_id from public.crew_members m where m.crew_id = target and m.user_id = p_from),
    (select owner_id from public.crews where id = target))
  into inviter;
  return (
    select jsonb_build_object(
      'crew_name', c.name,
      'member_count', (select count(*) from public.crew_members m where m.crew_id = c.id),
      'owner_name', private.display_name(o.first_name, o.last_name),
      'inviter_name', private.display_name(i.first_name, i.last_name),
      'inviter_initials', private.initials(i.first_name, i.last_name),
      'member_initials', coalesce((
        select jsonb_agg(private.initials(u.first_name, u.last_name)
          order by m.role = 'owner' desc, m.joined_at, m.user_id)
        from public.crew_members m join public.users u on u.id = m.user_id
        where m.crew_id = c.id), '[]'::jsonb),
      'pacts', coalesce((
        select jsonb_agg(jsonb_build_object(
            'title', p.title, 'icon_key', p.icon_key, 'days_per_week', p.days_per_week)
          order by p.created_at, p.id)
        from public.crew_pacts p where p.crew_id = c.id), '[]'::jsonb),
      'is_member', auth.uid() is not null and private.is_crew_member(c.id, auth.uid())
    )
    from public.crews c
    join public.users o on o.id = c.owner_id
    join public.users i on i.id = inviter
    where c.id = target);
end;
$$;
revoke all on function private.preview_crew_invite(text, uuid) from public, anon, authenticated;
-- anon has no usage on the private schema, so this wrapper runs as its owner.
create function public.preview_crew_invite(p_code text, p_from uuid default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select private.preview_crew_invite(p_code, p_from);
$$;
revoke all on function public.preview_crew_invite(text, uuid) from public;
grant execute on function public.preview_crew_invite(text, uuid) to anon, authenticated;

-- Joining with a code or a live legacy token. Repeating it is harmless, and the
-- free-crew limit still applies through the crew_members trigger.
drop function public.accept_crew_invite(text);
drop function private.accept_any_crew_invite(text);
create function private.accept_crew_invite(p_code text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare recipient text; target uuid; link private.crew_share_links%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to join this crew' using errcode = '42501'; end if;
  select lower(email) into recipient from auth.users
    where id = auth.uid() and email_confirmed_at is not null;
  if recipient is null then raise exception 'Confirm your email before joining' using errcode = '42501'; end if;
  if p_code ~ '^[a-f0-9]{64}$' then
    select * into link from private.crew_share_links
      where token_hash = encode(extensions.digest(p_code, 'sha256'), 'hex') for update;
    if found and link.expires_at <= now() then raise exception 'This invite link has expired'; end if;
    target := link.crew_id;
  else
    select crew_id into target from private.crew_invite_codes
      where code = private.normalize_invite_code(p_code) for update;
  end if;
  if target is null then raise exception 'This invite code is no longer valid'; end if;
  insert into public.crew_members(crew_id, user_id, email, role)
    values (target, auth.uid(), recipient, 'member')
    on conflict (crew_id, user_id) do nothing;
  return target;
end;
$$;
revoke all on function private.accept_crew_invite(text) from public, anon;
grant execute on function private.accept_crew_invite(text) to authenticated;
create function public.accept_crew_invite(p_code text)
returns uuid language sql volatile security invoker set search_path = '' as $$
  select private.accept_crew_invite(p_code);
$$;
revoke all on function public.accept_crew_invite(text) from public, anon;
grant execute on function public.accept_crew_invite(text) to authenticated;

-- Email invites go, with their inbox. Pending ones are dropped with the table.
drop function public.received_crew_invites();
drop function public.respond_to_crew_invite(uuid, boolean);
drop function private.received_crew_invites();
drop function private.respond_to_crew_invite(uuid, boolean);
drop function private.accept_email_crew_invite(text);
drop table public.crew_invites;

-- Creating or resetting a code is the invite_created funnel event.
create or replace function private.record_product_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid; crew uuid; event_name text; period_key text:=''; zone text;
begin
  case tg_table_name
    when 'users' then actor:=new.id;event_name:='signup';
    when 'crews' then actor:=new.owner_id;crew:=new.id;event_name:='crew_created';period_key:=new.id::text;
    when 'crew_members' then
      if new.role='owner' then return new; end if;
      actor:=new.user_id;crew:=new.crew_id;event_name:='invite_accepted';period_key:=crew::text;
    when 'crew_invite_codes' then
      if new.created_by is null then return new; end if;
      actor:=new.created_by;crew:=new.crew_id;event_name:='invite_created';period_key:=new.crew_id::text||':'||new.code;
    when 'crew_share_links' then actor:=new.created_by;crew:=new.crew_id;event_name:='invite_created';period_key:=new.token_hash;
    when 'pact_check_ins' then
      actor:=new.user_id; select p.crew_id,c.timezone into crew,zone from public.crew_pacts p join public.crews c on c.id=p.crew_id where p.id=new.pact_id;
      insert into private.product_events(user_id,event,crew_id) values(actor,'first_check_in',crew) on conflict do nothing;
      event_name:='weekly_check_in';period_key:=crew::text||':'||date_trunc('week',new.completed_on::timestamp)::date::text;
  end case;
  insert into private.product_events(user_id,event,crew_id,period) values(actor,event_name,crew,period_key) on conflict do nothing;
  return new;
end;
$$;
create trigger product_invite_code after insert or update of code on private.crew_invite_codes
for each row execute function private.record_product_event();

-- Leaving or being removed no longer touches invites. The crew's code still
-- works for someone who was removed; the owner resets it to shut them out.
create or replace function private.remove_crew_member(p_crew_id uuid, p_user_id uuid, p_successor_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  owner uuid;
begin
  if actor is null then raise exception 'You must be signed in' using errcode = '42501'; end if;
  select owner_id into owner from public.crews where id = p_crew_id for update;
  if not found or (actor is distinct from p_user_id and actor is distinct from owner) then
    raise exception 'Only the owner can remove another member' using errcode = '42501';
  end if;
  perform 1 from public.crew_members
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
  delete from public.crew_members where crew_id = p_crew_id and user_id = p_user_id;
end;
$$;

create or replace function private.prepare_account_deletion()
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
  -- Includes authored pacts in crews the user previously left. Their dependent
  -- check-ins are removed by FK cascade, as disclosed in the confirmation UI.
  delete from private.notification_events where payload->>'pact_id' in (
    select id::text from public.crew_pacts where created_by = old.id
  );
  delete from public.crew_pacts where created_by = old.id;
  -- FK cascades remove memberships, own check-ins, push devices, the Apple
  -- token, notification events/deliveries and Auth sessions when Auth removes
  -- the user. Invite codes they created stay with the crew.
  return old;
end;
$$;

-- Apple and Google send the name as given_name/family_name, or only as one
-- full_name/name string; first_name/last_name (older email sign-ups) win.
create or replace function private.insert_user_profile(user_id uuid, user_email text, meta jsonb)
returns void language sql security definer set search_path = '' as $$
  with full_name as (
    select regexp_split_to_array(
      coalesce(nullif(trim(meta->>'full_name'), ''), nullif(trim(meta->>'name'), ''), ''),
      '\s+') parts
  ), names as (
    select
      left(coalesce(
        nullif(trim(meta->>'first_name'), ''),
        nullif(trim(meta->>'given_name'), ''),
        nullif(parts[1], ''),
        ''), 60) first_name,
      left(coalesce(
        nullif(trim(meta->>'last_name'), ''),
        nullif(trim(meta->>'family_name'), ''),
        nullif(array_to_string(parts[2:], ' '), ''),
        ''), 60) last_name
    from full_name
  )
  insert into public.users(id, email, first_name, last_name, avatar_path, onboarding_step)
  select
    user_id,
    user_email,
    names.first_name,
    names.last_name,
    case when meta->>'avatar_path' = user_id::text || '/avatar.png' then meta->>'avatar_path' end,
    case
      when coalesce(meta->>'onboarding_completed' = 'true', false)
        and names.first_name <> '' then 'done'
      else 'profile'
    end::public.onboarding_step
  from names
  on conflict (id) do nothing;
$$;
revoke all on function private.insert_user_profile(uuid, text, jsonb) from public, anon, authenticated;

-- The Apple refresh token from Sign in with Apple, kept only so deleting the
-- account can revoke it (App Store Review Guideline 5.1.1(v)). Edge functions
-- reach it through the two service-role functions below.
create table private.apple_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);
alter table private.apple_tokens enable row level security;
revoke all on private.apple_tokens from public, anon, authenticated;

create function public.save_apple_refresh_token(p_user uuid, p_refresh_token text)
returns void language sql volatile security definer set search_path = '' as $$
  insert into private.apple_tokens(user_id, refresh_token) values (p_user, p_refresh_token)
  on conflict (user_id) do update set refresh_token = excluded.refresh_token, updated_at = now();
$$;
revoke all on function public.save_apple_refresh_token(uuid, text) from public, anon, authenticated;
grant execute on function public.save_apple_refresh_token(uuid, text) to service_role;

create function public.apple_refresh_token(p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select refresh_token from private.apple_tokens where user_id = p_user;
$$;
revoke all on function public.apple_refresh_token(uuid) from public, anon, authenticated;
grant execute on function public.apple_refresh_token(uuid) to service_role;

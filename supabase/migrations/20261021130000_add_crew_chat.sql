-- A chat for each crew, end-to-end encrypted.
--
-- The server stores ciphertext and nothing it could read. Every install of
-- the app is a chat device with its own X25519 key pair; the private half
-- never leaves the phone's keychain, the public half is registered here. Each
-- crew's messages are sealed with a crew key — 32 random bytes, AES-256-GCM —
-- that a device makes and then hands to every other device in the crew by
-- wrapping it for that device's public key. Those wrapped copies are the
-- shares. A device that joins later (a new member, or an old member's new
-- phone) is wrapped in by whichever crewmate's app is open next.
--
-- When somebody leaves, their shares go with them and the next sender makes a
-- new key, so anything said afterwards is sealed under a key they never held.
--
-- Typing and presence ride Realtime broadcast on a private channel per crew,
-- `chat:<crew id>`, authorised against membership below. They carry who is
-- typing, never what.

-- One row per install that can read the crew chat.
create table public.chat_devices (
  -- Generated on the device, so it can name itself before it has been saved.
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  -- Base64 of the 32-byte X25519 public key.
  public_key text not null check (char_length(public_key) = 44),
  created_at timestamptz not null default now()
);
create index chat_devices_user_idx on public.chat_devices(user_id);

-- Whether two people share any crew: what decides whose devices are visible.
create function private.shares_crew(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.crew_members x
    join public.crew_members y on y.crew_id = x.crew_id
    where x.user_id = a and y.user_id = b
  );
$$;
revoke all on function private.shares_crew(uuid, uuid) from public, anon;
grant execute on function private.shares_crew(uuid, uuid) to authenticated;

alter table public.chat_devices enable row level security;
revoke all on public.chat_devices from public, anon, authenticated;
grant select, insert, delete on public.chat_devices to authenticated;
create policy chat_devices_read on public.chat_devices for select to authenticated
  using (user_id = (select auth.uid()) or private.shares_crew(user_id, (select auth.uid())));
create policy chat_devices_register on public.chat_devices for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy chat_devices_forget on public.chat_devices for delete to authenticated
  using (user_id = (select auth.uid()));

-- One crew key. Only its id lives here; the key itself exists only wrapped.
create table public.chat_keys (
  id uuid primary key,
  crew_id uuid not null references public.crews(id) on delete cascade,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index chat_keys_crew_idx on public.chat_keys(crew_id, created_at desc);

alter table public.chat_keys enable row level security;
revoke all on public.chat_keys from public, anon, authenticated;
grant select, insert on public.chat_keys to authenticated;
create policy chat_keys_read on public.chat_keys for select to authenticated
  using (private.is_crew_member(crew_id, (select auth.uid())));
create policy chat_keys_create on public.chat_keys for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and private.is_crew_member(crew_id, (select auth.uid()))
  );

-- A crew key wrapped for one device. The sender's public key travels with it,
-- because the recipient needs it to unwrap and the sender's device row can be
-- gone by then.
create table public.chat_key_shares (
  key_id uuid not null references public.chat_keys(id) on delete cascade,
  device_id uuid not null references public.chat_devices(id) on delete cascade,
  crew_id uuid not null references public.crews(id) on delete cascade,
  sender_device_id uuid not null,
  sender_public_key text not null check (char_length(sender_public_key) = 44),
  nonce text not null check (char_length(nonce) = 16),
  ciphertext text not null check (char_length(ciphertext) between 40 and 100),
  created_at timestamptz not null default now(),
  primary key (key_id, device_id)
);
create index chat_key_shares_device_idx on public.chat_key_shares(device_id, crew_id);
create index chat_key_shares_crew_idx on public.chat_key_shares(crew_id);

alter table public.chat_key_shares enable row level security;
revoke all on public.chat_key_shares from public, anon, authenticated;
grant select, insert, delete on public.chat_key_shares to authenticated;
-- Only the device's owner reads a share: nobody else could open it anyway, and
-- the less of the key graph is visible the better.
create policy chat_key_shares_read on public.chat_key_shares for select to authenticated
  using (exists (
    select 1 from public.chat_devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));
-- A share is written by a member, from one of their own devices under the key
-- that device registered, for a key of the same crew, to a device of somebody
-- still in it.
create policy chat_key_shares_give on public.chat_key_shares for insert to authenticated
  with check (
    private.is_crew_member(crew_id, (select auth.uid()))
    and exists (
      select 1 from public.chat_devices s
      where s.id = sender_device_id
        and s.user_id = (select auth.uid())
        and s.public_key = sender_public_key
    )
    and exists (
      select 1 from public.chat_keys k where k.id = key_id and k.crew_id = chat_key_shares.crew_id
    )
    and exists (
      select 1 from public.chat_devices d
      join public.crew_members m on m.user_id = d.user_id and m.crew_id = chat_key_shares.crew_id
      where d.id = device_id
    )
  );
-- A recipient may throw away a share that does not open, so a good one can
-- take its place.
create policy chat_key_shares_discard on public.chat_key_shares for delete to authenticated
  using (exists (
    select 1 from public.chat_devices d
    where d.id = device_id and d.user_id = (select auth.uid())
  ));

create table public.chat_messages (
  -- Generated by the sender, and sealed into the ciphertext's associated data,
  -- so a message cannot be replayed under another row.
  id uuid primary key,
  crew_id uuid not null references public.crews(id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  key_id uuid not null references public.chat_keys(id) on delete cascade,
  nonce text not null check (char_length(nonce) in (0, 16)),
  -- Room for 2,000 characters of text, sealed and base64'd.
  ciphertext text not null check (char_length(ciphertext) <= 12000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint chat_messages_deleted_empty check (
    (deleted_at is null and char_length(ciphertext) > 0 and char_length(nonce) = 16)
    or (deleted_at is not null and ciphertext = '' and nonce = '')
  )
);
create index chat_messages_crew_idx on public.chat_messages(crew_id, created_at desc, id desc);
create index chat_messages_sender_idx on public.chat_messages(sender_id);
create index chat_messages_key_idx on public.chat_messages(key_id);

alter table public.chat_messages enable row level security;
revoke all on public.chat_messages from public, anon, authenticated;
grant select, insert on public.chat_messages to authenticated;
create policy chat_messages_read on public.chat_messages for select to authenticated
  using (private.is_crew_member(crew_id, (select auth.uid())));
create policy chat_messages_send on public.chat_messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and deleted_at is null
    and private.is_crew_member(crew_id, (select auth.uid()))
    and exists (
      select 1 from public.chat_keys k where k.id = key_id and k.crew_id = chat_messages.crew_id
    )
  );

-- The time is the server's: a phone with its clock wrong would otherwise
-- file its messages in the wrong place for everyone.
create function private.stamp_chat_message() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_at := now();
  return new;
end;
$$;
create trigger stamp_chat_message before insert on public.chat_messages
for each row execute function private.stamp_chat_message();

-- Unsending empties the row rather than removing it, so everyone's list
-- closes the gap the same way and the realtime update says what happened.
create function public.delete_chat_message(target_message_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.chat_messages
  set deleted_at = now(), ciphertext = '', nonce = ''
  where id = target_message_id and sender_id = auth.uid() and deleted_at is null;
  if not found then
    raise exception 'Only the sender can delete a message' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.delete_chat_message(uuid) from public, anon;
grant execute on function public.delete_chat_message(uuid) to authenticated;

-- How far each member has read, for "Seen" and the unread dot.
create table public.chat_reads (
  crew_id uuid not null references public.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null,
  primary key (crew_id, user_id)
);
create index chat_reads_user_idx on public.chat_reads(user_id);
alter table public.chat_reads enable row level security;
revoke all on public.chat_reads from public, anon, authenticated;
grant select on public.chat_reads to authenticated;
create policy chat_reads_read on public.chat_reads for select to authenticated
  using (private.is_crew_member(crew_id, (select auth.uid())));

-- Only ever moves forward, and never past now.
create function public.mark_chat_read(target_crew_id uuid, read_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_crew_member(target_crew_id, auth.uid()) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  insert into public.chat_reads(crew_id, user_id, last_read_at)
  values (target_crew_id, auth.uid(), least(read_at, now()))
  on conflict (crew_id, user_id) do update
    set last_read_at = greatest(public.chat_reads.last_read_at, excluded.last_read_at);
end;
$$;
revoke all on function public.mark_chat_read(uuid, timestamptz) from public, anon;
grant execute on function public.mark_chat_read(uuid, timestamptz) to authenticated;

-- Messages from others the caller has not read, per crew they are in.
create function public.chat_unread_counts()
returns table (crew_id uuid, unread integer)
language sql stable security definer set search_path = '' as $$
  select m.crew_id, count(c.id)::integer
  from public.crew_members m
  left join public.chat_reads r on r.crew_id = m.crew_id and r.user_id = m.user_id
  join public.chat_messages c on c.crew_id = m.crew_id
    and c.sender_id <> m.user_id
    and c.deleted_at is null
    -- Nothing from before joining counts as unread.
    and c.created_at > greatest(coalesce(r.last_read_at, '-infinity'), m.joined_at)
  where m.user_id = auth.uid()
  group by m.crew_id;
$$;
revoke all on function public.chat_unread_counts() from public, anon;
grant execute on function public.chat_unread_counts() to authenticated;

-- When each crew last lost a member: a key older than that is retired.
create table private.chat_departures (
  crew_id uuid primary key references public.crews(id) on delete cascade,
  left_at timestamptz not null
);
alter table private.chat_departures enable row level security;
revoke all on private.chat_departures from public, anon, authenticated;
create policy chat_departures_no_direct_access on private.chat_departures
  for all to authenticated using (false) with check (false);

create function private.chat_member_left() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Whatever was wrapped for their phones goes with them.
  delete from public.chat_key_shares s
  using public.chat_devices d
  where s.device_id = d.id and d.user_id = old.user_id and s.crew_id = old.crew_id;
  -- Not when the crew itself is being deleted: its members cascade away
  -- after it, and a departure row would point at a crew that is gone.
  if exists (select 1 from public.crews where id = old.crew_id) then
    insert into private.chat_departures(crew_id, left_at) values (old.crew_id, now())
    on conflict (crew_id) do update set left_at = excluded.left_at;
  end if;
  return old;
end;
$$;
revoke all on function private.chat_member_left() from public, anon, authenticated;
create trigger chat_member_left after delete on public.crew_members
for each row execute function private.chat_member_left();

-- What a device needs to open a crew's chat: the key to send under, and
-- whether that key has to be replaced first.
create function public.chat_room(target_crew_id uuid)
returns table (current_key_id uuid, rotate boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_crew_member(target_crew_id, auth.uid()) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  return query
  select k.id, coalesce(d.left_at > k.created_at, false)
  from (select 1) one
  left join lateral (
    select id, created_at from public.chat_keys
    where crew_id = target_crew_id order by created_at desc, id desc limit 1
  ) k on true
  left join private.chat_departures d on d.crew_id = target_crew_id;
end;
$$;
revoke all on function public.chat_room(uuid) from public, anon;
grant execute on function public.chat_room(uuid) to authenticated;

-- The devices still waiting for keys the caller's device holds: every device
-- of a current member that has no share of that key yet. The caller wraps
-- each one and writes it back.
create function public.chat_pending_shares(target_crew_id uuid, holder_device_id uuid)
returns table (key_id uuid, device_id uuid, public_key text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_crew_member(target_crew_id, auth.uid()) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  return query
  select held.key_id, d.id, d.public_key
  from public.chat_key_shares held
  join public.chat_devices own on own.id = held.device_id and own.user_id = auth.uid()
  join public.crew_members m on m.crew_id = target_crew_id
  join public.chat_devices d on d.user_id = m.user_id
  where held.device_id = holder_device_id
    and held.crew_id = target_crew_id
    and not exists (
      select 1 from public.chat_key_shares s
      where s.key_id = held.key_id and s.device_id = d.id
    )
  limit 500;
end;
$$;
revoke all on function public.chat_pending_shares(uuid, uuid) from public, anon;
grant execute on function public.chat_pending_shares(uuid, uuid) to authenticated;

-- Realtime: rows the app listens for, filtered by the policies above.
alter publication supabase_realtime add table public.chat_messages;
alter publication supabase_realtime add table public.chat_key_shares;
alter publication supabase_realtime add table public.chat_reads;

-- Private broadcast and presence on `chat:<crew id>`, for that crew's members.
create function private.can_use_chat_topic(topic text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if topic is null or topic !~ '^chat:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return private.is_crew_member(substr(topic, 6)::uuid, auth.uid());
end;
$$;
revoke all on function private.can_use_chat_topic(text) from public, anon;
grant execute on function private.can_use_chat_topic(text) to authenticated;

create policy chat_topic_listen on realtime.messages for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and private.can_use_chat_topic((select realtime.topic()))
  );
create policy chat_topic_send on realtime.messages for insert to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and private.can_use_chat_topic((select realtime.topic()))
  );

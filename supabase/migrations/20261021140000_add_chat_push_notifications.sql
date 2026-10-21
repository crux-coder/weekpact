-- A push when a crewmate writes in the crew chat.
--
-- The message itself is sealed on the sender's phone, so the server has
-- nothing to put in a push but who wrote and where: "Ana sent a message in
-- Runners." That is the same metadata the chat already leaves in the clear.
--
-- Chat pushes are push-only. The inbox is a list of things worth reading back;
-- a line per chat message would bury the claps and nudges it is for, and the
-- Chat tab already has its own unread dot. So this does not go through
-- private.enqueue_crew_notification, which writes both.
--
-- A busy chat is many messages in a few minutes. Each recipient gets at most
-- one push per crew per window; what follows inside the window is left to the
-- unread dot.
--
-- Somebody reading the chat right now should not be buzzed by it. The open
-- chat marks each arrival read within a moment (chat_reads), so a chat push
-- waits a few seconds before it may be sent, and is cancelled if by then the
-- recipient has read the message it announces. A cancelled push does not use
-- up the window, so the next message after they put the phone down still
-- reaches them.

create function private.chat_push_window() returns interval
language sql immutable set search_path = '' as $$ select interval '3 minutes' $$;
revoke all on function private.chat_push_window() from public, anon, authenticated;

-- Long enough for an open chat to mark the message read; the dispatcher runs
-- on a minute schedule, so this costs nobody any real delay.
create function private.chat_push_grace() returns interval
language sql immutable set search_path = '' as $$ select interval '15 seconds' $$;
revoke all on function private.chat_push_grace() from public, anon, authenticated;

-- What the window looks back over: recent chat events of a crew.
create index notification_events_chat_idx on private.notification_events(crew_id, created_at)
  where type = 'chat_message';

create function private.notify_chat_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  recipients uuid[];
  actor_name text;
  crew_name text;
  event uuid;
begin
  -- One sender's burst at a time per crew, so two messages landing together
  -- cannot both find the window empty.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chat_push:' || new.crew_id, 0));

  select array_agg(m.user_id) into recipients
  from public.crew_members m
  where m.crew_id = new.crew_id and m.user_id <> new.sender_id
    -- Somebody who can be pushed to at all.
    and exists (
      select 1 from private.push_devices d
      join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
      where d.user_id = m.user_id and d.updated_at > now() - interval '60 days')
    -- Nobody already told about this crew's chat inside the window. Cancelled
    -- pushes, the ones they were reading anyway, do not count.
    and not exists (
      select 1 from private.notification_events e
      join private.notification_deliveries d on d.event_id = e.id
      where e.type = 'chat_message' and e.crew_id = new.crew_id
        and e.created_at > now() - private.chat_push_window()
        and d.recipient_id = m.user_id
        and d.status in ('pending', 'sending', 'sent'));
  if recipients is null then return new; end if;

  -- Display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(first_name), 60), ''), 'A crew member')
    into actor_name from public.users where id = new.sender_id;
  select left(c.name, 60) into crew_name from public.crews c where c.id = new.crew_id;

  insert into private.notification_events(dedupe_key, type, crew_id, actor_id, payload)
  values ('chat_message:' || new.id, 'chat_message', new.crew_id, new.sender_id,
    jsonb_build_object(
      'actor_name', coalesce(actor_name, 'A crew member'),
      'crew_name', coalesce(crew_name, 'your crew'),
      'message_id', new.id,
      'sent_at', new.created_at))
  on conflict (dedupe_key) do nothing returning id into event;
  if event is null then return new; end if;

  insert into private.notification_deliveries(event_id, device_id, recipient_id, available_at)
  select event, d.id, d.user_id, now() + private.chat_push_grace()
  from private.push_devices d
  join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
  where d.user_id = any(recipients) and d.updated_at > now() - interval '60 days';
  perform private.wake_notification_dispatcher();
  return new;
end;
$$;
revoke all on function private.notify_chat_message() from public, anon, authenticated;
create trigger chat_message_notification after insert on public.chat_messages
for each row execute function private.notify_chat_message();

-- As before, plus: a chat push is dropped once its message is unsent, or once
-- the recipient has read up to it.
create or replace function public.claim_notification_deliveries(batch_size integer default 20)
returns table(delivery_id uuid, lease uuid, device_token text, event_type text, event_id uuid, crew_id uuid, payload jsonb)
language plpgsql security definer set search_path = '' as $$
begin
  -- Invalidate queued work if membership/session/pact state changed after enqueue.
  update private.notification_deliveries d set status = 'cancelled', last_error = 'recipient_or_event_unavailable'
  from private.notification_events e, private.push_devices p
  where d.event_id=e.id and d.device_id=p.id and d.status in ('pending','sending')
    and (e.created_at < now()-interval '24 hours' or p.user_id <> d.recipient_id
      or not exists(select 1 from auth.sessions s where s.id=p.session_id and s.user_id=p.user_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=d.recipient_id)
      or not exists(select 1 from public.crew_members m where m.crew_id=e.crew_id and m.user_id=e.actor_id)
      or (e.type='pact_completed' and not exists(select 1 from public.pact_check_ins i
        where i.pact_id=(e.payload->>'pact_id')::uuid and i.user_id=e.actor_id and i.completed_on=(e.payload->>'completed_on')::date))
      or (e.type='check_in_clapped' and (
        d.recipient_id is distinct from (e.payload->>'recipient_id')::uuid
        or not exists(select 1 from public.check_in_claps c
          where c.pact_id=(e.payload->>'pact_id')::uuid
            and c.check_in_user_id=(e.payload->>'recipient_id')::uuid
            and c.completed_on=(e.payload->>'completed_on')::date
            and c.actor_id <> (e.payload->>'recipient_id')::uuid)))
      or (e.type='crew_nudge' and (
        d.recipient_id is distinct from (e.payload->>'recipient_id')::uuid
        or (e.payload->>'completed_on')::date is distinct from (
          select (now() at time zone coalesce(t.name,'UTC'))::date
          from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=e.crew_id)
        or exists(select 1 from public.pact_check_ins i join public.crew_pacts p2 on p2.id=i.pact_id
          where p2.crew_id=e.crew_id and i.user_id=d.recipient_id and i.completed_on=(e.payload->>'completed_on')::date)
      ))
      or (e.type='chat_message' and (
        not exists(select 1 from public.chat_messages c
          where c.id=(e.payload->>'message_id')::uuid and c.deleted_at is null)
        or exists(select 1 from public.chat_reads r
          where r.crew_id=e.crew_id and r.user_id=d.recipient_id
            and r.last_read_at >= (e.payload->>'sent_at')::timestamptz))));
  update private.notification_deliveries set status='failed',last_error='retry_limit'
    where status in ('pending','sending') and available_at <= now() and attempts >= 8;
  return query with picked as (
    select d.id from private.notification_deliveries d
    where d.status in ('pending','sending') and d.available_at <= now() and d.attempts < 8
    order by d.available_at,d.id for update skip locked limit greatest(1,least(batch_size,50))
  ), claimed as (
    update private.notification_deliveries d set status='sending', attempts=d.attempts+1,
      available_at=now()+interval '2 minutes',lease_id=gen_random_uuid()
    from picked where d.id=picked.id returning d.*
  ) select d.id,d.lease_id,p.token,e.type,e.id,e.crew_id,e.payload
    from claimed d join private.push_devices p on p.id=d.device_id
    join private.notification_events e on e.id=d.event_id;
end;
$$;

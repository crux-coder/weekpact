-- Which pushes an account wants, in three kinds it can turn off one at a
-- time: pact check-ins, claps and chat. Only adds things: an account with no
-- row wants all three, which is what every push did before, so builds that
-- never ask keep getting everything. A nudge belongs to none of the three and
-- is still always sent.
--
-- The phone's own switch stays where it was: it decides whether this device
-- is registered at all. These decide what the account's devices are sent.
create table private.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  check_ins boolean not null default true,
  claps boolean not null default true,
  chat boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table private.notification_preferences enable row level security;
revoke all on private.notification_preferences from public, anon, authenticated;
grant all on private.notification_preferences to service_role;

-- The kind a push is, or null for one no switch turns off.
create function private.notification_kind(event_type text)
returns text language sql immutable set search_path = '' as $$
  select case
    when event_type = 'pact_completed' then 'check_ins'
    when event_type in ('check_in_clapped', 'achievement_clapped', 'story_clapped') then 'claps'
    when event_type = 'chat_message' then 'chat'
  end;
$$;

create function private.wants_notification(recipient uuid, event_type text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case private.notification_kind(event_type)
      when 'check_ins' then p.check_ins
      when 'claps' then p.claps
      when 'chat' then p.chat
    end
    from private.notification_preferences p where p.user_id = recipient), true);
$$;
revoke all on function private.wants_notification(uuid, text) from public, anon, authenticated;

-- Every push is queued as a delivery, whichever trigger or function queues
-- it, so one check here covers them all. The event and its inbox row are
-- untouched: turning a kind off quiets the phone, not the list.
create function private.skip_unwanted_delivery() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not private.wants_notification(new.recipient_id,
    (select e.type from private.notification_events e where e.id = new.event_id)) then
    return null;
  end if;
  return new;
end;
$$;
create trigger skip_unwanted_delivery before insert on private.notification_deliveries
  for each row execute function private.skip_unwanted_delivery();

create function private.my_notification_preferences()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  result jsonb;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select jsonb_build_object('check_ins', p.check_ins, 'claps', p.claps, 'chat', p.chat)
    into result from private.notification_preferences p where p.user_id = viewer;
  return coalesce(result, jsonb_build_object('check_ins', true, 'claps', true, 'chat', true));
end;
$$;
revoke all on function private.my_notification_preferences() from public, anon;
grant execute on function private.my_notification_preferences() to authenticated;

create function public.my_notification_preferences()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.my_notification_preferences();
$$;
revoke all on function public.my_notification_preferences() from public, anon;
grant execute on function public.my_notification_preferences() to authenticated;

-- Turns one kind on or off and answers with all three. Turning one off also
-- withdraws what is still queued of that kind — a chat push waits out its
-- grace period first — so nothing arrives after the switch says it won't.
create function private.set_notification_preference(kind text, enabled boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if kind is null or kind not in ('check_ins', 'claps', 'chat') or enabled is null then
    raise exception 'Unknown notification preference' using errcode = '22023';
  end if;
  insert into private.notification_preferences(user_id) values (viewer)
    on conflict (user_id) do nothing;
  update private.notification_preferences p set
    check_ins = case when kind = 'check_ins' then enabled else p.check_ins end,
    claps = case when kind = 'claps' then enabled else p.claps end,
    chat = case when kind = 'chat' then enabled else p.chat end,
    updated_at = now()
  where p.user_id = viewer;
  if not enabled then
    update private.notification_deliveries d
      set status = 'cancelled', last_error = 'recipient_muted'
    from private.notification_events e
    where e.id = d.event_id and d.recipient_id = viewer
      and d.status in ('pending', 'sending')
      and private.notification_kind(e.type) = kind;
  end if;
  return private.my_notification_preferences();
end;
$$;
revoke all on function private.set_notification_preference(text, boolean) from public, anon;
grant execute on function private.set_notification_preference(text, boolean) to authenticated;

create function public.set_notification_preference(kind text, enabled boolean)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.set_notification_preference(kind, enabled);
$$;
revoke all on function public.set_notification_preference(text, boolean) from public, anon;
grant execute on function public.set_notification_preference(text, boolean) to authenticated;

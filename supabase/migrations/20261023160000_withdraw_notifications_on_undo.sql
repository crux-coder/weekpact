-- A check-in taken back takes its notifications with it: the crew's "completed
-- a pact" and the author's "clapped your check-in" leave every inbox, and any
-- push not yet sent is cancelled. The same goes for an achievement or story
-- taken down, and the claps on it.
--
-- The events themselves stay. A completed pact's event is what keeps a check-in
-- undone and redone from telling the crew twice (its dedupe key names the
-- check-in), so withdrawing it rather than deleting it keeps that promise.
-- Pushes already on someone's phone stay there; tapping one opens a page that
-- says the check-in is gone.

-- Finds a check-in's clap notices without reading every event.
create index notification_events_check_in_clap_idx
  on private.notification_events (
    (payload->>'pact_id'), (payload->>'recipient_id'), (payload->>'completed_on')
  )
  where type = 'check_in_clapped';

create index notification_events_achievement_idx
  on private.notification_events ((payload->>'achievement_id'))
  where type in ('achievement_clapped', 'story_clapped');

-- Takes [events] out of every inbox and cancels what has not been sent.
create function private.withdraw_notifications(events uuid[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if events is null or cardinality(events) = 0 then return; end if;
  delete from private.notification_inbox n where n.event_id = any(events);
  update private.notification_deliveries d
    set status = 'cancelled', last_error = 'withdrawn'
    where d.event_id = any(events) and d.status = 'pending';
end;
$$;

revoke all on function private.withdraw_notifications(uuid[]) from public, anon, authenticated;

create function private.withdraw_check_in_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.withdraw_notifications(array(
    select e.id from private.notification_events e
    where e.dedupe_key = 'pact_completed:' || old.pact_id || ':' || old.user_id
      || ':' || old.completed_on
    union all
    select e.id from private.notification_events e
    where e.type = 'check_in_clapped'
      and e.payload->>'pact_id' = old.pact_id::text
      and e.payload->>'recipient_id' = old.user_id::text
      and e.payload->>'completed_on' = to_char(old.completed_on, 'YYYY-MM-DD')
  ));
  return old;
end;
$$;

revoke all on function private.withdraw_check_in_notifications() from public, anon, authenticated;

create trigger withdraw_check_in_notifications after delete on public.pact_check_ins
for each row execute function private.withdraw_check_in_notifications();

create function private.withdraw_achievement_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.withdraw_notifications(array(
    select e.id from private.notification_events e
    where e.type in ('achievement_clapped', 'story_clapped')
      and e.payload->>'achievement_id' = old.id::text
  ));
  return old;
end;
$$;

revoke all on function private.withdraw_achievement_notifications() from public, anon, authenticated;

create trigger withdraw_achievement_notifications after delete on public.crew_achievements
for each row execute function private.withdraw_achievement_notifications();

-- What was already taken back before this migration goes too.
select private.withdraw_notifications(array(
  select e.id from private.notification_events e
  where (e.type in ('pact_completed', 'check_in_clapped')
      and not exists (
        select 1 from public.pact_check_ins i
        where i.pact_id::text = e.payload->>'pact_id'
          and i.user_id::text = case e.type
            when 'check_in_clapped' then e.payload->>'recipient_id'
            else e.actor_id::text end
          and to_char(i.completed_on, 'YYYY-MM-DD') = e.payload->>'completed_on'))
    or (e.type in ('achievement_clapped', 'story_clapped')
      and not exists (
        select 1 from public.crew_achievements a
        where a.id::text = e.payload->>'achievement_id'))
));

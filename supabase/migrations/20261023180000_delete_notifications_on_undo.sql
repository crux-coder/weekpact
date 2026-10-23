-- Undo deletes notifications outright instead of withdrawing them.
--
-- 20261023160000 kept a taken-back check-in's events and only emptied their
-- inboxes, so the dedupe key still blocked the next check-in from notifying
-- anyone. Now the events themselves are deleted (inbox rows and unsent pushes
-- go with them), and checking in again sends a new one like any check-in.
-- The same goes for an achievement or story taken down, and the claps on it.

drop trigger withdraw_check_in_notifications on public.pact_check_ins;
drop trigger withdraw_achievement_notifications on public.crew_achievements;
drop function private.withdraw_check_in_notifications();
drop function private.withdraw_achievement_notifications();
drop function private.withdraw_notifications(uuid[]);

create function private.delete_check_in_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from private.notification_events e
  where e.dedupe_key = 'pact_completed:' || old.pact_id || ':' || old.user_id
      || ':' || old.completed_on
    or (e.type = 'check_in_clapped'
      and e.payload->>'pact_id' = old.pact_id::text
      and e.payload->>'recipient_id' = old.user_id::text
      and e.payload->>'completed_on' = to_char(old.completed_on, 'YYYY-MM-DD'));
  return old;
end;
$$;
revoke all on function private.delete_check_in_notifications() from public, anon, authenticated;
create trigger delete_check_in_notifications after delete on public.pact_check_ins
for each row execute function private.delete_check_in_notifications();

create function private.delete_achievement_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from private.notification_events e
  where e.type in ('achievement_clapped', 'story_clapped')
    and e.payload->>'achievement_id' = old.id::text;
  return old;
end;
$$;
revoke all on function private.delete_achievement_notifications() from public, anon, authenticated;
create trigger delete_achievement_notifications after delete on public.crew_achievements
for each row execute function private.delete_achievement_notifications();

-- Events withdrawn so far, or left from before any of this, whose check-in or
-- post is gone.
delete from private.notification_events e
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
      where a.id::text = e.payload->>'achievement_id'));

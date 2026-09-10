-- Shared event enqueue API. Future crew events only supply a type, payload,
-- actor and stable deduplication key; fanout and delivery stay centralized.
create function private.enqueue_crew_notification(
  event_type text, event_key text, target_crew uuid, actor uuid, event_payload jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare created_event uuid;
begin
  insert into private.notification_events(dedupe_key,type,crew_id,actor_id,payload)
  values(event_key,event_type,target_crew,actor,event_payload)
  on conflict(dedupe_key) do nothing returning id into created_event;
  if created_event is not null then
    insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select created_event,d.id,m.user_id from public.crew_members m
      join private.push_devices d on d.user_id=m.user_id
      join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    where m.crew_id=target_crew and m.user_id<>actor and d.updated_at>now()-interval '60 days';
    perform private.wake_notification_dispatcher();
  end if;
  return created_event;
end;
$$;
revoke all on function private.enqueue_crew_notification(text,text,uuid,uuid,jsonb) from public,anon,authenticated;

create or replace function private.notify_goal_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare crew uuid; goal_title text; actor_name text;
begin
  select g.crew_id,g.title into crew,goal_title from public.crew_goals g where g.id=new.goal_id;
  select coalesce(nullif(left(trim(raw_user_meta_data->>'first_name'),60),''),'A crew member')
    into actor_name from auth.users where id=new.user_id;
  perform private.enqueue_crew_notification('goal_completed',
    'goal_completed:'||new.goal_id||':'||new.user_id||':'||new.completed_on,
    crew,new.user_id,jsonb_build_object('goal_id',new.goal_id,'goal_title',left(goal_title,120),
      'actor_name',coalesce(actor_name,'A crew member'),'completed_on',new.completed_on));
  return new;
end;
$$;
-- Explicitly deny direct access; only narrowly authorized RPCs can use these tables.
create policy push_devices_no_direct_access on private.push_devices for all to authenticated using(false) with check(false);
create policy notification_events_no_direct_access on private.notification_events for all to authenticated using(false) with check(false);
create policy notification_deliveries_no_direct_access on private.notification_deliveries for all to authenticated using(false) with check(false);

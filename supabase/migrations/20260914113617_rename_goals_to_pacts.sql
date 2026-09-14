-- Rename the existing entities in place: IDs, check-ins, RLS and grants survive.
-- Previously applied migrations intentionally retain their historical names.
alter table public.crew_goals rename to crew_pacts;
alter table public.goal_check_ins rename to pact_check_ins;
alter table public.pact_check_ins rename column goal_id to pact_id;
alter table public.crew_pacts rename constraint crew_goals_pkey to crew_pacts_pkey;
alter table public.crew_pacts rename constraint crew_goals_crew_id_fkey to crew_pacts_crew_id_fkey;
alter table public.crew_pacts rename constraint crew_goals_created_by_fkey to crew_pacts_created_by_fkey;
alter table public.crew_pacts rename constraint crew_goals_title_check to crew_pacts_title_check;
alter table public.crew_pacts rename constraint crew_goals_frequency_check to crew_pacts_frequency_check;
alter table public.crew_pacts rename constraint crew_goals_days_per_week_check to crew_pacts_days_per_week_check;
alter table public.crew_pacts rename constraint crew_goals_daily_seven_days to crew_pacts_daily_seven_days;
alter table public.crew_pacts rename constraint crew_goals_icon_key_check to crew_pacts_icon_key_check;
alter table public.pact_check_ins rename constraint goal_check_ins_pkey to pact_check_ins_pkey;
alter table public.pact_check_ins rename constraint goal_check_ins_goal_id_fkey to pact_check_ins_pact_id_fkey;
alter table public.pact_check_ins rename constraint goal_check_ins_user_id_fkey to pact_check_ins_user_id_fkey;
alter index public.crew_goals_crew_created_idx rename to crew_pacts_crew_created_idx;
alter index public.crew_goals_created_by_idx rename to crew_pacts_created_by_idx;
alter index public.goal_check_ins_user_idx rename to pact_check_ins_user_idx;
alter policy crew_goals_read_for_members on public.crew_pacts rename to crew_pacts_read_for_members;
alter policy crew_goals_add_for_owners on public.crew_pacts rename to crew_pacts_add_for_owners;
alter policy crew_goals_edit_for_owners on public.crew_pacts rename to crew_pacts_edit_for_owners;

alter function private.notify_goal_completed() rename to notify_pact_completed;
alter trigger goal_completed_notification on public.pact_check_ins rename to pact_completed_notification;

-- Preserve queued delivery IDs and deduplication so migration cannot send duplicates.
update private.notification_events
set type = 'pact_completed',
    dedupe_key = regexp_replace(dedupe_key, '^goal_completed:', 'pact_completed:'),
    payload = (payload - 'goal_id' - 'goal_title') || jsonb_build_object(
      'pact_id', payload->'goal_id', 'pact_title', payload->'goal_title'
    )
where type = 'goal_completed';

create or replace function public.crew_week_snapshot(target_crew_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  crew_zone text;
  today date;
  week_start date;
  result jsonb;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(t.name, 'UTC') into crew_zone from public.crews c
  left join pg_catalog.pg_timezone_names t on t.name = c.timezone where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  week_start := date_trunc('week', today::timestamp)::date;
  select jsonb_build_object(
    'streak_weeks', public.crew_weekly_streak(target_crew_id),
    'today', today, 'week_start', week_start, 'timezone', crew_zone,
    'pacts', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_pacts g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) || coalesce(private.crew_member_profile(target_crew_id, m.user_id), '{}'::jsonb) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on)) from public.pact_check_ins i join public.crew_pacts g on g.id = i.pact_id where g.crew_id = target_crew_id and i.completed_on between week_start and today), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.save_pact_check_ins(target_crew_id uuid, expected_today date, selected_pact_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
  today date;
begin
  perform 1 from public.crew_members where crew_id = target_crew_id and user_id = current_user_id for update;
  if not found then raise exception 'Crew membership required' using errcode = '42501'; end if;
  select (now() at time zone coalesce(t.name, 'UTC'))::date into today
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone where c.id = target_crew_id;
  if expected_today is distinct from today then raise exception 'The day changed. Refresh before checking in.' using errcode = '22023'; end if;
  if selected_pact_ids is null or exists (
    select 1 from unnest(selected_pact_ids) selected(pact_id) where selected.pact_id is null or not exists (
      select 1 from public.crew_pacts g where g.id = selected.pact_id and g.crew_id = target_crew_id
    )
  ) then raise exception 'Invalid pact selection' using errcode = '22023'; end if;
  delete from public.pact_check_ins i using public.crew_pacts g
  where i.pact_id = g.id and g.crew_id = target_crew_id and i.user_id = current_user_id
    and i.completed_on = today and not (i.pact_id = any(selected_pact_ids));
  insert into public.pact_check_ins(pact_id, user_id, completed_on)
  select distinct id, current_user_id, today from unnest(selected_pact_ids) id
  on conflict do nothing;
end;
$$;

create or replace function public.crew_weekly_streak(target_crew_id uuid)
returns integer language plpgsql stable security invoker set search_path = '' as $$
declare
  crew_zone text;
  today date;
  current_week date;
  candidate date;
  first_week date;
  earned boolean;
  streak integer := 0;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select coalesce(t.name, 'UTC'), date_trunc('week', c.created_at at time zone coalesce(t.name, 'UTC'))::date
    into crew_zone, first_week
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone
  where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  current_week := date_trunc('week', today::timestamp)::date;
  candidate := current_week;
  while candidate >= first_week loop
    select count(*) > 0 and bool_and(completed >= days_per_week) into earned
    from (
      select g.days_per_week, (
        select count(*) from public.pact_check_ins i
        where i.pact_id = g.id and i.user_id = m.user_id
          and i.completed_on between candidate and least(candidate + 6, today)
      ) as completed
      from public.crew_pacts g cross join public.crew_members m
      where g.crew_id = target_crew_id and m.crew_id = target_crew_id
        and (g.created_at at time zone crew_zone)::date <= least(candidate + 6, today)
        and (m.joined_at at time zone crew_zone)::date <= least(candidate + 6, today)
    ) requirements;
    if earned then
      streak := streak + 1;
    elsif candidate <> current_week then
      exit;
    end if;
    candidate := candidate - 7;
  end loop;
  return streak;
end;
$$;

create or replace function private.received_crew_invites()
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
      'pacts', coalesce((
        select jsonb_agg(jsonb_build_object('id', g.id, 'crew_id', g.crew_id,
          'title', g.title, 'frequency', g.frequency,
          'days_per_week', g.days_per_week, 'icon_key', g.icon_key)
          order by g.created_at, g.id)
        from public.crew_pacts g where g.crew_id = c.id
      ), '[]'::jsonb)
    ) order by i.created_at desc, i.id)
    from public.crew_invites i join public.crews c on c.id = i.crew_id
    where i.email = recipient and i.accepted_at is null and i.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

create or replace function private.notify_pact_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare crew uuid; pact_title text; actor_name text;
begin
  select g.crew_id,g.title into crew,pact_title from public.crew_pacts g where g.id=new.pact_id;
  select coalesce(nullif(left(trim(raw_user_meta_data->>'first_name'),60),''),'A crew member')
    into actor_name from auth.users where id=new.user_id;
  perform private.enqueue_crew_notification('pact_completed',
    'pact_completed:'||new.pact_id||':'||new.user_id||':'||new.completed_on,
    crew,new.user_id,jsonb_build_object('pact_id',new.pact_id,'pact_title',left(pact_title,120),
      'actor_name',coalesce(actor_name,'A crew member'),'completed_on',new.completed_on));
  return new;
end;
$$;

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
        where i.pact_id=(e.payload->>'pact_id')::uuid and i.user_id=e.actor_id and i.completed_on=(e.payload->>'completed_on')::date)));
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
  delete from public.crew_invites where email = lower(btrim(old.email));
  -- FK cascades remove memberships, own check-ins, sent invites, push devices,
  -- notification events/deliveries and Auth sessions when Auth removes the user.
  return old;
end;
$$;

-- New RPC argument names require a new signature name; remove the former entrypoint.
revoke all on function public.save_pact_check_ins(uuid, date, uuid[]) from public, anon;
grant execute on function public.save_pact_check_ins(uuid, date, uuid[]) to authenticated;
drop function public.save_goal_check_ins(uuid, date, uuid[]);

notify pgrst, 'reload schema';

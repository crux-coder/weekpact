-- Every crew-day lookup stops reading pg_timezone_names.
--
-- The functions below found a crew's zone by joining the crew to
-- pg_catalog.pg_timezone_names, which reads the whole zone database off disk
-- on every call: about half a second each, measured on production, and the
-- week snapshot alone did it twice. `private.crew_zone` asks Postgres to use
-- the zone instead, and falls back to UTC exactly when the old join did — a
-- zone Postgres does not know.
--
-- The bodies are the live ones with only that lookup changed, except that the
-- week snapshot also learns `next_day_at`: the instant the crew's day turns
-- over, so the app can refresh then rather than poll for it. Additive: a
-- snapshot keeps every key it had.

create function private.crew_zone(zone text)
returns text language plpgsql stable set search_path = '' as $$
begin
  if zone is null then return 'UTC'; end if;
  perform now() at time zone zone;
  return zone;
exception when invalid_parameter_value then
  return 'UTC';
end;
$$;
revoke all on function private.crew_zone(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.can_upload_check_in_photo(object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare crew uuid; today date; target text;
begin
  if auth.uid() is null or not private.account_exists() then return false; end if;
  if object_name !~ ('^'||auth.uid()::text||'/[a-f0-9-]{36}/([a-f0-9-]{36}|achievements)/[0-9]{4}-[0-9]{2}-[0-9]{2}/[a-f0-9]{32}\.png$') then return false; end if;
  crew:=split_part(object_name,'/',2)::uuid;
  target:=split_part(object_name,'/',3);
  if not private.is_crew_member(crew,auth.uid()) then return false; end if;
  if target<>'achievements' and not exists(
    select 1 from public.crew_pacts where id::text=target and crew_id=crew) then
    return false;
  end if;
  select (now() at time zone private.crew_zone(c.timezone))::date into today
    from public.crews c where c.id=crew;
  return split_part(object_name,'/',4)=today::text;
exception when invalid_text_representation then return false;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_notification_deliveries(batch_size integer DEFAULT 20)
 RETURNS TABLE(delivery_id uuid, lease uuid, device_token text, event_type text, event_id uuid, crew_id uuid, payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          select (now() at time zone private.crew_zone(c.timezone))::date
          from public.crews c where c.id=e.crew_id)
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
$function$;

CREATE OR REPLACE FUNCTION private.crew_nudge_status(target_crew_id uuid)
 RETURNS TABLE(recipient_id uuid, status text, next_allowed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid(); today date;
begin
  if uid is null or not exists(select 1 from public.crew_members m where m.crew_id=target_crew_id and m.user_id=uid) then
    raise exception 'Crew membership required' using errcode='42501';
  end if;
  select (now() at time zone private.crew_zone(c.timezone))::date into today
    from public.crews c where c.id=target_crew_id;
  return query
    select m.user_id,
      case
        when exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
          where p.crew_id=target_crew_id and i.user_id=m.user_id and i.completed_on=today) then 'checked_in'
        when n.last_sent_at > now()-interval '24 hours' then 'cooldown'
        when not exists(select 1 from public.crew_pacts p where p.crew_id=target_crew_id)
          or not exists(select 1 from private.push_devices d join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
            where d.user_id=m.user_id and d.updated_at>now()-interval '60 days') then 'unavailable'
        else 'ready'
      end,
      case when n.last_sent_at > now()-interval '24 hours' then n.last_sent_at+interval '24 hours' end
    from public.crew_members m left join private.crew_nudge_cooldowns n on n.actor_id=uid and n.recipient_id=m.user_id
    where m.crew_id=target_crew_id and m.user_id<>uid;
end;
$function$;

CREATE OR REPLACE FUNCTION private.crew_week_history(target_crew_id uuid, before_week date, week_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  crew_zone text;
  today date;
  current_week date;
  first_week date;
  last_week date;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if week_count < 1 or week_count > 52 then
    raise exception 'Ask for between 1 and 52 weeks' using errcode = '22023';
  end if;
  select private.crew_zone(c.timezone), date_trunc('week', c.created_at at time zone private.crew_zone(c.timezone))::date
    into crew_zone, first_week
  from public.crews c
  where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  current_week := date_trunc('week', today::timestamp)::date;
  last_week := least(date_trunc('week', coalesce(before_week, current_week)::timestamp)::date, current_week) - 7;
  return coalesce((
    select jsonb_agg(jsonb_build_object('week_start', w.week_start, 'percent', w.percent, 'days', w.days, 'top_pacts', w.top_pacts) order by w.week_start desc)
    from (
      select s.week_start,
        coalesce((
          select round(100.0 * sum(least(g.days_per_week, (
            select count(distinct i.completed_on) from public.pact_check_ins i
            where i.pact_id = g.id and i.user_id = m.user_id
              and i.completed_on between s.week_start and s.week_start + 6
          ))) / nullif(sum(g.days_per_week), 0))::integer
          from public.crew_pacts g cross join public.crew_members m
          where g.crew_id = target_crew_id and m.crew_id = target_crew_id
            and (g.created_at at time zone crew_zone)::date <= s.week_start + 6
            and (m.joined_at at time zone crew_zone)::date <= s.week_start + 6
        ), 0) as percent,
        (
          select jsonb_agg(coalesce((
            select count(distinct i.user_id)::numeric from public.pact_check_ins i
            join public.crew_pacts g on g.id = i.pact_id
            join public.crew_members m on m.crew_id = g.crew_id and m.user_id = i.user_id
            where g.crew_id = target_crew_id and i.completed_on = s.week_start + d
          ) / nullif((select count(*) from public.crew_members m where m.crew_id = target_crew_id), 0), 0) order by d)
          from generate_series(0, 6) d
        ) as days,
        (
          select jsonb_agg((
            select g.id from public.pact_check_ins i
            join public.crew_pacts g on g.id = i.pact_id
            join public.crew_members m on m.crew_id = g.crew_id and m.user_id = i.user_id
            where g.crew_id = target_crew_id and i.completed_on = s.week_start + d
            group by g.id, g.created_at
            order by count(*) desc, g.created_at, g.id
            limit 1
          ) order by d)
          from generate_series(0, 6) d
        ) as top_pacts
      from (
        select generate_series(last_week, greatest(first_week, last_week - 7 * (week_count - 1)), interval '-7 days')::date as week_start
      ) s
    ) w
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION private.crew_week_snapshot(target_crew_id uuid, target_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  viewer uuid := (select auth.uid());
  crew_zone text;
  today date;
  week_start date;
  week_end date;
  result jsonb;
begin
  if not private.is_crew_member(target_crew_id, (select auth.uid())) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  select private.crew_zone(c.timezone) into crew_zone from public.crews c where c.id = target_crew_id;
  today := (now() at time zone crew_zone)::date;
  week_start := date_trunc('week', today::timestamp)::date;
  if target_week_start is not null then
    if target_week_start > week_start + 6 then
      raise exception 'That week has not started' using errcode = '22023';
    end if;
    week_start := date_trunc('week', target_week_start::timestamp)::date;
  end if;
  week_end := least(week_start + 6, today);
  select jsonb_build_object(
    'streak_weeks', public.crew_weekly_streak(target_crew_id),
    'today', today, 'week_start', week_start, 'timezone', crew_zone,
    'next_day_at', (today + 1)::timestamp at time zone crew_zone,
    'pacts', coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at, g.id) from public.crew_pacts g where g.crew_id = target_crew_id), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'email', m.email) || coalesce(private.crew_member_profile(target_crew_id, m.user_id), '{}'::jsonb) order by m.joined_at, m.user_id) from public.crew_members m where m.crew_id = target_crew_id), '[]'::jsonb),
    'check_ins', coalesce((select jsonb_agg(jsonb_build_object('pact_id', i.pact_id, 'user_id', i.user_id, 'completed_on', i.completed_on, 'photo_path', i.photo_path, 'created_at', i.created_at,
      'clap_count', (select count(*) from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on),
      'viewer_clapped', exists(select 1 from public.check_in_claps k
        where k.pact_id = i.pact_id and k.check_in_user_id = i.user_id and k.completed_on = i.completed_on
          and k.actor_id = viewer))) from public.pact_check_ins i join public.crew_pacts g on g.id = i.pact_id where g.crew_id = target_crew_id and i.completed_on between week_start and week_end), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.post_crew_achievement(target_crew_id uuid, achievement_body text, photo text, post_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  viewer uuid := (select auth.uid());
  cleaned text := trim(coalesce(achievement_body, ''));
  today date;
  posted public.crew_achievements;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not private.is_crew_member(target_crew_id, viewer) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  if post_kind is null or post_kind not in ('achievement', 'story') then
    raise exception 'A post is an achievement or a story' using errcode = '22023';
  end if;
  if char_length(cleaned) not between 1 and 160 then
    raise exception 'An achievement is 1 to 160 characters' using errcode = '22023';
  end if;
  select (now() at time zone private.crew_zone(c.timezone))::date into today
  from public.crews c
  where c.id = target_crew_id;
  if photo is null or photo !~ ('^' || viewer::text || '/' || target_crew_id::text
      || '/achievements/' || today::text || '/[a-f0-9]{32}\.png$') then
    raise exception 'Take a photo to post an achievement.' using errcode = '22023';
  end if;
  -- Hold the object against a concurrent removal until the post commits.
  perform 1 from storage.objects where bucket_id = 'check-in-photos' and name = photo for update;
  if not found or exists(select 1 from private.check_in_photo_cleanup where path = photo) then
    raise exception 'The achievement photo is unavailable. Take another photo.' using errcode = '22023';
  end if;
  -- Serializes one member's posts to one crew, so two at once cannot both
  -- slip under the cap.
  perform pg_advisory_xact_lock(hashtextextended(target_crew_id::text || viewer::text, 0));
  if (select count(*) from public.crew_achievements a
      where a.crew_id = target_crew_id and a.user_id = viewer and a.posted_on = today) >= 5 then
    raise exception 'That is five achievements today' using errcode = '23514';
  end if;
  insert into public.crew_achievements(crew_id, user_id, body, posted_on, photo_path, kind)
  values (target_crew_id, viewer, cleaned, today, photo, post_kind)
  returning * into posted;
  return jsonb_build_object(
    'id', posted.id, 'user_id', posted.user_id, 'posted_on', posted.posted_on,
    'body', posted.body, 'kind', posted.kind, 'photo_path', posted.photo_path,
    'created_at', posted.created_at, 'clap_count', 0, 'viewer_clapped', false);
end;
$function$;

CREATE OR REPLACE FUNCTION private.save_pact_check_ins_with_photos(target_crew_id uuid, expected_today date, selected_pact_ids uuid[], photos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); today date; pact uuid; photo text; needs_photo boolean;
begin
  perform 1 from public.crew_members where crew_id=target_crew_id and user_id=uid for update;
  if not found then raise exception 'Crew membership required' using errcode='42501'; end if;
  select (now() at time zone private.crew_zone(c.timezone))::date into today
    from public.crews c where c.id=target_crew_id;
  if expected_today is distinct from today then raise exception 'The day changed. Refresh before checking in.' using errcode='22023'; end if;
  if selected_pact_ids is null or photos is null or jsonb_typeof(photos)<>'object' or exists(
    select 1 from unnest(selected_pact_ids) s(id) where s.id is null or not exists(
      select 1 from public.crew_pacts p where p.id=s.id and p.crew_id=target_crew_id)) then
    raise exception 'Invalid pact selection' using errcode='22023';
  end if;
  for pact in select distinct unnest(selected_pact_ids) loop
    if exists(select 1 from public.pact_check_ins where pact_id=pact and user_id=uid and completed_on=today) then continue; end if;
    select p.photo_required into needs_photo from public.crew_pacts p where p.id=pact;
    photo:=photos->>pact::text;
    if photo is null and not needs_photo then
      insert into public.pact_check_ins(pact_id,user_id,completed_on) values(pact,uid,today);
      continue;
    end if;
    if photo is null or photo !~ ('^'||uid::text||'/'||target_crew_id::text||'/'||pact::text||'/'||today::text||'/[a-f0-9]{32}\.png$') then
      raise exception 'Take a photo to check in.' using errcode='22023';
    end if;
    -- Hold the object against a concurrent removal until the check-in commits.
    perform 1 from storage.objects where bucket_id='check-in-photos' and name=photo for update;
    if not found or exists(select 1 from private.check_in_photo_cleanup where path=photo) then
      raise exception 'The check-in photo is unavailable. Take another photo.' using errcode='22023';
    end if;
    insert into public.pact_check_ins(pact_id,user_id,completed_on,photo_path) values(pact,uid,today,photo);
  end loop;
  delete from public.pact_check_ins i using public.crew_pacts p
    where i.pact_id=p.id and p.crew_id=target_crew_id and i.user_id=uid
    and i.completed_on=today and not(i.pact_id=any(selected_pact_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION private.send_crew_nudge(target_crew_id uuid, target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid(); today date; members_count integer;
  device_ids uuid[]; sent_at timestamptz; next_at timestamptz;
  event_id uuid := gen_random_uuid(); actor_name text; request_time timestamptz := now();
begin
  if uid is null or target_user_id is null or uid=target_user_id then
    raise exception 'Choose another crew member' using errcode='42501';
  end if;
  -- Stable lock order also serializes recipient check-ins and membership removal.
  perform m.user_id from public.crew_members m
    where m.crew_id=target_crew_id and m.user_id in (uid,target_user_id)
    order by m.user_id for update;
  get diagnostics members_count = row_count;
  if members_count<>2 then raise exception 'Crew membership required' using errcode='42501'; end if;
  select (request_time at time zone private.crew_zone(c.timezone))::date into today
    from public.crews c where c.id=target_crew_id;
  if exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
      where p.crew_id=target_crew_id and i.user_id=target_user_id and i.completed_on=today) then
    return jsonb_build_object('status','checked_in');
  end if;
  select array_agg(d.id) into device_ids from private.push_devices d
    join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    where d.user_id=target_user_id and d.updated_at>request_time-interval '60 days';
  if device_ids is null or not exists(select 1 from public.crew_pacts p where p.crew_id=target_crew_id) then
    return jsonb_build_object('status','unavailable');
  end if;
  -- The unique pair plus conditional update makes repeated/concurrent taps atomic.
  insert into private.crew_nudge_cooldowns(actor_id,recipient_id,last_sent_at)
    values(uid,target_user_id,request_time)
    on conflict(actor_id,recipient_id) do update set last_sent_at=excluded.last_sent_at
      where private.crew_nudge_cooldowns.last_sent_at <= request_time-interval '24 hours'
    returning last_sent_at into sent_at;
  if sent_at is null then
    select n.last_sent_at+interval '24 hours' into next_at from private.crew_nudge_cooldowns n
      where n.actor_id=uid and n.recipient_id=target_user_id;
    return jsonb_build_object('status','cooldown','next_allowed_at',next_at);
  end if;
  -- Profile names are display text only, never an authorization source.
  select coalesce(nullif(left(trim(first_name),60),''),'A crew member')
    into actor_name from public.users where id=uid;
  insert into private.notification_events(id,dedupe_key,type,crew_id,actor_id,payload)
    values(event_id,'crew_nudge:'||event_id,'crew_nudge',target_crew_id,uid,
      jsonb_build_object('actor_name',coalesce(actor_name,'A crew member'),'recipient_id',target_user_id,'completed_on',today));
  insert into private.notification_inbox(event_id,recipient_id) values(event_id,target_user_id);
  insert into private.notification_deliveries(event_id,device_id,recipient_id)
    select event_id,device_id,target_user_id from unnest(device_ids) device_id;
  perform private.wake_notification_dispatcher();
  return jsonb_build_object('status','sent','next_allowed_at',sent_at+interval '24 hours');
end;
$function$;


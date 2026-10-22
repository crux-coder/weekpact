-- Every achievement carries a photo, taken the way a photo check-in is: the
-- camera opens first and the words follow. An achievement is never words
-- alone.
--
-- The photo lives in the `check-in-photos` bucket beside check-in photos, so
-- it is uploaded, read, discarded and swept by the same rules: a member
-- uploads under their own id, today, for a crew they are in; the crew reads
-- it once a row names it; and anything nothing names is swept after a day.
-- An achievement's photo sits where a check-in's pact id would:
--
--   <user>/<crew>/achievements/<today>/<nonce>.png
--
-- Every rule that asked "does a check-in name this photo" now asks whether a
-- check-in or an achievement does, or the sweeper would take an achievement's
-- photo the day after it was posted.
alter table public.crew_achievements add column photo_path text unique;

-- A post is an achievement, or a plain story: the same photo and words,
-- without the claim of a win. The poster chooses as they write the words, and
-- the app draws each in its own colour.
alter table public.crew_achievements add column kind text not null default 'achievement'
  constraint crew_achievements_kind check (kind in ('achievement', 'story'));
-- Not valid: it binds every achievement from here on without asking rows
-- posted before photos to have one.
alter table public.crew_achievements
  add constraint crew_achievements_photo_required check (photo_path is not null) not valid;

create function private.check_in_photo_in_use(photo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.pact_check_ins i where i.photo_path = photo)
    or exists(select 1 from public.crew_achievements a where a.photo_path = photo);
$$;
revoke all on function private.check_in_photo_in_use(text) from public, anon, authenticated;

create or replace function private.can_upload_check_in_photo(object_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare crew uuid; today date; target text;
begin
  if auth.uid() is null or not private.account_exists() then return false; end if;
  if object_name !~ ('^'||auth.uid()::text||'/[a-f0-9-]{36}/([a-f0-9-]{36}|achievements)/[0-9]{4}-[0-9]{2}-[0-9]{2}/[a-f0-9]{32}\.png$') then return false; end if;
  crew:=split_part(object_name,'/',2)::uuid;
  target:=split_part(object_name,'/',3);
  if not private.is_crew_member(crew,auth.uid()) then return false; end if;
  if target<>'achievements' and not exists(
    select 1 from public.crew_pacts where id=target::uuid and crew_id=crew) then
    return false;
  end if;
  select (now() at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=crew;
  return split_part(object_name,'/',4)=today::text;
exception when invalid_text_representation then return false;
end;
$$;

drop policy check_in_photos_read on storage.objects;
create policy check_in_photos_read on storage.objects for select to authenticated
using(bucket_id='check-in-photos' and (
  (split_part(name,'/',1)=(select auth.uid())::text and (select private.account_exists()))
  or exists(select 1 from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id
    where i.photo_path=name and private.is_crew_member(p.crew_id,(select auth.uid())))
  or exists(select 1 from public.crew_achievements a
    where a.photo_path=name and private.is_crew_member(a.crew_id,(select auth.uid())))
));

-- An achievement taken down queues its photo, as a check-in undone does.
create trigger queue_check_in_photo_cleanup after delete on public.crew_achievements
for each row execute function private.queue_check_in_photo_cleanup();

create or replace function private.discard_unused_check_in_photos(paths text[])
returns void language plpgsql security definer set search_path='' as $$
declare photo text; uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if cardinality(paths)>100 then raise exception 'Too many photos' using errcode='22023'; end if;
  for photo in select distinct unnest(paths) loop
    if split_part(photo,'/',1)<>uid::text then continue; end if;
    perform 1 from storage.objects where bucket_id='check-in-photos' and name=photo for update;
    if found and not private.check_in_photo_in_use(photo) then
      insert into private.check_in_photo_cleanup(path) values(photo) on conflict do nothing;
    end if;
  end loop;
end;
$$;

create or replace function private.pending_check_in_photo_cleanup()
returns table(path text) language plpgsql security definer set search_path='' as $$
begin
  insert into private.check_in_photo_cleanup(path)
    select o.name from storage.objects o where o.bucket_id='check-in-photos'
      and o.created_at<now()-interval '24 hours'
      and not private.check_in_photo_in_use(o.name)
    for update of o skip locked
    on conflict do nothing;
  return query select q.path from private.check_in_photo_cleanup q
    where not private.check_in_photo_in_use(q.path)
    order by q.queued_at limit 100;
end;
$$;

create or replace function private.check_in_photo_cleanup_needed() returns boolean
language sql stable security invoker set search_path='' as $$
  select exists(select 1 from private.check_in_photo_cleanup)
    or exists(select 1 from storage.objects o where o.bucket_id='check-in-photos'
      and o.created_at<now()-interval '24 hours'
      and not private.check_in_photo_in_use(o.name));
$$;

-- The day's achievements now say which photo each carries.
create or replace function private.crew_achievements(target_crew_id uuid, on_day date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
begin
  if not private.is_crew_member(target_crew_id, viewer) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', a.id, 'user_id', a.user_id, 'posted_on', a.posted_on,
        'body', a.body, 'kind', a.kind, 'photo_path', a.photo_path,
        'created_at', a.created_at,
        'clap_count', (select count(*) from public.achievement_claps k
          where k.achievement_id = a.id),
        'viewer_clapped', exists(select 1 from public.achievement_claps k
          where k.achievement_id = a.id and k.actor_id = viewer))
      order by a.created_at, a.id)
    from public.crew_achievements a
    where a.crew_id = target_crew_id and a.posted_on = on_day
  ), '[]'::jsonb);
end;
$$;

-- Posting takes the photo's path, uploaded first as a check-in's is, and
-- refuses a post without one. The two-argument form goes: nothing has shipped
-- against it.
drop function public.post_crew_achievement(uuid, text);
drop function private.post_crew_achievement(uuid, text);

create function private.post_crew_achievement(
  target_crew_id uuid, achievement_body text, photo text, post_kind text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
  select (now() at time zone coalesce(t.name, 'UTC'))::date into today
  from public.crews c left join pg_catalog.pg_timezone_names t on t.name = c.timezone
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
$$;
revoke all on function private.post_crew_achievement(uuid, text, text, text) from public, anon;
grant execute on function private.post_crew_achievement(uuid, text, text, text) to authenticated;

create function public.post_crew_achievement(
  target_crew_id uuid, achievement_body text, photo text, post_kind text
)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.post_crew_achievement(target_crew_id, achievement_body, photo, post_kind);
$$;
revoke all on function public.post_crew_achievement(uuid, text, text, text) from public, anon;
grant execute on function public.post_crew_achievement(uuid, text, text, text) to authenticated;

-- A clap on a plain story says so: the author's notification reads "clapped
-- your story", from its own event type, rather than calling it a win.
create or replace function private.notify_achievement_clap(target_achievement_id uuid, actor uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  author uuid;
  crew uuid;
  post_kind text;
  achievement_text text;
  actor_name text;
  event_type text;
  event uuid;
begin
  select a.user_id, a.crew_id, a.kind, left(a.body, 120)
    into author, crew, post_kind, achievement_text
  from public.crew_achievements a where a.id = target_achievement_id;
  if author is null or author = actor then return; end if;
  event_type := case post_kind when 'story' then 'story_clapped' else 'achievement_clapped' end;
  -- Names supply display text only, never membership or delivery authorization.
  select coalesce(nullif(left(trim(first_name), 60), ''), 'A crew member')
    into actor_name from public.users where id = actor;
  insert into private.notification_events(dedupe_key, type, crew_id, actor_id, payload)
  values ('achievement_clapped:' || target_achievement_id || ':' || actor,
    event_type, crew, actor,
    jsonb_build_object(
      'recipient_id', author, 'achievement_id', target_achievement_id,
      'achievement_text', achievement_text,
      'actor_name', coalesce(actor_name, 'A crew member')))
  on conflict (dedupe_key) do nothing
  returning id into event;
  if event is null then return; end if;
  insert into private.notification_inbox(event_id, recipient_id) values (event, author);
  insert into private.notification_deliveries(event_id, device_id, recipient_id)
    select event, d.id, author
    from private.push_devices d
    join auth.sessions s on s.id = d.session_id and s.user_id = d.user_id
    where d.user_id = author and d.updated_at > now() - interval '60 days';
  if found then perform private.wake_notification_dispatcher(); end if;
end;
$$;
revoke all on function private.notify_achievement_clap(uuid, uuid) from public, anon, authenticated;

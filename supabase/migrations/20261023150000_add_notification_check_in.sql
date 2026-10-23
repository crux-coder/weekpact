-- A notification about a check-in names it — pact, member and day — in the
-- inbox and in its push, so a tap can open that check-in's story.
--
-- Additive: every key the row and the push had is still there, so an app
-- that does not know them reads both as before.

create or replace function private.notification_inbox(
  before_created_at timestamptz,
  before_event uuid,
  page_limit int
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  viewer uuid := (select auth.uid());
  result jsonb;
begin
  if viewer is null or not private.account_exists() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- A cursor is the complete sort key, or nothing at all.
  if (before_created_at is null) <> (before_event is null) then
    raise exception 'Invalid notification cursor' using errcode = '22023';
  end if;
  select coalesce(
    jsonb_agg(to_jsonb(entry) order by entry.created_at desc, entry.event_id desc),
    '[]'::jsonb
  ) into result
  from (
    select
      n.event_id,
      n.created_at,
      n.read_at is not null as read,
      e.type,
      e.crew_id,
      c.name as crew_name,
      e.actor_id,
      coalesce(nullif(trim(concat_ws(' ',
        nullif(trim(u.first_name), ''),
        nullif(trim(u.last_name), ''))), ''),
        'Crew member') as display_name,
      case
        when u.avatar_path = u.id::text || '/avatar.png'
        then u.id::text || '/avatar.png'
      end as avatar_path,
      e.payload->>'pact_title' as pact_title,
      p.icon_key,
      coalesce((e.payload->>'clap_count')::int, 0) as clap_count,
      -- The pact's place in its crew's list, which is what its colour is
      -- read from everywhere else in the app.
      case when p.id is not null then (
        select count(*)::int from public.crew_pacts q
        where q.crew_id = p.crew_id and (q.created_at, q.id) < (p.created_at, p.id)
      ) end as pact_index,
      -- The check-in the notice is about, which a tap opens: a clap is on
      -- the reader's own check-in, a completed pact on the actor's.
      case when e.type in ('check_in_clapped', 'pact_completed')
        then e.payload->>'pact_id' end as pact_id,
      case e.type
        when 'check_in_clapped' then n.recipient_id
        when 'pact_completed' then e.actor_id
      end as check_in_user_id,
      case when e.type in ('check_in_clapped', 'pact_completed')
        then e.payload->>'completed_on' end as check_in_day
    from private.notification_inbox n
    join private.notification_events e on e.id = n.event_id
    join public.crews c on c.id = e.crew_id
    join public.users u on u.id = e.actor_id
    left join public.crew_pacts p on p.id = (e.payload->>'pact_id')::uuid
    where n.recipient_id = viewer
      and (before_created_at is null
        or (n.created_at, n.event_id) < (before_created_at, before_event))
    order by n.created_at desc, n.event_id desc
    limit least(greatest(coalesce(page_limit, 20), 1), 50)
  ) entry;
  return result;
end;
$$;

-- A completed pact's push names whose check-in it was. A clap's push already
-- can: the check-in is the recipient's own.
create or replace function private.notify_pact_completed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare crew uuid; pact_title text; actor_name text;
begin
  select g.crew_id,g.title into crew,pact_title from public.crew_pacts g where g.id=new.pact_id;
  select coalesce(nullif(left(trim(first_name),60),''),'A crew member')
    into actor_name from public.users where id=new.user_id;
  perform private.enqueue_crew_notification('pact_completed',
    'pact_completed:'||new.pact_id||':'||new.user_id||':'||new.completed_on,
    crew,new.user_id,jsonb_build_object('pact_id',new.pact_id,'pact_title',left(pact_title,120),
      'actor_name',coalesce(actor_name,'A crew member'),'completed_on',new.completed_on,
      'check_in_user_id',new.user_id));
  return new;
end;
$$;

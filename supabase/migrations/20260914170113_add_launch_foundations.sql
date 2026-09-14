-- Aggregate weekly records are immutable once the crew's local week has ended.
-- No member names, emails, photos, or individual check-ins are copied here.
create table private.crew_week_results (
  crew_id uuid not null references public.crews(id) on delete cascade,
  week_start date not null,
  timezone text not null,
  check_ins integer not null,
  active_members integer not null,
  completed_pacts integer not null,
  total_pacts integer not null,
  earned boolean not null,
  finalized_at timestamptz not null default now(),
  primary key (crew_id, week_start)
);
alter table private.crew_week_results enable row level security;
revoke all on private.crew_week_results from public, anon, authenticated;

create function private.calculate_crew_week(p_crew uuid, p_week date, p_zone text)
returns table(check_ins integer, active_members integer, completed_pacts integer, total_pacts integer, earned boolean)
language sql stable security invoker set search_path = '' as $$
  with requirements as (
    select p.id, p.days_per_week, m.user_id, (
      select count(*) from public.pact_check_ins i where i.pact_id=p.id
      and i.user_id=m.user_id and i.completed_on between p_week and p_week+6
    ) as completed
    from public.crew_pacts p cross join public.crew_members m
    where p.crew_id=p_crew and m.crew_id=p_crew
      and (p.created_at at time zone p_zone)::date <= p_week+6
      and (m.joined_at at time zone p_zone)::date <= p_week+6
  ), pacts as (
    select id, bool_and(completed>=days_per_week) done from requirements group by id
  )
  select
    (select count(*)::integer from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id where p.crew_id=p_crew and i.completed_on between p_week and p_week+6),
    (select count(distinct i.user_id)::integer from public.pact_check_ins i join public.crew_pacts p on p.id=i.pact_id where p.crew_id=p_crew and i.completed_on between p_week and p_week+6),
    count(*) filter(where done)::integer, count(*)::integer, count(*)>0 and coalesce(bool_and(done),false)
  from pacts;
$$;
revoke all on function private.calculate_crew_week(uuid,date,text) from public,anon,authenticated;

-- Internal worker; deliberately not executable by API roles. Callers below
-- perform authorization, and triggers/cron use the database owner's privileges.
create function private.finalize_crew_weeks(p_crew uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare zone text; first_week date; this_week date; candidate date;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_crew::text, 713));
  select c.timezone, date_trunc('week', c.created_at at time zone c.timezone)::date
    into zone, first_week from public.crews c where c.id=p_crew;
  if not found then return; end if;
  this_week:=date_trunc('week',now() at time zone zone)::date;
  select coalesce(max(week_start)+7,first_week) into candidate from private.crew_week_results where crew_id=p_crew;
  while candidate<this_week loop
    insert into private.crew_week_results(crew_id,week_start,timezone,check_ins,active_members,completed_pacts,total_pacts,earned)
      select p_crew,candidate,zone,r.* from private.calculate_crew_week(p_crew,candidate,zone) r
      on conflict do nothing;
    candidate:=candidate+7;
  end loop;
end;
$$;
revoke all on function private.finalize_crew_weeks(uuid) from public,anon,authenticated;

create function private.finalize_all_crew_weeks()
returns void language plpgsql security definer set search_path = '' as $$
declare crew record;
begin
  for crew in select id from public.crews order by id loop
    perform private.finalize_crew_weeks(crew.id);
  end loop;
end;
$$;
revoke all on function private.finalize_all_crew_weeks() from public,anon,authenticated;
-- Seed the best available historical state before enabling immutable results.
select private.finalize_all_crew_weeks();

create function private.preserve_closed_weeks()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  if tg_table_name='crews' then target:=old.id;
  elsif tg_table_name='pact_check_ins' then
    select crew_id into target from public.crew_pacts where id=case when tg_op='INSERT' then new.pact_id else old.pact_id end;
  else target:=case when tg_op='INSERT' then new.crew_id else old.crew_id end;
  end if;
  if target is not null then perform private.finalize_crew_weeks(target); end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.preserve_closed_weeks() from public,anon,authenticated;
create trigger preserve_pact_weeks before insert or update or delete on public.crew_pacts for each row execute function private.preserve_closed_weeks();
create trigger preserve_member_weeks before insert or update or delete on public.crew_members for each row execute function private.preserve_closed_weeks();
create trigger preserve_check_in_weeks before insert or update or delete on public.pact_check_ins for each row execute function private.preserve_closed_weeks();
create trigger preserve_crew_weeks before update on public.crews for each row execute function private.preserve_closed_weeks();

create function private.frozen_crew_streak(p_crew uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare zone text; candidate date; earned_now boolean; result integer:=0;
begin
  if auth.uid() is null or not private.is_crew_member(p_crew,auth.uid()) then raise exception 'Crew membership required' using errcode='42501'; end if;
  perform private.finalize_crew_weeks(p_crew);
  select timezone into zone from public.crews where id=p_crew;
  candidate:=date_trunc('week',now() at time zone zone)::date;
  select r.earned into earned_now from private.calculate_crew_week(p_crew,candidate,zone) r;
  if earned_now then result:=1; end if;
  loop
    candidate:=candidate-7;
    select r.earned into earned_now from private.crew_week_results r where r.crew_id=p_crew and r.week_start=candidate;
    exit when not found or not earned_now;
    result:=result+1;
  end loop;
  return result;
end;
$$;
revoke all on function private.frozen_crew_streak(uuid) from public,anon;
grant execute on function private.frozen_crew_streak(uuid) to authenticated;
create or replace function public.crew_weekly_streak(target_crew_id uuid)
returns integer language sql volatile security invoker set search_path='' as $$ select private.frozen_crew_streak(target_crew_id); $$;
alter function public.crew_week_snapshot(uuid) volatile;

create table private.crew_recap_views (
  crew_id uuid not null, week_start date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key(crew_id,week_start,user_id),
  foreign key(crew_id,week_start) references private.crew_week_results(crew_id,week_start) on delete cascade
);
create index crew_recap_views_user on private.crew_recap_views(user_id);
alter table private.crew_recap_views enable row level security;
revoke all on private.crew_recap_views from public,anon,authenticated;
create function private.weekly_recap(p_crew uuid, p_seen date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; joined date; zone text;
begin
  if auth.uid() is null or not private.is_crew_member(p_crew,auth.uid()) then raise exception 'Crew membership required' using errcode='42501'; end if;
  perform private.finalize_crew_weeks(p_crew);
  select c.timezone,(m.joined_at at time zone c.timezone)::date into zone,joined from public.crews c join public.crew_members m on m.crew_id=c.id where c.id=p_crew and m.user_id=auth.uid();
  if p_seen is not null then
    insert into private.crew_recap_views(crew_id,week_start,user_id)
    select p_crew,p_seen,auth.uid() from private.crew_week_results where crew_id=p_crew and week_start=p_seen and week_start+6>=joined on conflict do nothing;
  end if;
  select to_jsonb(r)-'crew_id' || jsonb_build_object('seen',exists(select 1 from private.crew_recap_views v where v.crew_id=p_crew and v.week_start=r.week_start and v.user_id=auth.uid()))
    into result from private.crew_week_results r where r.crew_id=p_crew and r.week_start=date_trunc('week',now() at time zone zone)::date-7 and r.week_start+6>=joined;
  return result;
end;
$$;
revoke all on function private.weekly_recap(uuid,date) from public,anon;
grant execute on function private.weekly_recap(uuid,date) to authenticated;
create function public.weekly_recap(p_crew uuid,p_seen date default null) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.weekly_recap(p_crew,p_seen); $$;
revoke all on function public.weekly_recap(uuid,date) from public,anon;
grant execute on function public.weekly_recap(uuid,date) to authenticated;

-- Share invitations: one active link per crew, hashed, seven days, revocable.
-- Uses the existing 64-character invitation token format and acceptance route.
create table private.crew_share_links (
  crew_id uuid primary key references public.crews(id) on delete cascade,
  token_hash text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index crew_share_links_creator on private.crew_share_links(created_by);
alter table private.crew_share_links enable row level security;
revoke all on private.crew_share_links from public,anon,authenticated;
create function private.manage_crew_share_link(p_crew uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare token text; expiry timestamptz;
begin
  if auth.uid() is null or not private.is_crew_owner(p_crew,auth.uid()) then raise exception 'Crew owner required' using errcode='42501'; end if;
  if p_action is null or p_action not in ('status','create','revoke') then raise exception 'Invalid link action'; end if;
  perform 1 from public.crews where id=p_crew for update;
  if p_action='revoke' then
    delete from private.crew_share_links where crew_id=p_crew; return null;
  elsif p_action='status' then
    select expires_at into expiry from private.crew_share_links where crew_id=p_crew and expires_at>now();
    return case when expiry is null then null else jsonb_build_object('expires_at',expiry) end;
  elsif p_action<>'create' then raise exception 'Invalid link action'; end if;
  token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  expiry:=now()+interval '7 days';
  insert into private.crew_share_links(crew_id,token_hash,created_by,expires_at) values(p_crew,encode(extensions.digest(token,'sha256'),'hex'),auth.uid(),expiry)
    on conflict(crew_id) do update set token_hash=excluded.token_hash,created_by=excluded.created_by,expires_at=excluded.expires_at,created_at=now();
  return jsonb_build_object('token',token,'expires_at',expiry);
end;
$$;
revoke all on function private.manage_crew_share_link(uuid,text) from public,anon;
grant execute on function private.manage_crew_share_link(uuid,text) to authenticated;
create function public.manage_crew_share_link(p_crew uuid,p_action text) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.manage_crew_share_link(p_crew,p_action); $$;
revoke all on function public.manage_crew_share_link(uuid,text) from public,anon;
grant execute on function public.manage_crew_share_link(uuid,text) to authenticated;
-- Keep email-bound acceptance unchanged as a fallback for existing links.
alter function public.accept_crew_invite(text) set schema private;
alter function private.accept_crew_invite(text) rename to accept_email_crew_invite;
revoke all on function private.accept_email_crew_invite(text) from public,anon,authenticated;
create function private.accept_any_crew_invite(p_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare link private.crew_share_links%rowtype; recipient text; existing uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to join this crew' using errcode='42501'; end if;
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid invite'; end if;
  select lower(email) into recipient from auth.users where id=auth.uid() and email_confirmed_at is not null;
  if recipient is null then raise exception 'Confirm your email before joining' using errcode='42501'; end if;
  select * into link from private.crew_share_links where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if not found then return private.accept_email_crew_invite(p_token); end if;
  if link.expires_at<=now() then raise exception 'This invite link has expired'; end if;
  select crew_id into existing from public.crew_members where user_id=auth.uid();
  if existing=link.crew_id then return existing; end if;
  if existing is not null then raise exception 'You already belong to a crew'; end if;
  insert into public.crew_members(crew_id,user_id,email,role) values(link.crew_id,auth.uid(),recipient,'member');
  return link.crew_id;
end;
$$;
revoke all on function private.accept_any_crew_invite(text) from public,anon;
grant execute on function private.accept_any_crew_invite(text) to authenticated;
create function public.accept_crew_invite(p_token text) returns uuid language sql volatile security invoker set search_path='' as $$ select private.accept_any_crew_invite(p_token); $$;
revoke all on function public.accept_crew_invite(text) from public,anon;
grant execute on function public.accept_crew_invite(text) to authenticated;

-- First-party funnel measurements: event names and internal IDs only.
create table private.product_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  event text not null check(event in ('signup','crew_created','invite_created','invite_accepted','first_check_in','weekly_check_in','weekly_open')),
  crew_id uuid references public.crews(id) on delete cascade,
  period text not null default '',
  happened_at timestamptz not null default now(),
  primary key(user_id,event,period)
);
create index product_events_crew on private.product_events(crew_id);
create index product_events_time on private.product_events(happened_at,event);
alter table private.product_events enable row level security;
revoke all on private.product_events from public,anon,authenticated;
create function private.record_product_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid; crew uuid; event_name text; period_key text:=''; zone text;
begin
  case tg_table_name
    when 'users' then actor:=new.id;event_name:='signup';
    when 'crews' then actor:=new.owner_id;crew:=new.id;event_name:='crew_created';period_key:=new.id::text;
    when 'crew_members' then
      if new.role='owner' then return new; end if;
      actor:=new.user_id;crew:=new.crew_id;event_name:='invite_accepted';period_key:=crew::text;
    when 'crew_invites' then actor:=new.invited_by;crew:=new.crew_id;event_name:='invite_created';period_key:=new.id::text||':'||new.token_hash;
    when 'crew_share_links' then actor:=new.created_by;crew:=new.crew_id;event_name:='invite_created';period_key:=new.token_hash;
    when 'pact_check_ins' then
      actor:=new.user_id; select p.crew_id,c.timezone into crew,zone from public.crew_pacts p join public.crews c on c.id=p.crew_id where p.id=new.pact_id;
      insert into private.product_events(user_id,event,crew_id) values(actor,'first_check_in',crew) on conflict do nothing;
      event_name:='weekly_check_in';period_key:=crew::text||':'||date_trunc('week',new.completed_on::timestamp)::date::text;
  end case;
  insert into private.product_events(user_id,event,crew_id,period) values(actor,event_name,crew,period_key) on conflict do nothing;
  return new;
end;
$$;
revoke all on function private.record_product_event() from public,anon,authenticated;
create trigger product_signup after insert on auth.users for each row execute function private.record_product_event();
create trigger product_crew after insert on public.crews for each row execute function private.record_product_event();
create trigger product_join after insert on public.crew_members for each row execute function private.record_product_event();
create trigger product_invite after insert or update of token_hash on public.crew_invites for each row execute function private.record_product_event();
create trigger product_share_invite after insert or update of token_hash on private.crew_share_links for each row execute function private.record_product_event();
create trigger product_check_in after insert on public.pact_check_ins for each row execute function private.record_product_event();
create function private.record_weekly_open()
returns void language plpgsql security definer set search_path='' as $$
declare crew uuid; zone text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  select c.id,c.timezone into crew,zone from public.crew_members m join public.crews c on c.id=m.crew_id where m.user_id=auth.uid();
  insert into private.product_events(user_id,event,crew_id,period) values(auth.uid(),'weekly_open',crew,date_trunc('week',now() at time zone coalesce(zone,'UTC'))::date::text) on conflict do nothing;
end;
$$;
revoke all on function private.record_weekly_open() from public,anon;
grant execute on function private.record_weekly_open() to authenticated;
create function public.record_weekly_open() returns void language sql volatile security invoker set search_path='' as $$ select private.record_weekly_open(); $$;
revoke all on function public.record_weekly_open() from public,anon;
grant execute on function public.record_weekly_open() to authenticated;

-- Cron executes frequently to cover Monday midnight in every crew timezone,
-- including quarter-hour offsets. Unique weekly keys make repeats harmless.
-- Local test environments can omit pg_cron; production installs it below.
do $$ begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('weekpact-weekly-recaps','*/15 * * * *','select private.finalize_all_crew_weeks();');
  end if;
end $$;

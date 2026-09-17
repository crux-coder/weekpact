-- One crew per account without Pro.
--
-- Every way into a crew ends in a crew_members insert: creating one (through
-- the add_crew_owner trigger), accepting an email invite, answering the inbox,
-- and following a share link. The limit lives on that insert so a path added
-- later cannot quietly skip it, and so creating a second crew rolls the crew
-- itself back in the same transaction.

create function private.free_crew_limit() returns integer
language sql immutable set search_path = '' as $$ select 1 $$;

create function private.enforce_crew_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  joined integer;
begin
  -- Re-accepting an invite for a crew you are already in is a no-op upstream,
  -- so it must not read as joining another crew.
  if exists (
    select 1 from public.crew_members m
    where m.user_id = new.user_id and m.crew_id = new.crew_id
  ) then
    return new;
  end if;

  -- Two invites accepted at the same moment must not both find room for one.
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

  select count(*) into joined
  from public.crew_members m where m.user_id = new.user_id;

  if joined >= private.free_crew_limit() and not private.is_pro(new.user_id) then
    -- A dedicated SQLSTATE, so the app can offer an upgrade rather than show
    -- this sentence. Anyone already in more than one crew keeps them: the
    -- limit only applies to joining another.
    raise exception 'WeekPact Pro is needed to be in more than one crew'
      using errcode = 'WPPRO';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_crew_limit() from public, anon, authenticated;
revoke all on function private.free_crew_limit() from public, anon, authenticated;

create trigger crew_members_enforce_limit
before insert on public.crew_members
for each row execute function private.enforce_crew_limit();

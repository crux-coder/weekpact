-- Achievement photos could not be uploaded.
--
-- `20261022170000` taught the upload check that a photo's third segment may
-- read `achievements` instead of a pact id, and guarded the pact lookup with
-- `target <> 'achievements' and not exists (... id = target::uuid ...)`. SQL
-- promises nothing about evaluating the left of an `and` first, and
-- PL/pgSQL plans the expression with the value already in place, so
-- `'achievements'::uuid` is folded — and fails — while the plan is being
-- made. The failure landed in the function's own `invalid_text_representation`
-- handler, which answers false, and Storage refused every achievement photo.
--
-- The pact is now matched on its id as text, so nothing here casts a segment
-- that may not be a uuid. Everything else is as `20261022170000` left it.
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
    select 1 from public.crew_pacts where id::text=target and crew_id=crew) then
    return false;
  end if;
  select (now() at time zone coalesce(t.name,'UTC'))::date into today
    from public.crews c left join pg_catalog.pg_timezone_names t on t.name=c.timezone where c.id=crew;
  return split_part(object_name,'/',4)=today::text;
exception when invalid_text_representation then return false;
end;
$$;

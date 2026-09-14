-- Every creation gets its own seven-day token, without replacing earlier links.
-- Preserve existing tokens and the RPC signature for app compatibility.
alter table private.crew_share_links drop constraint crew_share_links_pkey;
alter table private.crew_share_links add primary key (token_hash);
alter table private.crew_share_links drop constraint crew_share_links_token_hash_key;
create index crew_share_links_crew_expiry
  on private.crew_share_links (crew_id, expires_at);

create or replace function private.manage_crew_share_link(p_crew uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare token text; expiry timestamptz;
begin
  if auth.uid() is null or not private.is_crew_owner(p_crew, auth.uid()) then
    raise exception 'Crew owner required' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('status', 'create') then
    raise exception 'Invalid link action';
  end if;
  perform 1 from public.crews where id = p_crew for update;
  if p_action = 'status' then
    select max(expires_at) into expiry
      from private.crew_share_links where crew_id = p_crew and expires_at > now();
    return case when expiry is null then null
      else jsonb_build_object('expires_at', expiry) end;
  end if;
  token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  expiry := now() + interval '7 days';
  insert into private.crew_share_links(crew_id, token_hash, created_by, expires_at)
    values(p_crew, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), expiry);
  return jsonb_build_object('token', token, 'expires_at', expiry);
end;
$$;
revoke all on function private.manage_crew_share_link(uuid, text) from public, anon;
grant execute on function private.manage_crew_share_link(uuid, text) to authenticated;

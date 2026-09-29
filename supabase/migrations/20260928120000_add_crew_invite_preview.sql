-- An invitation that cannot name its crew asks people to join an unknown. The
-- preview answers a token with the three things an invitation card says, and
-- nothing that belongs to the crew's members: no emails, no ids, no pacts.
-- Tokens are matched by their SHA-256 hash, the way acceptance matches them,
-- so the raw token is never stored or compared in the clear.
create function private.preview_crew_invite(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare digest text; target uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to view this invite' using errcode='42501'; end if;
  -- An unknown or expired token is not an error here: the page falls back to
  -- its own copy, and a token that is merely wrong should say no more than
  -- one that is right about a crew the viewer cannot see.
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then return null; end if;
  digest := encode(extensions.digest(p_token,'sha256'),'hex');
  select crew_id into target from private.crew_share_links
    where token_hash=digest and expires_at>now();
  if target is null then
    select crew_id into target from public.crew_invites
      where token_hash=digest and accepted_at is null and expires_at>now();
  end if;
  if target is null then return null; end if;
  return (select jsonb_build_object(
    'crew_name', c.name,
    'member_count', (select count(*) from public.crew_members m where m.crew_id=c.id),
    'owner_name', coalesce(nullif(trim(concat_ws(' ',
      nullif(trim(u.raw_user_meta_data->>'first_name'),''),
      nullif(trim(u.raw_user_meta_data->>'last_name'),''))),''), 'Crew member')
  ) from public.crews c join auth.users u on u.id=c.owner_id where c.id=target);
end;
$$;
revoke all on function private.preview_crew_invite(text) from public,anon;
grant execute on function private.preview_crew_invite(text) to authenticated;
create function public.preview_crew_invite(p_token text) returns jsonb language sql stable security invoker set search_path='' as $$ select private.preview_crew_invite(p_token); $$;
revoke all on function public.preview_crew_invite(text) from public,anon;
grant execute on function public.preview_crew_invite(text) to authenticated;

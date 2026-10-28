-- The per-pact history on profiles was taken out of the app before it
-- shipped. 20261028150000 had already been applied, so it stays as applied
-- and this takes its three functions back out. Nothing else referenced them,
-- and no table was ever added for them.
drop function if exists public.my_pact_history();
drop function if exists public.member_pact_history(uuid);
drop function if exists private.pact_history(uuid);

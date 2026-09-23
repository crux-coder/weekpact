-- Removing the cross-crew feed.
--
-- The Feed destination is gone from the app: the stories rail on Home shows
-- today's check-ins, and the notification inbox carries everything a member is
-- told. Nothing calls `check_in_feed` any more, so the RPC and the index built
-- for its paging come out with it.
--
-- Claps are untouched. `set_check_in_clap` and `check_in_claps` stay exactly as
-- they are — the story viewer still writes claps and reads the count back from
-- that function's own return, which never went through the feed.
--
-- The index only ever served the feed's cursor (created_at, pact_id, user_id,
-- completed_on across every crew). The week, the roster and the activity list
-- all read a single crew's rows and use `pact_check_ins_pkey` instead.
drop function if exists public.check_in_feed(timestamptz, uuid, uuid, date, int);
drop function if exists private.check_in_feed(timestamptz, uuid, uuid, date, int);
drop index if exists public.pact_check_ins_feed_idx;

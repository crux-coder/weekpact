-- Deleting a pact, for the crew's owner.
--
-- The cascade already existed and is what makes this safe to expose: a pact's
-- check-ins hang off `crew_pacts` with `on delete cascade`, and the claps on
-- those check-ins hang off them the same way, so removing the pact takes its
-- whole history with it in one statement rather than leaving rows pointing at
-- a pact that is gone.
--
-- Check-in photos are storage objects, not rows, so they survive the cascade —
-- but only until `private.pending_check_in_photo_cleanup` next runs. That
-- sweeper queues any object over 24 hours old with no `pact_check_ins` row
-- naming it, which is exactly what a deleted pact's photos become.
grant delete on public.crew_pacts to authenticated;
create policy crew_pacts_delete_for_owners on public.crew_pacts
for delete to authenticated
using (
  private.is_crew_owner(crew_id, (select auth.uid()))
  and private.is_crew_member(crew_id, (select auth.uid()))
);

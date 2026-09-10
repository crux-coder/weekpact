-- Only editable goal fields can change; crew and creator remain immutable.
grant update (title, frequency, days_per_week, icon_key) on public.crew_goals to authenticated;
create policy crew_goals_edit_for_owners on public.crew_goals
for update to authenticated
using (
  private.is_crew_owner(crew_id, (select auth.uid()))
  and private.is_crew_member(crew_id, (select auth.uid()))
)
with check (
  private.is_crew_owner(crew_id, (select auth.uid()))
  and private.is_crew_member(crew_id, (select auth.uid()))
);

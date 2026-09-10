-- Recurring crew goals: weekly targets count distinct days, Monday–Sunday.
create table public.crew_goals (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid not null references public.crews(id) on delete cascade,
  title text not null check (title = btrim(title) and char_length(title) between 2 and 100),
  frequency text not null check (frequency in ('daily', 'weekly')),
  days_per_week integer not null check (days_per_week between 1 and 7),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint crew_goals_daily_seven_days check (frequency <> 'daily' or days_per_week = 7)
);

create index crew_goals_crew_created_idx on public.crew_goals (crew_id, created_at);
create index crew_goals_created_by_idx on public.crew_goals (created_by);
alter table public.crew_goals enable row level security;
revoke all on public.crew_goals from public, anon, authenticated;
grant select, insert on public.crew_goals to authenticated;
grant all on public.crew_goals to service_role;

create policy crew_goals_read_for_members on public.crew_goals
for select to authenticated
using (private.is_crew_member(crew_id, (select auth.uid())));

create policy crew_goals_add_for_owners on public.crew_goals
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.is_crew_owner(crew_id, (select auth.uid()))
  and private.is_crew_member(crew_id, (select auth.uid()))
);

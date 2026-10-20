-- Onboarding is a path, not a switch.
--
-- A single "completed" flag knew only whether the profile form had been
-- saved. The question after it — who you are doing this with — lived in the
-- app's memory, so closing the app between the two skipped it, and nothing
-- short of clearing the flag could send someone back to the start.
--
-- public.users.onboarding_step is where a person is now: 'profile' (the form),
-- 'crew' (the crew fork, or an invitation answering it) and 'done'. Setting it
-- back to 'profile' restarts onboarding. Every step a person reaches is also
-- written to public.user_onboarding_steps, so a restart keeps the history of
-- the first run instead of overwriting it.
alter table public.users
  add column onboarding_step text not null default 'profile'
    constraint users_onboarding_step check (onboarding_step in ('profile', 'crew', 'done'));

-- Everyone who finished the old single step had nothing further to do.
update public.users
  set onboarding_step = case when onboarding_completed then 'done' else 'profile' end;

alter table public.users drop constraint users_onboarding_needs_name;
alter table public.users drop column onboarding_completed;
-- The profile form is what asks for a first name; leaving it without one is
-- not leaving it.
alter table public.users add constraint users_onboarding_needs_name
  check (onboarding_step = 'profile' or first_name <> '');
grant update (onboarding_step) on public.users to authenticated;

-- Sign-up metadata can still mark an account as already set up (the App
-- Review account is created that way); it lands on 'done'.
create or replace function private.insert_user_profile(user_id uuid, user_email text, meta jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.users(id, email, first_name, last_name, avatar_path, onboarding_step)
  values (
    user_id,
    user_email,
    left(coalesce(trim(meta->>'first_name'), ''), 60),
    left(coalesce(trim(meta->>'last_name'), ''), 60),
    case when meta->>'avatar_path' = user_id::text || '/avatar.png' then meta->>'avatar_path' end,
    case
      when coalesce(meta->>'onboarding_completed' = 'true', false)
        and coalesce(trim(meta->>'first_name'), '') <> '' then 'done'
      else 'profile'
    end
  )
  on conflict (id) do nothing;
$$;
revoke all on function private.insert_user_profile(uuid, text, jsonb) from public, anon, authenticated;

create table public.user_onboarding_steps (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  step text not null constraint user_onboarding_steps_step
    check (step in ('profile', 'crew', 'done')),
  reached_at timestamptz not null default now()
);
create index user_onboarding_steps_user_idx
  on public.user_onboarding_steps(user_id, reached_at);
alter table public.user_onboarding_steps enable row level security;
revoke all on public.user_onboarding_steps from public, anon, authenticated;
grant select on public.user_onboarding_steps to authenticated;
-- Written only by the trigger below; a person can read their own history.
create policy user_onboarding_steps_read_own on public.user_onboarding_steps
  for select to authenticated using (user_id = (select auth.uid()));

create function private.record_onboarding_step() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_onboarding_steps(user_id, step) values (new.id, new.onboarding_step);
  return new;
end;
$$;
revoke all on function private.record_onboarding_step() from public, anon, authenticated;
create trigger record_onboarding_step_insert after insert on public.users
for each row execute function private.record_onboarding_step();
create trigger record_onboarding_step_update after update of onboarding_step on public.users
for each row when (old.onboarding_step is distinct from new.onboarding_step)
execute function private.record_onboarding_step();

-- Existing accounts start their history at the step they are on now.
insert into public.user_onboarding_steps(user_id, step, reached_at)
select id, onboarding_step, updated_at from public.users;

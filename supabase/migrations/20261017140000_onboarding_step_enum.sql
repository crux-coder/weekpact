-- The onboarding step is one of three values, so the database says so with a
-- type rather than a text column and a check.
create type public.onboarding_step as enum ('profile', 'crew', 'done');

-- The name rule and the history trigger both read the step, so they are
-- rebuilt around the new type.
drop trigger record_onboarding_step_update on public.users;
alter table public.users drop constraint users_onboarding_needs_name;
alter table public.users drop constraint users_onboarding_step;
alter table public.users alter column onboarding_step drop default;
alter table public.users
  alter column onboarding_step type public.onboarding_step
    using onboarding_step::public.onboarding_step;
alter table public.users alter column onboarding_step set default 'profile';
alter table public.users add constraint users_onboarding_needs_name
  check (onboarding_step = 'profile' or first_name <> '');
create trigger record_onboarding_step_update after update of onboarding_step on public.users
for each row when (old.onboarding_step is distinct from new.onboarding_step)
execute function private.record_onboarding_step();

alter table public.user_onboarding_steps drop constraint user_onboarding_steps_step;
alter table public.user_onboarding_steps
  alter column step type public.onboarding_step using step::public.onboarding_step;

-- A CASE of string literals is text, which does not assign to the enum.
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
    end::public.onboarding_step
  )
  on conflict (id) do nothing;
$$;
revoke all on function private.insert_user_profile(uuid, text, jsonb) from public, anon, authenticated;

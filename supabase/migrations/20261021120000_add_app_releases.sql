-- The newest build in each store, and the oldest one that still works.
--
-- The app reads its own platform's row on launch and when it comes back to
-- the foreground. Below latest_version it offers the update once; below
-- min_version it refuses to go on until the person updates, which is the
-- lever for a backend change that breaks older builds. Rows are raised by
-- `pnpm mark-released` only once a release is live in the store, never on
-- upload: a prompt pointing at a build nobody can download yet is worse than
-- no prompt.
create table public.app_releases (
  platform text primary key check (platform in ('ios', 'android')),
  latest_version text not null check (latest_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  min_version text not null check (min_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  -- Optional words for the prompt, such as what changed.
  message text check (char_length(message) <= 300),
  updated_at timestamptz not null default now()
);

alter table public.app_releases enable row level security;
revoke all on public.app_releases from public, anon, authenticated;
-- Signed-out screens check too, so anon reads as well; nobody writes from
-- the app.
grant select on public.app_releases to anon, authenticated;
create policy app_releases_read on public.app_releases for select
  to anon, authenticated using (true);

create function private.touch_app_release() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger touch_app_release before update on public.app_releases
for each row execute function private.touch_app_release();

insert into public.app_releases(platform, latest_version, min_version) values
  ('ios', '1.0.0', '1.0.0'),
  ('android', '1.0.0', '1.0.0');

-- The in-app update prompt is gone, so nothing reads the store versions.
drop table public.app_releases;
drop function private.touch_app_release();

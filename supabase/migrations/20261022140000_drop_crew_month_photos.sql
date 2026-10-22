-- The month drawer it fed is gone from the app: Home's week card shows the
-- month as dots from the week history, and nothing asks for its photos. The
-- public wrapper goes first, since it calls the private definer.
drop function if exists public.crew_month_photos(uuid, date);
drop function if exists private.crew_month_photos(uuid, date);

-- Remove weekly recaps, keeping completed-week history that protects streaks.
drop function if exists public.weekly_recap(uuid, date);
drop function if exists private.weekly_recap(uuid, date);
drop table if exists private.crew_recap_views;

-- The old job only finalizes streak history; keep it under an accurate name.
do $$
declare old_job record;
begin
  if to_regclass('cron.job') is not null then
    for old_job in select jobid from cron.job where jobname = 'weekpact-weekly-recaps'
    loop
      perform cron.unschedule(old_job.jobid);
    end loop;
    perform cron.schedule(
      'weekpact-finalize-crew-weeks',
      '*/15 * * * *',
      'select private.finalize_all_crew_weeks();'
    );
  end if;
end;
$$;

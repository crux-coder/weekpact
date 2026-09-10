-- Installed by tool/deploy_notifications.py; credentials remain in Vault.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
do $$
declare secret_id uuid;
begin
  select id into secret_id from vault.secrets where name='notification_dispatch_secret';
  if secret_id is null then
    perform vault.create_secret('__DISPATCH_SECRET__','notification_dispatch_secret');
  else
    perform vault.update_secret(secret_id,'__DISPATCH_SECRET__');
  end if;
end;
$$;
create or replace function private.wake_notification_dispatcher() returns void
language plpgsql security definer set search_path='' as $$
declare credential text;
begin
  if not exists(select 1 from private.notification_deliveries where status in ('pending','sending') and available_at<=now()) then return; end if;
  select decrypted_secret into credential from vault.decrypted_secrets where name='notification_dispatch_secret';
  if credential is null then return; end if;
  perform net.http_post(
    url := 'https://__PROJECT_REF__.supabase.co/functions/v1/dispatch-notifications',
    headers := jsonb_build_object('Content-Type','application/json','x-notification-secret',credential),
    body := '{}'::jsonb, timeout_milliseconds := 5000
  );
exception when others then
  -- The durable outbox remains available to the next scheduled attempt.
  return;
end;
$$;
revoke all on function private.wake_notification_dispatcher() from public,anon,authenticated;
select cron.schedule('weekpact-notification-dispatch','* * * * *','select private.wake_notification_dispatcher()');

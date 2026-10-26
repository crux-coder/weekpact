-- WeekPact no longer sells anything. Everyone can be in as many crews as they
-- like, and the RevenueCat mirror goes with its data.
--
-- Older builds never call these functions; they only recognise the WPPRO
-- refusal, which simply stops happening.

drop trigger if exists crew_members_enforce_limit on public.crew_members;
drop function if exists private.enforce_crew_limit();
drop function if exists private.free_crew_limit();

drop function if exists public.apply_subscription_event(jsonb);
drop function if exists public.pro_status();
drop function if exists private.apply_subscription_event(jsonb);
drop function if exists private.pro_status();
drop function if exists private.is_pro(uuid);
drop function if exists private.subscription_account(jsonb);
drop function if exists private.subscription_until(private.subscriptions);

drop table if exists private.subscriptions;

-- Run as a database administrator. No customer-facing endpoint exposes these.
-- Main metric: completed crew-local weeks with at least two people checking in.
select week_start,
       count(*) filter (where active_members >= 2) as active_crews,
       count(*) as total_crews,
       sum(check_ins) as total_check_ins
from private.crew_week_results
where week_start >= current_date - 84
group by week_start order by week_start;

-- New-account cohorts and activation. Owners create crews; invited members join.
with cohorts as (
  select user_id,date_trunc('week',happened_at)::date as signup_week,happened_at
  from private.product_events where event='signup'
)
select c.signup_week,count(*) as signups,
  count(*) filter(where exists(select 1 from private.product_events e where e.user_id=c.user_id and e.event='crew_created')) as created_crew,
  count(*) filter(where exists(select 1 from private.product_events e where e.user_id=c.user_id and e.event='invite_created')) as created_invitation,
  count(*) filter(where exists(select 1 from private.product_events e where e.user_id=c.user_id and e.event='invite_accepted')) as joined_crew,
  count(*) filter(where exists(select 1 from private.product_events e where e.user_id=c.user_id and e.event='first_check_in')) as checked_in,
  count(*) filter(where exists(select 1 from private.product_events e where e.user_id=c.user_id and e.event='weekly_open' and e.happened_at>=c.happened_at+interval '7 days')) as returned_after_seven_days
from cohorts c group by c.signup_week order by c.signup_week;

-- Crew retention: among activated crews, how many had two check-in members
-- again one and three weeks after their first active week?
with first_active as (
 select crew_id,min(week_start) week_start from private.crew_week_results
 where active_members>=2 group by crew_id
)
select f.week_start,count(*) activated_crews,
 count(*) filter(where w2.active_members>=2) week_two_active,
 count(*) filter(where w4.active_members>=2) week_four_active
from first_active f
left join private.crew_week_results w2 on w2.crew_id=f.crew_id and w2.week_start=f.week_start+7
left join private.crew_week_results w4 on w4.crew_id=f.crew_id and w4.week_start=f.week_start+21
group by f.week_start order by f.week_start;

alter table public.crew_goals
  add column icon_key text not null default 'target'
  check (icon_key in ('target', 'book', 'strength', 'walk', 'run', 'cycle', 'sleep', 'yoga', 'food', 'music', 'art', 'code', 'plant', 'savings'));

// What the crew chat migration expects of Supabase Realtime: the publication it
// adds tables to, and the broadcast table its channel policies guard.
export const realtimeTestSchema = `
  create publication supabase_realtime;
  create schema realtime;
  create table realtime.messages(topic text, extension text, payload jsonb);
  alter table realtime.messages enable row level security;
  create function realtime.topic() returns text language sql stable as $$
    select nullif(current_setting('realtime.topic', true), '')
  $$;
`;

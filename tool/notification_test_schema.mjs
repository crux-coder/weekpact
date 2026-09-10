export const notificationTestSchema = `
alter table auth.users add column raw_user_meta_data jsonb not null default '{}';
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade);
create function auth.jwt() returns jsonb language sql stable as $$
 select jsonb_build_object('session_id',nullif(current_setting('request.jwt.claim.session_id',true),''))
$$;
`;

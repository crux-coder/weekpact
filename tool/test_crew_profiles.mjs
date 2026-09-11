import { storageTestSchema } from './storage_test_schema.mjs';
// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite entrypoint.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const owner = '00000000-0000-4000-8000-000000000001';
const member = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const crew = '00000000-0000-4000-8000-000000000011';
await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth; create schema extensions;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to authenticated;
  grant execute on function auth.uid() to authenticated;
`);
const base = await readFile(new URL('../supabase/migrations/20260904155307_create_crews_and_invites.sql', import.meta.url), 'utf8');
// PGlite has built-in UUID generation; invite-token hashing is outside these tests.
await db.exec(base.replace('create extension if not exists pgcrypto with schema extensions;', ''));
await db.exec(await readFile(new URL('../supabase/migrations/20260909172623_create_crew_goals.sql', import.meta.url), 'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20260909175528_add_goal_icons.sql', import.meta.url), 'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20260909175842_allow_goal_editing.sql', import.meta.url), 'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20260909180912_add_goal_check_ins.sql', import.meta.url), 'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20260909211520_add_crew_weekly_streak.sql', import.meta.url), 'utf8'));
await db.query('insert into auth.users values ($1,$2),($3,$4),($5,$6)', [owner,'owner@example.com',member,'member@example.com',outsider,'outsider@example.com']);
await db.query('insert into public.crews (id,name,owner_id) values ($1,$2,$3)', [crew,'Test Crew',owner]);
await db.query("insert into public.crew_members (crew_id,user_id,email,role) values ($1,$2,'member@example.com','member')", [crew,member]);

await db.exec("alter table auth.users add column raw_user_meta_data jsonb default '{}'::jsonb");
await db.exec(storageTestSchema);
await db.exec(await readFile(new URL('../supabase/migrations/20260910110607_create_avatar_storage.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20260910234413_add_crew_profile_previews.sql',import.meta.url),'utf8'));
await db.query("update auth.users set raw_user_meta_data=$1 where id=$2", [{first_name:'Jane',last_name:'Doe',avatar_path:`${member}/avatar.png`},member]);
await db.query("insert into storage.objects(bucket_id,name) values('avatars',$1)",[`${member}/avatar.png`]);
async function asUser(user,fn) { await db.exec('begin'); try { await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user]); await db.exec('set local role authenticated'); await fn(); } finally {await db.exec('rollback');} }
await asUser(owner, async()=>{
 const row=(await db.query('select public.crew_week_snapshot($1) as snapshot',[crew])).rows[0].snapshot;
 const profile=row.members.find(m=>m.user_id===member);
 assert.equal(profile.display_name,'Jane Doe');assert.equal(profile.avatar_path,`${member}/avatar.png`);
 assert.equal((await db.query('select * from storage.objects')).rows.length,1);
 assert.equal((await db.query("update storage.objects set name=name returning *")).rows.length,0);
});
await asUser(outsider,async()=>{
 assert.equal((await db.query('select private.crew_member_profile($1,$2) as profile',[crew,member])).rows[0].profile,null);
 assert.equal((await db.query('select * from storage.objects')).rows.length,0);
});
await db.query('delete from crew_members where crew_id=$1 and user_id=$2',[crew,member]);
await asUser(owner,async()=>assert.equal((await db.query('select * from storage.objects')).rows.length,0));
await db.close();console.log('Crew profile visibility, photo read access, write isolation, and membership removal checks passed.');

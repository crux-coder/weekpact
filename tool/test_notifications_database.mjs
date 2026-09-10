import { readFile,readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import {storageTestSchema} from './storage_test_schema.mjs';
import {notificationTestSchema} from './notification_test_schema.mjs';
const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;
create schema auth;create schema extensions;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to authenticated;
create function extensions.digest(value text, algorithm text) returns bytea language sql as $$select sha256(convert_to(value,'UTF8'))$$;`);
await db.exec(storageTestSchema);await db.exec(notificationTestSchema);
for(const f of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort())
 await db.exec((await readFile('supabase/migrations/'+f,'utf8')).replace('create extension if not exists pgcrypto with schema extensions;',''));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [actor,member,outsider,crew,goal,s1,s2,s3]=[1,2,3,10,20,101,102,103].map(id);
for(const [u,s] of [[actor,s1],[member,s2],[outsider,s3]]) {
 await db.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),'{\"first_name\":\"Ada\"}')",[u,u+'@example.com']);
 await db.query('insert into auth.sessions values($1,$2)',[s,u]);
}
await db.query("insert into crews(id,name,owner_id) values($1,'Crew',$2)",[crew,actor]);
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')",[crew,member]);
await db.query("insert into crew_goals(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','daily',7,$3)",[goal,crew,actor]);
async function user(u,s,fn,role='authenticated') {
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.session_id',$2,false)",[u,s]);
 await db.exec('set role '+role);try{return await fn();}finally{await db.exec('reset role');}
}
const register=t=>db.query("select register_push_device($1,'ios')",[t]);
for(const [u,s] of [[actor,s1],[member,s2],[outsider,s3]]) await user(u,s,()=>register('token_'+u));
await user(member,s2,()=>register('second_token_'+member));
await user(outsider,s3,()=>assert.rejects(register('token_'+member),/another active session/));
await user(member,s2,()=>assert.rejects(db.query('select * from private.push_devices'),/permission denied/));
await user(member,s2,()=>assert.rejects(db.query('select * from claim_notification_deliveries()'),/permission denied/));
const save=ids=>user(actor,s1,()=>db.query('select save_goal_check_ins($1,current_date,$2)',[crew,ids]));
await save([goal]);await save([goal]);await save([]);await save([goal]);
assert.equal((await db.query('select * from private.notification_events')).rows.length,1);
assert.equal((await db.query('select * from private.notification_deliveries')).rows.length,2);
const claim=()=>user('','',()=>db.query('select * from claim_notification_deliveries()'),'service_role');
let jobs=(await claim()).rows;assert.equal(jobs.length,2);
assert.equal((await claim()).rows.length,0);
await db.query("select finish_notification_delivery($1,$2,'sent',null)",[jobs[0].delivery_id,jobs[0].lease]);
await db.query("select finish_notification_delivery($1,$2,'retry','UNAVAILABLE')",[jobs[1].delivery_id,jobs[1].lease]);
assert.equal((await claim()).rows.length,0);
await db.exec("update private.notification_deliveries set available_at=now()-interval '1 minute' where status='pending'");
let retried=(await claim()).rows;assert.equal(retried.length,1);
await db.query("select finish_notification_delivery($1,$2,'sent',null)",[jobs[1].delivery_id,jobs[1].lease]);
assert.equal((await db.query("select status from private.notification_deliveries where id=$1",[jobs[1].delivery_id])).rows[0].status,'sending');
await db.query("select finish_notification_delivery($1,$2,'unregistered','UNREGISTERED')",[retried[0].delivery_id,retried[0].lease]);
assert.equal((await db.query('select * from private.push_devices where user_id=$1',[member])).rows.length,1);
// A new event followed by leaving the crew is cancelled before sending.
await db.exec('delete from private.notification_events');await save([]);await save([goal]);
await db.query('delete from crew_members where user_id=$1',[member]);
assert.equal((await claim()).rows.length,0);
assert.equal((await db.query('select status from private.notification_deliveries')).rows[0].status,'cancelled');
// Session revocation removes eligibility even if the token still exists.
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')",[crew,member]);
await db.exec('delete from private.notification_events');await save([]);await save([goal]);
await db.query('delete from auth.sessions where id=$1',[s2]);
assert.equal((await claim()).rows.length,0);
await user(member,s2,()=>assert.rejects(register('token_'+member),/Active session/));
console.log('Notification database checks passed: ownership, session checks, recipient fanout, deduplication, leases, retries, stale ack, token pruning, and membership removal.');
await db.close();

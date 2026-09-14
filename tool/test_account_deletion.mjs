import { notificationTestSchema } from './notification_test_schema.mjs';
import { storageTestSchema } from './storage_test_schema.mjs';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, member, other, crew, pact, otherPact, session] = [1,2,3,10,20,21,30].map(id);
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth; create schema extensions;
create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated;
create function extensions.digest(value text, algorithm text) returns bytea language sql as $$ select sha256(convert_to(value, 'UTF8')) $$;
`);
await db.exec(storageTestSchema);
await db.exec(notificationTestSchema);
const directory = new URL('../supabase/migrations/', import.meta.url);
for (const file of (await readdir(directory)).filter(f => f.endsWith('.sql')).sort()) {
  await db.exec((await readFile(new URL(file, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', ''));
}
for (const [i,user] of [owner,member,other].entries()) await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[user,`user${i}@example.com`]);
await db.query("insert into crews(id,name,owner_id) values($1,'Review Crew',$2)",[crew,owner]);
for (const [user,email,date] of [[member,'user1@example.com','2026-01-01'],[other,'user2@example.com','2026-02-01']]) {
 await db.query("insert into crew_members(crew_id,user_id,email,role,joined_at) values($1,$2,$3,'member',$4)",[crew,user,email,date]);
}
for (const [g,creator] of [[pact,owner],[otherPact,other]]) await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','weekly',3,$3)",[g,crew,creator]);
for (const [g,user] of [[pact,owner],[pact,member],[otherPact,owner],[otherPact,other]]) await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,current_date)',[g,user]);
await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,owner]);
await db.query("insert into private.push_devices(user_id,session_id,token,platform) values($1,$2,repeat('x',30),'ios')",[owner,session]);
await db.query("insert into crew_invites(crew_id,email,token_hash,invited_by) values($1,'user0@example.com',repeat('a',64),$2)",[crew,other]);
let passed = 0;
async function scenario(fn) { await db.exec('begin'); try { await fn(); passed++; } finally { await db.exec('rollback'); } }
const count = async(sql,args=[]) => (await db.query(sql,args)).rows.length;
await scenario(async()=>{
 await db.query('delete from auth.users where id=$1',[owner]);
 assert.equal((await db.query('select owner_id from crews')).rows[0].owner_id,member);
 assert.equal((await db.query("select user_id from crew_members where role='owner'")).rows[0].user_id,member);
 assert.equal(await count('select * from crew_pacts where id=$1',[pact]),0);
 assert.equal(await count('select * from pact_check_ins where pact_id=$1',[pact]),0);
 assert.equal(await count('select * from pact_check_ins where user_id=$1',[owner]),0);
 assert.equal(await count('select * from pact_check_ins where pact_id=$1 and user_id=$2',[otherPact,other]),1);
 assert.equal(await count('select * from crew_invites'),0);
 assert.equal(await count('select * from auth.sessions where user_id=$1',[owner]),0);
 assert.equal(await count('select * from private.push_devices where user_id=$1',[owner]),0);
 assert.equal(await count('select * from private.notification_events where actor_id=$1',[owner]),0);
 assert.equal(await count("select * from private.notification_events where payload->>'pact_id'=$1",[pact]),0);
});
await scenario(async()=>{
 await db.query('delete from auth.users where id in ($1,$2)',[member,other]);
 await db.query('delete from auth.users where id=$1',[owner]);
 assert.equal(await count('select * from crews'),0);
 assert.equal(await count('select * from crew_pacts'),0);
});
await scenario(async()=>{
 await db.query('delete from auth.users where id=$1',[member]);
 assert.equal((await db.query('select owner_id from crews')).rows[0].owner_id,owner);
 assert.equal(await count('select * from pact_check_ins where user_id=$1',[member]),0);
 assert.equal(await count('select * from crew_pacts'),2);
});
await scenario(async()=>{
 await db.query("select set_config('request.jwt.claim.sub',$1,true)",[owner]);
 await db.exec('set local role authenticated');
 await assert.rejects(db.query('delete from auth.users where id=$1',[other]),e=>e.code==='42501');
});
await scenario(async()=>{
 await db.query("select set_config('request.jwt.claim.sub',$1,true)",[owner]);
 await db.exec('set local role authenticated');
 await assert.rejects(db.query('select private.prepare_account_deletion()'),e=>e.code==='42501');
});
await scenario(async()=>{
 await db.query('delete from auth.users where id=$1',[owner]);
 await db.query("select set_config('request.jwt.claim.sub',$1,true)",[owner]);
 await db.exec('set local role authenticated');
 await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('avatars',$1)",[`${owner}/avatar.png`]),e=>e.code==='42501');
});
await db.close();
console.log(`${passed} account deletion, ownership, cascade and stale-token scenarios passed.`);

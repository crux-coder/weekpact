import { notificationTestSchema } from './notification_test_schema.mjs';
import { storageTestSchema } from './storage_test_schema.mjs';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, member, other, outsider, crew, goal] = [1,2,3,4,10,20].map(id);
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth; create schema extensions;
create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
create function extensions.digest(value text, algorithm text) returns bytea language sql as $$ select sha256(convert_to(value, 'UTF8')) $$;
`);
await db.exec(storageTestSchema);
await db.exec(notificationTestSchema);
const directory = new URL('../supabase/migrations/', import.meta.url);
for (const file of (await readdir(directory)).filter(f => f.endsWith('.sql')).sort()) {
  await db.exec((await readFile(new URL(file, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', ''));
}
if (process.env.MEMBERSHIP_SQL) await db.exec(await readFile(process.env.MEMBERSHIP_SQL, 'utf8'));
for (const [i, user] of [owner, member, other, outsider].entries()) await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())', [user,`user${i}@example.com`]);
await db.query("insert into crews(id,name,owner_id) values($1,'Early Birds',$2)",[crew,owner]);
for (const [user,email] of [[member,'user1@example.com'],[other,'user2@example.com']]) await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')",[crew,user,email]);
await db.query("insert into crew_goals(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','weekly',3,$3)",[goal,crew,owner]);
await db.query('insert into goal_check_ins(goal_id,user_id,completed_on) values($1,$2,current_date)',[goal,member]);
await db.query("insert into crew_invites(crew_id,email,token_hash,invited_by) values($1,'user1@example.com',repeat('a',64),$2)",[crew,owner]);
let passed=0;
async function asUser(user, run, role='authenticated') {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user]);
    await db.exec(`set local role ${role}`);
    await run(); passed++;
  } finally { await db.exec('rollback'); }
}
const leave = successor => db.query('select public.leave_crew($1,$2)',[crew,successor??null]);
const remove = target => db.query('select public.remove_crew_member($1,$2)',[crew,target]);
await asUser(member, async()=> {
  await leave();
  assert.equal((await db.query('select * from crews')).rows.length,0);
  await db.exec('reset role');
  assert.equal((await db.query('select * from crew_members where user_id=$1',[member])).rows.length,0);
  assert.equal((await db.query('select * from goal_check_ins where user_id=$1',[member])).rows.length,1);
  assert.equal((await db.query('select * from crew_invites')).rows.length,0);
  // The former member is free to create a crew.
  await db.exec('set local role authenticated');
  await db.query("insert into crews(name,owner_id) values('New crew',$1)",[member]);
});
await asUser(owner, async()=> {
  await remove(member);
  assert.equal((await db.query('select * from crew_members')).rows.length,2);
  assert.equal((await db.query('select * from crew_invites')).rows.length,0);
});
await asUser(member, async()=>assert.rejects(remove(other),/Only the owner/));
await asUser(outsider, async()=>assert.rejects(remove(member),/Only the owner/));
await asUser(outsider, async()=>assert.rejects(leave(),/no longer in the crew/));
await asUser(owner, async()=>assert.rejects(leave(),/Choose another member/));
await asUser(owner, async()=>assert.rejects(leave(outsider),/must belong/));
await asUser(member, async()=>assert.rejects(leave(other),/Only a departing owner/));
await asUser('', async()=>assert.rejects(leave(),/signed in/));
await asUser('', async()=>assert.rejects(leave(), e=>e.code==='42501'),'anon');
await asUser(owner, async()=> {
  await leave(member);
  await db.exec('reset role');
  assert.equal((await db.query('select owner_id from crews')).rows[0].owner_id, member);
  assert.equal((await db.query("select user_id from crew_members where role='owner'")).rows[0].user_id, member);
  assert.equal((await db.query('select * from crew_members where user_id=$1',[owner])).rows.length,0);
  await db.query("select set_config('request.jwt.claim.sub',$1,true)",[member]);
  await db.exec('set local role authenticated');
  await remove(other);
});
await asUser(member, async()=>assert.rejects(db.query('delete from crew_members where user_id=$1',[other]), e=>e.code==='42501'));
await db.close();
console.log(`${passed} membership permission and state checks passed.`);

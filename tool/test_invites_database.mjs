// PGLITE_MODULE may point to a local @electric-sql/pglite installation.
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, recipient, outsider, unverified, otherOwner] = [1,2,3,4,5].map(id);
const crew = id(11), otherCrew = id(12), invite = id(21), expired = id(22), otherInvite = id(23);
const rawToken = 'a'.repeat(64);
await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth; create schema extensions;
  create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to authenticated;
  grant execute on function auth.uid() to authenticated;
  create function extensions.digest(value text, algorithm text) returns bytea language sql as $$ select sha256(convert_to(value, 'UTF8')) $$;
`);
const directory = new URL('../supabase/migrations/', import.meta.url);
for (const file of (await readdir(directory)).filter(f => f.endsWith('.sql')).sort()) {
  await db.exec((await readFile(new URL(file, directory), 'utf8')).replace('create extension if not exists pgcrypto with schema extensions;', ''));
}
for (const [user, email, confirmed] of [[owner,'owner@example.com',true],[recipient,'Member@Example.com',true],[outsider,'outsider@example.com',true],[unverified,'unverified@example.com',false],[otherOwner,'other@example.com',true]]) {
  await db.query('insert into auth.users values($1,$2,case when $3 then now() else null end)', [user,email,confirmed]);
}
await db.query("insert into crews(id,name,owner_id) values($1,'Early Birds',$2),($3,'Other Crew',$4)", [crew,owner,otherCrew,otherOwner]);
await db.query("insert into crew_goals(crew_id,title,frequency,days_per_week,created_by) values($1,'Morning walk','weekly',3,$2)", [crew,owner]);
await db.query("insert into crew_invites(id,crew_id,email,token_hash,invited_by) values($1,$2,'member@example.com',encode(extensions.digest($3,'sha256'),'hex'),$4),($5,$6,'outsider@example.com',repeat('b',64),$7)", [invite,crew,rawToken,owner,otherInvite,otherCrew,otherOwner]);
await db.query("insert into crew_invites(id,crew_id,email,token_hash,invited_by,created_at,expires_at) values($1,$2,'member@example.com',repeat('c',64),$3,now()-interval '8 days',now()-interval '1 day')", [expired,otherCrew,otherOwner]);
const inbox = async () => (await db.query('select public.received_crew_invites() as data')).rows[0].data;
const respond = (invitation, accept) => db.query('select public.respond_to_crew_invite($1,$2)', [invitation,accept]);
let passed = 0;
async function asUser(user, fn, role='authenticated') {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
    await db.exec(`set local role ${role}`);
    await fn();
    passed++;
  } finally { await db.exec('rollback'); }
}
await asUser(recipient, async () => {
  const rows = await inbox();
  assert.equal(rows.length,1);
  assert.equal(rows[0].id,invite);
  assert.equal(rows[0].name,'Early Birds');
  assert.equal(rows[0].members[0].email,'owner@example.com');
  assert.equal(rows[0].goals[0].title,'Morning walk');
  assert.equal(rows[0].goals[0].days_per_week,3);
  assert.ok(!JSON.stringify(rows).includes('token_hash'));
  // Preview access does not grant normal member data access.
  for (const table of ['crews','crew_members','crew_goals','crew_invites']) {
    assert.equal((await db.query(`select * from ${table}`)).rows.length,0);
  }
});
await asUser(outsider, async () => assert.equal((await inbox())[0].id, otherInvite));
await asUser(owner, async () => assert.equal((await inbox()).length,0));
await asUser(unverified, async () => assert.rejects(inbox(), /Confirm your email/));
await asUser('', async () => assert.rejects(inbox(), /signed in/));
await asUser('', async () => assert.rejects(inbox(), e => e.code === '42501'), 'anon');
for (const accept of [true,false]) {
  await asUser(outsider, async () => assert.rejects(respond(invite,accept), /no longer available/));
  await asUser(unverified, async () => assert.rejects(respond(invite,accept), /Confirm your email/));
  await asUser(recipient, async () => assert.rejects(respond(expired,accept), /no longer available/));
  await asUser(recipient, async () => assert.rejects(respond(id(999),accept), /no longer available/));
}
await asUser(recipient, async () => {
  await respond(invite,true);
  assert.equal((await inbox()).length,0);
  const membership = (await db.query('select * from crew_members where user_id=$1',[recipient])).rows[0];
  assert.equal(membership.crew_id,crew);
  assert.equal(membership.role,'member');
  assert.equal(membership.email,'member@example.com');
});
await asUser(recipient, async () => {
  await respond(invite,true);
  await assert.rejects(respond(invite,true), /no longer available/);
});
await asUser(recipient, async () => {
  await respond(invite,false);
  assert.equal((await inbox()).length,0);
  assert.equal((await db.query('select * from crew_members where user_id=$1',[recipient])).rows.length,0);
  await assert.rejects(db.query('select accept_crew_invite($1)',[rawToken]), /invalid or has already been used/);
});
await asUser(recipient, async () => {
  await db.query('select accept_crew_invite($1)',[rawToken]);
  assert.equal((await inbox()).length,0);
});
// Existing members cannot accept another crew; declining still works.
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')",[otherCrew,recipient]);
await asUser(recipient, async () => assert.rejects(respond(invite,true), /already belong to a crew/));
await asUser(recipient, async () => { await respond(invite,false); assert.equal((await inbox()).length,0); });
// Owner revocation takes effect immediately, including already-open previews.
await db.query('delete from crew_invites where id=$1',[invite]);
await asUser(recipient, async () => assert.equal((await inbox()).length,0));
await asUser(recipient, async () => assert.rejects(respond(invite,true), /no longer available/));
console.log(`${passed} invite inbox, preview, response and access-control scenarios passed.`);
await db.close();

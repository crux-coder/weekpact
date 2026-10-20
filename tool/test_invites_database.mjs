// Legacy seven-day share links and the removal of address-locked email invites.
// Crew invite codes have their own script, test_invite_codes_database.mjs.
// PGLITE_MODULE may point to a local @electric-sql/pglite installation.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';
const db = await createTestDatabase();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, recipient, outsider, unverified] = [1,2,3,4].map(id);
const crew = id(11), otherCrew = id(12);
for (const [user, email, confirmed] of [[owner,'owner@example.com',true],[recipient,'Member@Example.com',true],[outsider,'outsider@example.com',true],[unverified,'unverified@example.com',false]]) {
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,case when $3 then now() else null end)', [user,email,confirmed]);
}
await db.query("insert into crews(id,name,owner_id) values($1,'Early Birds',$2),($3,'Other Crew',$4)", [crew,owner,otherCrew,outsider]);
await db.query("update public.users set first_name='Ada',last_name='Lovelace' where id=$1", [owner]);
await db.query("insert into crew_pacts(crew_id,title,frequency,days_per_week,created_by) values($1,'Morning walk','weekly',3,$2)", [crew,owner]);
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
// Email invites and their inbox are gone from the API and the schema.
const gone = (await db.query(`select
  to_regclass('public.crew_invites')::text invites,
  to_regprocedure('public.received_crew_invites()')::text inbox,
  to_regprocedure('public.respond_to_crew_invite(uuid,boolean)')::text respond,
  to_regprocedure('private.accept_email_crew_invite(text)')::text email_accept,
  to_regprocedure('private.accept_any_crew_invite(text)')::text any_accept`)).rows[0];
assert.deepEqual(gone, {invites:null, inbox:null, respond:null, email_accept:null, any_accept:null});
// Share links made before codes keep working until they expire.
const shareToken = 'd'.repeat(64), expiredShare = 'e'.repeat(64);
for (const [token, life] of [[shareToken, "interval '7 days'"], [expiredShare, "-interval '1 second'"]]) {
  await db.query(`insert into private.crew_share_links(crew_id,token_hash,created_by,expires_at) values($1,encode(extensions.digest($2,'sha256'),'hex'),$3,now()+${life})`, [crew, token, owner]);
}
const preview = token => db.query('select public.preview_crew_invite($1) as data', [token]).then(r => r.rows[0].data);
const accept = token => db.query('select public.accept_crew_invite($1) as crew', [token]).then(r => r.rows[0].crew);
for (const role of ['authenticated', 'anon']) {
  await asUser(role === 'anon' ? '' : outsider, async () => {
    const shared = await preview(shareToken);
    assert.equal(shared.crew_name, 'Early Birds');
    assert.equal(shared.owner_name, 'Ada Lovelace');
    assert.equal(shared.inviter_name, 'Ada Lovelace');
    assert.deepEqual(shared.pacts, [{title:'Morning walk', icon_key:'target', days_per_week:3}]);
    assert.equal(shared.is_member, false);
    for (const unusable of [expiredShare, '0'.repeat(64), 'D'.repeat(64), 'not-a-token', '', null]) {
      assert.equal(await preview(unusable), null, `${unusable} previews nothing`);
    }
  }, role);
}
await asUser(owner, async () => assert.equal((await preview(shareToken)).is_member, true));
await asUser(recipient, async () => {
  assert.equal(await accept(shareToken), crew);
  assert.equal(await accept(shareToken), crew, 'accepting twice is harmless');
  const membership = (await db.query('select * from crew_members where user_id=$1', [recipient])).rows;
  assert.equal(membership.length, 1);
  assert.equal(membership[0].role, 'member');
  assert.equal(membership[0].email, 'member@example.com');
});
await asUser(recipient, async () => assert.rejects(accept(expiredShare), /expired/));
await asUser(recipient, async () => assert.rejects(accept('0'.repeat(64)), /no longer valid/));
await asUser(unverified, async () => assert.rejects(accept(shareToken), /Confirm your email/));
await asUser('', async () => assert.rejects(accept(shareToken), /Sign in/));
await asUser('', async () => assert.rejects(accept(shareToken), e => e.code === '42501'), 'anon');
// One crew without Pro: the outsider owns one already, so joining a second through a link is refused with WPPRO.
await asUser(outsider, async () => assert.rejects(accept(shareToken), e => e.code === 'WPPRO'));
await db.query("insert into private.subscriptions(user_id,entitlement,active,expires_at) values($1,'weekpact_pro',true,now()+interval '1 year')", [outsider]);
await asUser(outsider, async () => assert.equal(await accept(shareToken), crew));
console.log(`${passed} legacy share link, email-invite removal and access-control scenarios passed.`);
await db.close();

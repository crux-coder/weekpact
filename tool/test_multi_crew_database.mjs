import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `20000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, member, outsider, first, second, third] = [1, 2, 3, 11, 12, 13].map(id);
for (const user of [owner, member, outsider]) {
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())', [user, `${user}@example.com`]);
}
async function asUser(user, fn) {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
    await db.exec('set local role authenticated');
    const result = await fn();
    await db.exec('commit');
    return result;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const memberships = async user => (await db.query('select crew_id,role from crew_members where user_id=$1 order by crew_id', [user])).rows;
await asUser(owner, async () => {
  for (const [crew, name] of [[first, 'Climbers'], [second, 'Readers']]) {
    await db.query('insert into crews(id,name,owner_id) values($1,$2,$3) returning id', [crew, name, owner]);
  }
  assert.deepEqual(await memberships(owner), [{crew_id:first,role:'owner'}, {crew_id:second,role:'owner'}]);
});
await asUser(outsider, () => db.query("insert into crews(id,name,owner_id) values($1,'Private crew',$2)", [third, outsider]));
const tokens = await asUser(owner, async () => {
  const tokens = [];
  for (const crew of [first,second]) tokens.push((await db.query("select manage_crew_share_link($1,'create') as link", [crew])).rows[0].link.token);
  return tokens;
});
await asUser(member, async () => {
  for (const token of tokens) await db.query('select accept_crew_invite($1)', [token]);
  // Reusing a valid share link leaves the existing membership untouched.
  await db.query('select accept_crew_invite($1)', [tokens[0]]);
  assert.deepEqual(await memberships(member), [{crew_id:first,role:'member'}, {crew_id:second,role:'member'}]);
  assert.deepEqual((await db.query('select id from crews order by id')).rows.map(r=>r.id), [first,second]);
  assert.equal((await db.query('select * from crew_members where crew_id=$1',[third])).rows.length,0);
  // Members can also create another crew after joining someone else's.
  await db.query("insert into crews(id,name,owner_id) values($1,'My own crew',$2)", [id(14),member]);
  assert.equal((await memberships(member)).length,3);
});
await assert.rejects(asUser(member, () => db.query("select manage_crew_share_link($1,'create')", [second])), /Crew owner required/);
await asUser(owner, async () => {
  await db.query('select accept_crew_invite($1)', [tokens[0]]);
  assert.equal((await memberships(owner))[0].role,'owner');
});
await asUser(member, () => db.query('select leave_crew($1,null)', [first]));
await asUser(member, async () => {
  assert.deepEqual((await memberships(member)).map(r=>r.crew_id), [second,id(14)]);
  assert.equal((await db.query('select * from crews where id=$1',[first])).rows.length,0);
});
await asUser(owner, () => db.query('select remove_crew_member($1,$2)', [second,member]));
await asUser(member, async () => assert.deepEqual((await memberships(member)).map(r=>r.crew_id), [id(14)]));
console.log('Multi-crew creation, sharing, duplicate acceptance, ownership, RLS, leaving and removal passed.');
await db.close();

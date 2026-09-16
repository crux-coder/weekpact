import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [viewer, mate, outsider] = [1, 2, 3].map(id);
const [shared, other, foreign] = [11, 12, 13].map(id);
for (const [user, name] of [[viewer, 'Ada Lovelace'], [mate, 'Mirnes Halilovic'], [outsider, 'Nobody']]) {
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())', [user, `${user}@example.com`]);
  await db.query('update auth.users set raw_user_meta_data=$1 where id=$2', [
    { first_name: name.split(' ')[0], last_name: name.split(' ')[1], avatar_path: `${user}/avatar.png` },
    user,
  ]);
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
const feed = (user, cursor = null) => asUser(user, async () => (await db.query(
  'select check_in_feed($1,$2,$3,$4,$5) as entries',
  cursor
    ? [cursor.created_at, cursor.pact_id, cursor.user_id, cursor.completed_on, 2]
    : [null, null, null, null, 2],
)).rows[0].entries);

// Two crews the viewer belongs to, and one they do not.
await asUser(viewer, async () => {
  for (const [crew, name] of [[shared, 'Climbers'], [other, 'Readers']]) {
    await db.query('insert into crews(id,name,owner_id) values($1,$2,$3)', [crew, name, viewer]);
  }
});
await asUser(outsider, () => db.query("insert into crews(id,name,owner_id) values($1,'Private crew',$2)", [foreign, outsider]));
await db.query('insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,$4)', [shared, mate, `${mate}@example.com`, 'member']);

const pacts = {};
for (const [crew, key, title, icon] of [
  [shared, 'climb', 'Climb twice', 'strength'],
  [other, 'read', 'Read 20 pages', 'book'],
  [foreign, 'secret', 'Private pact', 'target'],
]) {
  pacts[key] = id(20 + Object.keys(pacts).length);
  await db.query(
    "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by) values($1,$2,$3,'weekly',3,$4,$5)",
    [pacts[key], crew, title, icon, crew === foreign ? outsider : viewer],
  );
}
// Deliberately out of order, so the RPC's ordering is what sorts the feed.
const posted = [
  [pacts.read, viewer, '2026-09-07', '2026-09-07T08:00:00Z', null],
  [pacts.climb, mate, '2026-09-09', '2026-09-09T12:00:00Z', `${mate}/${shared}/${pacts.climb}/2026-09-09/${'a'.repeat(32)}.png`],
  [pacts.climb, viewer, '2026-09-08', '2026-09-08T18:00:00Z', null],
  [pacts.secret, outsider, '2026-09-09', '2026-09-09T13:00:00Z', null],
];
for (const [pact, user, day, at, photo] of posted) {
  await db.query(
    'insert into pact_check_ins(pact_id,user_id,completed_on,created_at,photo_path) values($1,$2,$3,$4,$5)',
    [pact, user, day, at, photo],
  );
}

const first = await feed(viewer);
assert.equal(first.length, 2, 'honors the page limit');
assert.deepEqual(first.map(e => e.pact_title), ['Climb twice', 'Climb twice']);
assert.deepEqual(first.map(e => e.crew_name), ['Climbers', 'Climbers']);
assert.equal(first[0].display_name, 'Mirnes Halilovic', 'resolves the author name');
assert.equal(first[0].avatar_path, `${mate}/avatar.png`);
assert.equal(first[0].icon_key, 'strength');
assert.ok(first[0].photo_path.endsWith('.png'));
assert.equal(first[1].photo_path, null, 'photo-free check-ins still appear');

const second = await feed(viewer, first[1]);
assert.deepEqual(second.map(e => e.pact_title), ['Read 20 pages'], 'the cursor continues without repeats');
assert.equal((await feed(viewer, second[0])).length, 0, 'the feed ends');

// A crew the viewer does not belong to never appears, in any page.
for (const page of [first, second]) {
  assert.ok(page.every(e => e.pact_title !== 'Private pact'));
}
assert.deepEqual((await feed(mate)).map(e => e.pact_title), ['Climb twice', 'Climb twice'],
  'members see only the crews they joined');
assert.deepEqual((await feed(outsider)).map(e => e.pact_title), ['Private pact']);

// Leaving a crew withdraws its posts from the feed.
await db.query('delete from crew_members where crew_id=$1 and user_id=$2', [shared, mate]);
assert.deepEqual(await feed(mate), []);

await assert.rejects(
  asUser(viewer, () => db.query('select check_in_feed($1,$2,null,null,2)', ['2026-09-09T12:00:00Z', pacts.climb])),
  /Invalid feed cursor/,
  'a partial cursor is refused rather than silently ignored',
);
await assert.rejects(
  db.query('select check_in_feed(null,null,null,null,2)'),
  /Authentication required|permission denied/,
  'unauthenticated callers get nothing',
);

console.log('Check-in feed pagination, cross-crew scope, membership limits and cursor validation passed.');
await db.close();

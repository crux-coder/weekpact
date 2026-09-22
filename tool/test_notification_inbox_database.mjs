process.on('uncaughtException', error => { console.error(error.message, error.where ?? ''); process.exit(1); });
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `60000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, mate, quiet, outsider] = [1, 2, 3, 4].map(id);
const people = [owner, mate, quiet, outsider];
const [crew, pact] = [10, 20].map(id);
const day = '2026-09-09';

for (const [index, user] of people.entries()) {
  await db.query(
    'insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),$3)',
    [user, `${user}@example.com`, JSON.stringify({
      first_name: { [owner]: 'Ada', [mate]: 'Jasmin', [quiet]: 'Sam', [outsider]: 'Rex' }[user],
      last_name: 'Vega',
      avatar_path: `${user}/avatar.png`,
    })],
  );
  await db.query('insert into auth.sessions values($1,$2)', [id(100 + index), user]);
}
await db.query("insert into public.crews(id,name,owner_id,timezone) values($1,'Climbers',$2,'Europe/Sarajevo')", [crew, owner]);
for (const user of [mate, quiet]) {
  await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')", [crew, user, `${user}@example.com`]);
}
await db.query(
  "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by) values($1,$2,'Climb twice','weekly',3,'target',$3)",
  [pact, crew, owner],
);

async function asUser(user, fn) {
  await db.query(
    "select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.session_id',$2,false)",
    [user, user ? id(100 + people.indexOf(user)) : ''],
  );
  await db.exec(`set role ${user ? 'authenticated' : 'anon'}`);
  try { return await fn(); } finally { await db.exec('reset role'); }
}
const inbox = (user, cursor = [null, null], limit = 20) => asUser(user, async () => (await db.query(
  'select notification_inbox($1,$2,$3) as page', [...cursor, limit],
)).rows[0].page);
const unread = user => asUser(user, async () =>
  (await db.query('select unread_notification_count() as total')).rows[0].total);
const markRead = (user, upTo = null) => asUser(user, async () =>
  (await db.query('select mark_notifications_read($1) as cleared', [upTo])).rows[0].cleared);

// Nobody has anything to read yet, and nobody can read past their own account.
assert.deepEqual(await inbox(mate), []);
assert.equal(await unread(mate), 0);
await assert.rejects(inbox(''), /Authentication required|permission denied/, 'anonymous callers get nothing');
await assert.rejects(
  asUser(mate, () => db.query('select * from private.notification_inbox')),
  /permission denied/, 'the table is not readable around the RPC',
);
await assert.rejects(inbox(mate, [new Date().toISOString(), null]), /Invalid notification cursor/);

// A check-in reaches the crew, whether or not anyone registered a device.
await asUser(mate, () => db.query("select register_push_device($1,'ios')", ['inbox_device_token_mate']));
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on,photo_path) values($1,$2,$3,$4)',
  [pact, owner, day, 'photo.png']);
let page = await inbox(mate);
assert.equal(page.length, 1, 'a crew check-in lands in every other member\'s list');
assert.deepEqual(
  { type: page[0].type, crew_name: page[0].crew_name, display_name: page[0].display_name, pact_title: page[0].pact_title, icon_key: page[0].icon_key, read: page[0].read },
  { type: 'pact_completed', crew_name: 'Climbers', display_name: 'Ada Vega', pact_title: 'Climb twice', icon_key: 'target', read: false },
);
assert.equal(page[0].avatar_path, `${owner}/avatar.png`, 'the actor\'s avatar comes with it');
assert.equal((await inbox(quiet)).length, 1, 'a member with no device reads the same list');
assert.equal((await inbox(owner)).length, 0, 'the person who checked in is not told about themselves');
assert.equal(await unread(quiet), 1);

// A clap is addressed to one person.
await asUser(mate, () => db.query('select set_check_in_clap($1,$2,$3,true)', [pact, owner, day]));
assert.equal((await inbox(owner)).length, 1, 'the author hears about the clap');
assert.equal((await inbox(owner))[0].type, 'check_in_clapped');
assert.equal((await inbox(quiet)).length, 1, 'nobody else does');

// Reading clears only as far as the reader actually saw.
const seen = (await inbox(mate))[0].created_at;
assert.equal(await markRead(mate, seen), 1);
assert.equal(await unread(mate), 0);
assert.equal((await inbox(mate))[0].read, true);
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, quiet, '2026-09-10']);
assert.equal(await unread(mate), 1, 'what arrived after that point is still unread');
assert.equal(await markRead(mate, seen), 0, 'and is not cleared by an older mark');
assert.equal(await markRead(mate), 1, 'clearing everything takes it');
assert.equal(await unread(mate), 0);

// Paging is keyed on the whole sort key, so a page never repeats or skips.
for (const [index, date] of ['2026-09-11', '2026-09-12', '2026-09-13'].entries()) {
  await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, index % 2 === 0 ? owner : quiet, date]);
}
const all = await inbox(mate, [null, null], 50);
const firstPage = await inbox(mate, [null, null], 2);
const secondPage = await inbox(mate, [firstPage.at(-1).created_at, firstPage.at(-1).event_id], 2);
assert.equal(firstPage.length, 2);
assert.deepEqual(
  [...firstPage, ...secondPage].map(entry => entry.event_id),
  all.slice(0, 4).map(entry => entry.event_id),
  'the pages line up with the whole list',
);
assert.deepEqual(all.map(e => e.created_at), [...all.map(e => e.created_at)].sort().reverse(), 'newest first');

// Deleting what a notification was about takes the notification with it.
const clapped = (await inbox(owner))[0];
await db.query('delete from pact_check_ins where pact_id=$1 and user_id=$2 and completed_on=$3', [pact, owner, day]);
assert.equal((await inbox(owner)).some(entry => entry.event_id === clapped.event_id), true,
  'a clap already announced survives its check-in');
await db.query('delete from crews where id=$1', [crew]);
assert.deepEqual(await inbox(mate), [], 'deleting the crew empties what it queued');
assert.equal(await unread(mate), 0);

console.log('Notification inbox passed: fanout without devices, per-person read state, cursors, and cascade.');
await db.close();

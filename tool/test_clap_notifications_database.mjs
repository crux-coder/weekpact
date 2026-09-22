process.on('uncaughtException', error => { console.error(error.message, error.where ?? ''); process.exit(1); });
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `50000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [author, mate, other, quiet] = [1, 2, 3, 4].map(id);
const people = [author, mate, other, quiet];
const [crew, pact] = [10, 20].map(id);
const day = '2026-09-09';

for (const [index, user] of people.entries()) {
  await db.query(
    `insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
     values($1,$2,now(),$3)`,
    [user, `${user}@example.com`, JSON.stringify({ first_name: { [author]: 'Ada', [mate]: 'Jasmin', [other]: 'Nina', [quiet]: 'Sam' }[user] })],
  );
  await db.query('insert into auth.sessions values($1,$2)', [id(100 + index), user]);
}
await db.query("insert into public.crews(id,name,owner_id,timezone) values($1,'Climbers',$2,'Europe/Sarajevo')", [crew, author]);
for (const user of [mate, other, quiet]) {
  await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')", [crew, user, `${user}@example.com`]);
}
await db.query(
  "insert into crew_pacts(id,crew_id,title,frequency,days_per_week,icon_key,created_by) values($1,$2,'Climb twice','weekly',3,'target',$3)",
  [pact, crew, author],
);
for (const user of [author, quiet]) {
  await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)', [pact, user, day]);
}

async function asUser(user, fn) {
  await db.query(
    "select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.session_id',$2,false)",
    [user, id(100 + people.indexOf(user))],
  );
  await db.exec('set role authenticated');
  try { return await fn(); } finally { await db.exec('reset role'); }
}
const clap = (user, clapped, target = [pact, author, day]) => asUser(user, async () => (await db.query(
  'select set_check_in_clap($1,$2,$3,$4) as result', [...target, clapped],
)).rows[0].result);
const events = async () => (await db.query(
  `select e.id, e.type, e.actor_id, e.payload, count(d.id)::int as deliveries
   from private.notification_events e
   left join private.notification_deliveries d on d.event_id = e.id
   where e.type = 'check_in_clapped'
   group by e.id order by e.created_at`,
)).rows;

// The author is reachable on two devices; the second author registers none.
for (const [user, platform, suffix] of [[author, 'ios', 'a'], [author, 'android', 'b'], [mate, 'ios', 'c'], [other, 'ios', 'd']]) {
  await asUser(user, () => db.query("select register_push_device($1,$2)", [`clap_device_token_${user}_${suffix}`, platform]));
}

// A first clap reaches every device the author has, and nobody else.
await clap(mate, true);
let queued = await events();
assert.equal(queued.length, 1, 'the first clap queues one event');
assert.equal(queued[0].deliveries, 2, 'delivered to each of the author\'s devices');
assert.equal(queued[0].actor_id, mate);
assert.deepEqual(
  { ...queued[0].payload, completed_on: queued[0].payload.completed_on },
  { recipient_id: author, pact_id: pact, pact_title: 'Climb twice', completed_on: day, actor_name: 'Jasmin', clap_count: 1 },
);
assert.equal(
  (await db.query('select count(*)::int as total from private.notification_deliveries where recipient_id <> $1', [author])).rows[0].total,
  0, 'only the person who was clapped hears about it',
);

// Clapping again changes nothing, so a double tap cannot repeat a push.
await clap(mate, true);
assert.equal((await events()).length, 1, 'a clap that was already there notifies nobody');

// A second clapper inside the window folds into the push still waiting to go out.
await clap(other, true);
queued = await events();
assert.equal(queued.length, 1, 'the second clapper does not queue a second push');
assert.equal(queued[0].payload.clap_count, 2, 'it is folded into the one still queued');
assert.equal(queued[0].payload.actor_name, 'Jasmin', 'named after the clap that opened the window');

// Applauding yourself is not news, and never counts towards someone else's tally.
await clap(author, true);
queued = await events();
assert.equal(queued.length, 1);
assert.equal(queued[0].payload.clap_count, 2, 'the author\'s own clap is not announced to them');

// Once the push has left the outbox, later claps wait for the next window.
await db.query("update private.notification_deliveries set status='sent',sent_at=now() where event_id=$1", [queued[0].id]);
await clap(mate, false);
await clap(mate, true);
queued = await events();
assert.equal(queued.length, 1, 'a clap inside a spent window is silent');
assert.equal(queued[0].payload.clap_count, 2, 'and cannot rewrite a push already sent');

// An hour later the window reopens, counting only what the author has not heard.
await db.query("update private.check_in_clap_notices set notified_at = notified_at - interval '1 hour'");
await db.query("update public.check_in_claps set created_at = created_at - interval '1 hour' where actor_id <> $1", [mate]);
await clap(other, false);
await clap(other, true);
queued = await events();
assert.equal(queued.length, 2, 'the next window queues its own push');
assert.equal(queued[1].payload.clap_count, 2, 'carrying the claps that arrived while it was closed');
assert.equal(queued[1].payload.actor_name, 'Nina');

// An author with no registered device is still notified: nothing is pushed, but
// the clap is written down where they can read it back.
const before = (await events()).length;
await clap(mate, true, [pact, quiet, day]);
queued = await events();
assert.equal(queued.length, before + 1, 'a clap on an unreachable author is still an event');
assert.equal(queued[before].deliveries, 0, 'with nothing to push it to');
assert.equal(queued[before].payload.recipient_id, quiet);
assert.equal(
  (await db.query('select count(*)::int as total from private.notification_inbox where event_id=$1 and recipient_id=$2',
    [queued[before].id, quiet])).rows[0].total,
  1, 'and a line in their list either way',
);
assert.equal(
  (await db.query('select count(*)::int as total from private.check_in_clap_notices where check_in_user_id=$1', [quiet])).rows[0].total,
  1, 'the window governs the list as well as the push',
);

// Folding works the same with no device to push to, so the one line in the
// list counts everyone rather than only whoever clapped first.
await clap(other, true, [pact, quiet, day]);
assert.equal((await events()).length, before + 1, 'a second clap inside the window adds no second line');
assert.equal((await events())[before].payload.clap_count, 2, 'it is folded into the one already there');

// A queued push is only worth sending while a clap it announces survives.
const [firstEvent] = await events();
await db.query("update private.notification_deliveries set status='pending' where event_id=$1", [firstEvent.id]);
await clap(mate, false);
await clap(other, false);
await clap(author, false);
await db.query('select claim_notification_deliveries(50)');
assert.equal(
  (await db.query('select status from private.notification_deliveries where event_id=$1', [firstEvent.id])).rows.every(row => row.status === 'cancelled'),
  true, 'taking every clap back before delivery cancels the push',
);

// Deleting the check-in takes its claps, its window, and its queued push.
const orphaned = (await events()).find(event => event.payload.recipient_id === author && event.payload.clap_count === 2 && event.actor_id === other).id;
await db.query('delete from pact_check_ins where pact_id=$1 and user_id=$2 and completed_on=$3', [pact, author, day]);
assert.equal(
  (await db.query('select count(*)::int as total from private.check_in_clap_notices where check_in_user_id=$1', [author])).rows[0].total,
  0, 'the window is removed with the check-in',
);
await db.query('select claim_notification_deliveries(50)');
assert.equal(
  (await db.query("select count(*)::int as total from private.notification_deliveries where event_id=$1 and status in ('pending','sending')", [orphaned])).rows[0].total,
  0, 'and nothing queued for it is still waiting to send',
);

console.log('Clap notifications passed: single recipient, window throttling, coalescing, self-claps, unreachable authors, and cancellation.');
await db.close();

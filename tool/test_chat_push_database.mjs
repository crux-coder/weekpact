process.on('uncaughtException', error => { console.error(error.message, error.where ?? ''); process.exit(1); });
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const id = n => `70000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, mate, quiet] = [1, 2, 3].map(id);
const people = [owner, mate, quiet];
const crew = id(10);

for (const [index, user] of people.entries()) {
  await db.query(
    'insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),$3)',
    [user, `${user}@example.com`, JSON.stringify({ first_name: { [owner]: 'Ada', [mate]: 'Jasmin', [quiet]: 'Sam' }[user] })],
  );
  await db.query('insert into auth.sessions values($1,$2)', [id(100 + index), user]);
}
await db.query("insert into public.crews(id,name,owner_id) values($1,'Climbers',$2)", [crew, owner]);
for (const user of [mate, quiet]) {
  await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')", [crew, user, `${user}@example.com`]);
}

async function asUser(user, fn) {
  await db.query(
    "select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.session_id',$2,false)",
    [user, id(100 + people.indexOf(user))],
  );
  await db.exec('set role authenticated');
  try { return await fn(); } finally { await db.exec('reset role'); }
}
// Sam never turned notifications on.
for (const user of [owner, mate]) {
  await asUser(user, () => db.query("select register_push_device($1,'ios')", [`chat_device_token_${user}`]));
}

let sent = 0;
const send = async (sender, body = 'Running late, start without me') => {
  const message = id(1000 + ++sent);
  await asUser(sender, () => db.query(
    'insert into chat_messages(id,crew_id,body) values($1,$2,$3)',
    [message, crew, body]));
  return message;
};
const deliveries = async () => (await db.query(`
  select d.recipient_id, d.status, d.available_at > now() as waiting, e.payload
  from private.notification_deliveries d join private.notification_events e on e.id = d.event_id
  where e.type = 'chat_message' order by e.created_at, d.recipient_id`)).rows;
const claim = async () => {
  await db.query("update private.notification_deliveries set available_at = now() where status = 'pending'");
  return (await db.query('select * from claim_notification_deliveries(50)')).rows
    .filter(job => job.event_type === 'chat_message');
};
const finish = async jobs => {
  for (const job of jobs) {
    await db.query("select finish_notification_delivery($1,$2,'sent',null)", [job.delivery_id, job.lease]);
  }
};

// A message reaches every other member who can be pushed to, with who wrote,
// where, and what.
const first = await send(owner);
let rows = await deliveries();
assert.equal(rows.length, 1, 'only Jasmin has a device; Ada wrote it');
assert.equal(rows[0].recipient_id, mate);
assert.equal(rows[0].waiting, true, 'held back long enough for an open chat to read it');
assert.deepEqual(Object.keys(rows[0].payload).sort(), ['actor_name', 'crew_name', 'message_id', 'sent_at', 'text']);
assert.equal(rows[0].payload.actor_name, 'Ada');
assert.equal(rows[0].payload.crew_name, 'Climbers');
assert.equal(rows[0].payload.message_id, first);
assert.equal(rows[0].payload.text, 'Running late, start without me');

// Nothing lands in anyone's inbox.
assert.equal((await db.query('select count(*)::int as n from private.notification_inbox')).rows[0].n, 0);
for (const user of people) {
  assert.equal(await asUser(user, async () => (await db.query('select unread_notification_count() as n')).rows[0].n), 0);
}

// A burst inside the window adds nothing for the same recipient and crew...
await send(owner);
await send(owner);
assert.equal((await deliveries()).length, 1, 'one push per recipient per crew per window');

// ...but a reply is somebody else's first push.
await send(mate);
rows = await deliveries();
assert.equal(rows.length, 2);
assert.equal(rows[1].recipient_id, owner);
assert.equal(rows[1].payload.actor_name, 'Jasmin');

// Jasmin has the chat open: it marks what arrives read, so her push is dropped.
// Ada's is not, and goes out.
const firstAt = (await db.query('select created_at from chat_messages where id=$1', [first])).rows[0].created_at;
await asUser(mate, () => db.query('select mark_chat_read($1,$2)', [crew, firstAt]));
let jobs = await claim();
assert.equal(jobs.length, 1);
assert.equal(jobs[0].crew_id, crew);
assert.equal(jobs[0].payload.actor_name, 'Jasmin');
await finish(jobs);
rows = await deliveries();
assert.deepEqual(rows.map(r => [r.recipient_id, r.status]), [[mate, 'cancelled'], [owner, 'sent']]);

// A dropped push did not use up the window: once Jasmin puts the phone down,
// the next message still reaches her. Ada was just told, so she is not.
await send(owner);
await send(mate);
rows = await deliveries();
assert.equal(rows.length, 3);
assert.deepEqual([rows[2].recipient_id, rows[2].status], [mate, 'pending']);

// Unsending the message before the push goes out drops it.
const unsent = rows[2].payload.message_id;
await asUser(owner, () => db.query('select delete_chat_message($1)', [unsent]));
assert.equal((await claim()).length, 0);
assert.equal((await deliveries())[2].status, 'cancelled');
assert.equal((await deliveries())[2].payload.text, undefined, 'its words are gone from the queue');

// Once the window has passed, a new message is worth a push again. Only the
// start of a long one rides along.
await db.query("update private.notification_events set created_at = created_at - interval '4 minutes' where type = 'chat_message'");
await send(owner, 'a'.repeat(1500));
await send(mate);
rows = await deliveries();
assert.deepEqual(rows.slice(3).map(r => r.recipient_id), [mate, owner]);
assert.equal(rows[3].payload.text.length, 200);
jobs = await claim();
assert.equal(jobs.length, 2);

// The words are stored as text, so the read and send rules are what keep them
// inside the crew.
const outsider = id(4);
await db.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),'{}')", [outsider, 'outsider@example.com']);
await db.query('insert into auth.sessions values($1,$2)', [id(104), outsider]);
people.push(outsider);
assert.equal((await asUser(outsider, () => db.query('select * from chat_messages'))).rows.length, 0, 'an outsider reads nothing');
await assert.rejects(send(outsider), 'an outsider cannot post');
assert.ok((await asUser(mate, () => db.query('select * from chat_messages'))).rows.length > 0, 'a member reads the crew chat');
await assert.rejects(send(mate, '   '), 'a blank message is refused');
await assert.rejects(send(mate, 'a'.repeat(2001)), 'so is one over the limit');

console.log('Chat push passed: carries the text, push-only, throttled per crew, and dropped (with its text) when read or unsent.');

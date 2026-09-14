process.on('uncaughtException', error => { console.error(error.message, error.where ?? ''); process.exit(1); });
import assert from 'node:assert/strict';
import {createTestDatabase} from './database_test_schema.mjs';
const db = await createTestDatabase();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [actor,recipient,other,outsider,noDevice,crew,secondCrew,pact,secondPact] = [1,2,3,4,5,10,11,20,21].map(id);
for (const [i,u] of [actor,recipient,other,outsider,noDevice].entries()) {
  await db.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),'{\"first_name\":\"Jasmin\"}')",[u,`${u}@example.com`]);
  await db.query('insert into auth.sessions values($1,$2)',[id(100+i),u]);
}
for (const c of [crew]) {
  await db.query("insert into public.crews(id,name,owner_id,timezone) values($1,'Crew',$2,'Pacific/Auckland')",[c,actor]);
  for (const u of [recipient,other,noDevice]) await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')",[c,u,`${u}@example.com`]);
}
for (const [p,c] of [[pact,crew]]) await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','daily',7,$3)",[p,c,actor]);
async function asUser(u,fn,role='authenticated') {
  await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.session_id',$2,false)",[u,u ? id(100+[actor,recipient,other,outsider,noDevice].indexOf(u)) : '']);
  await db.exec(`set role ${role}`);
  try {return await fn();} finally {await db.exec('reset role');}
}
for (const u of [actor,recipient,other,outsider]) await asUser(u,()=>db.query("select register_push_device($1,'ios')",[`test_nudge_device_token_${u}`]));
await asUser(recipient,()=>db.query("select register_push_device($1,'android')",['second_nudge_device_token_'+recipient]));
const nudge=(u=recipient,c=crew)=>db.query('select send_crew_nudge($1,$2) result',[c,u]).then(r=>r.rows[0].result);
const status=()=>db.query('select * from crew_nudge_status($1)',[crew]).then(r=>r.rows);
await asUser(outsider,()=>assert.rejects(nudge(),/membership required/));
await asUser(outsider,()=>assert.rejects(status(),/membership required/));
await asUser(actor,()=>assert.rejects(nudge(actor),/another crew member/));
await asUser(actor,()=>assert.rejects(nudge(outsider),/membership required/));
await asUser('',()=>assert.rejects(nudge(),/permission denied/),'anon');
await asUser(actor,()=>assert.rejects(db.query('select * from private.crew_nudge_cooldowns'),/permission denied/));
const initial=await asUser(actor,status);
assert.equal(initial.find(r=>r.recipient_id===recipient).status,'ready');
assert.equal(initial.some(r=>r.recipient_id===actor),false);
assert.equal(initial.find(r=>r.recipient_id===noDevice).status,'unavailable');
assert.equal((await asUser(actor,()=>nudge(noDevice))).status,'unavailable');
assert.equal((await db.query('select * from private.crew_nudge_cooldowns')).rows.length,0);
const results=await asUser(actor,()=>Promise.all([nudge(),nudge(),nudge()]));
assert.equal(results.filter(r=>r.status==='sent').length,1);
assert.equal(results.filter(r=>r.status==='cooldown').length,2);
assert.equal(new Date(results[0].next_allowed_at)-Date.now()>23*3600*1000,true);
assert.equal((await asUser(actor,status)).find(r=>r.recipient_id===recipient).status,'cooldown');
let deliveries=(await db.query('select d.recipient_id,e.type,e.payload from private.notification_deliveries d join private.notification_events e on e.id=d.event_id')).rows;
assert.equal(deliveries.length,2);
assert.ok(deliveries.every(d=>d.recipient_id===recipient && d.type==='crew_nudge'));
assert.equal(deliveries[0].payload.actor_name,'Jasmin');
const today=(await db.query("select (now() at time zone 'Pacific/Auckland')::date::text as crew_date")).rows[0].crew_date;
assert.equal(deliveries[0].payload.completed_on,today);
assert.equal((await asUser(other,()=>nudge())).status,'sent','each sender has their own cooldown');
assert.equal((await asUser(actor,()=>nudge(other))).status,'sent','sender can encourage another person');
await db.query("update private.crew_nudge_cooldowns set last_sent_at=now()-interval '24 hours' where actor_id=$1 and recipient_id=$2",[actor,recipient]);
assert.equal((await asUser(actor,()=>nudge())).status,'sent','cooldown expires at 24 hours');
// Delayed encouragement must not arrive after the recipient already checked in.
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)',[pact,recipient,today]);
assert.equal((await asUser(actor,()=>nudge())).status,'checked_in');
const jobs=(await asUser('',()=>db.query('select * from claim_notification_deliveries()'),'service_role')).rows;
assert.ok(!jobs.some(j=>j.event_type==='crew_nudge' && j.payload.recipient_id===recipient));
const recipientNudges=(await db.query("select d.status from private.notification_deliveries d join private.notification_events e on e.id=d.event_id where e.type='crew_nudge' and d.recipient_id=$1",[recipient])).rows;
assert.ok(recipientNudges.every(d=>d.status==='cancelled'));
// Yesterday's undelivered nudges expire at the crew's date boundary.
await db.exec("update private.notification_events set payload=jsonb_set(payload,'{completed_on}',to_jsonb('2000-01-01'::text)) where type='crew_nudge'");
await asUser('',()=>db.query('select * from claim_notification_deliveries()'),'service_role');
assert.equal((await db.query("select d.* from private.notification_deliveries d join private.notification_events e on e.id=d.event_id where e.type='crew_nudge' and d.status<>'cancelled'")).rows.length,0);
// Moving to another crew does not reset the sender/recipient cooldown.
await db.query("insert into crews(id,name,owner_id) values($1,'Next crew',$2)",[secondCrew,outsider]);
await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','daily',7,$3)",[secondPact,secondCrew,outsider]);
for (const u of [actor,recipient]) {
  await db.query('delete from crew_members where crew_id=$1 and user_id=$2',[crew,u]);
  await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')",[secondCrew,u,`${u}@example.com`]);
}
assert.equal((await asUser(actor,()=>nudge(recipient,secondCrew))).status,'cooldown','changing crews cannot bypass cooldown');
await db.query('delete from auth.users where id=$1',[recipient]);
assert.equal((await db.query('select * from private.crew_nudge_cooldowns where recipient_id=$1',[recipient])).rows.length,0);
console.log('Nudge database checks passed: authorization, targeted devices, per-pair cooldown across crews, duplicate requests, expiry, eligibility, stale delivery cancellation, and deletion cleanup.');
await db.close();

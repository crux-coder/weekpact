process.on('uncaughtException',error=>{console.error(error.message,error.where??'');process.exit(1);});
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createTestDatabase} from './database_test_schema.mjs';
const migration='20260914170113_add_launch_foundations.sql';
const db=await createTestDatabase({beforeMigration:migration});
const id=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [owner,member,joiner,outsider,crew,pact]=[1,2,3,4,10,20].map(id);
for(const u of [owner,member,joiner,outsider])await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[u,`${u}@example.com`]);
const week=(await db.query("select date_trunc('week',now() at time zone 'Pacific/Auckland')::date::text w")).rows[0].w;
await db.query("insert into crews(id,name,owner_id,timezone,created_at) values($1,'Early Birds',$2,'Pacific/Auckland',$3::date-21)",[crew,owner,week]);
await db.query('update crew_members set joined_at=$1::date-21 where crew_id=$2',[week,crew]);
await db.query("insert into crew_members(crew_id,user_id,email,role,joined_at) values($1,$2,$3,'member',$4::date-21)",[crew,member,`${member}@example.com`,week]);
await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by,created_at) values($1,$2,'Read','weekly',1,$3,$4::date-21)",[pact,crew,owner,week]);
for(const days of [14,7])for(const u of [owner,member])await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3::date-$4::int)',[pact,u,week,days]);
await db.exec(await readFile(new URL(`../supabase/migrations/${migration}`,import.meta.url),'utf8'));
async function asUser(user,fn,role='authenticated'){
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec(`set role ${role}`);
 try{return await fn();}finally{await db.exec('reset role');}
}
const streak=()=>db.query('select crew_weekly_streak($1) n',[crew]).then(r=>r.rows[0].n);
const recap=(seen=null)=>db.query('select weekly_recap($1,$2) r',[crew,seen]).then(r=>r.rows[0].r);
const link=action=>db.query('select manage_crew_share_link($1,$2) r',[crew,action]).then(r=>r.rows[0].r);
assert.equal(await asUser(owner,streak),2);
const frozen=await asUser(owner,()=>recap());
assert.equal(frozen.check_ins,2);assert.equal(frozen.active_members,2);assert.equal(frozen.completed_pacts,1);assert.equal(frozen.seen,false);
assert.ok(!JSON.stringify(frozen).includes('@'));assert.ok(!('members' in frozen));
await db.query("update crew_pacts set days_per_week=7,frequency='daily',title='Read more' where id=$1",[pact]);
assert.equal(await asUser(owner,streak),2,'raising targets cannot erase earned weeks');
assert.deepEqual(await asUser(owner,()=>recap()),frozen,'recap is immutable');
await asUser(owner,()=>recap(frozen.week_start));
assert.equal((await asUser(owner,()=>recap())).seen,true);
assert.equal((await asUser(member,()=>recap())).seen,false,'seen status is per member');
await asUser(outsider,()=>assert.rejects(recap(),/membership required/));
await asUser('',()=>assert.rejects(recap(),/permission denied/),'anon');
await asUser(owner,()=>assert.rejects(db.query('delete from private.crew_week_results'),/permission denied/));
await asUser(owner,()=>assert.rejects(db.query('select private.finalize_all_crew_weeks()'),/permission denied/));
await asUser(member,()=>assert.rejects(link('create'),/owner required/));
const first=await asUser(owner,()=>link('create'));
assert.match(first.token,/^[a-f0-9]{64}$/);
assert.ok(new Date(first.expires_at)>new Date(Date.now()+6*86400000));
assert.equal((await db.query('select token_hash from private.crew_share_links')).rows[0].token_hash===first.token,false);
const accepted=()=>db.query('select accept_crew_invite($1) crew',[first.token]);
await asUser(joiner,accepted);
assert.equal((await asUser(joiner,accepted)).rows[0].crew,crew,'same-crew retry is idempotent');
assert.equal(await asUser(joiner,()=>recap()),null,'new members do not get recaps from before they joined');
await asUser(owner,()=>link('revoke'));
await asUser(outsider,()=>assert.rejects(accepted(),/invalid|already been used/));
const second=await asUser(owner,()=>link('create'));
assert.notEqual(second.token,first.token);
await db.query("update private.crew_share_links set expires_at=now()-interval '1 second'");
await asUser(outsider,()=>assert.rejects(db.query('select accept_crew_invite($1)',[second.token]),/expired/));
// Replacement invalidates a leaked/old link; confirmed accounts only.
const third=await asUser(owner,()=>link('create'));
await asUser(outsider,()=>assert.rejects(db.query('select accept_crew_invite($1)',[second.token]),/invalid|already been used/));
await db.query('update auth.users set email_confirmed_at=null where id=$1',[outsider]);
await asUser(outsider,()=>assert.rejects(db.query('select accept_crew_invite($1)',[third.token]),/Confirm your email/));
// Aggregate history survives member/account deletion and cascading pact changes.
await db.query('delete from auth.users where id=$1',[member]);
await db.query('delete from crew_pacts where id=$1',[pact]);
assert.equal(await asUser(owner,streak),2);
const afterDelete=await asUser(owner,()=>recap());
assert.equal(afterDelete.check_ins,2);assert.equal(afterDelete.active_members,2);
// Cron and foreground calls are repeatable and do not overwrite history.
await db.exec('select private.finalize_all_crew_weeks(); select private.finalize_all_crew_weeks();');
assert.equal((await db.query('select count(*) n from private.crew_week_results where crew_id=$1',[crew])).rows[0].n,3);
// New funnel events are server-derived and deduplicated.
const fresh=id(50);await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[fresh,'fresh@example.com']);
await asUser(fresh,()=>db.exec('select record_weekly_open(); select record_weekly_open();'));
const events=(await db.query('select event,count(*) n from private.product_events where user_id=$1 group by event',[fresh])).rows;
assert.deepEqual(events.sort((a,b)=>a.event.localeCompare(b.event)),[{event:'signup',n:1},{event:'weekly_open',n:1}]);
await asUser(fresh,()=>assert.rejects(db.query('select * from private.product_events'),/permission denied/));
await db.query('delete from auth.users where id=$1',[fresh]);assert.equal((await db.query('select * from private.product_events where user_id=$1',[fresh])).rows.length,0);
await db.exec(await readFile(new URL('./product_metrics.sql',import.meta.url),'utf8'));
console.log('Launch database checks passed: frozen history, crew timezone, recap privacy/authorization/seen states, idempotent cron, revocable invites, acceptance retry, confirmation, and private funnel events.');
await db.close();

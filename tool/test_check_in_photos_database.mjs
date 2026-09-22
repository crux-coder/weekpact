import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';
const db = await createTestDatabase();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [owner,member,outsider,crew,otherCrew,pact,second,otherPact] = [1,2,3,10,11,20,21,22].map(id);
for (const uid of [owner,member,outsider]) await db.query('insert into auth.users(id,email) values($1,$2)',[uid,uid+'@example.com']);
await db.query("insert into crews(id,name,owner_id) values($1,'Crew',$2),($3,'Other crew',$4)",[crew,owner,otherCrew,outsider]);
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')",[crew,member]);
for(const [pid,cid,uid] of [[pact,crew,owner],[second,crew,owner],[otherPact,otherCrew,outsider]]) await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by) values($1,$2,'Read','daily',7,$3)",[pid,cid,uid]);
const today=(await db.query("select to_char(current_date,'YYYY-MM-DD') as day")).rows[0].day;
const path=(uid=member,pid=pact,cid=crew,day=today,n='a')=>`${uid}/${cid}/${pid}/${day}/${n.repeat(32)}.png`;
const upload=name=>db.query("insert into storage.objects(bucket_id,name) values('check-in-photos',$1)",[name]);
const save=(ids,photos={},day=today,cid=crew)=>db.query('select save_pact_check_ins_with_photos($1,$2,$3::uuid[],$4::jsonb)',[cid,day,ids,JSON.stringify(photos)]);
const discard=paths=>db.query('select discard_unused_check_in_photos($1::text[])',[paths]);
const visible=async()=> (await db.query("select name from storage.objects where bucket_id='check-in-photos'")).rows.map(r=>r.name);
async function as(uid,fn,role='authenticated') {
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
 await db.exec('set role '+role);try {return await fn();} finally {await db.exec('reset role');}
}
const bucket=(await db.query("select * from storage.buckets where id='check-in-photos'")).rows[0];
assert.equal(bucket.public,false);assert.equal(Number(bucket.file_size_limit),5242880);assert.deepEqual(bucket.allowed_mime_types,['image/png']);
await as(member,async()=> {
 await assert.rejects(db.query('select save_pact_check_ins($1,$2,$3::uuid[])',[crew,today,[pact]]),/Take a photo/);
 await assert.rejects(save([pact]),/Take a photo/);
 await assert.rejects(save([pact],{[pact]:path()}),/unavailable/);
 for(const name of [path(owner),path(member,otherPact,otherCrew),path(member,pact,crew,'2000-01-01'),'junk']) await assert.rejects(upload(name),/row-level security/);
 await upload(path());
 await assert.rejects(save([pact],{[pact]:path(owner)}),/Take a photo/);
 await assert.rejects(save([pact],{[pact]:path()},'2000-01-01'),/day changed/);
 await assert.rejects(save([pact,otherPact],{[pact]:path()}),/Invalid pact/);
 assert.equal((await db.query('select * from pact_check_ins')).rows.length,0);
 // Drafts remain invisible to other crew members until submitted.
});
await as(owner,async()=>assert.deepEqual(await visible(),[]));
await as(outsider,async()=> {assert.deepEqual(await visible(),[]);await assert.rejects(save([pact],{[pact]:path()}),/membership/);});
await as(member,async()=> {
 await save([pact,pact],{[pact]:path()});
 await save([pact]); // Idempotent even without a fresh image.
 await discard([path()]); // Uncertain client responses cannot remove committed evidence.
 assert.equal((await db.query('select * from pact_check_ins')).rows[0].photo_path,path());
 assert.equal((await db.query("update storage.objects set name='changed' returning name")).rows.length,0);
 assert.equal((await db.query('delete from storage.objects returning name')).rows.length,0);
 await assert.rejects(db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)',[second,member,today]),/permission denied/);
 await assert.rejects(db.query('select * from pending_check_in_photo_cleanup()'),/permission denied/);
});
assert.equal((await db.query('select * from private.check_in_photo_cleanup')).rows.length,0);
await as(owner,async()=>assert.deepEqual(await visible(),[path()]));
await as(outsider,async()=> {await discard([path()]);assert.deepEqual(await visible(),[]);});
await as('',async()=> {assert.deepEqual(await visible(),[]);await assert.rejects(save([pact]),/permission denied/);},'anon');
await db.query('delete from crew_members where user_id=$1',[member]);
await as(member,async()=>assert.equal((await db.query('delete from storage.objects returning name')).rows.length,0));
// Removing a viewer's membership revokes access to another member's evidence.
await db.query('delete from crew_members where user_id=$1',[owner]);
await as(owner,async()=>assert.deepEqual(await visible(),[]));
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'member@example.com','member')",[crew,member]);
await as(member,async()=> {
 await save([]);
 await assert.rejects(save([pact],{[pact]:path()}),/unavailable/);
 await upload(path(member,pact,crew,today,'b'));
 await save([pact],{[pact]:path(member,pact,crew,today,'b')});
 await upload(path(member,second));
 await discard([path(member,second)]);
 await assert.rejects(save([pact,second],{[second]:path(member,second)}),/unavailable/);
});
const orphan=path(member,second,crew,today,'c');await upload(orphan);
await db.query("update storage.objects set created_at=now()-interval '25 hours' where name=$1",[orphan]);
const pending=await as('',()=>db.query('select * from pending_check_in_photo_cleanup()'),'service_role');
assert.deepEqual(new Set(pending.rows.map(r=>r.path)),new Set([path(),path(member,second),orphan]));
assert.equal((await as('',()=>db.query('select * from account_check_in_photo_paths($1)',[member]),'service_role')).rows.length,4);
await as('',()=>db.query('select finish_check_in_photo_cleanup($1::text[])',[[path()]]),'service_role');
assert.equal((await db.query('select * from private.check_in_photo_cleanup where path=$1',[path()])).rows.length,0);
// Old photo-free history is retained and may be preserved or undone.
await db.query('insert into pact_check_ins(pact_id,user_id,completed_on) values($1,$2,$3)',[second,member,today]);
await as(member,()=>save([pact,second]));
await db.query('delete from crew_pacts where id=$1',[pact]);
assert.equal((await db.query('select * from private.check_in_photo_cleanup where path=$1',[path(member,pact,crew,today,'b')])).rows.length,1);
// The photo is the pact's own rule: a pact that asks for none checks in on the
// selection alone, while its neighbour in the same crew still needs evidence.
const [optional,strict]=[23,24].map(id);
await db.query("insert into crew_pacts(id,crew_id,title,frequency,days_per_week,created_by,photo_required) values($1,$2,'Stretch','daily',7,$3,false),($4,$2,'Journal','daily',7,$3,true)",[optional,crew,owner,strict]);
await as(member,async()=> {
 await assert.rejects(save([second,optional,strict]),/Take a photo/);
 await save([second,optional]);
 assert.equal((await db.query('select photo_path from pact_check_ins where pact_id=$1',[optional])).rows[0].photo_path,null);
 await upload(path(member,strict,crew,today,'d'));
 await save([second,optional,strict],{[strict]:path(member,strict,crew,today,'d')});
 assert.equal((await db.query('select photo_path from pact_check_ins where pact_id=$1',[strict])).rows[0].photo_path,path(member,strict,crew,today,'d'));
 // Only the crew owner sets the rule; a member cannot relax it for everyone.
 assert.equal((await db.query('update crew_pacts set photo_required=false where id=$1 returning id',[strict])).rows.length,0);
});
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,'owner@example.com','owner')",[crew,owner]);
await as(owner,async()=>assert.equal((await db.query('update crew_pacts set photo_required=false where id=$1 returning id',[strict])).rows.length,1));
console.log('Per-pact photo requirement, scope, privacy, immutability, retries, undo, legacy history and cleanup permissions passed.');
await db.close();

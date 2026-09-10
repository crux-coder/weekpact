import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { storageTestSchema } from './storage_test_schema.mjs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role authenticated; create role anon; create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;`);
await db.exec(storageTestSchema);
await db.exec(await readFile(new URL('../supabase/migrations/20260910110607_create_avatar_storage.sql',import.meta.url),'utf8'));
const owner='00000000-0000-4000-8000-000000000001';
const other='00000000-0000-4000-8000-000000000002';
await db.query("insert into storage.objects(bucket_id,name) values('avatars',$1)",[`${owner}/avatar.png`]);
const bucket=(await db.query('select * from storage.buckets')).rows[0];
assert.equal(bucket.public,false); assert.equal(Number(bucket.file_size_limit),5242880); assert.deepEqual(bucket.allowed_mime_types,['image/png']);
let count=1;
async function asUser(user,fn,role='authenticated') {
 await db.exec('begin');
 try { await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user]); await db.exec(`set local role ${role}`); await fn(); count++; } finally { await db.exec('rollback'); }
}
await asUser(owner,async()=>assert.equal((await db.query('select * from storage.objects')).rows.length,1));
await asUser(other,async()=>{
 assert.equal((await db.query('select * from storage.objects')).rows.length,0);
 await db.query("insert into storage.objects(bucket_id,name) values('avatars',$1)",[`${other}/avatar.png`]);
 assert.equal((await db.query('select * from storage.objects')).rows.length,1);
});
await asUser(other,async()=>assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('avatars',$1)",[`${owner}/other.png`]),e=>e.code==='42501'));
await asUser(other,async()=>assert.equal((await db.query("update storage.objects set name=$1 returning *",[`${other}/avatar.png`])).rows.length,0));
await asUser(owner,async()=>assert.rejects(db.query('update storage.objects set name=$1',[`${other}/avatar.png`]),e=>e.code==='42501'));
await asUser(owner,async()=>assert.equal((await db.query('update storage.objects set name=name returning *')).rows.length,1));
await asUser('',async()=>{
 assert.equal((await db.query('select * from storage.objects')).rows.length,0);
 await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('avatars','anonymous/avatar.png')"),e=>e.code==='42501');
},'anon');
await db.close(); console.log(`${count} avatar bucket and access checks passed.`);

// Run with PGLITE_MODULE pointing to an installed @electric-sql/pglite entrypoint.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';

const db = await createTestDatabase();
const user = '00000000-0000-4000-8000-000000000001';

// Both stores start at the version that shipped first.
assert.deepEqual(
  (await db.query('select platform, latest_version, min_version, message from public.app_releases order by platform')).rows,
  [
    { platform: 'android', latest_version: '1.0.0', min_version: '1.0.0', message: null },
    { platform: 'ios', latest_version: '1.0.0', min_version: '1.0.0', message: null },
  ],
);

async function as(role, fn) {
  await db.exec('begin');
  try {
    if (role === 'authenticated') {
      await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user]);
    }
    await db.exec(`set local role ${role}`);
    await fn();
  } finally {
    await db.exec('rollback');
  }
}
async function rejects(sql, params) {
  await db.exec('savepoint attempt');
  await assert.rejects(db.query(sql, params));
  await db.exec('rollback to savepoint attempt');
}

// Signed out and signed in both read every row, and neither can change one.
for (const role of ['anon', 'authenticated']) {
  await as(role, async () => {
    assert.equal((await db.query('select count(*)::int as n from public.app_releases')).rows[0].n, 2);
    await rejects("update public.app_releases set latest_version='9.9.9'");
    await rejects("insert into public.app_releases(platform,latest_version,min_version) values('ios','2.0.0','1.0.0')");
    await rejects('delete from public.app_releases');
  });
}

// Marking a release raises the row and stamps it.
const before = (await db.query("select updated_at from public.app_releases where platform='ios'")).rows[0].updated_at;
await db.query("update public.app_releases set latest_version='1.2.0', min_version='1.1.0', message='Faster check-ins' where platform='ios'");
const raised = (await db.query("select * from public.app_releases where platform='ios'")).rows[0];
assert.equal(raised.latest_version, '1.2.0');
assert.equal(raised.min_version, '1.1.0');
assert.ok(raised.updated_at >= before);

// Only the two stores, plain X.Y.Z versions, and short messages are accepted.
await db.exec('begin');
await rejects("insert into public.app_releases(platform,latest_version,min_version) values('web','1.0.0','1.0.0')");
await rejects("update public.app_releases set latest_version='1.2' where platform='ios'");
await rejects("update public.app_releases set min_version='1.0.0+5' where platform='ios'");
await rejects("update public.app_releases set message=repeat('a',301) where platform='ios'");
await db.exec('rollback');

await db.close();
console.log('Release rows seeded, public read-only access, versions, messages and update stamps checks passed.');

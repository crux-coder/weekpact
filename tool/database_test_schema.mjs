import { readFile, readdir } from 'node:fs/promises';
import { storageTestSchema } from './storage_test_schema.mjs';
import { notificationTestSchema } from './notification_test_schema.mjs';

// Run the complete migration history against minimal Supabase-owned schemas.
export async function createTestDatabase({ beforeMigration } = {}) {
  const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema extensions;
    create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    create function extensions.digest(value text, algorithm text) returns bytea language sql as $$
      select sha256(convert_to(value, 'UTF8'))
    $$;
  `);
  await db.exec(storageTestSchema);
  await db.exec(notificationTestSchema);
  const directory = new URL('../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(directory)).filter(f => f.endsWith('.sql')).sort()) {
    if (file === beforeMigration) break;
    await db.exec((await readFile(new URL(file, directory), 'utf8'))
      .replace('create extension if not exists pgcrypto with schema extensions;', ''));
  }
  return db;
}

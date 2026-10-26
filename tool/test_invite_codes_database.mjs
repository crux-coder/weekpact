// Crew invite codes: one six-character code per crew, valid until reset.
// PGLITE_MODULE may point to a local @electric-sql/pglite installation.
import assert from 'node:assert/strict';
import { createTestDatabase } from './database_test_schema.mjs';
const db = await createTestDatabase();
const id = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const [owner, member, joiner, outsider, unverified, crew, otherCrew] = [1,2,3,4,5,10,11].map(id);
for (const [user, confirmed] of [[owner,true],[member,true],[joiner,true],[outsider,true],[unverified,false]]) {
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,case when $3 then now() else null end)', [user,`${user}@example.com`,confirmed]);
}
await db.query("insert into crews(id,name,owner_id) values($1,'Early Birds',$2),($3,'Night Owls',$4)", [crew,owner,otherCrew,outsider]);
await db.query("insert into crew_members(crew_id,user_id,email,role) values($1,$2,$3,'member')", [crew,member,`${member}@example.com`]);
for (const [user, first, last] of [[owner,'Ada','Lovelace'],[member,'grace','Hopper'],[outsider,'Alan','']]) {
  await db.query('update public.users set first_name=$2,last_name=$3 where id=$1', [user,first,last]);
}
await db.query("insert into crew_pacts(crew_id,title,frequency,days_per_week,created_by,icon_key,created_at) values($1,'Morning walk','weekly',3,$2,'walk',now()-interval '1 day'),($1,'Read','daily',7,$2,'book',now())", [crew,owner]);
let passed = 0;
// Every call runs in a transaction that commits, unless `rollback` is set.
async function asUser(user, fn, {role='authenticated', rollback=false} = {}) {
  await db.exec('begin');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user ?? '']);
    await db.exec(`set local role ${role}`);
    const result = await fn();
    await db.exec(rollback ? 'rollback' : 'commit');
    passed++;
    return result;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const anon = fn => asUser(null, fn, {role:'anon'});
const one = (sql, args) => db.query(sql, args).then(r => Object.values(r.rows[0])[0]);
const codeFor = target => one('select public.crew_invite_code($1)', [target]);
const reset = target => one('select public.reset_crew_invite_code($1)', [target]);
const preview = (code, from=null) => one('select public.preview_crew_invite($1,$2)', [code, from]);
const accept = code => one('select public.accept_crew_invite($1)', [code]);

// Format and alphabet: six characters, none of 0/O/1/I/L.
const alphabet = /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$/;
const drawn = (await db.query('select private.new_invite_code() c from generate_series(1,400)')).rows.map(r => r.c);
for (const c of drawn) assert.match(c, alphabet);
assert.ok(new Set(drawn.join('')).size >= 28, 'the draw covers the alphabet');
assert.ok(new Set(drawn).size >= 399, 'draws do not repeat');

// Any member gets the same code until it is reset.
const first = await asUser(member, () => codeFor(crew));
assert.match(first, alphabet);
assert.equal(await asUser(owner, () => codeFor(crew)), first);
assert.equal(await asUser(member, () => codeFor(crew)), first);
// Creating it is the invite_created funnel event, credited to whoever made it.
const events = (await db.query("select user_id,crew_id from private.product_events where event='invite_created'")).rows;
assert.deepEqual(events, [{user_id:member, crew_id:crew}]);

// Outsiders cannot fetch a code, and only the owner resets one.
await assert.rejects(asUser(outsider, () => codeFor(crew)), e => e.code === '42501' && /Crew member required/.test(e.message));
await assert.rejects(anon(() => codeFor(crew)), e => e.code === '42501');
await assert.rejects(asUser(member, () => reset(crew)), e => e.code === '42501' && /Crew owner required/.test(e.message));
await assert.rejects(asUser(outsider, () => reset(crew)), /Crew owner required/);
await assert.rejects(anon(() => reset(crew)), e => e.code === '42501');
// The table itself is out of the API's reach.
await assert.rejects(asUser(owner, () => db.query('select * from private.crew_invite_codes')), e => e.code === '42501');

// Anyone holding the code sees the crew, including before they have an account.
const anonPreview = await anon(() => preview(first));
assert.deepEqual(anonPreview, {
  crew_name: 'Early Birds',
  member_count: 2,
  owner_name: 'Ada Lovelace',
  inviter_name: 'Ada Lovelace',
  inviter_initials: 'AL',
  member_initials: ['AL', 'GH'],
  pacts: [
    {title:'Morning walk', icon_key:'walk', days_per_week:3},
    {title:'Read', icon_key:'book', days_per_week:7},
  ],
  is_member: false,
});
assert.ok(!JSON.stringify(anonPreview).includes('@'), 'no emails');
assert.ok(!JSON.stringify(anonPreview).includes(owner), 'no ids');
// Typed codes ignore case and surrounding space.
assert.equal((await anon(() => preview(` ${first.toLowerCase()} `))).crew_name, 'Early Birds');
// The inviter is whoever shared the link, if they belong to the crew; otherwise the owner.
const fromMember = await anon(() => preview(first, member));
assert.equal(fromMember.inviter_name, 'grace Hopper');
assert.equal(fromMember.inviter_initials, 'GH');
assert.equal(fromMember.owner_name, 'Ada Lovelace');
for (const stranger of [outsider, id(999)]) {
  assert.equal((await anon(() => preview(first, stranger))).inviter_name, 'Ada Lovelace');
}
// is_member is answered for the signed-in viewer only.
assert.equal((await asUser(member, () => preview(first))).is_member, true);
assert.equal((await asUser(owner, () => preview(first))).is_member, true);
assert.equal((await asUser(joiner, () => preview(first))).is_member, false);
// Unknown or malformed codes preview nothing rather than raising.
const unknown = first === 'ABCDEF' ? 'ABCDEG' : 'ABCDEF';
for (const nothing of [unknown, 'ABC0EF', 'ABCDE', 'ABCDEFG', '', null]) {
  assert.equal(await anon(() => preview(nothing)), null, `${nothing} previews nothing`);
}

// Accepting is idempotent and adds a plain member.
assert.equal(await asUser(joiner, () => accept(first.toLowerCase())), crew);
assert.equal(await asUser(joiner, () => accept(first)), crew);
assert.deepEqual((await db.query('select role,email from crew_members where crew_id=$1 and user_id=$2', [crew, joiner])).rows,
  [{role:'member', email:`${joiner}@example.com`}]);
assert.equal((await asUser(joiner, () => preview(first))).member_count, 3);
assert.equal((await asUser(joiner, () => preview(first))).is_member, true);
// A member re-using the code is harmless too, owner included.
assert.equal(await asUser(owner, () => accept(first)), crew);
assert.equal((await db.query("select role from crew_members where crew_id=$1 and user_id=$2", [crew, owner])).rows[0].role, 'owner');
await assert.rejects(asUser(joiner, () => accept(unknown)), /This invite code is no longer valid/);
await assert.rejects(asUser(unverified, () => accept(first)), /Confirm your email/);
await assert.rejects(anon(() => accept(first)), e => e.code === '42501');

// Reset gives a new code and the old one stops working everywhere.
const second = await asUser(owner, () => reset(crew));
assert.match(second, alphabet);
assert.notEqual(second, first);
assert.equal(await asUser(member, () => codeFor(crew)), second);
assert.equal(await anon(() => preview(first)), null);
await assert.rejects(asUser(outsider, () => accept(first)), /This invite code is no longer valid/);
assert.equal((await anon(() => preview(second))).crew_name, 'Early Birds');
assert.equal((await db.query("select count(*)::int n from private.product_events where event='invite_created' and user_id=$1", [owner])).rows[0].n, 1);
// Each crew has its own code.
const other = await asUser(outsider, () => codeFor(otherCrew));
assert.notEqual(other, second);
assert.equal((await anon(() => preview(other))).crew_name, 'Night Owls');
assert.equal((await anon(() => preview(other))).inviter_initials, 'A');

// Hex share links made before codes still preview and join while they live.
const legacy = 'c'.repeat(64);
await db.query(`insert into private.crew_share_links(crew_id,token_hash,created_by,expires_at) values($1,encode(extensions.digest($2,'sha256'),'hex'),$3,now()+interval '7 days')`, [crew, legacy, owner]);
assert.equal((await anon(() => preview(legacy, member))).inviter_name, 'grace Hopper');
assert.equal(await asUser(outsider, () => accept(legacy)), crew);

// New profiles take their name from Apple/Google metadata.
const meta = [
  [{given_name:'Joan', family_name:'Clarke'}, 'Joan', 'Clarke'],
  [{full_name:'Mary  Jane Watson'}, 'Mary', 'Jane Watson'],
  [{name:'Hedy'}, 'Hedy', ''],
  [{first_name:'Kept', given_name:'Ignored', name:'Also Ignored'}, 'Kept', 'Ignored'],
  [{}, '', ''],
];
for (const [i, [data, firstName, lastName]] of meta.entries()) {
  const user = id(100 + i);
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)', [user, `${user}@example.com`, data]);
  assert.deepEqual((await db.query('select first_name,last_name,onboarding_step::text step from public.users where id=$1', [user])).rows[0],
    {first_name:firstName, last_name:lastName, step:'profile'}, JSON.stringify(data));
}

// Deleting the crew takes its code with it.
await db.query('delete from crews where id=$1', [crew]);
assert.equal((await db.query('select * from private.crew_invite_codes where crew_id=$1', [crew])).rows.length, 0);
assert.equal(await anon(() => preview(second)), null);
console.log(`${passed} invite code format, reuse, reset, preview, acceptance and access-control checks passed.`);
await db.close();

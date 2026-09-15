import { randomBytes } from 'node:crypto';
// Upload fixtures through the real RLS policy when valid. Invalid requests reach
// the RPC unchanged so its membership, date, and pact checks are still exercised.
export async function saveWithTestPhotos(db, crew, day, ids) {
  const photos = {};
  const uid = (await db.query('select auth.uid() as id')).rows[0].id;
  for (const pact of new Set(ids ?? [])) {
    const path = `${uid}/${crew}/${pact}/${day}/${randomBytes(16).toString('hex')}.png`;
    if (uid && (await db.query('select private.can_upload_check_in_photo($1) as ok', [path])).rows[0].ok) {
      await db.query("insert into storage.objects(bucket_id,name) values('check-in-photos',$1)", [path]);
      photos[pact] = path;
    }
  }
  return db.query('select public.save_pact_check_ins_with_photos($1,$2,$3::uuid[],$4::jsonb)', [crew,day,ids,JSON.stringify(photos)]);
}

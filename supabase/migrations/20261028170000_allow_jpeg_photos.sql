-- Photos are uploaded as JPEG from this build on: a tenth of the same frame
-- as PNG, which every crew member downloads. PNG stays allowed for older
-- builds. Object names keep their .png ending, so every path check and every
-- client that matches on the name works unchanged; the stored content type
-- says what the bytes are.
update storage.buckets
set allowed_mime_types = array['image/png', 'image/jpeg']
where id in ('avatars', 'check-in-photos', 'crew-avatars');

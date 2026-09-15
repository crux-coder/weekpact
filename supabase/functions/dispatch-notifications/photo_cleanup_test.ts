import { cleanUpCheckInPhotos, type PhotoCleanupBackend } from './photo_cleanup.ts';
function assert(value: unknown): asserts value { if (!value) throw new Error('Assertion failed'); }
function fixture(paths = ['one.png']) {
  const calls: string[] = [];
  const backend: PhotoCleanupBackend = {
    async pending() { calls.push('pending'); return paths; },
    async remove(received) { assert(JSON.stringify(received) === JSON.stringify(paths)); calls.push('remove'); },
    async finish(received) { assert(JSON.stringify(received) === JSON.stringify(paths)); calls.push('finish'); },
  };
  return { calls, backend };
}
Deno.test('photo cleanup acknowledges only confirmed Storage deletions', async () => {
  const { calls, backend } = fixture();await cleanUpCheckInPhotos(backend);
  assert(calls.join(',') === 'pending,remove,finish');
});
Deno.test('empty cleanup makes no Storage request', async () => {
  const { calls, backend } = fixture([]);await cleanUpCheckInPhotos(backend);
  assert(calls.join(',') === 'pending');
});
Deno.test('failed deletion stays queued for a retry', async () => {
  const { calls, backend } = fixture();backend.remove = async () => { throw new Error('offline'); };
  let failed = false;try { await cleanUpCheckInPhotos(backend); } catch { failed = true; }
  assert(failed);assert(!calls.includes('finish'));
});

export interface PhotoCleanupBackend {
  pending(): Promise<string[]>;
  remove(paths: string[]): Promise<void>;
  finish(paths: string[]): Promise<void>;
}

export async function cleanUpCheckInPhotos(backend: PhotoCleanupBackend) {
  const paths = await backend.pending();
  if (!paths.length) return;
  await backend.remove(paths);
  // Only acknowledge confirmed removals; failed Storage requests retry next run.
  await backend.finish(paths);
}

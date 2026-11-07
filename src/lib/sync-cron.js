/**
 * Daily sync housekeeping (scheduled() in src/index.js):
 *   1. purge items deleted >30 days ago (tombstones stay; their R2 images go)
 *   2. a gzipped snapshot of each user's library to R2, keeping 30 days
 */
import storage from './storage.js';
import { purgeExpired, writeSnapshot, pruneSnapshots, T } from './sync.js';

export async function runDailySync(env, now = Date.now()) {
  const out = { purged: 0, snapshots: 0, errors: [] };
  try {
    for (let i = 0; i < 20; i++) {
      const { purged, imagePaths } = await purgeExpired(env.DB, now);
      out.purged += purged;
      if (imagePaths.length) await storage.remove(env, imagePaths);
      if (purged < 500) break;
    }
  } catch (err) {
    out.errors.push(`purge: ${err.message}`);
  }
  const { results: users } = await env.DB.prepare(`SELECT id FROM ${T.users}`).all();
  for (const { id } of users || []) {
    try {
      await writeSnapshot(env.DB, env.BUCKET, id, new Date(now));
      await pruneSnapshots(env.BUCKET, id, now);
      out.snapshots++;
    } catch (err) {
      out.errors.push(`snapshot ${id}: ${err.message}`);
    }
  }
  if (out.errors.length) console.warn('daily sync housekeeping', out);
  return out;
}

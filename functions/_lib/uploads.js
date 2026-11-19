// Loose uploads, shared by POST /api/upload (one crew, after its own uploads) and
// POST /api/housekeeping (every crew, on a timer). This file exports no onRequest handler, so it
// never becomes a route.
//
// "Unattached" means part of neither a cleanup nor a mission (submission_id and mission_id NULL).
// Mission photos and videos therefore never count against the unattached limit and are never cleaned
// up as orphans. Before migration 0004 there is no mission_id, and only submission_id counts.
import { LIMITS } from "./util.js";
import { withMissions } from "./missions.js";

// Rows one cleanup run handles at most.
const ORPHAN_BATCH = 50;

export const unattached = (m) => (m ? "submission_id IS NULL AND mission_id IS NULL" : "submission_id IS NULL");

// The same test for the cleanup below, with a unary + on the terms no index may serve. Nearly every
// row has mission_id NULL, so without index statistics SQLite would read the whole table through
// uploads_mission. With the +, the inner SELECT reads uploads_partner_unattached (one crew) or
// uploads_submission (every crew: only files that belong to no cleanup), and the DELETE goes by key.
const looseFirst = (m) => (m ? "submission_id IS NULL AND +mission_id IS NULL" : "submission_id IS NULL");
const looseStill = (m) => (m ? "+submission_id IS NULL AND +mission_id IS NULL" : "+submission_id IS NULL");

// Deletes uploads that were never sent with a cleanup or a mission and are older than
// LIMITS.orphanHours, rows and R2 objects, oldest first and at most ORPHAN_BATCH per run.
// With partnerId only that crew's files (after each of its uploads). Without it every crew's, so the
// files of a crew that never uploads again go too (POST /api/housekeeping).
// The rows go first, and only the keys whose row was really deleted leave R2: a file that a cleanup
// or a mission took in the meantime keeps its row (the DELETE re-checks) and so its object.
// Returns the number of rows deleted.
export async function cleanOrphans(env, partnerId = null) {
  const before = new Date(Date.now() - LIMITS.orphanHours * 3600000).toISOString();
  const crew = partnerId ? "partner_id = ? AND " : "";
  const args = partnerId ? [partnerId, before, ORPHAN_BATCH] : [before, ORPHAN_BATCH];
  const { results } = await withMissions((m) => env.DB.prepare(
    `DELETE FROM uploads
     WHERE key IN (SELECT key FROM uploads WHERE ${crew}${looseFirst(m)} AND created_at < ? ORDER BY created_at LIMIT ?)
       AND ${looseStill(m)}
     RETURNING key`
  ).bind(...args).all());
  if (!results || !results.length) return 0;
  const keys = results.map((r) => r.key);
  await env.MEDIA.delete(keys).catch((e) => console.error("orphan files not deleted", keys, e));
  return keys.length;
}

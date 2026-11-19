// The crew's private details of settled cleanups and missions: the message to Sapu Earth (private_note)
// and the exact point (lat, lng). LIMITS.privateDays days after a cleanup was approved or rejected
// (reviewed_at), or a mission was done (closed_at), the message is deleted and the point rounded to 3
// decimals: about 100 m, what the public map shows anyway (round3 in events.js), so no receipt moves
// off the globe. Pending cleanups, and missions in review, open or funded, keep both. A removed mission
// lost both at once (WIPE_PRIVATE in missions.js). The upload page's privacy notice promises this
// (docs/upload-flow.md, Privacy notices for crews and visitors).
// POST /api/housekeeping runs it, at most TRIM_BATCH rows per table per run. This file exports no
// onRequest handler, so it never becomes a route.
import { LIMITS } from "./util.js";
import { noMissionsTable } from "./missions.js";

const TRIM_BATCH = 100;
// SQLite's round(x, 3) gives the same 3 decimals as round3, and NULL stays NULL. It is idempotent, so a
// trimmed row never matches UNTRIMMED again and each row is written once.
const TRIM = "private_note = NULL, lat = round(lat, 3), lng = round(lng, 3)";
const UNTRIMMED = "(private_note IS NOT NULL OR lat <> round(lat, 3) OR lng <> round(lng, 3))";

// Returns how many cleanups and missions were trimmed in this run.
export async function trimPrivate(env) {
  const cutoff = new Date(Date.now() - LIMITS.privateDays * 86400000).toISOString();
  const subs = await env.DB.prepare(
    `UPDATE submissions SET ${TRIM}
     WHERE id IN (SELECT id FROM submissions
                  WHERE status IN ('approved', 'rejected') AND reviewed_at < ?1 AND ${UNTRIMMED} LIMIT ?2)`
  ).bind(cutoff, TRIM_BATCH).run();
  let missions = 0;
  try {
    const r = await env.DB.prepare(
      `UPDATE missions SET ${TRIM}
       WHERE id IN (SELECT id FROM missions WHERE status = 'done' AND closed_at < ?1 AND ${UNTRIMMED} LIMIT ?2)`
    ).bind(cutoff, TRIM_BATCH).run();
    missions = r.meta?.changes ?? 0;
  } catch (e) {
    // Before migration 0004 there are no missions: the cleanups above are trimmed all the same.
    if (!noMissionsTable(e)) throw e;
  }
  return { cleanups: subs.meta?.changes ?? 0, missions };
}

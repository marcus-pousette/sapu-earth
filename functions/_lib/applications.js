// Retention for partner applications, shared by POST /api/apply (after the response) and
// GET /api/admin/applications (before the list). This file exports no onRequest handler, so it
// never becomes a route.
//
// What is kept, and for how long:
// - Open applications are deleted after LIMITS.applyOpenDays days, with their photos.
// - The IP hash is only needed by the 24 h rate limit, so it is cleared after 24 hours.
// - Photos are deleted once an application is decided. An approve whose photo delete failed
//   leaves the keys on the row, and the next run here deletes them.
// - The logo of an application that no longer waits (expired here, or a DELETE APPLICATION whose rows were
//   left behind) is deleted in the same run, file and row (sweepApplicationLogos in logos.js).
// Each step handles at most LIMITS.applyCleanupBatch rows per run (the logos LOGO.batch).
import { LIMITS, keyList } from "./util.js";
import { sweepApplicationLogos } from "./logos.js";

// D1's error when migration 0003 has not been applied yet.
export function noApplicationsTable(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such table: applications/i.test(text);
}

export async function expireApplications(env) {
  const now = Date.now();
  const batch = LIMITS.applyCleanupBatch;

  // Rows first, then their photos. The status guard keeps a concurrent approve or reject safe: it
  // either decides the row before this delete (then the row stays), or finds it gone (404 or 409).
  const cutoff = new Date(now - LIMITS.applyOpenDays * 86400000).toISOString();
  const { results: expired } = await env.DB.prepare(
    `DELETE FROM applications
     WHERE id IN (SELECT id FROM applications WHERE status = 'new' AND created_at < ? ORDER BY created_at LIMIT ?)
       AND status = 'new'
     RETURNING id, photos`
  ).bind(cutoff, batch).all();
  const keys = (expired || []).flatMap((r) => keyList(r.photos));
  if (keys.length) {
    await env.MEDIA.delete(keys).catch((e) => console.error("expired application photos not deleted", keys, e));
  }
  // Their logos go in the same run. A failure leaves the logo rows for the next run, and must not stop the steps
  // below: the address hashes are promised to go after about a day.
  const logos = await sweepApplicationLogos(env).catch((e) => {
    console.error("application logos not deleted yet, the next run tries again", e);
    return 0;
  });

  // The rate limit counts created_at > now minus 24 h, so this never touches a hash it still needs.
  // Decided applications have no hash left (approve clears it, reject deletes the row).
  const since = new Date(now - 86400000).toISOString();
  await env.DB.prepare(
    `UPDATE applications SET ip_hash = ''
     WHERE id IN (SELECT id FROM applications WHERE status = 'new' AND created_at <= ? AND ip_hash <> '' LIMIT ?)`
  ).bind(since, batch).run();

  const photos = await dropDecidedPhotos(env);
  return { expired: (expired || []).length, photos: keys.length + photos, logos };
}

// Deletes the photos still listed on approved applications (an approve or a deactivate whose R2
// delete failed), then clears the list. If R2 fails again the keys stay for the next run.
// partnerId limits it to the application of that partner. Returns the number of keys deleted.
export async function dropDecidedPhotos(env, partnerId = null) {
  let st = env.DB.prepare(
    `SELECT id, photos FROM applications WHERE status = 'approved' AND photos <> '[]'${partnerId ? " AND partner_id = ?" : ""} LIMIT ?`
  );
  st = partnerId ? st.bind(partnerId, LIMITS.applyCleanupBatch) : st.bind(LIMITS.applyCleanupBatch);
  const { results } = await st.all();
  if (!results || !results.length) return 0;
  const keys = results.flatMap((r) => keyList(r.photos));
  if (keys.length) await env.MEDIA.delete(keys);
  const ids = results.map((r) => r.id);
  await env.DB.prepare(
    `UPDATE applications SET photos = '[]' WHERE status = 'approved' AND id IN (${ids.map(() => "?").join(",")})`
  ).bind(...ids).run();
  return keys.length;
}

// Missions (docs/missions.md), shared by the partner API, the public API, /admin/ and the share
// page /m/<no>. This file exports no onRequest handler, so it never becomes a route.
//
// States: review (just posted, only /admin/ sees it), open (shown as NEXT UP), funded,
// done (an approved cleanup closed it), removed (removed_why says why).
// "Now" media are uploads rows with mission_id set and submission_id NULL: 1 to 4 photos (kind 'before')
// and at most one short video of the spot (kind 'video', no stage). /media/ serves them publicly while the
// mission is open, funded or done.
//
// Housekeeping:
// - A mission nobody funds within MISSION_LIMITS.expireDays days (review: since it was posted,
//   open: since it was published) is removed ('expired') with its photos and video. expireMissions()
//   runs before the /admin/ list and after GET /api/missions, at most MISSION_LIMITS.batch per run.
// - Removing a mission for any reason deletes its now photos and video (deleteMissionPhotos): the rows
//   first, then R2. If R2 fails, the keys are logged; without a row /media/ never serves them.
//   If the row delete fails, sweepRemovedPhotos() retries it with the next /admin/ missions list.
//   None of these looks at kind: every file of the mission goes, whatever it is.
// - Removing a mission for any reason also wipes its private data in the same UPDATE (WIPE_PRIVATE):
//   the crew's private note and the exact point. Place, task, dates and money stay as the record.
import { SITE } from "./util.js";

export const MISSION_STATES = ["review", "open", "funded", "done", "removed"];
// States whose mission (and its now photos and video) the public may see.
export const PUBLIC_MISSION_STATES = ["open", "funded", "done"];
// States that count against the per-partner limit, and that a partner can still change.
export const ACTIVE_MISSION_STATES = ["review", "open", "funded"];
export const REMOVED_WHY = ["declined", "cancelled", "expired", "withdrawn", "unpublished", "deactivated"];

export const MISSION_LIMITS = {
  place: 120,
  task: 600,
  privateNote: 1000,
  photos: 4,         // now photos per mission (at least 1)
  videos: 1,         // short video of the spot now per mission (optional)
  active: 5,         // missions in review, open or funded per partner
  aheadDays: 120,    // plan_date at most this many days ahead
  expireDays: 28,    // review or open missions older than this are removed with their photos and video
  lateDays: 3,       // a funded mission this many days past plan_date with no cleanup in PENDING is LATE in /admin/, and
                     // the housekeeping counts it (waiting.late), so the GitHub note emails Marcus
  overdueDays: 14,   // a funded mission this many days past plan_date is OVERDUE in /admin/
  batch: 50,         // missions the expiry handles per run
  editMinutes: 120,  // a mission sent again with changes (same client_ref) takes them this long after posting
};

export const missionShareUrl = (no) => `${SITE}/m/${no}`;

// ---------- mission money: the same block in upload/upload.js, site/app.js, admin/admin.js and functions/_lib/missions.js ----------
// A stored price read back: price the whole price (price_local, or a cleanup's total_cost_local), crew the crew's pay in
// all, inside it (crew_local, crew_pay_local), people the crew size it was added up for. other: the rest of the price, to
// the cent. each: the pay for each person to the cent, null without a crew size from 1 to 1000. exact: the crew's pay is
// the same whole number of cents for each person, as for every price the crew page adds up since it asks for the pay
// for each person. null when the numbers do not fit together (not numbers, a crew pay below 0 or above the price).
function splitOf(price, crew, people) {
  if (!Number.isFinite(price) || !Number.isFinite(crew) || crew < 0 || crew > price) return null;
  const known = Number.isInteger(people) && people >= 1 && people <= 1000;
  const each = known ? Math.round((crew / people) * 100) / 100 : null;
  return { each, other: Math.round((price - crew) * 100) / 100, exact: known && Math.round(each * people * 100) === Math.round(crew * 100) };
}
// ---------- end of the mission money block ----------
// /missions and /m/<no> say a price as it adds up with it. The block is the same text as in the three pages, so the
// export sits outside it.
export { splitOf };

// What a crew fills in for a mission. A mission sent again with the same client_ref counts as the same
// one only when these and its now photos match (api/mission/index.js).
export const MISSION_CONTENT = ["place_name", "country", "lat", "lng", "task", "plan_date", "crew_size", "currency",
  "price_local", "crew_local", "private_note"];

// A short fingerprint of a mission's content and its now media, photos and video (as a set of keys). The
// /admin/ list sends it with every mission, and PUBLISH and FUND send it back, so they never act on a
// version Marcus has not seen: a mission in review can still take the crew's changes
// (api/admin/missions/decide.js).
export async function missionRevision(m, keys) {
  const text = JSON.stringify([MISSION_CONTENT.map((k) => m[k] ?? null), [...keys].sort()]);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return [...hash.slice(0, 8)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// SET clause for every UPDATE that makes a mission 'removed' (decline, remove, cancel, withdraw,
// expire, deactivate, unpublish): the private note and the exact point go with it.
export const WIPE_PRIVATE = "private_note = NULL, lat = NULL, lng = NULL";

// D1's error when migration 0004 has not been applied yet: the missions table or a mission_id
// column is missing.
export function noMissionsTable(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such table: missions|no such column: (?:\w+\.)?mission_id|has no column named mission_id/i.test(text);
}

// Runs fn(true), which may use the missions table and the mission_id columns. Before migration
// 0004 that throws, and fn(false) runs instead, with SQL that does not know about missions.
// Single statements and batches are atomic in D1, so the first try never leaves half a write.
export async function withMissions(fn) {
  try {
    return await fn(true);
  } catch (e) {
    if (!noMissionsTable(e)) throw e;
    return fn(false);
  }
}

// Now media rows (photos and video) for a set of mission ids, grouped as
// {missionId: [{key, kind, content_type, public}]}. nowParts splits one mission's rows.
export async function nowMediaFor(env, ids) {
  const out = {};
  for (const id of ids) out[id] = [];
  if (!ids.length) return out;
  // D1 caps bound parameters at 100 per statement.
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const { results } = await env.DB.prepare(
      `SELECT key, kind, content_type, public, mission_id FROM uploads
       WHERE submission_id IS NULL AND mission_id IN (${chunk.map(() => "?").join(",")}) ORDER BY created_at, key`
    ).bind(...chunk).all();
    for (const r of results) out[r.mission_id]?.push(r);
  }
  return out;
}

// One mission's now media rows as {photos: [rows], video: row or null}.
export const nowParts = (rows = []) => ({
  photos: rows.filter((r) => r.kind !== "video"),
  video: rows.find((r) => r.kind === "video") || null,
});

// Deletes the now media of these missions, photos and video alike (it never looks at kind): the uploads
// rows first (RETURNING their keys), then the objects in MEDIA and, when bound, PUBLIC_MEDIA. R2 failures
// are logged with the keys, not thrown. Returns the number of keys.
async function dropPhotos(env, ids) {
  const keys = [];
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const { results } = await env.DB.prepare(
      `DELETE FROM uploads WHERE submission_id IS NULL AND mission_id IN (${chunk.map(() => "?").join(",")}) RETURNING key`
    ).bind(...chunk).all();
    for (const r of results || []) keys.push(r.key);
  }
  // R2 deletes at most 1000 keys per call.
  for (let i = 0; i < keys.length; i += 1000) {
    const part = keys.slice(i, i + 1000);
    await env.MEDIA.delete(part).catch((e) => console.error("mission photos not deleted", part, e));
    if (env.PUBLIC_MEDIA) {
      await env.PUBLIC_MEDIA.delete(part).catch((e) => console.error("mission photos not deleted (public)", part, e));
    }
  }
  return keys.length;
}

export function deleteMissionPhotos(env, missionId) {
  return dropPhotos(env, [missionId]);
}

// The retry for deleteMissionPhotos: photo and video rows still on file for a removed mission, because
// the delete after the status change failed on the database side. Runs with the /admin/ missions list,
// at most MISSION_LIMITS.batch missions per run. Returns the number of keys.
export async function sweepRemovedPhotos(env) {
  const { results } = await env.DB.prepare(
    `SELECT DISTINCT u.mission_id AS id FROM uploads u JOIN missions m ON m.id = u.mission_id
     WHERE u.mission_id IS NOT NULL AND u.submission_id IS NULL AND m.status = 'removed' LIMIT ?`
  ).bind(MISSION_LIMITS.batch).all();
  const ids = (results || []).map((r) => r.id);
  return ids.length ? dropPhotos(env, ids) : 0;
}

// Missions nobody funded in time: review missions posted, and open missions published, more than
// MISSION_LIMITS.expireDays days ago are removed ('expired') with their photos and video. The status
// guard in the UPDATE keeps a concurrent FUND or PUBLISH safe: it either wins (the mission stays) or
// the mission is already removed (the admin action then answers 409).
export async function expireMissions(env) {
  const now = new Date();
  const cutoff = new Date(now.getTime() - MISSION_LIMITS.expireDays * 86400000).toISOString();
  const { results } = await env.DB.prepare(
    `UPDATE missions SET status = 'removed', removed_why = 'expired', closed_at = ?1, ${WIPE_PRIVATE}
     WHERE id IN (
         SELECT id FROM missions WHERE status = 'review' AND created_at < ?2
         UNION ALL
         SELECT id FROM missions WHERE status = 'open' AND COALESCE(published_at, created_at) < ?2
         LIMIT ?3)
       AND status IN ('review', 'open')
     RETURNING id`
  ).bind(now.toISOString(), cutoff, MISSION_LIMITS.batch).all();
  const ids = (results || []).map((r) => r.id);
  if (!ids.length) return { expired: 0, photos: 0 };
  const photos = await dropPhotos(env, ids);
  return { expired: ids.length, photos };
}

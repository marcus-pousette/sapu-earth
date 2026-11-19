// GET /api/admin/missions?status=review|open|funded|done|removed (default review)
// -> {counts: {review, open, funded}, month_eur, missions: [...]}
// Each mission has every column except client_ref (private_note, lat and lng are null once it is
// removed, see WIPE_PRIVATE in _lib/missions.js), plus partner_name, partner_slug, the contact
// from the partner's application (for the decline message, or null), late, overdue, pending_submission
// (a cleanup for it waiting in PENDING), share_url, the now photos as short-lived signed links
// (now: [{key, url}]), the crew's video of the spot (now_video: {key, url}, or null), and revision (a
// fingerprint of the content, photos and video, see missionRevision in _lib/missions.js).
// spots: a mission with several spots has every spot, spot 1 first ([{no, place_name, lat, lng, date}], spotList in
// _lib/spots.js; spot 1's point exact, the others rounded as stored), [] otherwise and before migration 0008. LATE and
// OVERDUE count from its last day.
// The 28-day expiry runs first, so the list never shows a mission that should be gone.
import { err, handle, json, signedMediaUrl } from "../../../_lib/util.js";
import { noApplicationsTable } from "../../../_lib/applications.js";
import {
  MISSION_LIMITS, PUBLIC_MISSION_STATES, expireMissions, missionRevision, missionShareUrl, noMissionsTable,
  nowMediaFor, nowParts, sweepRemovedPhotos,
} from "../../../_lib/missions.js";
import { lastDay, spotList, withSpots } from "../../../_lib/spots.js";

// Oldest first while something is to do, newest first for the history.
const ORDER = {
  review: "m.created_at ASC",
  open: "COALESCE(m.published_at, m.created_at) ASC",
  funded: "m.plan_date ASC, m.funded_at ASC",
  done: "m.closed_at DESC",
  removed: "m.closed_at DESC",
};

// client_ref is never selected, so it cannot leak into the response.
// The application join picks at most one row per partner, so it cannot duplicate missions.
const LIST = (status, withContact, sp) =>
  `SELECT m.id, m.no, m.partner_id, m.status, m.removed_why, m.place_name, m.country, m.lat, m.lng, m.task,
     ${sp ? "m.spots" : "NULL AS spots"},
     m.plan_date, m.crew_size, m.currency, m.price_local, m.crew_local, m.private_note, m.consent,
     m.funded_eur, m.advance_eur, m.review_note, m.submission_id, m.created_at, m.published_at,
     m.funded_at, m.closed_at,
     p.name AS partner_name, p.slug AS partner_slug,
     (SELECT s.id FROM submissions s WHERE s.mission_id = m.id AND s.status = 'pending'
       ORDER BY s.created_at DESC LIMIT 1) AS pending_submission,
     ${withContact ? "a.contact_name, a.whatsapp, a.email" : "NULL AS contact_name, NULL AS whatsapp, NULL AS email"}
   FROM missions m JOIN partners p ON p.id = m.partner_id
   ${withContact ? `LEFT JOIN applications a ON a.id = (
     SELECT x.id FROM applications x WHERE x.partner_id = m.partner_id ORDER BY x.decided_at DESC LIMIT 1)` : ""}
   WHERE m.status = ? ORDER BY ${ORDER[status]} LIMIT 200`;

// Money spent on missions funded this UTC month. A mission cancelled or removed with its deactivated
// partner only cost its advance.
const MONTH_EUR = `SELECT COALESCE(SUM(CASE WHEN removed_why IN ('cancelled', 'deactivated') THEN COALESCE(advance_eur, 0)
     ELSE COALESCE(funded_eur, 0) END), 0) AS eur
   FROM missions WHERE funded_at >= ?`;

const COUNTS = "SELECT status, COUNT(*) AS n FROM missions WHERE status IN ('review', 'open', 'funded') GROUP BY status";

// Funded, no cleanup waiting for it, and its day (the last of its spots) is at least this many days ago (that day at
// 00:00 UTC, as the housekeeping's late count goes by the UTC date).
function pastDay(m, now, days) {
  if (m.status !== "funded" || m.pending_submission) return false;
  const day = Date.parse(lastDay(m, "plan_date") + "T00:00:00Z");
  return Number.isFinite(day) && now - day >= days * 86400000;
}
// LATE from MISSION_LIMITS.lateDays (the housekeeping counts it, so Marcus gets an email), OVERDUE from overdueDays.
const isLate = (m, now) => pastDay(m, now, MISSION_LIMITS.lateDays);
const isOverdue = (m, now) => pastDay(m, now, MISSION_LIMITS.overdueDays);

export const onRequestGet = handle(async ({ request, env }) => {
  const status = new URL(request.url).searchParams.get("status") || "review";
  if (!Object.prototype.hasOwnProperty.call(ORDER, status)) return err(400, "Unknown status.");

  // Expiry first (review and open missions older than 28 days), then the retry for photos a removal
  // left behind. A failure must not hide the list.
  await expireMissions(env).catch((e) => { if (!noMissionsTable(e)) console.error("mission expiry", e); });
  await sweepRemovedPhotos(env).catch((e) => { if (!noMissionsTable(e)) console.error("mission photo sweep", e); });

  const now = new Date();
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
  const load = (withContact) => withSpots((sp) => env.DB.batch([
    env.DB.prepare(LIST(status, withContact, sp)).bind(status),
    env.DB.prepare(COUNTS),
    env.DB.prepare(MONTH_EUR).bind(monthStart),
  ]));
  let list, counts, month;
  try {
    try {
      [list, counts, month] = await load(true);
    } catch (e) {
      // Code deployed before migration 0003: the list works without contacts.
      if (!noApplicationsTable(e)) throw e;
      [list, counts, month] = await load(false);
    }
  } catch (e) {
    // Code deployed before migration 0004: say so instead of a 500.
    if (noMissionsTable(e)) return err(503, "Missions are not set up yet. Run migration 0004 (see docs/upload-flow.md).", { code: "migration" });
    throw e;
  }

  const c = { review: 0, open: 0, funded: 0 };
  for (const r of counts.results) c[r.status] = r.n;
  const media = await nowMediaFor(env, list.results.map((m) => m.id));
  const sign = async (r) => ({ key: r.key, url: await signedMediaUrl(env, r.key) });
  const missions = [];
  for (const m of list.results) {
    const { contact_name, whatsapp, email, ...rest } = m;
    const rows = media[m.id] || [];
    const { photos, video } = nowParts(rows);
    missions.push({
      ...rest,
      consent: !!m.consent,
      // A deactivated partner's application keeps contact_name '' (wiped), shown as no contact.
      contact: contact_name || whatsapp || email
        ? { contact_name: contact_name || null, whatsapp: whatsapp || null, email: email || null }
        : null,
      spots: spotList(m, "plan_date"),
      late: isLate(m, now.getTime()),
      overdue: isOverdue(m, now.getTime()),
      share_url: PUBLIC_MISSION_STATES.includes(m.status) ? missionShareUrl(m.no) : null,
      now: await Promise.all(photos.map(sign)),
      now_video: video ? await sign(video) : null,
      // PUBLISH and FUND send this back, so they only act on the version shown here, video included.
      revision: await missionRevision(m, rows.map((r) => r.key)),
    });
  }
  const eur = Number(month.results[0]?.eur) || 0;
  return json({ counts: c, month_eur: Math.round(eur * 100) / 100, missions });
});

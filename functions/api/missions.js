// GET /api/missions -> open and funded missions of active partners for the homepage (NEXT UP, the
// globe), newest published first, at most 200. The shape is in data/README.md (publicMission in
// _lib/events.js). Before migration 0004 it answers [] so the homepage just shows no missions.
// DEACTIVATE removes a partner's open and funded missions; the active check is a second guard.
// Every call also runs the mission expiry after the response, so a mission nobody funds goes away
// after 28 days even when nobody opens /admin/.
// partner.logo is the crew's live logo (migration 0006), null without one and before 0006.
// spots: a mission's spots when it has several (migration 0008, docs/missions.md, Spots); none before 0008.
import { LIVE_LOGO, publicMission } from "../_lib/events.js";
import { MISSION_LIMITS, expireMissions, noMissionsTable, nowMediaFor } from "../_lib/missions.js";
import { withLogos } from "../_lib/logos.js";
import { withSpots } from "../_lib/spots.js";
import { handle, json, noBindings } from "../_lib/util.js";

const CACHE = { "cache-control": "public, max-age=60" };

export const onRequestGet = handle(async ({ env, waitUntil }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  // An open mission past its 28 days is left out even before the expiry below has removed it.
  const cutoff = new Date(Date.now() - MISSION_LIMITS.expireDays * 86400000).toISOString();
  let rows, media;
  try {
    // withLogos inside this try: before migration 0004 the missions table is missing whichever runs first.
    ({ results: rows } = await withSpots((sp) => withLogos((logos) => env.DB.prepare(
      `SELECT m.no, m.status, m.plan_date, m.place_name, m.country, m.lat, m.lng, m.crew_size, m.task,
         m.currency, m.price_local, m.crew_local, m.funded_eur, m.id, p.name AS partner_name, p.slug AS partner_slug,
         ${logos ? LIVE_LOGO("m.partner_id") : "NULL"} AS partner_logo, ${sp ? "m.spots" : "NULL AS spots"}
       FROM missions m JOIN partners p ON p.id = m.partner_id
       WHERE p.active = 1 AND (m.status = 'funded' OR (m.status = 'open' AND COALESCE(m.published_at, m.created_at) >= ?))
       ORDER BY COALESCE(m.published_at, m.created_at) DESC, m.no DESC LIMIT 200`
    ).bind(cutoff).all())));
    // Photos and video of each mission; publicMission puts them in now and now_video.
    media = await nowMediaFor(env, rows.map((r) => r.id));
  } catch (e) {
    if (noMissionsTable(e)) return json([], 200, CACHE);
    throw e;
  }
  if (typeof waitUntil === "function") {
    waitUntil(expireMissions(env).catch((e) => {
      if (!noMissionsTable(e)) console.error("mission expiry", e);
    }));
  }
  return json(rows.map((m) => publicMission(env, m, media[m.id])), 200, CACHE);
});

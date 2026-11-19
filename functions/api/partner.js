// GET /api/partner?k=TOKEN -> {name, slug, country, page_url, submissions, missions, missions_enabled, logo, tiktok,
// listed, post_links_enabled, thanks_total} for an active partner, 404 otherwise.
// submissions: the last 10 cleanups this partner sent, with a share link once published, and a published one with its
// standing thanks (thanks, a whole number; never on a pending or rejected one, and not before migration 0007).
// missions: every mission of this partner in review, open or funded (any age, so a funded one never
// drops out of the crew page and the cleanup picker), plus the 20 newest others (done, removed), newest
// first, with a share link once they are open, funded or done. cleanup_sent says a pending or approved
// cleanup for it exists already. plan is the crew's own task and price ({task, currency, price_local,
// crew_local}), null once the mission is removed. spots: only for a mission with several spots (docs/missions.md,
// Spots; migration 0008), every spot, spot 1 first, as [{no, place_name, date}]: the cleanup form asks the photos and
// the day of each. Never their points.
// missions_enabled: false (and missions: []) before migration 0004, so the crew page (upload page)
// hides POST A MISSION and the mission cards.
// logo: the crew's logo for YOUR LOGO on the crew page, {enabled, live, review, declined, initials}
// (logoStateFor in _lib/logos.js); enabled false before migration 0006, and the page then hides the panel.
// tiktok: the crew's own TikTok account for YOUR TIKTOK on the crew page, {enabled, live, review, declined}
// (tiktokStateFor in _lib/tiktok.js; docs/upload-flow.md, Crew TikTok accounts); enabled false before migration 0009,
// and the page then hides the panel.
// listed: whether the crew is in the list of crews at /crews, so the crew page shows YOUR PUBLIC PAGE and SEE ALL CREWS
// by the rule of /crews. Every active crew is on it from the day Sapu Earth starts working with it (under JUST JOINED
// until it has a mission or a cleanup on sapu.earth; listedCrews in _lib/crews.js), and only active crews get this far
// (requirePartner), so it is always true and needs no read. The field stays: the crew page reads an older server's
// missing listed as "once a cleanup is approved".
// post_links_enabled: whether migration 0007 is in (crewThanks in _lib/social.js answers), so the cleanup form shows the
// field for the link to the crew's own post (docs/upload-flow.md, Post links and thanks); false before it.
// thanks_total: every standing thanks on the crew's approved receipts (crewThanks), for the line under YOUR CLEANUPS
// (docs/upload-flow.md, Thanks); only once migration 0007 is in.
// Additive (logo, tiktok, listed, post_links_enabled, thanks and thanks_total): a page from before them ignores them.
// review_note and private_note stay internal.
import { SITE, handle, json, noBindings, requirePartner } from "../_lib/util.js";
import { PUBLIC_MISSION_STATES, missionShareUrl, noMissionsTable } from "../_lib/missions.js";
import { logoStateFor } from "../_lib/logos.js";
import { tiktokStateFor } from "../_lib/tiktok.js";
import { crewThanks } from "../_lib/social.js";
import { spotList, withSpots } from "../_lib/spots.js";

// { spots } for a mission with several spots, {} otherwise: the place and day of each, never a point.
function spotsOf(m) {
  const s = spotList(m, "plan_date");
  return s.length ? { spots: s.map((p) => ({ no: p.no, place_name: p.place_name, date: p.date })) } : {};
}

// null before migration 0004 (the missions table or column is missing).
async function missionsOf(env, partnerId) {
  try {
    const { results } = await withSpots((sp) => env.DB.prepare(
      `SELECT m.id, m.no, m.place_name, m.country, m.crew_size, m.plan_date, m.status, m.removed_why,
         m.funded_eur, m.advance_eur, m.task, m.currency, m.price_local, m.crew_local, ${sp ? "m.spots" : "NULL AS spots"},
         EXISTS (SELECT 1 FROM submissions s WHERE s.mission_id = m.id AND s.status IN ('pending', 'approved')) AS cleanup_sent
       FROM missions m
       WHERE m.partner_id = ?1 AND (m.status IN ('review', 'open', 'funded') OR m.id IN (
         SELECT x.id FROM missions x WHERE x.partner_id = ?1 AND x.status NOT IN ('review', 'open', 'funded')
         ORDER BY x.created_at DESC, x.no DESC LIMIT 20))
       ORDER BY m.created_at DESC, m.no DESC`
    ).bind(partnerId).all());
    return results.map((m) => ({
      id: m.id,
      no: m.no,
      place_name: m.place_name,
      plan_date: m.plan_date,
      status: m.status,
      removed_why: m.removed_why,
      funded_eur: m.funded_eur,
      advance_eur: m.advance_eur,
      share_url: PUBLIC_MISSION_STATES.includes(m.status) ? missionShareUrl(m.no) : null,
      // For the crew page: a cleanup opened from a funded mission's card starts on its country and crew
      // size, and a mission whose cleanup was already sent offers none (a second one would get 409).
      country: m.country,
      crew_size: m.crew_size,
      cleanup_sent: !!m.cleanup_sent,
      // The crew's own plan and price, for its crew page: the price in a mission cleanup's costs line, and
      // the one-tap plan and price in POST A MISSION. null once removed, so a declined price is never
      // offered again. Never the notes, the review note or the point.
      plan: m.status === "removed" ? null
        : { task: m.task, currency: m.currency, price_local: m.price_local, crew_local: m.crew_local },
      ...spotsOf(m),
    }));
  } catch (e) {
    if (noMissionsTable(e)) return null;
    throw e;
  }
}

export const onRequestGet = handle(async ({ request, env }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const p = await requirePartner(env, request);
  const { results } = await env.DB.prepare(
    `SELECT id, place_name, cleanup_date, status FROM submissions
     WHERE partner_id = ? ORDER BY created_at DESC LIMIT 10`
  ).bind(p.id).all();
  const missions = await missionsOf(env, p.id);
  // null before migration 0007: then no thanks anywhere, and no post link field.
  const ct = await crewThanks(env, p.id, results.filter((s) => s.status === "approved").map((s) => s.id));
  return json({
    name: p.name,
    slug: p.slug,
    country: p.country,
    page_url: `${SITE}/p/${p.slug}`,
    submissions: results.map((s) => ({
      id: s.id,
      place_name: s.place_name,
      cleanup_date: s.cleanup_date,
      status: s.status,
      share_url: s.status === "approved" ? `${SITE}/r/${s.id}` : null,
      ...(ct && s.status === "approved" ? { thanks: ct.byId[s.id] || 0 } : {}),
    })),
    missions: missions || [],
    missions_enabled: missions !== null,
    logo: await logoStateFor(env, p.id, p.name),
    tiktok: await tiktokStateFor(env, p.id),
    listed: true,
    post_links_enabled: ct !== null,
    ...(ct ? { thanks_total: ct.total } : {}),
  });
});

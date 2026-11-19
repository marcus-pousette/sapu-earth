// POST /api/admin/partners/deactivate {id} -> the upload link stops working and /p/<slug> disappears.
// Answers {id, active: false, missions_removed, funded_removed: [{no, advance_eur}], logos_removed, post_links_removed,
// tiktok_removed}.
// Their approved cleanups stay on the globe.
// Their live and waiting logos are gone, files deleted (logos_removed: how many). The receipts stay, without it.
// The links to their own posts on Instagram or TikTok come off their receipts (post_links_removed: how many receipts);
// Sapu Earth's own post links stay (docs/upload-flow.md, Post links and thanks). Their thanks stay with their receipts,
// which take no new ones (countThanks counts only for an active crew).
// Their TikTok account, live and waiting, is deleted (tiktok_removed: 1 when they had one, else 0; docs/upload-flow.md,
// Crew TikTok accounts). /p/<slug> and /crews show only active crews, so it is off sapu.earth at once anyway.
// The personal details of the application that created the partner are wiped in the same step
// (contact, about, links, how they heard of us). The crew name, country and area stay.
// Their missions in review, open and funded are removed ('deactivated') with their now photos, and
// their private note and exact point are wiped: the crew can no longer send a cleanup, so a funded
// one would never come. The money columns stay, and a line in the review note says the advance
// stays with the crew. Done missions stay: they are receipts.
import { ID_RE, LIMITS, err, handle, json, nowIso, readJson } from "../../../_lib/util.js";
import { dropDecidedPhotos, noApplicationsTable } from "../../../_lib/applications.js";
import { WIPE_PRIVATE, deleteMissionPhotos, noMissionsTable } from "../../../_lib/missions.js";
import { dropCrewLogos } from "../../../_lib/logos.js";
import { dropCrewPostLinks } from "../../../_lib/social.js";
import { dropCrewTiktok } from "../../../_lib/tiktok.js";

// The line for the review note, from the row before the UPDATE (SQLite evaluates every SET
// expression on the old row, so status is still the old one here).
const LINE = `(CASE WHEN status = 'funded'
  THEN 'Partner deactivated; advance EUR ' || printf('%.2f', COALESCE(advance_eur, 0)) || ' stays with the crew.'
  ELSE 'Partner deactivated.' END)`;

// The old note (cut so the whole note stays within LIMITS.reviewNote), a new line, then LINE.
const REMOVE_ALL = `UPDATE missions SET status = 'removed', removed_why = 'deactivated', closed_at = ?1, ${WIPE_PRIVATE},
    review_note = CASE WHEN COALESCE(review_note, '') = '' THEN ${LINE}
      ELSE rtrim(substr(review_note, 1, max(?3 - length(${LINE}) - 1, 0))) || char(10) || ${LINE} END
  WHERE partner_id = ?2 AND status IN ('review', 'open', 'funded')
  RETURNING id, no, funded_at IS NOT NULL AS was_funded, advance_eur`;

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  const off = () => env.DB.prepare("UPDATE partners SET active = 0 WHERE id = ?").bind(b.id);

  // One batch, so the link never stops working without the details being wiped, or the other way round.
  let r, wiped = true;
  try {
    [r] = await env.DB.batch([
      off(),
      env.DB.prepare(
        `UPDATE applications SET contact_name = '', about = '', whatsapp = NULL, email = NULL,
           heard_from = NULL, links = NULL, ip_hash = '' WHERE partner_id = ?`
      ).bind(b.id),
    ]);
  } catch (e) {
    // Code deployed before migration 0003: deactivating a leaked link must still work.
    if (!noApplicationsTable(e)) throw e;
    r = await off().run();
    wiped = false;
  }
  if (!r.meta?.changes) return err(404, "Partner not found.");

  // Photos are normally gone since the approve. If that R2 delete failed, try again now; if it
  // fails again the keys stay on the row and the application cleanup retries.
  if (wiped) await dropDecidedPhotos(env, b.id).catch((e) => console.error("deactivate photo delete", b.id, e));

  // After the link is off, so a failure here never leaves a leaked link working. Deactivating
  // again is harmless and retries this step. /api/missions and /m/<no> also hide missions of an
  // inactive partner, so nothing shows in between.
  let missions_removed = 0;
  const funded_removed = [];
  try {
    const { results } = await env.DB.prepare(REMOVE_ALL).bind(nowIso(), b.id, LIMITS.reviewNote).all();
    for (const m of results || []) {
      await deleteMissionPhotos(env, m.id).catch((e) => console.error("deactivate mission photos", m.id, e));
      if (m.was_funded) funded_removed.push({ no: m.no, advance_eur: m.advance_eur ?? 0 });
    }
    missions_removed = (results || []).length;
  } catch (e) {
    // Code deployed before migration 0004: deactivating must still work.
    if (!noMissionsTable(e)) throw e;
  }
  // The crew's logos, after the link is off. A failure is logged, never thrown: the housekeeping's logo sweep takes
  // the logos of an inactive crew off as well. 0 before migration 0006.
  let logos_removed = 0;
  try {
    logos_removed = await dropCrewLogos(env, b.id);
  } catch (e) {
    console.error("deactivate logos", b.id, e);
  }
  // The crew's own post links, the same way: logged, never thrown; the housekeeping's post link sweep takes the links
  // of an inactive crew off as well. Its receipts stop showing them at once anyway (socialPick). 0 before migration 0007.
  let post_links_removed = 0;
  try {
    post_links_removed = await dropCrewPostLinks(env, b.id);
  } catch (e) {
    console.error("deactivate post links", b.id, e);
  }
  // The crew's TikTok account, the same way: logged, never thrown; the housekeeping's TikTok sweep deletes the row of an
  // inactive crew as well. 0 before migration 0009.
  let tiktok_removed = 0;
  try {
    tiktok_removed = await dropCrewTiktok(env, b.id);
  } catch (e) {
    console.error("deactivate tiktok", b.id, e);
  }
  return json({ id: b.id, active: false, missions_removed, funded_removed, logos_removed, post_links_removed, tiktok_removed });
});

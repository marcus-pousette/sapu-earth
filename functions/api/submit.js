// POST /api/submit?k=TOKEN  JSON body -> {id}
// Creates a pending submission and attaches this partner's unattached uploads (part of neither a
// cleanup nor a mission). Optional mission_id: the cleanup for one of this partner's funded missions
// (docs/missions.md); approving it in /admin/ marks the mission done.
// Media: 1 to 4 before and 1 to 4 after photos, at most 2 videos, of which at most 1 was uploaded as the
// video before the cleanup and 1 as the video after it (uploads.stage). A video without a stage only
// counts toward the 2.
// Before migration 0004 there is no mission_id column: cleanups without a mission still work. Before
// migration 0005 there is no stage column: the videos are then all without a stage.
// Optional post_url: the link to the crew's own post about the cleanup on Instagram or TikTok, stored in post_links
// (docs/upload-flow.md, Post links and thanks; postLink in _lib/social.js). A link that is not one post, or a short
// link, is refused (400 code post_link). Before migration 0007 the cleanup is stored and the link dropped.
// A mission with several spots (docs/missions.md, Spots; migration 0008): the cleanup has 1 to 4 before and 1 to 4 after
// photos for each spot (uploads.spot, set by POST /api/upload), the videos stay at most 2 for the whole mission, and
// spot_dates lists the day the crew cleaned spots 2, 3 and 4 (cleanup_date is spot 1's). The mission's spots go on the
// cleanup (submissions.spots) with those days. A photo of spot 2 or later is refused for any other cleanup.
import {
  CURRENCY_RE, HttpError, ID_RE, ISO2_RE, KEY_RE, LIMITS,
  cleanText, err, handle, isoDate, json, noBindings, nowIso, num, randomId, readJson, requirePartner, withStage,
} from "../_lib/util.js";
import { noMissionsTable, withMissions } from "../_lib/missions.js";
import { SPOTS, extraSpots, spotOf, withSpots } from "../_lib/spots.js";
import { postLink, withSocial } from "../_lib/social.js";

const unattached = (m) => (m ? "submission_id IS NULL AND mission_id IS NULL" : "submission_id IS NULL");
// The most files a cleanup takes: 4 before and 4 after photos for each of SPOTS.max spots, and 2 videos.
const MEDIA_MAX = 8 * SPOTS.max + 2;

// The mission a cleanup is sent for must be this partner's, funded, and not have a pending or
// approved cleanup yet. Throws the error to answer with, returns its spots 2 to 4 when it is fine ([] for one spot).
async function checkMission(env, partner, missionId) {
  let m = null;
  try {
    m = await withSpots((p) => env.DB.prepare(
      `SELECT status, ${p ? "spots" : "NULL AS spots"},
         (SELECT COUNT(*) FROM submissions WHERE mission_id = ?1 AND status IN ('pending', 'approved')) AS taken
       FROM missions WHERE id = ?1 AND partner_id = ?2`
    ).bind(missionId, partner.id).first());
  } catch (e) {
    if (!noMissionsTable(e)) throw e;
  }
  if (!m || m.status !== "funded") {
    throw new HttpError(400, "This mission is not funded, or not yours. Choose a funded mission or No mission.", "mission", "mission_id");
  }
  if (m.taken) throw new HttpError(409, "A cleanup for this mission was already sent.", "mission", "mission_id");
  return extraSpots(m.spots);
}

export const onRequestPost = handle(async ({ request, env }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);
  const b = await readJson(request);

  if (b.consent !== true) throw new HttpError(400, "Please confirm the consent checkbox.");

  const cleanup_date = isoDate(b.cleanup_date, "cleanup_date");
  const place_name = cleanText(b.place_name, LIMITS.place, { required: true, field: "place_name" });

  const country = b.country == null || b.country === "" ? null : String(b.country).toUpperCase();
  if (country !== null && !ISO2_RE.test(country)) throw new HttpError(400, "country must be a 2-letter ISO code.");

  let lat = num(b.lat, { min: -90, max: 90, field: "lat" });
  let lng = num(b.lng, { min: -180, max: 180, field: "lng" });
  if ((lat === null) !== (lng === null)) throw new HttpError(400, "lat and lng must be sent together.");

  const kg = num(b.kg, { min: 0, max: 100000, field: "kg" });
  const sacks = num(b.sacks, { min: 0, max: 10000, int: true, field: "sacks" });
  if (!(kg > 0) && !(sacks > 0)) throw new HttpError(400, "Enter the kg removed or the number of sacks.");
  const crew_size = num(b.crew_size, { min: 1, max: 1000, int: true, required: true, field: "crew_size" });
  const hours = num(b.hours, { min: 0, max: 72, field: "hours" });

  let currency = b.currency == null || b.currency === "" ? null : String(b.currency).trim().toUpperCase();
  if (currency !== null && !CURRENCY_RE.test(currency)) throw new HttpError(400, "currency must be a 3-letter code like IDR.");
  const total_cost_local = num(b.total_cost_local, { min: 0, max: 1e12, field: "total_cost_local" });
  const crew_pay_local = num(b.crew_pay_local, { min: 0, max: 1e12, field: "crew_pay_local" });
  if ((total_cost_local !== null || crew_pay_local !== null) && currency === null) {
    throw new HttpError(400, "Choose the currency for the money amounts.");
  }
  // The page adds the crew's pay into the total; a page from before that, still open in a tab, may not.
  if (total_cost_local !== null && crew_pay_local !== null && crew_pay_local > total_cost_local) {
    throw new HttpError(400, "crew_pay_local cannot be more than total_cost_local.", undefined, "crew_pay_local");
  }

  const disposal = cleanText(b.disposal, LIMITS.disposal, { field: "disposal" });
  const notes = cleanText(b.notes, LIMITS.notes, { field: "notes", multiline: true });
  // Never published: only /admin/ shows it, and toEvent() does not map it.
  const private_note = cleanText(b.private_note, LIMITS.privateNote, { field: "private_note", multiline: true });

  const mission_id = b.mission_id === undefined || b.mission_id === null || b.mission_id === "" ? null : b.mission_id;
  if (mission_id !== null && (typeof mission_id !== "string" || !ID_RE.test(mission_id))) {
    throw new HttpError(400, "Unknown mission. Choose a funded mission or No mission.", "mission", "mission_id");
  }

  // Here with the other fields, before the files are looked at, so a refused link never attaches them.
  const noPost = b.post_url === undefined || b.post_url === null || b.post_url === "";
  const post = noPost ? null : postLink(b.post_url);
  if (!noPost && !(post && post.url)) {
    throw new HttpError(400, post && post.short
      ? "Short links cannot be checked. Paste the full link to the post, or leave it empty."
      : "post_url must be the link to one Instagram or TikTok post.", "post_link", "post_url");
  }

  // Media: keys this partner uploaded that are not attached to any submission yet. 8 photos for each spot and 2 videos.
  if (!Array.isArray(b.media) || b.media.length === 0 || b.media.length > MEDIA_MAX) {
    throw new HttpError(400, `media must list 2 to ${MEDIA_MAX} uploaded file keys.`);
  }
  const keys = [...new Set(b.media)];
  if (keys.length !== b.media.length || !keys.every((k) => typeof k === "string" && KEY_RE.test(k))) {
    throw new HttpError(400, "media contains an invalid key.");
  }
  const marks = keys.map(() => "?").join(",");
  const { results: rows } = await withSpots((p) => withStage((s) => withMissions((m) => env.DB.prepare(
    `SELECT key, kind${s ? ", stage" : ""}${p ? ", spot" : ""} FROM uploads WHERE partner_id = ? AND ${unattached(m)} AND content_type <> 'invalid' AND key IN (${marks})`
  ).bind(partner.id, ...keys).all())));
  if (rows.length !== keys.length) {
    // Idempotent retry: the phone sent this exact cleanup before but never got the answer
    // (common on flaky mobile data). If every key already belongs to one submission of this
    // partner, and that submission has exactly these files, answer with its id again.
    // (A mission's now photos have no submission, so they never match here.)
    const { results: owners } = await env.DB.prepare(
      `SELECT submission_id, COUNT(*) AS c FROM uploads WHERE partner_id = ? AND key IN (${marks}) GROUP BY submission_id`
    ).bind(partner.id, ...keys).all();
    if (owners.length === 1 && owners[0].submission_id && owners[0].c === keys.length) {
      const prev = await env.DB.prepare(
        "SELECT (SELECT COUNT(*) FROM uploads WHERE submission_id = ?1) AS n, status FROM submissions WHERE id = ?1 AND partner_id = ?2"
      ).bind(owners[0].submission_id, partner.id).first();
      if (prev && prev.n === keys.length && prev.status !== "rejected") return json({ id: owners[0].submission_id, repeated: true });
    }
    return err(400, "Some files were not found or were already used. Please upload them again.", { code: "media" });
  }
  const count = (k) => rows.filter((r) => r.kind === k).length;
  if (count("before") < 1 || count("after") < 1) throw new HttpError(400, "Add at least one before photo and one after photo.");
  if (count("video") > 2) throw new HttpError(400, "At most 2 videos.");
  const staged = (st) => rows.filter((r) => r.kind === "video" && r.stage === st).length;
  if (staged("before") > 1 || staged("after") > 1) throw new HttpError(400, "At most 1 video before and 1 video after the cleanup.");

  // After the idempotent retry above: a retry of a mission cleanup must get its id back, not a 409.
  const extra = mission_id ? await checkMission(env, partner, mission_id) : [];
  // The photos, spot by spot (a row without a spot is spot 1). A spot this cleanup does not have takes no photo. No code
  // "media" here: the crew page would upload every file again, which fixes nothing a missing photo needs.
  const n = 1 + extra.length;
  if (rows.some((r) => r.kind !== "video" && Number.isInteger(r.spot) && spotOf(r, n) !== r.spot)) {
    throw new HttpError(400, n > 1 ? `This mission has ${n} spots. Please reload the page.` : "This cleanup has one spot. Please reload the page.");
  }
  for (let k = 1; k <= n; k++) {
    const at = (kind) => rows.filter((r) => r.kind === kind && spotOf(r, n) === k).length;
    const of = n > 1 ? ` for spot ${k}` : "";
    if (at("before") < 1 || at("after") < 1) throw new HttpError(400, `Add at least one before photo and one after photo${of}.`);
    if (at("before") > 4 || at("after") > 4) throw new HttpError(400, `At most 4 before and 4 after photos${of}.`);
  }
  // The day of each spot after the first, and the mission's spots with them. cleanup_date is spot 1's day.
  let spots = null;
  if (extra.length) {
    const days = Array.isArray(b.spot_dates) ? b.spot_dates : [];
    if (days.length !== extra.length) throw new HttpError(400, `spot_dates must list the day of spots 2 to ${n}.`, "spot_dates", "spot_dates");
    spots = JSON.stringify(extra.map((s, i) => ({ ...s, date: isoDate(days[i], `spot_dates[${i}]`) })));
  }

  const id = randomId(10);
  const cols = `id, partner_id, status, created_at, cleanup_date, place_name, country, lat, lng,
        kg, sacks, crew_size, hours, currency, total_cost_local, crew_pay_local, disposal, notes, private_note, consent`;
  const vals = [id, partner.id, nowIso(), cleanup_date, place_name, country, lat, lng,
    kg, sacks, crew_size, hours, currency, total_cost_local, crew_pay_local, disposal, notes, private_note];
  const insert = mission_id
    // The mission is checked again inside the INSERT, so two racing cleanups cannot both take it
    // and a mission cancelled in the meantime is not taken.
    ? env.DB.prepare(
      `INSERT INTO submissions (${cols}${spots ? ", spots" : ""}, mission_id)
       SELECT ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1${spots ? ", ?" : ""}, ?
       WHERE EXISTS (SELECT 1 FROM missions WHERE id = ? AND partner_id = ? AND status = 'funded')
         AND NOT EXISTS (SELECT 1 FROM submissions WHERE mission_id = ? AND status IN ('pending', 'approved'))`
    ).bind(...vals, ...(spots ? [spots] : []), mission_id, mission_id, partner.id, mission_id)
    : env.DB.prepare(
      `INSERT INTO submissions (${cols})
       VALUES (?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`
    ).bind(...vals);
  // The crew's post link goes in the same batch, only once the cleanup is stored. Before migration 0007 the first try
  // fails as a whole (one batch is one transaction) and the second runs without it.
  const res = await withSocial((social) => withMissions((m) => env.DB.batch([
    insert,
    // Re-check "unattached" inside the batch so two racing submits cannot share files.
    env.DB.prepare(
      `UPDATE uploads SET submission_id = ? WHERE partner_id = ? AND ${unattached(m)} AND key IN (${marks})
         AND EXISTS (SELECT 1 FROM submissions WHERE id = ?)`
    ).bind(id, partner.id, ...keys, id),
    ...(social && post ? [env.DB.prepare(
      "INSERT INTO post_links (submission_id, crew_url) SELECT ?1, ?2 WHERE EXISTS (SELECT 1 FROM submissions WHERE id = ?1)"
    ).bind(id, post.url)] : []),
  ])));
  if (mission_id && (res[0].meta?.changes ?? 1) === 0) {
    // Only a mission cleanup can insert nothing: the mission changed since the check above.
    return err(409, "A cleanup for this mission was already sent, or the mission changed. Please reload the page.", { code: "mission", field: "mission_id" });
  }
  if ((res[1].meta?.changes ?? keys.length) !== keys.length) {
    // Lost a race: undo and ask to retry. The post link goes with the cleanup.
    await withSocial((social) => env.DB.batch([
      env.DB.prepare("UPDATE uploads SET submission_id = NULL WHERE submission_id = ?").bind(id),
      ...(social ? [env.DB.prepare("DELETE FROM post_links WHERE submission_id = ?1").bind(id)] : []),
      env.DB.prepare("DELETE FROM submissions WHERE id = ?").bind(id),
    ]));
    return err(409, "Some files were already used. Please try again.", { code: "media" });
  }
  return json({ id });
});

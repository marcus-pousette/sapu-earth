// POST /api/mission?k=TOKEN  JSON body -> 201 {id, no}
// A crew posts a mission (docs/missions.md): 1 to 4 photos of the spot now (uploaded before with
// kind=before) and at most 1 short video of it (kind=video, no stage), the place, what they will do, the
// planned day, the crew size and their price.
// It starts in 'review': only /admin/ sees it until Sapu Earth publishes or funds it.
// Errors are {error, field?, code?}; the upload page shows its own translated text.
//
// Body: {client_ref, place_name, country, lat, lng, task, plan_date, crew_size, currency,
//        price_local, crew_local, private_note, consent: true, media: [key, ...]}
// Sending the same client_ref again (the phone lost the answer):
// - unchanged: 200 {id, no, repeated: true}, unless the mission was removed meanwhile;
// - changed, while the mission is in review and was posted less than MISSION_LIMITS.editMinutes ago:
//   the stored mission takes the changes, photos and video included: 200 {id, no, repeated: true, updated: true};
// - changed later, or once Sapu Earth acted on it (open, funded, done), or sent again in any form once it
//   was removed (withdrawn, declined, expired...): 409 code client_ref. The page then posts a new mission.
import {
  CURRENCY_RE, HttpError, ISO2_RE, KEY_RE,
  cleanText, err, handle, json, noBindings, nowIso, num, randomId, readJson, requirePartner,
} from "../../_lib/util.js";
import { MISSION_CONTENT, MISSION_LIMITS, noMissionsTable } from "../../_lib/missions.js";

const REF_RE = /^[0-9a-f]{32}$/;
const DAY = 86400000;

const bad = (message, field, code, status = 400) => new HttpError(status, message, code, field);

const MEDIA_RULE = `Add 1 to ${MISSION_LIMITS.photos} photos of the place now, and at most ${MISSION_LIMITS.videos} video.`;

// The answer when a mission's files (the upload rows of its media keys) are not 1 to 4 photos (kind
// before) and at most 1 video, and nothing else. null when they are.
function mediaProblem(rows) {
  const photos = rows.filter((r) => r.kind === "before").length;
  const videos = rows.filter((r) => r.kind === "video").length;
  return photos + videos !== rows.length || photos < 1 || photos > MISSION_LIMITS.photos || videos > MISSION_LIMITS.videos
    ? err(400, MEDIA_RULE, { code: "media", field: "media" })
    : null;
}

// Run one field's check and tag its error with the body field name.
function at(field, check) {
  try {
    return check();
  } catch (e) {
    if (e instanceof HttpError && !e.field) e.field = field;
    throw e;
  }
}

// YYYY-MM-DD, a real date, from yesterday (time zones) up to MISSION_LIMITS.aheadDays days ahead.
// isoDate() in util.js refuses the future, a mission is all future.
function planDate(v) {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad("plan_date must be YYYY-MM-DD.", "plan_date");
  const t = Date.parse(v + "T00:00:00Z");
  if (!Number.isFinite(t) || new Date(t).toISOString().slice(0, 10) !== v) throw bad("plan_date is not a real date.", "plan_date");
  const today = Date.parse(new Date().toISOString().slice(0, 10) + "T00:00:00Z");
  if (t < today - DAY) throw bad("plan_date cannot be in the past.", "plan_date");
  if (t > today + MISSION_LIMITS.aheadDays * DAY) {
    throw bad(`plan_date can be at most ${MISSION_LIMITS.aheadDays} days ahead.`, "plan_date");
  }
  return v;
}

function readFields(b) {
  if (b.consent !== true) throw bad("Please confirm the consent checkbox.", "consent", "consent");
  if (typeof b.client_ref !== "string" || !REF_RE.test(b.client_ref)) {
    throw bad("The form is missing its reference. Please reload the page and try again.", "client_ref");
  }
  const f = { client_ref: b.client_ref };
  f.place_name = at("place_name", () => cleanText(b.place_name, MISSION_LIMITS.place, { required: true, field: "place_name" }));

  f.country = b.country == null || b.country === "" ? null : String(b.country).trim().toUpperCase();
  if (f.country !== null && !ISO2_RE.test(f.country)) throw bad("country must be a 2-letter ISO code.", "country");

  f.lat = at("lat", () => num(b.lat, { min: -90, max: 90, field: "lat" }));
  f.lng = at("lng", () => num(b.lng, { min: -180, max: 180, field: "lng" }));
  if ((f.lat === null) !== (f.lng === null)) throw bad("lat and lng must be sent together.", "lat");

  const task = typeof b.task === "string" ? b.task.replace(/\r\n?/g, "\n") : b.task;
  f.task = at("task", () => cleanText(task, MISSION_LIMITS.task, { required: true, field: "task", multiline: true }));
  f.plan_date = planDate(b.plan_date);
  f.crew_size = at("crew_size", () => num(b.crew_size, { min: 1, max: 1000, int: true, required: true, field: "crew_size" }));

  f.currency = typeof b.currency === "string" ? b.currency.trim().toUpperCase() : "";
  if (!CURRENCY_RE.test(f.currency)) throw bad("currency must be a 3-letter code like IDR.", "currency");
  f.price_local = at("price_local", () => num(b.price_local, { min: 0, max: 1e12, required: true, field: "price_local" }));
  if (!(f.price_local > 0)) throw bad("price_local must be more than 0.", "price_local");
  f.crew_local = at("crew_local", () => num(b.crew_local, { min: 0, max: 1e12, required: true, field: "crew_local" }));
  if (f.crew_local > f.price_local) throw bad("crew_local cannot be more than price_local.", "crew_local");

  // Never published: only /admin/ shows it.
  const note = typeof b.private_note === "string" ? b.private_note.replace(/\r\n?/g, "\n") : b.private_note;
  f.private_note = at("private_note", () => cleanText(note, MISSION_LIMITS.privateNote, { field: "private_note", multiline: true }));

  // The photos and the video. Which is which is checked against their upload rows (mediaProblem).
  if (!Array.isArray(b.media) || b.media.length < 1 || b.media.length > MISSION_LIMITS.photos + MISSION_LIMITS.videos) {
    throw bad(MEDIA_RULE, "media", "media");
  }
  f.keys = [...new Set(b.media)];
  if (f.keys.length !== b.media.length || !f.keys.every((k) => typeof k === "string" && KEY_RE.test(k))) {
    throw bad("media contains an invalid key.", "media", "media");
  }
  return f;
}

const byRef = (env, ref) => env.DB.prepare(
  `SELECT id, no, partner_id, status, created_at, ${MISSION_CONTENT.join(", ")} FROM missions WHERE client_ref = ?`
).bind(ref).first();
const marksFor = (keys) => keys.map(() => "?").join(",");

const refUsed = () => err(409,
  "This mission was already sent and can no longer be changed. Send it again to post it as a new mission.",
  { code: "client_ref", field: "client_ref" });

// The answer for a client_ref that is already stored (the phone sent this mission before but lost the
// answer), or null when it is new. See the top of this file for the three cases. The edit window keeps a
// draft reused days later for another spot from overwriting the mission it once posted.
async function repeatedFor(env, partner, f) {
  const prev = await byRef(env, f.client_ref);
  if (!prev) return null;
  if (prev.partner_id !== partner.id) {
    return err(409, "This form was already sent. Please reload the page and try again.", { code: "client_ref", field: "client_ref" });
  }
  const { results: have } = await env.DB.prepare("SELECT key, kind FROM uploads WHERE mission_id = ?").bind(prev.id).all();
  const keys = have.map((r) => r.key);
  const same = MISSION_CONTENT.every((k) => (prev[k] ?? null) === (f[k] ?? null))
    && keys.length === f.keys.length && f.keys.every((k) => keys.includes(k));
  if (same && prev.status !== "removed") return json({ id: prev.id, no: prev.no, repeated: true });
  const fresh = Date.now() - Date.parse(prev.created_at) < MISSION_LIMITS.editMinutes * 60000;
  if (prev.status === "review" && fresh) return update(env, partner, prev, have, f);
  return refUsed();
}

// The crew changed the form and sent it again soon after posting, while the mission is in review: the
// stored mission takes the new fields, photos and video in one batch, which D1 runs as one transaction.
// The new set of files must still be 1 to 4 photos and at most 1 video, checked before anything is
// written. The field UPDATE and the drop only apply when every file of the request is on the mission
// after the attach and no other file is (besides the ones it takes out), so a lost race for a file, a
// resend with other files at the same moment (a second video, a fifth photo), or a mission that just left
// review, changes nothing, and only the files this request attached are given back. The mission then
// always holds the set that was checked. A photo or video taken out becomes a loose file
// again: it counts against the crew's unattached files, and cleanOrphans (_lib/uploads.js) deletes it
// once it is LIMITS.orphanHours old, counted from its upload: at the crew's next upload or the scheduled
// housekeeping (api/housekeeping.js), whichever comes first.
// have: the upload rows {key, kind} on the mission now.
async function update(env, partner, prev, have, f) {
  const keys = have.map((r) => r.key);
  const add = f.keys.filter((k) => !keys.includes(k));
  const drop = keys.filter((k) => !f.keys.includes(k));
  let added = [];
  if (add.length) {
    // New files: photos and videos of this partner that are not part of a cleanup or a mission yet.
    const { results: rows } = await env.DB.prepare(
      `SELECT key, kind FROM uploads
       WHERE partner_id = ? AND submission_id IS NULL AND mission_id IS NULL AND content_type <> 'invalid' AND key IN (${marksFor(add)})`
    ).bind(partner.id, ...add).all();
    if (rows.length !== add.length) {
      return err(400, "Some photos were not found or were already used. Please upload them again.", { code: "media", field: "media" });
    }
    added = rows;
  }
  const problem = mediaProblem([...have.filter((r) => f.keys.includes(r.key)), ...added]);
  if (problem) return problem;
  const inReview = "EXISTS (SELECT 1 FROM missions WHERE id = ? AND partner_id = ? AND status = 'review')";
  const allOn = `(SELECT COUNT(*) FROM uploads WHERE mission_id = ? AND key IN (${marksFor(f.keys)})) = ${f.keys.length}`;
  const known = [...f.keys, ...drop];
  const only = `NOT EXISTS (SELECT 1 FROM uploads WHERE mission_id = ? AND key NOT IN (${marksFor(known)}))`;
  const stmts = [];
  if (add.length) {
    stmts.push(env.DB.prepare(
      `UPDATE uploads SET mission_id = ?
       WHERE partner_id = ? AND submission_id IS NULL AND mission_id IS NULL AND kind IN ('before', 'video')
         AND content_type <> 'invalid' AND key IN (${marksFor(add)}) AND ${inReview} RETURNING key`
    ).bind(prev.id, partner.id, ...add, prev.id, partner.id));
  }
  stmts.push(env.DB.prepare(
    `UPDATE missions SET place_name = ?, country = ?, lat = ?, lng = ?, task = ?, plan_date = ?, crew_size = ?,
       currency = ?, price_local = ?, crew_local = ?, private_note = ?
     WHERE id = ? AND partner_id = ? AND status = 'review' AND ${allOn} AND ${only}`
  ).bind(f.place_name, f.country, f.lat, f.lng, f.task, f.plan_date, f.crew_size, f.currency, f.price_local,
    f.crew_local, f.private_note, prev.id, partner.id, prev.id, ...f.keys, prev.id, ...known));
  if (drop.length) {
    stmts.push(env.DB.prepare(
      `UPDATE uploads SET mission_id = NULL WHERE mission_id = ? AND key IN (${marksFor(drop)}) AND ${inReview} AND ${allOn} AND ${only}`
    ).bind(prev.id, ...drop, prev.id, partner.id, prev.id, ...f.keys, prev.id, ...known));
  }
  const res = await env.DB.batch(stmts);
  if (!res[add.length ? 1 : 0].meta?.changes) {
    const mine = add.length ? (res[0].results || []).map((r) => r.key) : [];
    if (mine.length) {
      await env.DB.prepare(`UPDATE uploads SET mission_id = NULL WHERE mission_id = ? AND key IN (${marksFor(mine)})`)
        .bind(prev.id, ...mine).run();
    }
    const now = await env.DB.prepare("SELECT status FROM missions WHERE id = ?").bind(prev.id).first();
    return now?.status === "review" ? err(409, "Some photos were already used. Please try again.", { code: "media", field: "media" }) : refUsed();
  }
  return json({ id: prev.id, no: prev.no, repeated: true, updated: true });
}

const limitHit = () => err(429,
  `You already have ${MISSION_LIMITS.active} missions waiting, on sapu.earth or funded. Finish or withdraw one first.`, { code: "limit" });

async function create(env, partner, f) {
  // The phone sent this mission before but never got the answer.
  const again = await repeatedFor(env, partner, f);
  if (again) return again;

  const active = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM missions WHERE partner_id = ? AND status IN ('review', 'open', 'funded')"
  ).bind(partner.id).first();
  if ((active?.n ?? 0) >= MISSION_LIMITS.active) return limitHit();

  // Photos and video: files of this partner that are not part of a cleanup or a mission yet, 1 to 4
  // before photos and at most 1 video.
  const marks = f.keys.map(() => "?").join(",");
  const { results: rows } = await env.DB.prepare(
    `SELECT key, kind FROM uploads
     WHERE partner_id = ? AND submission_id IS NULL AND mission_id IS NULL AND content_type <> 'invalid' AND key IN (${marks})`
  ).bind(partner.id, ...f.keys).all();
  if (rows.length !== f.keys.length) {
    return err(400, "Some photos were not found or were already used. Please upload them again.", { code: "media", field: "media" });
  }
  const problem = mediaProblem(rows);
  if (problem) return problem;

  // One batch: the row (number and limit checked inside the INSERT, D1 runs writes one at a time,
  // so two posts cannot get the same number or both pass the limit), then the photos and video. The
  // UPDATE re-checks "unattached", so a racing cleanup or mission cannot share the files.
  const id = randomId(10);
  let res;
  try {
    res = await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO missions (id, no, client_ref, partner_id, status, place_name, country, lat, lng, task, plan_date,
           crew_size, currency, price_local, crew_local, private_note, consent, created_at)
         SELECT ?, (SELECT COALESCE(MAX(no), 0) + 1 FROM missions), ?, ?, 'review', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?
         WHERE (SELECT COUNT(*) FROM missions WHERE partner_id = ? AND status IN ('review', 'open', 'funded')) < ?`
      ).bind(id, f.client_ref, partner.id, f.place_name, f.country, f.lat, f.lng, f.task, f.plan_date,
        f.crew_size, f.currency, f.price_local, f.crew_local, f.private_note, nowIso(),
        partner.id, MISSION_LIMITS.active),
      env.DB.prepare(
        `UPDATE uploads SET mission_id = ?
         WHERE partner_id = ? AND submission_id IS NULL AND mission_id IS NULL AND kind IN ('before', 'video')
           AND content_type <> 'invalid' AND key IN (${marks})
           AND EXISTS (SELECT 1 FROM missions WHERE id = ? AND partner_id = ?)`
      ).bind(id, partner.id, ...f.keys, id, partner.id),
    ]);
  } catch (e) {
    // A racing retry with the same client_ref won the UNIQUE index: answer as for any resend.
    const won = noMissionsTable(e) ? null : await repeatedFor(env, partner, f).catch(() => null);
    if (won) return won;
    throw e;
  }

  if (!res[0].meta?.changes) {
    const won = await repeatedFor(env, partner, f);
    return won || limitHit();
  }
  if ((res[1].meta?.changes ?? f.keys.length) !== f.keys.length) {
    // Lost a race for a photo: undo (photos first, the row points nowhere after that) and ask to retry.
    await env.DB.batch([
      env.DB.prepare("UPDATE uploads SET mission_id = NULL WHERE mission_id = ?").bind(id),
      env.DB.prepare("DELETE FROM missions WHERE id = ?").bind(id),
    ]);
    return err(409, "Some photos were already used. Please try again.", { code: "media", field: "media" });
  }

  const row = await env.DB.prepare("SELECT no FROM missions WHERE id = ?").bind(id).first();
  return json({ id, no: row.no }, 201);
}

export const onRequestPost = handle(async ({ request, env }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);
  const f = readFields(await readJson(request));
  try {
    return await create(env, partner, f);
  } catch (e) {
    // Code deployed before migration 0004.
    if (noMissionsTable(e)) return err(503, "Missions are not open yet. Please try again later.", { code: "unavailable" });
    throw e;
  }
});

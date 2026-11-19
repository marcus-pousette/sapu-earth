// POST /api/admin/missions/decide {id, action, funded_eur, advance_pct, review_note, revision, video}
// revision: what the /admin/ list showed for this mission. PUBLISH and FUND answer 409 code changed when
// the crew changed the mission since (a mission in review can still take changes, see
// api/mission/index.js). video: the key of the video the card showed (null for none); with a revision,
// PUBLISH and FUND also answer 409 code changed when the mission has a video the card did not show, for
// example in an /admin/ tab opened before missions had videos. Without a revision they act as before.
// publish: review -> open (shown on the globe without funding).
// fund:    review or open -> funded. funded_eur is what we agreed to pay, advance_pct (0 to 100,
//          default 30) of it is sent now, the rest after the receipt. Answers advance_eur and rest_eur.
// decline: review or open -> removed (declined).
// remove:  open -> removed (cancelled).
// cancel:  funded -> removed (cancelled). The advance stays with the crew; the review note keeps
//          the money history.
// Removing deletes the now photos and video (R2 and their upload rows) and wipes the private note and
// the exact point in the same UPDATE. Every change is an UPDATE guarded by the expected status, so a
// double click or a second tab cannot apply it twice: that one gets 409.
import { HttpError, ID_RE, LIMITS, cleanText, err, handle, json, nowIso, num, readJson } from "../../../_lib/util.js";
import {
  MISSION_CONTENT, WIPE_PRIVATE, deleteMissionPhotos, missionRevision, missionShareUrl, noMissionsTable, nowMediaFor,
} from "../../../_lib/missions.js";

const ACTIONS = {
  publish: { from: ["review"], verb: "published" },
  fund: { from: ["review", "open"], verb: "funded" },
  decline: { from: ["review", "open"], why: "declined", verb: "declined" },
  remove: { from: ["open"], why: "cancelled", verb: "removed" },
  cancel: { from: ["funded"], why: "cancelled", verb: "cancelled" },
};
const STATUS_WORDS = { review: "waiting for review", open: "open", funded: "funded", done: "done", removed: "removed" };
const EUR = { min: 0, max: 1000000 };

const cents = (v) => Math.round(v * 100) / 100;
const marks = (a) => a.map(() => "?").join(", ");

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  if (typeof b.action !== "string" || !Object.prototype.hasOwnProperty.call(ACTIONS, b.action)) {
    return err(400, "action must be publish, fund, decline, remove or cancel.");
  }
  const act = ACTIONS[b.action];

  let m;
  try {
    m = await env.DB.prepare(
      "SELECT id, no, status, funded_eur, advance_eur, review_note FROM missions WHERE id = ?"
    ).bind(b.id).first();
  } catch (e) {
    if (noMissionsTable(e)) return err(503, "Missions are not set up yet. Run migration 0004 (see docs/upload-flow.md).", { code: "migration" });
    throw e;
  }
  if (!m) return err(404, "Mission not found.");
  const wrongState = () => err(409, `Mission #${m.no} is ${STATUS_WORDS[m.status] || m.status}, so it cannot be ${act.verb}. Reload the list.`, { code: "state" });
  if (!act.from.includes(m.status)) return wrongState();

  // PUBLISH makes the photos and video public and FUND decides money, so both act only on the version
  // Marcus saw: the same keys as the list, video included, and a video only when the card played it. The
  // revision alone cannot tell: an older admin.js gets the same revision but never shows the video.
  // The same check is repeated inside the UPDATE below (same, sameVals): the content columns as read here and the same
  // set of photo and video keys, so a resend from the crew that lands between this check and the UPDATE (a mission in
  // review takes changes for MISSION_LIMITS.editMinutes) changes nothing and gets the same 409.
  const changed = () => err(409, `The crew changed mission #${m.no} after this list was loaded. Check it again before you publish or fund it.`, { code: "changed" });
  let same = "", sameVals = [];
  if ((b.action === "publish" || b.action === "fund") && typeof b.revision === "string") {
    const cur = await env.DB.prepare(`SELECT ${MISSION_CONTENT.join(", ")} FROM missions WHERE id = ?`).bind(b.id).first();
    const rows = (await nowMediaFor(env, [b.id]))[b.id] || [];
    if (!cur || (await missionRevision(cur, rows.map((r) => r.key))) !== b.revision) return changed();
    if (rows.some((r) => r.kind === "video" && r.key !== b.video)) {
      return err(409, `Mission #${m.no} has a video this page does not show. Reload the page and watch it before you publish or fund it.`, { code: "changed" });
    }
    const keys = rows.map((r) => r.key);
    same = " AND " + MISSION_CONTENT.map((c) => `${c} IS ?`).join(" AND ") +
      " AND (SELECT COUNT(*) FROM uploads WHERE mission_id = ? AND submission_id IS NULL) = " + keys.length +
      (keys.length ? ` AND (SELECT COUNT(*) FROM uploads WHERE mission_id = ? AND submission_id IS NULL AND key IN (${marks(keys)})) = ${keys.length}` : "");
    sameVals = [...MISSION_CONTENT.map((c) => cur[c] ?? null), b.id, ...(keys.length ? [b.id, ...keys] : [])];
  }
  // Nothing changed: the state moved on, or (with a revision) the crew's resend came in between.
  const missed = async () => {
    if (!same) return wrongState();
    const st = await env.DB.prepare("SELECT status FROM missions WHERE id = ?").bind(b.id).first();
    return st && act.from.includes(st.status) ? changed() : wrongState();
  };

  let review_note = "review_note" in b
    ? cleanText(b.review_note, LIMITS.reviewNote, { field: "review_note", multiline: true })
    : m.review_note;
  const now = nowIso();
  const guard = `id = ? AND status IN (${marks(act.from)})`;

  if (b.action === "publish") {
    const r = await env.DB.prepare(
      `UPDATE missions SET status = 'open', published_at = COALESCE(published_at, ?), review_note = ? WHERE ${guard}${same}`
    ).bind(now, review_note, b.id, ...act.from, ...sameVals).run();
    if (!r.meta?.changes) return missed();
    return json({ id: b.id, no: m.no, status: "open", share_url: missionShareUrl(m.no) });
  }

  if (b.action === "fund") {
    const funded_eur = cents(num(b.funded_eur, { ...EUR, required: true, field: "funded_eur" }));
    if (!(funded_eur > 0)) throw new HttpError(400, "funded_eur must be more than 0.", undefined, "funded_eur");
    const pct = num(b.advance_pct, { min: 0, max: 100, field: "advance_pct" }) ?? 30;
    const advance_eur = Math.round(funded_eur * pct) / 100; // pct percent of it, in cents
    const rest_eur = cents(funded_eur - advance_eur);
    const r = await env.DB.prepare(
      `UPDATE missions SET status = 'funded', funded_eur = ?, advance_eur = ?, funded_at = ?,
         published_at = COALESCE(published_at, ?), review_note = ? WHERE ${guard}${same}`
    ).bind(funded_eur, advance_eur, now, now, review_note, b.id, ...act.from, ...sameVals).run();
    if (!r.meta?.changes) return missed();
    return json({ id: b.id, no: m.no, status: "funded", funded_eur, advance_eur, rest_eur, share_url: missionShareUrl(m.no) });
  }

  // decline, remove, cancel: the mission goes, with its now photos and video.
  if (b.action === "cancel") {
    // The money columns stay, and the note says what happened to the money.
    const line = `Cancelled ${now.slice(0, 10)}: agreed EUR ${cents(m.funded_eur ?? 0).toFixed(2)}, ` +
      `advance EUR ${cents(m.advance_eur ?? 0).toFixed(2)} sent and kept by the crew.`;
    const room = LIMITS.reviewNote - line.length - 1;
    review_note = review_note ? [...review_note].slice(0, Math.max(room, 0)).join("").trim() : "";
    review_note = review_note ? `${review_note}\n${line}` : line;
  }
  const r = await env.DB.prepare(
    `UPDATE missions SET status = 'removed', removed_why = ?, closed_at = ?, review_note = ?, ${WIPE_PRIVATE} WHERE ${guard}`
  ).bind(act.why, now, review_note, b.id, ...act.from).run();
  if (!r.meta?.changes) return wrongState();

  // The mission is removed now, so /media no longer serves its photos and video to the public even if R2 fails.
  let deleted_media = 0;
  try {
    deleted_media = await deleteMissionPhotos(env, b.id);
  } catch (e) {
    console.error("mission photos not deleted", b.id, e);
  }
  return json({ id: b.id, no: m.no, status: "removed", removed_why: act.why, deleted_media });
});

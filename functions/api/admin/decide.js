// POST /api/admin/decide
// {id, action: approve|reject, paid_eur, crew_eur, ops_eur, review_note, mission_id,
//  edits: {place_name, kg, sacks, crew_size, disposal, notes, lat, lng}}
// Reject deletes the media objects from R2 (and from the public bucket, if used).
// Approve copies the files to the public bucket PUBLIC_MEDIA when it is bound, so the site
// can load them from its custom domain (edge cached, no Function call per view).
// Missions: approving a cleanup sent for a funded mission marks the mission done. Rejecting a
// pending one leaves the mission funded (the crew can send it again). Rejecting an approved one
// (UNPUBLISH) removes the mission it completed, with its now photos, its private note and exact point.
// mission_id (approve only, optional): links a cleanup the crew sent with No mission to one of the
// same partner's funded missions that has no other pending or approved cleanup ("Link to mission"
// in PENDING). It is stored on the cleanup and the mission is marked done in the same batch.
// 400 when the cleanup already has another mission, or the mission is not this partner's or not
// funded; 409 when another cleanup is sent for it, or it changed meanwhile. A mission with several spots (docs/missions.md,
// Spots) takes no link: 400, since a cleanup sent without a mission has no photos for its other spots.
// Post links and thanks (docs/upload-flow.md, Post links and thanks): REJECT and UNPUBLISH delete the cleanup's post_links
// row and its thanks in their own batch (dropReceiptSocial in _lib/social.js), so a rejected cleanup never keeps a link
// or a count, and the site's day counts lose its thanks. Before migration 0007 the batch runs without them.
import {
  HttpError, ID_RE, LIMITS, cleanText, err, handle, json, nowIso, num, readJson,
} from "../../_lib/util.js";
import { WIPE_PRIVATE, deleteMissionPhotos, noMissionsTable } from "../../_lib/missions.js";
import { dropReceiptSocial, withSocial } from "../../_lib/social.js";
import { extraSpots, withSpots } from "../../_lib/spots.js";

const EUR = { min: 0, max: 1000000 };

async function copyToPublic(env, key) {
  const obj = await env.MEDIA.get(key);
  if (!obj) return false;
  const body = typeof FixedLengthStream === "function" ? obj.body.pipeThrough(new FixedLengthStream(obj.size)) : await obj.arrayBuffer();
  await env.PUBLIC_MEDIA.put(key, body, {
    httpMetadata: { contentType: obj.httpMetadata?.contentType, cacheControl: "public, max-age=86400" },
  });
  return true;
}

// The mission an approve links a cleanup without one to (b.mission_id), checked, or null when there
// is nothing to link. Sending the mission the cleanup already has is fine and links nothing new.
async function linkTarget(env, sub, b) {
  const want = b.mission_id === undefined || b.mission_id === null || b.mission_id === "" ? null : b.mission_id;
  if (want === null || want === sub.mission_id) return null;
  if (typeof want !== "string" || !ID_RE.test(want)) throw new HttpError(400, "Invalid mission_id.", "mission", "mission_id");
  if (sub.mission_id) throw new HttpError(400, "This cleanup was already sent for another mission.", "mission", "mission_id");
  let m;
  try {
    m = await withSpots((sp) => env.DB.prepare(
      `SELECT partner_id, status, ${sp ? "spots" : "NULL AS spots"},
         (SELECT COUNT(*) FROM submissions WHERE mission_id = ?1 AND id <> ?2 AND status IN ('pending', 'approved')) AS taken
       FROM missions WHERE id = ?1`
    ).bind(want, sub.id).first());
  } catch (e) {
    if (noMissionsTable(e)) throw new HttpError(503, "Missions are not set up yet. Run migration 0004 (see docs/upload-flow.md).", "migration");
    throw e;
  }
  if (!m || m.partner_id !== sub.partner_id || m.status !== "funded") {
    throw new HttpError(400, "A cleanup can only be linked to a funded mission of the same partner.", "mission", "mission_id");
  }
  if (m.taken) throw new HttpError(409, "Another cleanup was already sent for this mission. Reload the list.", "mission", "mission_id");
  if (extraSpots(m.spots).length) {
    throw new HttpError(400, "This mission has several spots. The crew sends its cleanup from the mission's card, with photos for each spot.", "mission", "mission_id");
  }
  return want;
}

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  if (!["approve", "reject"].includes(b.action)) return err(400, "action must be approve or reject.");

  const sub = await env.DB.prepare("SELECT * FROM submissions WHERE id = ?").bind(b.id).first();
  if (!sub) return err(404, "Submission not found.");
  const review_note = "review_note" in b
    ? cleanText(b.review_note, LIMITS.reviewNote, { field: "review_note", multiline: true })
    : sub.review_note;

  if (b.action === "reject") {
    if (sub.status === "rejected") return err(409, "Already rejected.");
    const { results } = await env.DB.prepare("SELECT key FROM uploads WHERE submission_id = ?").bind(b.id).all();
    const keys = results.map((r) => r.key);
    if (keys.length) {
      await env.MEDIA.delete(keys);
      if (env.PUBLIC_MEDIA) await env.PUBLIC_MEDIA.delete(keys);
    }
    const now = nowIso();
    const stmts = [
      env.DB.prepare("DELETE FROM uploads WHERE submission_id = ?").bind(b.id),
      env.DB.prepare("UPDATE submissions SET status = 'rejected', review_note = ?, reviewed_at = ? WHERE id = ?")
        .bind(review_note, now, b.id),
    ];
    // sub.mission_id only exists after migration 0004; before it this is undefined and skipped.
    const unpublish = sub.status === "approved" && sub.mission_id;
    if (unpublish) {
      stmts.push(env.DB.prepare(
        `UPDATE missions SET status = 'removed', removed_why = 'unpublished', closed_at = ?, ${WIPE_PRIVATE}
         WHERE id = ? AND status = 'done' AND submission_id = ?`
      ).bind(now, sub.mission_id, b.id));
    }
    // The links and thanks come after the mission statement, so res[2] stays the mission's.
    const res = await withSocial((social) => env.DB.batch(social ? [...stmts, ...dropReceiptSocial(env, b.id)] : stmts));
    const out = { id: b.id, status: "rejected", deleted_media: keys.length };
    if (unpublish && res[2].meta?.changes) {
      let deleted = 0;
      try {
        deleted = await deleteMissionPhotos(env, sub.mission_id);
      } catch (e) {
        console.error("mission photos not deleted", sub.mission_id, e);
      }
      out.mission = { id: sub.mission_id, status: "removed", deleted_media: deleted };
    }
    return json(out);
  }

  if (sub.status === "rejected") return err(409, "Rejected submissions cannot be approved (their media is deleted).");

  // Money in EUR, all optional. Keep existing values when a field is not sent.
  const pickEur = (k) => (k in b ? num(b[k], { ...EUR, field: k }) : sub[k]);
  const paid_eur = pickEur("paid_eur");
  const crew_eur = pickEur("crew_eur");
  const ops_eur = pickEur("ops_eur");
  if (paid_eur === null && (crew_eur !== null || ops_eur !== null)) {
    throw new HttpError(400, "Set paid_eur when you set crew_eur or ops_eur.");
  }

  // Optional edits to what the partner sent.
  const e = b.edits && typeof b.edits === "object" ? b.edits : {};
  const has = (k) => Object.prototype.hasOwnProperty.call(e, k);
  const v = {
    place_name: has("place_name") ? cleanText(e.place_name, LIMITS.place, { required: true, field: "place_name" }) : sub.place_name,
    kg: has("kg") ? num(e.kg, { min: 0, max: 100000, field: "kg" }) : sub.kg,
    sacks: has("sacks") ? num(e.sacks, { min: 0, max: 10000, int: true, field: "sacks" }) : sub.sacks,
    crew_size: has("crew_size") ? num(e.crew_size, { min: 1, max: 1000, int: true, required: true, field: "crew_size" }) : sub.crew_size,
    disposal: has("disposal") ? cleanText(e.disposal, LIMITS.disposal, { field: "disposal" }) : sub.disposal,
    notes: has("notes") ? cleanText(e.notes, LIMITS.notes, { field: "notes", multiline: true }) : sub.notes,
    lat: has("lat") ? num(e.lat, { min: -90, max: 90, field: "lat" }) : sub.lat,
    lng: has("lng") ? num(e.lng, { min: -180, max: 180, field: "lng" }) : sub.lng,
  };
  if ((v.lat === null) !== (v.lng === null)) throw new HttpError(400, "lat and lng must be set together.");
  if (!(v.kg > 0) && !(v.sacks > 0)) throw new HttpError(400, "Keep the kg or the number of sacks.");
  const link = await linkTarget(env, sub, b);

  const now = nowIso();
  const set = `UPDATE submissions SET status = 'approved', paid_eur = ?, crew_eur = ?, ops_eur = ?, review_note = ?, reviewed_at = ?,
         place_name = ?, kg = ?, sacks = ?, crew_size = ?, disposal = ?, notes = ?, lat = ?, lng = ?`;
  const vals = [paid_eur, crew_eur, ops_eur, review_note, now,
    v.place_name, v.kg, v.sacks, v.crew_size, v.disposal, v.notes, v.lat, v.lng];
  // Both UPDATEs also require the status this request read (pending, or approved for a second APPROVE that fixes a
  // typo), so an APPROVE that races a REJECT or UNPUBLISH from another tab changes nothing (409 below) instead of
  // publishing a cleanup whose photos were just deleted.
  const stmts = [link
    // Linking: the mission is checked again inside the UPDATE. If it was cancelled or another
    // cleanup took it meanwhile, nothing is approved (409 below).
    ? env.DB.prepare(
      `${set}, mission_id = ?
       WHERE id = ? AND status = ? AND mission_id IS NULL
         AND EXISTS (SELECT 1 FROM missions WHERE id = ? AND partner_id = ? AND status = 'funded')
         AND NOT EXISTS (SELECT 1 FROM submissions o WHERE o.mission_id = ? AND o.id <> ? AND o.status IN ('pending', 'approved'))`
    ).bind(...vals, link, b.id, sub.status, link, sub.partner_id, link, b.id)
    : env.DB.prepare(`${set} WHERE id = ? AND status = ?`).bind(...vals, b.id, sub.status)];
  // A cleanup sent for (or linked to) a mission completes it, in the same batch, so the receipt and
  // the mission never disagree. Only a funded mission: one cancelled meanwhile stays removed, and
  // approving again (to fix a typo) leaves a done mission as it is. Only when the cleanup carries the
  // mission after the first statement, so a link that did not apply never completes it.
  const missionId = sub.mission_id || link;
  if (missionId) {
    stmts.push(env.DB.prepare(
      `UPDATE missions SET status = 'done', submission_id = ?, closed_at = ? WHERE id = ? AND status = 'funded'
         AND EXISTS (SELECT 1 FROM submissions WHERE id = ? AND mission_id = ? AND status = 'approved')`
    ).bind(b.id, now, missionId, b.id, missionId));
  }
  const res = await env.DB.batch(stmts);
  if (!res[0].meta?.changes) {
    const st = await env.DB.prepare("SELECT status FROM submissions WHERE id = ?").bind(b.id).first();
    if (!st || st.status !== sub.status) {
      return err(409, "This cleanup changed meanwhile (rejected, unpublished or approved in another tab). Reload the list.", { code: "state" });
    }
    if (link) {
      return err(409, "The mission changed meanwhile (cancelled, or another cleanup was sent for it). Reload the list.",
        { code: "mission", field: "mission_id" });
    }
    return err(409, "Nothing was approved. Reload the list.", { code: "state" });
  }

  // The public bucket gets the files once the cleanup is approved (until then /media/<key> serves them, signed).
  if (env.PUBLIC_MEDIA) {
    const { results } = await env.DB.prepare("SELECT key FROM uploads WHERE submission_id = ? AND public = 0").bind(b.id).all();
    for (const { key } of results) {
      try {
        if (await copyToPublic(env, key)) await env.DB.prepare("UPDATE uploads SET public = 1 WHERE key = ?").bind(key).run();
      } catch (e) {
        console.error("copy to public bucket failed", key, e); // falls back to /media/<key>
      }
    }
  }

  const out = { id: b.id, status: "approved" };
  if (missionId) {
    const m = await env.DB.prepare("SELECT no, status FROM missions WHERE id = ?").bind(missionId).first();
    out.mission = m ? { id: missionId, no: m.no, status: m.status } : null;
  }
  return json(out);
});

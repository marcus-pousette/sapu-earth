// POST /api/mission/withdraw?k=TOKEN  {id} -> {id, status: 'removed', deleted_media}
// The crew takes back its own mission while it is in review or open. Its now photos and video are
// deleted (rows, then R2), its private note and exact point are wiped. A funded, done or already removed
// mission answers 409, someone else's 404.
import { ID_RE, err, handle, json, noBindings, nowIso, readJson, requirePartner } from "../../_lib/util.js";
import { WIPE_PRIVATE, deleteMissionPhotos, noMissionsTable } from "../../_lib/missions.js";

const notFound = () => err(404, "Mission not found.", { code: "not_found" });

export const onRequestPost = handle(async ({ request, env }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.", { field: "id" });

  let r;
  try {
    // The status guard makes a race with FUND safe: whichever runs first wins, the other gets 409.
    r = await env.DB.prepare(
      `UPDATE missions SET status = 'removed', removed_why = 'withdrawn', closed_at = ?, ${WIPE_PRIVATE}
       WHERE id = ? AND partner_id = ? AND status IN ('review', 'open')`
    ).bind(nowIso(), b.id, partner.id).run();
  } catch (e) {
    if (noMissionsTable(e)) return notFound(); // before migration 0004 there are no missions
    throw e;
  }
  if (!r.meta?.changes) {
    const m = await env.DB.prepare("SELECT status FROM missions WHERE id = ? AND partner_id = ?").bind(b.id, partner.id).first();
    if (!m) return notFound();
    return err(409, m.status === "removed"
      ? "This mission was already removed."
      : "A funded or finished mission cannot be withdrawn. Please write to Sapu Earth.", { code: "state", status: m.status });
  }

  // The mission is withdrawn either way. If deleting the photos and video fails, they are no longer
  // public (/media/ only serves the files of open, funded and done missions).
  let deleted = 0;
  try {
    deleted = await deleteMissionPhotos(env, b.id);
  } catch (e) {
    console.error("withdraw photo delete", b.id, e);
  }
  return json({ id: b.id, status: "removed", removed_why: "withdrawn", deleted_media: deleted });
});

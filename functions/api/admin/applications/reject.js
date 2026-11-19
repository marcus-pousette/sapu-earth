// POST /api/admin/applications/reject {id}
// Deletes a new application, its photos and its logo for good. Approved applications stay.
// The answer: {deleted: true, deleted_photos, deleted_logo}.
import { ID_RE, err, handle, json, keyList, nowIso, readJson } from "../../../_lib/util.js";
import { withLogos } from "../../../_lib/logos.js";

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  const app = await env.DB.prepare("SELECT status, photos FROM applications WHERE id = ?").bind(b.id).first();
  if (!app) return err(404, "Application not found.");
  if (app.status !== "new") return err(409, "Only new applications can be rejected.");

  // The logo sent with it, if any (none before migration 0006), is claimed before its file is touched: it becomes
  // gone, so an APPROVE AND CREATE PARTNER of the same application in another tab can no longer make it live (that
  // takes a waiting logo). If that approval came first, nothing is claimed and the live file stays. A retry claims
  // the same row again (any status), so a failed R2 delete is never lost.
  const logoKeys = await withLogos(async (on) => (on
    ? ((await env.DB.prepare(
        `UPDATE logos SET status = 'gone', decided_at = ?2
         WHERE application_id = ?1 AND partner_id IS NULL AND EXISTS (SELECT 1 FROM applications WHERE id = ?1 AND status = 'new')
         RETURNING key`
      ).bind(b.id, nowIso()).all()).results || [])
      .map((x) => x.key).filter((k) => typeof k === "string")
    : []));

  // Files first: if this fails, the rows (and the list of keys) are still there for a retry.
  const keys = keyList(app.photos);
  if (keys.length || logoKeys.length) await env.MEDIA.delete([...keys, ...logoKeys]);
  // Without a logo row this runs the one statement it always ran, so it also works before migration 0006.
  const drop = env.DB.prepare("DELETE FROM applications WHERE id = ? AND status = 'new'").bind(b.id);
  let r;
  if (!logoKeys.length) {
    r = await drop.run();
  } else {
    [, r] = await env.DB.batch([
      env.DB.prepare(
        "DELETE FROM logos WHERE application_id = ?1 AND partner_id IS NULL AND EXISTS (SELECT 1 FROM applications WHERE id = ?1 AND status = 'new')"
      ).bind(b.id),
      drop,
    ]);
  }
  if (!r.meta?.changes) return err(409, "Already decided.");

  return json({ deleted: true, deleted_photos: keys.length, deleted_logo: logoKeys.length });
});

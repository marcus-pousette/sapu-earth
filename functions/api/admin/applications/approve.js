// POST /api/admin/applications/approve {id, name, url, country, slug, logo}
// Creates the partner (same rules as POST /api/admin/partners), marks the application approved
// and deletes its photos. The upload link in the response is shown ONCE.
// The photo keys stay on the row until R2 has deleted them, so a failed delete is retried by the
// application cleanup (functions/_lib/applications.js) instead of leaving photos nobody can find.
// logo: the crew's logo sent with the application, decided in the same tap (docs/upload-flow.md, Crew logos).
// Its key (the box "Show this logo on sapu.earth" ticked): live at once, or gone when its file is missing. null
// (the box unticked): declined, file deleted, and the crew page asks for another one. No logo property (an /admin/
// tab from before logos) or another key: it stays waiting, now as the partner's, under PARTNERS, LOGOS TO CHECK.
// The answer adds logo: the status the logo got, or null when the application had none (or before migration 0006,
// when this writes nothing to the logos table).
import { ID_RE, err, handle, json, keyList, nowIso, readJson } from "../../../_lib/util.js";
import { createPartner } from "../../../_lib/partners.js";
import { dropLogoFiles, withLogos } from "../../../_lib/logos.js";

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  const app = await env.DB.prepare(
    "SELECT id, status, lang, contact_name, org_name, whatsapp, email, photos FROM applications WHERE id = ?"
  ).bind(b.id).first();
  if (!app) return err(404, "Application not found.");
  if (app.status !== "new") return err(409, "Already decided.");

  // The application's logo, and what it becomes. Read before the partner exists, so nothing waits on R2 after it.
  const logoRow = await withLogos((on) => (on
    ? env.DB.prepare("SELECT key FROM logos WHERE application_id = ? AND partner_id IS NULL AND status = 'review'").bind(b.id).first()
    : null));
  let st = null;
  if (logoRow) {
    st = b.logo === null ? "declined"
      : b.logo === logoRow.key ? ((await env.MEDIA.head(logoRow.key)) ? "live" : "gone")
      : "review";
  }

  const partner = await createPartner(env, { name: b.name, url: b.url, country: b.country, slug: b.slug });

  // If the application was decided meanwhile (another approve or a reject), or the update fails,
  // nobody has seen this token yet, so the partner is removed again.
  const dropPartner = () => env.DB.prepare("DELETE FROM partners WHERE id = ?").bind(partner.id).run();
  const now = nowIso();
  const approve = env.DB.prepare(
    "UPDATE applications SET status = 'approved', partner_id = ?, decided_at = ?, ip_hash = '' WHERE id = ? AND status = 'new'"
  ).bind(partner.id, now, b.id);
  let r, moved = false;
  try {
    if (logoRow) {
      // One batch: the logo moves to the partner only together with the approval.
      const [r1, r2] = await env.DB.batch([approve, env.DB.prepare(
        `UPDATE logos SET partner_id = ?1, status = ?2, decided_at = ?3
         WHERE key = ?4 AND application_id = ?5 AND partner_id IS NULL AND status = 'review'
           AND EXISTS (SELECT 1 FROM applications WHERE id = ?5 AND status = 'approved' AND partner_id = ?1)`
      ).bind(partner.id, st, st === "review" ? null : now, logoRow.key, b.id)]);
      r = r1;
      moved = !!r2.meta?.changes;
    } else {
      r = await approve.run();
    }
  } catch (e) {
    await dropPartner().catch((e2) => console.error("approve undo", partner.id, e2));
    throw e;
  }
  if (!r.meta?.changes) {
    await dropPartner();
    return err(409, "Already decided.");
  }
  if (moved && (st === "declined" || st === "gone")) await dropLogoFiles(env, [logoRow.key]);

  // The partner exists now and its link is shown only in this response, so a failed
  // photo delete must not turn it into an error. The list is cleared only after R2 deleted them.
  const keys = keyList(app.photos);
  let deleted = 0;
  if (app.photos !== "[]") {
    try {
      if (keys.length) await env.MEDIA.delete(keys);
      deleted = keys.length;
      await env.DB.prepare("UPDATE applications SET photos = '[]' WHERE id = ?").bind(app.id).run();
    } catch (e) {
      console.error("application photos not deleted yet, the cleanup retries", app.id, keys, e);
    }
  }

  return json({
    partner,
    application: {
      id: app.id, lang: app.lang, contact_name: app.contact_name, org_name: app.org_name,
      whatsapp: app.whatsapp, email: app.email,
    },
    deleted_photos: deleted,
    logo: moved ? st : null,
  }, 201);
});

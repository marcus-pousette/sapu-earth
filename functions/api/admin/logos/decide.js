// POST /api/admin/logos/decide {key, action}: LOGOS TO CHECK and REMOVE LOGO in /admin/ (docs/upload-flow.md, Crew logos).
// approve: a waiting logo goes live next to the crew's name at once, and the crew's live logo before it is gone (file
//          deleted). 200 {key, status: "live", partner_id, replaced: the old live key or null}.
// decline: a waiting logo is declined and its file deleted; the crew page asks for another one.
// remove:  a live logo is taken off sapu.earth the same way. Both answer 200 {key, status: "declined", partner_id}.
// Only a crew's logo: one sent with an open application is decided with the application. Every change is guarded by
// the state it was asked for, so a double click or two tabs answer 409 code state instead of deciding twice; 409 code
// inactive when the crew is deactivated, code missing when approve finds no file. 503 code migration before 0006.
import { KEY_RE, err, handle, json, nowIso, readJson } from "../../../_lib/util.js";
import { dropLogoFiles, withLogos } from "../../../_lib/logos.js";

const ACTIONS = ["approve", "decline", "remove"];
const decided = () => err(409, "This logo was already decided or replaced.", { code: "state" });

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.key !== "string" || !KEY_RE.test(b.key) || !ACTIONS.includes(b.action)) return err(400, "Invalid key or action.");
  const found = await withLogos(async (on) => (on
    ? { row: await env.DB.prepare(
        "SELECT l.key, l.partner_id, l.status, p.active FROM logos l LEFT JOIN partners p ON p.id = l.partner_id WHERE l.key = ?"
      ).bind(b.key).first() }
    : null));
  if (!found) return err(503, "Logos are not set up yet. Run migration 0006 (docs/upload-flow.md).", { code: "migration" });
  const row = found.row;
  if (!row || !row.partner_id) return err(404, "Logo not found.");
  if (Number(row.active) !== 1) return err(409, "This crew is deactivated.", { code: "inactive" });
  const now = nowIso();

  if (b.action === "approve") {
    if (!(await env.MEDIA.head(b.key))) {
      return err(409, "The file of this logo is missing. DECLINE it, the crew can send it again.", { code: "missing" });
    }
    // The crew's live logo goes first (one live per crew), and only while this one still waits and the crew is active.
    const [old, made] = await env.DB.batch([
      env.DB.prepare(
        `UPDATE logos SET status = 'gone', decided_at = ?1 WHERE partner_id = ?2 AND status = 'live'
           AND EXISTS (SELECT 1 FROM logos x JOIN partners p ON p.id = x.partner_id
                       WHERE x.key = ?3 AND x.partner_id = ?2 AND x.status = 'review' AND p.active = 1)
         RETURNING key`
      ).bind(now, row.partner_id, b.key),
      env.DB.prepare(
        `UPDATE logos SET status = 'live', decided_at = ?1 WHERE key = ?3 AND partner_id = ?2 AND status = 'review'
           AND EXISTS (SELECT 1 FROM partners WHERE id = ?2 AND active = 1)`
      ).bind(now, row.partner_id, b.key),
    ]);
    if (!made.meta?.changes) return decided();
    const replaced = (old.results || []).map((r) => r.key);
    await dropLogoFiles(env, replaced);
    return json({ key: b.key, status: "live", partner_id: row.partner_id, replaced: replaced[0] || null });
  }

  const from = b.action === "decline" ? "review" : "live";
  const { results } = await env.DB.prepare(
    "UPDATE logos SET status = 'declined', decided_at = ?1 WHERE key = ?2 AND partner_id IS NOT NULL AND status = ?3 RETURNING key"
  ).bind(now, b.key, from).all();
  if (!results || !results.length) return decided();
  await dropLogoFiles(env, [b.key]);
  return json({ key: b.key, status: "declined", partner_id: row.partner_id });
});

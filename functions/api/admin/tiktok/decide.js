// POST /api/admin/tiktok/decide {partner_id, account, action}: TIKTOK TO CHECK and REMOVE TIKTOK in /admin/
// (docs/upload-flow.md, Crew TikTok accounts).
// approve: the waiting account goes live at once, in place of the live one: 200 {partner_id, account, status: "live"}.
// decline: the waiting account is dropped (not kept), and the crew page says Sapu Earth is not showing it.
// remove:  the live account comes off sapu.earth the same way. Both answer 200 {partner_id, account, status: "declined"}.
// account is the one Marcus saw. Every change is guarded by it, so a crew that sent another one meanwhile, a double
// click or a second tab answer 409 code state instead of deciding on an account Marcus did not see; 409 code inactive
// for a deactivated crew; 404 for an unknown crew; 503 code migration before migration 0009.
import { ID_RE, err, handle, json, nowIso, readJson } from "../../../_lib/util.js";
import { accountOf, withTiktok } from "../../../_lib/tiktok.js";

const ACTIONS = ["approve", "decline", "remove"];

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  const account = accountOf(b.account);
  if (typeof b.partner_id !== "string" || !ID_RE.test(b.partner_id) || !account || !ACTIONS.includes(b.action)) {
    return err(400, "Invalid partner, account or action.");
  }
  // The join only makes this read fail before migration 0009, so that case answers 503.
  const found = await withTiktok(async (on) => (on
    ? { row: await env.DB.prepare("SELECT p.active FROM partners p LEFT JOIN crew_tiktok t ON t.partner_id = p.id WHERE p.id = ?").bind(b.partner_id).first() }
    : null));
  if (!found) return err(503, "TikTok accounts are not set up yet. Run migration 0009 (docs/upload-flow.md).", { code: "migration" });
  if (!found.row) return err(404, "Partner not found.");
  if (Number(found.row.active) !== 1) return err(409, "This crew is deactivated.", { code: "inactive" });

  // D1 refuses bindings a statement does not use, so approve binds two and the others three.
  const st = b.action === "approve"
    ? env.DB.prepare(
        `UPDATE crew_tiktok SET live = review, review = NULL, sent_at = NULL, declined_at = NULL
         WHERE partner_id = ?1 AND review = ?2 AND EXISTS (SELECT 1 FROM partners WHERE id = ?1 AND active = 1)`
      ).bind(b.partner_id, account)
    : env.DB.prepare(b.action === "decline"
        ? "UPDATE crew_tiktok SET review = NULL, sent_at = NULL, declined_at = ?3 WHERE partner_id = ?1 AND review = ?2"
        : "UPDATE crew_tiktok SET live = NULL, declined_at = ?3 WHERE partner_id = ?1 AND live = ?2"
      ).bind(b.partner_id, account, nowIso());
  const r = await st.run();
  if (!r.meta?.changes) return err(409, "This TikTok account was already decided or changed.", { code: "state" });
  return json({ partner_id: b.partner_id, account, status: b.action === "approve" ? "live" : "declined" });
});

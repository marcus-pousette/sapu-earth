// POST /api/tiktok?k=TOKEN {account} -> 200 {tiktok: the crew page's state, as GET /api/partner has it}
// docs/upload-flow.md, Crew TikTok accounts. account is the crew's TikTok account as typed or pasted on its crew page
// (YOUR TIKTOK): its name or the link to its profile, read by the same block as the page's (tiktokAccount in
// functions/_lib/tiktok.js). It waits for Marcus and shows nowhere until APPROVE TIKTOK in /admin/; a newer one replaces
// the one waiting, while the live one stays until Marcus approves the newer one. The account already live clears what
// waits. An empty account (or null) takes the crew's TikTok off sapu.earth at once, the waiting one too: taking
// something down needs no check.
// Errors are {error, code}: 405, 404 (the link), 400 (not a JSON object; code tiktok: not an account; code short: a
// short link, which names no account), 413 for a body over 2 KB, 503 code migration before migration 0009.
import { err, handle, json, noBindings, nowIso, readJson, requirePartner } from "../_lib/util.js";
import { SEND_TIKTOK, tiktokAccount, tiktokStateFor, withTiktok } from "../_lib/tiktok.js";

export const onRequest = handle(async ({ request, env }) => {
  if (request.method !== "POST") return json({ error: "Use POST." }, 405, { allow: "POST" });
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);
  const b = await readJson(request, 2048);
  if (b.account !== undefined && b.account !== null && typeof b.account !== "string") {
    return err(400, "account must be text.", { code: "tiktok" });
  }
  const text = typeof b.account === "string" ? b.account.trim() : "";
  let account = null;
  if (text) {
    const t = tiktokAccount(text);
    if (t && t.short) return err(400, "Short links cannot be checked. Type your TikTok name instead, like @sapu.earth.", { code: "short" });
    if (!t || !t.account) return err(400, "This is not a TikTok account. Type your TikTok name, like @sapu.earth.", { code: "tiktok" });
    account = t.account;
  }
  const done = await withTiktok(async (on) => {
    if (!on) return false;
    if (account) await env.DB.prepare(SEND_TIKTOK).bind(partner.id, account, nowIso()).run();
    else await env.DB.prepare("DELETE FROM crew_tiktok WHERE partner_id = ?").bind(partner.id).run();
    return true;
  });
  if (!done) return err(503, "TikTok accounts are not set up yet.", { code: "migration" });
  return json({ tiktok: await tiktokStateFor(env, partner.id) });
});

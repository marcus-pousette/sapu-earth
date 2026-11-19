// POST /api/admin/partners/rotate {id} -> new token + upload link (shown once). The old link stops working.
import { ID_RE, SITE, err, handle, json, randomToken, readJson, sha256Hex } from "../../../_lib/util.js";

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  const token = randomToken();
  const r = await env.DB.prepare("UPDATE partners SET token_hash = ? WHERE id = ? AND active = 1")
    .bind(await sha256Hex(token), b.id).run();
  if (!r.meta?.changes) return err(404, "Partner not found or deactivated.");
  return json({ id: b.id, token, upload_url: `${SITE}/upload/?k=${token}` });
});

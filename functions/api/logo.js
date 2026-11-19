// POST /api/logo?k=TOKEN  raw body: the crew's logo, one square JPEG made by the crew page (toLogoJpeg in
// upload/upload.js) -> 201 {logo: the crew page's logo state, as GET /api/partner has it}.
// docs/upload-flow.md, Crew logos. The logo waits for Marcus (status review) and shows nowhere until APPROVE LOGO in
// /admin/. A logo sent while another one waits replaces it: the waiting one is gone and its file deleted.
// Checks: JPEG only, at most LOGO.maxBytes, and exactly what cleanJpeg leaves of a canvas JPEG, square, 128 to 640 px
// (logoJpegInfo in functions/_lib/logos.js): no Exif, no XMP, nothing after the image. The picture is never decoded.
// At most LOGO.perDay logos per crew per 24 h, every status counted, checked inside the INSERT itself.
// The file is written before its row, so a waiting row always has its file and APPROVE never makes a missing file
// live. Known gap: a Worker killed between the write and the batch leaves one file of at most 150 KB with no row. It
// is never served (no row, no signature for it) and never found again, the same trade as an interrupted upload.
// Before migration 0006 it answers 503 code migration, and the crew page hides YOUR LOGO.
// Errors are {error, code}: 405, 404 (the link), 415 type, 411 and 413 and 400 size, 415 logo, 429 limit.
import { err, handle, json, noBindings, nowIso, randomHex, requirePartner } from "../_lib/util.js";
import { LOGO, dropLogoFiles, logoJpegInfo, logoStateFor, withLogos } from "../_lib/logos.js";

export const onRequest = handle(async ({ request, env, waitUntil }) => {
  if (request.method !== "POST") return json({ error: "Use POST." }, 405, { allow: "POST" });
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);

  const type = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (type !== "image/jpeg") return err(415, "Logos must be JPEG. Choose your logo on your crew page, it prepares it.", { code: "type" });
  const lenHeader = request.headers.get("content-length");
  const size = lenHeader === null ? NaN : Number(lenHeader);
  if (!Number.isInteger(size) || size < 1) return err(411, "The logo needs a Content-Length.", { code: "size" });
  if (size > LOGO.maxBytes) return err(413, "The logo is too large (max 150 KB).", { code: "size" });
  let bytes;
  try {
    bytes = new Uint8Array(await request.arrayBuffer());
  } catch {
    bytes = null; // the connection dropped halfway
  }
  if (!bytes || bytes.length !== size) return err(400, "The logo did not arrive whole. Please try again.", { code: "size" });
  if (!logoJpegInfo(bytes)) {
    return err(415, "This is not a logo prepared by the crew page (a square JPEG without camera data).", { code: "logo" });
  }

  const now = nowIso();
  const since = new Date(Date.parse(now) - 86400000).toISOString();
  const used = await withLogos(async (on) => {
    if (!on) return null;
    const r = await env.DB.prepare("SELECT COUNT(*) AS n FROM logos WHERE partner_id = ? AND created_at > ?").bind(partner.id, since).first();
    return Number(r?.n) || 0;
  });
  if (used === null) return err(503, "Logos are not set up yet.", { code: "migration" });
  if (used >= LOGO.perDay) return err(429, "Too many logos today. Please try again tomorrow.", { code: "limit" });

  // The file first, then one batch: the waiting logo (if any) is gone and the new one waits, both only while the
  // crew is under its daily limit, so two sends at once can never pass it. waitUntil keeps this going when the phone
  // drops the connection halfway, so a cut request cannot leave a row without its file.
  const key = randomHex(16);
  const store = (async () => {
    await env.MEDIA.put(key, bytes, { httpMetadata: { contentType: "image/jpeg" } });
    const under = "(SELECT COUNT(*) FROM logos WHERE partner_id = ?2 AND created_at > ?3) < ?4";
    let res;
    try {
      res = await env.DB.batch([
        env.DB.prepare(
          `UPDATE logos SET status = 'gone', decided_at = ?1 WHERE partner_id = ?2 AND status = 'review' AND ${under} RETURNING key`
        ).bind(now, partner.id, since, LOGO.perDay),
        env.DB.prepare(
          `INSERT INTO logos (key, partner_id, status, created_at) SELECT ?5, ?2, 'review', ?1 WHERE ${under}`
        ).bind(now, partner.id, since, LOGO.perDay, key),
      ]);
    } catch (e) {
      await env.MEDIA.delete(key).catch((e2) => console.error("logo file not deleted", key, e2));
      throw e;
    }
    if (!res[1].meta?.changes) {
      await env.MEDIA.delete(key).catch((e2) => console.error("logo file not deleted", key, e2));
      return false;
    }
    await dropLogoFiles(env, (res[0].results || []).map((r) => r.key));
    return true;
  })();
  waitUntil?.(store.catch(() => {}));
  if (!(await store)) return err(429, "Too many logos today. Please try again tomorrow.", { code: "limit" });

  return json({ logo: await logoStateFor(env, partner.id, partner.name) }, 201);
});

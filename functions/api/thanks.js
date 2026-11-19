// POST /api/thanks {id} -> 200 {thanks, counted}: one thank you for a published receipt, from SAY TERIMA KASIH (SAY THANK
// YOU) in its post on the homepage (docs/upload-flow.md, Thanks). countThanks in _lib/social.js counts it within the
// caps (THANKS) in one batch; counted false says a cap, or an undo of that day, stopped it, and thanks is the receipt's
// standing count either way. 404 code receipt when the id is not an approved receipt (never one, or unpublished), 409
// code inactive for a receipt of a crew Sapu Earth no longer works with (the receipt stays on sapu.earth with its count
// and takes no new thanks, so the post can say so instead of calling it gone), 503 code migration before migration 0007.
// Only from sapu.earth's own pages: the Origin header must be this site's, and Sec-Fetch-Site, when the browser sends
// it, same-origin (403 code origin). The body must be JSON (415 code type): an HTML form on another site cannot send that
// type, and another site's script would need a CORS preflight, which gets 405 here like every method but POST, with no
// Access-Control-Allow-Origin.
// It uses only the receipt's id: it reads no internet address, sets no cookie and keeps nothing about who tapped, and
// every answer is no-store (json in _lib/util.js). The rate limiting rule counts it like every Function.
import { HttpError, ID_RE, handle, json, noBindings, readJson } from "../_lib/util.js";
import { countThanks } from "../_lib/social.js";

export const onRequest = handle(async ({ request, env }) => {
  if (request.method !== "POST") return json({ error: "Use POST." }, 405, { allow: "POST" });
  const fetchSite = request.headers.get("sec-fetch-site");
  if (request.headers.get("origin") !== new URL(request.url).origin || (fetchSite !== null && fetchSite !== "same-origin")) {
    throw new HttpError(403, "Thanks come only from sapu.earth's own pages.", "origin");
  }
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get("content-type") || "")) throw new HttpError(415, "Send JSON.", "type");
  const b = await readJson(request, 1024);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) throw new HttpError(400, "Invalid receipt id.");
  const missing = noBindings(env);
  if (missing) return missing;
  const r = await countThanks(env, b.id);
  if (!r) throw new HttpError(404, "This receipt is not on sapu.earth.", "receipt");
  if (r.inactive) throw new HttpError(409, "This receipt takes no more thanks.", "inactive");
  return json(r);
});

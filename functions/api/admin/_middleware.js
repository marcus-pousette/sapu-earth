// Every /api/admin/* request needs "Authorization: Bearer <ADMIN_TOKEN>".
import { json, noBindings, safeEqual } from "../../_lib/util.js";

export async function onRequest(context) {
  const { request, env } = context;
  const expected = typeof env.ADMIN_TOKEN === "string" ? env.ADMIN_TOKEN : "";
  const m = /^Bearer (.+)$/.exec(request.headers.get("authorization") || "");
  // Always run the comparison so timing does not reveal whether a header was sent.
  const ok = await safeEqual(m ? m[1] : "", expected);
  if (!expected || !m || !ok) {
    return json({ error: "Unauthorized." }, 401, { "www-authenticate": "Bearer" });
  }
  const missing = noBindings(env);
  if (missing) return missing;
  return context.next();
}

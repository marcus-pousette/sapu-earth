// Creating a partner, shared by POST /api/admin/partners and approving an application.
// This file exports no onRequest handler, so it never becomes a route.
// The token is returned ONCE. Only its SHA-256 hex is stored.
import {
  HttpError, ISO2_RE, SITE, SLUG_RE, cleanText, cleanUrl, nowIso, randomId, randomToken, sha256Hex,
} from "./util.js";

const slugTaken = async (env, slug) => !!(await env.DB.prepare("SELECT 1 FROM partners WHERE slug = ?").bind(slug).first());

export async function createPartner(env, { name, url, country, slug } = {}) {
  name = cleanText(name, 80, { required: true, field: "name" });
  url = cleanUrl(url, "url");
  country = String(country || "").toUpperCase();
  if (!ISO2_RE.test(country)) throw new HttpError(400, "country must be a 2-letter ISO code.");
  slug = String(slug || "").trim().toLowerCase();
  if (!SLUG_RE.test(slug)) throw new HttpError(400, "slug must be 1 to 40 characters: a-z, 0-9 and dashes.");

  if (await slugTaken(env, slug)) throw new HttpError(409, "That slug is already taken.");

  const id = randomId(10);
  const token = randomToken();
  try {
    await env.DB.prepare(
      "INSERT INTO partners (id, slug, name, url, country, token_hash, active, created_at) VALUES (?, ?, ?, ?, ?, ?, 1, ?)"
    ).bind(id, slug, name, url, country, await sha256Hex(token), nowIso()).run();
  } catch (e) {
    // Two requests with the same slug at once: the UNIQUE index lets only one through.
    if (await slugTaken(env, slug)) throw new HttpError(409, "That slug is already taken.");
    throw e;
  }

  return { id, slug, name, token, upload_url: `${SITE}/upload/?k=${token}` };
}

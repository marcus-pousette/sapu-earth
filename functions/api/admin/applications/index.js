// GET /api/admin/applications?status=new|approved
// Photo URLs are short-lived signed links (application photos are never public), and so is the crew's logo:
// logo {key, url} for an open application sent with one, else null (always null in the approved list, where the
// logo belongs to the partner, and before migration 0006).
// ip_hash and client_ref are never selected, so they cannot leak into the response.
import { KEY_RE, err, handle, json, keyList, signedMediaUrl } from "../../../_lib/util.js";
import { expireApplications } from "../../../_lib/applications.js";
import { withLogos } from "../../../_lib/logos.js";

export const onRequestGet = handle(async ({ request, env }) => {
  const status = new URL(request.url).searchParams.get("status") || "new";
  if (!["new", "approved"].includes(status)) return err(400, "Unknown status.");

  // Retention runs here too (open applications after 90 days, old IP hashes), so it also happens
  // when nobody applies, and the list never shows what should be gone. A failure must not hide the list.
  await expireApplications(env).catch((e) => console.error("application expiry", e));

  // existing_partner: a partner with the same name, other than the one this application created.
  // Both joins match at most one row each, so they cannot duplicate applications.
  const [list, counts] = await env.DB.batch([
    env.DB.prepare(
      `SELECT a.id, a.status, a.lang, a.org_name, a.contact_name, a.country, a.area, a.about, a.crew_size,
         a.links, a.whatsapp, a.email, a.heard_from, a.photos, a.created_at, a.decided_at,
         p.id AS p_id, p.slug AS p_slug, p.name AS p_name, p.active AS p_active,
         e.slug AS e_slug, e.name AS e_name, e.active AS e_active,
         (SELECT group_concat(o.id) FROM applications o
           WHERE o.id <> a.id
             AND (o.whatsapp = a.whatsapp OR o.email = a.email OR lower(o.org_name) = lower(a.org_name))) AS possible_duplicates
       FROM applications a
       LEFT JOIN partners p ON p.id = a.partner_id
       LEFT JOIN partners e ON e.id = (
         SELECT x.id FROM partners x
         WHERE lower(x.name) = lower(a.org_name) AND x.id <> COALESCE(a.partner_id, '')
         ORDER BY x.active DESC, x.created_at DESC LIMIT 1)
       WHERE a.status = ?
       ORDER BY ${status === "new" ? "a.created_at ASC" : "a.decided_at DESC"} LIMIT 200`
    ).bind(status),
    env.DB.prepare("SELECT COUNT(*) AS n FROM applications WHERE status = 'new'"),
  ]);

  // The logos of open applications (at most one each: the page sends one), by application id.
  const logoOf = {};
  if (status === "new") {
    const rows = await withLogos(async (on) => (on
      ? (await env.DB.prepare("SELECT key, application_id FROM logos WHERE partner_id IS NULL AND status = 'review'").all()).results || []
      : []));
    for (const r of rows) if (typeof r.application_id === "string" && KEY_RE.test(r.key || "")) logoOf[r.application_id] = r.key;
  }

  const applications = [];
  for (const a of list.results) {
    const photos = await Promise.all(keyList(a.photos).map(async (key) => ({ key, url: await signedMediaUrl(env, key) })));
    const logoKey = logoOf[a.id];
    applications.push({
      id: a.id,
      status: a.status,
      lang: a.lang,
      org_name: a.org_name,
      contact_name: a.contact_name,
      country: a.country,
      area: a.area,
      about: a.about,
      crew_size: a.crew_size,
      links: a.links ? String(a.links).split("\n") : [],
      whatsapp: a.whatsapp,
      email: a.email,
      heard_from: a.heard_from,
      photos,
      logo: logoKey ? { key: logoKey, url: await signedMediaUrl(env, logoKey) } : null,
      created_at: a.created_at,
      decided_at: a.decided_at,
      partner: a.p_id ? { id: a.p_id, slug: a.p_slug, name: a.p_name, active: !!a.p_active } : null,
      possible_duplicates: a.possible_duplicates ? String(a.possible_duplicates).split(",") : [],
      existing_partner: a.e_slug ? { slug: a.e_slug, name: a.e_name, active: !!a.e_active } : null,
    });
  }
  return json({ counts: { new: counts.results[0]?.n ?? 0 }, applications });
});

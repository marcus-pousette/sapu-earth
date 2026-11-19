// GET  /api/admin/partners -> {partners, counts: {logos}}: the list, with the contact from the application that
//      created the partner (contact_name, whatsapp, email), or null when it was created by hand, and the crew's
//      logos: logo (the live one) and logo_review (one waiting under LOGOS TO CHECK, with created_at), each
//      {key, url} with a signed url, or null. counts.logos: the logos of active crews waiting for a decision.
//      It is /admin/'s token check too, so it must answer before migrations 0003 and 0006 (no contacts, no logos).
// POST /api/admin/partners {name, url, country, slug} -> {id, slug, name, token, upload_url}
// The token is shown ONCE. Only its SHA-256 hex is stored.
import { KEY_RE, handle, json, readJson, signedMediaUrl } from "../../../_lib/util.js";
import { createPartner } from "../../../_lib/partners.js";
import { noApplicationsTable } from "../../../_lib/applications.js";
import { withLogos } from "../../../_lib/logos.js";

// The join picks at most one application per partner, so it cannot duplicate rows.
const LIST = (withContact) =>
  `SELECT p.id, p.slug, p.name, p.url, p.country, p.active, p.created_at,
     (SELECT COUNT(*) FROM submissions s WHERE s.partner_id = p.id AND s.status = 'pending') AS pending,
     (SELECT COUNT(*) FROM submissions s WHERE s.partner_id = p.id AND s.status = 'approved') AS approved,
     ${withContact ? "a.contact_name, a.whatsapp, a.email" : "NULL AS contact_name, NULL AS whatsapp, NULL AS email"}
   FROM partners p
   ${withContact ? `LEFT JOIN applications a ON a.id = (
     SELECT x.id FROM applications x WHERE x.partner_id = p.id ORDER BY x.decided_at DESC LIMIT 1)` : ""}
   ORDER BY p.active DESC, p.created_at DESC`;

export const onRequestGet = handle(async ({ env }) => {
  let results;
  try {
    ({ results } = await env.DB.prepare(LIST(true)).all());
  } catch (e) {
    // Code deployed before migration 0003: /admin/ checks the token with this list, so it must
    // keep working without the applications table (no contacts then).
    if (!noApplicationsTable(e)) throw e;
    ({ results } = await env.DB.prepare(LIST(false)).all());
  }
  // The live and the waiting logo of each crew (at most one of each, the unique indexes say so). [] before 0006.
  const logos = await withLogos(async (on) => (on
    ? (await env.DB.prepare(
        "SELECT key, partner_id, status, created_at FROM logos WHERE partner_id IS NOT NULL AND status IN ('live', 'review')"
      ).all()).results || []
    : []));
  const live = {}, review = {};
  for (const l of logos) if (KEY_RE.test(l.key || "")) (l.status === "live" ? live : review)[l.partner_id] = l;
  const active = new Set(results.filter((p) => p.active).map((p) => p.id));
  const partners = [];
  for (const p of results) {
    const lv = live[p.id], rv = review[p.id];
    partners.push({
      ...p,
      active: !!p.active,
      // A deactivated partner's application keeps contact_name '' (wiped), shown as no contact.
      contact_name: p.contact_name || null,
      whatsapp: p.whatsapp || null,
      email: p.email || null,
      logo: lv ? { key: lv.key, url: await signedMediaUrl(env, lv.key) } : null,
      logo_review: rv ? { key: rv.key, url: await signedMediaUrl(env, rv.key), created_at: rv.created_at } : null,
    });
  }
  return json({ partners, counts: { logos: Object.keys(review).filter((id) => active.has(id)).length } });
});

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request);
  const partner = await createPartner(env, { name: b.name, url: b.url, country: b.country, slug: b.slug });
  return json(partner, 201);
});

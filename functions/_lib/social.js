// Post links and thanks on receipts (docs/upload-flow.md, Post links and thanks), shared by POST /api/submit, POST
// /api/thanks, toEvent, GET /api/partner, /p/<slug>, /crews, /admin/ and the housekeeping. No onRequest handler, so never
// a route. Post links: one post_links row per cleanup (migrations/0007_post_links_thanks.sql), with crew_url (the crew's
// own post, pasted with the cleanup) and sapu_url (Sapu Earth's post, pasted on the APPROVED card; a TikTok one only on
// @sapu.earth). The receipt shows one of them (socialPick). Only full post links, in one stored form (postLink), never
// short links: they redirect, so nobody can check where they lead. The receipt links the post and never embeds it, so
// nothing loads from Instagram or TikTok before a tap. Thanks: standing counts per receipt (thanks), per receipt and UTC
// day (thanks_days) and per UTC day for the site (thanks_site), within THANKS, and nothing about the visitor: the code
// reads no internet address, sets no cookie and keeps no time of day. Each day's site count is the sum of that day's
// receipt rows. Before migration 0007, everything goes through withSocial, and the site behaves as without links and
// thanks.
import { HttpError, randomHex } from "./util.js";

// ---------- post links: the same block in upload/upload.js and functions/_lib/social.js ----------
// postLink(text): the link to one Instagram or TikTok post as people paste it (Share, then Copy link, or the address
// bar). Returns { site: "instagram" | "tiktok", url, account }: url in its one stored form, account the TikTok account the
// link names, in lower case (null for Instagram, whose post links do not say whose post it is). Returns { short: true }
// for a short link that redirects and so cannot be checked, and null for anything else. A paste without https:// on one
// of these hosts gets it.
// Instagram: instagram.com, www. or m., then /p/<code>, /reel/<code> or /reels/<code>, also with an account in front
//   (/<account>/p/<code>); query (?igsh=) and hash dropped: https://www.instagram.com/p/<code>/ or /reel/<code>/.
// TikTok: tiktok.com, www. or m., then /@<account>/video/<digits> or /@<account>/photo/<digits>; query and hash
//   dropped: https://www.tiktok.com/@<account>/video/<digits> (or /photo/).
// Short: vm.tiktok.com, vt.tiktok.com, tiktok.com/t/..., instagr.am, instagram.com/share/... .
// Never: http:, another host or a port, a login in the link, a space, a profile, a story, more than POST_MAX characters.
const POST_MAX = 300;
const IG_HOST = /^(?:www\.|m\.)?instagram\.com$/;
const TT_HOST = /^(?:www\.|m\.)?tiktok\.com$/;
const BARE = /^(?:(?:www\.|m\.)?(?:instagram|tiktok)\.com|v[mt]\.tiktok\.com|(?:www\.)?instagr\.am)\//i;
function postLink(text) {
  if (typeof text !== "string") return null;
  let s = text.trim();
  if (BARE.test(s)) s = "https://" + s;
  if (!s || s.length > POST_MAX || /\s/.test(s)) return null;
  let u;
  try { u = new URL(s); } catch { return null; }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return null;
  const host = u.hostname, path = u.pathname;
  if (host === "vm.tiktok.com" || host === "vt.tiktok.com" || host === "instagr.am" || host === "www.instagr.am"
    || (TT_HOST.test(host) && path.startsWith("/t/")) || (IG_HOST.test(host) && path.startsWith("/share/"))) return { short: true };
  let m = IG_HOST.test(host) && /^\/(?:[A-Za-z0-9._]{1,30}\/)?(p|reels?)\/([A-Za-z0-9_-]{5,40})\/?$/.exec(path);
  if (m) return { site: "instagram", url: `https://www.instagram.com/${m[1] === "p" ? "p" : "reel"}/${m[2]}/`, account: null };
  m = TT_HOST.test(host) && /^\/@([A-Za-z0-9._]{2,24})\/(video|photo)\/(\d{8,25})\/?$/.exec(path);
  if (m) return { site: "tiktok", url: `https://www.tiktok.com/@${m[1]}/${m[2]}/${m[3]}`, account: m[1].toLowerCase() };
  return null;
}
// ---------- end of the post link block ----------
export { POST_MAX, postLink };

// Sapu Earth's own TikTok account (@sapu.earth, registered in November 2026): the only TikTok account Marcus's slot takes.
export const SAPU_TIKTOK = "sapu.earth";

// D1's error when migration 0007 has not been applied yet.
export function noSocialTables(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such table: (?:post_links|thanks|thanks_days|thanks_site)\b/i.test(text);
}
// Runs fn(true), which may use the tables of migration 0007. Before 0007 that throws, and fn(false) runs instead,
// without them. Like withLogos: one statement or one batch is atomic, so the first try wrote nothing.
export async function withSocial(fn) {
  try { return await fn(true); } catch (e) { if (!noSocialTables(e)) throw e; return fn(false); }
}

// toEvent's social: Sapu Earth's post when there is one, else the crew's while the crew is active, else null. Both
// stored values go through postLink again, so nothing stored by hand reaches a page in another form.
export function socialPick(sapuUrl, crewUrl, crewActive) {
  const sapu = postLink(sapuUrl);
  if (sapu && sapu.url) return { site: sapu.site, url: sapu.url, by: "sapu" };
  const crew = crewActive ? postLink(crewUrl) : null;
  return crew && crew.url ? { site: crew.site, url: crew.url, by: "crew" } : null;
}

// Whether migration 0007 is in (socialFor without ids). It reads no row.
export const socialOn = (env) => withSocial(async (on) => (on ? (await env.DB.prepare("SELECT 1 FROM post_links LIMIT 0").all(), true) : false));

// The post links and thanks of these cleanups for /admin/: { id: { post_links: { crew, sapu }, thanks } }, every id there
// with both links null and thanks 0 when it has none; {} for no ids. null before migration 0007. D1 takes at most 100
// bound values a statement, so 90 ids a read, both reads of a chunk in one batch.
export async function socialFor(env, ids) {
  if (!ids.length) return (await socialOn(env)) ? {} : null;
  return withSocial(async (on) => {
    if (!on) return null;
    const out = {};
    for (const id of ids) out[id] = { post_links: { crew: null, sapu: null }, thanks: 0 };
    for (let i = 0; i < ids.length; i += 90) {
      const chunk = ids.slice(i, i + 90);
      const marks = chunk.map(() => "?").join(",");
      const [links, thanks] = await env.DB.batch([
        env.DB.prepare(`SELECT submission_id, crew_url, sapu_url FROM post_links WHERE submission_id IN (${marks})`).bind(...chunk),
        env.DB.prepare(`SELECT submission_id, n FROM thanks WHERE submission_id IN (${marks})`).bind(...chunk),
      ]);
      for (const r of links.results || []) {
        if (out[r.submission_id]) out[r.submission_id].post_links = { crew: r.crew_url ?? null, sapu: r.sapu_url ?? null };
      }
      for (const r of thanks.results || []) {
        if (out[r.submission_id]) out[r.submission_id].thanks = Number(r.n) || 0;
      }
    }
    return out;
  });
}

// The statements REJECT and UNPUBLISH (POST /api/admin/decide) append to their batch, after the mission statement, so
// the cleanup's links and thanks go in the same transaction as its status. First the site's day counts lose this
// receipt's thanks of each day, so each day's site count stays the sum of its standing receipts (counted, which the site
// cap uses, stays as it is), then its day rows, its total and its post links go. Only with migration 0007 (withSocial).
export function dropReceiptSocial(env, id) {
  return [
    env.DB.prepare(`UPDATE thanks_site SET n = MAX(0, n - COALESCE((SELECT d.n FROM thanks_days d WHERE d.submission_id = ?1 AND d.day = thanks_site.day), 0))
      WHERE day IN (SELECT day FROM thanks_days WHERE submission_id = ?1 AND n > 0)`).bind(id),
    env.DB.prepare("DELETE FROM thanks_days WHERE submission_id = ?1").bind(id),
    env.DB.prepare("DELETE FROM thanks WHERE submission_id = ?1").bind(id),
    env.DB.prepare("DELETE FROM post_links WHERE submission_id = ?1").bind(id),
  ];
}

// DEACTIVATE: the crew's own links come off all its receipts, Sapu Earth's stay, and a row left with neither is deleted.
// One batch. Returns how many receipts lost the crew's link; 0 before migration 0007.
export async function dropCrewPostLinks(env, partnerId) {
  return withSocial(async (on) => {
    if (!on) return 0;
    const [r] = await env.DB.batch([
      env.DB.prepare(`UPDATE post_links SET crew_url = NULL WHERE crew_url IS NOT NULL
        AND submission_id IN (SELECT id FROM submissions WHERE partner_id = ?1)`).bind(partnerId),
      env.DB.prepare("DELETE FROM post_links WHERE crew_url IS NULL AND sapu_url IS NULL"),
    ]);
    return r.meta?.changes ?? 0;
  });
}

// The housekeeping's post link sweep: the crew's own links on receipts of inactive crews, for example after a DEACTIVATE
// whose link step failed. Sapu Earth's own links stay. Returns how many went; before 0007 it throws "no such table",
// which the job's check (noSocialTables) keeps out of the log.
export async function sweepCrewPostLinks(env) {
  const [r] = await env.DB.batch([
    env.DB.prepare(`UPDATE post_links SET crew_url = NULL WHERE crew_url IS NOT NULL
      AND submission_id IN (SELECT s.id FROM submissions s JOIN partners p ON p.id = s.partner_id WHERE p.active = 0)`),
    env.DB.prepare("DELETE FROM post_links WHERE crew_url IS NULL AND sapu_url IS NULL"),
  ]);
  return r.meta?.changes ?? 0;
}

// ---------- thanks (docs/upload-flow.md, Thanks) ----------
// perReceiptDay and perSiteDay: counted thanks per receipt and for the whole site per UTC day. D1 Free allows 100,000 rows
// written a day, and running out stops every query until 00:00 UTC, so the site cap is required. It is on
// thanks_site.counted, every thanks counted that day, which no undo and no UNPUBLISH lowers, so taking thanks off never
// makes room for more that day and a day writes at most what the caps allow. busySite and busyReceipt: a UTC day with
// this many standing on the site, or on one receipt, comes up in the GitHub note. days: the UTC days THANKS BY DAY shows.
export const THANKS = { perReceiptDay: 1000, perSiteDay: 5000, busySite: 200, busyReceipt: 100, days: 7 };
const COUNT_DAY = `INSERT INTO thanks_days (submission_id, day, n, last)
  SELECT ?1, ?2, 1, ?5
  WHERE EXISTS (SELECT 1 FROM submissions s JOIN partners p ON p.id = s.partner_id
                WHERE s.id = ?1 AND s.status = 'approved' AND p.active = 1)
    AND NOT EXISTS (SELECT 1 FROM thanks_site WHERE day = ?2 AND (counted >= ?4 OR undone > 0))
  ON CONFLICT (submission_id, day) DO UPDATE SET n = thanks_days.n + 1, last = excluded.last
    WHERE thanks_days.n < ?3 AND thanks_days.undone = 0`;
const COUNT_SITE = `INSERT INTO thanks_site (day, n, counted)
  SELECT ?2, 1, 1 WHERE EXISTS (SELECT 1 FROM thanks_days WHERE submission_id = ?1 AND day = ?2 AND last = ?3)
  ON CONFLICT (day) DO UPDATE SET n = thanks_site.n + 1, counted = thanks_site.counted + 1`;
const COUNT_TOTAL = `INSERT INTO thanks (submission_id, n)
  SELECT ?1, 1 WHERE EXISTS (SELECT 1 FROM thanks_days WHERE submission_id = ?1 AND day = ?2 AND last = ?3)
  ON CONFLICT (submission_id) DO UPDATE SET n = thanks.n + 1`;
// One thank you: null when id is not an approved receipt, { inactive: true } for a receipt of a crew no longer active (it
// stays on sapu.earth with its count and takes no new thanks), else { thanks, counted }. One batch (one transaction):
// COUNT_DAY counts the tap only if every check passes (the receipt, the caps, no undo on that receipt or day) and marks
// the receipt's day row with this request's random mark. The site's day and the receipt's total move only where that
// mark is, so the three counts move together or not at all, also with taps at the same moment. About 3 rows written
// (more for a receipt's first thanks of a day) and 10 read per counted thanks; none written and about 6 read per refused
// one. It uses only the id: nothing about who tapped reaches it.
export async function countThanks(env, id) {
  const row = await env.DB.prepare("SELECT p.active FROM submissions s JOIN partners p ON p.id = s.partner_id WHERE s.id = ?1 AND s.status = 'approved'").bind(id).first();
  if (!row) return null;
  if (Number(row.active) !== 1) return { inactive: true };
  const day = new Date().toISOString().slice(0, 10);
  const mark = randomHex(8);
  let res;
  try {
    res = await env.DB.batch([
      env.DB.prepare(COUNT_DAY).bind(id, day, THANKS.perReceiptDay, THANKS.perSiteDay, mark),
      env.DB.prepare(COUNT_SITE).bind(id, day, mark),
      env.DB.prepare(COUNT_TOTAL).bind(id, day, mark),
      env.DB.prepare("SELECT n FROM thanks WHERE submission_id = ?1").bind(id),
    ]);
  } catch (e) {
    if (noSocialTables(e)) throw new HttpError(503, "Thanks are not set up yet.", "migration");
    throw e;
  }
  return { thanks: Number(res[3].results?.[0]?.n) || 0, counted: (res[0].meta?.changes ?? 0) === 1 };
}

// UNDO in THANKS BY DAY (POST /api/admin/thanks/undo): null when there is nothing to undo, else { taken }. One batch each
// way, and its first statement reads what is taken, inside the same transaction as the takes. Each day's site count is
// always the sum of its standing receipt rows, so taken is what really came off the receipts. Neither undo lowers
// thanks_site.counted, so an undo never makes room under the site cap that day.
// With id (UNDO ON THAT RECEIPT): that receipt's thanks of that day come off its total and the site's day count. Its day
// row stays at 0 with undone set, so it takes no more thanks that day (COUNT_DAY); the rest of the site keeps counting.
// Without id (UNDO THE WHOLE DAY): every receipt's thanks of that day, the same way, and the site's day is kept as undone,
// so nobody can thank for the rest of that day (COUNT_DAY checks thanks_site.undone).
export async function undoThanks(env, day, id = null) {
  if (id) {
    const row = await env.DB.prepare("SELECT n FROM thanks_days WHERE day = ?1 AND submission_id = ?2").bind(day, id).first();
    if (!(Number(row?.n) > 0)) return null;
    const res = await env.DB.batch([
      "SELECT n AS taken FROM thanks_days WHERE day = ?1 AND submission_id = ?2",
      "UPDATE thanks SET n = MAX(0, n - COALESCE((SELECT d.n FROM thanks_days d WHERE d.submission_id = ?2 AND d.day = ?1), 0)) WHERE submission_id = ?2",
      "DELETE FROM thanks WHERE submission_id = ?2 AND n <= 0",
      "UPDATE thanks_site SET n = MAX(0, n - COALESCE((SELECT d.n FROM thanks_days d WHERE d.submission_id = ?2 AND d.day = ?1), 0)) WHERE day = ?1",
      "UPDATE thanks_days SET undone = undone + n, n = 0 WHERE day = ?1 AND submission_id = ?2 AND n > 0",
    ].map((sql) => env.DB.prepare(sql).bind(day, id)));
    return { taken: Number(res[0].results?.[0]?.taken) || 0 };
  }
  const row = await env.DB.prepare("SELECT n FROM thanks_site WHERE day = ?1").bind(day).first();
  if (!(Number(row?.n) > 0)) return null;
  const res = await env.DB.batch([
    "SELECT COALESCE(SUM(n), 0) AS taken FROM thanks_days WHERE day = ?1",
    `UPDATE thanks SET n = MAX(0, n - COALESCE((SELECT d.n FROM thanks_days d WHERE d.submission_id = thanks.submission_id AND d.day = ?1), 0))
      WHERE submission_id IN (SELECT submission_id FROM thanks_days WHERE day = ?1 AND n > 0)`,
    "DELETE FROM thanks WHERE n <= 0 AND submission_id IN (SELECT submission_id FROM thanks_days WHERE day = ?1)",
    "UPDATE thanks_days SET undone = undone + n, n = 0 WHERE day = ?1 AND n > 0",
    "UPDATE thanks_site SET undone = undone + n, n = 0 WHERE day = ?1",
  ].map((sql) => env.DB.prepare(sql).bind(day)));
  return { taken: Number(res[0].results?.[0]?.taken) || 0 };
}

// THANKS BY DAY on APPROVED: the last THANKS.days UTC days with standing thanks or an undo, newest first, each
// { day, n, closed, taken, full, top }: n the site's standing count, closed after UNDO THE WHOLE DAY, taken what the undos
// took off that day, full at the site cap (on counted, which the undos do not lower), top the receipt with the most that
// day ({ id, place_name, n }, the lowest id on a tie), for UNDO ON THAT RECEIPT. null before migration 0007.
export async function thanksDays(env) {
  const cutoff = new Date(Date.now() - (THANKS.days - 1) * 86400000).toISOString().slice(0, 10);
  return withSocial(async (on) => {
    if (!on) return null;
    const { results } = await env.DB.prepare(
      `SELECT ts.day, ts.n, ts.counted, ts.undone,
         (SELECT COALESCE(SUM(x.undone), 0) FROM thanks_days x WHERE x.day = ts.day) AS taken,
         d.submission_id AS top_id, d.n AS top_n, s.place_name AS top_place
       FROM thanks_site ts
       LEFT JOIN thanks_days d ON d.day = ts.day
         AND d.submission_id = (SELECT x.submission_id FROM thanks_days x WHERE x.day = ts.day AND x.n > 0 ORDER BY x.n DESC, x.submission_id LIMIT 1)
       LEFT JOIN submissions s ON s.id = d.submission_id
       WHERE ts.day >= ?1 AND (ts.n > 0 OR ts.undone > 0 OR EXISTS (SELECT 1 FROM thanks_days y WHERE y.day = ts.day AND y.undone > 0))
       ORDER BY ts.day DESC`
    ).bind(cutoff).all();
    return (results || []).map((r) => ({
      day: r.day,
      n: Number(r.n) || 0,
      closed: Number(r.undone) > 0,
      taken: Number(r.taken) || 0,
      full: (Number(r.counted) || 0) >= THANKS.perSiteDay,
      top: r.top_id ? { id: r.top_id, place_name: r.top_place, n: Number(r.top_n) || 0 } : null,
    }));
  });
}

// GET /api/partner: the crew's standing thanks on its approved receipts (total), and on the cleanups its crew page lists
// (byId, at most 10 ids). null before migration 0007, so the crew page shows no thanks line.
export async function crewThanks(env, partnerId, ids) {
  return withSocial(async (on) => {
    if (!on) return null;
    const res = await env.DB.batch([
      env.DB.prepare("SELECT COALESCE(SUM(t.n), 0) AS n FROM submissions s JOIN thanks t ON t.submission_id = s.id WHERE s.partner_id = ?1 AND s.status = 'approved'").bind(partnerId),
      ...(ids.length ? [env.DB.prepare(`SELECT submission_id, n FROM thanks WHERE submission_id IN (${ids.map(() => "?").join(",")})`).bind(...ids)] : []),
    ]);
    const byId = {};
    for (const r of res[1]?.results || []) byId[r.submission_id] = Number(r.n) || 0;
    return { total: Number(res[0].results?.[0]?.n) || 0, byId };
  });
}

// /crews: each crew's standing thanks on its approved receipts, { results: [{ partner_id, n }] }; none before 0007.
export const thanksByCrew = (env) => withSocial((on) => (on
  ? env.DB.prepare("SELECT s.partner_id, SUM(t.n) AS n FROM thanks t JOIN submissions s ON s.id = t.submission_id WHERE s.status = 'approved' GROUP BY s.partner_id").all()
  : { results: [] }));

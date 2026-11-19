// A crew's own TikTok account (docs/upload-flow.md, Crew TikTok accounts), shared by POST /api/tiktok, GET /api/partner,
// /admin/ (GET /api/admin/partners, POST /api/admin/tiktok/decide), DEACTIVATE, /p/<slug>, /crews and the housekeeping.
// No onRequest handler, so never a route. One crew_tiktok row per crew (migrations/0009_crew_tiktok.sql): live, the
// account sapu.earth links once Marcus approved it, and review, one waiting for him. Only the account's name is stored,
// in lower case, and every page builds the one link from it (tiktokUrl) after checking it again (accountOf), so nothing
// stored by hand reaches a page in another form. A link per cleanup is something else: post_links (_lib/social.js).
// Before migration 0009 everything goes through withTiktok, and the site behaves as without TikTok accounts.

// ---------- TikTok accounts: the same block in upload/upload.js and functions/_lib/tiktok.js ----------
// tiktokAccount(text): the crew's TikTok account as a crew types or pastes it: its name with the @ (@sapu.earth; without
// the @ it could be a website, kru.org), the link to its profile (https://www.tiktok.com/@sapu.earth, also with
// ?_t=..&_r=1 as the app copies it), or the link to one of its videos or photo posts (the account is taken from it, and
// the line under the field shows which). Returns { account, url }: account in lower case without the @, url the one
// link pages show, https://www.tiktok.com/@<account>. Returns { short: true } for a short link (vm.tiktok.com,
// vt.tiktok.com, tiktok.com/t/...), which redirects and names no account anybody can check, and null for anything else.
// A paste without https:// on tiktok.com (www. or m.) gets it, and the query and the hash are dropped.
// An account: 2 to 24 of a to z, 0 to 9, . and _, with at least one letter or digit.
// Never: http:, another host or a port, a login in the link, a space, a link to anything but a profile, a video or a
// photo post, more than TIKTOK_MAX characters.
const TIKTOK_MAX = 300;
const TT_NAME = /^(?=[a-z0-9._]*[a-z0-9])[a-z0-9._]{2,24}$/;
const TT_WEB = /^(?:www\.|m\.)?tiktok\.com$/;
function tiktokAccount(text) {
  if (typeof text !== "string") return null;
  let s = text.trim();
  if (!s || s.length > TIKTOK_MAX || /\s/.test(s)) return null;
  const named = (name) => {
    const account = name.toLowerCase();
    return TT_NAME.test(account) ? { account, url: "https://www.tiktok.com/@" + account } : null;
  };
  if (/^@[A-Za-z0-9._]+$/.test(s)) return named(s.slice(1));
  if (/^(?:(?:www\.|m\.)?tiktok\.com|v[mt]\.tiktok\.com)\//i.test(s)) s = "https://" + s;
  let u;
  try { u = new URL(s); } catch { return null; }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return null;
  const host = u.hostname, path = u.pathname;
  if (host === "vm.tiktok.com" || host === "vt.tiktok.com" || (TT_WEB.test(host) && path.startsWith("/t/"))) return { short: true };
  const m = TT_WEB.test(host) && /^\/@([A-Za-z0-9._]{2,24})(?:\/(?:video|photo)\/\d{8,25})?\/?$/.exec(path);
  return m ? named(m[1]) : null;
}
// ---------- end of the TikTok account block ----------
export { TIKTOK_MAX, tiktokAccount };

// A stored account as a page may use it, or null: it goes through the block again and must come back as it was, so a
// value written by hand in the D1 console that is no account (or not in lower case) never reaches a page.
export function accountOf(stored) {
  if (typeof stored !== "string" || !stored || stored[0] === "@") return null;
  const t = tiktokAccount("@" + stored);
  return t && t.account === stored ? stored : null;
}
// The one link to an account (from accountOf).
export const tiktokUrl = (account) => "https://www.tiktok.com/@" + account;

// D1's error when migration 0009 has not been applied yet.
export function noTiktokTable(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such table: crew_tiktok\b/i.test(text);
}
// Runs fn(true), which may use the crew_tiktok table. Before migration 0009 that throws, and fn(false) runs instead,
// without it. Like withLogos: one statement is atomic, so the first try wrote nothing.
export async function withTiktok(fn) {
  try { return await fn(true); } catch (e) { if (!noTiktokTable(e)) throw e; return fn(false); }
}

// The crew page's YOUR TIKTOK (GET /api/partner, and the answer of POST /api/tiktok): { enabled, live, review, declined }.
// live: the account sapu.earth links; review: the one waiting for Marcus; declined: Marcus declined the last one the
// crew sent, or took the live one off, and nothing waits. Before migration 0009: enabled false, and the page hides it.
export async function tiktokStateFor(env, partnerId) {
  const row = await withTiktok(async (on) => (on
    ? (await env.DB.prepare("SELECT live, review, declined_at FROM crew_tiktok WHERE partner_id = ?").bind(partnerId).first()) || {}
    : null));
  if (!row) return { enabled: false, live: null, review: null, declined: false };
  const review = accountOf(row.review);
  return { enabled: true, live: accountOf(row.live), review, declined: !review && !!row.declined_at };
}

// The crew's live account for /p/<slug>, or null (also before migration 0009).
export async function liveTiktok(env, partnerId) {
  const row = await withTiktok((on) => (on
    ? env.DB.prepare("SELECT live FROM crew_tiktok WHERE partner_id = ?").bind(partnerId).first()
    : null));
  return accountOf(row?.live);
}

// /crews: the live account of every crew that has one, as a Map of partner id to account; empty before migration 0009.
export async function tiktokByCrew(env) {
  const rows = await withTiktok(async (on) => (on
    ? (await env.DB.prepare("SELECT partner_id, live FROM crew_tiktok WHERE live IS NOT NULL").all()).results || []
    : []));
  const out = new Map();
  for (const r of rows) { const a = accountOf(r.live); if (a) out.set(r.partner_id, a); }
  return out;
}

// GET /api/admin/partners: { live, review: { account, sent_at } } per partner id with either, or null before 0009.
export async function tiktokForAdmin(env) {
  return withTiktok(async (on) => {
    if (!on) return null;
    const { results } = await env.DB.prepare(
      "SELECT partner_id, live, review, sent_at FROM crew_tiktok WHERE live IS NOT NULL OR review IS NOT NULL"
    ).all();
    const out = {};
    for (const r of results || []) {
      const review = accountOf(r.review);
      out[r.partner_id] = { live: accountOf(r.live), review: review ? { account: review, sent_at: r.sent_at || null } : null };
    }
    return out;
  });
}

// POST /api/tiktok: the crew sends an account, and it waits for Marcus, in place of one that waited. The account already
// live clears what waits instead (the crew keeps the one shown), and sending the one that waits again keeps its place
// in TIKTOK TO CHECK. Only while the crew is active, in one statement, so a send in the moment of a DEACTIVATE never
// leaves a row behind it.
export const SEND_TIKTOK = `INSERT INTO crew_tiktok (partner_id, review, sent_at)
  SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM partners WHERE id = ?1 AND active = 1)
  ON CONFLICT (partner_id) DO UPDATE SET
    review = CASE WHEN crew_tiktok.live = excluded.review THEN NULL ELSE excluded.review END,
    sent_at = CASE WHEN crew_tiktok.live = excluded.review THEN NULL
                   WHEN crew_tiktok.review = excluded.review THEN crew_tiktok.sent_at ELSE excluded.sent_at END,
    declined_at = NULL`;

// DEACTIVATE: the crew's row goes, the live and the waiting account alike. Returns 1 when it had either, else 0 (also
// before migration 0009).
export async function dropCrewTiktok(env, partnerId) {
  return withTiktok(async (on) => {
    if (!on) return 0;
    const { results } = await env.DB.prepare("DELETE FROM crew_tiktok WHERE partner_id = ? RETURNING live, review").bind(partnerId).all();
    return (results || []).some((r) => r.live || r.review) ? 1 : 0;
  });
}

// The housekeeping's TikTok sweep: the rows of crews that are no longer active (a DEACTIVATE whose TikTok step failed).
// Returns how many; before 0009 it throws "no such table", which the job's check (noTiktokTable) keeps out of the log.
export async function sweepCrewTiktok(env) {
  const r = await env.DB.prepare("DELETE FROM crew_tiktok WHERE partner_id IN (SELECT id FROM partners WHERE active = 0)").run();
  return r.meta?.changes ?? 0;
}

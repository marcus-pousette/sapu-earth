// The list of crews (docs/upload-flow.md, The list of crews), shared by the page /crews and NEXT UP on /p/<slug>, and the
// list of missions, /missions (missionList, and missionsListed for the foot of /crews), with the bits both list pages
// share (PAGE_HEADERS, nb, DOT, JOIN). This file exports no onRequest handler, so it never becomes a route.
//
// Every active crew is on /crews from the day Sapu Earth starts working with it (Marcus decided on 2026-11-11 to list
// the approved crews that had nothing public yet), so GET /api/partner's listed is true for every crew that reaches it.
// One rule, written once, splits the list: a crew with an approved cleanup, or a mission that is funded, or open and
// published less than MISSION_LIMITS.expireDays days ago (PUBLIC_MISSION, the rule of GET /api/missions), shows its
// totals, its newest receipt and its missions; so does a crew that ever had a mission published (missions.published_at,
// kept when the mission expires, is withdrawn or cancelled), with "no cleanups yet" and nothing else, since its first
// mission did come; every other active crew is under JUST JOINED (justJoined) with its name, live logo, country and live
// TikTok account only.
// NEXT UP on /p/<slug> uses the same mission rule, so the two never disagree. Everything the
// list shows is already public on the receipts, the missions or /p/<slug>: the name, the live logo, the country, the
// live TikTok account (_lib/tiktok.js), the totals of the approved receipts (their thanks too), the newest receipt's day
// and place, the open and funded missions.
// Never contact details or anything from the application, the partner id, the join date (it only orders JUST JOINED),
// a waiting or declined logo, or the website (that stays on /p/<slug>).
// Before migration 0004 (no missions table) only an approved cleanup takes a crew out of JUST JOINED; before 0006 there
// are no logos (withMissions, withLogos).
import { esc, publicMediaUrl } from "./util.js";
import { MISSION_LIMITS, nowMediaFor, nowParts, withMissions } from "./missions.js";
import { logoUrl, withLogos } from "./logos.js";
import { LIVE_LOGO } from "./events.js";
import { thanksByCrew } from "./social.js";
import { tiktokByCrew } from "./tiktok.js";
import { lastDay, spotList, withSpots } from "./spots.js";

// The public missions, as SQL over missions m: funded, or open and published within the last expireDays days. ?1 is
// the cutoff (since()). A statement binds ?1 only in the variant that uses it, since D1 refuses extra bindings.
export const PUBLIC_MISSION = "(m.status = 'funded' OR (m.status = 'open' AND COALESCE(m.published_at, m.created_at) >= ?1))";
const since = () => new Date(Date.now() - MISSION_LIMITS.expireDays * 86400000).toISOString();
// At most this many crews on /crews, both groups together (paging past it is not built yet).
export const CREWS_CAP = 200;
const FUNDED_FIRST = "ORDER BY CASE m.status WHEN 'funded' THEN 0 ELSE 1 END, m.plan_date, m.no";

// The crews on /crews, at most CREWS_CAP in all, in two groups. First the crews with an approved cleanup or a public
// mission, newest activity first (the newer of the newest receipt's day and the newest public mission's publishing day),
// then by name, and after them the crews that only ever had a mission published, by name. Then JUST JOINED, every other
// active crew (justJoined), the newest first by partners.created_at (the day
// Marcus created it with NEW PARTNER or APPROVE AND CREATE PARTNER; only the order, never shown), then by name. Never by
// kilograms, sacks, money or thanks. Five reads, at once:
// (a) every active crew with the totals of its approved receipts and its live logo;
// (b) the public missions of active crews, funded first, then the soonest day;
// (c) each active crew's newest approved receipt;
// (d) each crew's standing thanks on its approved receipts (thanksByCrew in _lib/social.js; none before migration 0007);
// (e) each crew's live TikTok account (tiktokByCrew in _lib/tiktok.js; none before migration 0009).
// A JUST JOINED crew has nothing in (b), (c) or (d) by the rule itself, so its totals are 0, last null and missions [].
// Returns [{ slug, name, country, justJoined, cleanups, kg, sacks, paid_eur, thanks, logo, tiktok (the account's name or
// null), last: { id, place_name, cleanup_date } or null, missions: [{ no, status, place_name, plan_date }] }], never the
// partner id or the join date.
export async function listedCrews(env) {
  const cutoff = since();
  const crews = withMissions((missions) => withLogos((logos) => {
    // No approved cleanup, no public mission and never a published one: JUST JOINED. A crew whose only mission expired
    // unfunded, or was withdrawn or cancelled, stays on top as "no cleanups yet", sorted after the crews with something to
    // show (its activity is ''), so FIRST MISSION COMING is never said of a crew whose first mission already came. As
    // SQL it is 0 or 1, so ordering by it first puts the crews with something public on top, and the CASE orders only
    // JUST JOINED by the join date: the order of the crews with something to show is exactly the one they had before
    // JUST JOINED existed.
    const joined = missions ? "(s.n IS NULL AND x.last_pub IS NULL AND e.partner_id IS NULL)" : "(s.n IS NULL)";
    const st = env.DB.prepare(
      `SELECT p.id, p.slug, p.name, p.country, ${joined} AS just_joined, COALESCE(s.n, 0) AS cleanups, COALESCE(s.kg, 0) AS kg,
         COALESCE(s.sacks, 0) AS sacks, COALESCE(s.paid, 0) AS paid_eur, ${logos ? LIVE_LOGO("p.id") : "NULL"} AS logo,
         ${missions ? "MAX(COALESCE(s.last_day, ''), COALESCE(substr(x.last_pub, 1, 10), ''))" : "COALESCE(s.last_day, '')"} AS activity
       FROM partners p
       LEFT JOIN (SELECT partner_id, COUNT(*) AS n, SUM(kg) AS kg, SUM(sacks) AS sacks, SUM(paid_eur) AS paid,
                    MAX(cleanup_date) AS last_day
                  FROM submissions WHERE status = 'approved' GROUP BY partner_id) s ON s.partner_id = p.id
       ${missions ? `LEFT JOIN (SELECT m.partner_id, MAX(COALESCE(m.published_at, m.created_at)) AS last_pub
                  FROM missions m WHERE ${PUBLIC_MISSION} GROUP BY m.partner_id) x ON x.partner_id = p.id
       LEFT JOIN (SELECT DISTINCT partner_id FROM missions WHERE published_at IS NOT NULL) e ON e.partner_id = p.id` : ""}
       WHERE p.active = 1
       ORDER BY ${joined}, activity DESC, CASE WHEN ${joined} THEN p.created_at END DESC, lower(p.name) LIMIT ${CREWS_CAP}`
    );
    return (missions ? st.bind(cutoff) : st).all();
  }));
  const missions = withMissions((on) => (on
    ? env.DB.prepare(
        `SELECT m.partner_id, m.no, m.status, m.place_name, m.plan_date FROM missions m JOIN partners p ON p.id = m.partner_id
         WHERE p.active = 1 AND ${PUBLIC_MISSION} ${FUNDED_FIRST} LIMIT 1000`
      ).bind(cutoff).all()
    : { results: [] }));
  const lasts = env.DB.prepare(
    `SELECT s.partner_id, s.id, s.place_name, s.cleanup_date FROM submissions s WHERE s.id IN (
       SELECT (SELECT x.id FROM submissions x WHERE x.partner_id = p.id AND x.status = 'approved'
               ORDER BY x.cleanup_date DESC, x.created_at DESC LIMIT 1)
       FROM partners p WHERE p.active = 1)`
  ).all();
  const [a, b, c, d, e] = await Promise.all([crews, missions, lasts, thanksByCrew(env), tiktokByCrew(env)]);
  const thanks = new Map((d.results || []).map((r) => [r.partner_id, Number(r.n) || 0]));

  const byId = new Map();
  for (const p of a.results || []) {
    byId.set(p.id, {
      slug: p.slug,
      name: p.name,
      country: p.country,
      justJoined: Number(p.just_joined) === 1,
      cleanups: Number(p.cleanups) || 0,
      kg: Number(p.kg) || 0,
      sacks: Number(p.sacks) || 0,
      paid_eur: Number(p.paid_eur) || 0,
      thanks: thanks.get(p.id) || 0,
      logo: logoUrl(p.logo),
      tiktok: e.get(p.id) || null,
      last: null,
      missions: [],
    });
  }
  for (const m of b.results || []) {
    byId.get(m.partner_id)?.missions.push({ no: m.no, status: m.status, place_name: m.place_name, plan_date: m.plan_date });
  }
  for (const s of c.results || []) {
    const crew = byId.get(s.partner_id);
    if (crew) crew.last = { id: s.id, place_name: s.place_name, cleanup_date: s.cleanup_date };
  }
  return [...byId.values()];
}

// NEXT UP on /p/<slug>: one crew's public missions under the same rule, funded first, then the soonest day, each with
// its first photo of the spot now. [{ no, status, place_name, plan_date, crew_size, photo }], [] before migration 0004.
// A crew has at most MISSION_LIMITS.active missions waiting, open or funded, so the LIMIT is only a guard.
export async function crewMissions(env, partnerId) {
  const rows = await withMissions(async (on) => {
    if (!on) return [];
    const { results } = await env.DB.prepare(
      `SELECT m.id, m.no, m.status, m.place_name, m.plan_date, m.crew_size FROM missions m
       WHERE m.partner_id = ?2 AND ${PUBLIC_MISSION} ${FUNDED_FIRST} LIMIT 20`
    ).bind(since(), partnerId).all();
    return results || [];
  });
  if (!rows.length) return [];
  const media = await nowMediaFor(env, rows.map((m) => m.id));
  return rows.map((m) => {
    const first = nowParts(media[m.id]).photos[0];
    return {
      no: m.no, status: m.status, place_name: m.place_name, plan_date: m.plan_date, crew_size: m.crew_size,
      photo: first ? publicMediaUrl(env, first) : null,
    };
  });
}

// The list of missions, /missions (docs/upload-flow.md, The list of missions). Two reads, at once:
// (a) live: the open and funded missions of active crews, by the rule above (PUBLIC_MISSION, the rule of GET /api/missions);
// (b) cleaned: every done mission whose cleanup is an approved receipt (missions.submission_id), also of a crew Sapu Earth
//     no longer works with (a receipt stays), the newest cleanup first, at most CLEANED_CAP, and how many there are in all;
//     the mission's number and place (as /m/<no> shows them), everything else from the receipt, its country too.
// Only what GET /api/missions, /m/<no> and the receipts already show: never the mission id, the private or review note,
// the advance, the exact point, the partner id or anything from the application. Before migration 0004 there are none.
// Returns { live: [{ no, status, place_name, country, plan_date, crew_size, currency, price_local, crew_local,
// funded_eur, crew }], cleaned: [{ no, place_name, country, receipt_id, cleanup_date, kg, sacks, crew_size, paid_eur,
// crew }], cleanedTotal }, crew being { name, slug }, slug null once the crew is no longer active. live comes in the
// order of NEXT UP on the homepage: the soonest day first, a day that has passed last (the most recent of those first).
// A mission with several spots (docs/missions.md, Spots) also has spots, [{place_name, date}] for spot 1 first, its
// cleaned one the receipt's (the days it was cleaned), [] for one spot and before migration 0008; it counts as passed
// only once its last day has passed.
export const LIVE_CAP = 1000; // at most MISSION_LIMITS.active per crew are open or funded, so this is only a guard
export const CLEANED_CAP = 200; // paging past it is not built yet
// The two halves of the list as SQL over missions m, partners p (and submissions s), written once for missionList and
// missionsListed, so the list and the links to it never disagree. LIVE binds ?1 (since()), CLEANED binds nothing.
const LIVE_FROM = `FROM missions m JOIN partners p ON p.id = m.partner_id
           WHERE p.active = 1 AND ${PUBLIC_MISSION}`;
const CLEANED_FROM = `FROM missions m JOIN submissions s ON s.id = m.submission_id AND s.status = 'approved'
             JOIN partners p ON p.id = m.partner_id
           WHERE m.status = 'done'`;
export async function missionList(env) {
  const rows = await withMissions((on) => (on
    ? withSpots((sp) => Promise.all([
        env.DB.prepare(
          `SELECT m.no, m.status, m.place_name, m.country, m.plan_date, m.crew_size, m.currency, m.price_local,
             m.crew_local, m.funded_eur, p.name AS crew_name, p.slug AS crew_slug, ${sp ? "m.spots" : "NULL AS spots"}
           ${LIVE_FROM} ORDER BY m.no LIMIT ${LIVE_CAP}`
        ).bind(since()).all(),
        env.DB.prepare(
          `SELECT m.no, m.place_name, s.country, s.id AS receipt_id, s.cleanup_date, s.kg, s.sacks, s.crew_size, s.paid_eur,
             p.name AS crew_name, p.slug AS crew_slug, p.active AS crew_active, COUNT(*) OVER () AS total,
             ${sp ? "s.spots" : "NULL AS spots"}
           ${CLEANED_FROM}
           ORDER BY s.cleanup_date DESC, s.created_at DESC, m.no DESC LIMIT ${CLEANED_CAP}`
        ).all(),
      ]))
    : null));
  if (!rows) return { live: [], cleaned: [], cleanedTotal: 0 };
  const [a, b] = rows;
  const today = new Date().toISOString().slice(0, 10);
  const passed = (m) => (String(m.last) < today ? 1 : 0); // m.last: the last day of its spots, dropped after the sort
  const spotsOf = (m, dayCol) => spotList(m, dayCol).map((s) => ({ place_name: s.place_name, date: s.date }));
  const live = (a.results || []).map((m) => ({
    no: m.no, status: m.status, place_name: m.place_name, country: m.country, plan_date: m.plan_date,
    crew_size: m.crew_size, currency: m.currency, price_local: m.price_local, crew_local: m.crew_local,
    funded_eur: m.status === "funded" ? m.funded_eur : null, crew: { name: m.crew_name, slug: m.crew_slug },
    spots: spotsOf(m, "plan_date"), last: lastDay(m, "plan_date"),
  })).sort((x, y) => passed(x) - passed(y)
    || (passed(x) ? String(y.plan_date).localeCompare(String(x.plan_date)) : String(x.plan_date).localeCompare(String(y.plan_date)))
    || x.no - y.no).map(({ last, ...m }) => m);
  const cleaned = (b.results || []).map((m) => ({
    no: m.no, place_name: m.place_name, country: m.country, receipt_id: m.receipt_id, cleanup_date: m.cleanup_date,
    kg: Number(m.kg) || 0, sacks: Number(m.sacks) || 0, crew_size: m.crew_size, paid_eur: m.paid_eur ?? null,
    crew: { name: m.crew_name, slug: Number(m.crew_active) === 1 ? m.crew_slug : null },
    spots: spotsOf(m, "cleanup_date"),
  }));
  return { live, cleaned, cleanedTotal: Number(b.results?.[0]?.total) || 0 };
}

// Whether /missions lists anything: one read, an EXISTS for each half of missionList. The foot of /crews links the list
// only then, as THE MISSIONS in the homepage footer waits for it, since a crew can be on /crews without any mission: by a
// cleanup sent with No mission alone, or under JUST JOINED. false before migration 0004.
export async function missionsListed(env) {
  const row = await withMissions((on) => (on
    ? env.DB.prepare(`SELECT (EXISTS (SELECT 1 ${LIVE_FROM}) OR EXISTS (SELECT 1 ${CLEANED_FROM})) AS listed`).bind(since()).first()
    : null));
  return Number(row?.listed) === 1;
}

// Shared by the two list pages, /crews and /missions, so they never drift apart. PAGE_HEADERS: no script, no framing,
// only this site's styles, fonts and pictures (data: for the noise texture in styles.css); each page adds its caching.
// nb: escaped text that never breaks across lines on a narrow phone ("64.5 kg", "21 Nov 2026"); DOT: the separator
// whose dot stays with what it follows, so a line never starts with it. A card's text may still break anywhere when one
// piece alone is wider than the card (overflow-wrap: anywhere in forms.css). JOIN: the box for crews under both lists.
export const PAGE_HEADERS = {
  "content-type": "text/html; charset=utf-8",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "strict-origin-when-cross-origin",
  "content-security-policy": "default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};
export const nb = (text) => esc(text).replace(/ /g, "&nbsp;");
export const DOT = "&nbsp;· ";
export const JOIN = `  <section class="panel cx-join">
    <h2 class="panel-title">RUN A CLEANUP CREW?</h2>
    <p>We pay local crews for cleanups and publish each one as a receipt. There are no fees, and we never ask for a PIN, a password or an OTP code.</p>
    <p class="hint" lang="id">Kamu membersihkan pantai, sungai, atau jalan bersama tim? Daftar dalam bahasa Indonesia, sekitar 3 menit. Tidak ada biaya apa pun, dan kami tidak pernah meminta PIN, kata sandi, atau kode OTP.</p>
    <p><a class="btn btn-apply" href="/apply/">APPLY AS A CREW →</a></p>
  </section>`;

// "Indonesia" for ID: the English name of a country code, or the code itself when it is unknown or the runtime has no
// Intl.DisplayNames. "" without a code.
let regions;
export function countryName(code) {
  if (typeof code !== "string" || !code) return "";
  if (regions === undefined) {
    try { regions = new Intl.DisplayNames(["en"], { type: "region" }); } catch { regions = null; }
  }
  if (!regions) return code;
  try {
    const name = regions.of(code);
    return typeof name === "string" && name && name !== "Unknown Region" ? name : code;
  } catch {
    return code;
  }
}

// "15 Nov 2026" (en-GB, UTC), as on /m/<no>.
export function fmtDay(iso) {
  const t = Date.parse(String(iso ?? "") + "T00:00:00Z");
  if (!Number.isFinite(t)) return String(iso ?? "");
  return new Date(t).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

// "€95", "€1,250", or "€28.50" when there are cents.
export function eurText(n) {
  const v = Number(n) || 0;
  const cents = Math.round(v * 100) % 100 !== 0;
  return "€" + v.toLocaleString("en", { minimumFractionDigits: cents ? 2 : 0, maximumFractionDigits: 2 });
}

// Maps approved submissions to the public site event schema (see data/README.md), and missions to
// the public mission shape of GET /api/missions.
import { SITE, VIDEO_STAGES, mediaFor, publicMediaUrl } from "./util.js";
import { missionShareUrl, noMissionsTable, nowMediaFor, nowParts } from "./missions.js";
import { logoUrl, withLogos } from "./logos.js";
import { socialPick, withSocial } from "./social.js";
import { spotList, spotOf } from "./spots.js";

// The crew's live logo, a scalar subquery: at most one live logo per crew (migration 0006). NULL before 0006.
export const LIVE_LOGO = (partnerCol) => `(SELECT l.key FROM logos l WHERE l.partner_id = ${partnerCol} AND l.status = 'live')`;

// crew_post and sapu_post: the cleanup's post links (post_links, migration 0007), NULL without them and before 0007.
// thanks_n: its standing thanks (thanks, by primary key), 0 without any, NULL before 0007.
const SELECT = (logos, social) => `
  SELECT s.*, p.name AS partner_name, p.url AS partner_url, p.slug AS partner_slug, p.active AS partner_active,
    ${logos ? LIVE_LOGO("s.partner_id") : "NULL"} AS partner_logo,
    ${social ? "pl.crew_url" : "NULL"} AS crew_post, ${social ? "pl.sapu_url" : "NULL"} AS sapu_post,
    ${social ? "COALESCE((SELECT t.n FROM thanks t WHERE t.submission_id = s.id), 0)" : "NULL"} AS thanks_n
  FROM submissions s JOIN partners p ON p.id = s.partner_id${social ? "\n  LEFT JOIN post_links pl ON pl.submission_id = s.id" : ""}`;

export async function approvedEvents(env, { partnerId = null, id = null, limit = 500 } = {}) {
  let where = " WHERE s.status = 'approved'";
  const args = [];
  if (partnerId) { where += " AND s.partner_id = ?"; args.push(partnerId); }
  if (id) { where += " AND s.id = ?"; args.push(id); }
  where += " ORDER BY s.cleanup_date DESC, s.created_at DESC LIMIT ?";
  args.push(limit);
  const { results } = await withLogos((logos) => withSocial((social) => env.DB.prepare(SELECT(logos, social) + where).bind(...args).all()));
  const media = await mediaFor(env, results.map((r) => r.id));
  const missions = await missionBlocks(env, results);
  // Only the cleanup that closed the mission gets its block. Another cleanup that still carries
  // the mission_id (approved after the mission was cancelled, say) is a plain receipt.
  const blockOf = (s) => {
    const m = s.mission_id ? missions[s.mission_id] : undefined;
    return m && m.submission_id === s.id ? m : undefined;
  };
  return results.map((s) => toEvent(env, s, media[s.id], blockOf(s)));
}

// The done missions behind these receipts, {missionId: {no, funded_eur, currency, price_local,
// crew_local, crew_size, submission_id, now: [photo rows], now_video: row or null}}. crew_local is the crew's pay in
// all, inside price_local; crew_size the crew the mission was planned with, which that pay was added up for.
// Never fails: before migration 0004 there is no mission_id (and nothing to look up), and any
// other error only costs the mission block, never the receipts.
async function missionBlocks(env, subs) {
  const ids = [...new Set(subs.map((s) => s.mission_id).filter((v) => typeof v === "string" && v))];
  if (!ids.length) return {};
  try {
    const out = {};
    for (let i = 0; i < ids.length; i += 90) {
      const chunk = ids.slice(i, i + 90);
      const { results } = await env.DB.prepare(
        `SELECT id, no, funded_eur, currency, price_local, crew_local, crew_size, submission_id
         FROM missions WHERE status = 'done' AND id IN (${chunk.map(() => "?").join(",")})`
      ).bind(...chunk).all();
      for (const m of results) {
        out[m.id] = {
          no: m.no, funded_eur: m.funded_eur, currency: m.currency, price_local: m.price_local, crew_local: m.crew_local,
          crew_size: m.crew_size, submission_id: m.submission_id, now: [], now_video: null,
        };
      }
    }
    const media = await nowMediaFor(env, Object.keys(out));
    for (const id of Object.keys(out)) {
      const { photos, video } = nowParts(media[id]);
      out[id].now = photos;
      out[id].now_video = video;
    }
    return out;
  } catch (e) {
    if (!noMissionsTable(e)) console.error("mission blocks", e);
    return {};
  }
}

// Public coordinates are rounded to 3 decimals (about 100 m). /admin/ keeps full precision,
// so a pin placed at someone's home does not publish the exact house.
export const round3 = (v) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v * 1000) / 1000 : null);

// Only explicit public fields. Never spread the row: private_note and review_note must stay internal.
// mission: {no, funded_eur, currency, price_local, crew_local, crew_size, now: [photo rows], now_video: row or null}
// when the cleanup closed a mission. price_local and crew_local are what the crew asked when it posted
// the mission, in its currency: price_local the whole price, crew_local the crew's pay in all, inside it. crew_size is
// the mission's planned crew, so the receipt can say the pay for each person (it is public in /api/missions already).
// media.video_stages goes with media.videos, one for each: 'before', 'after', or null (no stage). The videos come in
// mediaFor's order: before (up to 30), after (up to 30), then those without a stage, each stage in upload order.
// provider.url (the crew's website), provider.slug, provider.page (the crew's page /p/<slug>) and provider.logo (its
// live logo, "/media/<key>") only while the crew is active: a deactivated crew has none of them, and its receipts stay
// with the name alone (DEACTIVATE wipes the same links from the application, as personal data).
// social: the one post on Instagram or TikTok where people comment on this receipt (socialPick in _lib/social.js), as
// { site, url, by }: Sapu Earth's post (by "sapu") when Marcus saved one, else the crew's own (by "crew"), which counts
// only while the crew is active. A plain link for the receipt post, never an embed, and null without one (also before
// migration 0007).
// thanks: the receipt's standing thanks from SAY TERIMA KASIH in its post (docs/upload-flow.md, Thanks), a whole number,
// also for a crew no longer active (its receipts keep their count and take no new ones). Taps, not people. Absent
// before migration 0007, so the homepage then shows no button and no count.
// spots: only for the cleanup of a mission with several spots (docs/missions.md, Spots; migration 0008), every spot,
// spot 1 first, as [{no, name, lat, lng, date}] (spot 1 is location and date), the points rounded like location's; and
// media.before_spots and media.after_spots, one spot number for each photo of media.before and media.after, which come
// spot by spot (mediaFor). Absent for a cleanup with one spot.
export function toEvent(env, s, m = { before: [], after: [], videos: [] }, mission) {
  const url = (r) => publicMediaUrl(env, r);
  const active = Number(s.partner_active) === 1;
  const ev = {
    id: s.id,
    date: s.cleanup_date,
    location: { name: s.place_name, country: s.country, lat: round3(s.lat), lng: round3(s.lng) },
    crew: { size: s.crew_size },
    result: { kg_estimate: s.kg, sacks: s.sacks, disposal: s.disposal },
    hours: s.hours,
    provider: {
      name: s.partner_name, url: active ? s.partner_url : null, slug: active ? s.partner_slug : null,
      page: active ? `${SITE}/p/${s.partner_slug}` : null,
      logo: active ? logoUrl(s.partner_logo) : null,
    },
    local_money: { currency: s.currency, total: s.total_cost_local, crew: s.crew_pay_local },
    media: {
      before: m.before.map(url),
      after: m.after.map(url),
      videos: m.videos.map(url),
      video_stages: m.videos.map((r) => (VIDEO_STAGES.includes(r.stage) ? r.stage : null)),
    },
    notes: s.notes,
    social: socialPick(s.sapu_post, s.crew_post, active),
  };
  if (s.paid_eur !== null && s.paid_eur !== undefined) {
    ev.money = { paid_eur: s.paid_eur, crew_eur: s.crew_eur, ops_eur: s.ops_eur };
  }
  if (s.thanks_n !== null && s.thanks_n !== undefined) ev.thanks = Number(s.thanks_n) || 0;
  const spots = spotList(s, "cleanup_date");
  if (spots.length) {
    ev.spots = spots.map((p) => ({ no: p.no, name: p.place_name, lat: round3(p.lat), lng: round3(p.lng), date: p.date }));
    ev.media.before_spots = m.before.map((r) => spotOf(r, spots.length));
    ev.media.after_spots = m.after.map((r) => spotOf(r, spots.length));
  }
  if (mission) {
    ev.mission = {
      no: mission.no,
      url: missionShareUrl(mission.no),
      now: (mission.now || []).map(url),
      now_video: mission.now_video ? url(mission.now_video) : null,
      funded_eur: mission.funded_eur ?? null,
      currency: mission.currency ?? null,
      price_local: mission.price_local ?? null,
      crew_local: mission.crew_local ?? null,
      crew_size: mission.crew_size ?? null,
    };
  }
  return ev;
}

// One mission in the public shape of GET /api/missions (data/README.md). Only explicit fields:
// never id, client_ref, private_note, review_note, advance_eur or the exact coordinates.
// m: a missions row joined with partner_name, partner_slug and partner_logo (the crew's live logo key, LIVE_LOGO), and
// its spots (migration 0008, NULL without them).
// rows: its now media rows (nowMediaFor), the photos as now, the video as now_video.
// spots: only for a mission with several spots (docs/missions.md, Spots), every spot, spot 1 first, as
// [{no, place_name, lat, lng, date}] (spot 1 is place_name, lat, lng and date), rounded like lat and lng.
export function publicMission(env, m, rows = []) {
  const { photos, video } = nowParts(rows);
  const out = {
    no: m.no,
    status: m.status,
    date: m.plan_date,
    place_name: m.place_name,
    country: m.country,
    lat: round3(m.lat),
    lng: round3(m.lng),
    crew_size: m.crew_size,
    task: m.task,
    currency: m.currency,
    price_local: m.price_local,
    crew_local: m.crew_local,
  };
  const spots = spotList(m, "plan_date");
  if (spots.length) {
    out.spots = spots.map((p) => ({ no: p.no, place_name: p.place_name, lat: round3(p.lat), lng: round3(p.lng), date: p.date }));
  }
  if (m.status === "funded") out.funded_eur = m.funded_eur;
  out.partner = { name: m.partner_name, slug: m.partner_slug, logo: logoUrl(m.partner_logo) };
  out.now = photos.map((r) => publicMediaUrl(env, r));
  out.now_video = video ? publicMediaUrl(env, video) : null;
  out.url = missionShareUrl(m.no);
  return out;
}

// GET /api/admin/submissions?status=pending|approved|rejected
// Media URLs are short-lived signed links, so pending files are viewable here but not public.
// media: {before, after: [{key, url, content_type}], videos: [{key, url, content_type, stage}]}, the videos
// in the order before, after, then those without a stage (stage null: sent before the two video fields,
// or before migration 0005).
// A cleanup sent for a mission carries mission: {id, no, status, removed_why, place_name, plan_date, task,
// currency, price_local, crew_local, crew_size, funded_eur, advance_eur, lat, lng, now: [{key, url}], now_video: {key,
// url} or null} (crew_size: the crew the price was added up for, so Asked can say the pay for each person), so
// PENDING can show the spot as it was next to the before photos, and use the mission's
// point when the cleanup came without one. lat and lng are rounded to 3 decimals (about 100 m, the
// precision of the public receipt): an exact mission point is wiped when the mission is removed, so no copy
// of it may reach a cleanup. null otherwise.
// partner_missions: for a cleanup without a mission (not rejected), the partner's funded missions
// that have no pending or approved cleanup yet, [{id, no, place_name, plan_date, lat, lng}] soonest day first,
// for the "Link to mission" select (APPROVE then sends mission_id). [] otherwise, and before
// migration 0004.
// post_links: {crew, sapu}, the cleanup's links to posts on Instagram or TikTok in their stored form (the crew's own
// for THE CREW'S POST on PENDING, and both for COMMENTS LINK on APPROVED; docs/upload-flow.md, Post links and thanks),
// each null when there is none; null before migration 0007. partner_active says whether the crew's own link counts
// on the receipt (socialPick in _lib/social.js).
// thanks: a published cleanup's standing thanks (docs/upload-flow.md, Thanks), for the line on its APPROVED card; null on
// a pending or rejected one, and before migration 0007.
// status=approved also answers thanks_days, THANKS BY DAY: the last 7 UTC days with thanks or an undo ([{day, n, closed,
// taken, full, top: {id, place_name, n} or null}], thanksDays in _lib/social.js), and thanks_caps, the limits its hint
// names ({receipt, site, busy_site, busy_receipt}, THANKS); both null before migration 0007.
// Spots (docs/missions.md, Spots; migration 0008): a cleanup of a mission with several spots has spots, every spot,
// spot 1 first ([{no, place_name, lat, lng, date}], spotList in _lib/spots.js), [] otherwise; each before and after
// photo has its spot (1 to 4); its mission has its planned spots the same way. A mission with several spots is never in
// partner_missions: a cleanup sent without a mission has no photos for its other spots.
// contact: on a pending cleanup, {contact_name, whatsapp, email, lang} from the crew's application, for the reply that
// REJECT opens (the reasons, in English or Indonesian). null on the other lists, for a crew made with NEW PARTNER
// (no application), once DEACTIVATE wiped it, and before migration 0003.
import { err, handle, json, mediaFor, signedMediaUrl } from "../../_lib/util.js";
import { noApplicationsTable } from "../../_lib/applications.js";
import { noMissionsTable, nowMediaFor, nowParts } from "../../_lib/missions.js";
import { round3 } from "../../_lib/events.js";
import { THANKS, socialFor, thanksDays } from "../../_lib/social.js";
import { extraSpots, spotList, spotOf, withSpots } from "../../_lib/spots.js";

const marks = (a) => a.map(() => "?").join(",");

// The contact on the latest decided application of each of these partners: {partnerId: contact}, the same row the
// MISSIONS cards use. A contact DEACTIVATE wiped (contact_name '', no WhatsApp or email) is left out.
async function contactsFor(env, partnerIds) {
  const out = {};
  if (!partnerIds.length) return out;
  try {
    for (let i = 0; i < partnerIds.length; i += 90) {
      const chunk = partnerIds.slice(i, i + 90);
      const { results } = await env.DB.prepare(
        `SELECT a.partner_id, a.contact_name, a.whatsapp, a.email, a.lang FROM applications a
         WHERE a.partner_id IN (${marks(chunk)})
           AND a.id = (SELECT x.id FROM applications x WHERE x.partner_id = a.partner_id ORDER BY x.decided_at DESC LIMIT 1)`
      ).bind(...chunk).all();
      for (const r of results) {
        if (!r.contact_name && !r.whatsapp && !r.email) continue;
        out[r.partner_id] = {
          contact_name: r.contact_name || null, whatsapp: r.whatsapp || null, email: r.email || null,
          lang: r.lang === "id" ? "id" : "en",
        };
      }
    }
  } catch (e) {
    // Code deployed before migration 0003: no applications, so no contacts.
    if (!noApplicationsTable(e)) throw e;
  }
  return out;
}

// The missions with these ids, with their now photos and video as signed links: {id: mission}.
async function missionsFor(env, ids) {
  const out = {};
  if (!ids.length) return out;
  try {
    // D1 caps bound parameters at 100 per statement.
    for (let i = 0; i < ids.length; i += 90) {
      const chunk = ids.slice(i, i + 90);
      const { results } = await withSpots((sp) => env.DB.prepare(
        `SELECT id, no, status, removed_why, place_name, plan_date, task, currency, price_local, crew_local, crew_size,
           funded_eur, advance_eur, lat, lng, ${sp ? "spots" : "NULL AS spots"}
         FROM missions WHERE id IN (${marks(chunk)})`
      ).bind(...chunk).all());
      for (const m of results) {
        const r = { ...m, lat: round3(m.lat), lng: round3(m.lng) };
        out[m.id] = { ...r, spots: spotList(r, "plan_date"), now: [], now_video: null };
      }
    }
    const media = await nowMediaFor(env, Object.keys(out));
    const sign = async (r) => ({ key: r.key, url: await signedMediaUrl(env, r.key) });
    for (const [id, rows] of Object.entries(media)) {
      const { photos, video } = nowParts(rows);
      out[id].now = await Promise.all(photos.map(sign));
      out[id].now_video = video ? await sign(video) : null;
    }
  } catch (e) {
    // Code deployed before migration 0004: no missions, the list still works.
    if (!noMissionsTable(e)) throw e;
  }
  return out;
}

// Funded missions of these partners without a pending or approved cleanup: {partnerId: [mission]}.
async function linkableFor(env, partnerIds) {
  const out = {};
  if (!partnerIds.length) return out;
  try {
    for (let i = 0; i < partnerIds.length; i += 90) {
      const chunk = partnerIds.slice(i, i + 90);
      const { results } = await withSpots((sp) => env.DB.prepare(
        `SELECT m.id, m.no, m.place_name, m.plan_date, m.partner_id, m.funded_eur, m.advance_eur, m.lat, m.lng,
           ${sp ? "m.spots" : "NULL AS spots"} FROM missions m
         WHERE m.status = 'funded' AND m.partner_id IN (${marks(chunk)})
           AND NOT EXISTS (SELECT 1 FROM submissions s WHERE s.mission_id = m.id AND s.status IN ('pending', 'approved'))
         ORDER BY m.plan_date ASC, m.no ASC`
      ).bind(...chunk).all());
      for (const m of results) {
        if (extraSpots(m.spots).length) continue; // several spots: only its own cleanup, with photos for each spot
        (out[m.partner_id] ||= []).push({
          id: m.id, no: m.no, place_name: m.place_name, plan_date: m.plan_date,
          funded_eur: m.funded_eur, advance_eur: m.advance_eur, lat: round3(m.lat), lng: round3(m.lng),
        });
      }
    }
  } catch (e) {
    if (!noMissionsTable(e)) throw e;
  }
  return out;
}

export const onRequestGet = handle(async ({ request, env }) => {
  const status = new URL(request.url).searchParams.get("status") || "pending";
  if (!["pending", "approved", "rejected"].includes(status)) return err(400, "Unknown status.");
  const { results } = await env.DB.prepare(
    `SELECT s.*, p.name AS partner_name, p.slug AS partner_slug, p.url AS partner_url, p.active AS partner_active,
       (SELECT group_concat(o.id) FROM submissions o
         WHERE o.partner_id = s.partner_id AND o.cleanup_date = s.cleanup_date
           AND lower(o.place_name) = lower(s.place_name) AND o.id <> s.id AND o.status <> 'rejected') AS possible_duplicates
     FROM submissions s JOIN partners p ON p.id = s.partner_id
     WHERE s.status = ? ORDER BY ${status === "pending" ? "s.created_at ASC" : "COALESCE(s.reviewed_at, s.created_at) DESC"} LIMIT 200`
  ).bind(status).all();
  const media = await mediaFor(env, results.map((r) => r.id));
  const social = await socialFor(env, results.map((r) => r.id));
  // s.mission_id only exists after migration 0004; before it every submission has no mission.
  const missions = await missionsFor(env, [...new Set(results.map((r) => r.mission_id).filter(Boolean))]);
  const unlinked = (s) => !s.mission_id && s.status !== "rejected";
  const linkable = await linkableFor(env, [...new Set(results.filter(unlinked).map((r) => r.partner_id))]);
  const contacts = status === "pending" ? await contactsFor(env, [...new Set(results.map((r) => r.partner_id))]) : {};
  const pick = (rows) => Promise.all(rows.map(async (r) => ({
    key: r.key, url: await signedMediaUrl(env, r.key), content_type: r.content_type,
  })));
  // A photo also says its spot: 1 to the cleanup's number of spots (n), 1 for a cleanup with one spot.
  const pickPhotos = async (rows, n) => (await pick(rows)).map((p, i) => ({ ...p, spot: spotOf(rows[i], n) }));
  // A video also says which it is: 'before', 'after', or null (no stage, see the top of this file).
  const pickVideos = async (rows) => (await pick(rows)).map((v, i) => ({ ...v, stage: rows[i].stage ?? null }));
  const submissions = [];
  for (const s of results) {
    const m = media[s.id];
    const spots = spotList(s, "cleanup_date");
    const n = spots.length || 1;
    submissions.push({
      ...s,
      spots,
      consent: !!s.consent,
      possible_duplicates: s.possible_duplicates ? String(s.possible_duplicates).split(",") : [],
      media: { before: await pickPhotos(m.before, n), after: await pickPhotos(m.after, n), videos: await pickVideos(m.videos) },
      mission: (s.mission_id && missions[s.mission_id]) || null,
      partner_missions: (unlinked(s) && linkable[s.partner_id]) || [],
      post_links: social ? (social[s.id]?.post_links || { crew: null, sapu: null }) : null,
      thanks: social && s.status === "approved" ? (social[s.id]?.thanks ?? 0) : null,
      contact: contacts[s.partner_id] || null,
    });
  }
  if (status !== "approved") return json({ submissions });
  const days = await thanksDays(env);
  const caps = days === null ? null
    : { receipt: THANKS.perReceiptDay, site: THANKS.perSiteDay, busy_site: THANKS.busySite, busy_receipt: THANKS.busyReceipt };
  return json({ submissions, thanks_days: days, thanks_caps: caps });
});

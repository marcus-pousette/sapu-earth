// Missions with several spots (docs/missions.md, Spots; migration 0008). One mission, one cleanup, one receipt and one
// payment, however many spots it has. Spot 1 is the row's own place and day, as for every mission and cleanup before:
// a mission's place_name, lat, lng and plan_date, a cleanup's place_name, lat, lng and cleanup_date. Spots 2 to SPOTS.max
// are a JSON array in the row's spots column, [{place_name, lat, lng, date}], in spot order:
// - missions.spots: the plan, written by Sapu Earth for now (an UPDATE in the D1 console, docs/missions.md);
// - submissions.spots: the cleanup of such a mission, copied from the mission by POST /api/submit, with the day the crew
//   cleaned each spot;
// - uploads.spot: the spot a cleanup's before or after photo shows, 2 to SPOTS.max; NULL for spot 1, for every photo of
//   a mission with one spot, and for every video (a mission keeps one video before and one after, whatever its spots).
// The points of spots 2 to SPOTS.max are kept rounded to 3 decimals (about 100 m, what the public map shows anyway), so
// they hold nothing private: removing a mission (WIPE_PRIVATE in missions.js) and the 90-day trim (retention.js) leave
// them as they are.
// Before migration 0008 the columns are missing: withSpots runs the SQL without them, and every mission has one spot.
// This file exports no onRequest handler, so it never becomes a route.

export const SPOTS = { max: 4 };

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const r3 = (v) => Math.round(v * 1000) / 1000;
const coord = (v, lim) => (typeof v === "number" && Number.isFinite(v) && Math.abs(v) <= lim ? r3(v) : null);
const isDay = (v) => typeof v === "string" && DAY_RE.test(v) && Number.isFinite(Date.parse(v + "T00:00:00Z"));

// D1's error before migration 0008: no spots column on missions or submissions, no spot column on uploads.
export function noSpotsColumn(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such column: (?:\w+\.)?spots?\b|has no column named spots?\b/i.test(text);
}

// Runs fn(true), which may use the spots columns. Before migration 0008 that throws, and fn(false) runs instead, with
// SQL that does not know them. A single statement or batch is atomic in D1, so the first try never leaves half a write.
export async function withSpots(fn) {
  try {
    return await fn(true);
  } catch (e) {
    if (!noSpotsColumn(e)) throw e;
    return fn(false);
  }
}

// A row's spots 2 to SPOTS.max as stored, [{place_name, lat, lng, date}]: each with a place of at most 120 characters
// (LIMITS.place) and a real day, lat and lng both numbers (rounded to 3 decimals) or both null. [] for NULL, '[]', or
// anything that is not such a list: a broken value never stops a page, the mission then shows its first spot alone, and
// POST /api/submit takes no photo for a spot it does not know.
export function extraSpots(raw) {
  if (typeof raw !== "string" || !raw) return [];
  let a;
  try { a = JSON.parse(raw); } catch { return []; }
  if (!Array.isArray(a) || a.length > SPOTS.max - 1) return [];
  const out = [];
  for (const s of a) {
    if (!s || typeof s !== "object") return [];
    const place = typeof s.place_name === "string" ? s.place_name.trim() : "";
    if (!place || [...place].length > 120 || !isDay(s.date)) return [];
    const lat = coord(s.lat, 90), lng = coord(s.lng, 180), both = lat !== null && lng !== null;
    out.push({ place_name: place, lat: both ? lat : null, lng: both ? lng : null, date: s.date });
  }
  return out;
}

// A row's spots, spot 1 first, [{no, place_name, lat, lng, date}], or [] for a row with one spot (its own). dayCol names
// the row's own day: plan_date for a mission, cleanup_date for a cleanup. Spot 1's lat and lng are the row's own, exact
// for /admin/: what goes public rounds them (round3 in events.js).
export function spotList(row, dayCol) {
  const extra = extraSpots(row?.spots);
  if (!extra.length) return [];
  return [
    { no: 1, place_name: row.place_name, lat: row.lat ?? null, lng: row.lng ?? null, date: row[dayCol] },
    ...extra.map((s, i) => ({ no: i + 2, ...s })),
  ];
}

// The last day of a row's spots (YYYY-MM-DD), the day its cleanup can come after: a funded mission is LATE and OVERDUE
// counted from it. The row's own day when it has one spot.
export function lastDay(row, dayCol) {
  const own = row?.[dayCol];
  return [own, ...extraSpots(row?.spots).map((s) => s.date)].filter(isDay).sort().pop() || own;
}

// The same in SQL, for the missions row m (its alias): the housekeeping's late count. Only with migration 0008.
export const LAST_DAY_SQL = (m) => `max(${m}.plan_date, COALESCE((SELECT MAX(json_extract(j.value, '$.date'))
  FROM json_each(CASE WHEN json_valid(${m}.spots) THEN ${m}.spots ELSE '[]' END) j), ${m}.plan_date))`;

// The spot a photo row shows, 1 to n (uploads.spot; NULL, and a spot the row's list does not have, are spot 1).
export const spotOf = (r, n) => (Number.isInteger(r?.spot) && r.spot >= 2 && r.spot <= n ? r.spot : 1);

// For the English pages (/m/<no>, /missions): "a", "a and b", "a, b and c".
export const andList = (items) => (items.length < 2 ? items.join("")
  : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`);

// A list of days (YYYY-MM-DD) as the English pages write one ("5 Jan 2027"): each day once, the earliest first, the
// month and the year written once where they repeat. "5 and 6 Jan 2027", "31 Jan and 1 Feb 2027", "5, 6 and 7 Jan
// 2027". The month comes from the same en-GB format as a single day's.
export function fmtDays(days) {
  const parts = [...new Set(days.filter(isDay))].sort().map((d) => {
    const t = new Date(Date.parse(d + "T00:00:00Z"));
    return { d: t.getUTCDate(), m: t.toLocaleDateString("en-GB", { month: "short", timeZone: "UTC" }), y: t.getUTCFullYear() };
  });
  return andList(parts.map((p, i) => {
    const next = parts[i + 1];
    let s = String(p.d);
    if (!next || next.m !== p.m || next.y !== p.y) s += " " + p.m;
    if (!next || next.y !== p.y) s += " " + p.y;
    return s;
  }));
}

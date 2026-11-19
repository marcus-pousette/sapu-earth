// GET /m/<no> -> share page for a mission (the short link crews put in their bio). Carries Open
// Graph / Twitter tags for the state the mission is in, then sends people on: to the mission on the
// globe while it is open or funded (/#m-<no>), to its receipt once it is done (/#ev-<id>).
// The preview picture is always a photo. An open or funded mission with an MP4 video of the spot also
// names it (og:video), for apps that play one; MOV and WebM clips are left out there, most previews
// cannot play them. The mission post on the homepage plays every one.
// Open and funded missions of a deactivated partner are hidden too (DEACTIVATE removes them anyway),
// a done one stays: it is a receipt.
// Missions in review or removed (expired, declined, ...), and unknown numbers, get a small page with
// status 404: "This mission is no longer on the map." with a link to the globe, one to the list of
// missions (/missions) and the generic Sapu Earth preview tags. Before migration 0004 too. The page
// never says which case it is.
// A mission with several spots (docs/missions.md, Spots) names every place in the title and every place with its day in
// the description ("A crew of 15 cleans Pantai Kuta on 5 Jan 2027 and Pantai Legian on 6 Jan 2027.").
import { approvedEvents } from "../_lib/events.js";
import { noMissionsTable, nowMediaFor, nowParts, splitOf } from "../_lib/missions.js";
import { ID_RE, SITE, absUrl, amountText, esc, fmtNum, headOf, pageHeaders, publicMediaUrl } from "../_lib/util.js";
import { andList, spotList, withSpots } from "../_lib/spots.js";

const NO_RE = /^[1-9][0-9]{0,8}$/;

const STYLE = "body{font-family:system-ui,sans-serif;background:#f2ecdd;color:#1c1813;padding:24px}a{color:#ff5f00;font-weight:700}";
const SITE_DESC = "Trash gets picked. People get paid. You watch it happen.";

// origin: of the request, for the absolute preview image. noindex: the number may never be a page.
async function notFound(origin) {
  const image = `${origin}/site/social/sapu-earth-mark.png`; // the broom, square: a small card
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sapu Earth</title>
<meta name="description" content="${esc(SITE_DESC)}">
<meta name="robots" content="noindex">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Sapu Earth">
<meta property="og:title" content="Sapu Earth">
<meta property="og:description" content="${esc(SITE_DESC)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:url" content="${esc(SITE)}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="Sapu Earth">
<meta name="twitter:description" content="${esc(SITE_DESC)}">
<meta name="twitter:image" content="${esc(image)}">
<link rel="icon" href="/site/brand/sapu-sketch/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/site/brand/sapu-sketch/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/site/brand/sapu-sketch/apple-touch-icon.png">
<style>${STYLE}</style>
</head>
<body>
<p>This mission is no longer on the map.</p>
<p><a href="/">See the globe on sapu.earth</a></p>
<p><a href="/missions">See the missions on sapu.earth</a></p>
</body>
</html>`;
  // Short: a mission in review can be published any moment. No script on this page.
  return new Response(html, { status: 404, headers: await pageHeaders(null, { "cache-control": "public, max-age=60" }) });
}

// "14 Nov 2026"
function fmtDay(iso) {
  const t = Date.parse(iso + "T00:00:00Z");
  if (!Number.isFinite(t)) return String(iso ?? "");
  return new Date(t).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

const money = (n) => Number(n).toLocaleString("en", { maximumFractionDigits: 2 });

// What an open mission asks, as its /missions card says it: "Asking IDR 3,000,000 in all: IDR 100,000 for each person and
// IDR 1,500,000 for other costs.", a crew pay that does not split evenly (sent as one total) with its head count, and the
// price alone without a crew pay.
function askText(m) {
  const all = `Asking ${m.currency} ${money(m.price_local)} in all`;
  const crew = Number(m.crew_local);
  const s = m.crew_local === null || m.crew_local === undefined ? null : splitOf(Number(m.price_local), crew, m.crew_size);
  if (!s || crew === 0) return `${all}.`;
  if (!s.exact) return `${all}, with ${m.currency} ${money(crew)} of it for the crew of ${fmtNum(m.crew_size)}.`;
  return s.other > 0 ? `${all}: ${m.currency} ${money(s.each)} for each person and ${m.currency} ${money(s.other)} for other costs.`
    : `${all}: ${m.currency} ${money(s.each)} for each person, no other costs.`;
}

export async function onRequestGet({ request, env, params }) {
  const origin = new URL(request.url).origin;
  const no = params.no;
  if (typeof no !== "string" || !NO_RE.test(no) || !env.DB) return notFound(origin);
  let m, media, ev = null;
  try {
    m = await withSpots((sp) => env.DB.prepare(
      `SELECT m.id, m.no, m.status, m.place_name, m.plan_date, m.crew_size, m.currency, m.price_local, m.crew_local, m.submission_id,
         ${sp ? "m.spots" : "NULL AS spots"}
       FROM missions m JOIN partners p ON p.id = m.partner_id
       WHERE m.no = ? AND (m.status = 'done' OR (m.status IN ('open', 'funded') AND p.active = 1))`
    ).bind(Number(no)).first());
    if (!m) return notFound(origin);
    media = nowParts((await nowMediaFor(env, [m.id]))[m.id]);
    if (m.status === "done") {
      if (typeof m.submission_id !== "string" || !ID_RE.test(m.submission_id)) return notFound(origin);
      [ev] = await approvedEvents(env, { id: m.submission_id, limit: 1 });
      if (!ev) return notFound(origin);
    }
  } catch (e) {
    if (!noMissionsTable(e)) console.error(e);
    return notFound(origin);
  }

  // Every place, and every place with its day: "Pantai Kuta on 5 Jan 2027", or with several spots "Pantai Kuta on 5 Jan 2027
  // and Pantai Legian on 6 Jan 2027".
  const spots = spotList(m, "plan_date");
  const place = spots.length ? andList(spots.map((s) => s.place_name)) : m.place_name;
  const where = spots.length ? andList(spots.map((s) => `${s.place_name} on ${fmtDay(s.date)}`)) : `${place} on ${fmtDay(m.plan_date)}`;
  let title, desc, img, target, video = null;
  if (m.status === "done") {
    title = `Mission #${m.no} done: ${place}`;
    desc = `${amountText(ev.result.kg_estimate, ev.result.sacks)} by a crew of ${ev.crew.size}. Cleaned by ${ev.provider.name}.`;
    img = ev.media.after[0] || ev.media.before[0] || ev.mission?.now[0];
    target = `/#ev-${m.submission_id}`; // validated base32 above, so this is never an open redirect
  } else {
    if (m.status === "funded") {
      title = `Mission #${m.no} is funded: ${place}`;
      desc = `A crew of ${fmtNum(m.crew_size)} cleans ${where}.`;
    } else {
      title = `Mission #${m.no}: ${place}`;
      desc = `A local crew of ${fmtNum(m.crew_size)} wants to clean ${where}. ${askText(m)}`;
    }
    img = media.photos[0] ? publicMediaUrl(env, media.photos[0]) : null;
    if (media.video && media.video.content_type === "video/mp4") video = absUrl(origin, publicMediaUrl(env, media.video));
    target = `/#m-${m.no}`; // a number, so this is never an open redirect
  }
  const image = img ? absUrl(origin, img) : origin + "/site/social/sapu-earth-mark.png"; // without a photo, the broom (square: a small card)
  const videoTags = video ? `
<meta property="og:video" content="${esc(video)}">
<meta property="og:video:type" content="video/mp4">` : "";
  const url = `${origin}/m/${m.no}`;

  // The page's one script, allowed by its SHA-256 in the page's script policy (pageHeaders in _lib/util.js).
  const go = `location.replace(${JSON.stringify(target)});`;
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · Sapu Earth</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${esc(url)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Sapu Earth">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:url" content="${esc(url)}">
<meta name="twitter:card" content="${img ? "summary_large_image" : "summary"}">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
<meta name="twitter:image" content="${esc(image)}">${videoTags}
<meta http-equiv="refresh" content="0; url=${esc(target)}">
<link rel="icon" href="/site/brand/sapu-sketch/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/site/brand/sapu-sketch/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/site/brand/sapu-sketch/apple-touch-icon.png">
<style>${STYLE}</style>
</head>
<body>
<p>${esc(desc)}</p>
<p><a href="${esc(target)}">See mission #${esc(m.no)} on sapu.earth</a></p>
<script>${go}</script>
</body>
</html>`;
  // Short: the page follows the mission from open to funded to done.
  return new Response(html, { headers: await pageHeaders(go, { "cache-control": "public, max-age=60" }) });
}
export const onRequestHead = headOf(onRequestGet);

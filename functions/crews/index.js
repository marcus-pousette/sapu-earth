// GET /crews -> the list of crews (docs/upload-flow.md, The list of crews): every active crew (listedCrews in
// functions/_lib/crews.js). First the crews with an approved cleanup or a public mission, newest activity first, with
// their live logo or their letters, name, country, the totals of their approved receipts, their newest receipt and their
// open and funded missions; then, under JUST JOINED · FIRST MISSION COMING, the crews with neither yet, the newest
// first, with their logo or letters, name and country only. English, rendered here with no script, so it works without
// JavaScript on any phone. /crews/ reaches this Function too, and HEAD gets its status and headers (headOf).
// ?country=XX lists the crews of one country in both groups, but only when a country chip offers it (2 or more
// countries); any other value lists everyone and is never echoed. While no crew is active the page says so (NO CREW IS
// LISTED YET, noindex), never sample crews and never that crews are joining. The CSP allows only this origin's styles,
// fonts and pictures: the page has no inline style or script, and data: is for the noise texture in styles.css. Every
// crew text goes through esc(). A number keeps its unit, a day its month and year, and a " · " its dot on one line (nb,
// DOT).
import { SITE, esc, fmtNum, headOf } from "../_lib/util.js";
import { DOT, JOIN, PAGE_HEADERS as HEADERS, countryName, eurText, fmtDay, listedCrews, missionsListed, nb } from "../_lib/crews.js";
import { monogram } from "../_lib/logos.js";
import { ASSET_V } from "../_lib/asset-version.js"; // written by scripts/build-site.sh on every build

const TITLE = "The crews · Sapu Earth";
const DESC = "The local cleanup crews on Sapu Earth, with their cleanups, kilograms and what Sapu Earth paid them, all from public receipts, and the spots they want to clean next.";
const EMPTY_DESC = "The local cleanup crews on Sapu Earth. No crew is listed yet."; // also what a link preview says
// While every crew on the list is under JUST JOINED, DESC would promise cleanups and kilograms the page does not have.
const JOINED_DESC = "The local cleanup crews on Sapu Earth. The crews listed so far just joined, and their first missions are coming.";
const CARD_MISSIONS = 3; // missions on a card; the rest are one tap away on /p/<slug>

const plural = (n, one, many) => `${fmtNum(n)} ${n === 1 ? one : many}`;

// missions: ALL MISSIONS next to SEE THE GLOBE while the list of missions has something (missionsListed, the rule of THE
// MISSIONS in the homepage footer). A listed crew is not enough: one cleanup sent with No mission lists a crew, and
// /missions would then say NO MISSION IS LISTED YET.
function page(origin, { noindex, desc, main, missions = false }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(TITLE)}</title>
<meta name="description" content="${esc(desc)}">${noindex ? `\n<meta name="robots" content="noindex">` : ""}
<link rel="canonical" href="${SITE}/crews">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Sapu Earth">
<meta property="og:title" content="${esc(TITLE)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${SITE}/crews">
<meta property="og:image" content="${esc(origin + "/site/social/sapu-earth-mark.png")}">
<meta property="og:image:width" content="1024">
<meta property="og:image:height" content="1024">
<meta property="og:image:alt" content="Sapu Earth's logo, a hand-drawn yellow broom">
<meta name="twitter:card" content="summary">
<link rel="icon" href="/site/brand/sapu-sketch/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/site/brand/sapu-sketch/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/site/brand/sapu-sketch/apple-touch-icon.png">
<link rel="stylesheet" href="/site/fonts.css?v=${ASSET_V}">
<link rel="stylesheet" href="/site/styles.css?v=${ASSET_V}">
<link rel="stylesheet" href="/site/forms.css?v=${ASSET_V}">
</head>
<body class="form-page">
<header class="fp-top">
  <a class="logo logo-sm" href="/">SAPU<br>EARTH</a>
</header>
<main class="fp-main">
  <h1 class="fp-title"><mark>THE CREWS</mark></h1>
${main}
  <p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a>${missions ? ` <a class="btn" href="/missions">ALL MISSIONS</a>` : ""}</p>
</main>
<footer>
  <p><a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a></p>
</footer>
</body>
</html>`;
}

// "Indonesia · 4 cleanups · 310 kg · 42 sacks · €95 paid · thanked 47 times", or "Indonesia · no cleanups yet", as
// escaped HTML. Thanks only above 0, and never in the order.
function cardLine(c) {
  const parts = [];
  const country = countryName(c.country);
  if (country) parts.push(esc(country));
  if (c.cleanups > 0) {
    parts.push(nb(plural(c.cleanups, "cleanup", "cleanups")));
    if (c.kg > 0) parts.push(nb(`${fmtNum(c.kg)} kg`));
    if (c.sacks > 0) parts.push(nb(plural(c.sacks, "sack", "sacks")));
    if (c.paid_eur > 0) parts.push(nb(`${eurText(c.paid_eur)} paid`));
    if (c.thanks > 0) parts.push(nb(`thanked ${fmtNum(c.thanks)} ${c.thanks === 1 ? "time" : "times"}`));
  } else {
    parts.push("no cleanups yet");
  }
  return parts.join(DOT);
}

// The crew's live logo (56 px), or its letters while it has none.
const face = (c) => (c.logo
  ? `<img class="cx-logo" src="${esc(c.logo)}" alt="" width="56" height="56" loading="lazy" decoding="async">`
  : `<span class="cx-mono" aria-hidden="true">${esc(monogram(c.name))}</span>`);

function card(c) {
  const slug = esc(c.slug);
  const head = face(c);
  // The label inside the link, so the row wraps as one block, like a mission row.
  const last = c.last
    ? `\n      <p class="cx-last"><a href="/r/${esc(c.last.id)}"><b>LAST CLEANUP</b><span>${nb(fmtDay(c.last.cleanup_date))}${DOT}${esc(c.last.place_name)}</span></a></p>`
    : "";
  let ms = "";
  if (c.missions.length) {
    const rows = c.missions.slice(0, CARD_MISSIONS).map((m) => {
      const funded = m.status === "funded";
      return `\n        <li><a href="/m/${esc(m.no)}"><i class="mpin-tag${funded ? " mpin-funded" : ""}">#${esc(m.no)}</i><span>${funded ? "funded" : "open"}${DOT}${nb(fmtDay(m.plan_date))}${DOT}${esc(m.place_name)}</span></a></li>`;
    });
    const more = c.missions.length - CARD_MISSIONS;
    if (more > 0) rows.push(`\n        <li><a href="/p/${slug}"><span>+${more} more mission${more === 1 ? "" : "s"}</span></a></li>`);
    ms = `\n      <ul class="cx-ms">${rows.join("")}\n      </ul>`;
  }
  return `
    <li class="cx-card" data-slug="${slug}" data-cleanups="${esc(c.cleanups)}" data-kg="${esc(c.kg)}" data-sacks="${esc(c.sacks)}" data-paid="${esc(c.paid_eur)}">
      <a class="cx-head" href="/p/${slug}">${head}<span class="cx-name"><b>${esc(c.name)}</b><small>${cardLine(c)}</small></span></a>${last}${ms}
    </li>`;
}

// A JUST JOINED card: a crew Sapu Earth works with that has no approved cleanup and no public mission yet. Its logo or
// letters, its name linking /p/<slug> and "Indonesia · first mission coming", nothing else: it has no numbers to show,
// and like every card it never shows the website or anything from the application. "first mission coming" stays on one
// line, so a narrow phone breaks after the dot, never inside it.
function joinedCard(c) {
  const slug = esc(c.slug);
  const country = countryName(c.country);
  return `
    <li class="cx-card cx-new" data-slug="${slug}">
      <a class="cx-head" href="/p/${slug}">${face(c)}<span class="cx-name"><b>${esc(c.name)}</b><small>${country ? esc(country) + DOT : ""}${nb("first mission coming")}</small></span></a>
    </li>`;
}

// Each line says only what the code keeps: every active crew is listed, under JUST JOINED until it has a mission or a
// cleanup on sapu.earth (a crew whose first mission came and went stays out of it, listedCrews in _lib/crews.js);
// the totals come from approved receipts, kilograms may be estimated (the crew form says so), a funded mission's day is
// the crew's plan, Sapu Earth checks a logo but cannot vouch for it, and thanks are taps that mark nobody
// (docs/upload-flow.md, Thanks), so they count taps, not people.
const HOW = [
  "A crew shows up here as soon as it works with Sapu Earth. Until it has a mission or a cleanup on sapu.earth, it is under JUST JOINED with its name, logo and country only. A crew Sapu Earth stops working with leaves the list; its receipts stay on the globe.",
  "The totals add up each crew's approved receipts. Crews count the sacks and weigh or estimate the kilograms themselves, and Sapu Earth checks the photos and numbers of every cleanup before it becomes a receipt.",
  "An open mission is a spot a crew wants to clean, waiting for funding. A funded one is paid for by Sapu Earth, and the crew plans to clean it on the day shown.",
  "Crews send their own logos, and Sapu Earth checks each one before it shows.",
  "Thanks are one tap under a receipt. Nobody signs in and nothing marks who tapped, so one person can thank more than once: read them as applause, not votes. They are never money.",
  "Newest activity first, and under JUST JOINED the crews that joined most recently first. No crew is ranked by kilograms, money or thanks.",
];
// The line under the title. While every crew on the page is under JUST JOINED, there are no totals to explain yet.
const SUB = "// local cleanup crews on sapu.earth. the totals add up their public receipts.";
const SUB_JOINED = "// local cleanup crews on sapu.earth. the crews listed so far just joined.";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  let crews, anyMission;
  try {
    if (!env.DB) throw new Error("no DB binding");
    // The link to /missions is never worth a 503: if its read fails, the foot leaves it out.
    [crews, anyMission] = await Promise.all([listedCrews(env),
      missionsListed(env).catch((e) => { console.error("crews: missions", e); return false; })]);
  } catch (e) {
    console.error("crews", e);
    const main = `  <p class="fp-lead">THE CREWS COULD NOT BE LOADED. TRY AGAIN IN A MINUTE.</p>`;
    return new Response(page(url.origin, { noindex: true, desc: DESC, main }), { status: 503, headers: { ...HEADERS, "cache-control": "no-store" } });
  }

  // Country chips, only with crews from 2 or more countries: most crews first, then by name. They count and filter
  // both groups, JUST JOINED included.
  const count = new Map();
  for (const c of crews) if (typeof c.country === "string" && c.country) count.set(c.country, (count.get(c.country) || 0) + 1);
  const countries = [...count].map(([code, n]) => ({ code, n, name: countryName(code) }))
    .sort((x, y) => y.n - x.n || x.name.localeCompare(y.name, "en"));
  const chips = countries.length >= 2;
  const want = String(url.searchParams.get("country") || "").toLowerCase();
  const pick = chips && want ? countries.find((x) => x.code.toLowerCase() === want) || null : null;
  const shown = pick ? crews.filter((c) => c.country === pick.code) : crews;
  const working = shown.filter((c) => !c.justJoined), joined = shown.filter((c) => c.justJoined);

  const allJoined = !working.length && joined.length > 0;
  const parts = [`  <p class="sub">${esc(allJoined ? SUB_JOINED : SUB)}</p>`];
  if (chips) {
    const chip = (href, label, on) => `\n    <a href="${esc(href)}"${on ? ` aria-current="page"` : ""}>${esc(label)}</a>`;
    parts.push(`  <nav class="cx-chips" aria-label="Countries">${chip("/crews", `ALL (${crews.length})`, !pick)}${countries
      .map((x) => chip(`/crews?country=${encodeURIComponent(x.code)}`, `${x.name.toUpperCase()} (${x.n})`, x === pick)).join("")}\n  </nav>`);
  }
  if (shown.length) {
    if (working.length) parts.push(`  <ul class="cx-list">${working.map(card).join("")}\n  </ul>`);
    // JUST JOINED at the bottom, under its own title, so a crew with no work on sapu.earth yet never stands between
    // the crews whose receipts and missions are there. The title's two halves wrap as blocks on a phone (forms.css), so
    // it reads "JUST JOINED ·" over "FIRST MISSION COMING", never with FIRST left behind.
    if (joined.length) {
      parts.push(`  <section class="cx-sec">
    <h2 class="cx-title"><span>JUST JOINED&nbsp;·</span> <span>FIRST MISSION COMING</span></h2>
    <ul class="cx-list">${joined.map(joinedCard).join("")}
    </ul>
  </section>`);
    }
    parts.push(`  <section class="panel cx-how">
    <h2 class="panel-title">HOW THIS LIST WORKS</h2>
    <ul>${HOW.map((li) => `\n      <li>${li}</li>`).join("")}
    </ul>
  </section>`);
  } else {
    parts.push(`  <section class="panel cx-empty">
    <h2 class="panel-title">NO CREW IS LISTED YET</h2>
    <p>A crew shows up here as soon as it works with Sapu Earth.</p>
  </section>`);
  }
  parts.push(JOIN);

  // The description follows the page shown, so a link preview of a country whose crews all just joined promises no
  // cleanups or kilograms either.
  const desc = !crews.length ? EMPTY_DESC : allJoined ? JOINED_DESC : DESC;
  const html = page(url.origin, { noindex: !crews.length || !!pick, desc, main: parts.join("\n"), missions: anyMission });
  return new Response(html, { headers: { ...HEADERS, "cache-control": "public, max-age=300" } });
}
export const onRequestHead = headOf(onRequestGet);

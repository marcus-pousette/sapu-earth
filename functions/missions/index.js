// GET /missions -> the list of missions (docs/upload-flow.md, The list of missions): the missions on sapu.earth in the
// order a mission goes, OPEN (not funded yet), FUNDED (the cleanup is coming) and CLEANED (done, its cleanup a public
// receipt), from missionList in functions/_lib/crews.js: the open and funded ones are those of GET /api/missions (active
// crews only, an open one for 28 days after it was published), the cleaned ones every done mission whose cleanup is an
// approved receipt, also of a crew Sapu Earth no longer works with (then with its name alone, as on its receipt).
// English, rendered here with no script, so it works without JavaScript on any phone; /missions/ reaches it too, and HEAD
// gets its status and headers (headOf).
// ?status=open|funded|cleaned shows one state, but only when a chip offers it (missions in 2 or more states); any other
// value shows them all and is never echoed, and a filtered page is noindex. Until a mission is listed (also before
// migration 0004) the page says so (NO MISSION IS LISTED YET, noindex), never sample missions. No photos of the spots
// (the site has no small copies yet; the mission post and the receipt show them) and no logos (/crews and /p/<slug> have
// them). The headers of /crews (PAGE_HEADERS). Every crew text goes through esc(); a number keeps its unit, a day its
// month and year, and " · " its dot on one line (nb, DOT).
// A mission with several spots (docs/missions.md, Spots) names every place in its head ("Pantai Kuta and Pantai Legian") and
// says its days ("days 5 and 6 Jan 2027"; once cleaned, the days of its receipt).
import { ID_RE, SITE, esc, fmtNum, headOf } from "../_lib/util.js";
import { DOT, JOIN, PAGE_HEADERS, countryName, eurText, fmtDay, missionList, nb } from "../_lib/crews.js";
import { MISSION_LIMITS, splitOf } from "../_lib/missions.js";
import { andList, fmtDays } from "../_lib/spots.js";
import { ASSET_V } from "../_lib/asset-version.js"; // written by scripts/build-site.sh on every build

const TITLE = "The missions · Sapu Earth";
const DESC = "The cleanup missions on Sapu Earth: the spots local crews want to clean, waiting for funding, funded or cleaned, each cleaned one with its public receipt.";
const EMPTY_DESC = "The cleanup missions on Sapu Earth. No mission is listed yet."; // also what a link preview says
const ALL_CLEANED = 6; // cleaned missions on the page with every state; ?status=cleaned shows them all (up to CLEANED_CAP)

// The globe's two glyphs, exactly GLYPH in site/app.js and the legend in index.html: change the three together.
const GLYPH = {
  open: '<svg class="gl" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 7h6c2 1.5 2.6 4.5 1.4 6.6-.5.8-1.2 1.2-2 1.2H5.6c-.8 0-1.5-.4-2-1.2C2.4 11.5 3 8.5 5 7z"/><path d="M6.6 7l.7-2h1.4l.7 2M7.3 5L5.6 3M8.7 5l1.7-2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  funded: '<svg class="gl" viewBox="0 0 16 16" aria-hidden="true"><g transform="rotate(35 8 8)"><rect x="7.1" y=".6" width="1.8" height="8.2" rx=".9"/><path fill-rule="evenodd" d="M5.4 8.2h5.2l1.8 6.2H3.6zM5.2 9.9h5.6v.9H5.2z"/></g></svg>',
};
// The three states in the order a mission goes: the chip's word and the section's title.
const STATES = [
  { key: "open", chip: "OPEN", title: "OPEN · NOT FUNDED YET" },
  { key: "funded", chip: "FUNDED", title: "FUNDED · CLEANUP COMING" },
  { key: "cleaned", chip: "CLEANED", title: "CLEANED · WITH ITS RECEIPT" },
];
// A state's mark as in the legend under the globe, next to its title: the yellow tag with a trash bag (open), the ink tag
// with a broom (funded), the green dot on a white rim (cleaned). Decorative, the title says it.
const legendMark = (key) => (key === "cleaned" ? `<i class="lg-dot" aria-hidden="true"></i>`
  : `<i class="mpin-tag${key === "funded" ? " mpin-funded" : ""}" aria-hidden="true">${GLYPH[key]}#</i>`);
// A mission's own tag on its card, as on the globe: #12 with its glyph, or once cleaned the green dot.
const tag = (key, no) => (key === "cleaned" ? `<i class="mpin-tag mx-done"><i class="lg-dot" aria-hidden="true"></i>#${esc(no)}</i>`
  : `<i class="mpin-tag${key === "funded" ? " mpin-funded" : ""}">${GLYPH[key]}#${esc(no)}</i>`);

// Each line says only what the code keeps: what shows (published or funded, never in review), the crew's pay is inside
// the price (crew_local <= price_local in functions/api/mission/index.js), the 28 days of an open mission
// (PUBLIC_MISSION), a funded mission's day is the crew's plan, a cleaned one is an approved receipt, removed missions
// never show, DEACTIVATE takes open and funded ones off and leaves cleaned ones, and the order.
const HOW = [
  "A mission is a spot a local crew wants to clean, with the day and the price the crew asks in its own money. The crew's pay is part of that price, and the rest is for other costs. It shows here once Sapu Earth publishes or funds it.",
  `Open: not funded yet. An open mission nobody funds leaves this list ${MISSION_LIMITS.expireDays} days after it was published.`,
  "Funded: Sapu Earth pays for it, and the crew plans to clean it on the day shown.",
  "Cleaned: the crew sent the cleanup, and Sapu Earth checked its photos and numbers before it became a receipt. Crews count the sacks and weigh or estimate the kilograms themselves.",
  "A mission that is withdrawn, declined or cancelled never shows here. When Sapu Earth stops working with a crew, its open and funded missions leave the list, and its cleaned ones stay, like its receipts.",
  "Open and funded missions show the soonest day first and a day that has passed last, cleaned ones the newest cleanup first. Nothing is ranked by money or kilograms.",
];

const plural = (n, one, many) => `${fmtNum(n)} ${n === 1 ? one : many}`;
// "IDR 1,500,000", as the mission post writes the crew's money, or "" for a value the page cannot show.
const local = (cur, v) => (/^[A-Z]{3}$/.test(cur || "") && v !== null && v !== undefined && Number.isFinite(Number(v))
  ? `${cur} ${Number(v).toLocaleString("en", { maximumFractionDigits: 2 })}` : "");
const line = (parts) => parts.filter(Boolean).join(DOT);

function page(origin, { noindex, desc, main, crews = false }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(TITLE)}</title>
<meta name="description" content="${esc(desc)}">${noindex ? `\n<meta name="robots" content="noindex">` : ""}
<link rel="canonical" href="${SITE}/missions">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Sapu Earth">
<meta property="og:title" content="${esc(TITLE)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${SITE}/missions">
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
  <h1 class="fp-title"><mark>THE MISSIONS</mark></h1>
${main}
  <p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a>${crews ? ` <a class="btn" href="/crews">ALL CREWS</a>` : ""}</p>
</main>
<footer>
  <p><a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a></p>
</footer>
</body>
</html>`;
}

// BY: the crew's name, linking its page while it is active, the name alone after (as on its receipts).
const by = (crew) => (crew.slug
  ? `\n      <p class="cx-last"><a href="/p/${esc(crew.slug)}"><b>BY</b><span>${esc(crew.name)}</span></a></p>`
  : `\n      <p class="cx-last mx-by"><b>BY</b><span>${esc(crew.name)}</span></p>`);

// Its places, every spot's: "Pantai Kuta", "Pantai Kuta and Pantai Legian".
const places = (m) => (m.spots?.length ? andList(m.spots.map((s) => s.place_name)) : m.place_name);
// Its day as a fact: "day 5 Jan 2027" on one line, or for several spots "days 5 and 6 Jan 2027", which may wrap.
// word: [one day, several days], like ["day", "days"] or ["cleaned", "cleaned"].
const dayFact = (m, [one, many], own) => (m.spots?.length ? esc(`${many} ${fmtDays(m.spots.map((s) => s.date))}`)
  : nb(`${one} ${fmtDay(own)}`));

// One card: the tag, the place (underlined: the head is the link), a line of facts and a line of money, then BY.
const card = (key, m, href, facts, money) => `
    <li class="cx-card mx-card" id="m-${esc(m.no)}" data-no="${esc(m.no)}" data-kind="${key}">
      <a class="mx-head" href="${href}">${tag(key, m.no)}<span class="cx-name"><b>${esc(places(m))}</b><small>${facts}</small><small class="mx-money">${money}</small></span></a>${by(m.crew)}
    </li>`;

// The crew's pay and the other costs of a price for its money line (splitOf): "crew pay 15 × IDR 100,000", with its head
// count when it does not split evenly ("crew pay IDR 100,000 for 15 people"), "no crew pay" for 0, then "other costs IDR
// 1,500,000" or "no other costs". [] when the numbers do not fit together.
function payParts(m) {
  const s = local(m.currency, m.price_local) && local(m.currency, m.crew_local) ? splitOf(Number(m.price_local), Number(m.crew_local), m.crew_size) : null;
  if (!s) return [];
  const crew = Number(m.crew_local);
  const pay = crew === 0 ? "no crew pay" : s.exact ? `crew pay ${fmtNum(m.crew_size)} × ${local(m.currency, s.each)}`
    : s.each !== null ? `crew pay ${local(m.currency, crew)} for ${plural(m.crew_size, "person", "people")}` : `crew pay ${local(m.currency, crew)} in all`;
  return [nb(pay), nb(s.other > 0 ? `other costs ${local(m.currency, s.other)}` : "no other costs")];
}
// An open or funded mission, linking /m/<no>: "Indonesia · day 21 Nov 2026 · crew of 8", then "asking IDR 2,000,000 in
// all · crew pay 8 × IDR 150,000 · other costs IDR 800,000" or "funded €100 · asked IDR 2,000,000 in all · crew pay ...".
function liveCard(m) {
  const key = m.status === "funded" ? "funded" : "open";
  const ask = local(m.currency, m.price_local);
  const money = key === "funded"
    ? line([nb(m.funded_eur > 0 ? `funded ${eurText(m.funded_eur)}` : "funded"), ask && nb(`asked ${ask} in all`), ...payParts(m)])
    : line([nb(ask ? `asking ${ask} in all` : "asking ?"), ...payParts(m)]);
  const facts = line([esc(countryName(m.country)), dayFact(m, ["day", "days"], m.plan_date), nb(`crew of ${fmtNum(m.crew_size)}`)]);
  return card(key, m, `/m/${esc(m.no)}`, facts, money);
}

// A cleaned mission, linking its receipt /r/<id>: the receipt's own day and numbers, "€60 paid" or "payment pending".
function cleanedCard(m) {
  const facts = line([esc(countryName(m.country)), dayFact(m, ["cleaned", "cleaned"], m.cleanup_date), m.kg > 0 && nb(`${fmtNum(m.kg)} kg`),
    m.sacks > 0 && nb(plural(m.sacks, "sack", "sacks")), nb(`crew of ${fmtNum(m.crew_size)}`)]);
  const money = m.paid_eur === null ? "payment pending" : nb(`${eurText(m.paid_eur)} paid`);
  const href = ID_RE.test(String(m.receipt_id)) ? `/r/${m.receipt_id}` : `/m/${esc(m.no)}`;
  return card("cleaned", m, href, facts, money);
}

const section = (st, cards, n, tail = "") => `  <section class="mx-sec">
    <h2 class="mx-title">${legendMark(st.key)}<span>${st.title}&nbsp;<small>(${fmtNum(n)})</small></span></h2>
    <ul class="cx-list">${cards}
    </ul>${tail}
  </section>`;

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  let data;
  try {
    if (!env.DB) throw new Error("no DB binding");
    data = await missionList(env);
  } catch (e) {
    console.error("missions", e);
    const main = `  <p class="fp-lead">THE MISSIONS COULD NOT BE LOADED. TRY AGAIN IN A MINUTE.</p>`;
    return new Response(page(url.origin, { noindex: true, desc: DESC, main }), { status: 503, headers: { ...PAGE_HEADERS, "cache-control": "no-store" } });
  }

  const live = { open: data.live.filter((m) => m.status === "open"), funded: data.live.filter((m) => m.status === "funded") };
  const count = { open: live.open.length, funded: live.funded.length, cleaned: data.cleanedTotal };
  const total = count.open + count.funded + count.cleaned;
  // State chips, only with missions in 2 or more states, and only for a state that has some: as the country chips on /crews.
  const present = STATES.filter((s) => count[s.key] > 0);
  const chips = present.length >= 2;
  const want = String(url.searchParams.get("status") || "").toLowerCase();
  const pick = chips ? present.find((s) => s.key === want) || null : null;

  const parts = [`  <p class="sub">// dirty spots local crews want to clean. open = waiting for funding. funded = it happens. cleaned = done, with its receipt.</p>`];
  if (!total) {
    parts.push(`  <section class="panel cx-empty">
    <h2 class="panel-title">NO MISSION IS LISTED YET</h2>
    <p>A mission is a spot a local crew wants to clean, with the day and the price. It shows up here once Sapu Earth publishes or funds it: open while it waits for funding, then funded, then cleaned, with its receipt.</p>
    <p class="cx-last"><a href="https://www.instagram.com/sapu.earth" rel="noopener"><span>FOLLOW ALONG ON INSTAGRAM</span> ↗</a></p>
    <p class="hint">Already a crew with us? Post a mission on your crew page: open the private link from our WhatsApp or email message.</p>
  </section>`);
  } else {
    if (chips) {
      const chip = (href, label, on) => `\n    <a href="${esc(href)}"${on ? ` aria-current="page"` : ""}>${esc(label)}</a>`;
      parts.push(`  <nav class="cx-chips" aria-label="Missions by state">${chip("/missions", `ALL (${fmtNum(total)})`, !pick)}${present
        .map((s) => chip(`/missions?status=${s.key}`, `${s.chip} (${fmtNum(count[s.key])})`, s === pick)).join("")}\n  </nav>`);
    }
    for (const s of pick ? [pick] : present) {
      if (s.key !== "cleaned") {
        parts.push(section(s, live[s.key].map(liveCard).join(""), count[s.key]));
        continue;
      }
      // With every state on the page, the newest ALL_CLEANED cleaned ones and a link to the rest; alone, all of them.
      const shown = chips && !pick ? data.cleaned.slice(0, ALL_CLEANED) : data.cleaned;
      const tail = count.cleaned <= shown.length ? ""
        : chips && !pick ? `\n    <p class="mx-more"><a href="/missions?status=cleaned">SEE ALL ${fmtNum(count.cleaned)} CLEANED MISSIONS →</a></p>`
          : `\n    <p class="hint mx-cap">The newest ${fmtNum(shown.length)} of ${fmtNum(count.cleaned)} cleaned missions. Every receipt is on the globe.</p>`;
      parts.push(section(s, shown.map(cleanedCard).join(""), count.cleaned, tail));
    }
    parts.push(`  <section class="panel cx-how">
    <h2 class="panel-title">HOW THIS LIST WORKS</h2>
    <ul>${HOW.map((li) => `\n      <li>${li}</li>`).join("")}
    </ul>
  </section>`);
  }
  parts.push(JOIN);

  // ALL CREWS while a crew behind a listed mission is on /crews: an open or funded one, or a cleaned one of an active crew.
  const crews = data.live.length > 0 || data.cleaned.some((m) => m.crew.slug);
  const html = page(url.origin, { noindex: !total || !!pick, desc: total ? DESC : EMPTY_DESC, main: parts.join("\n"), crews });
  return new Response(html, { headers: { ...PAGE_HEADERS, "cache-control": "public, max-age=300" } });
}
export const onRequestHead = headOf(onRequestGet);

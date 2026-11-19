// GET /p/<slug> -> public page for an active partner: who they are and their approved cleanups.
// With a live logo (functions/_lib/logos.js) it stands next to the name. The link preview uses the first after
// photo; a crew without a receipt yet gets its logo there instead, so sharing its page shows the crew's own picture,
// and a crew with neither the broom, as /crews and /missions (since 2026-11-17; a share showed no picture before).
// NEXT UP (between the numbers and THE RECEIPTS) lists the crew's open and funded missions on sapu.earth, the same rule
// as the list of crews (crewMissions in functions/_lib/crews.js), each with its first photo of the spot, and ALL CREWS
// at the foot links that list, /crews. No script. The description (also the link preview's text) gives the crew's
// cleanups only once it has one: a crew listed for a mission alone, or under JUST JOINED, gets no "trash removed" it has
// not done, and the page shows its numbers (kg removed, cleanups, sacks) only once it has a receipt, so a crew that just
// joined, which /crews links from its first day, never shows three zeros; THE RECEIPTS says "No published cleanups yet.".
// Thanks (docs/upload-flow.md, Thanks): under the numbers, how often visitors thanked the crew on its receipts, and each
// receipt row its own count, both only above 0; never in the description or the preview, where a count would go stale.
import { approvedEvents } from "../_lib/events.js";
import { liveLogoKey, logoUrl } from "../_lib/logos.js";
import { PAGE_HEADERS, crewMissions, fmtDay } from "../_lib/crews.js";
import { SLUG_RE, absUrl, amountText, esc, fmtNum, headOf } from "../_lib/util.js";
import { ASSET_V } from "../_lib/asset-version.js"; // written by scripts/build-site.sh on every build

const notFound = () => new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });

export async function onRequestGet({ request, env, params }) {
  const slug = params.slug;
  if (typeof slug !== "string" || !SLUG_RE.test(slug) || !env.DB) return notFound();
  let partner, events, logoKey, next;
  try {
    partner = await env.DB.prepare("SELECT id, slug, name, url, country FROM partners WHERE slug = ? AND active = 1").bind(slug).first();
    if (!partner) return notFound();
    events = await approvedEvents(env, { partnerId: partner.id, limit: 500 });
    logoKey = await liveLogoKey(env, partner.id);
    next = await crewMissions(env, partner.id);
  } catch (e) {
    console.error(e);
    return notFound();
  }

  const origin = new URL(request.url).origin;
  const totalKg = events.reduce((s, e) => s + (e.result.kg_estimate || 0), 0);
  const totalSacks = events.reduce((s, e) => s + (e.result.sacks || 0), 0);
  const totalThanks = events.reduce((s, e) => s + (typeof e.thanks === "number" ? e.thanks : 0), 0);
  const safeSite = partner.url && /^https?:\/\//i.test(partner.url) ? partner.url : null;
  const cover = events.find((e) => e.media.after[0])?.media.after[0];
  const logo = logoUrl(logoKey);
  const title = `${partner.name} · Sapu Earth`;
  const amount = totalKg > 0 ? `${fmtNum(totalKg)} kg removed` : totalSacks > 0 ? `${fmtNum(totalSacks)} sacks of trash removed` : "trash removed";
  const desc = events.length
    ? `${events.length} cleanup${events.length === 1 ? "" : "s"}, ${amount} by ${partner.name}. Every receipt public on sapu.earth.`
    : `${partner.name}, a local cleanup crew on sapu.earth. No published cleanups yet.`;
  const preview = cover
    ? `<meta property="og:image" content="${esc(absUrl(origin, cover))}">\n<meta name="twitter:card" content="summary_large_image">`
    : logo ? `<meta property="og:image" content="${esc(absUrl(origin, logo))}">\n<meta name="twitter:card" content="summary">`
    : `<meta property="og:image" content="${esc(origin + "/site/social/sapu-earth-mark.png")}">
<meta property="og:image:width" content="1024">
<meta property="og:image:height" content="1024">
<meta property="og:image:alt" content="Sapu Earth's logo, a hand-drawn yellow broom">
<meta name="twitter:card" content="summary">`;
  const h1 = `<h1 class="fp-title"><mark>${esc(partner.name.toUpperCase())}</mark></h1>`;

  // A day keeps its month and year, an amount its unit, "crew of 8" its number, and " · " its dot on one line, in
  // NEXT UP and THE RECEIPTS alike (as on /crews).
  const nb = (text) => esc(text).replace(/ /g, "&nbsp;");
  const rows = events.map((e) => `
      <li>
        <a href="/r/${esc(e.id)}">
          ${e.media.after[0] ? `<img src="${esc(e.media.after[0])}" alt="" loading="lazy">` : `<span class="noimg"></span>`}
          <span class="row-text">
            <b>${esc(e.location.name)}</b>
            <small>${esc(e.date)}&nbsp;· ${nb(amountText(e.result.kg_estimate, e.result.sacks).replace(" of trash", "").replace(" removed", "").replace("Trash", "trash"))}&nbsp;· ${nb(`crew of ${e.crew.size}`)}${e.thanks > 0 ? `&nbsp;· ${nb(`thanked ${fmtNum(e.thanks)} ${e.thanks === 1 ? "time" : "times"}`)}` : ""}</small>
          </span>
        </a>
      </li>`).join("");
  const nextRows = next.map((m) => `
      <li>
        <a href="/m/${esc(m.no)}">
          ${m.photo ? `<img src="${esc(m.photo)}" alt="" loading="lazy">` : `<span class="noimg"></span>`}
          <span class="row-text">
            <b>#${esc(m.no)} ${esc(m.place_name)}</b>
            <small>${m.status === "funded" ? "funded" : "open, not funded yet"}&nbsp;· ${nb(`day ${fmtDay(m.plan_date)}`)}&nbsp;· ${nb(`crew of ${m.crew_size}`)}</small>
          </span>
        </a>
      </li>`).join("");

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta property="og:type" content="profile">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(origin + "/p/" + partner.slug)}">
${preview}
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
  ${logo ? `<div class="ph-hero"><img class="ph-logo" src="${esc(logo)}" alt="" width="96" height="96">${h1}</div>` : h1}
  <p class="sub">// cleanup partner${partner.country ? " · " + esc(partner.country) : ""}${safeSite ? ` · <a href="${esc(safeSite)}" rel="noopener nofollow ugc" target="_blank">${esc(new URL(safeSite).host)} ↗</a>` : ""}</p>${events.length ? `
  <div class="stats fp-stats">
    <div class="stat"><strong>${esc(fmtNum(totalKg))}</strong><span>kg removed</span></div>
    <div class="stat"><strong>${events.length}</strong><span>cleanups</span></div>
    <div class="stat"><strong>${esc(fmtNum(totalSacks))}</strong><span>sacks</span></div>
  </div>` : ""}${totalThanks > 0 ? `
  <p class="sub p-thanks">// visitors thanked this crew ${esc(fmtNum(totalThanks))} ${totalThanks === 1 ? "time" : "times"} on its receipts.</p>` : ""}${next.length ? `
  <section class="panel">
    <h2 class="panel-title">NEXT UP</h2>
    <ul class="p-list">${nextRows}</ul>
    <p class="cx-last p-all"><a href="/missions"><span>ALL MISSIONS ON SAPU.EARTH</span> →</a></p>
  </section>` : ""}
  <section class="panel">
    <h2 class="panel-title">THE RECEIPTS</h2>
    ${events.length ? `<ul class="p-list">${rows}</ul>` : `<p class="hint">No published cleanups yet.</p>`}
  </section>
  <p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a> <a class="btn" href="/crews">ALL CREWS</a></p>
</main>
<footer>
  <p><a href="/impressum/">IMPRESSUM</a></p>
</footer>
</body>
</html>`;
  // The strict headers of /crews and /missions (PAGE_HEADERS): no script, no framing, only this site's styles, fonts
  // and pictures, plus the public bucket's host when PUBLIC_MEDIA_URL is set, since receipt photos may come from there.
  const headers = { ...PAGE_HEADERS, "cache-control": "public, max-age=300" };
  let mediaOrigin = "";
  try { if (typeof env.PUBLIC_MEDIA_URL === "string" && env.PUBLIC_MEDIA_URL) mediaOrigin = new URL(env.PUBLIC_MEDIA_URL).origin; } catch { /* not a URL: leave it out */ }
  if (mediaOrigin) headers["content-security-policy"] = headers["content-security-policy"].replace("img-src 'self' data:", `img-src 'self' data: ${mediaOrigin}`);
  return new Response(html, { headers });
}
export const onRequestHead = headOf(onRequestGet);

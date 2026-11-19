// GET /r/<id> -> share page for an approved cleanup. Carries Open Graph / Twitter tags
// so links get a rich preview, then sends people on to the receipt on the globe.
// The page leaves at once through a 0-second meta refresh, also without JavaScript. Its body shows only in a browser
// that does not follow the refresh (refresh blocked, a text browser). For them it carries the comments link and the
// thanks count as plain HTML (docs/upload-flow.md, Post links and thanks): a crew's own post with nofollow ugc, as
// /p/<slug> marks a crew's website. The tags stay as they are: no link and no count in a preview, where a count would
// go stale.
import { approvedEvents } from "../_lib/events.js";
import { ID_RE, absUrl, amountText, esc, fmtNum, headOf, pageHeaders } from "../_lib/util.js";

const notFound = () => new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });

export async function onRequestGet({ request, env, params }) {
  const id = params.id;
  if (typeof id !== "string" || !ID_RE.test(id) || !env.DB) return notFound();
  let ev;
  try {
    [ev] = await approvedEvents(env, { id, limit: 1 });
  } catch (e) {
    console.error(e);
    return notFound();
  }
  if (!ev) return notFound();

  const origin = new URL(request.url).origin;
  const place = ev.location.name;
  const title = `Cleanup in ${place} · Sapu Earth`;
  const amount = amountText(ev.result.kg_estimate, ev.result.sacks);
  const desc = `${amount} by a crew of ${ev.crew.size}. Cleaned by ${ev.provider.name}.`;
  const img = ev.media.after[0] || ev.media.before[0];
  const image = img ? absUrl(origin, img) : origin + "/site/social/sapu-earth-mark.png"; // without a photo, the broom (square: a small card)
  const url = `${origin}/r/${id}`;
  const target = `/#ev-${id}`; // id is validated base32, so this is never an open redirect
  // The page's one script, allowed by its SHA-256 in the page's script policy (pageHeaders in _lib/util.js).
  const go = `location.replace(${JSON.stringify(target)});`;

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
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
<meta name="twitter:image" content="${esc(image)}">
<meta http-equiv="refresh" content="0; url=${esc(target)}">
<link rel="icon" href="/site/brand/sapu-sketch/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/site/brand/sapu-sketch/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/site/brand/sapu-sketch/apple-touch-icon.png">
<style>body{font-family:system-ui,sans-serif;background:#f2ecdd;color:#1c1813;padding:24px}a{color:#ff5f00;font-weight:700}a.r-more{display:inline-block;min-height:44px;line-height:44px}</style>
</head>
<body>
<p>${esc(desc)}</p>
${typeof ev.thanks === "number" && ev.thanks > 0 ? `<p>Thanked ${esc(fmtNum(ev.thanks))} ${ev.thanks === 1 ? "time" : "times"} on sapu.earth.</p>\n` : ""}${ev.social ? `<p><a class="r-more" href="${esc(ev.social.url)}" rel="${ev.social.by === "crew" ? "noopener noreferrer nofollow ugc" : "noopener noreferrer"}">${ev.social.site === "tiktok" ? "Comments on TikTok" : "Comments on Instagram"}</a></p>\n` : ""}<p><a href="${esc(target)}">See the cleanup receipt on sapu.earth</a></p>
<script>${go}</script>
</body>
</html>`;
  return new Response(html, { headers: await pageHeaders(go, { "cache-control": "public, max-age=300" }) });
}
export const onRequestHead = headOf(onRequestGet);

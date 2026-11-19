// GET /media/<key> -> the R2 object, with single-range support for video seeking.
// Public: files of APPROVED cleanups (cached for a year), the now photos and video of missions that are open,
// funded or done, and the live logo of an active crew (both cached for an hour: a mission can still be removed,
// and a logo replaced or taken down; its file is deleted then, so this answers 404 at once). Anything else
// needs a short-lived signed link from /api/admin/* or the crew page's logo (?exp=..&sig=..) and is never
// cached. ?dl= makes it a download with a file name (downloadName below).
import { KEY_RE, SERVE_TYPES, validMediaSig } from "../_lib/util.js";
import { PUBLIC_MISSION_STATES, withMissions } from "../_lib/missions.js";
import { withLogos } from "../_lib/logos.js";

const notFound = () => new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });

// Downloads. ?dl=1 saves the file as sapu-earth-<first 8 of the key>.<ext>, as it always has. ?dl=<name> saves
// it as sapu-earth-<name>.<ext>, so a file saved from /admin/ says what it is (sapu-earth-<receipt id>-video-before.mp4).
// dl is not covered by the signature of an /admin/ link (that is over "<key>.<exp>"), so whoever holds a link can
// change it. That is fine only because dl changes nothing but the file name, and a name is used only when it
// matches DL_NAME_RE (lowercase letters, digits and dashes, at most 64), between the fixed "sapu-earth-" and an
// extension that comes from the stored content type. Any other dl value gets the old name, so nothing from the
// request but lowercase letters, digits and dashes ever reaches the header (never a quote, CR, LF or slash).
// Public files work the same way.
const DL_NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const DL_EXT = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm" };
// key is checked against KEY_RE before this runs, and type is one of SERVE_TYPES or application/octet-stream.
function downloadName(dl, key, type) {
  const name = dl !== "1" && DL_NAME_RE.test(dl) ? dl : key.slice(0, 8);
  return `sapu-earth-${name}.${DL_EXT[type] || "bin"}`;
}

// Parse a single "bytes=" range against a known size. Returns {offset, length}, null (no range) or "bad".
function parseRange(header, size) {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m || (m[1] === "" && m[2] === "")) return "bad";
  let start, end;
  if (m[1] === "") {
    const n = Number(m[2]);
    if (n === 0) return "bad";
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size) return "bad";
  return { offset: start, length: end - start + 1 };
}

async function serve({ request, env, params }, head) {
  const key = params.key;
  if (typeof key !== "string" || !KEY_RE.test(key) || !env.MEDIA || !env.DB) return notFound();
  const url = new URL(request.url);

  // Before migration 0004 there is no mission_id: then only the submission counts.
  const row = await withMissions((m) => env.DB.prepare(m
    ? `SELECT s.status, ms.status AS mission_status FROM uploads u
       LEFT JOIN submissions s ON s.id = u.submission_id
       LEFT JOIN missions ms ON ms.id = u.mission_id AND u.submission_id IS NULL
       WHERE u.key = ?`
    : "SELECT s.status FROM uploads u JOIN submissions s ON s.id = u.submission_id WHERE u.key = ?"
  ).bind(key).first());
  const approved = row?.status === "approved";
  const missionPublic = !approved && PUBLIC_MISSION_STATES.includes(row?.mission_status);
  // A crew logo has no uploads row (functions/_lib/logos.js), so it is looked up only when the key is no upload.
  // Before migration 0006 there is none.
  let logoPublic = false;
  if (!row) {
    const logo = await withLogos((on) => (on
      ? env.DB.prepare("SELECT l.status, p.active FROM logos l LEFT JOIN partners p ON p.id = l.partner_id WHERE l.key = ?").bind(key).first()
      : null));
    logoPublic = logo?.status === "live" && Number(logo?.active) === 1;
  }
  if (!approved && !missionPublic && !logoPublic && !(await validMediaSig(env, key, url.searchParams.get("exp"), url.searchParams.get("sig")))) {
    return notFound();
  }

  const meta = await env.MEDIA.head(key);
  if (!meta) return notFound();
  const size = meta.size;
  const stored = meta.httpMetadata?.contentType || "";
  const type = SERVE_TYPES.includes(stored) ? stored : "application/octet-stream";

  const headers = new Headers({
    "content-type": type,
    "cache-control": approved ? "public, max-age=31536000, immutable" : missionPublic || logoPublic ? "public, max-age=3600" : "private, no-store",
    "accept-ranges": "bytes",
    "etag": meta.httpEtag,
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; sandbox",
  });
  const dl = url.searchParams.get("dl");
  if (dl) headers.set("content-disposition", `attachment; filename="${downloadName(dl, key, type)}"`);

  const range = parseRange(request.headers.get("range"), size);
  if (range === "bad") {
    headers.set("content-range", `bytes */${size}`);
    return new Response(null, { status: 416, headers });
  }

  if (request.headers.get("if-none-match") === meta.httpEtag && !range) {
    return new Response(null, { status: 304, headers });
  }

  if (head) {
    headers.set("content-length", String(range ? range.length : size));
    if (range) headers.set("content-range", `bytes ${range.offset}-${range.offset + range.length - 1}/${size}`);
    return new Response(null, { status: range ? 206 : 200, headers });
  }

  const obj = await env.MEDIA.get(key, range ? { range } : undefined);
  if (!obj) return notFound();
  if (range) {
    headers.set("content-range", `bytes ${range.offset}-${range.offset + range.length - 1}/${size}`);
    headers.set("content-length", String(range.length));
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set("content-length", String(size));
  return new Response(obj.body, { status: 200, headers });
}

export const onRequestGet = (ctx) => serve(ctx, false);
export const onRequestHead = (ctx) => serve(ctx, true);

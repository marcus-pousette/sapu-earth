// Shared helpers for the Pages Functions. This file exports no onRequest
// handler, so it never becomes a route.
import { withSpots } from "./spots.js";

export const SITE = "https://sapu.earth";

export const LIMITS = {
  photoBytes: 15 * 1024 * 1024,
  videoBytes: 95 * 1024 * 1024,
  uploadsPerDay: 200,              // files per partner per 24 h (200 since 2026-11-19, when a cleanup took 60 videos; 60 before)
  place: 120,
  disposal: 200,
  notes: 1000,
  reviewNote: 1000,
  privateNote: 1000,
  bytesPerDay: 8 * 1024 * 1024 * 1024, // 8 GB per partner per 24 h (1 GB before 2026-11-19: a cleanup's 60 videos are up
                                   // to 5.7 GB). A safe integer, so the quota check in api/upload.js compares it exactly
  unattached: 100,                 // uploaded files not yet part of a sent cleanup (100 since 2026-11-19: a cleanup at 4 spots
                                   // takes up to 4 x 8 photos and 60 videos, 92 files; 40 from 2026-11-17, docs/missions.md, Spots)
  cleanupVideos: 60,               // a cleanup's videos in all, a video without a stage (from an older page) included
                                   // (POST /api/submit; 2 before 2026-11-19)
  stageVideos: 30,                 // a cleanup's videos before the cleanup, and its videos after it (uploads.stage; 1 each before)
  orphanHours: 48,                 // unattached files older than this are deleted
  privateDays: 90,                 // after a decision (cleanup) or done (mission): private note gone, point rounded
  // Partner applications (POST /api/apply)
  applyPhotoBytes: 3 * 1024 * 1024,
  applyPhotos: 3,
  applyBodyBytes: 10 * 1024 * 1024,
  applyPerIpPerDay: 3,             // stored applications per IP (per /64 for IPv6) per 24 h
  applyOpenMax: 40,                // open applications in total, a cap against floods
  applyMinMs: 3000,                // a form sent faster than this is treated as a bot
  applyOpenDays: 90,               // open applications older than this are deleted with their photos
  applyCleanupBatch: 50,           // rows the application cleanup handles per run
};

// The upload page always sends canvas JPEGs, so the API only takes JPEG photos.
// (PNG and WebP can carry EXIF/GPS that we would then publish.)
export const PHOTO_TYPES = ["image/jpeg"];
export const VIDEO_TYPES = ["video/mp4", "video/quicktime", "video/webm"];
// Types /media/ will ever serve with their own content type.
export const SERVE_TYPES = ["image/jpeg", "image/png", "image/webp", ...VIDEO_TYPES];
export const KINDS = ["before", "after", "video"];
// Which part of a cleanup a video shows (uploads.stage, migration 0005): POST /api/upload?kind=video&stage=.
export const VIDEO_STAGES = ["before", "after"];

export const KEY_RE = /^[0-9a-f]{32}$/;
export const ID_RE = /^[a-z2-7]{10}$/;
export const SLUG_RE = /^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$/;
export const ISO2_RE = /^[A-Z]{2}$/;
export const CURRENCY_RE = /^[A-Z]{3}$/;

// ---------- responses ----------
export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...headers,
    },
  });
}
export const err = (status, error, extra = {}) => json({ error, ...extra }, status);

export function noBindings(env) {
  if (!env.DB || !env.MEDIA) return err(503, "Uploads are not set up yet (missing DB or MEDIA binding).");
  return null;
}

export async function readJson(request, maxBytes = 64 * 1024) {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > maxBytes) throw new HttpError(413, "Request body too large.");
  const text = await request.text();
  if (text.length > maxBytes) throw new HttpError(413, "Request body too large.");
  try {
    const v = JSON.parse(text);
    if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error();
    return v;
  } catch {
    throw new HttpError(400, "Body must be a JSON object.");
  }
}

// field: the form field the error belongs to, so a page can show the message next to it.
export class HttpError extends Error {
  constructor(status, message, code, field) { super(message); this.status = status; this.code = code; this.field = field; }
}

// Wrap a handler so thrown HttpErrors become JSON responses and anything else is a 500.
export const handle = (fn) => async (ctx) => {
  try {
    return await fn(ctx);
  } catch (e) {
    if (e instanceof HttpError) {
      const extra = {};
      if (e.code) extra.code = e.code;
      if (e.field) extra.field = e.field;
      return err(e.status, e.message, extra);
    }
    console.error(e);
    return err(500, "Something went wrong on our side. Please try again.");
  }
};

// ---------- randomness + hashing ----------
const B32 = "abcdefghijklmnopqrstuvwxyz234567";

export function randomHex(bytes = 16) {
  const a = crypto.getRandomValues(new Uint8Array(bytes));
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// 10 lowercase base32 chars (50 bits). 256 is a multiple of 32, so b & 31 is unbiased.
export function randomId(len = 10) {
  const a = crypto.getRandomValues(new Uint8Array(len));
  let s = "";
  for (const b of a) s += B32[b & 31];
  return s;
}

export function randomToken() {
  const a = crypto.getRandomValues(new Uint8Array(32));
  let bin = "";
  for (const b of a) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Constant-time comparison: hash both sides to equal-length digests, then XOR every byte.
export async function safeEqual(a, b) {
  const enc = new TextEncoder();
  const [x, y] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(String(a))),
    crypto.subtle.digest("SHA-256", enc.encode(String(b))),
  ]);
  const ax = new Uint8Array(x), ay = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < ax.length; i++) diff |= ax[i] ^ ay[i];
  return diff === 0;
}

export const nowIso = () => new Date().toISOString();

// ---------- partners ----------
const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export async function partnerFromToken(env, token) {
  if (typeof token !== "string" || !TOKEN_RE.test(token)) return null;
  const hash = await sha256Hex(token);
  return env.DB.prepare(
    "SELECT id, slug, name, url, country FROM partners WHERE token_hash = ? AND active = 1"
  ).bind(hash).first();
}

export async function requirePartner(env, request) {
  const k = new URL(request.url).searchParams.get("k");
  const p = await partnerFromToken(env, k);
  if (!p) throw new HttpError(404, "This upload link is not valid. Ask Sapu Earth for a new link.");
  return p;
}

// ---------- validation ----------
const CTRL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F‪-‮⁦-⁩]/g;

export function cleanText(v, max, { required = false, field = "text", multiline = false } = {}) {
  if (v === undefined || v === null || v === "") {
    if (required) throw new HttpError(400, `${field} is required.`);
    return null;
  }
  if (typeof v !== "string") throw new HttpError(400, `${field} must be text.`);
  let s = v.replace(CTRL, "");
  if (!multiline) s = s.replace(/[\r\n\t]+/g, " ");
  s = s.trim();
  if (!s) {
    if (required) throw new HttpError(400, `${field} is required.`);
    return null;
  }
  if ([...s].length > max) throw new HttpError(400, `${field} is too long (max ${max} characters).`);
  return s;
}

export function num(v, { min, max, int = false, required = false, field = "number" } = {}) {
  if (v === undefined || v === null || v === "") {
    if (required) throw new HttpError(400, `${field} is required.`);
    return null;
  }
  const n = typeof v === "string" ? Number(v.trim()) : v;
  if (typeof n !== "number" || !Number.isFinite(n)) throw new HttpError(400, `${field} must be a number.`);
  if (int && !Number.isInteger(n)) throw new HttpError(400, `${field} must be a whole number.`);
  if (n < min || n > max) throw new HttpError(400, `${field} must be between ${min} and ${max}.`);
  return n;
}

export function cleanUrl(v, field = "url") {
  const s = cleanText(v, 200, { field });
  if (!s) return null;
  let u;
  try { u = new URL(s); } catch { throw new HttpError(400, `${field} must be a full https:// address.`); }
  if (u.protocol !== "https:" && u.protocol !== "http:") throw new HttpError(400, `${field} must start with https://`);
  return u.toString();
}

export function isoDate(v, field = "date") {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new HttpError(400, `${field} must be YYYY-MM-DD.`);
  const t = Date.parse(v + "T00:00:00Z");
  if (!Number.isFinite(t) || new Date(t).toISOString().slice(0, 10) !== v) throw new HttpError(400, `${field} is not a real date.`);
  if (t > Date.now() + 86400000) throw new HttpError(400, `${field} cannot be in the future.`);
  if (t < Date.parse("2020-01-01T00:00:00Z")) throw new HttpError(400, `${field} is too far in the past.`);
  return v;
}

// ---------- HTML ----------
const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ESC[c]);

// HEAD for a page Function (/crews, /missions, /p/<slug>, /m/<no>, /r/<id>): the status and headers of GET, no body.
// Link checkers and some link previews ask HEAD first, and a Function with only onRequestGet leaves HEAD to the static
// files, which answer the site's 404 page. Usage: export const onRequestHead = headOf(onRequestGet);
export const headOf = (get) => async (ctx) => {
  const res = await get(ctx);
  return new Response(null, { status: res.status, headers: res.headers });
};

export const mediaUrl = (key) => "/media/" + key;

// Public URL for an approved file: the public bucket (edge cached, no Function call)
// once it has been copied there, otherwise /media/<key> through the Function.
export function publicMediaUrl(env, row) {
  const base = typeof env.PUBLIC_MEDIA_URL === "string" ? env.PUBLIC_MEDIA_URL.replace(/\/+$/, "") : "";
  if (row.public && env.PUBLIC_MEDIA && /^https:\/\/[a-z0-9.-]+$/i.test(base)) return `${base}/${row.key}`;
  return mediaUrl(row.key);
}

// Absolute URL for Open Graph tags.
export const absUrl = (origin, u) => (/^https:\/\//.test(u) ? u : origin + u);

// Short-lived signed links so /admin/ can view media that is not approved yet (and a crew page its own waiting logo).
// HMAC-SHA256 over "<key>.<exp>". The key is MEDIA_KEY, a random secret of its own (docs/upload-flow.md, Signed links),
// and ADMIN_TOKEN only while MEDIA_KEY is not set: a crew page gets such links, so with ADMIN_TOKEN as the key anyone
// holding a crew link could test guesses of the admin token offline. The IP hash (ipHash) uses the same key.
const signKey = (env) => (typeof env.MEDIA_KEY === "string" && env.MEDIA_KEY ? env.MEDIA_KEY : env.ADMIN_TOKEN);
async function hmacHex(secret, text) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(text));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
export async function signedMediaUrl(env, key, ttlSeconds = 4 * 3600) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  return `/media/${key}?exp=${exp}&sig=${await hmacHex(signKey(env), `${key}.${exp}`)}`;
}
export async function validMediaSig(env, key, exp, sig) {
  const secret = signKey(env);
  if (typeof secret !== "string" || !secret) return false;
  if (!/^\d{10}$/.test(exp || "") || !/^[0-9a-f]{64}$/.test(sig || "")) return false;
  if (Number(exp) < Date.now() / 1000) return false;
  return safeEqual(await hmacHex(secret, `${key}.${exp}`), sig);
}

// Headers for an HTML page a Function builds (/r/<id>, /m/<no>): _headers reaches only static files. No other site may
// frame it, no plugins, no <base>, the origin only as referrer, and no script but the page's own inline one, by its
// SHA-256 (or none). Styles and pictures are not limited: these pages carry an inline <style>.
export async function pageHeaders(inlineScript, extra = {}) {
  let script = "'none'";
  if (inlineScript) {
    const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(inlineScript)));
    script = `'sha256-${btoa(String.fromCharCode(...d))}'`;
  }
  return {
    "content-type": "text/html; charset=utf-8",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
    "referrer-policy": "strict-origin-when-cross-origin",
    "content-security-policy": `script-src ${script}; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    ...extra,
  };
}

// The rate limit key for an address. IPv6 counts per /64, because one phone or home line gets a
// whole /64 and can pick any address in it. IPv4, IPv4 inside IPv6 (dotted) and malformed values
// are used as they are. Never throws.
const HEX_GROUP = /^[0-9a-f]{1,4}$/i;
export function ipKey(ip) {
  if (typeof ip !== "string" || !ip.includes(":") || ip.includes(".")) return ip;
  const parts = ip.split("::");
  if (parts.length > 2) return ip;
  const head = parts[0] ? parts[0].split(":") : [];
  const tail = parts[1] ? parts[1].split(":") : [];
  const gap = parts.length === 2 ? 8 - head.length - tail.length : 0;
  if (gap < 0) return ip;
  const groups = [...head, ...Array(gap).fill("0"), ...tail];
  if (groups.length !== 8 || !groups.every((g) => HEX_GROUP.test(g))) return ip;
  return groups.slice(0, 4).map((g) => parseInt(g, 16).toString(16)).join(":") + "::/64";
}

// Keyed hash of the client IP, only for rate limiting. The IP itself is never stored. Same key as the signed links
// (signKey): once MEDIA_KEY is set, the hashes of the last day no longer match, which only resets the per-address count.
export function ipHash(env, request) {
  return hmacHex(signKey(env) || "sapu-earth", "ip:" + ipKey(request.headers.get("CF-Connecting-IP") || "unknown"));
}

// ---------- media ----------
// True when a JPEG carries an Exif (APP1) segment before the image data.
// Camera originals almost always do (with GPS). Our pages re-encode photos through a canvas and then strip
// every APPn segment but JFIF and the colour profile (cleanJpeg in upload.js and apply.js), because WebKit,
// so Safari and every iPhone browser, writes a small Exif block into each canvas JPEG.
export function jpegHasExif(b) {
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return false;
    const marker = b[i + 1];
    if (marker === 0xd9 || marker === 0xda) return false; // end of image / start of scan
    if (marker === 0xff) { i++; continue; }
    const len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) return false;
    if (marker === 0xe1 && i + 10 <= b.length &&
        b[i + 4] === 0x45 && b[i + 5] === 0x78 && b[i + 6] === 0x69 && b[i + 7] === 0x66) return true; // "Exif"
    i += 2 + len;
  }
  return false;
}

// True when a photo looks exactly like what the pages send, from its head (the first bytes, up to 64 KB) and its last
// two bytes: the segments before the image data are only what cleanJpeg leaves of a canvas JPEG (the JFIF header, a
// colour profile, comments, the tables and one plain frame), the image data starts within the head, and the file
// ends with the end marker. So no Exif or XMP (any APP1), no Photoshop block or other APPn, no stray byte that would
// hide a segment from this walk, no header padded past 64 KB, and nothing appended after the picture without an end
// marker of its own. The rules of the logo check (logoJpegInfo in _lib/logos.js) before the image data; the image
// data itself is not walked, which keeps a 15 MB photo within the CPU time a request may use.
export function jpegLikePage(head, last2) {
  const b = head, n = b ? b.length : 0;
  if (n < 4 || b[0] !== 0xff || b[1] !== 0xd8 || b[2] !== 0xff) return false;
  if (!last2 || last2.length !== 2 || last2[0] !== 0xff || last2[1] !== 0xd9) return false;
  const tagged = (p, len, text) => len >= 2 + text.length && [...text].every((c, j) => b[p + j] === c.charCodeAt(0));
  let i = 2, frames = 0;
  while (i + 4 <= n) {
    if (b[i] !== 0xff) return false;
    const m = b[i + 1];
    if (m === 0xff) { i++; continue; } // fill byte
    const len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > n) return false;
    if (m === 0xda) return frames === 1; // start of scan: the image data follows
    const p = i + 4; // the segment's payload
    if (m === 0xe0) { if (!tagged(p, len, "JFIF\u0000")) return false; }
    else if (m === 0xe2) { if (!tagged(p, len, "ICC_PROFILE\u0000")) return false; }
    else if (m >= 0xc0 && m <= 0xc2) {
      if (frames++ || len < 8) return false; // one frame only
      const comps = b[p + 5];
      if (b[p] !== 8 || (comps !== 1 && comps !== 3) || len !== 8 + 3 * comps) return false;
    } else if (m !== 0xfe && m !== 0xdb && m !== 0xc4 && m !== 0xdd) return false; // COM, DQT, DHT, DRI
    i += 2 + len;
  }
  return false; // no image data within the head
}

// R2 keys kept as a JSON array in a TEXT column (applications.photos). Anything malformed gives [].
export function keyList(text) {
  try {
    const a = JSON.parse(text);
    return Array.isArray(a) ? a.filter((k) => typeof k === "string" && KEY_RE.test(k)) : [];
  } catch {
    return [];
  }
}

// "120 kg removed", or "14 sacks of trash removed", or "Trash removed". Never "0 kg" or "null".
export function amountText(kg, sacks) {
  if (kg > 0) return `${fmtNum(kg)} kg removed`;
  if (sacks > 0) return `${fmtNum(sacks)} sack${sacks === 1 ? "" : "s"} of trash removed`;
  return "Trash removed";
}

export function fmtNum(n) {
  if (n === null || n === undefined) return null;
  return Number(n).toLocaleString("en", { maximumFractionDigits: 1 });
}

// D1's error when migration 0005 has not been applied yet: uploads has no stage column.
export function noStageColumn(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such column: (?:\w+\.)?stage\b|has no column named stage\b/i.test(text);
}

// Runs fn(true), which may use uploads.stage. Before migration 0005 that throws, and fn(false) runs
// instead, with SQL that does not know the column: a video is then stored and shown without its stage.
// Like withMissions (_lib/missions.js), a single statement is atomic, so the first try writes nothing.
export async function withStage(fn) {
  try {
    return await fn(true);
  } catch (e) {
    if (!noStageColumn(e)) throw e;
    return fn(false);
  }
}

// Load media rows for a set of submission ids, grouped as {id: {before:[], after:[], videos:[]}}.
// A video row carries its stage ('before', 'after', or null for one sent without it, and before
// migration 0005), and the videos come in that order: before, after, then the ones without a stage, each stage in
// upload order (up to LIMITS.stageVideos of each). The receipt and /admin/ number them in this order (BEFORE · VIDEO 2/3).
// A photo row carries its spot (uploads.spot, migration 0008: 2 to 4, or null for spot 1 and before the migration), and
// the photos come spot by spot, spot 1 first, each spot's in upload order (docs/missions.md, Spots).
export async function mediaFor(env, ids) {
  const out = {};
  for (const id of ids) out[id] = { before: [], after: [], videos: [] };
  if (!ids.length) return out;
  // D1 caps bound parameters at 100 per statement.
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const { results } = await withSpots((p) => withStage((s) => env.DB.prepare(
      `SELECT key, kind, content_type, size, submission_id, public${s ? ", stage" : ""}${p ? ", spot" : ""} FROM uploads WHERE submission_id IN (${chunk.map(() => "?").join(",")}) ORDER BY created_at, key`
    ).bind(...chunk).all()));
    for (const r of results) {
      const g = out[r.submission_id];
      if (!g) continue;
      (r.kind === "video" ? g.videos : r.kind === "before" ? g.before : g.after).push(r);
    }
  }
  // Stable sorts: two videos of the same stage, and two photos of the same spot, keep their upload order.
  const rank = (r) => (r.stage === "before" ? 0 : r.stage === "after" ? 1 : 2);
  const spot = (r) => (Number.isInteger(r.spot) ? r.spot : 1);
  for (const g of Object.values(out)) {
    g.videos.sort((a, b) => rank(a) - rank(b));
    g.before.sort((a, b) => spot(a) - spot(b));
    g.after.sort((a, b) => spot(a) - spot(b));
  }
  return out;
}

// Two uploads are the same file when they have the same size and type and the same R2 etag, which for these one-piece
// uploads (api/upload.js streams each file into a single put) is the MD5 of the bytes. sameFile(env) gives that check for
// upload rows ({key, size, content_type}): only rows of the same size and type are looked up in R2 (env.MEDIA, where every
// upload stays; approving only copies it to the public bucket), each key at most once, and a lookup that fails counts as
// not the same. For a mission photo or video that its cleanup sent again as its before (dropRepeats in events.js), and
// for a cleanup carrying another mission's (same_files in api/admin/submissions.js).
export function sameFile(env) {
  const etags = new Map();
  const etag = (key) => {
    if (!etags.has(key)) etags.set(key, Promise.resolve().then(() => env.MEDIA.head(key)).then((o) => o?.etag || null, () => null));
    return etags.get(key);
  };
  return async (a, b) => {
    if (!env.MEDIA || !Number.isFinite(a?.size) || a.size !== b?.size || a.content_type !== b.content_type) return false;
    const [x, y] = await Promise.all([etag(a.key), etag(b.key)]);
    return x !== null && x === y;
  };
}

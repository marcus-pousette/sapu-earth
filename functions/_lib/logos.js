// Crew logos (docs/upload-flow.md, Crew logos), shared by POST /api/logo, GET /api/partner, /api/apply, /admin/,
// /media/, the public pages and the housekeeping. This file exports no onRequest handler, so it never becomes a route.
//
// One logos row per logo file (migrations/0006_logos.sql). The file is in MEDIA under the row's key, a random 32 hex
// key like every upload's, so /media/<key> serves it with no new route. A logo is never written to uploads, so
// /api/submit, /api/mission, the 30-file quota and the 48-hour cleanup never see one, and never copied to PUBLIC_MEDIA:
// a removal must work at once, without an edge purge.
// Statuses: review (waiting for Marcus, file kept, shown only through signed links; at most one per crew, any number
// with partner_id NULL while they belong to open applications), live (next to the crew's name on sapu.earth while the
// crew is active; at most one per crew), declined (no file: Marcus did not use it, or it waited LOGO.reviewDays days)
// and gone (no file: replaced, the crew deactivated, or the file was missing). declined and gone rows only let the
// crew page say what happened, and go LOGO.keepDays days after decided_at (sweepLogos).
// Before migration 0006 every reader goes through withLogos, and the site behaves as without logos.
import { KEY_RE, nowIso, signedMediaUrl } from "./util.js";

// ---------- logo checks (pure; tests/e2e.sh runs this block in node) ----------
// minBytes to maxBytes: what a 320 px canvas JPEG weighs (usually 10 to 60 KB). minSide to maxSide: the square the
// pages make is 320 px, so this leaves room for a later change without taking posters. perDay: logos per crew per
// 24 h, every status counted. reviewDays: a logo nobody decides on is declined and deleted after this, like an open
// application. keepDays: declined and gone rows are deleted this long after their decision. batch: rows per run
// (D1 takes at most 100 bound values). crewLinkSeconds: how long the crew page's link to its waiting logo works.
const LOGO = { minBytes: 300, maxBytes: 150 * 1024, minSide: 128, maxSide: 640, perDay: 10, reviewDays: 90, keepDays: 30, batch: 90, crewLinkSeconds: 3600 };

// { w, h } when b (a Uint8Array) is exactly what the pages send, else null: a JPEG whose segments before the image
// data are only what cleanJpeg leaves of a canvas JPEG (the JFIF header, a colour profile, comments, the tables and
// one plain SOF), square and LOGO.minSide to LOGO.maxSide px. After the first scan only tables, a restart interval
// and more scans may come, and the first end marker must be the file's last two bytes, so no block (Exif, XMP, any
// APPn) hides behind the picture and nothing (a second picture, any file) is appended to it. No Exif or XMP (APP1),
// no Photoshop block, no other APPn, no other kind of JPEG. The picture itself is never decoded.
function logoJpegInfo(b) {
  if (!b || typeof b.length !== "number" || b.length < LOGO.minBytes || b.length > LOGO.maxBytes) return null;
  const n = b.length;
  if (b[0] !== 0xff || b[1] !== 0xd8 || b[2] !== 0xff || b[n - 2] !== 0xff || b[n - 1] !== 0xd9) return null;
  const tagged = (p, len, text) => len >= 2 + text.length && [...text].every((c, j) => b[p + j] === c.charCodeAt(0));
  let i = 2, sof = null;
  while (i + 4 <= n) {
    if (b[i] !== 0xff) return null;
    const m = b[i + 1];
    if (m === 0xff) { i++; continue; } // fill byte
    const len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > n) return null;
    if (m === 0xda) { // start of scan: the image data follows
      if (!sof || sof.w !== sof.h || sof.w < LOGO.minSide || sof.w > LOGO.maxSide) return null;
      // The rest, scan by scan. Image data is skipped: a 0xFF in it is followed by 0x00, a restart marker (D0 to D7)
      // or a fill byte. The next marker may only be a table (DHT, DQT), a restart interval (DRI), another scan, or
      // the end (EOI), and the end must be the file's last two bytes.
      let j = i + 2 + len;
      for (;;) {
        while (j + 1 < n && (b[j] !== 0xff || b[j + 1] === 0x00 || b[j + 1] === 0xff || (b[j + 1] >= 0xd0 && b[j + 1] <= 0xd7))) j++;
        if (j + 1 >= n) return null; // no end marker
        const x = b[j + 1];
        if (x === 0xd9) return j === n - 2 ? { w: sof.w, h: sof.h } : null;
        if (x !== 0xc4 && x !== 0xdb && x !== 0xdd && x !== 0xda) return null;
        const l = (b[j + 2] << 8) | b[j + 3];
        if (l < 2 || j + 2 + l > n) return null;
        j += 2 + l;
      }
    }
    const p = i + 4; // the segment's payload
    if (m === 0xe0) { if (!tagged(p, len, "JFIF\u0000")) return null; }
    else if (m === 0xe2) { if (!tagged(p, len, "ICC_PROFILE\u0000")) return null; }
    else if (m >= 0xc0 && m <= 0xc2) {
      if (sof || len < 8) return null; // one frame only
      const comps = b[p + 5];
      if (b[p] !== 8 || (comps !== 1 && comps !== 3) || len !== 8 + 3 * comps) return null;
      sof = { h: (b[p + 1] << 8) | b[p + 2], w: (b[p + 3] << 8) | b[p + 4] };
    } else if (m !== 0xfe && m !== 0xdb && m !== 0xc4 && m !== 0xdd) return null; // COM, DQT, DHT, DRI
    i += 2 + len;
  }
  return null; // no image data
}

// The letters a crew without a logo shows: the first letter or digit of each of its first two words, or the first
// two of a one-word name, upper-cased; "?" without any. "Sapu Bersih Padang" SB, "ocean" OC.
function monogram(name) {
  const runs = String(name ?? "").match(/[\p{L}\p{N}]+/gu) || [];
  if (!runs.length) return "?";
  const s = runs.length > 1 ? [...runs[0]][0] + [...runs[1]][0] : [...runs[0]].slice(0, 2).join("");
  return s.toUpperCase();
}
// ---------- end of the logo checks ----------
export { LOGO, logoJpegInfo, monogram };

// D1's error when migration 0006 has not been applied yet.
export function noLogosTable(e) {
  const text = `${e?.message ?? ""} ${e?.cause?.message ?? ""}`;
  return /no such table: logos\b/i.test(text);
}

// Runs fn(true), which may use the logos table. Before migration 0006 that throws, and fn(false) runs instead,
// without it. Like withMissions and withStage: one statement or one batch is atomic, so the first try wrote nothing.
export async function withLogos(fn) {
  try {
    return await fn(true);
  } catch (e) {
    if (!noLogosTable(e)) throw e;
    return fn(false);
  }
}

// The public address of a live logo, "/media/<key>", or null.
export const logoUrl = (key) => (typeof key === "string" && KEY_RE.test(key) ? "/media/" + key : null);

// Deletes logo files from MEDIA. By then their rows are never live, so /media/ never serves a file that is left
// behind: a failure is logged with its keys and never thrown.
export async function dropLogoFiles(env, keys) {
  const list = (keys || []).filter((k) => typeof k === "string" && KEY_RE.test(k));
  for (let i = 0; i < list.length; i += 1000) { // R2 deletes at most 1000 keys per call
    const part = list.slice(i, i + 1000);
    try {
      await env.MEDIA.delete(part);
    } catch (e) {
      console.error("logo files not deleted", part, e);
    }
  }
}

// The crew page's YOUR LOGO (GET /api/partner, and the answer of POST /api/logo): { enabled, live, review, declined,
// initials }. live: the public address of the live logo. review: a signed link to the waiting one, for an hour.
// declined: Sapu Earth did not use the last logo the crew sent, and nothing waits (with a live logo, only when that
// came after it). One statement that no number of old rows can cut short: the unique indexes allow one review and one
// live row, and the aggregate is always one row. Before migration 0006: enabled false, and the page hides the panel.
export async function logoStateFor(env, partnerId, name) {
  const initials = monogram(name);
  const rows = await withLogos(async (on) => {
    if (!on) return null;
    const { results } = await env.DB.prepare(
      `SELECT key, status, decided_at FROM logos WHERE partner_id = ?1 AND status IN ('review', 'live')
       UNION ALL SELECT NULL, 'declined', MAX(decided_at) FROM logos WHERE partner_id = ?1 AND status = 'declined'`
    ).bind(partnerId).all();
    return results || [];
  });
  if (!rows) return { enabled: false, live: null, review: null, declined: false, initials };
  const live = rows.find((r) => r.status === "live" && KEY_RE.test(r.key || "")) || null;
  const review = rows.find((r) => r.status === "review" && KEY_RE.test(r.key || "")) || null;
  const last = rows.find((r) => r.status === "declined" && r.key === null)?.decided_at ?? null;
  return {
    enabled: true,
    live: live ? logoUrl(live.key) : null,
    review: review ? await signedMediaUrl(env, review.key, LOGO.crewLinkSeconds) : null,
    declined: !review && last !== null && (!live || String(last) > String(live.decided_at || "")),
    initials,
  };
}

// The key of the crew's live logo, or null (also before migration 0006).
export async function liveLogoKey(env, partnerId) {
  const row = await withLogos((on) => (on
    ? env.DB.prepare("SELECT key FROM logos WHERE partner_id = ? AND status = 'live'").bind(partnerId).first()
    : null));
  return row && typeof row.key === "string" && KEY_RE.test(row.key) ? row.key : null;
}

// DEACTIVATE: the crew's live and waiting logos are gone, their files deleted. Returns how many (0 before 0006).
export async function dropCrewLogos(env, partnerId) {
  const keys = await withLogos(async (on) => {
    if (!on) return [];
    const { results } = await env.DB.prepare(
      "UPDATE logos SET status = 'gone', decided_at = ?1 WHERE partner_id = ?2 AND status IN ('review', 'live') RETURNING key"
    ).bind(nowIso(), partnerId).all();
    return (results || []).map((r) => r.key);
  });
  await dropLogoFiles(env, keys);
  return keys.length;
}

// The logos of applications that no longer wait (expired, a DELETE APPLICATION whose rows were left behind, or a logo
// that DELETE APPLICATION or the /api/apply undo claimed while the application was approved in the same moment):
// files first, then rows, at most LOGO.batch per run. If R2 fails, the rows stay for the next run. Run inside
// expireApplications. Returns how many; 0 before migration 0006, so callers never log a missing table.
export async function sweepApplicationLogos(env) {
  let keys;
  try {
    const { results } = await env.DB.prepare(
      `SELECT l.key FROM logos l WHERE l.partner_id IS NULL
         AND NOT EXISTS (SELECT 1 FROM applications a WHERE a.id = l.application_id AND a.status = 'new') LIMIT ?`
    ).bind(LOGO.batch).all();
    keys = (results || []).map((r) => r.key).filter((k) => typeof k === "string");
  } catch (e) {
    if (noLogosTable(e)) return 0;
    throw e;
  }
  if (!keys.length) return 0;
  await env.MEDIA.delete(keys);
  await env.DB.prepare(
    `DELETE FROM logos WHERE partner_id IS NULL AND key IN (${keys.map(() => "?").join(",")})`
  ).bind(...keys).run();
  return keys.length;
}

// The housekeeping's logo job (POST /api/housekeeping), LOGO.batch rows per step:
// (1) the live and waiting logos of inactive crews are gone, files deleted: a DEACTIVATE whose logo step failed, or a
//     logo sent in the moment its crew was deactivated;
// (2) a logo of an active crew that waited LOGO.reviewDays days without a decision is declined and its file deleted,
//     so the crew page asks for another one (the upload notice promises this);
// (3) declined and gone rows older than LOGO.keepDays days: their keys are deleted from R2 once more (the files should
//     be gone already, so this only retries a failed delete; if it fails, the rows stay for the next run), then the rows.
// Returns { gone, expired, deleted }.
export async function sweepLogos(env) {
  const now = nowIso();
  const keysOf = (r) => (r.results || []).map((x) => x.key);
  const off = keysOf(await env.DB.prepare(
    `UPDATE logos SET status = 'gone', decided_at = ?1
     WHERE key IN (SELECT l.key FROM logos l JOIN partners p ON p.id = l.partner_id
                   WHERE l.status IN ('review', 'live') AND p.active = 0 LIMIT ?2)
       AND status IN ('review', 'live')
     RETURNING key`
  ).bind(now, LOGO.batch).all());
  await dropLogoFiles(env, off);

  const unchecked = new Date(Date.now() - LOGO.reviewDays * 86400000).toISOString();
  const late = keysOf(await env.DB.prepare(
    `UPDATE logos SET status = 'declined', decided_at = ?1
     WHERE key IN (SELECT l.key FROM logos l JOIN partners p ON p.id = l.partner_id
                   WHERE l.status = 'review' AND p.active = 1 AND l.created_at < ?3 LIMIT ?2)
       AND status = 'review'
     RETURNING key`
  ).bind(now, LOGO.batch, unchecked).all());
  await dropLogoFiles(env, late);

  const kept = new Date(Date.now() - LOGO.keepDays * 86400000).toISOString();
  const old = keysOf(await env.DB.prepare(
    "SELECT key FROM logos WHERE status IN ('declined', 'gone') AND decided_at < ?1 LIMIT ?2"
  ).bind(kept, LOGO.batch).all()).filter((k) => typeof k === "string");
  if (old.length) {
    await env.MEDIA.delete(old);
    await env.DB.prepare(
      `DELETE FROM logos WHERE status IN ('declined', 'gone') AND key IN (${old.map(() => "?").join(",")})`
    ).bind(...old).run();
  }
  return { gone: off.length, expired: late.length, deleted: old.length };
}

// POST /api/upload?k=TOKEN&kind=before|after|video[&stage=before|after][&spot=2..4]
// Raw body (one file). Validates token, kind vs type, size and magic bytes, then
// streams the file into R2 under a random 128-bit hex key.
// stage: only for a video, whether it is one of the cleanup's videos before or after the cleanup (the two video fields
// on the upload page, up to 30 each; POST /api/submit counts them, LIMITS.stageVideos). A mission's video, and a video
// from an older page, come without it. Stored in uploads.stage (migration 0005); before that migration the video is
// stored without its stage.
// spot: only for a before or after photo, the spot of a mission with several spots it shows (2 to SPOTS.max; spot 1 comes
// without it), from the field the photo was picked in on the cleanup form (docs/missions.md, Spots). Stored in
// uploads.spot (migration 0008); before that migration no mission has spots, and a photo sent with one is refused.
//
// The quota row is reserved in D1 BEFORE the body is streamed, in one atomic
// INSERT ... SELECT ... WHERE, so parallel requests cannot all pass the check.
//
// "Unattached" (loose) files and their 48-hour cleanup live in _lib/uploads.js. Each upload starts
// that cleanup for its own crew; POST /api/housekeeping runs it for every crew on a timer.
import {
  KINDS, LIMITS, PHOTO_TYPES, VIDEO_STAGES, VIDEO_TYPES,
  err, handle, jpegHasExif, jpegLikePage, json, noBindings, nowIso, randomHex, requirePartner, withStage,
} from "../_lib/util.js";
import { withMissions } from "../_lib/missions.js";
import { SPOTS, withSpots } from "../_lib/spots.js";
import { cleanOrphans, unattached } from "../_lib/uploads.js";

// What the first bytes must look like for each declared type.
function magicMatches(type, b) {
  const at = (i, ...v) => v.every((x, j) => b[i + j] === x);
  const ascii = (i, s) => [...s].every((c, j) => b[i + j] === c.charCodeAt(0));
  switch (type) {
    case "image/jpeg": return at(0, 0xff, 0xd8, 0xff);
    case "video/mp4":
    case "video/quicktime": return ascii(4, "ftyp");
    case "video/webm": return at(0, 0x1a, 0x45, 0xdf, 0xa3);
    default: return false;
  }
}

export const onRequestPost = handle(async ({ request, env, waitUntil }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const partner = await requirePartner(env, request);

  const url = new URL(request.url);
  const kind = url.searchParams.get("kind");
  if (!KINDS.includes(kind)) return err(400, "kind must be before, after or video.", { code: "kind" });
  const stage = url.searchParams.get("stage");
  if (stage !== null && (kind !== "video" || !VIDEO_STAGES.includes(stage))) {
    return err(400, "stage must be before or after, and only for a video.", { code: "kind" });
  }
  const spotParam = url.searchParams.get("spot");
  const spot = spotParam === null ? null : Number(spotParam);
  if (spotParam !== null && (kind === "video" || !/^[2-9]$/.test(spotParam) || spot > SPOTS.max)) {
    return err(400, `spot must be 2 to ${SPOTS.max}, and only for a before or after photo.`, { code: "kind" });
  }

  const type = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  const allowed = kind === "video" ? VIDEO_TYPES : PHOTO_TYPES;
  if (!allowed.includes(type)) {
    return err(415, kind === "video"
      ? "Videos must be MP4, MOV or WebM."
      : "Photos must be JPEG. Please use the upload page, it converts photos for you.", { code: "type" });
  }

  const max = kind === "video" ? LIMITS.videoBytes : LIMITS.photoBytes;
  const lenHeader = request.headers.get("content-length");
  const size = lenHeader === null ? NaN : Number(lenHeader);
  if (!Number.isInteger(size) || size <= 0) return err(411, "Upload needs a Content-Length.", { code: "size" });
  if (size > max) return err(413, `File too large (max ${Math.round(max / 1048576)} MB).`, { code: "size" });
  if (!request.body) return err(400, "Empty upload.", { code: "size" });

  waitUntil?.(cleanOrphans(env, partner.id).catch((e) => console.error("orphan cleanup", e)));

  // Reserve the slot atomically: count, byte budget and unattached files, all in one statement.
  // D1 runs writes one at a time, so this cannot race. col: the video's stage (migration 0005) or the photo's spot
  // (migration 0008), with its value; null for neither.
  const key = randomHex(16);
  const now = nowIso();
  const since = new Date(Date.now() - 86400000).toISOString();
  const insert = (col, val) => withMissions((m) => env.DB.prepare(
    `INSERT INTO uploads (key, partner_id, kind, content_type, size, created_at${col ? ", " + col : ""})
     SELECT ?, ?, ?, ?, ?, ?${col ? ", ?" : ""}
     WHERE (SELECT COUNT(*) FROM uploads WHERE partner_id = ? AND created_at > ?) < ?
       AND (SELECT COALESCE(SUM(size), 0) FROM uploads WHERE partner_id = ? AND created_at > ?) + ? <= ?
       AND (SELECT COUNT(*) FROM uploads WHERE partner_id = ? AND ${unattached(m)}) < ?`
  ).bind(
    key, partner.id, kind, type, size, now, ...(col ? [val] : []),
    partner.id, since, LIMITS.uploadsPerDay,
    partner.id, since, size, LIMITS.bytesPerDay,
    partner.id, LIMITS.unattached,
  ).run());
  // Only a video sent with its stage, or a photo sent with its spot, tries the column: anything else runs the statement
  // it always ran. A photo for spot 2 or later cannot be stored without its spot, so before migration 0008 it is refused.
  const reserved = await (stage ? withStage((s) => insert(s ? "stage" : null, stage))
    : spot ? withSpots((p) => (p ? insert("spot", spot) : null))
    : insert(null));
  if (!reserved) return err(400, "This photo is for a spot this server does not know yet.", { code: "kind" });
  if (!reserved.meta?.changes) {
    return err(429, "Too many uploads today. Please try again tomorrow.", { code: "limit" });
  }

  // Undo the reservation. Network failures free the slot (an honest retry should not burn quota);
  // content that fails validation keeps the row as 'invalid', so it still counts against the limit.
  const fail = async (status, message, code, keepRow) => {
    await env.MEDIA.delete(key).catch(() => {});
    await (keepRow
      ? env.DB.prepare("UPDATE uploads SET content_type = 'invalid' WHERE key = ?").bind(key).run()
      : env.DB.prepare("DELETE FROM uploads WHERE key = ?").bind(key).run()
    ).catch((e) => console.error("upload undo", e));
    return err(status, message, { code });
  };

  // Stream the body straight into R2 (no JS copying, so large videos cost almost no CPU time),
  // then read back the first bytes and the stored size.
  let stored;
  try {
    stored = await env.MEDIA.put(key, request.body, { httpMetadata: { contentType: type } });
  } catch (e) {
    console.error("upload failed", e);
    return fail(400, "The upload was interrupted or its size did not match. Please try again.", "interrupted", false);
  }
  if (!stored || stored.size !== size) return fail(400, "The upload was incomplete. Please try again.", "interrupted", false);

  const headLen = kind === "video" ? 16 : Math.min(size, 65536);
  const headObj = await env.MEDIA.get(key, { range: { offset: 0, length: headLen } });
  const first = headObj ? new Uint8Array(await headObj.arrayBuffer()) : new Uint8Array(0);
  if (first.length < 12 || !magicMatches(type, first)) {
    return fail(415, "The file content does not match its type. Please choose a real photo or video file.", "content", true);
  }
  if (type === "image/jpeg" && jpegHasExif(first)) {
    return fail(415, "This photo still has camera data (location) in it. Please send it through the upload page.", "exif", true);
  }
  // Exactly what the page sends (jpegLikePage): no other block before the image, nothing after it. The end marker
  // is the file's last two bytes, read on their own unless the head already holds the whole file.
  if (type === "image/jpeg") {
    let last2 = size <= first.length ? first.subarray(size - 2, size) : null;
    if (!last2) {
      const tailObj = await env.MEDIA.get(key, { range: { offset: size - 2, length: 2 } });
      last2 = tailObj ? new Uint8Array(await tailObj.arrayBuffer()) : null;
    }
    if (!jpegLikePage(first, last2)) {
      return fail(415, "This photo was not prepared by the upload page (it carries extra data). Please send it through the upload page.", "exif", true);
    }
  }

  return json({ key });
});

/* Removes location and device metadata from MP4 and MOV videos on the phone, before upload.
   Phones store GPS in the 'moov' box: Android as udta/©xyz, iPhone as an mdta item
   "com.apple.quicktime.location.ISO6709" (moov/meta/keys + ilst), some as udta/loci.
   We only read the 'moov' box (usually well under 1 MB), rename each matching box to 'free'
   and zero its payload. Sizes do not change, so the rest of the file is reused as is
   (Blob slices, no copy), which keeps this cheap on old phones. WebM is passed through. */
(function (root) {
  "use strict";
  const DROP = new Set(["©xyz", "loci", "©mak", "©mod"]); // location, make, model
  const DROP_KEY = /location|(^|\.)(make|model)$/i;                         // mdta key names
  const MAX_MOOV = 32 * 1024 * 1024;

  const fourcc = (dv, o) => String.fromCharCode(dv.getUint8(o), dv.getUint8(o + 1), dv.getUint8(o + 2), dv.getUint8(o + 3));
  const read = async (blob, start, len) => new Uint8Array(await blob.slice(start, start + len).arrayBuffer());

  // Box header at o within [o, end): {size, type, hdr} or null when malformed.
  function box(dv, o, end) {
    if (o + 8 > end) return null;
    let size = dv.getUint32(o), hdr = 8;
    const type = fourcc(dv, o + 4);
    if (size === 1) {
      if (o + 16 > end) return null;
      size = dv.getUint32(o + 8) * 4294967296 + dv.getUint32(o + 12);
      hdr = 16;
    } else if (size === 0) size = end - o;
    if (size < hdr || o + size > end) return null;
    return { size, type, hdr };
  }

  async function findMoov(blob) {
    let off = 0;
    for (let guard = 0; off + 8 <= blob.size && guard < 5000; guard++) {
      const h = await read(blob, off, 16);
      if (h.length < 8) return null;
      const dv = new DataView(h.buffer);
      let size = dv.getUint32(0);
      if (size === 1) {
        if (h.length < 16) return null;
        size = dv.getUint32(8) * 4294967296 + dv.getUint32(12);
      } else if (size === 0) size = blob.size - off;
      if (size < 8 || off + size > blob.size) return null;
      if (fourcc(dv, 4) === "moov") return { start: off, size };
      off += size;
    }
    return null;
  }

  function wipe(u8, o, size, hits) {
    u8.set([0x66, 0x72, 0x65, 0x65], o + 4); // 'free'
    u8.fill(0, o + 8, o + size);
    hits.n++;
  }

  // 1-based indexes of mdta keys we want gone, from a 'keys' box payload.
  function badKeys(dv, start, end) {
    const out = new Set();
    let o = start + 4; // version + flags
    if (o + 4 > end) return out;
    const count = dv.getUint32(o);
    o += 4;
    for (let i = 1; i <= count && o + 8 <= end; i++) {
      const len = dv.getUint32(o);
      if (len < 8 || o + len > end) break;
      let name = "";
      for (let j = o + 8; j < o + len; j++) name += String.fromCharCode(dv.getUint8(j));
      if (DROP_KEY.test(name)) out.add(i);
      o += len;
    }
    return out;
  }

  function walk(u8, dv, from, to, ctx, hits, depth) {
    if (depth > 12) return;
    let o = from;
    while (o + 8 <= to) {
      const b = box(dv, o, to);
      if (!b) return;
      const body = o + b.hdr, end = o + b.size;
      if (DROP.has(b.type) || (ctx.inIlst && ctx.keys && ctx.keys.has(dv.getUint32(o + 4)))) {
        wipe(u8, o, b.size, hits);
      } else if (b.type === "meta") {
        // QuickTime meta has children right away; ISO meta is a FullBox (4 bytes version/flags first).
        const start = body + 8 <= end && fourcc(dv, body + 4) === "hdlr" ? body : body + 4;
        let keys = null;
        for (let c = start; c + 8 <= end;) {
          const k = box(dv, c, end);
          if (!k) break;
          if (k.type === "keys") keys = badKeys(dv, c + k.hdr, c + k.size);
          c += k.size;
        }
        walk(u8, dv, start, end, { keys, inIlst: false }, hits, depth + 1);
      } else if (b.type === "ilst") {
        walk(u8, dv, body, end, { keys: ctx.keys, inIlst: true }, hits, depth + 1);
      } else if (b.type === "udta" || b.type === "trak" || b.type === "moov") {
        walk(u8, dv, body, end, { keys: null, inIlst: false }, hits, depth + 1);
      }
      o = end;
    }
  }

  // Returns {blob, cleaned, ok}. Never throws. ok is false when the clip could not be checked (no moov box
  // found, one too big to read, a read error): blob is then the original file, and the upload page refuses
  // the clip instead of sending it with its location.
  async function stripVideoLocation(file) {
    const failed = { blob: file, cleaned: 0, ok: false };
    try {
      const moov = await findMoov(file);
      if (!moov || moov.size > MAX_MOOV) return failed;
      const u8 = await read(file, moov.start, moov.size);
      const dv = new DataView(u8.buffer);
      const hits = { n: 0 };
      walk(u8, dv, 0, u8.length, { keys: null, inIlst: false }, hits, 0);
      if (!hits.n) return { blob: file, cleaned: 0, ok: true };
      const blob = new Blob([file.slice(0, moov.start), u8, file.slice(moov.start + moov.size)], { type: file.type });
      if (blob.size !== file.size) return failed;
      return { blob, cleaned: hits.n, ok: true };
    } catch (e) {
      return failed;
    }
  }

  root.SapuVideoClean = { stripVideoLocation };
  if (typeof module !== "undefined" && module.exports) module.exports = { stripVideoLocation };
})(typeof window !== "undefined" ? window : globalThis);

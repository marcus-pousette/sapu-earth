// POST /api/apply  multipart/form-data -> 201 {id}
// A crew applies to become a partner (from /apply/). Nothing here is public: /admin/ reads the
// application, and its photos have no row in `uploads`, so /media/ serves them only with a
// signed admin link. Errors are {error, field?, code?}; the page shows its own translated text.
//
// The rate limits are checked inside the INSERT itself (INSERT ... SELECT ... WHERE), so
// parallel requests cannot all pass them. D1 runs writes one at a time.
//
// The row is claimed BEFORE any photo is written to R2, and it already lists the photo keys.
// So a request that hits a limit or repeats never touches R2, and a request cut off halfway
// leaves a row whose keys REJECT, APPROVE or the 90 day expiry delete (deleting a key that was
// never written is harmless).
// The crew's logo, optional (one file entry "logo"): the square JPEG the apply page made (toLogoJpeg), under the
// checks of POST /api/logo. It gets a logos row with the application (partner_id NULL, status review) in the same
// claim, and its file is written after the photos. APPROVE AND CREATE PARTNER decides it with the application
// (docs/upload-flow.md, Crew logos). Before migration 0006 the application is stored without its logo, and nothing
// of the logo reaches R2.
import {
  HttpError, ISO2_RE, LIMITS,
  cleanText, cleanUrl, err, handle, ipHash, jpegHasExif, jpegLikePage, json, noBindings, nowIso, randomHex, randomId,
} from "../_lib/util.js";
import { expireApplications } from "../_lib/applications.js";
import { LOGO, logoJpegInfo, noLogosTable } from "../_lib/logos.js";

const REF_RE = /^[0-9a-f]{32}$/;
const HANDLE_RE = /^@[A-Za-z0-9._]{1,40}$/;
const WHATSAPP_RE = /^\+[1-9][0-9]{7,14}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Spaces, invisible format marks (a number copied from WhatsApp or the contacts app often comes
// wrapped in direction marks), any dash, dots and parentheses.
const WA_STRIP = /[\s.()\p{Cf}\p{Pd}]/gu;

// ---------- WhatsApp numbers: the same block in apply/apply.js and functions/api/apply.js ----------
// The calling code (ITU E.164) of every country on the apply page that has phones. No code is the start of
// another one, so a "+..." number has at most one of them.
const DIAL = {
  AD: "376", AE: "971", AF: "93", AG: "1", AI: "1", AL: "355", AM: "374", AO: "244", AR: "54", AS: "1",
  AT: "43", AU: "61", AW: "297", AX: "358", AZ: "994", BA: "387", BB: "1", BD: "880", BE: "32", BF: "226",
  BG: "359", BH: "973", BI: "257", BJ: "229", BL: "590", BM: "1", BN: "673", BO: "591", BQ: "599", BR: "55",
  BS: "1", BT: "975", BW: "267", BY: "375", BZ: "501", CA: "1", CC: "61", CD: "243", CF: "236", CG: "242",
  CH: "41", CI: "225", CK: "682", CL: "56", CM: "237", CN: "86", CO: "57", CR: "506", CU: "53", CV: "238",
  CW: "599", CX: "61", CY: "357", CZ: "420", DE: "49", DJ: "253", DK: "45", DM: "1", DO: "1", DZ: "213",
  EC: "593", EE: "372", EG: "20", EH: "212", ER: "291", ES: "34", ET: "251", FI: "358", FJ: "679", FK: "500",
  FM: "691", FO: "298", FR: "33", GA: "241", GB: "44", GD: "1", GE: "995", GF: "594", GG: "44", GH: "233",
  GI: "350", GL: "299", GM: "220", GN: "224", GP: "590", GQ: "240", GR: "30", GT: "502", GU: "1", GW: "245",
  GY: "592", HK: "852", HN: "504", HR: "385", HT: "509", HU: "36", ID: "62", IE: "353", IL: "972", IM: "44",
  IN: "91", IO: "246", IQ: "964", IR: "98", IS: "354", IT: "39", JE: "44", JM: "1", JO: "962", JP: "81",
  KE: "254", KG: "996", KH: "855", KI: "686", KM: "269", KN: "1", KP: "850", KR: "82", KW: "965", KY: "1",
  KZ: "7", LA: "856", LB: "961", LC: "1", LI: "423", LK: "94", LR: "231", LS: "266", LT: "370", LU: "352",
  LV: "371", LY: "218", MA: "212", MC: "377", MD: "373", ME: "382", MF: "590", MG: "261", MH: "692", MK: "389",
  ML: "223", MM: "95", MN: "976", MO: "853", MP: "1", MQ: "596", MR: "222", MS: "1", MT: "356", MU: "230",
  MV: "960", MW: "265", MX: "52", MY: "60", MZ: "258", NA: "264", NC: "687", NE: "227", NF: "672", NG: "234",
  NI: "505", NL: "31", NO: "47", NP: "977", NR: "674", NU: "683", NZ: "64", OM: "968", PA: "507", PE: "51",
  PF: "689", PG: "675", PH: "63", PK: "92", PL: "48", PM: "508", PR: "1", PS: "970", PT: "351", PW: "680",
  PY: "595", QA: "974", RE: "262", RO: "40", RS: "381", RU: "7", RW: "250", SA: "966", SB: "677", SC: "248",
  SD: "249", SE: "46", SG: "65", SH: "290", SI: "386", SJ: "47", SK: "421", SL: "232", SM: "378", SN: "221",
  SO: "252", SR: "597", SS: "211", ST: "239", SV: "503", SX: "1", SY: "963", SZ: "268", TC: "1", TD: "235",
  TG: "228", TH: "66", TJ: "992", TK: "690", TL: "670", TM: "993", TN: "216", TO: "676", TR: "90", TT: "1",
  TV: "688", TW: "886", TZ: "255", UA: "380", UG: "256", US: "1", UY: "598", UZ: "998", VA: "39", VC: "1",
  VE: "58", VG: "1", VI: "1", VN: "84", VU: "678", WF: "681", WS: "685", YE: "967", YT: "262", ZA: "27",
  ZM: "260", ZW: "263",
};
// Where a number can start with 0, that 0 is part of it, never a national prefix to drop: Italy, San Marino
// and the Vatican, Côte d'Ivoire (10 digits since 2021), Benin (10 digits since 2024), Congo and Gabon.
const KEEP0 = ["IT", "SM", "VA", "CI", "BJ", "CG", "GA"];
// Digits of a mobile number after the code, [fewest, most], where we know them (every +1 country has 10).
const WA_LEN = {
  ID: [9, 12], PH: [10, 10], MY: [9, 10], TH: [9, 9], VN: [9, 9], KH: [8, 9], MM: [8, 10], TL: [8, 8],
  IN: [10, 10], LK: [9, 9], BD: [10, 10], PK: [10, 10], NP: [10, 10], CN: [11, 11], JP: [10, 10], KR: [9, 10],
  SG: [8, 8], HK: [8, 8], AU: [9, 9], NZ: [8, 10], PG: [8, 8], FJ: [7, 7],
  KE: [9, 9], UG: [9, 9], TZ: [9, 9], RW: [9, 9], BI: [8, 8], ET: [9, 9], CD: [9, 9], CM: [9, 9],
  NG: [10, 10], GH: [9, 9], SN: [9, 9], CI: [10, 10], BJ: [10, 10], TG: [8, 8], BF: [8, 8], ML: [8, 8],
  NE: [8, 8], GN: [9, 9], SL: [8, 8], GM: [7, 7], AO: [9, 9], ZM: [9, 9], ZW: [9, 9], MW: [9, 9],
  MZ: [9, 9], MG: [9, 9], NA: [9, 9], BW: [8, 8], ZA: [9, 9], EG: [10, 10], MA: [9, 9], DZ: [9, 9],
  TN: [8, 8], BR: [10, 11], MX: [10, 10], CO: [10, 10], PE: [9, 9], CL: [9, 9], AR: [10, 11], EC: [9, 9],
  RU: [10, 10], KZ: [10, 10], TR: [10, 10], GB: [10, 10], FR: [9, 9], DE: [10, 11], ES: [9, 9], IT: [9, 10],
  PT: [9, 9], NL: [9, 9],
};
const waLen = (country) => WA_LEN[country] || (DIAL[country] === "1" ? [10, 10] : null);
const CODES = [...new Set(Object.values(DIAL))];
// The calling code a "+..." number starts with, or "" for none we know.
const codeOf = (s) => CODES.find((c) => s.startsWith("+" + c)) || "";
// Spaces, invisible marks, dashes, dots and brackets go (WA_STRIP), a leading 00 becomes +. A number without +
// gets the chosen country's code in place of its national 0; digits that start with the code already carry it
// only when the rest has a mobile number's length there ("812 3456 7890" with Indonesia chosen needs +62, or it
// would be +81, Japan; an Indian mobile "9123456789" starts with 91 but needs +91). Without a code for the
// country it stays without +, so it is refused and never gets a wrong code. A 0 typed right after the code
// ("+62 0812...") is the national 0 and goes too, except where numbers start with 0 ("+39 06...", "+225 07...").
function normWhatsapp(raw, country) {
  let s = raw.replace(WA_STRIP, "");
  if (!s) return "";
  if (s.startsWith("00")) s = "+" + s.slice(2);
  const cc = DIAL[country];
  if (cc && /^\d+$/.test(s)) {
    const len = waLen(country) || [7, 12];
    const rest = s.length - cc.length;
    if (s.startsWith("0") && !KEEP0.includes(country)) s = "+" + cc + s.slice(1);
    else s = "+" + (s.startsWith(cc) && rest >= len[0] && rest <= len[1] ? "" : cc) + s;
  }
  const c = codeOf(s);
  if (c && s.charAt(c.length + 1) === "0" && !KEEP0.some((k) => DIAL[k] === c)) s = "+" + c + s.slice(c.length + 2);
  return s;
}
// ---------- end of the WhatsApp block ----------

const bad = (status, message, field, code) => new HttpError(status, message, code, field);

// Run one field's check and tag its error with the form field name.
function at(field, check) {
  try {
    return check();
  } catch (e) {
    if (e instanceof HttpError && !e.field) e.field = field;
    throw e;
  }
}

// A text field of the form, "" when missing. A file sent under a text field name is refused.
function str(fd, name) {
  const v = fd.get(name);
  if (v === null) return "";
  if (typeof v !== "string") throw bad(400, `${name} must be text.`, name);
  return v;
}

function cleanLinks(raw) {
  const lines = raw.split(/[\r\n]+/).map((s) => s.trim()).filter(Boolean);
  if (lines.length > 3) throw bad(400, "Please give at most 3 links.", "links");
  const out = lines.map((line) => {
    if (!line.startsWith("@")) return cleanUrl(line, "Each link");
    if (!HANDLE_RE.test(line)) throw bad(400, "Write a handle like @yourcrew, or a full link like https://instagram.com/yourcrew.", "links");
    return line;
  });
  return out.length ? out.join("\n") : null;
}

// The number as the page shows it under the field ("We will use: ..."), from the same rules and the chosen country.
function cleanWhatsapp(raw, country) {
  const s = normWhatsapp(raw, country);
  if (!s) return null;
  if (!WHATSAPP_RE.test(s)) {
    throw bad(400, "Please write your WhatsApp number with the country code, like +62 812 3456 7890.", "whatsapp");
  }
  return s;
}

function cleanEmail(raw) {
  const s = cleanText(raw, 120, { field: "Email" });
  if (s === null) return null;
  if (!EMAIL_RE.test(s)) throw bad(400, "Please check your email address.", "email");
  return s.toLowerCase();
}

// Validates every text field, in the order the form shows them. Since 2026-11-17 the form no longer asks how many people
// usually join (Marcus: 'Drop the head count'): a crew_size sent by a page from before is ignored, and the column stays
// NULL (older applications keep theirs).
function readFields(fd) {
  const f = {};
  f.lang = str(fd, "lang") === "id" ? "id" : "en";
  f.org_name = at("org_name", () => cleanText(str(fd, "org_name"), 80, { required: true, field: "Crew or group name" }));
  f.contact_name = at("contact_name", () => cleanText(str(fd, "contact_name"), 80, { required: true, field: "Your name" }));
  f.country = at("country", () => str(fd, "country").trim().toUpperCase());
  if (!ISO2_RE.test(f.country)) throw bad(400, "Please choose your country.", "country");
  f.area = at("area", () => cleanText(str(fd, "area"), 120, { required: true, field: "City or area" }));
  // Browsers send textarea line breaks as CRLF in a form upload. Count and store each as one "\n".
  f.about = at("about", () => cleanText(str(fd, "about").replace(/\r\n?/g, "\n"), 1000, { required: true, field: "What you clean", multiline: true }));
  f.links = at("links", () => cleanLinks(str(fd, "links")));
  f.whatsapp = at("whatsapp", () => cleanWhatsapp(str(fd, "whatsapp"), f.country));
  f.email = at("email", () => cleanEmail(str(fd, "email")));
  if (!f.whatsapp && !f.email) throw bad(400, "Please give a WhatsApp number or an email address, so we can reply.", "contact");
  f.heard_from = at("heard_from", () => cleanText(str(fd, "heard_from"), 120, { field: "How you heard about us" }));
  if (fd.get("consent") !== "1") throw bad(400, "Please tick the box to agree that we may store your details.", "consent");
  f.client_ref = fd.get("client_ref");
  if (typeof f.client_ref !== "string" || !REF_RE.test(f.client_ref)) {
    throw bad(400, "The form is missing its reference. Please reload the page and try again.", "client_ref");
  }
  return f;
}

// Checks the photo entries and reads them into memory (at most 3 x 3 MB).
async function readPhotos(fd) {
  const files = fd.getAll("photo");
  if (files.length > LIMITS.applyPhotos) throw bad(400, `Please send at most ${LIMITS.applyPhotos} photos.`, "photos");
  const out = [];
  for (const file of files) {
    if (typeof file === "string" || !file.size) throw bad(400, "A photo was empty. Please choose it again.", "photos");
    if (file.size > LIMITS.applyPhotoBytes) throw bad(413, "A photo is too large (max 3 MB).", "photos");
    const b = new Uint8Array(await file.arrayBuffer());
    if (b.length > LIMITS.applyPhotoBytes) throw bad(413, "A photo is too large (max 3 MB).", "photos");
    if (!(b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff)) {
      throw bad(415, "Photos must be JPEG. Please choose them on the apply page, it converts them for you.", "photos", "photo");
    }
    if (jpegHasExif(b.subarray(0, 65536))) {
      throw bad(415, "This photo still has camera data (location) in it. Please choose it on the apply page, it removes that data.", "photos", "photo");
    }
    // Exactly what the page sends (jpegLikePage in _lib/util.js): no other block before the image, nothing after it.
    if (!jpegLikePage(b.subarray(0, 65536), b.subarray(b.length - 2))) {
      throw bad(415, "This photo was not prepared by the apply page (it carries extra data). Please choose it on the apply page.", "photos", "photo");
    }
    out.push(b);
  }
  return out;
}

// The logo entry, read into memory (at most 150 KB), or null without one. The same checks as POST /api/logo.
async function readLogo(fd) {
  const all = fd.getAll("logo");
  if (!all.length) return null;
  if (all.length > 1) throw bad(400, "Please send at most one logo.", "logo");
  const file = all[0];
  if (typeof file === "string" || !file.size) throw bad(400, "The logo was empty. Please choose it again.", "logo");
  if (file.size > LOGO.maxBytes) throw bad(413, "The logo is too large.", "logo");
  const b = new Uint8Array(await file.arrayBuffer());
  if (b.length > LOGO.maxBytes) throw bad(413, "The logo is too large.", "logo");
  if (!logoJpegInfo(b)) throw bad(415, "The logo was not accepted. Please choose it on the apply page, it prepares it.", "logo", "logo");
  return b;
}

const byRef = (env, ref) => env.DB.prepare("SELECT id FROM applications WHERE client_ref = ?").bind(ref).first();
const repeated = (id) => json({ id, repeated: true }, 200);

// Claims the row (with the limits), then writes the photos under the keys it lists, and the logo under a.logoKey.
// With a logo, its logos row goes in the same batch as the application, so both or neither are stored.
// Returns "refused" (a limit was reached), "stored", or "failed" (a file could not be written; the files and the
// rows are deleted again). Throws only when the INSERT throws.
async function claimAndStore(env, a, photos, logo) {
  const insert = () => env.DB.prepare(
    `INSERT INTO applications (id, client_ref, status, lang, org_name, contact_name, country, area, about,
       links, whatsapp, email, heard_from, photos, ip_hash, created_at)
     SELECT ?, ?, 'new', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
     WHERE (SELECT COUNT(*) FROM applications WHERE ip_hash = ? AND created_at > ?) < ?
       AND (SELECT COUNT(*) FROM applications WHERE status = 'new') < ?`
  ).bind(
    a.id, a.client_ref, a.lang, a.org_name, a.contact_name, a.country, a.area, a.about,
    a.links, a.whatsapp, a.email, a.heard_from, JSON.stringify(a.keys), a.ip, a.now,
    a.ip, a.since, LIMITS.applyPerIpPerDay,
    LIMITS.applyOpenMax,
  );
  let res;
  if (a.logoKey) {
    try {
      [res] = await env.DB.batch([
        insert(),
        env.DB.prepare(
          "INSERT INTO logos (key, application_id, status, created_at) SELECT ?1, ?2, 'review', ?3 WHERE EXISTS (SELECT 1 FROM applications WHERE id = ?2)"
        ).bind(a.logoKey, a.id, a.now),
      ]);
    } catch (e) {
      // Before migration 0006: the application goes in without its logo. Any other error is the caller's (the
      // client_ref race). A batch is atomic, so the first try wrote nothing.
      if (!noLogosTable(e)) throw e;
      a.logoKey = null;
      logo = null;
      res = await insert().run();
    }
  } else {
    res = await insert().run();
  }
  if (!res.meta?.changes) return "refused";

  try {
    for (let i = 0; i < photos.length; i++) {
      await env.MEDIA.put(a.keys[i], photos[i], { httpMetadata: { contentType: "image/jpeg" } });
    }
    if (a.logoKey && logo) await env.MEDIA.put(a.logoKey, logo, { httpMetadata: { contentType: "image/jpeg" } });
    return "stored";
  } catch (e) {
    console.error("apply photo store failed", a.id, e);
    // The logo is claimed first (gone), so an APPROVE AND CREATE PARTNER in this very moment can no longer make it
    // live; if one came first, nothing is claimed and its file stays. Then the files, then the rows. If the file
    // delete fails, the rows stay and still list the keys, so a decision or the expiry deletes them later (a retry
    // then gets this id back). The logos statements run only when a logos row was written, so without a logo (and
    // before migration 0006) this runs the statements it always ran.
    try {
      let claimed = [];
      if (a.logoKey) {
        const { results } = await env.DB.prepare(
          "UPDATE logos SET status = 'gone', decided_at = ?2 WHERE key = ?1 AND partner_id IS NULL RETURNING key"
        ).bind(a.logoKey, nowIso()).all();
        claimed = (results || []).map((x) => x.key).filter((k) => typeof k === "string");
      }
      const keys = [...a.keys, ...claimed];
      if (keys.length) await env.MEDIA.delete(keys);
      const drop = env.DB.prepare("DELETE FROM applications WHERE id = ? AND status = 'new'").bind(a.id);
      if (a.logoKey) {
        await env.DB.batch([env.DB.prepare("DELETE FROM logos WHERE key = ? AND partner_id IS NULL").bind(a.logoKey), drop]);
      } else {
        await drop.run();
      }
    } catch (e2) {
      console.error("apply undo failed", a.id, a.keys, a.logoKey, e2);
    }
    return "failed";
  }
}

export const onRequestPost = handle(async ({ request, env, waitUntil }) => {
  const missing = noBindings(env);
  if (missing) return missing;

  const lenHeader = request.headers.get("content-length");
  const size = lenHeader === null ? NaN : Number(lenHeader);
  if (!Number.isInteger(size) || size <= 0) return err(411, "The form needs a Content-Length.");
  if (size > LIMITS.applyBodyBytes) return err(413, "The form is too large. Please send smaller or fewer photos.", { field: "photos" });
  const type = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (type !== "multipart/form-data") return err(415, "Send the form as multipart/form-data.");

  let fd;
  try {
    fd = await request.formData();
  } catch {
    return err(400, "Could not read the form. Please try again.");
  }

  const f = readFields(fd);

  // Bot traps: answer like a success and store nothing.
  const hp = fd.get("website");
  const ms = fd.get("elapsed_ms");
  const elapsed = typeof ms === "string" && ms.trim() !== "" ? Number(ms) : NaN;
  const trapped = typeof hp === "string" ? hp.trim() !== "" : hp !== null;
  if (trapped || !(elapsed >= LIMITS.applyMinMs)) return json({ id: randomId(10) }, 201);

  // The phone sent this before but never got the answer.
  const prev = await byRef(env, f.client_ref);
  if (prev) return repeated(prev.id);

  const photos = await readPhotos(fd);
  const logo = await readLogo(fd);

  const a = {
    ...f,
    id: randomId(10),
    keys: photos.map(() => randomHex(16)),
    logoKey: logo ? randomHex(16) : null,
    ip: await ipHash(env, request),
    now: nowIso(),
    since: new Date(Date.now() - 86400000).toISOString(),
  };

  // waitUntil keeps the insert and the photo writes going when the phone drops the connection
  // halfway, so a cut request cannot leave a row with only some of its photos written.
  const work = claimAndStore(env, a, photos, logo);
  waitUntil?.(work.catch(() => {}));
  let outcome;
  try {
    outcome = await work;
  } catch (e) {
    // A racing retry with the same client_ref won the UNIQUE index: answer with its id.
    const won = await byRef(env, f.client_ref).catch(() => null);
    if (won) return repeated(won.id);
    throw e;
  }
  if (outcome === "failed") return err(500, "Could not save the photos. Please try again.");

  if (outcome === "refused") {
    const won = await byRef(env, f.client_ref);
    if (won) return repeated(won.id);
    const c = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM applications WHERE ip_hash = ? AND created_at > ?"
    ).bind(a.ip, a.since).first();
    if ((c?.n ?? 0) >= LIMITS.applyPerIpPerDay) {
      return err(429, "You already sent a few applications today. Please wait a day, or email hello@sapu.earth.", { code: "rate" });
    }
    return err(429, "We have a lot of applications to read right now. Please try again in a few days, or email hello@sapu.earth.", { code: "busy" });
  }

  // Retention (old open applications, old IP hashes), after the answer is sent.
  waitUntil?.(expireApplications(env).catch((e) => console.error("application expiry", e)));
  return json({ id: a.id }, 201);
});

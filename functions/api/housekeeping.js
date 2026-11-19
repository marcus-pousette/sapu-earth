// POST /api/housekeeping -> 200 {ran, waiting: {applications, missions, cleanups, logos, tiktok, thanks, late}, newest: {the same keys}}
// The cleanup jobs that otherwise only run when someone uses the site, on a timer. Pages has no cron,
// so a GitHub Actions workflow (.github/workflows/housekeeping.yml) calls this on a 3-hourly schedule (GitHub skips many runs, so a few times a day):
// - the 28-day mission expiry, then the retry for photos a mission removal left behind (_lib/missions.js)
// - the application retention: 90-day expiry, old IP hashes, photos of decided applications, logos of
//   applications that no longer wait (_lib/applications.js)
// - the 48-hour cleanup of loose uploads for every crew, also a crew that never uploads again
//   (_lib/uploads.js)
// - the crew logos (_lib/logos.js): the logos of deactivated crews, a logo that waited 90 days for Marcus
//   without a decision (declined and deleted, so the crew page asks for another one), and old records
// - the crew's own post links on receipts of deactivated crews (_lib/social.js)
// - the TikTok accounts of deactivated crews (_lib/tiktok.js)
// - 90 days after a cleanup was decided or a mission was done: the crew's private message goes and the
//   exact point is rounded to about 100 m (_lib/retention.js)
// Each job handles one batch per run. One job failing is logged and the others still run.
//
// Public, no token: every job only removes what is already due, so an extra run changes nothing.
// Still, the jobs run at most once per 10 minutes per Cloudflare data center (Cache API, a fixed
// key no request can reach). Other calls skip them and answer ran: false.
// waiting: new applications not decided yet, missions in review, cleanups in PENDING, crew logos under
// LOGOS TO CHECK, crew TikTok accounts under TIKTOK TO CHECK (of active crews), counted after the jobs, and busy days of thanks: the UTC days, today or yesterday, with at least
// THANKS.busySite standing thanks on the site or THANKS.busyReceipt on one receipt (_lib/social.js), for THANKS BY DAY
// on APPROVED; an undo takes its day out. late: funded missions MISSION_LIMITS.lateDays (3) or more days past their
// planned day (the last day of their spots, docs/missions.md, Spots) with no cleanup in PENDING, LATE on their MISSIONS card (a mission whose cleanup was rejected counts
// again until the crew sends it anew). newest: when the newest of each came in (its created_at; for thanks the
// busy day at 00:00 UTC; for late the day the latest of them became late, at 00:00 UTC; for tiktok when it was sent), or null when none waits. The workflow keeps it from run to run: a later one means something
// new came in, also when an older one was handled meanwhile and the count stayed the same. Counts and times only,
// never names. Before migrations 0003, 0004, 0006, 0007 and 0009 the missing tables count as 0, with newest null.
// plan_date is the crew's own day (YYYY-MM-DD) and is compared with the UTC date, the same day /admin/ goes by.
// Any other method answers 405.
import { expireApplications, noApplicationsTable } from "../_lib/applications.js";
import { MISSION_LIMITS, expireMissions, noMissionsTable, sweepRemovedPhotos } from "../_lib/missions.js";
import { cleanOrphans } from "../_lib/uploads.js";
import { LAST_DAY_SQL, noSpotsColumn } from "../_lib/spots.js";
import { trimPrivate } from "../_lib/retention.js";
import { noLogosTable, sweepLogos } from "../_lib/logos.js";
import { THANKS, noSocialTables, sweepCrewPostLinks } from "../_lib/social.js";
import { noTiktokTable, sweepCrewTiktok } from "../_lib/tiktok.js";
import { handle, json, noBindings } from "../_lib/util.js";

const QUIET_SECONDS = 600;
// The throttle's cache key: fixed, on a host that never resolves (.internal is reserved for private
// use), so no request from outside can match or overwrite it.
const LAST_RUN = "https://sapu-earth.internal/housekeeping/last-run";

const never = () => false;
const JOBS = [
  ["mission expiry", expireMissions, noMissionsTable],
  ["mission photo sweep", sweepRemovedPhotos, noMissionsTable],
  ["application retention", expireApplications, noApplicationsTable],
  ["orphan uploads", (env) => cleanOrphans(env), never],
  ["logo sweep", sweepLogos, noLogosTable],
  ["post link sweep", sweepCrewPostLinks, noSocialTables],
  ["tiktok sweep", sweepCrewTiktok, noTiktokTable],
  ["private details", trimPrivate, never],
];

// True when this call should run the jobs: no run in the last QUIET_SECONDS at this data center.
// The mark is set before the jobs start, so a second call meanwhile skips them. If the Cache API
// fails, the jobs run anyway: an extra run is harmless, a housekeeping that never runs is not.
async function claimRun() {
  const cache = globalThis.caches?.default;
  if (!cache) return true;
  try {
    if (await cache.match(LAST_RUN)) return false;
    await cache.put(LAST_RUN, new Response(new Date().toISOString(), {
      headers: { "content-type": "text/plain", "cache-control": `max-age=${QUIET_SECONDS}` },
    }));
  } catch (e) {
    console.error("housekeeping throttle", e);
  }
  return true;
}

// Never throws: a failing job is logged (unless its table is not there yet) and the next one runs.
async function runJobs(env) {
  for (const [name, job, missingTable] of JOBS) {
    try {
      await job(env);
    } catch (e) {
      if (!missingTable(e)) console.error("housekeeping:", name, e);
    }
  }
}

// The late count's SQL: funded missions whose day, the last of their spots with migration 0008 (LAST_DAY_SQL in
// _lib/spots.js; spots false runs it on plan_date alone, before that migration), is lateDays or more days ago.
const LATE = (spots) => {
  const day = spots ? LAST_DAY_SQL("m") : "m.plan_date";
  return `SELECT COUNT(*) AS n, date(MAX(${day}), '+${MISSION_LIMITS.lateDays} days') || 'T00:00:00.000Z' AS newest FROM missions m
     WHERE m.status = 'funded' AND ${day} <= date('now', '-${MISSION_LIMITS.lateDays} days')
       AND NOT EXISTS (SELECT 1 FROM submissions s WHERE s.mission_id = m.id AND s.status = 'pending')`;
};

// What waits for Marcus, one indexed query each: [key, SQL, missing table check, SQL before migration 0008 or none].
const WAITING = [
  ["applications", "SELECT COUNT(*) AS n, MAX(created_at) AS newest FROM applications WHERE status = 'new'", noApplicationsTable],
  ["missions", "SELECT COUNT(*) AS n, MAX(created_at) AS newest FROM missions WHERE status = 'review'", noMissionsTable],
  ["cleanups", "SELECT COUNT(*) AS n, MAX(created_at) AS newest FROM submissions WHERE status = 'pending'", never],
  ["logos", "SELECT COUNT(*) AS n, MAX(l.created_at) AS newest FROM logos l JOIN partners p ON p.id = l.partner_id WHERE l.status = 'review' AND p.active = 1", noLogosTable],
  ["tiktok", "SELECT COUNT(*) AS n, MAX(t.sent_at) AS newest FROM crew_tiktok t JOIN partners p ON p.id = t.partner_id WHERE t.review IS NOT NULL AND p.active = 1", noTiktokTable],
  ["thanks", `SELECT COUNT(*) AS n, MAX(day) || 'T00:00:00.000Z' AS newest FROM (SELECT day FROM thanks_site WHERE day >= date('now', '-1 day') AND n >= ${THANKS.busySite} UNION SELECT day FROM thanks_days WHERE day >= date('now', '-1 day') AND n >= ${THANKS.busyReceipt})`, noSocialTables],
  ["late", LATE(true), noMissionsTable, LATE(false)],
];

async function waitingRow(env, sql, missingTable, before0008) {
  try {
    const r = await env.DB.prepare(sql).first();
    return { n: Number(r?.n) || 0, newest: r?.newest || null };
  } catch (e) {
    if (missingTable(e)) return { n: 0, newest: null };
    if (before0008 && noSpotsColumn(e)) return waitingRow(env, before0008, missingTable);
    throw e;
  }
}

export const onRequest = handle(async ({ request, env, waitUntil }) => {
  if (request.method !== "POST") return json({ error: "Use POST." }, 405, { allow: "POST" });
  const missing = noBindings(env);
  if (missing) return missing;

  const ran = await claimRun();
  if (ran) {
    // waitUntil lets the jobs finish when the caller hangs up halfway.
    const work = runJobs(env);
    waitUntil?.(work);
    await work;
  }
  const rows = await Promise.all(WAITING.map(([, sql, missingTable, before0008]) => waitingRow(env, sql, missingTable, before0008)));
  const waiting = {}, newest = {};
  WAITING.forEach(([k], i) => { waiting[k] = rows[i].n; newest[k] = rows[i].newest; });
  return json({ ran, waiting, newest });
});

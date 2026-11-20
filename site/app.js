/* Sapu Earth: globe, receipts-as-posts and missions. No build step, reads data/events/,
   /api/events (approved partner cleanups) and /api/missions (open and funded missions). */
(async function () {
  const $ = (s) => document.querySelector(s);
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Partner data is untrusted: every interpolated text value goes through escapeHTML,
  // every media URL through safeSrc.
  const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  const escapeHTML = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ESC[c]);
  const safeSrc = (u) =>
    typeof u === "string" && /^(\/media\/|data\/|site\/|https:\/\/)/.test(u) && !/[\s"'<>\\]/.test(u) ? u : null;
  const cc = (e) => (/^[A-Z]{2}$/.test(e.location?.country || "") ? e.location.country : "??");
  const SHARE_ORIGIN = "https://sapu.earth";

  // the visitor's own day, n days from today (n < 0: before), as YYYY-MM-DD
  const dayFromToday = (n) => {
    const d = new Date();
    d.setDate(d.getDate() + n);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  };

  // A link to one receipt or mission (#ev-<id>, #m-<no>: where /r/<id> and /m/<no> send people, also "It is live" in
  // /admin/) asks for both lists past the browser's cache (max-age 60): right after APPROVE, FUND or PUBLISH a list
  // cached a minute ago does not have it yet, and the post would not open. Other visits keep the cache.
  const fresh = /^#(ev-|m-\d)/.test(location.hash) ? { cache: "reload" } : undefined;

  // ---------- the lists after Back (tests/e2e.sh runs this block in node) ----------
  // WebKit (iPhone Safari, Instagram's browser on iPhones) cuts what is still on its way when the visitor leaves, as it
  // cuts the photos and the land (after Back, below). A page left before /api/missions and /api/events had come (CLEANUP
  // CREW? APPLY tapped at once on a slow connection) came back from Back with no mission, ? in the stats and COULDN'T
  // LOAD THE CLEANUPS until a reload, and with no globe at all when the visitor had stayed on sapu.earth (WebKit,
  // 2026-11-17). The first screen is built once from the lists, so a page whose list was cut on its way loads again once
  // it is back: at the next Back when the cut came before it (WebKit), at once when it came after one (Chrome), never
  // during the pageshow itself, and only once sapu.earth answers (a HEAD of this page, which no Function serves): offline
  // or with the site out of reach, the browser's error page took the place of the page, so then the cut waits for the
  // next Back. Only once in a row: a page that was itself loaded again (by this, or by the visitor) never loads again
  // for a cut, so one whose lists a blocker stops, or a server drops, does not load again on every Back (relisted). The
  // browser says how the page was loaded, so nothing is kept on the device for it (this site stores nothing there,
  // /impressum/). A link the visitor followed since the page came back goes first: one tapped while the HEAD was on its
  // way was dropped for the load (Chrome, 2026-11-18; WebKit drops the HEAD then), so the browser's navigate event,
  // where it has one, says a link to another page is on its way (a mailto: link or a download is not), and the load
  // waits for it. If the link goes, the next Back tries again. In Chrome, if it stops with the visitor still here, the
  // load goes ahead then (listStayed): Stop, the browser's Back over a step inside the page and the post's ✕ stop it
  // (navigateerror, then nothing or a step back), and a # or a post's step after the link lets it go on (navigateerror,
  // then that step; Chrome 149, 2026-11-18). A load the HEAD's answer or a step back asks for waits until the page
  // stands still (listSettled), at the next frame when it already does and no step back's wait is running: asked for
  // during a step back's own navigate event it reloaded the address being left, so a post closed with ✕ opened again,
  // and asked for during the smooth scroll back up it landed half way down, or before that scroll moved (Chrome 149 and
  // 157, 2026-11-18); a return or Stop lets a waiting load go at once.
  // In Chrome the page's own load, stopped by a step back, goes again after the step; stopped by a link, it waits for
  // that link; stopped by a mailto: link or by Stop, it waits for a return to the page or the next Back. WebKit says
  // nothing when a link or a load stops (no navigateerror, and no navigate event at all for a link to another site or a
  // mailto: link), a link there goes on after a step back, and it runs no frames while a load is on its way, so there
  // a step back during the page's own load is undone when the load lands. When the visitor comes back to the page from
  // another app or tab (INSTAGRAM or TIKTOK on a phone with the app),
  // a load waiting for a link goes ahead, and a cut the page knows of (a HEAD with no answer, offline or dropped by
  // WebKit for a link, or a list cut on the first load, once: relisted) is tried again, the load then waiting for a link
  // the browser told of. A HEAD answered after the page was left and came back counts not (that Back asked again),
  // and a load the browser dropped for one of its own (an address typed while the HEAD was on its way) is tried again
  // at the next Back. listLost takes the error and the number of Backs when the list was asked for; a cut is a TypeError
  // (a request the browser could not make or finish), never an answer with an error status or one that is not JSON.
  const relisted = (() => {
    try {
      const n = performance.getEntriesByType("navigation")[0];
      return n ? n.type === "reload" : performance.navigation?.type === 1;
    } catch { return false; }
  })();
  let listBacks = 0, listCut = false, listTrying = false, listLeaving = false, listHeld = false, listOwn = false, listAsked = false,
    listNavs = 0, listWait = 0, listStepping = false, listShown = -1e9;
  // listAsked: this page asked for its own load, whose navigate event Chrome fires before location.reload() returns and
  // WebKit after, or never when a step came first and dropped the load; listOwn: that load is on its way
  const listLoad = () => { listTrying = listAsked = true; listHeld = listOwn = false; location.reload(); listOwn = true; };
  const listStayed = () => { listLeaving = false; if (listHeld) listLoad(); };   // the link stopped, the visitor is here
  // once the page stands still (a step back's scroll, html's smooth scroll): three frames in a row with the same scroll,
  // for the last wait asked for only, unless a link was tapped since; listStepping: a step back's wait is running, or a
  // link cut it (its scroll may not have moved yet: Chrome moves it two frames after the step)
  const listSettled = (w, y = NaN, still = 0) => requestAnimationFrame(() => {
    if (listLeaving || w !== listWait) return;
    still = scrollY === y ? still + 1 : 0;
    if (still < 3) listSettled(w, scrollY, still); else { listStepping = false; listStayed(); }
  });
  window.navigation?.addEventListener("navigate", (ev) => {
    listNavs++;
    if (listAsked && ev.navigationType === "reload") { listAsked = false; listOwn = listLeaving = true; return; }
    const own = listOwn;
    listOwn = false;
    if (!ev.destination.sameDocument) {
      listLeaving = /^https?:/.test(ev.destination.url) && ev.downloadRequest == null;
      if (own && ev.navigationType !== "reload") {                    // a link stopped the page's own load: it waits for
        if (listLeaving) listHeld = true;                             // that link; a mailto: one, for a return or a Back
        else if (ev.downloadRequest == null) { listTrying = false; listCut = true; }
      }
    } else if (ev.navigationType === "traverse") {                    // a step back stops a link, or the page's own load
      if (own) listHeld = true;
      listLeaving = false;
      const w = ++listWait;                                           // a wait already running starts again after the step
      // not the step WebKit takes to this very entry right after a Back (0 to 56 ms after its pageshow, measured
      // 2026-11-18); a step to another entry at the same address (after a post's ✕) is a step back
      if (ev.destination.url !== location.href || ev.destination.key !== navigation.currentEntry?.key || performance.now() - listShown > 150) listStepping = true;
      setTimeout(() => listSettled(w));
    } else listOwn = own;                                             // a # or a post's step: what is on its way goes on
  });
  window.navigation?.addEventListener("navigateerror", () => {        // a link or a load stopped, or a step after it
    const n = listNavs;
    setTimeout(() => {
      if (n !== listNavs) return;                                    // nothing after it: Stop
      if (listOwn) { listTrying = false; listCut = true; }            // the page's own load: a return tries again
      listOwn = false; listStayed();
    });
  });
  addEventListener("pagehide", () => { listHeld = false; });          // the link went: the next Back tries again
  addEventListener("visibilitychange", () => {                        // back from an app or another tab
    if (document.hidden) return;
    if (listHeld) listStayed();                                       // an app took the link over: the load goes ahead
    else setTimeout(() => { if (listCut && !listTrying) { listCut = false; listAgain(); } });   // after a Back's own pageshow
  });
  const listAgain = () => {
    if (listTrying) return;
    listTrying = true;
    const b = listBacks;
    setTimeout(async () => {
      let ok = false;
      try { ok = (await fetch(location.pathname, { method: "HEAD", cache: "no-store" })).ok; } catch {}
      if (b !== listBacks) return;                                    // left and back since: that Back asked again
      listTrying = false;
      if (!ok) listCut = true;                                        // no answer: the next Back tries again
      else { listHeld = listCut = true; if (!listLeaving) listSettled(++listWait, scrollY, listStepping ? 0 : 2); }   // a link, or a still page
    });
  };
  addEventListener("pageshow", (ev) => {
    if (!ev.persisted) return;
    listBacks++; listWait++; listLeaving = listHeld = listOwn = listAsked = listStepping = false; listShown = performance.now();
    if (listTrying) { listTrying = false; listCut = true; }          // a HEAD or a load that the leave cut or dropped
    if (listCut) { listCut = false; listAgain(); }
  });
  const listLost = (e, b) => {
    if (e?.name !== "TypeError" || relisted) return;
    if (listBacks !== b) listAgain(); else listCut = true;
  };
  // ---------- end of the lists after Back ----------

  // missions load in parallel with the receipts. The site works the same when this fails or is empty.
  const missionsP = fetch("/api/missions", fresh).then((r) => (r.ok ? r.json() : null)).catch((e) => { listLost(e, 0); return null; }); // null: failed

  // ---------- data ----------
  let events = [];
  let loadFailed = false;
  try {
    const r = await fetch("data/events/index.json");
    if (!r.ok) throw new Error("manifest HTTP " + r.status);
    const manifest = await r.json();
    const loaded = await Promise.all(
      manifest.map((f) =>
        fetch("data/events/" + f).then((x) => (x.ok ? x.json() : null)).catch(() => null)
      )
    );
    events = loaded.filter(Boolean);
    // sample receipts count their day back from today, so they never sit in the future or grow old
    for (const e of events) if (e.demo && Number.isInteger(e.days_ago)) e.date = dayFromToday(-e.days_ago);
  } catch (e) {
    loadFailed = true;
    listLost(e, 0);
    console.error("Could not load events:", e);
  }
  // Approved partner uploads. Without the API (404, or 503 while it is not set up) the site shows only what
  // data/events/index.json lists, which since 2026-11-16 is nothing. When the API fails (down, a short rate limit block,
  // the day's Function quota used up), there may be real cleanups it cannot show, so samples must not stand in for them.
  let apiFailed = false;
  const apiFrom = listBacks;
  try {
    const r = await fetch("/api/events", fresh);
    if (r.ok) {
      const api = await r.json();
      if (!Array.isArray(api)) throw new Error("not a list");
      const seen = new Set(events.map((e) => e.id));
      for (const e of api) {
        if (!e || typeof e.id !== "string" || seen.has(e.id)) continue;
        seen.add(e.id);
        e.fromApi = true;
        events.push(e);
      }
      if (api.length) loadFailed = false;
    } else if (r.status !== 404 && r.status !== 503) apiFailed = true;
  } catch (e) { apiFailed = true; listLost(e, apiFrom); }
  events.sort((a, b) => String(b.date || "").localeCompare(String(a.date || "")));
  // Sample events are only for an empty site. Once a real cleanup is published, hide them so the totals stay honest.
  if (events.some((e) => !e.demo)) events = events.filter((e) => !e.demo);
  else if (apiFailed) { events = []; loadFailed = true; }

  const allDemo = events.length > 0 && events.every((e) => e.demo);
  if (allDemo) $("#demoPill").hidden = false;

  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------
  // A mission with several spots (docs/missions.md, Spots), and the receipt of its cleanup, list every spot, spot 1 first:
  // GET /api/missions as [{ no, place_name, lat, lng, date }], GET /api/events as [{ no, name, lat, lng, date }]. Taken
  // only when whole: 2 to 4 spots numbered 1, 2, ... in that order, each with a place and a day, its point two numbers or
  // none. As { no, name, lat, lng, date }, else []: the post then shows its one place as before.
  const spotList = (a, nameKey) => {
    if (!Array.isArray(a) || a.length < 2 || a.length > 4) return [];
    const ok = a.every((s, i) => !!s && s.no === i + 1 && typeof s[nameKey] === "string" && s[nameKey].trim() !== ""
      && typeof s.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s.date));
    const pt = (s) => Number.isFinite(s.lat) && Number.isFinite(s.lng);
    return ok ? a.map((s) => ({ no: s.no, name: s[nameKey], date: s.date, lat: pt(s) ? s.lat : null, lng: pt(s) ? s.lng : null })) : [];
  };
  const spotsE = (e) => spotList(e?.spots, "name");
  const spotsM = (m) => spotList(m?.spots, "place_name");
  // The spot of each photo of a receipt's media[kind] (media.before_spots, media.after_spots), 1 to n, 1 where it does not
  // say or says something else.
  const photoSpots = (e, kind, n) => {
    const a = e?.media?.[kind + "_spots"];
    return (Array.isArray(e?.media?.[kind]) ? e.media[kind] : []).map((_, i) => (Array.isArray(a) && Number.isInteger(a[i]) && a[i] >= 1 && a[i] <= n ? a[i] : 1));
  };
  // ---------- end of the spots ----------

  // ---------- missions: open (waiting for funding) and funded (cleanup coming) ----------
  // Not receipts: they never count in the stats below until they are done and approved.
  const isNo = (v) => Number.isInteger(v) && v > 0 && v < 1e9;
  const missions = [];
  {
    const raw = await missionsP;
    const seenNo = new Set();
    for (const m of Array.isArray(raw) ? raw : []) {
      if (!m || !isNo(m.no) || (m.status !== "open" && m.status !== "funded") || seenNo.has(m.no)) continue;
      seenNo.add(m.no);
      missions.push(m);
    }
    // Sample missions, like the sample receipts, are only for an empty site: while sapu.earth has no real
    // mission and no real cleanup, they show what missions look like. They are stamped SAMPLE and never
    // shared, and their days count from today, so they never go stale. A failed /api/missions shows none. They show only
    // next to the sample receipts (allDemo, under SAMPLE DATA): with no receipt at all, as since 2026-11-16, when
    // data/events/index.json lists no sample, none show either.
    if (Array.isArray(raw) && !missions.length && !loadFailed && allDemo) {
      const sample = await fetch("site/samples/missions.json").then((r) => (r.ok ? r.json() : [])).catch(() => []);
      for (const m of Array.isArray(sample) ? sample : []) {
        if (!m || !isNo(m.no) || (m.status !== "open" && m.status !== "funded") || seenNo.has(m.no)) continue;
        seenNo.add(m.no);
        missions.push({ ...m, date: dayFromToday(Number.isInteger(m.in_days) ? m.in_days : 7), demo: true });
      }
    }
    // NEXT UP order: funded missions from today on (soonest first), then open ones (soonest first),
    // then the ones whose planned day has passed (most recent first). "Today" is the visitor's day.
    const today = dayFromToday(0);
    const day = (m) => (typeof m.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(m.date) ? m.date : "9999");
    // A mission with several spots has passed once the day of its last spot has (docs/missions.md, Spots).
    const last = (m) => spotsM(m).map((x) => x.date).sort().pop() || day(m);
    const rank = (m) => (last(m) < today ? 2 : m.status === "funded" ? 0 : 1);
    missions.sort((a, b) => rank(a) - rank(b)
      || (rank(a) === 2 ? day(b).localeCompare(day(a)) : day(a).localeCompare(day(b)))
      || a.no - b.no);
  }

  // ---------- stats (count-up) ----------
  const totals = {
    kg: events.reduce((s, e) => s + (e.result?.kg_estimate || 0), 0),
    events: events.length,
    paid: Math.round(events.reduce((s, e) => s + (e.money?.paid_eur ?? e.cost_eur ?? 0), 0)),
  };
  const fmt = {
    kg: (v) => (allDemo ? "~" : "") + Math.round(v).toLocaleString("en"),
    events: (v) => String(Math.round(v)),
    paid: (v) => (allDemo ? "~€" : "€") + Math.round(v).toLocaleString("en"),
  };
  document.querySelectorAll("[data-stat]").forEach((el) => {
    const key = el.dataset.stat;
    const target = totals[key];
    if (loadFailed && !events.length) { el.textContent = "?"; return; } // not known, which is not zero
    if (key === "kg" && target === 0 && events.length) { el.textContent = "?"; return; } // only sacks so far: the card says ? KG too
    if (reduceMotion || target === 0) { el.textContent = fmt[key](target); return; }
    const t0 = performance.now(), dur = 1400;
    (function tick(t) {
      const p = Math.min(1, (t - t0) / dur), ease = 1 - Math.pow(1 - p, 3);
      el.textContent = fmt[key](target * ease);
      if (p < 1) requestAnimationFrame(tick);
    })(t0);
  });
  // The row is hidden in index.html and shows once there is a receipt to count, or ? when the load failed: before the
  // first receipt it would say 0 KG REMOVED next to a funded mission (Marcus said 'Yes, build all 9' on 2026-11-16).
  $("#stats").hidden = !events.length && !loadFailed;
  if (totals.events === 1) $('[data-stat="events"] + span').textContent = "cleanup";

  // ---------- shared bits ----------
  const phOr = (src, tag, cls) => {
    const u = safeSrc(src);
    return u
      ? `<div class="${cls}"><img src="${escapeHTML(u)}" alt="${tag.toLowerCase()}" loading="lazy"><span class="tag">${tag}</span></div>`
      : `<div class="${cls}"><div class="ph">PHOTO SOON</div><span class="tag">${tag}</span></div>`;
  };
  const dateStr = (e) => {
    const ok = typeof e.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(e.date) && !isNaN(Date.parse(e.date + "T00:00:00"));
    return ok ? e.date : "TBA";
  };
  const rid = (e) => String(e.id || "").toUpperCase().replace(/[^A-Z0-9]+/g, "-");
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? Number(v.toFixed(1)).toLocaleString("en") : "?");
  const eur = (v) => (v ?? null) === null ? "?" : "€" + escapeHTML(typeof v === "number" ? Number(v.toFixed(2)) : v);
  const upper = (v, dflt) => escapeHTML(String(v || dflt).toUpperCase());
  const videosOf = (e) => (Array.isArray(e.media?.videos) ? e.media.videos.map(safeSrc).filter(Boolean) : []);
  // A video in a post, with its tag above the player, never on it: Safari puts fullscreen and picture in
  // picture at the top left of the video, and every browser its timeline at the bottom. The tag also names the player.
  // lazy: a receipt's videos in the one-column post, which load nothing until they come into view (lazyVideos). hid: one
  // that a long stage keeps out of view until its SHOW ALL is pressed (foldVideos, showRest).
  const videoBox = (src, tag, lazy, hid) => `<div class="pm pm-video"${hid ? " hidden" : ""}><span class="tag">${escapeHTML(tag)}</span><video controls playsinline preload="${lazy ? "none" : "metadata"}" src="${escapeHTML(src)}" aria-label="${escapeHTML(tag.toLowerCase())}"></video></div>`;
  // A mission's short video of the spot as the crew posted it, or null.
  const nowVideoOf = (m) => safeSrc(m?.now_video);
  // a receipt that finished a mission carries { no, url, now, now_video, funded_eur, currency, price_local, crew_local,
  // crew_size }
  const missionOf = (e) => (e.mission && isNo(e.mission.no) ? e.mission : null);
  // ---------- mission money: the same block in upload/upload.js, site/app.js, admin/admin.js and functions/_lib/missions.js ----------
  // A stored price read back: price the whole price (price_local, or a cleanup's total_cost_local), crew the crew's pay in
  // all, inside it (crew_local, crew_pay_local), people the crew size it was added up for. other: the rest of the price, to
  // the cent. each: the pay for each person to the cent, null without a crew size from 1 to 1000. exact: the crew's pay is
  // the same whole number of cents for each person, as for every price the crew page adds up since it asks for the pay
  // for each person. null when the numbers do not fit together (not numbers, a crew pay below 0 or above the price).
  function splitOf(price, crew, people) {
    if (!Number.isFinite(price) || !Number.isFinite(crew) || crew < 0 || crew > price) return null;
    const known = Number.isInteger(people) && people >= 1 && people <= 1000;
    const each = known ? Math.round((crew / people) * 100) / 100 : null;
    return { each, other: Math.round((price - crew) * 100) / 100, exact: known && Math.round(each * people * 100) === Math.round(crew * 100) };
  }
  // ---------- end of the mission money block ----------
  // ---------- local money rows (pure; tests/e2e.sh runs this block in node) ----------
  // A mission's price and a receipt's local money, the total first and its parts under it, as PAID does in euros. The
  // price is the whole mission: CREW PAY (15 × IDR 100,000 when it splits evenly, else with its head count) is part of
  // it, the rest is OTHER COSTS. A cleanup's own costs never show a pay for each person: APPROVE can change its crew
  // size, not its money.
  const isCur = (c) => /^[A-Z]{3}$/.test(c || "");
  const fin = (v) => typeof v === "number" && Number.isFinite(v);
  const localMoney = (cur, v) => (isCur(cur) && fin(v) ? cur + " " + v.toLocaleString("en", { maximumFractionDigits: 2 }) : "?");
  const crewPayText = (cur, crew, s, people) => (crew === 0 ? "NONE" : s.exact ? `${num(people)} × ${localMoney(cur, s.each)}`
    : s.each !== null ? `${localMoney(cur, crew)} FOR ${num(people)} PPL` : `${localMoney(cur, crew)} IN ALL`);
  const payRows = (cur, price, crew, people) => {
    const s = isCur(cur) && fin(price) && fin(crew) ? splitOf(price, crew, people) : null;
    return s ? [["CREW PAY", crewPayText(cur, crew, s, people)], ["OTHER COSTS", s.other > 0 ? localMoney(cur, s.other) : "NONE"]] : [];
  };
  const ownRows = (cur, total, crew) => {
    if (!fin(total) || crew > total) return [["CREW PAY", localMoney(cur, crew)]];
    const other = Math.round((total - crew) * 100) / 100;
    return [["SPENT", localMoney(cur, total)], ["CREW PAY", crew === 0 ? "NONE" : localMoney(cur, crew)], ["OTHER COSTS", other > 0 ? localMoney(cur, other) : "NONE"]];
  };
  const subRows = (rows, first = "") => rows.map(([dt, dd], i) => `<div class="r-sub${i ? "" : first}"><dt>${dt}</dt><dd>${escapeHTML(dd)}</dd></div>`).join("");
  const mMoney = (m) => (m.status === "funded"
    ? `<div class="r-total"><dt>FUNDED</dt><dd>${eur(m.funded_eur)}</dd></div>` +
      subRows([["ASKED", localMoney(m.currency, m.price_local)], ...payRows(m.currency, m.price_local, m.crew_local, m.crew_size)])
    : `<div class="r-total"><dt>ASKING</dt><dd>${escapeHTML(localMoney(m.currency, m.price_local))}</dd></div>` +
      subRows(payRows(m.currency, m.price_local, m.crew_local, m.crew_size)));
  const localRows = (e) => {
    const mis = missionOf(e);
    if (!mis) return "";
    const own = e.local_money;
    const rows = own && isCur(own.currency) && fin(own.crew) ? ownRows(own.currency, own.total, own.crew)
      : isCur(mis.currency) && fin(mis.price_local) ? [["ASKED", localMoney(mis.currency, mis.price_local)], ...payRows(mis.currency, mis.price_local, mis.crew_local, mis.crew_size)] : [];
    return subRows(rows, " r-local");
  };
  // ---------- end of the local money rows ----------
  // own crews: one total. partner cleanups: who did it, what we paid them, and the crew's share
  const moneyRows = (e) => {
    const m = e.money;
    const loc = localRows(e);
    if (!m && e.fromApi) return `<div class="r-total"><dt>PAID</dt><dd>PAYMENT PENDING</dd></div>` + loc;
    if (!m) return `<div class="r-total"><dt>PAID OUT</dt><dd>${eur(e.cost_eur)}</dd></div>`;
    let rows = `<div class="r-total"><dt>PAID</dt><dd>${eur(m.paid_eur)}</dd></div>`;
    if (m.crew_eur != null) rows += `<div class="r-sub"><dt>TO THE CREW</dt><dd>${eur(m.crew_eur)}</dd></div>`;
    else if (!loc) rows += `<div class="r-sub"><dt>CREW SHARE</dt><dd>NOT DISCLOSED</dd></div>`;
    if (m.ops_eur != null) rows += `<div class="r-sub"><dt>OPS + TRANSPORT</dt><dd>${eur(m.ops_eur)}</dd></div>`;
    return rows + loc;
  };
  // A crew's live logo (provider.logo in /api/events, partner.logo in /api/missions): only "/media/<32 hex>", never
  // a public bucket or another host, else nothing. 20 px next to the crew's name, in the posts only.
  const logoSrc = (u) => (typeof u === "string" && /^\/media\/[0-9a-f]{32}$/.test(u) ? u : null);
  const crewLogo = (u) => (logoSrc(u) ? `<img class="r-logo" src="${logoSrc(u)}" alt="" width="20" height="20" loading="lazy" decoding="async">` : "");
  // CLEANED BY. In the post (post true) the crew's logo and a link to its page /p/<slug>, while the crew is active
  // (provider.page is set then). The receipt card is role=button, so a link there would nest: it keeps the name alone.
  const byRow = (e, post) => {
    const p = e.provider;
    if (!p?.name) return "";
    const name = upper(p.name);
    if (!post) return `<div><dt>CLEANED BY</dt><dd>${name}</dd></div>`;
    const slug = p.slug;
    const link = typeof p.page === "string" && typeof slug === "string" && /^[a-z0-9-]{1,40}$/.test(slug)
      ? `<a href="/p/${slug}">${name}</a>` : name;
    return `<div><dt>CLEANED BY</dt><dd>${crewLogo(p.logo)}${link}</dd></div>`;
  };
  // COMMENTS ON INSTAGRAM or COMMENTS ON TIKTOK in a real receipt's post (social in /api/events: Sapu Earth's post, or the
  // crew's own while the crew is active): a plain link, new tab, no referrer, and nofollow ugc on a crew's link. Nothing
  // loads from Instagram or TikTok before the tap. Only the two stored forms of functions/_lib/social.js, compared as text,
  // since partner data is untrusted.
  const IG_POST = /^https:\/\/www\.instagram\.com\/(?:p|reel)\/[A-Za-z0-9_-]{5,40}\/$/;
  const TT_POST = /^https:\/\/www\.tiktok\.com\/@[A-Za-z0-9._]{2,24}\/(?:video|photo)\/\d{8,25}$/;
  const socialOf = (e) => {
    const s = e.fromApi && e.social;
    if (!s || typeof s.url !== "string" || (s.by !== "sapu" && s.by !== "crew")) return null;
    if (s.site === "instagram" && IG_POST.test(s.url)) return { site: "instagram", url: s.url, by: s.by };
    if (s.site === "tiktok" && TT_POST.test(s.url)) return { site: "tiktok", url: s.url, by: s.by };
    return null;
  };
  const commentsRow = (e) => {
    const s = socialOf(e);
    if (!s) return "";
    const line = `// on ${s.by === "sapu" ? "our" : "the crew's own"} ${s.site} post. tap to read the comments there or write one.`;
    const rel = s.by === "crew" ? "noopener noreferrer nofollow ugc" : "noopener noreferrer";
    return `<div class="post-comments"><a class="post-cbtn" href="${escapeHTML(s.url)}" target="_blank" rel="${rel}">COMMENTS ON ${s.site === "tiktok" ? "TIKTOK" : "INSTAGRAM"}<span aria-hidden="true"> ↗</span></a><p class="post-cline">${escapeHTML(line)}</p></div>`;
  };
  // SAY TERIMA KASIH (SAY THANK YOU) right under the photos of a receipt post (docs/upload-flow.md, Thanks): one tap,
  // POST /api/thanks. Real receipts of active crews only (provider.page is set then; thanks comes with migration 0007). A
  // sample shows the button and counts nothing, and a receipt of an inactive crew shows its count only. Nothing is saved on
  // the device: thankedHere remembers a tap only while this page is open. A stamped button keeps its focus (aria-disabled).
  const thankedHere = new Set();
  const thanksWord = (e) => (cc(e) === "ID" ? ["TERIMA KASIH", "id"] : cc(e) === "MY" ? ["TERIMA KASIH", "ms"] : ["THANK YOU", "en"]);
  const times = (n) => `${num(n)} ${n === 1 ? "time" : "times"}`;
  const thanksOpen = (e) => e.demo || (e.fromApi && typeof e.thanks === "number" && Number.isFinite(e.thanks) && e.thanks >= 0 && typeof e.provider?.page === "string");
  const thanksTail = (e) => { const [, l] = thanksWord(e); return (l === "id" ? " terima kasih is thank you in indonesian." : l === "ms" ? " terima kasih is thank you in malay." : "") + " the crew sees the count on its crew page."; };
  const thanksBase = (e) => (e.demo ? "// sample receipt: nothing is counted." : (e.thanks > 0 ? `// thanked ${times(e.thanks)}.` : "// be the first to thank this crew.") + thanksTail(e));
  const thanksDone = (e) => (e.demo ? "// sample receipt: nothing is counted." : `// counted. thanked ${times(e.thanks)} so far. the crew sees the count on its crew page.`);
  const thanksLabel = (word, lang, done) => (done ? `<span lang="${lang}">${word}</span> ✓` : `SAY <span lang="${lang}">${word}</span>`);
  const thanksRow = (e) => {
    if (!thanksOpen(e)) return e.fromApi && typeof e.thanks === "number" && e.thanks > 0 ? `<div class="post-thanks"><p class="thanks-line">// thanked ${times(e.thanks)}.</p></div>` : "";
    const [word, lang] = thanksWord(e);
    const done = thankedHere.has(String(e.id));
    return `<div class="post-thanks"><button type="button" class="thanks-btn${done ? " thanks-done" : ""}"${done ? ' aria-disabled="true"' : ""}>${thanksLabel(word, lang, done)}</button><p class="thanks-line" role="status">${escapeHTML(done ? thanksDone(e) : thanksBase(e))}</p></div>`;
  };
  // THANKED on a receipt card, only above 0 and never on a sample.
  const thankedRow = (e) => (!e.demo && e.fromApi && typeof e.thanks === "number" && e.thanks > 0
    ? `<div class="r-thanked"><dt>THANKED</dt><dd>${num(e.thanks)} ${e.thanks === 1 ? "TIME" : "TIMES"}</dd></div>` : "");
  const nowOf = (m) => (Array.isArray(m?.now) ? m.now.map(safeSrc).filter(Boolean) : []);
  // SPOT 1, SPOT 2, ...: a row for each spot, its place and the country, and its day on a line of its own (an ISO day
  // broke at its hyphen on a 320 px card), in place of LOC and the day. "" for a mission or receipt with one spot.
  const spotRows = (spots, country) => spots.map((s) => `<div><dt>SPOT ${s.no}</dt><dd>${upper(s.name, "TBA")} · ${country}<br>${dateStr(s)}</dd></div>`).join("");
  // The receipt post on a phone: the first before and the first after photo of each spot (BEFORE · SPOT 2). "" for one spot.
  const spotPairs = (e) => {
    const spots = spotsE(e);
    const first = (kind, k) => { const i = photoSpots(e, kind, spots.length).indexOf(k); return i < 0 ? null : e.media[kind][i]; };
    return spots.map((s) => phOr(first("before", s.no), "BEFORE · SPOT " + s.no, "pm") + phOr(first("after", s.no), "AFTER · SPOT " + s.no, "pm")).join("");
  };
  // SEE THE SPOT ON SATELLITE, in a post with a point: the satellite map there (seeSpot, in the globe section). With
  // several spots (spotsE, spotsM), one button for each spot with a point, SEE SPOT 2 ON SATELLITE. Each button carries its
  // point (data-lat, data-lng) for its handler (satButtons).
  const satRow = (lat, lng, spots = []) => {
    const pts = spots.length ? spots.filter((s) => s.lat !== null).map((s) => [s.lat, s.lng, `SEE SPOT ${s.no} ON SATELLITE`])
      : Number.isFinite(lat) && Number.isFinite(lng) ? [[lat, lng, "SEE THE SPOT ON SATELLITE"]] : [];
    return typeof Globe === "function" && pts.length
      ? `<div class="post-sat">${pts.map(([a, b, label]) => `<button type="button" class="post-link post-map" data-lat="${a}" data-lng="${b}">${label}</button>`).join("")}</div>` : "";
  };

  // ---------- receipt cards ----------
  const cards = $("#cards");
  cards.innerHTML = "";
  if (!events.length) {
    cards.innerHTML = loadFailed
      ? '<p class="loading">COULDN’T LOAD THE CLEANUPS. CHECK YOUR CONNECTION &amp; REFRESH.</p>'
      : '<p class="loading">FIRST CLEANUP DROPS SOON. STAY TUNED.</p>';
  }
  events.forEach((e) => {
    const card = document.createElement("article");
    card.className = "card";
    card.id = "ev-" + String(e.id);
    card.tabIndex = 0;
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", "Open cleanup receipt: " + (e.location?.name || e.id));
    card.innerHTML = `
      <div class="stamp${e.demo ? "" : " stamp-ok"}">${e.demo ? "SAMPLE" : "VERIFIED"}</div>
      ${videosOf(e).length || nowVideoOf(missionOf(e)) ? '<div class="vid-tag">▶ VIDEO</div>' : ""}
      ${missionOf(e) ? `<div class="mis-tag">MISSION #${missionOf(e).no}</div>` : ""}
      <div class="r-head">SAPU EARTH<span>CLEANUP RECEIPT</span></div>
      <div class="ba">${phOr(e.media?.before?.[0], "BEFORE", "b")}${phOr(e.media?.after?.[0], "AFTER", "a")}</div>
      <dl class="r-rows">
        ${spotRows(spotsE(e), cc(e)) || `<div><dt>LOC</dt><dd>${upper(e.location?.name, "TBA")} · ${cc(e)}</dd></div>
        <div><dt>DATE</dt><dd>${dateStr(e)}</dd></div>`}
        <div><dt>SACKS</dt><dd>${num(e.result?.sacks)}</dd></div>
        <div><dt>TRASH</dt><dd>${num(e.result?.kg_estimate)} KG</dd></div>
        <div><dt>CREW</dt><dd>${num(e.crew?.size)} PPL</dd></div>
        ${byRow(e)}${thankedRow(e)}
        ${moneyRows(e)}
      </dl>
      <div class="r-note">*** EVERY EURO ACCOUNTED FOR ***</div>
      <div class="barcode" aria-hidden="true"></div>
      <div class="r-id">${rid(e)}</div>`;
    card.addEventListener("click", () => openPost(e));
    card.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); openPost(e); } });
    cards.appendChild(card);
  });

  // ---------- post lightbox (a receipt as a shareable post) ----------
  const overlay = $("#post");
  let lastFocus = null;
  // The wide post (the wide post's slides, below; styles.css, the wide post): on a screen at least WIDE a post opens in two
  // columns. The same query is in the comment over its rules in styles.css; change both. reopen draws the open post again
  // (crossing WIDE), null while a chooser or nothing is open; stage is the open wide post's stage, null otherwise.
  const WIDE = matchMedia("(min-width: 900px) and (min-height: 520px)");
  let reopen = null, stage = null;
  // Every SEE ... ON SATELLITE of the post on show flies to its own point (satRow).
  function satButtons() {
    overlay.querySelectorAll(".post-map").forEach((b) => b.addEventListener("click", () => seeSpot(Number(b.dataset.lat), Number(b.dataset.lng))));
  }
  function openPost(e) {
    if (overlay.hidden) lastFocus = document.activeElement;
    reopen = () => openPost(e);
    stage = null;
    const clips = (Array.isArray(e.media?.clips) ? e.media.clips : []).map(safeSrc).filter(Boolean)
      .map((c, i) => `<a href="${escapeHTML(c)}" rel="noopener" target="_blank">CLIP ${String(i + 1).padStart(2, "0")} ↗</a>`).join("");
    // every video of the cleanup in the order of the day, each with its tag (videosIn, in the wide post's slides); a stage
    // of more than 3 shows its first 2, then SHOW ALL 30 BEFORE VIDEOS for the rest (foldVideos, showRest)
    const videos = foldVideos(videosIn(e)).map((v) => (v.more ? `<div class="pm pm-more"><button type="button" class="post-link pm-show">${escapeHTML(v.more)}</button></div>` : videoBox(v.src, v.tag, true, v.hid))).join("");
    // a cleanup that finished a mission also shows the spot as the crew posted it, its video too
    const mis = missionOf(e);
    const misNow = nowOf(mis)[0];
    const misVideo = nowVideoOf(mis);
    // On a wide screen the paper goes without its photos and stamp and without its own links (acts: COPY LINK, SHARE, ALL
    // CLEANED MISSIONS), which the stage left of it shows under the photos, and the frame around both is the dialog
    // (wideHtml). Below WIDE the post is the one column, a stage of more than 3 videos folded after its first 2
    // (foldVideos).
    const wide = WIDE.matches, slides = wide ? receiptSlides(e) : null;
    const stamp = `<div class="stamp${e.demo ? "" : " stamp-ok"} post-stamp">${e.demo ? "SAMPLE" : "VERIFIED"}</div>`;
    const acts = `<div class="post-actions"><button class="post-link post-copy">COPY LINK</button>${navigator.share ? '<button class="post-link post-share">SHARE</button>' : ""}</div>
        ${mis && e.fromApi ? `<p class="post-all"><a href="/missions?status=cleaned#m-${mis.no}">ALL CLEANED MISSIONS →</a></p>` : ""}`;
    const paper = `
      <div class="post-paper"${wide ? "" : ' role="dialog" aria-modal="true" aria-label="Cleanup receipt"'}>
        <button class="post-close" aria-label="Close">✕</button>
        ${wide ? "" : stamp}
        <div class="r-head">SAPU EARTH<span>CLEANUP RECEIPT · ${dateStr(e)}</span></div>
        ${wide ? "" : `<div class="post-media">${misNow ? phOr(misNow, "NOW · MISSION #" + mis.no, "pm") : ""}${misVideo ? videoBox(misVideo, "NOW · MISSION #" + mis.no + " · VIDEO", true) : ""}${spotPairs(e) || phOr(e.media?.before?.[0], "BEFORE", "pm") + phOr(e.media?.after?.[0], "AFTER", "pm")}${videos}</div>`}
        ${thanksRow(e)}
        <dl class="r-rows">
          ${spotRows(spotsE(e), cc(e)) || `<div><dt>LOC</dt><dd>${upper(e.location?.name, "TBA")} · ${cc(e)}</dd></div>`}
          ${mis ? `<div><dt>MISSION</dt><dd>#${mis.no}</dd></div>` : ""}
          <div><dt>SACKS</dt><dd>${num(e.result?.sacks)}</dd></div>
          <div><dt>TRASH</dt><dd>${num(e.result?.kg_estimate)} KG</dd></div>
          <div><dt>CREW</dt><dd>${num(e.crew?.size)} PPL</dd></div>
          <div><dt>DISPOSAL</dt><dd>${upper(e.result?.disposal, "TBA")}</dd></div>
          ${byRow(e, true)}
          ${moneyRows(e)}
        </dl>
        ${clips ? `<div class="post-clips">${clips}</div>` : ""}
        ${e.notes && e.fromApi ? `<p class="post-notes">${escapeHTML(e.notes)}</p>` : ""}
        ${commentsRow(e)}
        ${satRow(e.location?.lat, e.location?.lng, spotsE(e))}
        <div class="r-note">*** EVERY EURO ACCOUNTED FOR ***</div>
        <div class="barcode" aria-hidden="true"></div>
        ${wide ? "" : acts}
        <div class="r-id">${rid(e)}</div>
      </div>`;
    overlay.innerHTML = wide ? wideHtml("Cleanup receipt", slides, stamp, paper, acts) : paper;
    showOverlay("#ev-" + encodeURIComponent(e.id));
    if (slides) startStage(slides);
    lazyVideos(); // the one column's videos (a wide post has none in its paper)
    // partner uploads get /r/<id>, which carries link previews for social media
    const shareUrl = e.fromApi
      ? SHARE_ORIGIN + "/r/" + encodeURIComponent(e.id)
      : location.origin + location.pathname + "#ev-" + encodeURIComponent(e.id);
    overlay.querySelector(".post-copy").addEventListener("click", (ev) => {
      (navigator.clipboard?.writeText(shareUrl) || Promise.reject())
        .then(() => (ev.target.textContent = "COPIED ✓"))
        .catch(() => (ev.target.textContent = shareUrl));
    });
    overlay.querySelector(".post-share")?.addEventListener("click", () => {
      navigator.share({ title: "Sapu Earth cleanup receipt", url: shareUrl }).catch(() => {});
    });
    satButtons();
    overlay.querySelector(".thanks-btn")?.addEventListener("click", (ev) => sayThanks(e, ev.currentTarget));
    overlay.querySelectorAll(".pm-show").forEach((b) => b.addEventListener("click", () => showRest(b.parentElement)));
  }
  // SHOW ALL 30 BEFORE VIDEOS in the one-column post (foldVideos): the rest of its stage, hidden right after the button's
  // box, shows in place under the first 2, in order, the button goes, and the focus moves to the first video it showed,
  // with no scroll, so a keyboard or a screen reader goes on there. The paper's scroll is put back as it was: with the
  // top of the view in the button's box, Chrome's scroll anchoring held the next stage's first video in place instead,
  // and the 28 videos shown and the focus landed 15,500 px above the reader (WebKit has no scroll anchoring). The
  // second click of a double click on the button does nothing (the post's own guard, openedAt), so it plays no video.
  // lazyVideos has watched them since the post opened (hidden, they were never near the view): once shown they load as
  // the others do. Nothing is kept: the post drawn again (reopen, Back and Forward) starts folded.
  function showRest(box) {
    const paper = box.closest(".post-paper"), top = paper.scrollTop, rest = [];
    for (let el = box.nextElementSibling; el?.hidden; el = el.nextElementSibling) rest.push(el);
    box.remove();
    rest.forEach((el) => { el.hidden = false; });
    paper.scrollTop = top;
    rest[0]?.querySelector("video")?.focus({ preventScroll: true });
    openedAt = performance.now(); openX = pressX; openY = pressY;
  }
  // One thank you from a receipt post. No automatic retry: a tap that did not get through says so, and the next tap is
  // the visitor's. A sample only stamps the button.
  async function sayThanks(e, btn) {
    if (btn.getAttribute("aria-disabled") === "true") return;
    const line = btn.parentElement.querySelector(".thanks-line");
    const [word, lang] = thanksWord(e);
    const say = (text) => { if (line.isConnected) line.textContent = text; };
    const stamp = () => { btn.setAttribute("aria-disabled", "true"); btn.classList.add("thanks-done"); btn.innerHTML = thanksLabel(word, lang, true); };
    const unstamp = () => { btn.removeAttribute("aria-disabled"); btn.classList.remove("thanks-done"); btn.innerHTML = thanksLabel(word, lang, false); };
    if (e.demo) { stamp(); say("// sample receipt: nothing is counted."); return; }
    const id = String(e.id);
    if (thankedHere.has(id)) return;
    thankedHere.add(id); stamp(); say("// sending…");
    let r = null, body = null;
    try {
      r = await fetch("/api/thanks", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }), keepalive: true, cache: "no-store" });
      body = await r.json().catch(() => null);
    } catch { r = null; }
    if (r && r.ok && body && typeof body.thanks === "number") {
      e.thanks = Math.max(e.thanks || 0, body.thanks); // /api/events may be a minute old
      syncCardThanks(e);
      if (body.counted === true) { say(thanksDone(e)); return; }
      thankedHere.delete(id); unstamp(); say("// today's thanks are full. try again tomorrow."); return;
    }
    thankedHere.delete(id);
    // 409 inactive: Sapu Earth stopped working with the crew since the page loaded. The receipt stays on sapu.earth with
    // its count and takes no new thanks, as its post shows after a reload. 404: the receipt itself is gone.
    if (r && r.status === 409 && body && body.code === "inactive") {
      btn.remove(); say(e.thanks > 0 ? `// thanked ${times(e.thanks)}. this receipt takes no more thanks.` : "// this receipt takes no more thanks."); return;
    }
    if (r && r.status === 404) { btn.remove(); say("// this receipt is no longer on sapu.earth."); return; }
    unstamp(); say("// not sent. check your connection and tap again.");
  }
  // The receipt's card follows the new count at once: its THANKED row goes right before the money rows.
  function syncCardThanks(e) {
    const rows = document.getElementById("ev-" + String(e.id))?.querySelector(".r-rows");
    if (!rows) return;
    rows.querySelector(".r-thanked")?.remove();
    const html = thankedRow(e);
    if (!html) return;
    const money = rows.querySelector(".r-total");
    if (money) money.insertAdjacentHTML("beforebegin", html); else rows.insertAdjacentHTML("beforeend", html);
  }
  // When the post or the chooser opened, or a SHOW ALL showed its videos (showRest), and where the press that did it
  // was. There is none when it opened from the link, by Enter or Space, or with no press since the last close.
  let openedAt = 0, openX = NaN, openY = NaN, pressX = NaN, pressY = NaN;
  const forgetPress = () => { pressX = pressY = NaN; };
  addEventListener("pointerdown", (ev) => { pressX = ev.clientX; pressY = ev.clientY; }, true);
  addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") forgetPress(); }, true);
  // The phone's Back closes an open post or chooser (Marcus said 'Yes, build all 9' on 2026-11-16; before, Back left
  // sapu.earth, or closed Instagram's browser). A post or chooser that a tap opens over the page takes a step in the
  // history ({ post: 1 }, at the post's #ev- or #m- address), and ✕, the backdrop and Escape go back over that step too
  // (leavePost). A post opened by the link the page came with (#m-2 from /m/2, a shared #ev-) takes no step, so Back
  // there still goes back to the app the link came from. A post drawn again (another size) or opened from a chooser
  // keeps the step there is. The page under the step loses its # first (#main from SEE THE RECEIPTS), and the browser
  // restores no scroll when it goes back there (scrollRestoration manual): going back to it scrolled the page away from
  // the card the post opened from, to the # in Chrome and to where that page last stood in WebKit (iPhones), and dropped
  // the focus. Once the step back is over the page gets auto back (a timer: WebKit decides on the scroll right after the
  // popstate), so a reload still puts it where it was, and so does a Back from another site that loads the page again
  // (Mobile Safari puts such a page near the top all the same): kept manual until the page was put away, it came back at
  // the top after a post was closed (WebKit, 2026-11-17).
  // Forward onto a post's step shows that post again (popstate, openLinked); a chooser's step is skipped.
  let linked = true; // false once the link the page came with has opened its post (openLinked, below)
  const stepped = () => history.state?.post === 1;
  function showOverlay(hash) {
    openedAt = performance.now();
    openX = pressX; openY = pressY;
    const step = overlay.hidden && !linked;
    overlay.hidden = false;
    document.body.classList.add("post-open");
    if (step) {
      if (location.hash) history.replaceState(history.state, "", location.pathname + location.search);
      history.scrollRestoration = "manual"; // the page under the step
      history.pushState({ post: 1 }, "", hash || location.href);
      history.scrollRestoration = "auto"; // the post's step: a reload there puts the page back
    } else if (hash) history.replaceState(history.state, "", hash);
    overlay.querySelector(".post-close").focus();
    overlay.querySelector(".post-close").addEventListener("click", () => leavePost());
  }
  // shuts the post or chooser and leaves the history alone: leavePost and Back see to that
  function closePost() {
    reopen = stage = null;
    lazyStop();
    overlay.hidden = true;
    overlay.innerHTML = "";
    document.body.classList.remove("post-open");
    forgetPress();
    if (lastFocus) lastFocus.focus();
  }
  // A receipt's videos in the one-column post come with preload none (videoBox, lazy): a receipt can have 61 of them (60
  // of the cleanup and its mission's), and all their first frames at once would be close to 200 /media/ requests in a
  // second, over the rate limiting rule (100 in 10 s per address, docs/upload-flow.md), which then blocks the visitor for
  // 10 s, and megabytes of data. A video loads its first frame (metadata) once it has been within 300 px of the paper's
  // view for a quarter of a second, and one at most every second (also when the next one comes near only after the last
  // started), those that came near first first, so a quick scroll past loads nothing and a long scroll down 60 of them
  // stays near 50 requests in 10 s (Chrome asks 3 to 5 ranges of a phone's video). The videos a long stage keeps hidden
  // until its SHOW ALL (foldVideos) are watched from the start too: hidden, they are never near the view, and once shown
  // (showRest) they load as the others do. Without IntersectionObserver they load only when played. lazyStop ends the
  // watch of the post before (a new post, closePost); the wide post has its own (startStage).
  let lazyStop = () => {};
  function lazyVideos() {
    lazyStop();
    const paper = overlay.querySelector(".post-paper");
    const vids = [...overlay.querySelectorAll('.post-media video[preload="none"]')];
    if (!paper || !vids.length || typeof IntersectionObserver !== "function") return;
    const near = new Map(); // a video near the view -> since when
    let timer = 0, last = -1e9; // last: when the last video started to load
    const pump = () => {
      timer = 0;
      const now = performance.now(), v = now >= last + 1000 && [...near].find(([, since]) => now - since >= 250)?.[0];
      if (v) { near.delete(v); io.unobserve(v); if (v.isConnected) { v.preload = "metadata"; last = now; } }
      if (near.size) timer = setTimeout(pump, Math.max(100, last + 1000 - now));
    };
    const io = new IntersectionObserver((entries) => {
      for (const en of entries) {
        if (!en.isIntersecting) near.delete(en.target);
        else if (!near.has(en.target)) near.set(en.target, performance.now());
      }
      if (near.size && !timer) timer = setTimeout(pump, 250);
    }, { root: paper, rootMargin: "300px 0px" });
    vids.forEach((v) => io.observe(v));
    lazyStop = () => { io.disconnect(); clearTimeout(timer); near.clear(); lazyStop = () => {}; };
  }
  // ✕, the backdrop, Escape and SEE THE SPOT: shut, then go back over the step the tap took, or drop the post's address.
  // then runs once the post is shut, after the step back: going back puts the page's scroll where it was at the tap
  // (after popstate), so a flight to the spot (seeSpot) starts after that, never under it. Once shut it goes back no more:
  // a second close before the step back has landed would otherwise go back a second step, off sapu.earth.
  let afterBack = null;
  function leavePost(then) {
    if (overlay.hidden) { if (then) then(); return; }
    const back = stepped();
    closePost();
    if (!back) { history.replaceState(null, "", location.pathname); if (then) then(); return; }
    afterBack = then || null;
    history.back();
  }
  addEventListener("popstate", () => {
    if (!overlay.hidden) closePost();
    else if (stepped() && !openLinked()) history.back(); // Forward onto a step: its post again, or past a chooser's
    const then = afterBack;
    afterBack = null;
    if (then) setTimeout(then, 0);
    setTimeout(() => { if (!stepped()) history.scrollRestoration = "auto"; }, 0); // the page, once the step back is over
  });
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") history.scrollRestoration = "auto"; });
  // The second click of the double click (or double tap) that opened the post or the chooser, or pressed a
  // SHOW ALL, lands where the first one did, on whatever opened under it: a row, a link, the backdrop, the
  // first video shown. A click there in the first 500 ms does nothing. Any other click, ✕ for one, works at
  // once, and so does Enter or Space (their click has detail 0).
  overlay.addEventListener("click", (ev) => {
    if (ev.detail && performance.now() - openedAt < 500 && Math.hypot(ev.clientX - openX, ev.clientY - openY) < 40) {
      ev.stopImmediatePropagation(); ev.preventDefault();
    }
  }, true);
  // a click on the dark backdrop closes the post
  overlay.addEventListener("click", (ev) => { if (ev.target === overlay) leavePost(); });
  addEventListener("keydown", (ev) => { if (ev.key === "Escape" && !overlay.hidden) leavePost(); });

  // ---------- photos after Back (tests/e2e.sh runs this block in node) ----------
  // WebKit (iPhone Safari, Instagram's browser on iPhones) keeps a page that is left in its back-forward cache, and the
  // photos still on their way at that moment come back broken after Back, with no new try: a card's or a post's, when
  // a visitor taps away before they arrive, more likely on a slow connection (seen on live sapu.earth on 2026-11-17).
  // A page back from that cache asks once more for each picture that did not load: only once WebKit has finished
  // bringing the page back (a picture asked for during pageshow kept WebKit from firing pagehide and pageshow on the
  // next leave and Back, and the page then came back at the top), and with its src taken off first (WebKit answers a
  // src set to the value it already has from the failed picture it kept, without asking).
  // The scroll too: a page back from that cache goes back to where it was left (pagehide), once it is back. Back from
  // another site (INSTAGRAM or TIKTOK in WANT IN?), Mobile Safari put the page near the top unless its scrollRestoration
  // was still manual, so after a closed post only the first such Back kept the place (iOS Simulator), and a page left
  // with a post open came back with the page under the post at the top (WebKit, 2026-11-17). Where the browser already
  // put it back, this does nothing, nor after the window changed width while away: a phone turned on its side (Chrome
  // on Android) has already been placed in the new layout, where the old place would be 300 px off the card. A page
  // that comes back still manual (left before a step back was over) gets auto.
  // And the focus: WebKit scrolls a page back from that cache to the element that has the focus, so a card the focus
  // went back to when its post closed (closePost) pulled the page back down to it after the visitor had scrolled away
  // and left (by the address bar, without a tap in the page). WebKit scrolls to it only when none of it is on the
  // screen, so a focus wholly off the screen as the page is left (above, below or to a side) is let go once the page is
  // back, at the start of its pageshow, before WebKit scrolls to it; one partly on the screen stays, and so does the
  // page (iOS Simulator and WKWebView, 2026-11-18). A card is on the screen only where its row shows it (THE RECEIPTS
  // and NEXT UP scroll sideways), and in a row WebKit takes less than about 32 px of it as none: it scrolled the row
  // back to a focused card swiped out of it, its edge still in the window, and to one that showed up to 31 px in it, so
  // a card that shows less than 40 px in its row is let go too (WKWebView and iOS Simulator, 2026-11-18). WebKit takes
  // no focus change while a page goes into that cache (a blur in pagehide did nothing there), and a page coming back
  // reads as at the top for a moment, so where the focus stands is read as the page is left.
  let leftAt = null, leftW = 0, letGo = null;
  addEventListener("pagehide", () => {
    leftAt = scrollY; leftW = innerWidth;
    const f = document.activeElement, b = f && f !== document.body ? f.getBoundingClientRect() : null;
    const row = b && f.closest?.(".cards")?.getBoundingClientRect();   // a card shows only inside its row
    const left = row ? Math.max(0, row.left) : 0, right = row ? Math.min(innerWidth, row.right) : innerWidth;
    const across = b ? Math.min(b.right, right) - Math.max(b.left, left) : 0;   // how much of it shows, across
    letGo = b && (b.bottom <= 0 || b.top >= innerHeight || across <= 0 || (row && across < 40 && across < b.right - b.left)) ? f : null;
  });
  addEventListener("pageshow", (ev) => {
    if (!ev.persisted) return;
    letGo?.blur();
    letGo = null;
    const putBack = leftAt;
    if (history.scrollRestoration === "manual") history.scrollRestoration = "auto";
    setTimeout(() => {
      if (putBack !== null && innerWidth === leftW && scrollY !== putBack) scrollTo({ top: putBack, behavior: "instant" });
      document.querySelectorAll("img").forEach((im) => {
        if (!im.getAttribute("src") || !im.complete || im.naturalWidth) return;
        const u = im.src;
        im.removeAttribute("src");
        im.src = u;
      });
    });
  });
  // ---------- end of photos after Back ----------

  // ---------- the wide post's slides (pure; tests/e2e.sh runs this block in node) ----------
  // On a screen at least WIDE a post is two columns: the stage on the left shows every photo and video of the post, one
  // slide at a time, and the receipt paper stands on the right as on a phone (styles.css, the wide post). A slide is a
  // list of one or two items { src, tag, video }; src null is a photo still missing (PHOTO SOON, as phOr shows it).
  // vtag: a video's tag by its stage, before it is numbered (videosIn).
  const vtag = (st) => (st === "before" ? "BEFORE · VIDEO" : st === "after" ? "AFTER · VIDEO" : "VIDEO");
  const nth = (word, i, n) => (n > 1 ? `${word} ${i + 1}/${n}` : word);
  // A receipt's videos in the order of the day, [{ src, stage, tag, video }]: those before the cleanup, those after it,
  // then those sent without a stage, each group in the order it came in (the upload order, mediaFor) and numbered like
  // the photos when it has more than one: BEFORE · VIDEO 1/30 to BEFORE · VIDEO 30/30, BEFORE · VIDEO for one, VIDEO 1/2
  // without a stage. video_stages goes with videos, one each; it is compared as text only, never used as a key, since
  // partner data is untrusted, and anything but "before" or "after" is no stage. Unsafe links are left out before the
  // count. Both posts use it: the wide post's slides and openPost's one column.
  const videosIn = (e) => {
    const st = Array.isArray(e.media?.video_stages) ? e.media.video_stages : [];
    const all = (Array.isArray(e.media?.videos) ? e.media.videos : [])
      .map((v, i) => ({ src: safeSrc(v), stage: st[i] === "before" || st[i] === "after" ? st[i] : null })).filter((v) => v.src);
    return ["before", "after", null].flatMap((k) => {
      const same = all.filter((v) => v.stage === k);
      return same.map((v, i) => ({ src: v.src, stage: k, tag: nth(vtag(k), i, same.length), video: true }));
    });
  };
  // On a phone (openPost's one column) a stage of more than 3 videos shows its first 2, then a button for the rest of the
  // stage, which stays out of view and loads nothing until the button is pressed (showRest): SHOW ALL 30 BEFORE VIDEOS,
  // SHOW ALL 30 AFTER VIDEOS, or SHOW ALL 12 VIDEOS for those sent without a stage, with the stage's own count (Marcus,
  // 2026-11-19: "Yes, shorten them", keeping every original, each a tap away). A stage of 1, 2 or 3 shows whole, and so
  // does the wide post, one slide at a time. foldVideos takes videosIn's list and gives back the same videos in the same
  // order with the same tags, the 3rd and later of a folded stage with hid, and the button's words as { more } right
  // before them.
  const foldVideos = (vids) => vids.flatMap((v) => {
    const same = vids.filter((x) => x.stage === v.stage), i = same.indexOf(v);
    if (same.length <= 3 || i < 2) return [{ ...v, hid: false }];
    if (i > 2) return [{ ...v, hid: true }];
    return [{ more: `SHOW ALL ${same.length} ${v.stage === "before" ? "BEFORE " : v.stage === "after" ? "AFTER " : ""}VIDEOS` }, { ...v, hid: true }];
  });
  // A mission: NOW 1/3 to NOW 3/3 (NOW for one photo, NOW with PHOTO SOON for none), then NOW · VIDEO.
  const missionSlides = (m) => {
    const now = nowOf(m), out = (now.length ? now : [null]).map((u, i) => [{ src: u, tag: nth("NOW", i, now.length) }]);
    if (nowVideoOf(m)) out.push([{ src: nowVideoOf(m), tag: "NOW · VIDEO", video: true }]);
    return out;
  };
  // A cleanup: its first before and first after side by side (PHOTO SOON for a missing one), then every photo and video
  // alone in the order of the day: the spot as the crew posted its mission, before, the videos before, after, the videos
  // after, and any videos sent without a stage (videosIn: placed by their stage, never by their tag, which is numbered).
  // The receipt of a mission with several spots (spotsE) names each photo's spot and counts it in that spot: BEFORE 1/2 ·
  // SPOT 2.
  // photosOf: a receipt's photos of media[kind] with their tags, [{ src, tag }], unsafe links left out.
  const photosOf = (e, kind, word) => {
    const n = spotsE(e).length, at = photoSpots(e, kind, n || 1);
    const list = (Array.isArray(e.media?.[kind]) ? e.media[kind] : []).map((u, i) => ({ src: safeSrc(u), spot: at[i] })).filter((x) => x.src);
    return list.map((x, i) => {
      const same = list.filter((y) => y.spot === x.spot);
      return { src: x.src, tag: n ? nth(word, same.indexOf(x), same.length) + " · SPOT " + x.spot : nth(word, i, list.length) };
    });
  };
  const receiptSlides = (e) => {
    const before = photosOf(e, "before", "BEFORE"), after = photosOf(e, "after", "AFTER"), n = spotsE(e).length;
    const vids = videosIn(e);
    const out = [[before[0] || { src: null, tag: n ? "BEFORE · SPOT 1" : "BEFORE" }, after[0] || { src: null, tag: n ? "AFTER · SPOT 1" : "AFTER" }]];
    const mis = missionOf(e), now = nowOf(mis);
    now.forEach((u, i) => out.push([{ src: u, tag: nth("NOW", i, now.length) + " · MISSION #" + mis.no }]));
    if (nowVideoOf(mis)) out.push([{ src: nowVideoOf(mis), tag: "NOW · MISSION #" + mis.no + " · VIDEO", video: true }]);
    before.forEach((it) => out.push([it]));
    vids.filter((v) => v.stage === "before").forEach((v) => out.push([v]));
    after.forEach((it) => out.push([it]));
    vids.filter((v) => v.stage === "after").forEach((v) => out.push([v]));
    vids.filter((v) => v.stage === null).forEach((v) => out.push([v]));
    return out;
  };
  // The wide post's dialog: the frame, with the paper first (focus starts on its ✕) and the stage, which styles.css draws
  // on the left. Only the first slide shows. Photos load lazily and videos not at all (preload none) until their slide
  // shows (startStage). The tag above each picture is also its name. Under the photos the bar: the stamp, the arrows and
  // the post's own links (acts, from openPost and openMission; none on a sample mission), so the paper is shorter here.
  const pvItem = (it) => `<figure class="pv-item"><figcaption class="pv-tag">${escapeHTML(it.tag)}</figcaption>${it.video
    ? `<video controls playsinline preload="none" src="${escapeHTML(it.src)}" aria-label="${escapeHTML(it.tag.toLowerCase())}"></video>`
    : it.src ? `<img src="${escapeHTML(it.src)}" alt="${escapeHTML(it.tag.toLowerCase())}" loading="lazy" decoding="async">`
    : '<div class="ph">PHOTO SOON</div>'}</figure>`;
  const wideHtml = (label, slides, stamp, paper, acts) => `
      <div class="post-frame" role="dialog" aria-modal="true" aria-label="${escapeHTML(label)}">${paper}
        <section class="pv-stage" aria-label="Photos and videos">
          <div class="pv-slides">${slides.map((s, i) => `<div class="pv-slide${s.length > 1 ? " pv-two" : ""}"${i ? " hidden" : ""}>${s.map(pvItem).join("")}</div>`).join("")}</div>
          <div class="pv-bar">${stamp}${slides.length > 1 ? '<div class="pv-nav"><button type="button" class="pv-prev" aria-label="Previous photo or video">←</button><span class="pv-count"></span><button type="button" class="pv-next" aria-label="Next photo or video">→</button></div>' : ""}${acts ? `<div class="pv-acts">${acts}</div>` : ""}<p class="pv-live" aria-live="polite"></p></div>
        </section>
      </div>`;
  // ---------- end of the wide post's slides ----------

  // The open wide post's stage. One slide shows (go), the others are hidden and their videos paused. A slide's videos load
  // their first frame only once it shows (preload none, then metadata), and the photos of the slides next to it load
  // ahead (lazy, then eager), so an arrow shows them at once. The arrows stop at the ends (aria-disabled). A before and an
  // after stand side by side, or one above the other when that shows them larger in all (lay).
  function startStage(slides) {
    const els = [...overlay.querySelectorAll(".pv-slide")], box = overlay.querySelector(".pv-slides");
    const count = overlay.querySelector(".pv-count"), live = overlay.querySelector(".pv-live");
    const prev = overlay.querySelector(".pv-prev"), next = overlay.querySelector(".pv-next");
    const st = { at: 0 };
    st.lay = () => {
      const el = els[st.at], ms = [...el.querySelectorAll("img, video")];
      if (!el.classList.contains("pv-two") || ms.length !== 2) return;
      const rs = ms.map((x) => (x.naturalWidth || x.videoWidth) / (x.naturalHeight || x.videoHeight));
      if (!rs.every((r) => r > 0 && r < Infinity)) return;
      // the sizes of .pv-slide in styles.css: 14 px padding and gap, a 30 px tag above each picture
      const w = el.clientWidth - 28, h = el.clientHeight - 28;
      const shown = (cw, ch) => rs.reduce((s, r) => s + Math.min(cw, ch * r) ** 2 / r, 0);
      el.classList.toggle("pv-col", shown(w, (h - 14) / 2 - 30) > shown((w - 14) / 2, h - 30));
    };
    // A shown slide's video loads its first frame (preload none, then metadata) only once the slide has stayed 300 ms, and
    // one at most every second: Chrome asks 3 to 5 ranges of a phone's video, so holding → through 60 videos loads only
    // where it stops, and stepping stays near 40 /media/ requests in 10 s, under the rate limiting rule (100 in 10 s). A
    // video whose load failed (a 429 of that rule) loads again when its slide shows again. stage !== st: the post was
    // closed or drawn again meanwhile.
    let vt = 0, vlast = -1e9;
    const loadShown = () => {
      clearTimeout(vt);
      vt = setTimeout(() => {
        const vs = stage === st ? [...els[st.at].querySelectorAll("video")].filter((v) => v.preload === "none" || v.error) : [];
        if (!vs.length) return;
        vlast = performance.now();
        vs.forEach((v) => { if (v.preload === "none") v.preload = "metadata"; else v.load(); });
      }, Math.max(300, vlast + 1000 - performance.now()));
    };
    st.go = (i, say) => {
      if (i < 0 || i >= els.length) return;
      els.forEach((el, j) => { el.hidden = j !== i; if (j !== i) el.querySelectorAll("video").forEach((v) => v.pause()); });
      for (const el of [els[i - 1], els[i], els[i + 1]]) el?.querySelectorAll('img[loading="lazy"]').forEach((im) => { im.loading = "eager"; });
      st.at = i;
      loadShown();
      if (count) count.textContent = `${i + 1} / ${els.length}`;
      prev?.setAttribute("aria-disabled", String(i === 0));
      next?.setAttribute("aria-disabled", String(i === els.length - 1));
      if (say) live.textContent = `${slides[i].map((it) => it.tag.toLowerCase()).join(" and ")}, ${i + 1} of ${els.length}`;
      st.lay();
    };
    st.step = (d) => st.go(st.at + d, true);
    prev?.addEventListener("click", () => st.step(-1));
    next?.addEventListener("click", () => st.step(1));
    // a finger's swipe across the photos moves too (a tablet), unless it starts on a video or a button
    let sx = NaN, sy = NaN;
    box.addEventListener("pointerdown", (ev) => { sx = sy = NaN; if (ev.pointerType !== "mouse" && !ev.target.closest("video, button")) { sx = ev.clientX; sy = ev.clientY; } });
    box.addEventListener("pointercancel", () => { sx = sy = NaN; });
    box.addEventListener("pointerup", (ev) => {
      const dx = ev.clientX - sx, dy = ev.clientY - sy;
      sx = sy = NaN;
      if (Math.abs(dx) > 50 && Math.abs(dx) > 2 * Math.abs(dy)) st.step(dx < 0 ? 1 : -1);
    });
    // a photo's size is known once it loads, a video's once its metadata does; then the video takes its own shape
    box.addEventListener("load", () => st.lay(), true);
    box.addEventListener("loadedmetadata", (ev) => { ev.target.classList.add("pv-fit"); st.lay(); }, true);
    // The paper's bottom fades while more of it is below its edge (pv-more; styles.css, the wide post): on open, on its own
    // scroll, and whenever it or one of its parts changes size (the window, the fonts, a longer thanks line). The last 18 px
    // of a paper are blank (the id's 14 px padding and the paper's 4), so less than that below needs no fade.
    const paper = overlay.querySelector(".post-paper");
    st.more = () => paper.classList.toggle("pv-more", paper.scrollHeight - paper.clientHeight - paper.scrollTop > 18);
    paper.addEventListener("scroll", st.more, { passive: true });
    if (typeof ResizeObserver === "function") { const ro = new ResizeObserver(() => st.more()); [paper, ...paper.children].forEach((el) => ro.observe(el)); }
    stage = st;
    st.go(0, false);
    st.more();
  }
  // ← and → move the wide post's photos and videos from anywhere in it, except while a video has the focus (its own keys
  // seek then) or a modifier is held (Alt + ← is the browser's back).
  addEventListener("keydown", (ev) => {
    if (!stage || overlay.hidden || (ev.key !== "ArrowLeft" && ev.key !== "ArrowRight") || ev.altKey || ev.ctrlKey || ev.metaKey || ev.shiftKey) return;
    if (ev.target instanceof Element && ev.target.closest("video")) return;
    ev.preventDefault();
    stage.step(ev.key === "ArrowLeft" ? -1 : 1);
  });
  // Tab and Shift+Tab stay in the open post or chooser, at every size: from its last control to its first and back, and
  // from outside it (after a click on a part that takes no focus) to its first or last.
  addEventListener("keydown", (ev) => {
    const box = ev.key === "Tab" && !overlay.hidden && overlay.querySelector('[role="dialog"]');
    if (!box) return;
    const all = [...box.querySelectorAll("a[href], button, video[controls]")].filter((el) => el.getClientRects().length);
    const at = document.activeElement;
    if (all.length && (!box.contains(at) || at === (ev.shiftKey ? all[0] : all[all.length - 1]))) {
      ev.preventDefault();
      (ev.shiftKey ? all[all.length - 1] : all[0]).focus();
    }
  });
  // Crossing WIDE while a post is open (a window resized, a tablet turned) draws it again for the new size, from its first
  // slide; a chooser looks the same at every size and stays. A video's full screen changes the window's size too, so the
  // check waits 300 ms, never runs during full screen, and draws again only when the post on screen no longer fits the
  // size: a video put full screen from a narrow window keeps playing. A resize within WIDE lays the before and after again
  // and checks the paper's fade. Safari before 14 has only the old addListener, and the page must not stop there.
  let redrawAt = 0;
  const redraw = () => {
    clearTimeout(redrawAt);
    redrawAt = setTimeout(() => {
      if (overlay.hidden || !reopen || document.fullscreenElement || document.webkitFullscreenElement) return;
      if (!!overlay.querySelector(".post-frame") !== WIDE.matches) reopen();
    }, 300);
  };
  if (WIDE.addEventListener) WIDE.addEventListener("change", redraw); else WIDE.addListener?.(redraw);
  document.addEventListener("fullscreenchange", redraw);
  document.addEventListener("webkitfullscreenchange", redraw);
  addEventListener("resize", () => { if (stage) { stage.lay(); stage.more(); } });

  // ---------- NEXT UP: mission cards and the mission post ----------
  const funded = (m) => m.status === "funded";
  const mcc = (m) => (/^[A-Z]{2}$/.test(m.country || "") ? m.country : "??");
  const missionUrl = (m) => SHARE_ORIGIN + "/m/" + m.no; // no is a checked integer
  const mStamp = (m, cls) => (m.demo ? `<div class="stamp${cls}">SAMPLE</div>`
    : `<div class="stamp ${funded(m) ? "stamp-ok" : "stamp-open"}${cls}">${funded(m) ? "FUNDED" : "OPEN"}</div>`);
  const mNote = (m) => `<div class="r-note">*** ${funded(m) ? "FUNDED · CLEANUP COMING" : "NOT FUNDED YET"} ***</div>`;
  // linkPartner: the mission post, with the crew's logo and a link to its page. The NEXT UP card (role=button) has
  // the name alone.
  const mRows = (m, linkPartner) => {
    const by = m.partner?.name ? upper(m.partner.name) : "";
    const slug = m.partner?.slug;
    const byHtml = linkPartner && typeof slug === "string" && /^[a-z0-9-]{1,40}$/.test(slug)
      ? `<a href="/p/${slug}">${by}</a>` : by;
    return `
      ${spotRows(spotsM(m), mcc(m)) || `<div><dt>LOC</dt><dd>${upper(m.place_name, "TBA")} · ${mcc(m)}</dd></div>
      <div><dt>DAY</dt><dd>${dateStr(m)}</dd></div>`}
      <div><dt>CREW</dt><dd>${num(m.crew_size)} PPL</dd></div>
      ${by ? `<div><dt>BY</dt><dd>${linkPartner ? crewLogo(m.partner?.logo) : ""}${byHtml}</dd></div>` : ""}
      ${mMoney(m)}`;
  };

  const mcards = $("#mcards");
  missions.forEach((m) => {
    const card = document.createElement("article");
    card.className = "card mcard" + (funded(m) ? " mcard-funded" : "");
    card.id = "m-" + m.no;
    card.tabIndex = 0;
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", "Open mission #" + m.no + ": " + (m.place_name || ""));
    card.innerHTML = `
      ${mStamp(m, "")}
      ${nowVideoOf(m) ? '<div class="vid-tag">▶ VIDEO</div>' : ""}
      <div class="r-head m-head">MISSION #${m.no}<span>SAPU EARTH · NEXT UP</span></div>
      <div class="ba ba-now">${phOr(nowOf(m)[0], "NOW", "n")}</div>
      <dl class="r-rows">${mRows(m, false)}</dl>
      ${m.task ? `<p class="m-task">${escapeHTML(m.task)}</p>` : ""}
      ${mNote(m)}
      <div class="barcode" aria-hidden="true"></div>
      <div class="r-id">${m.demo ? "SAMPLE MISSION" : "SAPU.EARTH/M/" + m.no}</div>`;
    card.addEventListener("click", () => openMission(m));
    card.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); openMission(m); } });
    mcards.appendChild(card);
  });
  $("#nextup").hidden = !missions.length;

  // ---------- the ways on: ALL MISSIONS and THE MISSIONS ----------
  // SEE THE CREWS is not here: it stands next to SEE THE RECEIPTS in index.html (.cues) from the start, also next to the
  // samples and when the data failed to load (Marcus decided on 2026-11-11). /crews always answers honestly, with its
  // own empty state while no crew is listed, and counting the crews first would add a Function request to every visit.
  // The links to /missions still wait for real data, each until its page lists something real: ALL MISSIONS in NEXT UP's
  // head while its cards are real (/api/missions sends only active crews' open and funded missions), THE MISSIONS in the
  // footer once /missions (missionList) lists something, those missions or a cleaned one (a receipt that closed a mission).
  const realMission = missions.some((m) => !m.demo);
  $("#nextupAll").hidden = !realMission;
  $("#footMissions").hidden = !(realMission || events.some((e) => e.fromApi && missionOf(e)));

  function openMission(m) {
    if (overlay.hidden) lastFocus = document.activeElement;
    reopen = () => openMission(m);
    stage = null;
    const now = nowOf(m);
    const shots = (now.length ? now : [null])
      .map((u, i) => phOr(u, now.length > 1 ? `NOW ${i + 1}/${now.length}` : "NOW", "pm")).join("");
    // On a wide screen the paper goes without its photos and stamp and without its own links (acts: SHARE, COPY LINK, ALL
    // MISSIONS; a sample has none), which the stage left of it shows under the photos (wideHtml).
    const wide = WIDE.matches, slides = wide ? missionSlides(m) : null;
    const acts = m.demo ? "" : `<div class="post-actions"><button class="post-link post-share">SHARE</button>${navigator.share ? '<button class="post-link post-copy">COPY LINK</button>' : ""}</div>
        <p class="post-all"><a href="/missions#m-${m.no}">ALL MISSIONS →</a></p>`;
    const paper = `
      <div class="post-paper mpost${funded(m) ? " mpost-funded" : ""}"${wide ? "" : ` role="dialog" aria-modal="true" aria-label="Mission #${m.no}"`}>
        <button class="post-close" aria-label="Close">✕</button>
        ${wide ? "" : mStamp(m, " post-stamp")}
        <div class="r-head m-head">MISSION #${m.no}<span>SAPU EARTH · ${funded(m) ? "FUNDED" : "NEXT UP"}</span></div>
        ${wide ? "" : `<div class="post-media">${shots}${nowVideoOf(m) ? videoBox(nowVideoOf(m), "NOW · VIDEO") : ""}</div>`}
        <dl class="r-rows">${mRows(m, true)}</dl>
        ${m.task ? `<div class="post-task"><span>THE PLAN</span>${escapeHTML(m.task)}</div>` : ""}
        ${satRow(m.lat, m.lng, spotsM(m))}
        ${mNote(m)}
        <div class="barcode" aria-hidden="true"></div>
        ${m.demo ? '<div class="m-link">SAMPLE MISSION · THE FIRST REAL ONES SHOW UP HERE</div>'
          : `<div class="m-link">SAPU.EARTH/M/${m.no}</div>
        ${wide ? "" : acts}`}
        <div class="r-id">MISSION #${m.no} · ${funded(m) ? "FUNDED" : "OPEN"}</div>
      </div>`;
    overlay.innerHTML = wide ? wideHtml("Mission #" + m.no, slides, mStamp(m, " post-stamp"), paper, acts) : paper;
    showOverlay("#m-" + m.no);
    if (slides) startStage(slides);
    // /m/<no> carries the link preview and follows the mission from open to funded to done
    const shareUrl = missionUrl(m);
    const copy = (btn) => (navigator.clipboard?.writeText(shareUrl) || Promise.reject())
      .then(() => (btn.textContent = "COPIED ✓"))
      .catch(() => (btn.textContent = shareUrl));
    overlay.querySelector(".post-share")?.addEventListener("click", (ev) => {
      if (navigator.share) navigator.share({ title: "Sapu Earth mission #" + m.no, url: shareUrl }).catch(() => {});
      else copy(ev.currentTarget);
    });
    overlay.querySelector(".post-copy")?.addEventListener("click", (ev) => copy(ev.currentTarget));
    satButtons();
  }

  // a small chooser for a globe tag that stands for several missions; each line opens its mission
  function openChooser(list) {
    if (overlay.hidden) lastFocus = document.activeElement;
    reopen = stage = null;
    overlay.innerHTML = `
      <div class="post-paper mchooser" role="dialog" aria-modal="true" aria-label="${list.length} missions here">
        <button class="post-close" aria-label="Close">✕</button>
        <div class="r-head m-head">${list.length} MISSIONS<span>SAPU EARTH · PICK ONE</span></div>
        <ul class="mch">${list.map((m) => `
          <li><button type="button" data-no="${m.no}">
            <i class="mpin-tag ${funded(m) ? "mpin-funded" : "mpin-open"}">${glyph(funded(m))}#${m.no}</i>
            <span><b>${upper(m.place_name, "TBA")} · ${mcc(m)}</b>${m.demo ? "SAMPLE · " : ""}${funded(m) ? "FUNDED" : "OPEN"} · DAY ${dateStr(m)}</span>
          </button></li>`).join("")}
        </ul>
      </div>`;
    showOverlay(null);
    overlay.querySelectorAll(".mch button").forEach((b) => b.addEventListener("click", () => {
      const m = list.find((x) => x.no === Number(b.dataset.no));
      if (m) openMission(m);
    }));
  }

  // A finger tap among receipt dots too close together to tell apart: the receipts nearest first. A tap on a cleaned
  // spot's slip that stands for several receipts (cleanPin): newest first. Each row shows its receipt's slip.
  const CHOOSE_MAX = 8;
  function openReceiptChooser(list) {
    if (overlay.hidden) lastFocus = document.activeElement;
    reopen = stage = null;
    const rows = list.slice(0, CHOOSE_MAX), more = list.length - rows.length;
    overlay.innerHTML = `
      <div class="post-paper mchooser" role="dialog" aria-modal="true" aria-label="${list.length} cleanups here">
        <button class="post-close" aria-label="Close">✕</button>
        <div class="r-head m-head">${list.length} CLEANUPS<span>SAPU EARTH · PICK ONE</span></div>
        <ul class="mch">${rows.map((e, i) => `
          <li><button type="button" data-i="${i}">
            ${slipHtml([e])}
            <span><b>${upper(e.location?.name, "TBA")} · ${cc(e)}</b>${dateStr(e)}</span>
          </button></li>`).join("")}
        </ul>
        ${more > 0 ? `<p class="mch-more">${more} MORE HERE: ZOOM IN TO SEE THEM</p>` : ""}
      </div>`;
    showOverlay(null);
    overlay.querySelectorAll(".mch button").forEach((b) => b.addEventListener("click", () => openPost(rows[Number(b.dataset.i)])));
  }

  // deep links: #ev-<id> opens that receipt as a post, #m-<no> that mission
  // (or its receipt, once the mission is done), with no step in the history: the link the page came with, and
  // Forward onto a post's step (popstate). True when a post opened.
  function openLinked() {
    linked = true;
    if (location.hash.startsWith("#ev-")) {
      let want = "";
      try { want = decodeURIComponent(location.hash.slice(4)); } catch { want = ""; }
      const hit = events.find((e) => String(e.id) === want);
      if (hit) openPost(hit);
    } else if (/^#m-\d{1,9}$/.test(location.hash)) {
      const no = Number(location.hash.slice(3));
      const m = missions.find((x) => x.no === no);
      const done = m ? null : events.find((e) => missionOf(e)?.no === no);
      if (m) openMission(m);
      else if (done) openPost(done);
    }
    linked = false; // from here on a post opens by a tap, and takes a step in the history (showOverlay)
    return !overlay.hidden;
  }
  openLinked();

  // ---------- globe ----------
  const el = $("#globe");
  if (typeof Globe !== "function") { console.error("globe.gl failed to load"); return; }

  // The receipts' points, { of: the receipt, location: { name, lat, lng } }: one for each receipt, at its location, or for
  // the receipt of a mission with several spots one at each spot (docs/missions.md, Spots), all opening that receipt.
  const geo = events.flatMap((e) => (spotsE(e).length ? spotsE(e).map((s) => ({ of: e, location: s })) : [{ of: e, location: e.location }]))
    .filter((p) => Number.isFinite(p.location?.lat) && Number.isFinite(p.location?.lng));

  const tipMedia = (e) => {
    const t = (src) => { const u = safeSrc(src); return u ? `<img src="${escapeHTML(u)}">` : '<i class="tip-ph">PHOTO SOON</i>'; };
    return `<div class="tip-ba">${t(e.media?.before?.[0])}${t(e.media?.after?.[0])}</div>`;
  };

  // Mission tags that would touch on screen share one tag ("#1 #2", or "#1 +3" for more than 3), so
  // none hides under another. How near that is depends on the zoom, so tags regroup when the zoom
  // changes, never when the globe spins. Missions come in NEXT UP order. Funded ones lead their tag,
  // and the tag stands on its lead's spot.
  const TAG_ALT = 0.012;                               // tags float this high (globe radius = 1)
  // px: the .mpin-tag box in styles.css is 20 high with a 6 px pointer below it. Tags keep GAP_X
  // apart side by side, and GAP_Y between a pointer's tip and the tag below it.
  const TAG_H = 20, PTR = 6, GAP_X = 6, GAP_Y = 4;
  // Space Mono 700 11px: .612em + .5px a letter, padding, border, and 13 px for the glyph
  const tagW = (label) => 27 + 7.23 * label.length;
  // A small glyph opens every mission tag: a trash bag where the mess still waits (open), a broom where a
  // crew is booked (funded). It takes the tag's text colour. The legend in index.html has the same two.
  // A cleaned spot's slip (cleanPin) opens with a checked box instead: safety green with a paper tick, whatever the
  // colour around it, the same box as the legend's and /missions' (functions/missions/index.js).
  const GLYPH = {
    open: '<svg class="gl" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 7h6c2 1.5 2.6 4.5 1.4 6.6-.5.8-1.2 1.2-2 1.2H5.6c-.8 0-1.5-.4-2-1.2C2.4 11.5 3 8.5 5 7z"/><path d="M6.6 7l.7-2h1.4l.7 2M7.3 5L5.6 3M8.7 5l1.7-2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    funded: '<svg class="gl" viewBox="0 0 16 16" aria-hidden="true"><g transform="rotate(35 8 8)"><rect x="7.1" y=".6" width="1.8" height="8.2" rx=".9"/><path fill-rule="evenodd" d="M5.4 8.2h5.2l1.8 6.2H3.6zM5.2 9.9h5.6v.9H5.2z"/></g></svg>',
    cleaned: '<svg class="gl" viewBox="0 0 16 16" aria-hidden="true"><rect width="16" height="16" rx="3" fill="#007a3d"/><path d="M3.9 8.4l2.9 2.9 5.4-6.1" fill="none" stroke="#fdfaf1" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };
  const glyph = (isFunded) => (isFunded ? GLYPH.funded : GLYPH.open);
  const offKm = (a, b) => {                            // how far east and north b is from a, in km
    const r = Math.PI / 180;
    let dl = b.lng - a.lng;
    if (dl > 180) dl -= 360; else if (dl < -180) dl += 360;
    return [6371 * dl * r * Math.cos(((a.lat + b.lat) / 2) * r), 6371 * (b.lat - a.lat) * r];
  };
  // A tag's missions, each once: the spots of one mission are copies of it (mgeo).
  const baseOf = (m) => m.base || m;
  const missionsOf = (ms) => [...new Set(ms.map(baseOf))];
  const groupLabel = (ms) => { const u = missionsOf(ms); return u.length <= 3 ? u.map((m) => "#" + m.no).join(" ") : `#${u[0].no} +${u.length - 1}`; };
  // Groups for a zoom where one screen px is kmPx km. Any two tags that would touch merge, so a chain
  // of them becomes one tag. Then the merged, wider tags are checked again, until no two touch.
  // A group seen before is the same object, so globe.gl keeps its tag. The same for missions and for cleaned spots
  // (cleanGroups), each kind on its own, so a tag always stands on its lead mission's spot and a slip always hangs from
  // one of its receipts' dots: lead orders a group, width is its tag's width in px, high how far it reaches up or down
  // from its spot with its pointer, key names it and make builds it. Where a tag and a slip of other places meet, the
  // tidy pass below keeps one.
  const groupCache = new Map();
  const groupsAt = (list, kmPx, { lead, width, high, key, make }) => {
    let groups = list.map((m) => [m]);
    for (;;) {
      const up = groups.map((_, i) => i);
      const root = (i) => (up[i] === i ? i : (up[i] = root(up[i])));
      const half = groups.map((ms) => width(ms) / 2);
      let merged = false;
      for (let i = 0; i < groups.length; i++) {
        for (let j = i + 1; j < groups.length; j++) {
          const [dx, dy] = offKm(groups[i][0], groups[j][0]);
          if (Math.abs(dx) >= (half[i] + half[j] + GAP_X) * kmPx || Math.abs(dy) >= (high + GAP_Y) * kmPx) continue;
          const a = root(i), b = root(j);
          if (a !== b) { up[Math.max(a, b)] = Math.min(a, b); merged = true; }
        }
      }
      if (!merged) break;
      const into = new Map();
      groups.forEach((ms, i) => into.set(root(i), (into.get(root(i)) || []).concat(ms)));
      groups = [...into.values()].map((ms) => ms.sort(lead));
    }
    return groups.map((ms) => {
      const k = key(ms);
      if (!groupCache.has(k)) groupCache.set(k, make(k, ms));
      return groupCache.get(k);
    });
  };
  const missionGroups = (list, kmPx) => {
    const order = new Map(list.map((m, i) => [m, i]));
    return groupsAt(list, kmPx, {
      lead: (a, b) => funded(b) - funded(a) || order.get(a) - order.get(b),
      width: (ms) => tagW(groupLabel(ms)), high: TAG_H + PTR,
      key: (ms) => ms.map((m) => m.no + (m.spot ? "." + m.spot : "")).join(" "),
      make: (key, ms) => ({ key, lat: r3(ms[0].lat), lng: r3(ms[0].lng), ms }),
    });
  };
  // A cleaned spot's receipt is a paper slip that hangs below the spot (cleanPin; .cslip in styles.css: 21 px high, the
  // checked box a little taller than the words, under its 6 px pointer, with a torn edge of EDGE px below it), where a
  // mission's tag stands above its spot, so at one place the two never cover each other. Its words: the kilograms its
  // receipts removed, or their sacks where none gave a weight. Space Mono 700 12px: .612em + .5px a letter, padding,
  // border, and 17 px for the checked box and its gap.
  const SLIP_H = 21, EDGE = 4;
  const slipW = (label) => 31 + 7.84 * label.length;
  const kgOf = (e) => (typeof e.result?.kg_estimate === "number" && e.result.kg_estimate > 0 ? e.result.kg_estimate : 0);
  const sacksOf = (e) => (Number.isInteger(e.result?.sacks) && e.result.sacks > 0 ? e.result.sacks : 0);
  const amount = (list) => {
    const kg = list.reduce((s, e) => s + kgOf(e), 0), sacks = list.reduce((s, e) => s + sacksOf(e), 0);
    return kg > 0 ? num(kg) + " KG" : sacks > 0 ? sacks + (sacks === 1 ? " SACK" : " SACKS") : "CLEANED";
  };
  // a group's receipts, each once (the spots of one receipt are points of it), newest first
  const receiptsOf = (rs) => [...new Set(rs.map((p) => p.of))];
  const slipHtml = (list) => `<i class="cslip">${GLYPH.cleaned}${amount(list)}<i class="cslip-edge"></i></i>`;
  // slips that would touch share one, with the kilograms of all of them, hanging from the newest one's dot
  const cleanGroups = (list, kmPx) => groupsAt(list, kmPx, {
    lead: (a, b) => a.i - b.i,
    width: (rs) => slipW(amount(receiptsOf(rs))), high: PTR + SLIP_H + EDGE,
    key: (rs) => "r" + rs.map((p) => p.i).join(" "),
    make: (key, rs) => ({ key, lat: rs[0].lat, lng: rs[0].lng, rs }),
  });

  // The globe also fires its own click for a receipt dot under the pointer, even when the
  // tap landed on a mission tag above it. Remember the tag tap so only the mission opens.
  let pinTapAt = 0;
  const groupOfTag = new WeakMap();
  // A faded tag (opacity 0, no taps): see tidy below. The page is touched only when it changes. A cleaned spot's slip
  // swings on its pin the first time it shows, once, as if just hung there (styles.css, cslip-in), never under reduced
  // motion.
  const setOff = (g, off) => {
    if (off === !!g.off) return;
    g.off = off;
    g.pin.classList.toggle("mpin-off", off);
    if (off) g.pin.setAttribute("aria-hidden", "true"); else g.pin.removeAttribute("aria-hidden");
    if (!off && g.rs && !g.hung) { g.hung = true; if (!reduceMotion) g.pin.firstChild.classList.add("cslip-in"); }
  };
  // globe.gl asks for a tag each time a group comes on the globe. It starts faded, and the tidy pass
  // shows it once it has room, so a tag never lands on another one.
  function missionPin(g) {
    // A group that comes back after a zoom gets its old tag. The renderer set display: none on it if it
    // left behind the planet: cleared, tidy waits until it is drawn again instead of fading it for good.
    if (g.pin) { g.pin.style.display = ""; setOff(g, true); return g.pin; }
    const ms = g.ms, m = ms[0], mis = missionsOf(ms);
    const pin = document.createElement("div");
    pin.className = "mpin";
    // One mission: its place and day, or those of each of its spots on the tag. Several: each mission once.
    const tip = mis.length === 1
      ? `<b>${m.demo ? "SAMPLE " : ""}MISSION #${m.no} · ${funded(m) ? "FUNDED" : "OPEN"}</b>` +
        ms.map((x) => `<br>${upper(x.place_name, "TBA")} · ${dateStr(x)}`).join("") + "<span>TAP FOR THE MISSION</span>"
      : `<b>${mis.length} MISSIONS HERE</b>` +
        mis.slice(0, 4).map((x) => `<br>#${x.no} · ${funded(x) ? "FUNDED" : "OPEN"} · ${upper(x.place_name, "TBA")}`).join("") +
        (mis.length > 4 ? "<br>..." : "") + "<span>TAP TO CHOOSE</span>";
    pin.innerHTML = `<div class="mpin-tag ${ms.some(funded) ? "mpin-funded" : "mpin-open"}">${glyph(ms.some(funded))}${groupLabel(ms)}</div>` +
      `<div class="tip mtip">${tip}</div>`;
    const tag = pin.firstChild;
    groupOfTag.set(tag, g);
    tag.addEventListener("pointerup", () => (pinTapAt = performance.now()));
    // A mouse that comes onto the tag sweeps it once (styles.css, mpin-sweep, where the pointer is the broom). A class
    // runs the sweep, not :hover, so it ends on its own even when the tag moves from under the pointer for a moment.
    tag.addEventListener("pointerenter", (ev) => { if (ev.pointerType === "mouse") tag.classList.add("mpin-sweep"); });
    tag.addEventListener("animationend", () => tag.classList.remove("mpin-sweep"));
    tag.addEventListener("click", (ev) => {
      if (pressOn === false) return;                   // a tap that starts on a box beside it is the box's (pressOn)
      pinTapAt = performance.now();
      // The tap areas of two tags side by side can overlap. Every shown tag under the finger
      // counts, so a tap between them lists both. A tag faded out near the rim (tidy) does not, nor a cleaned spot's slip.
      const under = ev.clientX || ev.clientY
        ? document.elementsFromPoint(ev.clientX, ev.clientY).map((x) => groupOfTag.get(x)).filter((y) => y?.ms && !y.off) : [];
      const gs = new Set([g, ...under]);
      const list = missions.filter((x) => [...gs].some((y) => y.ms.some((z) => baseOf(z) === x)));
      if (list.length === 1) openMission(list[0]); else openChooser(list);
    });
    g.pin = pin;
    setOff(g, true);
    return pin;
  }
  // The same for a cleaned spot: its receipt, a slip with a checked box and the kilograms (cleanGroups), hanging from its
  // dot. --hang is how far the dot reaches below the spot on screen (satDraw), so the slip's pointer starts just under it.
  // One receipt: its place, its day and its photos, and a tap opens it; several: each once, and a tap lists them.
  function cleanPin(g) {
    if (g.pin) { g.pin.style.display = ""; setOff(g, true); return g.pin; }
    const list = receiptsOf(g.rs), e = list[0], mis = missionOf(e);
    const pin = document.createElement("div");
    pin.className = "mpin cpin";
    pin.style.setProperty("--hang", hangPx + "px");
    const tip = list.length === 1
      ? `<b>${e.demo ? "SAMPLE " : ""}CLEANED${mis ? " · MISSION #" + mis.no : ""}</b><br>${upper(e.location?.name, "TBA")} · ${dateStr(e)}` +
        tipMedia(e) + "<span>TAP FOR THE RECEIPT</span>"
      : `<b>${list.length} CLEANUPS HERE</b>` +
        list.slice(0, 4).map((x) => `<br>${upper(x.location?.name, "TBA")} · ${amount([x])}`).join("") +
        (list.length > 4 ? "<br>..." : "") + "<span>TAP TO CHOOSE</span>";
    pin.innerHTML = slipHtml(list) + `<div class="tip mtip ctip">${tip}</div>`;
    const tag = pin.firstChild;
    groupOfTag.set(tag, g);
    tag.addEventListener("pointerup", () => (pinTapAt = performance.now()));
    // a mouse that comes onto it swings it once more (styles.css, cslip-swing)
    tag.addEventListener("pointerenter", (ev) => { if (ev.pointerType === "mouse") tag.classList.add("cslip-swing"); });
    tag.addEventListener("animationend", () => tag.classList.remove("cslip-in", "cslip-swing"));
    tag.addEventListener("click", (ev) => {
      if (pressOn === false) return;                   // a tap that starts on a box beside it is the box's (pressOn)
      pinTapAt = performance.now();
      const under = ev.clientX || ev.clientY
        ? document.elementsFromPoint(ev.clientX, ev.clientY).map((x) => groupOfTag.get(x)).filter((y) => y?.rs && !y.off) : [];
      const gs = [g, ...under];
      const all = events.filter((x) => gs.some((y) => y.rs.some((p) => p.of === x)));
      if (all.length === 1) openPost(all[0]); else openReceiptChooser(all);
    });
    g.pin = pin;
    setOff(g, true);
    return pin;
  }

  // ----- satellite math (tests/e2e.sh runs this block in node) -----
  // Zoomed in far, the drawn globe turns into satellite pictures (see the satellite map below): EOxCloudless,
  // Sentinel-2 at about 10 m a pixel, by EOX IT Services GmbH in Vienna, loaded straight from EOX.
  const SAT_YEAR = 2025;
  const SAT_URL = (z, x, y) =>
    `https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-${SAT_YEAR}_3857/default/GoogleMapsCompatible/${z}/${y}/${x}.jpg`;
  const SAT_MAXZ = 14;                                 // EOX's sharpest tiles: about 10 m a pixel, what Sentinel-2 sees
  // The deepest zoom shows SAT_MPX metres a screen px, so a house is a pixel or two, never a shape. Public points
  // are rounded to 3 decimals, a box of about 110 by 110 m, and every spot in that box is within AREA_M of the
  // rounded point: the map shows a spot as that area, never as a pin.
  const SAT_MPX = 6, AREA_M = 80;
  const MAP_FROM = 0.6, MAP_FULL = 0.2;                // altitudes: the blend starts at 0.6, while the globe still looks whole, the map is whole at 0.2
  const r3 = (v) => Math.round(v * 1000) / 1000;
  // how much of the picture is the map at altitude a: 0 down to MAP_FROM, 1 from MAP_FULL on, eased between
  const mapShare = (a) => {
    const t = Math.min(1, Math.max(0, Math.log(MAP_FROM / a) / Math.log(MAP_FROM / MAP_FULL)));
    return t * t * (3 - 2 * t);
  };
  // Web Mercator tiles of 256 px: where a point is, in tiles of level z, and the latitude of row y's top edge
  const tileX = (lng, z) => ((lng + 180) / 360) * 2 ** z;
  const tileY = (lat, z) => {
    const s = Math.sin((Math.max(-85, Math.min(85, lat)) * Math.PI) / 180);
    return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * 2 ** z;
  };
  const rowLat = (y, z) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / 2 ** z))) * 180) / Math.PI;
  // the level for mpp metres a screen px at latitude lat: its tiles show at 0.7 to 1.4 times their size
  const tileZ = (mpp, lat) =>
    Math.max(2, Math.min(SAT_MAXZ, Math.round(Math.log2((156543.03 * Math.cos((lat * Math.PI) / 180)) / mpp))));
  // a receipt's mark on the map, radius in px: its dot, and never smaller than the area around its point
  const markPx = (mpp, dotPx) => Math.max(dotPx, AREA_M / mpp);
  // A dot of radius rad (degrees of the planet) with its top at height top, seen from altitude a in the middle of
  // the screen (f px for 1 unit seen from 1 unit away): its radius on screen in px. From at or below its top the
  // camera would be inside it, bigger than any screen; for a dot at its full height (0.006) that is everywhere
  // closer than about 40 m a px.
  const seenPx = (f, rad, a, top) => (a > top ? (f * rad * Math.PI) / 180 / (a - top) : Infinity);
  // Zooming toward the pointer: the view's centre for altitude next, so the spot P (a unit vector) stays where it
  // is on screen. The camera looks at the planet's centre from 1 + altitude radii away, so P shows at
  // tan = sin(th) / (1 + altitude - cos(th)) from the middle, th its angle from the centre C; this finds th2 with
  // the same at next and moves C along the great circle through P to th2 from it. Null: keep the centre.
  const toUnit = (lat, lng) => {
    const r = Math.PI / 180;
    return [Math.cos(lat * r) * Math.cos(lng * r), Math.cos(lat * r) * Math.sin(lng * r), Math.sin(lat * r)];
  };
  const keepSpot = (pov, next, P) => {
    const C = toUnit(pov.lat, pov.lng);
    const th = Math.acos(Math.min(1, Math.max(-1, C[0] * P[0] + C[1] * P[1] + C[2] * P[2])));
    if (th < 1e-9 || th > 1.2) return null;
    const q = Math.sin(th) / (1 + pov.altitude - Math.cos(th));
    let t2 = (th * next) / pov.altitude;
    for (let i = 0; i < 4; i++) t2 -= (Math.sin(t2) - q * (1 + next - Math.cos(t2))) / (Math.cos(t2) - q * Math.sin(t2));
    if (!(t2 > 0 && t2 < 1.5)) return null;
    const s = Math.sin(th), k0 = Math.sin(th - t2) / s, k1 = Math.sin(t2) / s, r = Math.PI / 180;
    const x = k0 * P[0] + k1 * C[0], y = k0 * P[1] + k1 * C[1], z = k0 * P[2] + k1 * C[2];
    return { lat: Math.atan2(z, Math.hypot(x, y)) / r, lng: Math.atan2(y, x) / r };
  };
  // A finger holds the spot it touched (one finger on the globe, below): the view's centre moves so that the spot
  // stays under the finger. The camera looks down on the centre C from 1 + altitude radii away, north up and east
  // to the right, so a spot at arc b from C on bearing g (clockwise from north) shows at bearing g from the middle
  // of the screen, clockwise from up. A ray at angle q from the middle meets the planet at b = asin(k sin q) - q,
  // k = 1 + altitude, the other way round from keepSpot's tan; a ray that passes the planet counts as its rim.
  // (dx, dy) are px from the middle, y down; f is the px for a tan of 1 (half the screen's height over tan(fov / 2)).
  const wrapLng = (lng) => ((((lng + 180) % 360) + 360) % 360) - 180;
  const rayArc = (k, q) => (k * Math.sin(q) >= 1 ? Math.acos(1 / k) : Math.asin(k * Math.sin(q)) - q);
  // the spot under (dx, dy), seen from pov
  const spotAt = (pov, dx, dy, f) => {
    const r = Math.PI / 180, la = pov.lat * r, g = Math.atan2(dx, -dy);
    const b = rayArc(1 + pov.altitude, Math.atan(Math.hypot(dx, dy) / f));
    const lat = Math.asin(Math.min(1, Math.max(-1, Math.sin(la) * Math.cos(b) + Math.cos(la) * Math.sin(b) * Math.cos(g))));
    const lng = pov.lng * r + Math.atan2(Math.sin(g) * Math.sin(b) * Math.cos(la), Math.cos(b) - Math.sin(la) * Math.sin(lat));
    return { lat: lat / r, lng: wrapLng(lng / r) };
  };
  // The centre, at altitude alt, that shows spot P (lat, lng) at (dx, dy). Its latitude solves
  // sin(P.lat) = cos(b) sin(lat) + sin(b) cos(g) cos(lat); of the two answers, the one nearest nearLat. North
  // stays up, so the centre stays within HOLD_LAT of the equator, and a spot that cannot reach the finger with
  // north up (past a pole) comes as near as it can.
  const HOLD_LAT = 85;
  const holdSpot = (P, dx, dy, f, alt, nearLat) => {
    const r = Math.PI / 180, g = Math.atan2(dx, -dy), near = nearLat * r;
    const b = rayArc(1 + alt, Math.atan(Math.hypot(dx, dy) / f));
    const A = Math.cos(b), B = Math.sin(b) * Math.cos(g), d = Math.atan2(B, A);
    const s = Math.asin(Math.min(1, Math.max(-1, Math.sin(P.lat * r) / Math.hypot(A, B))));
    const turn = (x) => Math.atan2(Math.sin(x), Math.cos(x));
    const fits = [turn(s - d), turn(Math.PI - s - d)].filter((x) => Math.abs(x) <= Math.PI / 2);
    let la = fits.length ? fits.reduce((p, q) => (Math.abs(q - near) < Math.abs(p - near) ? q : p)) : near;
    la = Math.max(-HOLD_LAT * r, Math.min(HOLD_LAT * r, la));
    const U = Math.cos(b) * Math.cos(la) - Math.sin(b) * Math.cos(g) * Math.sin(la), V = Math.sin(b) * Math.sin(g);
    return { lat: la / r, lng: wrapLng(P.lng - Math.atan2(V, U) / r) };
  };
  // ----- end of the satellite math -----

  const DOT_ALT = 0.006;                               // receipt dots stand this high (flat, like a sticker)
  // A cleaned spot is a safety green dot on a white rim, the colours of a "safe condition" sign, so it
  // reads as done next to the yellow (open) and ink (funded) mission tags, and the rim keeps it apart
  // from the green land. Its receipt hangs from it as a slip with the kilograms (cleanPin): the dot is the pin it
  // hangs on, and still takes taps of its own. The rim is a second point under each dot, wider and a little lower. Dot and rim
  // carry their receipt in `of`, so a hover or a click on either acts on that receipt. They are points of
  // their own, not the receipts: globe.gl keeps each layer's 3D object on the data (__threeObj), and the
  // pulse rings use the receipts, so a shared object would send the dots' updates to the rings. Both stand
  // above the land (0.001) and the pulse rings (0.0015). The pulse is a darker green that fades slowly, so
  // its thin ring stays visible on the pale ocean, and it stays off for visitors who ask for less motion.
  const CLEAN = "#007a3d", PULSE_RGB = "0, 77, 38", RIM = "#ffffff", DOT_R = 0.72, RIM_R = 0.98;
  // Around the white rim goes a dark ring, a third point under the two, wider and lower again: the outline
  // everything of Sapu's has. It also keeps the white rim apart from
  // the pale ocean. The ring stands only a little lower than the rim (dotAlt), so that seen from the side, away
  // from the middle of the screen, it stays an even ring and does not slide out into a crescent.
  const INK = "#1c1813", INK_R = 1.16;
  const receiptOf = (d) => d.of;
  let pointTapAt = 0;                                  // globe.gl opened a receipt for a dot hit right on
  let pressType = "", pressOn = null;                  // the last press: mouse, touch or pen, and whether on the globe
  // A dot grows with the zoom only up to its size on the satellite map, then keeps that size on screen
  // (dotSize). As the map comes in, dots come down to the ground (dotLow), and so do the mission tags (tagAlt),
  // so they stay on their spot over the map. hangPx: how far below its spot a dot, or its mark on the map, reaches on
  // screen, where a cleaned spot's slip hangs from it (cleanPin, satDraw).
  let dotSize = 1, dotLow = 1, tagAlt = TAG_ALT, hangPx = 7;
  const dotAlt = (d) => (d.ink ? DOT_ALT - 0.0022 : d.rim ? DOT_ALT - 0.0015 : DOT_ALT) * dotLow;
  const dotRadius = (d) => (d.ink ? INK_R : d.rim ? RIM_R : DOT_R) * dotSize;
  const globe = Globe({ animateIn: !reduceMotion })(el)
    .backgroundColor("rgba(0,0,0,0)")
    .showAtmosphere(false)                             // no glow: the planet is a flat drawing with an outline (below)
    .pointsData([...geo.map((p) => ({ ink: true, ...p })), ...geo.map((p) => ({ rim: true, ...p })), ...geo.map((p) => ({ ...p }))])
    .pointLat((d) => r3(d.location.lat))               // where the public point is, about 100 m (/api/events rounds the same way)
    .pointLng((d) => r3(d.location.lng))
    .pointColor((d) => (d.ink ? INK : d.rim ? RIM : CLEAN))
    .pointAltitude(dotAlt)
    .pointRadius(dotRadius)
    .pointResolution(32)
    .pointLabel((d) => {
      const e = receiptOf(d);
      return `<div class="tip"><b>${upper(d.location.name, "")}</b> · ${num(e.result?.kg_estimate)} KG${tipMedia(e)}<span>TAP FOR THE RECEIPT</span></div>`;
    })
    .ringsData(reduceMotion ? [] : geo)
    .ringLat((d) => d.location.lat)
    .ringLng((d) => d.location.lng)
    .ringColor(() => (t) => `rgba(${PULSE_RGB}, ${Math.sqrt(1 - t)})`)
    .ringMaxRadius(() => 3 * dotSize)                // the pulse shrinks with the dot (satDraw), at the same pace
    .ringPropagationSpeed(() => 2 * dotSize)
    .ringRepeatPeriod(1100)
    .onPointClick((d, ev) => {
      // A finger covers several dots where they crowd, so its tap goes through receiptsNear below. A click on the tap
      // hint's words is not one on a dot hidden under it (onStrip).
      if (pressType !== "mouse" || onStrip(ev)) return;
      pointTapAt = performance.now(); if (pointTapAt - pinTapAt > 400) openPost(receiptOf(d));
    });

  // missions are "#12" tags (yellow = open, ink = funded), cleanups are green dots on a white rim with their
  // receipt hanging below as a slip with the kilograms. A handful of DOM tags; globe.gl hides the ones behind the planet.
  // The missions' points: each mission at its place, or a mission with several spots at each spot (docs/missions.md,
  // Spots), as a copy of it with that spot's place, day and point, base the mission itself (baseOf). Spots a few km apart
  // share the mission's tag, which then reads #2 once; zoomed in, each spot has its own.
  const mgeo = missions.flatMap((m) => (spotsM(m).length
    ? spotsM(m).map((s) => ({ ...m, place_name: s.name, date: s.date, lat: s.lat, lng: s.lng, spot: s.no, base: m })) : [m]))
    .filter((m) => Number.isFinite(m.lat) && Number.isFinite(m.lng));
  // The cleaned spots' points for their slips, one at each dot (geo), in the receipts' order, newest first: slips that
  // would touch share one with the kilograms of all of them, hanging from the newest one's dot (cleanGroups).
  const cgeo = geo.map((p, i) => ({ of: p.of, lat: r3(p.location.lat), lng: r3(p.location.lng), i }));
  const tagged = mgeo.length + cgeo.length > 0;
  // km per screen px where the camera looks. The globe's radius is 100 units (6371 km), the camera
  // is 100 * (1 + altitude) from its centre, and the tags ride on a sphere 1 + tagAlt times as big.
  const kmPerPx = (alt) => (2 * Math.tan((globe.camera().fov * Math.PI) / 360) * 6371 * (alt - tagAlt)) /
    ((1 + tagAlt) * (globe.height() || 1));
  // Regroup only when that scale crosses a 15% step. Spinning and dragging keep the altitude, so
  // they never regroup. Each step groups for its most zoomed out end, so tags cannot touch inside
  // it, and a step is left only 10% past its edge, so a shaky pinch does not flip tags back and forth.
  const STEP = Math.log(1.15);
  let level = NaN, shown = "";
  const relayout = (alt) => {
    if (!tagged) return;
    try { // this runs inside globe.gl's frame: a throw here would stop the globe for good
      const x = Math.log(kmPerPx(alt)) / STEP;
      if (x > level - 0.1 && x < level + 1.1) return;
      level = Math.floor(x);
      const kp = Math.exp((level + 1) * STEP);
      const groups = [...missionGroups(mgeo, kp), ...cleanGroups(cgeo, kp)];
      const keys = groups.map((g) => g.key).join("|");
      if (keys !== shown) { shown = keys; globe.htmlElementsData(groups); tidySoon(); }
    } catch (e) {
      console.error("mission tags", e);
    }
  };

  // Grouping keeps tags apart where the globe faces the camera. Near the rim the globe squeezes
  // distances, so two tags can still touch while it spins. This pass reads where the tags really
  // are, at most every 100 ms, and walks them in order: a cleaned spot's slip first (the proof, newest first), then a
  // tag with a funded mission, then the NEXT UP order of its lead. A slip hangs below its spot and a mission's tag stands
  // above its own, so the two meet only where the slip's spot is a tag's height or so above the tag's. A slip's place is
  // taken from its pin, so its swing does not move it here. A tag that touches one already kept, or would by the next pass the
  // way the two are moving, fades out. It comes back as soon as it has room. A tag under the pointer
  // or with focus always stays. Tags that globe.gl hides behind the planet do not count; they fade
  // too, so one that comes back over the rim only shows once it has room. The tap hint's strip of paper counts as a
  // tag already kept: it hides a tag that passes under it and takes no taps (a drag that starts on it spins the globe),
  // so a tag that meets it fades, and a click on the hint's words never opens a mission no one can see there. Even a tag
  // under the pointer or with focus fades once its middle is behind the strip: a finger leaves :hover on the tag it
  // tapped (still there after Back closed its post), and a drag can leave one there under a mouse. Places are taken on
  // the page, not on the screen: a scroll moves the tags and the strip alike, so it is no move toward the strip (on the
  // screen, a tag far above the strip faded while the page scrolled back up to the globe, 2026-11-17).
  const nextUpAt = new Map(missions.map((m, i) => [m, i]));
  const hintStrip = $("#tapHint");
  // nor a tap on a receipt's dot hidden under it (onPointClick, the finger's tap below), and its preview stays away
  const onStrip = (ev) => {
    const b = hintStrip && !hintStrip.closest(".map-on") ? hintStrip.getBoundingClientRect() : null;
    return !!b?.width && ev.clientX >= b.left && ev.clientX < b.right && ev.clientY >= b.top && ev.clientY < b.bottom;
  };
  const AHEAD = 120;                                   // ms, about the time to the next pass
  let tidyReq = 0, tidyAt = -1e9, onScreen = true;
  const tidySoon = () => { if (tagged && !tidyReq) tidyReq = requestAnimationFrame(tidyFrame); };
  const tidyFrame = (now) => {
    tidyReq = 0;
    if (now - tidyAt < 100) { tidySoon(); return; }
    tidyAt = now;
    try { tidy(now); } catch (e) {
      console.error("mission tags", e);
      for (const g of globe.htmlElementsData()) if (g.pin) setOff(g, false); // never leave the missions hidden
    }
  };
  function tidy(now) {
    const live = [];
    let again = false;                                 // look again soon: a tag not drawn yet, or hidden on a guess
    for (const g of globe.htmlElementsData()) {
      const pin = g.pin;
      if (pin?.style.display === "none") { setOff(g, true); continue; } // behind the planet
      if (!pin?.isConnected) { again = true; continue; }   // not drawn yet
      const tag = pin.firstChild, r = (g.rs ? pin : tag).getBoundingClientRect();
      // the centre from where it is drawn, on the page, the size without the hover scale or the tilt; a slip's from its
      // pin (the spot): its pointer starts hangPx below it, its edge ends EDGE px below the slip
      const h = tag.offsetHeight + PTR + (g.rs ? EDGE : 0);
      const x = r.left + scrollX + r.width / 2, y = r.top + scrollY + (g.rs ? hangPx + 1 + h / 2 : r.height / 2);
      const dt = g.seen && now - g.seen.t < 300 ? now - g.seen.t : 0;
      live.push({ g, x, y, w: tag.offsetWidth, h, held: pin.matches(":hover, :focus-within"),
        nx: dt ? x + ((x - g.seen.x) * AHEAD) / dt : x, ny: dt ? y + ((y - g.seen.y) * AHEAD) / dt : y });
      g.seen = { x, y, t: now };
    }
    const lead = (t) => t.g.ms[0];
    const rank = (t) => (t.g.rs ? 0 : funded(lead(t)) ? 1 : 2);
    live.sort((a, b) => b.held - a.held || rank(a) - rank(b) ||
      (a.g.rs ? a.g.rs[0].i - b.g.rs[0].i : nextUpAt.get(baseOf(lead(a))) - nextUpAt.get(baseOf(lead(b)))));
    const touch = (k, t, dx, dy) => Math.abs(dx) < (k.w + t.w) / 2 + GAP_X && Math.abs(dy) < (k.h + t.h) / 2 + GAP_Y;
    const kept = [];
    const hb = hintStrip && !hintStrip.closest(".map-on") ? hintStrip.getBoundingClientRect() : null; // none while it fades for the map
    const strip = hb?.width ? { x: hb.left + scrollX + hb.width / 2, y: hb.top + scrollY + hb.height / 2, w: hb.width, h: hb.height } : null;
    if (strip) kept.push({ ...strip, nx: strip.x, ny: strip.y });
    for (const t of live) {
      const behind = !!strip && t.held && Math.abs(strip.x - t.x) < strip.w / 2 && Math.abs(strip.y - t.y) < strip.h / 2;
      const hit = behind || (!t.held && kept.some((k) => touch(k, t, k.x - t.x, k.y - t.y)));
      const soon = !t.held && !hit && kept.some((k) => touch(k, t, k.nx - t.nx, k.ny - t.ny));
      if (soon) again = true;                          // once they stop moving, the guess goes away
      if (!hit && !soon) kept.push(t);
      setOff(t.g, hit || soon);
    }
    if (again && onScreen) tidySoon();
  }

  if (tagged) {
    globe
      .htmlLat((g) => g.lat)
      .htmlLng((g) => g.lng)
      .htmlAltitude(TAG_ALT)
      .htmlTransitionDuration(0)
      .htmlElement((g) => (g.rs ? cleanPin(g) : missionPin(g)));
  }
  // globe.gl calls this on every camera move, inside its frame (satFrame is the satellite map, below)
  globe.onZoom((pov) => { relayout(pov.altitude); tidySoon(); satFrame(pov); });
  // The legend says what the markers on the globe are, the kinds that are there and no others
  $("#lgCleaned").hidden = !geo.length;
  $("#lgFunded").hidden = !mgeo.some(funded);
  $("#lgOpen").hidden = !mgeo.some((m) => !funded(m));
  $("#legend").hidden = !geo.length && !mgeo.length;

  // Sapu's planet, drawn the way Sapu is: a flat pale blue ocean, solid green land and a dark outline. Nothing is
  // shaded: the only light is an even white one from everywhere (globe.gl's own lights are a dimmer one of that
  // kind plus a lamp from one side, which turned the pale blue grey), so every colour shows exactly as written.
  const OCEAN = "#bde6f2", LAND = "#2bb673";
  globe.lights([new (globe.lights()[0].constructor)(0xffffff, Math.PI)]);
  globe.globeMaterial().color.set(OCEAN);              // the bare ball, until its picture is there
  // globe.gl takes the ball's picture by address only, so one pixel of ocean stands in from the start. Once the
  // land is painted, its canvas takes that picture's place (paintLand), with no detour through an image file.
  const px = document.createElement("canvas");
  px.width = px.height = 1;
  px.getContext("2d").fillStyle = OCEAN; px.getContext("2d").fillRect(0, 0, 1, 1);
  globe.globeImageUrl(px.toDataURL("image/png"));
  // The outline is a ball a little bigger than the planet, of which only the inside faces are drawn: it shows as
  // a ring around the planet and never over it. globe.gl builds the planet's ball a moment after this runs.
  const OUTLINE = 1.022;                               // the outline ball's radius, in planet radii
  let outline = null, hid3d = false;                   // hid3d: the satellite map is whole, the drawn globe has stopped drawing
  (function addOutline() {
    let ball = null;
    globe.scene().traverse((o) => { if (!ball && o.__globeObjType === "globe") ball = o; });
    if (!ball) { requestAnimationFrame(addOutline); return; }
    const ink = new ball.material.constructor({ color: INK, side: 1 });   // 1 is three.js BackSide
    outline = new ball.constructor(new ball.geometry.constructor(globe.getGlobeRadius() * OUTLINE, 96, 48), ink);
    outline.visible = !hid3d;
    ball.parent.add(outline);
  })();
  // The land is painted, not built: one flat picture of the ocean with every country in the same green (so no
  // border shows) wraps the ball. A picture costs nothing more to draw, where the hexagon dots it replaces were
  // tens of thousands of triangles in 177 draw calls, and land built as solid shapes was 590 calls. The picture
  // is as wide as the graphics card takes, up to 4096 px: sharp from far out down to where the satellite map
  // starts to come in. Each country is also stroked a hair wide, which closes the seams between neighbours and
  // keeps small islands from vanishing.
  // ---------- the land after Back (tests/e2e.sh runs this block in node) ----------
  // WebKit cuts the land's file as it cuts the photos (photos after Back, above) when the visitor leaves before it has
  // come (488 KB, seconds on a slow connection), and the globe came back from Back as a bare blue ball (seen on live
  // sapu.earth on 2026-11-17, leaving half a second after the page came). So the file is asked for again once the page
  // is back: at the next Back when it failed before it (WebKit fails it as the visitor leaves, before pagehide), at
  // once when it fails after a Back (Chrome reports a cut there right after the pageshow), and never during the
  // pageshow itself.
  function landAfterBack(load) {
    let backs = 0, lost = false;
    const go = () => {
      const b = backs;
      load().catch((e) => {
        console.error("countries failed to load", e);
        if (backs !== b) setTimeout(go); else lost = true;
      });
    };
    addEventListener("pageshow", (ev) => {
      if (!ev.persisted) return;
      backs++;
      if (lost) { lost = false; setTimeout(go); }
    });
    go();
  }
  // ---------- end of the land after Back ----------
  landAfterBack(() => fetch("site/vendor/countries.geojson")
    .then((r) => r.json())
    .then((world) => {
      const W = Math.min(4096, globe.renderer().capabilities.maxTextureSize || 2048), H = W / 2;
      const cv = document.createElement("canvas");
      cv.width = W; cv.height = H;
      const c = cv.getContext("2d");
      c.fillStyle = OCEAN; c.fillRect(0, 0, W, H);
      c.fillStyle = c.strokeStyle = LAND; c.lineWidth = W / 2048; c.lineJoin = "round";
      for (const f of world.features) {
        const g = f.geometry || {};
        const polys = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
        c.beginPath();
        for (const poly of polys) {
          for (const ring of poly) {
            ring.forEach(([lng, lat], i) => {
              const x = ((lng + 180) / 360) * W, y = ((90 - lat) / 180) * H;
              if (i) c.lineTo(x, y); else c.moveTo(x, y);
            });
            c.closePath();
          }
        }
        c.fill("evenodd"); c.stroke();
      }
      let tries = 0;
      (function paintLand() {
        const map = globe.globeMaterial().map;           // the one pixel, once globe.gl has loaded it
        if (!map) { if (++tries < 600) requestAnimationFrame(paintLand); return; }
        map.dispose();                                   // a picture of another size needs fresh room on the graphics card
        map.image = cv;
        // seen at a slant near the planet's edge the picture would blur: let the graphics card look closer there
        map.anisotropy = globe.renderer().capabilities.getMaxAnisotropy();
        map.needsUpdate = true;
      })();
    }));

  // ---------- where the globe starts ----------
  // It lands on the busiest spot: the middle of the largest group of markers (receipt dots and mission
  // tags) within LAND_KM of one of them. A first visit then shows the cleanups and missions at once,
  // wherever they are. With nothing to show it starts over Southeast Asia.
  const LAND_KM = 1500;
  const busiest = () => {
    const r = Math.PI / 180, near = Math.cos(LAND_KM / 6371);
    const vs = [...geo.map((p) => p.location), ...mgeo].map((p) =>
      [Math.cos(p.lat * r) * Math.cos(p.lng * r), Math.cos(p.lat * r) * Math.sin(p.lng * r), Math.sin(p.lat * r)]);
    let best = null;
    for (const v of vs) {
      const group = vs.filter((w) => v[0] * w[0] + v[1] * w[1] + v[2] * w[2] >= near);
      if (!best || group.length > best.length) best = group;
    }
    if (!best) return { lat: -4, lng: 115 };
    const s = best.reduce((a, w) => [a[0] + w[0], a[1] + w[1], a[2] + w[2]], [0, 0, 0]);
    const len = Math.hypot(s[0], s[1], s[2]);
    return { lat: Math.asin(s[2] / len) / r, lng: Math.atan2(s[1], s[0]) / r };
  };
  const home = busiest();
  globe.pointOfView({ ...home, altitude: innerWidth < 600 ? 2.6 : 2.1 }, 0);
  const controls = globe.controls();
  controls.autoRotate = false;
  controls.minDistance = 130;   // how deep a pinch may zoom: setMin (satellite map, below) takes it down to SAT_MPX
  controls.maxDistance = 500;
  controls.enableZoom = true;   // a mouse's middle button; fingers pinch with the code below (one finger on the globe)
  // globe.gl sets the pinch speed on every camera move, for a camera far out (0.1 * (altitude + 1)). A pinch scales
  // the distance to the planet's centre by the fingers' spread to the power pinchSpeed, so a few km up the same
  // speed would jump to the deepest zoom at once. Below MAP_FROM a pinch zooms the altitude by the fingers' spread
  // to the power 0.55, as globe.gl's speed does on the globe, and to the power 1 once the map is whole, as on a
  // map. The listener comes after globe.gl's, so it wins.
  const pinchSpeed = (a) => (a < MAP_FROM ? Math.min(0.1 * (a + 1), ((0.55 + 0.45 * mapShare(a)) * a) / (1 + a)) : 0.1 * (a + 1));
  controls.addEventListener("change", () => { controls.zoomSpeed = pinchSpeed(globe.pointOfView().altitude); });
  // Until the visitor touches it, the globe sways slowly around that spot, SWAY degrees either way and
  // back in SWAY_S seconds, so the markers stay in view (a steady spin carried them behind the planet
  // within half a minute). Less on a phone, where the zoom buttons sit at the globe's side. A touch, a
  // zoom or any other camera move stops it for good. Scrolled away it takes no frames and holds still.
  const SWAY = innerWidth < 600 ? 12 : 20, SWAY_S = 40;
  let swaying = !reduceMotion, swayAt = null, swayT = 0, swayLast = 0, swayReq = 0;
  const stopSway = () => { swaying = false; };
  const turnedBy = (a, b) => Math.abs(((a - b + 540) % 360) - 180);
  const swayFrame = (now) => {
    swayReq = 0;
    if (!swaying || !onScreen) return;        // the IntersectionObserver below starts it again
    const pov = globe.pointOfView();
    if (swayAt && (turnedBy(pov.lng, swayAt.lng) > 0.01 || Math.abs(pov.lat - swayAt.lat) > 0.01)) return stopSway();
    swayT += Math.min(now - swayLast, 100);   // no jump after a hidden tab
    swayLast = now;
    swayAt = { lat: home.lat, lng: home.lng + SWAY * Math.sin((2 * Math.PI * swayT) / (SWAY_S * 1000)) };
    globe.pointOfView({ ...swayAt, altitude: pov.altitude }, 0);
    swayReq = requestAnimationFrame(swayFrame);
  };
  const swayOn = () => {
    if (swaying && onScreen && !swayReq) swayReq = requestAnimationFrame((t) => { swayLast = t; swayReq = requestAnimationFrame(swayFrame); });
  };
  swayOn();
  el.addEventListener("pointerdown", stopSway, { once: true });

  // vertical thumb-swipes scroll the page; horizontal drags spin; pinch zooms. Zoomed in, with the page's
  // boxes away, one finger moves the globe and the map every way (setUi, in the satellite map section).
  globe.renderer().domElement.style.touchAction = "pan-y";

  // ---------- zoom: + and - buttons, Ctrl or ⌘ + wheel, a trackpad pinch, double click ----------
  // They all ease to a goal between the same limits, and any of them stops the spin. They go down to the
  // satellite map's SAT_MPX metres a screen px (satMin).
  const ZMAX = 3.2;
  const zmin = () => satMin();
  // never zooms the wrong way: after a touch pinch past a limit, zooming further keeps the altitude
  const goalFrom = (alt, f) => (f < 1 ? Math.max(Math.min(alt, zmin()), alt * f) : Math.min(Math.max(alt, ZMAX), alt * f));
  let zoomGoal = null, zoomReq = 0, zoomT = 0;
  // The double click flies with globe.gl's own animation (FLIGHT ms). While it flies, a zoom counts from
  // where the flight goes, not from the altitude halfway, and keeps easing until the flight is over.
  const FLIGHT = 700;
  let flightAlt = 0, flightEnd = 0;
  const flying = () => performance.now() < flightEnd;
  const zoomFrom = () => zoomGoal ?? (flying() ? flightAlt : globe.pointOfView().altitude);
  // A zoom by wheel or trackpad pinch keeps the spot under the pointer where it is on screen, as a map does
  // (keepSpot, in the satellite math). The buttons zoom at the centre. zoomAt is that spot as a unit vector.
  let zoomAt = null;
  const zoomCentre = (pov, next) => (zoomAt ? keepSpot(pov, next, zoomAt) : null);
  const zoomTo = (goal, at = null) => {
    stopSway();
    flyStop();
    flingStop();
    zoomAt = at;
    if (reduceMotion) {
      zoomGoal = null;
      const c = zoomCentre(globe.pointOfView(), goal);
      globe.pointOfView(c ? { ...c, altitude: goal } : { altitude: goal });
      return;
    }
    zoomGoal = goal;
    if (!zoomReq) { zoomT = performance.now(); zoomReq = requestAnimationFrame(zoomFrame); }
  };
  const zoomBy = (f, at = null) => zoomTo(goalFrom(zoomFrom(), f), at);
  const zoomFrame = (now) => {
    zoomReq = 0;
    if (zoomGoal === null) return;
    const pov = globe.pointOfView(), alt = pov.altitude;
    const k = 1 - Math.exp(-Math.max(0, now - zoomT) / 70); // eases out, there in about 300 ms
    zoomT = now;
    const next = Math.abs(Math.log(zoomGoal / alt)) < 0.002 ? zoomGoal : alt * Math.pow(zoomGoal / alt, k);
    const c = zoomCentre(pov, next);
    globe.pointOfView(c ? { ...c, altitude: next } : { altitude: next });
    if (next === zoomGoal && !flying()) zoomGoal = null; else zoomReq = requestAnimationFrame(zoomFrame);
  };
  // the spot under the pointer of a wheel or gesture event, for zoomAt (null next to the planet)
  const pointerSpot = (ev) => {
    const box = el.getBoundingClientRect(), g = screenToGeo(ev.clientX - box.left, ev.clientY - box.top);
    return g ? toUnit(g.lat, g.lng) : null;
  };
  // On the satellite map a step is bigger: from where it starts down to the deepest zoom is about 400 times.
  const zstep = (inward) => (zoomFrom() < MAP_FROM ? (inward ? 0.4 : 2.5) : inward ? 0.62 : 1.6);
  $("#zin").addEventListener("click", () => zoomBy(zstep(true)));
  $("#zout").addEventListener("click", () => zoomBy(zstep(false)));

  // A plain wheel keeps scrolling the page: OrbitControls never sees it, and a short hint on the
  // globe says how to zoom. Ctrl or ⌘ + wheel, and a trackpad pinch (browsers send it as a wheel
  // with ctrlKey), zoom the globe instead of the page.
  const isMac = /mac|iphone|ipad|ipod/i.test(navigator.userAgentData?.platform || navigator.platform || ""); // "macOS", "MacIntel"
  // Small pixel steps: a pinch zooms in proportion to the fingers, 100 px of it by e. It comes as a wheel
  // with ctrlKey but with no Control key down. Ctrl or ⌘ + two-finger scroll on a touchpad sends hundreds
  // of px, so it zooms 5 times slower.
  let ctrlDown = false;
  for (const type of ["keydown", "keyup"]) addEventListener(type, (ev) => (ctrlDown = ev.ctrlKey), true);
  addEventListener("blur", () => (ctrlDown = false));
  const pxPerStep = (ev) => (ev.ctrlKey && !ctrlDown ? 100 : 500);
  const zoomKeys = (isMac ? "⌘" : "ctrl") + " + scroll to zoom";
  const wheelHint = document.createElement("div");
  wheelHint.className = "wheel-hint";
  wheelHint.setAttribute("aria-hidden", "true");
  wheelHint.textContent = (isMac ? "⌘" : "Ctrl") + " + scroll to zoom";
  el.after(wheelHint);
  let hintTimer = 0;
  el.addEventListener("wheel", (ev) => {
    ev.stopPropagation();
    if (!ev.ctrlKey) ctrlDown = false; // a key up the page missed
    if (ev.ctrlKey || ev.metaKey) {
      ev.preventDefault();
      // A mouse notch is one step of 1.25x: 100 px, some lines (read first: Firefox only gives lines
      // then), or 4.000244140625 px on a Mac. A Mac's notch always has that size, so 50 px or more there
      // is a fast touchpad swipe. A pinch or a touchpad scroll sends many small values, and zooms in
      // proportion. Down zooms out, like a map.
      const lines = ev.deltaMode, dy = ev.deltaY;
      const step = lines || (Math.abs(dy) >= 50 && !isMac) || dy % 4.000244140625 === 0
        ? Math.sign(dy) * 0.22 : Math.max(-0.22, Math.min(0.22, dy / pxPerStep(ev)));
      if (step) zoomBy(Math.exp(step), pointerSpot(ev));
    } else if (Math.abs(ev.deltaY) > Math.abs(ev.deltaX)) {
      wheelHint.classList.add("on");
      clearTimeout(hintTimer);
      hintTimer = setTimeout(() => wheelHint.classList.remove("on"), 1500);
    }
  }, { capture: true, passive: false });
  // Safari on a Mac sends a trackpad pinch as gesture events, not as a wheel
  if ("GestureEvent" in window && !navigator.maxTouchPoints) {
    let from = 0;
    el.addEventListener("gesturestart", (ev) => { ev.preventDefault(); from = zoomFrom(); });
    el.addEventListener("gesturechange", (ev) => { ev.preventDefault(); if (ev.scale > 0) zoomTo(goalFrom(from, 1 / ev.scale), pointerSpot(ev)); });
    el.addEventListener("gestureend", (ev) => ev.preventDefault());
  }

  // ---------- one finger on the globe holds the spot it touched ----------
  // A finger (or a pen) moves the planet the way a map is moved: the spot under it stays under it (holdSpot, in the
  // satellite math), on the globe and on the satellite map, with nothing trailing behind. A flick carries on at the
  // finger's speed and slows down within about a second, timed by the clock and not by frames, so it feels the same
  // on a slow phone. A mouse keeps globe.gl's eased spin. On the globe a swipe that starts up or down scrolls the
  // page (touch-action: pan-y): until the finger has gone FIRM px mostly across, or LOOSE px any way, the planet
  // follows it only across, so it does not tilt before the page scrolls, and when the browser scrolls instead
  // (pointercancel) the planet goes back to where it was. A drag that starts on a mission tag holds the planet too
  // (#globe's touch-action in styles.css), and a tap on a tag still opens it. Two fingers pinch: the altitude follows
  // their spread as globe.gl's pinch did (pinchSpeed), within its limits, and the spot between them stays between
  // them, so the zoom goes toward the fingers and two fingers move the planet too. A finger on a tag counts, which
  // globe.gl's own pinch missed (it only knew fingers that came down on the canvas).
  const FIRM = 16, LOOSE = 48;                         // px
  const FLING_S = 0.35;                                // a flick loses two thirds of its speed in this many seconds
  const fingers = new Map();                           // pointerId -> { x, y } of each finger on the globe
  let hold = null, trail = [], flingReq = 0;           // the finger that holds a spot; the centre's last 120 ms
  function flingStop() { cancelAnimationFrame(flingReq); flingReq = 0; }
  // (fpx, with the satellite map below: the px on screen for a tan of 1)
  const fromMiddle = (x, y) => { const b = el.getBoundingClientRect(); return [x - b.left - b.width / 2, y - b.top - b.height / 2]; };
  const holdAt = (id, x, y, firm) => {
    const pov = globe.pointOfView(), [dx, dy] = fromMiddle(x, y);
    hold = { id, P: spotAt(pov, dx, dy, fpx()), x0: x, y0: y, from: { lat: pov.lat, lng: pov.lng }, firm };
    trail = [];
  };
  const holdMove = (x, y, t) => {
    if (!hold.firm) {
      const mx = x - hold.x0, my = y - hold.y0, d = Math.hypot(mx, my);
      if ((d >= FIRM && Math.abs(mx) >= Math.abs(my)) || d >= LOOSE) hold.firm = true;
      else y = hold.y0;                                // across only, until it is clear the page will not scroll
    }
    const pov = globe.pointOfView(), [dx, dy] = fromMiddle(x, y);
    const c = holdSpot(hold.P, dx, dy, fpx(), pov.altitude, pov.lat);
    globe.pointOfView({ ...c, altitude: pov.altitude }, 0);
    trail.push({ t, c: toUnit(c.lat, c.lng) });
    while (trail.length > 2 && t - trail[0].t > 120) trail.shift();
  };
  // A flick: the centre's turn over the finger's last 100 ms, if it still moved in the last 50 ms before letting
  // go, keeps turning the planet about the same axis, ever slower: by w * FLING_S * (1 - e^(-t / FLING_S)) in t s.
  const fling = (tUp) => {
    const last = trail[trail.length - 1];
    if (reduceMotion || !last || tUp - last.t > 50) return;
    const first = trail.find((e) => last.t - e.t <= 100), a = first.c, c0 = last.c, dt = (last.t - first.t) / 1000;
    const ax = [a[1] * c0[2] - a[2] * c0[1], a[2] * c0[0] - a[0] * c0[2], a[0] * c0[1] - a[1] * c0[0]], n = Math.hypot(...ax);
    if (dt < 0.01 || n < 1e-12) return;
    const pxRad = fpx() / globe.pointOfView().altitude; // px on screen a radian of turn moves the ground in the middle
    let w = Math.atan2(n, a[0] * c0[0] + a[1] * c0[1] + a[2] * c0[2]) / dt;   // radians a second
    if (w * pxRad < 60) return;                        // a slow let-go is no flick
    w = Math.min(w, 8000 / pxRad);
    const k = ax.map((v) => v / n), kc = k[0] * c0[0] + k[1] * c0[1] + k[2] * c0[2], t0 = performance.now(), r = Math.PI / 180;
    const step = (now) => {
      const t = (now - t0) / 1000, th = w * FLING_S * (1 - Math.exp(-t / FLING_S)), cos = Math.cos(th), sin = Math.sin(th);
      const v = [0, 1, 2].map((i) => c0[i] * cos + (k[(i + 1) % 3] * c0[(i + 2) % 3] - k[(i + 2) % 3] * c0[(i + 1) % 3]) * sin + k[i] * kc * (1 - cos));
      const lat = Math.max(-HOLD_LAT, Math.min(HOLD_LAT, Math.atan2(v[2], Math.hypot(v[0], v[1])) / r));
      globe.pointOfView({ lat, lng: Math.atan2(v[1], v[0]) / r, altitude: globe.pointOfView().altitude }, 0);
      flingReq = onScreen && w * Math.exp(-t / FLING_S) * pxRad > 10 ? requestAnimationFrame(step) : 0;
    };
    flingReq = requestAnimationFrame(step);
  };
  let pinch = null;                                    // { P, d }: the spot under the two fingers' middle, their spread
  const twoFingers = () => {
    const [a, b] = fingers.values();
    return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, d: Math.hypot(a.x - b.x, a.y - b.y) };
  };
  const pinchAt = () => {
    const m = twoFingers(), pov = globe.pointOfView(), [dx, dy] = fromMiddle(m.x, m.y);
    pinch = { P: spotAt(pov, dx, dy, fpx()), d: m.d };
  };
  const pinchMove = () => {
    const m = twoFingers(), pov = globe.pointOfView(), R = globe.getGlobeRadius();
    if (m.d < 1 || pinch.d < 1) return;
    const k = (1 + pov.altitude) * Math.pow(pinch.d / m.d, pinchSpeed(pov.altitude));
    const alt = Math.min(controls.maxDistance / R, Math.max(controls.minDistance / R, k)) - 1;
    pinch.d = m.d;
    const [dx, dy] = fromMiddle(m.x, m.y);
    globe.pointOfView({ ...holdSpot(pinch.P, dx, dy, fpx(), alt, pov.lat), altitude: alt }, 0);
  };
  el.addEventListener("pointerdown", (ev) => {
    flingStop();
    controls.enableRotate = controls.enableZoom = ev.pointerType === "mouse";   // fingers are ours; a mouse is globe.gl's
  }, true);
  el.addEventListener("pointerdown", (ev) => {
    if (ev.pointerType === "mouse") return;
    fingers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    hold = pinch = null;
    if (flying()) return;                              // a double tap's flight (globe.gl's own) runs to its end
    zoomGoal = null;
    if (fingers.size === 1) holdAt(ev.pointerId, ev.clientX, ev.clientY, uiOff);
    else if (fingers.size === 2) pinchAt();
  });
  el.addEventListener("pointermove", (ev) => {
    const f = fingers.get(ev.pointerId);
    if (!f) return;
    f.x = ev.clientX; f.y = ev.clientY;
    if (hold?.id === ev.pointerId) holdMove(ev.clientX, ev.clientY, ev.timeStamp);
    else if (pinch) pinchMove();
  });
  const lift = (ev) => {
    const f = fingers.get(ev.pointerId);
    if (!f) return;
    fingers.delete(ev.pointerId);
    pinch = null;
    if (hold?.id === ev.pointerId) {
      if (ev.type === "pointercancel") {           // the browser took the touch: it scrolls the page
        if (!hold.firm) globe.pointOfView({ ...hold.from, altitude: globe.pointOfView().altitude }, 0);
      } else {
        if (ev.clientX !== f.x || ev.clientY !== f.y) holdMove(ev.clientX, ev.clientY, ev.timeStamp);   // where it let go
        if (!fingers.size) fling(ev.timeStamp);
      }
      hold = null;
    }
    if (flying()) return;
    if (fingers.size === 1 && !hold) { const [[id, g]] = fingers; holdAt(id, g.x, g.y, true); }   // one finger left after a pinch
    else if (fingers.size === 2) pinchAt();            // three fingers down to two
  };
  el.addEventListener("pointerup", lift);
  el.addEventListener("pointercancel", lift);

  // double click zooms in toward that spot
  el.addEventListener("dblclick", (ev) => {
    if (ev.target.closest(".mpin")) return;   // on a tag, whose click opened it already
    const box = el.getBoundingClientRect();
    const at = screenToGeo(ev.clientX - box.left, ev.clientY - box.top);
    if (!at) return;                           // next to the planet
    const altitude = goalFrom(zoomFrom(), 0.5);
    zoomGoal = null;
    stopSway();
    flyStop();
    flingStop();
    if (!reduceMotion) { flightAlt = altitude; flightEnd = performance.now() + FLIGHT + 50; }
    globe.pointOfView({ lat: at.lat, lng: at.lng, altitude }, reduceMotion ? 0 : FLIGHT);
  });

  // the line under the globe says how to zoom on this device. Each part keeps its words and its dot together (no-break
  // spaces), so a hint too wide for one line (a narrow window, a larger text setting) breaks only after a dot, never in
  // PINCH TO ZOOM or ⌘ + SCROLL TO ZOOM
  const finePointer = matchMedia("(pointer: fine)");
  const tapHint = () => ($("#tapHint").textContent = ["drag to spin", finePointer.matches ? zoomKeys : "pinch to zoom",
    "tap a " + (mgeo.length ? "pin" : "dot")].map((p) => p.replace(/ /g, "\u00a0")).join("\u00a0· "));
  tapHint();
  finePointer.addEventListener?.("change", tapHint);

  // ---------- finger taps next to a receipt dot ----------
  // The dots are only a few px wide. A finger tap that hits none looks for receipts within REACH px
  // on the near side of the planet. globe.gl's own click (onGlobeClick) would miss most of these
  // taps: over land they hit a hex, near a dot one of its rings, and a finger that moves 2 px is a
  // drag to globe.gl. Mouse clicks keep exact hits (a dot shows its tooltip on hover), so a double
  // click next to a dot zooms in instead of opening a receipt.
  const REACH = 36;
  // A tap opens the nearest receipt when it is clearly the nearest: the next one is CLEAR px farther.
  // Otherwise the dots are too close together for a finger, and a list asks which one.
  const CLEAR = 16;
  // A dot no one can see is not there to tap: one under the tap hint's strip (onStrip), under a box that stands over
  // the globe and takes taps (the pitch or SAMPLE DATA, CLEANUP CREW? APPLY, the stats, the legend, the ways on, + and -,
  // and on the satellite map BACK TO THE GLOBE, the map's note and the credit's link), or with its middle off the
  // screen, where the browser has no element. A finger's reach found it from a tap next to the box (2026-11-17) or near
  // the screen's edge (2026-11-18). Mission tags do not hide one: they sit inside #globe, as the canvas does. Only the
  // boxes take taps, not the space between or beside them, so a dot seen in a gap between the stats or beside BACK TO
  // THE GLOBE is there to tap; + and - and BACK TO THE GLOBE reach 4 px past their edges (site/styles.css).
  const hidden = (cx, cy) => {
    if (onStrip({ clientX: cx, clientY: cy })) return true;
    const top = document.elementFromPoint(cx, cy);
    return !top || !el.contains(top);
  };
  const receiptsNear = (x, y, reach = REACH) => {
    const pov = globe.pointOfView(), r = Math.PI / 180;
    const horizon = 1 / (1 + pov.altitude);    // cos of the arc from the view's centre to the horizon
    const box = el.getBoundingClientRect(), near = [];
    for (const { of: e, location } of geo) {
      const lat = r3(location.lat), lng = r3(location.lng);
      const cos = Math.sin(pov.lat * r) * Math.sin(lat * r) + Math.cos(pov.lat * r) * Math.cos(lat * r) * Math.cos((lng - pov.lng) * r);
      if (cos <= horizon) continue;            // on the far side
      const s = globe.getScreenCoords(lat, lng, DOT_ALT * dotLow);
      const d = Math.hypot(s.x - x, s.y - y);
      if (d <= reach && !hidden(s.x + box.left, s.y + box.top)) near.push({ e, d });
    }
    // A receipt with several spots counts once, at its nearest dot.
    const seen = new Set();
    return near.sort((a, b) => a.d - b.d).filter((x) => !seen.has(x.e) && !!seen.add(x.e));
  };
  // A finger has no hover. The dot's small preview (globe.gl's tooltip) would flash under it just
  // before the post opens, and stay: it shows for a mouse only.
  // Nor over the tap hint's words, where a dot hidden under its strip would show it (on-strip).
  const byTouch = (ev) => {
    el.classList.toggle("by-touch", ev.pointerType !== "mouse");
    el.classList.toggle("on-strip", onStrip(ev));
  };
  el.addEventListener("pointerdown", byTouch, true);
  el.addEventListener("pointermove", byTouch, true);
  // The browser's click says it was a tap (not a drag or a pinch) and where it went: a tap that the
  // browser gives to a tag nearby is the tag's. A tap that starts on a box over the globe is the box's, even where
  // WebKit gives its click to the globe or to a mission tag beside it: a finger 10 px inside a stat's edge opened a dot
  // or mission #2's tag seen in the gap next to it (iOS Simulator, 2026-11-18). The press counts where the finger is, not
  // where the browser sends it: Chrome moves a press up to about 15 px inside a stat or the pitch onto a tag beside it
  // (Chrome 149, 2026-11-18).
  addEventListener("pointerdown", (ev) => {
    pressType = ev.pointerType;
    pressOn = el.contains(document.elementFromPoint(ev.clientX, ev.clientY) || ev.target);   // where the finger is
  }, true);
  el.addEventListener("click", (ev) => {
    // On the satellite map the receipts are marks behind the faded globe (satMarks), and globe.gl no longer
    // picks: a mouse click opens the receipt whose mark it hits. The press tells a finger from a mouse, not the click:
    // on an iPhone the click after a finger's tap says mouse (WebKit), and a tap on a receipt's dot opened nothing
    // (iOS Simulator, 2026-11-17).
    const mouse = pressType ? pressType === "mouse" : ev.pointerType === "mouse";
    if (pressOn === false || (mouse && !satMarks) || ev.target.closest(".mpin") || onStrip(ev)) return;
    const box = el.getBoundingClientRect(), x = ev.clientX - box.left, y = ev.clientY - box.top;
    // globe.gl handles its own click in an animation frame: let it go first, so a dot hit right on wins
    requestAnimationFrame(() => {
      const now = performance.now();
      if (!overlay.hidden || now - pinTapAt < 400 || now - pointTapAt < 400) return;
      const near = receiptsNear(x, y, mouse ? markR + 3 : REACH);
      if (!near.length) return;
      if (near.length === 1 || near[1].d - near[0].d > CLEAR) openPost(near[0].e);
      else openReceiptChooser(near.map((n) => n.e));
    });
  });

  // ---------- satellite map: zoom in far and the drawn globe turns into satellite pictures ----------
  // Below MAP_FROM the drawn globe (globe.gl's canvas) fades out over a layer of satellite pictures behind it
  // (satEl, z-index -1 inside #globe), and each receipt becomes a mark on that layer, where its dot was. The
  // pictures are EOxCloudless (the satellite math above), free for a non-commercial site with the credit in
  // #satBar. The browser loads them straight from tiles.maps.eox.at, never through a Function, and only once the
  // visitor zooms in below MAP_FROM or taps SEE THE SPOT ON SATELLITE in a post: before that the pages load
  // nothing from other companies. /impressum/#privacy says so, that EOX then sees the IP address, and why
  // (legitimate interest). BACK TO THE GLOBE (#satBack) flies back out.
  const DOT_PX = 8;                                    // a receipt's dot on the map: radius in px, without its white rim
  const SAT_LOADS = 6;                                 // pictures loading at once; the others wait, nearest the centre first
  const EARTH_M = 6371000;
  const canvas = globe.renderer().domElement;
  const tanHalf = () => Math.tan((globe.camera().fov * Math.PI) / 360);
  const mppAt = (a) => (a * EARTH_M * 2 * tanHalf()) / (globe.height() || 1);  // metres a screen px at the view's centre
  const satMin = () => (SAT_MPX * (globe.height() || 1)) / (EARTH_M * 2 * tanHalf());
  const fpx = () => (globe.height() || 1) / 2 / tanHalf();                     // px on screen for 1 unit seen from 1 unit away
  // a dot's radius on screen at altitude a with its top at DOT_ALT * low, at dotSize 1 (Infinity from that low)
  const natPx = (a, low) => seenPx(fpx(), DOT_R, a, DOT_ALT * low);

  // A camera moved by pointOfView gets its new direction only at the controls' next update, in globe.gl's next
  // frame: until then a projection would use the old direction (a zoom step or a wheel event can fall in that
  // gap). This points it at the planet's centre now, as that update does, so the maths below match the screen.
  function syncCam() {
    const cam = globe.camera();
    cam.lookAt(controls.target);
    cam.updateMatrixWorld();
    return cam;
  }
  // Where the screen point (x, y), in px, meets the planet, worked out on the true sphere: globe.toGlobeCoords
  // hits globe.gl's 75 by 75 mesh, which sits up to 5 km low between its corners, too far off a few km up.
  function screenToGeo(x, y) {
    const cam = syncCam();
    const ap = (m, v) => {                             // a three.js 4 by 4 matrix on a point
      const w = m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15];
      return [0, 1, 2].map((i) => (m[i] * v[0] + m[4 + i] * v[1] + m[8 + i] * v[2] + m[12 + i]) / w);
    };
    const p = ap(cam.matrixWorld.elements, ap(cam.projectionMatrixInverse.elements,
      [(x / (globe.width() || 1)) * 2 - 1, 1 - (y / (globe.height() || 1)) * 2, 0.5]));
    const o = cam.position, R = globe.getGlobeRadius();
    const d = [p[0] - o.x, p[1] - o.y, p[2] - o.z], dl = Math.hypot(d[0], d[1], d[2]);
    const b = (o.x * d[0] + o.y * d[1] + o.z * d[2]) / dl, c = o.x * o.x + o.y * o.y + o.z * o.z - R * R;
    if (b * b - c < 0) return null;                    // next to the planet
    const t = -b - Math.sqrt(b * b - c);
    if (t < 0) return null;
    const g = globe.toGeoCoords({ x: o.x + (d[0] / dl) * t, y: o.y + (d[1] / dl) * t, z: o.z + (d[2] / dl) * t });
    return { lat: g.lat, lng: g.lng };
  }

  const satEl = document.createElement("div");
  satEl.className = "satmap";
  satEl.hidden = true;
  el.appendChild(satEl);
  const satTiles = satEl.appendChild(Object.assign(document.createElement("div"), { className: "sat-tiles" }));
  const mark = (cls) => satEl.appendChild(Object.assign(document.createElement("i"), { className: cls }));
  // the marks stand on the rounded public point, about 100 m, like everything on the globe
  const satPts = geo.map((p) => ({ lat: r3(p.location.lat), lng: r3(p.location.lng), el: mark("sat-pt") }));
  const satMs = mgeo.map((m) => ({ lat: r3(m.lat), lng: r3(m.lng), el: mark("sat-ms" + (funded(m) ? " sat-ms-funded" : "")) }));
  const satBar = $("#satBar"), satErr = $("#satErr"), tapHintEl = $("#tapHint");

  const tiles = new Map();                             // "z/x/y" -> { img, z, x, y, d, st: 0 waiting, 1 loading, 2 there, 3 failed }
  let satZ = -1, satWant = [], loads = 0, satReady = false, satK = 0, fadeReq = 0;
  let satMarks = false, markR = 0;                     // the marks stand for the receipts (globe.gl no longer picks); their radius
  let cvOp = "", ringsOn = !reduceMotion, satClip = "";

  function satFrame(pov) {
    try { satDraw(pov); } catch (e) {                  // this runs inside globe.gl's frame: a throw here would stop the globe for good
      console.error("satellite map", e);
    }
  }
  // globe.gl's onZoom misses small moves: the camera controls only tell of a move over 0.001 units (64 m), and
  // a few km up that is many pixels, so the end of a zoom or of a flick would carry the globe's dots and tags
  // away from the map. While the map shows, the map follows the camera in every frame that globe.gl draws,
  // just before it draws, whenever the camera moved at all.
  let satCam = "";
  const camKey = () => { const p = globe.camera().position; return p.x + "," + p.y + "," + p.z; };
  globe.scene().onBeforeRender = () => { if (!satEl.hidden && camKey() !== satCam) satFrame(globe.pointOfView()); };
  function satDraw(pov) {
    const a = pov.altitude, cam = globe.camera();
    // A dot grows with the zoom only until it is DOT_PX on screen, its size on the map, and keeps that size from
    // there on, so it never looms large before the map and never changes size at the switch. As the map comes
    // in (m), dots and tags come down to the ground (low), so they stay on their spot over the map.
    const m = mapShare(a), low = 1 - m + m * Math.min(1, a / MAP_FROM);
    const rDot = Math.min(natPx(a, 1), DOT_PX), size = rDot / natPx(a, low);
    if (Math.abs(size - dotSize) > 0.015 * dotSize || Math.abs(low - dotLow) > 0.015 * dotLow ||
      (size === 1 && dotSize !== 1) || (low === 1 && dotLow !== 1)) {
      dotSize = size; dotLow = low;
      globe.pointsTransitionDuration(0).pointAltitude(dotAlt).pointRadius(dotRadius);
      if (tagged) { tagAlt = TAG_ALT * low; globe.htmlAltitude(tagAlt); }
    }
    // How far a dot reaches below its spot on screen where the camera looks: its dark ring, or on the map its mark (the
    // dot, or the area once that is bigger, with the white rim and the outline). A cleaned spot's slip hangs just under
    // it (cleanPin), in half px steps; only the slips are touched.
    const hang = Math.round(2 * Math.max((rDot * INK_R) / DOT_R, m > 0 ? Math.max(rDot, AREA_M / mppAt(a)) + 4 : 0)) / 2;
    if (hang !== hangPx) {
      hangPx = hang;
      for (const g of globe.htmlElementsData()) if (g.rs && g.pin) g.pin.style.setProperty("--hang", hang + "px");
    }
    // a few km up the camera would cut off the tags at its near plane (0.1 units, 6 km)
    const near = Math.min(0.1, Math.max(1e-4, a * 50));
    if (Math.abs(near - cam.near) > 0.05 * near) { cam.near = near; cam.updateProjectionMatrix(); }

    const mk = m * satK;                               // the canvas fades only once the pictures are there (fadeIn)
    const op = mk > 0 ? String(Math.round((1 - mk) * 1000) / 1000) : "";
    if (op !== cvOp) { cvOp = op; canvas.style.opacity = op; }
    const marks = mk >= 0.5;
    if (marks !== satMarks) { satMarks = marks; globe.enablePointerInteraction(!marks); canvas.style.cursor = ""; }
    // Once the map is whole the canvas is see-through: the planet with its land, its outline and the receipt dots
    // stop drawing, which saves a phone's battery. globe.gl keeps the dots in a group, found by a dot in it.
    const off3d = mk >= 1;
    if (off3d !== hid3d) {
      hid3d = off3d;
      globe.showGlobe(!off3d);
      if (outline) outline.visible = !off3d;
      let dots = null;
      globe.scene().traverse((o) => { if (!dots && o.__globeObjType === "point") dots = o.parent; });
      if (dots) dots.visible = !off3d;
    }
    // the pulse rings belong to the drawn globe
    const rg = !reduceMotion && m < 0.02;
    if (rg !== ringsOn) { ringsOn = rg; globe.ringsData(rg ? geo : []); }
    if (a < MAP_FROM) setUi(true); else if (a > UI_BACK_AT) setUi(false);
    const on = m > 0 && uiGone;                        // BACK TO THE GLOBE and the credit, while the map shows
    if (satBar.hidden === on) satBar.hidden = !on;
    if (tapHintEl.hidden !== on) tapHintEl.hidden = on;

    if (!m) { if (!satEl.hidden) satClear(); return; }
    satEl.hidden = false;
    satCam = camKey();
    syncCam();                                         // the projection of this frame, not the last one's
    const W = globe.width() || 1, H = globe.height() || 1, mpp = mppAt(a);
    satTilesDraw(pov, mpp, W, H);

    // A receipt's mark is its dot, as big as globe.gl draws it there (smaller away from the centre, seen at an
    // angle), and never smaller than the area its rounded point stands for. Once that area is about as big as
    // the dot, the mark turns see-through: an area, with the place under it.
    const area = AREA_M / mpp, r = Math.PI / 180, horizon = 1 / (1 + a), dotAt = DOT_ALT * low;
    const front = (p) => Math.sin(pov.lat * r) * Math.sin(p.lat * r) +
      Math.cos(pov.lat * r) * Math.cos(p.lat * r) * Math.cos((p.lng - pov.lng) * r) > horizon;
    const place = (p, s, rad) => {                     // shows the mark when its centre s is on screen
      const ok = s && s.x > -rad && s.x < W + rad && s.y > -rad && s.y < H + rad;
      if (p.el.hidden === !!ok) p.el.hidden = !ok;
      return !!ok;
    };
    markR = 0;
    for (const p of satPts) {
      const s = front(p) ? globe.getScreenCoords(p.lat, p.lng, dotAt) : null;
      const q = s && globe.getScreenCoords(p.lat + DOT_R * dotSize, p.lng, dotAt);
      // at most twice the dot's size on the map (it is DOT_PX or a bit less), so a mark never covers the screen
      const rd = s ? Math.min(Math.hypot(q.x - s.x, q.y - s.y), 2 * DOT_PX) : 0;
      const see = Math.min(1, Math.max(0, (area / rd - 0.45) / 0.45));
      const rr = Math.round(markPx(mpp, rd) * 10) / 10;
      const rim = Math.round(Math.max(2, rd * (RIM_R / DOT_R - 1) * (1 - see) + 2 * see) * 10) / 10;
      if (!place(p, s, rr + rim)) continue;
      markR = Math.max(markR, rr + rim);
      if (p.r !== rr || p.rim !== rim) {
        p.r = rr; p.rim = rim;
        p.el.style.width = p.el.style.height = 2 * rr + "px";
        p.el.style.borderWidth = rim + "px";
      }
      const fill = `rgba(0, 122, 61, ${Math.round((1 - 0.68 * see) * 100) / 100})`;
      if (p.fill !== fill) { p.fill = fill; p.el.style.background = fill; }
      p.el.style.transform = `translate(${s.x - rr - rim}px, ${s.y - rr - rim}px)`;
    }
    // a mission's tag points at its spot; deep in, a ring shows the area that spot stands for
    const ra = Math.round(area * 10) / 10;
    for (const p of satMs) {
      const s = ra >= 5 && front(p) ? globe.getScreenCoords(p.lat, p.lng, 0) : null;
      if (!place(p, s, ra)) continue;
      if (p.r !== ra) { p.r = ra; p.el.style.width = p.el.style.height = 2 * ra + "px"; }
      p.el.style.transform = `translate(${s.x - ra}px, ${s.y - ra}px)`;
    }
    // the map stops at the planet's outline (only seen at its start on a very wide screen)
    const rd = fpx() / Math.sqrt((1 + a) ** 2 - 1);
    const clip = rd < Math.hypot(W, H) / 2 ? `circle(${Math.round(rd)}px at 50% 50%)` : "";
    if (clip !== satClip) { satClip = clip; satEl.style.clipPath = clip; }
  }

  // The tiles under the screen at the level for this zoom. Each is drawn from where its corners fall on the
  // screen, so it lies on the curved planet where the dots and tags are. Until a new level is there, the last
  // level's tiles fill the gaps under it.
  function satTilesDraw(pov, mpp, W, H) {
    // in a flight, tiles two levels coarser (but not coarser than 5): a sixteenth of the pictures, and the
    // motion hides the blur
    const z = Math.max(flyReq ? 5 : 2, tileZ(mpp, pov.lat) - (flyReq ? 2 : 0)), n = 2 ** z;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let i = 0; i <= 4; i++) {
      for (let j = 0; j <= 4; j++) {
        const g = screenToGeo((W * i) / 4, (H * j) / 4);
        if (!g) continue;
        const lng = pov.lng + ((((g.lng - pov.lng) % 360) + 540) % 360) - 180;   // unwrapped around the view
        const tx = tileX(lng, z), ty = tileY(g.lat, z);
        x0 = Math.min(x0, tx); x1 = Math.max(x1, tx); y0 = Math.min(y0, ty); y1 = Math.max(y1, ty);
      }
    }
    if (!(x1 >= x0)) return;
    const want = [], cx = tileX(pov.lng, z), cy = tileY(pov.lat, z);
    for (let x = Math.floor(x0 - 0.05); x <= Math.floor(x1 + 0.05); x++) {
      for (let y = Math.max(0, Math.floor(y0 - 0.05)); y <= Math.min(n - 1, Math.floor(y1 + 0.05)); y++) {
        want.push({ k: z + "/" + x + "/" + y, x, y, d: Math.hypot(x + 0.5 - cx, y + 0.5 - cy) });
      }
    }
    if (want.length > 96) return;                      // never expected: it would ask EOX for too much at once
    satZ = z;
    satWant = want.map((w) => w.k);
    for (const w of want) {
      let t = tiles.get(w.k);
      if (!t) {
        // A big tile bends with the planet: it is laid as k by k parts, each on its own corners (a part is a
        // quarter or less of the picture, shown as a background once the picture has loaded)
        const k = z <= 4 ? 4 : z === 5 ? 3 : z <= 7 ? 2 : 1, box = document.createElement("div"), parts = [];
        box.className = "sat-tile";
        box.style.zIndex = String(z);
        for (let j = 0; j < k; j++) {
          for (let i = 0; i < k; i++) {
            const el = box.appendChild(document.createElement("i"));
            el.style.width = el.style.height = 256 / k + "px";
            el.style.backgroundPosition = `${(-256 * i) / k}px ${(-256 * j) / k}px`;
            parts.push({ el, i, j });
          }
        }
        t = { box, parts, k, z, x: w.x, y: w.y, st: 0, url: SAT_URL(z, ((w.x % n) + n) % n, w.y) };
        tiles.set(w.k, t);
        satTiles.appendChild(box);
      }
      t.d = w.d;
    }
    // Another level's tiles stay under this one until it is all there and faded in, so nothing shows through
    // while levels change: coarser ones as a blurry backdrop, finer ones (up to 2 levels) where they still fit.
    const wanted = new Set(satWant), now = performance.now(), whole = satWant.every((k) => tileShown(tiles.get(k), now));
    for (const [k, t] of tiles) {
      if (!wanted.has(k) && (t.z === z || whole || t.st === 0 || t.z > z + 2)) dropTile(k, t);
      else placeTile(t);
    }
    pump();
  }
  // a tile is shown once its picture has faded in (or failed: then there is nothing to wait for)
  const FADE_MS = reduceMotion ? 0 : 320;              // .sat-tile's opacity transition in styles.css, .3s
  const tileShown = (t, now) => t.st === 3 || (t.st === 2 && now - t.onAt >= FADE_MS);
  // Each part's four corners on screen, a hair outside its edges so neighbours overlap and no seam shows, and
  // the perspective transform that lays its square on them (Heckbert's square to quad). Neighbours share their
  // corners, so their edges meet along the same lines.
  function placeTile(t) {
    const n = 2 ** t.z, o = 0.0015, s = t.k / 256;
    const at = (u, v) => globe.getScreenCoords(rowLat(t.y + v, t.z), ((t.x + u) / n) * 360 - 180, 0);
    for (const { el, i, j } of t.parts) {
      const u0 = i / t.k - o, u1 = (i + 1) / t.k + o, v0 = j / t.k - o, v1 = (j + 1) / t.k + o;
      const p0 = at(u0, v0), p1 = at(u1, v0), p2 = at(u1, v1), p3 = at(u0, v1);
      const dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x;
      const dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y;
      const den = dx1 * dy2 - dx2 * dy1;
      const g = den ? (dx3 * dy2 - dx2 * dy3) / den : 0, h = den ? (dx1 * dy3 - dx3 * dy1) / den : 0;
      el.style.transform = `matrix3d(${(p1.x - p0.x + g * p1.x) * s}, ${(p1.y - p0.y + g * p1.y) * s}, 0, ${g * s}, ` +
        `${(p3.x - p0.x + h * p3.x) * s}, ${(p3.y - p0.y + h * p3.y) * s}, 0, ${h * s}, 0, 0, 1, 0, ${p0.x}, ${p0.y}, 0, 1)`;
    }
  }
  function dropTile(k, t) {
    tiles.delete(k);
    t.box.remove();                                    // one still loading finishes into the browser's cache
  }
  function pump() {
    if (loads >= SAT_LOADS) return;
    const wait = [...tiles.values()].filter((t) => t.st === 0).sort((p, q) => p.d - q.d);
    for (const t of wait) {
      if (loads >= SAT_LOADS) break;
      loads++; t.st = 1;
      const img = new Image(), asked = performance.now();
      img.onload = () => {
        loads--; t.st = 2; t.onAt = performance.now();
        for (const p of t.parts) p.el.style.backgroundImage = `url("${t.url}")`;
        // a picture the browser already had (zooming back and forth) shows at once, without the fade
        if (t.onAt - asked < 60) { t.box.classList.add("now"); t.onAt -= FADE_MS; }
        t.box.classList.add("on");
        satGot();
      };
      img.onerror = () => { loads--; t.st = 3; satGot(); };
      img.src = t.url;
    }
  }
  // a tile came (or failed): once a level is whole and faded in the older tiles go, and once most of the first
  // level is there the drawn globe starts to fade. When none of a level came, the bar says so.
  let pruneTimer = 0;
  function satPrune() {
    pruneTimer = 0;
    const now = performance.now(), cur = satWant.map((k) => tiles.get(k)).filter(Boolean);
    if (!cur.length || !cur.every((t) => tileShown(t, now))) return;
    for (const [k, t] of tiles) if (t.z !== satZ) dropTile(k, t);
  }
  function satGot() {
    const cur = satWant.map((k) => tiles.get(k)).filter(Boolean);
    const there = cur.filter((t) => t.st === 2).length, done = cur.filter((t) => t.st >= 2).length;
    if (cur.length && done === cur.length) { clearTimeout(pruneTimer); pruneTimer = setTimeout(satPrune, FADE_MS + 20); }
    if (!satReady && cur.length && there >= 0.8 * cur.length) { satReady = true; fadeIn(); }
    const failed = cur.length > 0 && done === cur.length && !there;
    if (satErr.hidden === failed) satErr.hidden = !failed;
    pump();
  }
  function fadeIn() {
    cancelAnimationFrame(fadeReq);
    const t0 = performance.now(), k0 = satK;
    const step = (now) => {
      satK = reduceMotion ? 1 : Math.min(1, k0 + (now - t0) / 450);
      fadeReq = satK < 1 ? requestAnimationFrame(step) : 0;
      satFrame(globe.pointOfView());
    };
    fadeReq = requestAnimationFrame(step);
  }
  function satClear() {
    satEl.hidden = true;
    for (const [k, t] of tiles) dropTile(k, t);
    satZ = -1; satWant = []; satReady = false; satK = 0;
    cancelAnimationFrame(fadeReq); fadeReq = 0;
    satErr.hidden = true;
  }

  // Zoomed in to the satellite map, the page's own boxes step aside so the map has the screen: the crew link,
  // SAMPLE DATA, the hint line, the legend, the stats, SEE THE RECEIPTS and SEE THE CREWS (the logo, the zoom buttons
  // and BACK TO THE GLOBE stay). They fade (map-on), then leave the layout (map-gone), so BACK TO THE GLOBE drops to the
  // bottom; they come back only zoomed far out again, above UI_BACK_AT, so a small zoom out leaves them away.
  // While they are away, one finger moves the globe and the map every way: a vertical swipe on the first screen
  // no longer scrolls the page or pulls it to refresh (the canvas here, the rest of the hero by .hero.map-on in
  // styles.css). It used to wait for the whole map, so a swipe on a map half in moved the page instead.
  const UI_BACK_AT = 1.2;
  const hero = el.closest(".hero");
  let uiOff = false, uiGone = false, uiTimer = 0;
  function setUi(off) {
    if (off === uiOff) return;
    uiOff = off;
    canvas.style.touchAction = off ? "none" : "pan-y";
    clearTimeout(uiTimer);
    if (off) {
      hero.classList.add("map-on");
      uiTimer = setTimeout(() => { uiGone = true; hero.classList.add("map-gone"); satFrame(globe.pointOfView()); }, reduceMotion ? 0 : 260);
    } else {
      uiGone = false;
      hero.classList.remove("map-gone");
      requestAnimationFrame(() => { if (!uiOff) hero.classList.remove("map-on"); });   // back in the layout, then fade in
    }
  }

  // a pinch goes down to the satellite map's deepest zoom, like the buttons (satMin depends on the screen's height)
  const setMin = () => { controls.minDistance = 100 * (1 + satMin()); };

  // Flies the camera to (lat, lng) at altitude alt: along the great circle, the altitude eased on a log scale.
  // From down on the map, a hop of more than about 25 km first goes up to about as high as the hop is long,
  // then across and down again, so the way across needs few satellite pictures (and a long hop crosses on the
  // drawn globe). Otherwise it moves and zooms at once, getting there sideways in the first 60% of the time,
  // while it is still high. A touch, a zoom or a double click stops it where it is.
  let flyReq = 0;
  function flyStop() { cancelAnimationFrame(flyReq); flyReq = 0; }
  const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (2 - 2 * t) ** 3 / 2);
  const clamp01 = (t) => Math.min(1, Math.max(0, t));
  function flyTo(lat, lng, alt, then) {
    flyStop(); flingStop(); stopSway(); zoomGoal = null;
    if (alt < MAP_FROM) satPrefetch(lat, lng, alt);
    if (reduceMotion) { globe.pointOfView({ lat, lng, altitude: alt }, 0); if (then) then(); return; }
    const p0 = globe.pointOfView(), r = Math.PI / 180;
    const v = (la, ln) => [Math.cos(la * r) * Math.cos(ln * r), Math.cos(la * r) * Math.sin(ln * r), Math.sin(la * r)];
    const A = v(p0.lat, p0.lng), B = v(lat, lng);
    const ang = Math.acos(Math.min(1, Math.max(-1, A[0] * B[0] + A[1] * B[1] + A[2] * B[2])));
    const high = ang > 0.004 && p0.altitude < ang * 1.5 ? Math.min(2.5, ang * 1.5) : 0;
    const l0 = Math.log(p0.altitude), l1 = Math.log(alt), lh = Math.log(high || 1);
    const tA = 0.3, tB = 0.65;                         // a hop from the map: up until tA, across until tB, then down
    const ms = Math.min(3200, 800 + (ang > 0.004 ? 500 : 0) +
      140 * (high ? Math.abs(lh - l0) + Math.abs(l1 - lh) : Math.abs(l1 - l0)));
    const t0 = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - t0) / ms);
      let ep, la;
      if (!high) { ep = ease(Math.min(1, t / 0.6)); la = l0 + (l1 - l0) * ease(t); }
      else {
        ep = ease(clamp01((t - tA) / (tB - tA)));
        la = t < tA ? l0 + (lh - l0) * ease(t / tA) : t < tB ? lh : lh + (l1 - lh) * ease((t - tB) / (1 - tB));
      }
      const s = Math.sin(ang), k0 = ang > 1e-9 ? Math.sin((1 - ep) * ang) / s : 1 - ep, k1 = ang > 1e-9 ? Math.sin(ep * ang) / s : ep;
      const x = k0 * A[0] + k1 * B[0], y = k0 * A[1] + k1 * B[1], z = k0 * A[2] + k1 * B[2];
      globe.pointOfView({ lat: Math.atan2(z, Math.hypot(x, y)) / r, lng: Math.atan2(y, x) / r, altitude: Math.exp(la) }, 0);
      flyReq = t < 1 ? requestAnimationFrame(step) : 0;
      if (t < 1) return;
      satFrame(globe.pointOfView());                   // the landing view's own tiles, not the flight's coarser ones
      if (then) then();
    };
    flyReq = requestAnimationFrame(step);
  }
  el.addEventListener("pointerdown", flyStop, true);

  $("#satBack").addEventListener("click", () => {
    const p = globe.pointOfView();
    flyTo(p.lat, p.lng, Math.max(p.altitude, 1.5));    // out to the drawn globe, past UI_BACK_AT, so the page's boxes come back
  });
  // The pictures where a flight lands are asked for as it starts, so they are in the browser's cache by then
  function satPrefetch(lat, lng, alt) {
    const mpp = mppAt(alt), z = tileZ(mpp, lat), n = 2 ** z;
    const px = (256 * 156543.03 * Math.cos((lat * Math.PI) / 180)) / n / mpp;      // a tile's size on screen there
    const kx = globe.width() / 2 / px + 0.5, ky = globe.height() / 2 / px + 0.5, cx = tileX(lng, z), cy = tileY(lat, z);
    for (let x = Math.floor(cx - kx); x <= Math.floor(cx + kx); x++) {
      for (let y = Math.max(0, Math.floor(cy - ky)); y <= Math.min(n - 1, Math.floor(cy + ky)); y++) new Image().src = SAT_URL(z, ((x % n) + n) % n, y);
    }
  }
  // SEE THE SPOT ON SATELLITE in a post: the satellite map at that spot's rounded point, at about 12 m a px
  function seeSpot(lat, lng) {
    lastFocus = null;
    leavePost(() => {
      if (scrollY > 0) scrollTo({ top: 0, behavior: reduceMotion ? "auto" : "smooth" });
      flyTo(r3(lat), r3(lng), (12 / SAT_MPX) * satMin(), () => {
        if (document.activeElement === document.body && !satBar.hidden) $("#satBack").focus();
      });
    });
  }
  // a mouse over a receipt's mark on the map: the hand, as over a dot on the globe
  el.addEventListener("pointermove", (ev) => {
    if (!satMarks || ev.pointerType !== "mouse") return;
    const box = el.getBoundingClientRect();
    canvas.style.cursor = receiptsNear(ev.clientX - box.left, ev.clientY - box.top, markR + 3).length ? "pointer" : "";
  });

  // don't burn battery while the globe is offscreen
  new IntersectionObserver(([en]) => {
    onScreen = en.isIntersecting;
    if (onScreen) { globe.resumeAnimation(); tidySoon(); swayOn(); } else { flingStop(); globe.pauseAnimation(); }
  }).observe(el);

  // keep canvas sized to the hero. The tag groups depend on its height, so they follow it, and so do the
  // satellite map and its deepest zoom.
  const size = () => {
    globe.width(el.clientWidth).height(el.clientHeight);
    relayout(globe.pointOfView().altitude);
    tidySoon();
    setMin();
    satFrame(globe.pointOfView());
  };
  size();
  new ResizeObserver(size).observe(el);
})();

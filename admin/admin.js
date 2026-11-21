/* Sapu Earth review page. Talks to /api/admin/* with the admin token (kept in localStorage on this device). */
(function () {
  "use strict";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const SITE = "https://sapu.earth";
  const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ESC[c]);
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* ignore */ } },
    del(k) { try { localStorage.removeItem(k); } catch { /* ignore */ } },
  };
  // Media URLs come from our own API (short-lived signed links), but check anyway before putting them in src/href.
  const safeMedia = (u) => (typeof u === "string" && /^\/media\/[0-9a-f]{32}\?exp=\d{10}&sig=[0-9a-f]{64}$/.test(u) ? u : "");
  const n = (v) => (v === null || v === undefined || v === "" ? "" : String(v));
  const fmt = (v) => (v === null || v === undefined ? "?" : Number(v).toLocaleString("en", { maximumFractionDigits: 2 }));
  const isNum = (v) => v !== null && v !== undefined && v !== "" && Number.isFinite(Number(v));
  const cents = (v) => Math.round(Number(v) * 100) / 100;
  // "EUR 30" or "EUR 30.50"
  const eur = (v) => {
    if (!isNum(v)) return "EUR ?";
    const x = cents(v);
    const whole = Math.round(x * 100) % 100 === 0;
    return "EUR " + x.toLocaleString("en", { minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: 2 });
  };
  // The public mission number, digits only (it goes into links), or "" if it cannot be read.
  const missionNo = (m) => { const v = Number(m && m.no); return Number.isInteger(v) && v > 0 ? String(v) : ""; };
  // A mission or cleanup with several spots (docs/missions.md, Spots): the server's spots, spot 1 first, [{no, place_name,
  // lat, lng, date}], or [] for one spot. lastDay: the last of their days, the day LATE and OVERDUE count from.
  const spotsOf = (x) => (x && Array.isArray(x.spots) && x.spots.length > 1 ? x.spots.filter((s) => s && Number.isInteger(s.no)) : []);
  const lastDay = (m) => [n(m.plan_date), ...spotsOf(m).map((s) => n(s.date))].filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort().pop() || n(m.plan_date);
  // "Spot 2" rows: the place, the day and the map link of each spot.
  const spotKv = (x) => spotsOf(x).map((s) => `<dt>Spot ${esc(s.no)}</dt><dd>${esc(s.place_name)} · ${esc(s.date)} · ${osm(s)}</dd>`).join("");
  const missionLink = (no) => `${SITE}/m/${no}`;
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
  // A price as /admin/ writes it (fmt, the currency once): "IDR 3,000,000 in all: crew pay 15 × 100,000 = 1,500,000
  // (50%), other costs 1,500,000". share: the crew's part in percent. each false: never a pay for each person (a
  // cleanup's own costs: APPROVE can change its crew size, not its money). odd: "about 6,666.67 each" when the crew's pay
  // does not split evenly (typed as one total, like mission #2), else "". null when the numbers do not fit together.
  function payText(cur, price, crew, people, { share = false, each = true } = {}) {
    if (!isNum(price) || !isNum(crew)) return null;
    const p = Number(price), c = Number(crew), k = Number(people), s = splitOf(p, c, k);
    if (!s) return null;
    const who = s.each !== null ? ` for ${fmt(k)} ${k === 1 ? "person" : "people"}` : "";
    const odd = each && c > 0 && s.each !== null && !s.exact ? `about ${fmt(s.each)} each` : "";
    const notes = [odd, share && c > 0 && p > 0 ? `${Math.round((c / p) * 100)}%` : ""].filter(Boolean);
    const pay = c === 0 ? "no crew pay" : each && s.exact ? `crew pay ${fmt(k)} × ${fmt(s.each)} = ${fmt(c)}` : `crew pay ${fmt(c)}${who}`;
    return { text: `${n(cur) || "?"} ${fmt(p)} in all: ${pay}${notes.length ? ` (${notes.join(", ")})` : ""}, ${s.other > 0 ? `other costs ${fmt(s.other)}` : "no other costs"}`, odd };
  }
  // What a mission's removal deletes and its PUBLISH makes public: its photos, and its video when it has one.
  const nowWhat = (m) => (m && m.now_video ? "photos and video" : "photos");
  // A video player that loads only when played: a list of many would otherwise fetch about 3 ranges each at
  // once and pass the rate limit rule (100 requests in 10 s), which then blocks the admin for 10 s.
  const player = (u) => `<video controls playsinline preload="none" src="${esc(u)}"></video>`;
  // A cleanup's videos (media.videos, in the server's order: before, after, then those without a stage, each in upload
  // order), each with its title and its download name: VIDEO BEFORE and video-before for the one video before the
  // cleanup, numbered when there are several (VIDEO BEFORE 1/30, video-before-1), so no two files save under one name;
  // the same for VIDEO AFTER; and VIDEO for one sent without a stage (before the two video fields, or before migration
  // 0005), whose download names are always numbered (video-1). Since 2026-11-19 a cleanup takes up to 30 of each stage.
  function videoRows(videos) {
    const list = Array.isArray(videos) ? videos : [];
    const stage = (v) => (v && (v.stage === "before" || v.stage === "after") ? v.stage : null);
    const all = list.map(stage), seen = { before: 0, after: 0, none: 0 };
    return list.map((v, i) => {
      const st = all[i], k = st || "none", n = all.filter((x) => x === st).length, no = ++seen[k];
      const title = st === "before" ? "VIDEO BEFORE" : st === "after" ? "VIDEO AFTER" : "VIDEO";
      return { v, title: n > 1 ? `${title} ${no}/${n}` : title, dl: st && n === 1 ? `video-${st}` : `video${st ? "-" + st : ""}-${no}` };
    });
  }

  let token = store.get("sapu-admin-token") || "";
  let tab = "pending";

  // ---------- auth ----------
  function showLogin(msg) {
    $("#app").hidden = true;
    $("#logout").hidden = true;
    $("#login").hidden = false;
    $("#loginErr").textContent = msg || "";
    $("#login").elements.token.focus();
  }
  $("#login").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    token = $("#login").elements.token.value.trim();
    $("#login").elements.token.value = "";
    try {
      await api("/api/admin/partners");
    } catch (e) {
      return showLogin(e.message);
    }
    store.set("sapu-admin-token", token);
    openApp();
  });
  $("#logout").addEventListener("click", () => { store.del("sapu-admin-token"); token = ""; showLogin(); });

  async function api(path, body) {
    const r = await fetch(path, {
      method: body ? "POST" : "GET",
      headers: { Authorization: "Bearer " + token, ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      cache: "no-store",
    });
    let data = null;
    try { data = await r.json(); } catch { /* not JSON */ }
    if (r.status === 401) {
      store.del("sapu-admin-token");
      const e = new Error("That token was not accepted.");
      showLogin(e.message);
      throw e;
    }
    if (!r.ok) {
      const e = new Error((data && data.error) || "HTTP " + r.status);
      e.code = data && data.code;
      throw e;
    }
    return data;
  }

  function flash(text, ok = true) {
    const f = $("#flash");
    f.className = "msg " + (ok ? "ok" : "err");
    f.textContent = text;
  }

  function copy(text, btn) {
    const done = () => { const o = btn.textContent; btn.textContent = "COPIED"; setTimeout(() => (btn.textContent = o), 1500); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, () => prompt("Copy this:", text));
    else prompt("Copy this:", text);
  }

  // ---------- tabs ----------
  function openApp() {
    $("#login").hidden = true;
    $("#app").hidden = false;
    $("#logout").hidden = false;
    render();
    refreshAppCount();
    refreshMissionCount();
    refreshPartnerCount();
  }
  $$("[data-tab]").forEach((b) => b.addEventListener("click", () => {
    tab = b.dataset.tab;
    $$("[data-tab]").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
    flash("");
    render();
  }));

  async function render() {
    const view = $("#view");
    view.innerHTML = '<p class="hint">Loading…</p>';
    try {
      // await, so a failed request lands in the catch below instead of leaving "Loading…"
      if (tab === "partners") return await renderPartners(view);
      if (tab === "applications") return await renderApplications(view);
      if (tab === "missions") return await renderMissions(view);
      const shown = tab;
      const { submissions, thanks_days: days, thanks_caps: caps } = await api("/api/admin/submissions?status=" + tab);
      // THANKS BY DAY above the APPROVED cards, while a day of the last 7 has thanks or an undo (only with migration 0007).
      const daysBox = tab === "approved" && Array.isArray(days) && days.length && caps ? thanksDaysBox(days, caps) : null;
      if (!submissions.length) {
        view.innerHTML = `<p class="hint">${tab === "pending" ? "Nothing waiting for review." : "Nothing approved yet."}</p>`;
        if (daysBox) view.prepend(daysBox);
        return;
      }
      const missions = await missionsFor(submissions, tab === "pending" ? "funded" : "done");
      if (tab !== shown) return; // another tab was opened meanwhile
      view.innerHTML = "";
      if (daysBox) view.append(daysBox);
      for (const s of submissions) {
        const mis = missionOf(s, missions);
        view.append(tab === "pending" ? pendingCard(s, mis, linkable(s, missions)) : approvedCard(s, mis));
      }
    } catch (e) {
      view.innerHTML = `<p class="msg err">${esc(e.message)}</p>`;
    }
  }

  // ---------- approved: THANKS BY DAY (docs/upload-flow.md, Thanks) ----------
  // One row per UTC day of the last 7 with thanks or an undo (thanks_days in GET /api/admin/submissions?status=approved):
  // the day's standing count and the receipt with the most, or what the undos took off, with UNDO ON THAT RECEIPT (the
  // top one; once it is undone, the next one is the top) and UNDO THE WHOLE DAY. Both ask first, take thanks off the
  // receipts for good (POST /api/admin/thanks/undo), then the list is drawn again. caps: thanks_caps, for the hint.
  const utcDay = (day) => new Date(Date.parse(day + "T00:00:00Z")).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
  // "1 thank you", "702 thanks": a number of thanks in the texts below.
  const nThanks = (n) => (n === 1 ? "1 thank you" : `${fmt(n)} thanks`);
  function thanksDaysBox(days, caps) {
    const box = document.createElement("section");
    box.className = "panel am-thanksdays";
    const row = (d) => {
      const when = `<b>${esc(utcDay(d.day))}</b>`;
      if (d.closed) return `<li><span>${when}: undone, ${esc(nThanks(d.taken))} taken off.</span></li>`;
      if (!(d.n > 0)) return `<li><span>${when}: ${esc(nThanks(d.taken))} taken off.</span></li>`;
      const top = d.top && d.top.n > 0 ? d.top : null;
      return `<li><span>${when}: ${esc(nThanks(d.n))}${top ? `, the most on ${esc(top.place_name)} (${esc(fmt(top.n))})` : ""}.` +
        `${d.full ? " The daily cap is reached." : ""}${d.taken > 0 ? ` ${esc(nThanks(d.taken))} already taken off.` : ""}</span>` +
        (top ? `<button type="button" class="b b-sm b-red" data-undo-receipt="${esc(top.id)}" data-day="${esc(d.day)}">UNDO ON THAT RECEIPT</button>` : "") +
        `<button type="button" class="b b-sm b-red" data-undo-day="${esc(d.day)}">UNDO THE WHOLE DAY</button></li>`;
    };
    box.innerHTML = `
      <h2 class="panel-title">THANKS BY DAY (UTC)</h2>
      <ul class="am-tdays">${days.map(row).join("")}</ul>
      <p class="hint">One tap under a receipt is one thank you. A receipt counts at most ${esc(fmt(caps.receipt))} a day and the whole site ${esc(fmt(caps.site))} (UTC days), and thanks taken off still count toward that day's caps. UNDO ON THAT RECEIPT takes that receipt's thanks of that day off for good, and that receipt takes no more thanks that day. UNDO THE WHOLE DAY takes all thanks of that day off the receipts for good, and nobody can thank on sapu.earth for the rest of that day. Use them only for a day that looks inflated, never to change a crew's numbers otherwise. A day with ${esc(fmt(caps.busy_site))} or more thanks in all, or ${esc(fmt(caps.busy_receipt))} or more on one receipt, also comes up in the GitHub note.</p>
      <div class="msg err" data-tdays-err></div>`;
    box.addEventListener("click", async (ev) => {
      const btn = ev.target.closest("[data-undo-receipt], [data-undo-day]");
      if (!btn) return;
      const day = btn.dataset.day || btn.dataset.undoDay;
      const d = days.find((x) => x.day === day);
      if (!d) return;
      const id = btn.dataset.undoReceipt || null;
      const when = utcDay(day);
      const place = id && d.top ? d.top.place_name : "";
      if (!confirm(id
        ? `Take the ${nThanks(d.top.n)} of ${when} off ${place}? This cannot be undone, and that receipt takes no more thanks that day (UTC).`
        : `Take ${d.n === 1 ? "the 1 thank you" : `all ${fmt(d.n)} thanks`} of ${when} off the receipts? This cannot be undone, and nobody can thank on sapu.earth for the rest of that day (UTC).`)) return;
      $$("button", box).forEach((b) => (b.disabled = true));
      try {
        const r = await api("/api/admin/thanks/undo", id ? { day, id } : { day });
        const was = r.taken === 1 ? "was" : "were";
        flash(id ? `The ${nThanks(r.taken)} of ${when} ${was} taken off ${place}.` : `The ${nThanks(r.taken)} of ${when} ${was} taken off the receipts.`);
        render();
      } catch (e) {
        $("[data-tdays-err]", box).textContent = e.message;
        $$("button", box).forEach((b) => (b.disabled = false));
      }
    });
    return box;
  }

  // ---------- shared card bits ----------
  // Post links (docs/upload-flow.md, Post links and thanks): only the stored forms of functions/_lib/social.js.
  const POST_URL_RE = /^https:\/\/www\.(?:instagram\.com\/(?:p|reel)\/[A-Za-z0-9_-]{5,40}\/|tiktok\.com\/@[A-Za-z0-9._]{2,24}\/(?:video|photo)\/\d{8,25})$/;
  const safePost = (u) => (typeof u === "string" && POST_URL_RE.test(u) ? u : "");
  const siteOf = (u) => (/^https:\/\/www\.tiktok\.com\//.test(u) ? "tiktok" : "instagram");
  const siteName = (u) => (siteOf(u) === "tiktok" ? "TikTok" : "Instagram");
  const postHost = (u) => String(u).replace(/^https:\/\/www\./, "");
  // OPEN POST before SAVE: an https link on instagram.com or tiktok.com (www., m. or bare), or a TikTok short link, which
  // opens the post so its full address can be copied. A paste without https:// gets it; no login, no port.
  const OPENABLE_HOST = /^(?:(?:www\.|m\.)?(?:instagram|tiktok)\.com|v[mt]\.tiktok\.com)$/;
  const openable = (v) => {
    const s = /^(?:(?:www\.|m\.)?(?:instagram|tiktok)\.com|v[mt]\.tiktok\.com)\//i.test(v) ? "https://" + v : v;
    try { const x = new URL(s); return x.protocol === "https:" && OPENABLE_HOST.test(x.hostname) && !x.username && !x.password && !x.port ? x.href : ""; } catch { return ""; }
  };
  const showsLine = (social) => (social ? `The receipt shows COMMENTS ON ${social.site === "tiktok" ? "TIKTOK" : "INSTAGRAM"}, to ${social.by === "sapu" ? "your" : "the crew's"} post.` : "The receipt shows no comments link.");
  // mis: the cleanup's mission, if any. Its "now" photos go in front of the before photos, and its video of
  // the spot in front of the cleanup's videos. Each video has its own title (videoRows): VIDEO BEFORE and VIDEO AFTER,
  // numbered when a stage has several (VIDEO BEFORE 1/3), or VIDEO for one sent without a stage. Each title stands with
  // its player, and more than two of them stand in cells side by side (.media-vgrid, admin.css), so a card with 61
  // players stays a few screens long; one or two keep the card's whole width.
  function mediaBlock(s, mis) {
    const imgs = (list) => list.map((m) => safeMedia(m && m.url))
      .filter(Boolean).map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener"><img src="${esc(u)}" alt="" loading="lazy"></a>`).join("") || '<p class="hint">none</p>';
    const titled = (label, url) => { const u = safeMedia(url); return u ? `<div><h4>${esc(label)}</h4>${player(u)}</div>` : ""; };
    const cells = [mis && mis.now_video ? titled(`VIDEO NOW, #${missionNo(mis)}`, mis.now_video.url) : "",
      ...videoRows(s.media.videos).map((r) => titled(r.title, r.v && r.v.url))].filter(Boolean);
    const vids = cells.join(""), vbox = `media-v${cells.length > 2 ? " media-vgrid" : ""}`;
    const now = mis && Array.isArray(mis.now) ? mis.now : [];
    // Several spots: the before and the after photos of each spot side by side, spot by spot, under the NOW photos.
    const spots = spotsOf(s);
    if (spots.length) {
      const of = (list, k) => list.filter((p) => (Number.isInteger(p && p.spot) ? p.spot : 1) === k);
      const pairs = spots.map((sp) => {
        const b = of(s.media.before, sp.no), a = of(s.media.after, sp.no);
        return `<div><h4>BEFORE, SPOT ${esc(sp.no)} (${b.length})</h4>${imgs(b)}</div><div><h4>AFTER, SPOT ${esc(sp.no)} (${a.length})</h4>${imgs(a)}</div>`;
      }).join("");
      return `
      ${now.length ? `<div class="media-ba"><div><h4>NOW, #${esc(missionNo(mis))} (${now.length})</h4>${imgs(now)}</div></div>` : ""}
      <div class="media-ba">${pairs}</div>
      ${vids ? `<div class="${vbox}">${vids}</div>` : ""}`;
    }
    return `
      <div class="media-ba${now.length ? " has-now" : ""}">
        ${now.length ? `<div><h4>NOW, #${esc(missionNo(mis))} (${now.length})</h4>${imgs(now)}</div>` : ""}
        <div><h4>BEFORE (${s.media.before.length})</h4>${imgs(s.media.before)}</div>
        <div><h4>AFTER (${s.media.after.length})</h4>${imgs(s.media.after)}</div>
      </div>
      ${vids ? `<div class="${vbox}">${vids}</div>` : ""}`;
  }
  function osm(s) {
    if (!isNum(s.lat) || !isNum(s.lng)) {
      return `<a href="https://www.openstreetmap.org/search?query=${encodeURIComponent(s.place_name || "")}" target="_blank" rel="noopener">no coordinates, find on map ↗</a>`;
    }
    const lat = Number(s.lat).toFixed(5), lng = Number(s.lng).toFixed(5);
    return `<a href="https://www.openstreetmap.org/?mlat=${lat}&amp;mlon=${lng}#map=17/${lat}/${lng}" target="_blank" rel="noopener">${lat}, ${lng} ↗</a>`;
  }
  function facts(s) {
    // The cleanup's own costs as the crew page added them up: what each person got × the crew size it was sent with,
    // plus the other costs. Never as a pay for each person: APPROVE can change the crew size, not the money. A row with
    // one amount only (a crew pay without a total) keeps the plain text.
    const own = payText(s.currency, s.total_cost_local, s.crew_pay_local, s.crew_size, { each: false });
    const money = own ? esc(own.text) : s.currency || s.total_cost_local !== null || s.crew_pay_local !== null
      ? `${esc(s.currency || "?")} ${esc(fmt(s.total_cost_local))} total, ${esc(fmt(s.crew_pay_local))} to the crew` : "not given";
    const eur = s.paid_eur !== null ? `€${esc(fmt(s.paid_eur))} paid, €${esc(fmt(s.crew_eur))} crew, €${esc(fmt(s.ops_eur))} ops` : "";
    return `
      <dl class="kv">
        <dt>Place</dt><dd>${esc(s.place_name)} · ${esc(s.country || "??")}</dd>
        ${spotsOf(s).length ? spotKv(s) : `<dt>Map</dt><dd>${osm(s)}</dd>
        <dt>Date</dt><dd>${esc(s.cleanup_date)}</dd>`}
        <dt>Kg</dt><dd>${esc(fmt(s.kg))}</dd>
        <dt>Sacks</dt><dd>${esc(fmt(s.sacks))}</dd>
        <dt>Crew</dt><dd>${esc(s.crew_size)} people${s.hours !== null ? `, ${esc(fmt(s.hours))} h` : ""}</dd>
        <dt>Disposal</dt><dd>${esc(s.disposal || "not given")}</dd>
        <dt>Local money</dt><dd>${money}</dd>
        ${eur ? `<dt>EUR</dt><dd>${eur}</dd>` : ""}
        <dt>Notes (public)</dt><dd>${esc(s.notes || "")}</dd>
        ${s.private_note ? `<dt>Private message</dt><dd class="private">${esc(s.private_note)}</dd>` : ""}
        <dt>Consent</dt><dd>${s.consent ? "yes" : "NO"}</dd>
        ${s.review_note ? `<dt>Review note</dt><dd>${esc(s.review_note)}</dd>` : ""}
      </dl>`;
  }
  // same_files (the cleanup's before photos and videos that are another mission's photo or video of the spot, the same
  // files, api/admin/submissions.js) as one red line: "Its before photo and video are the same files as mission #4's. Is
  // this the cleanup for mission #4?", or for several missions "... as those of missions #4 and #5. Which mission is this
  // cleanup for?". "" without any.
  function sameFilesLine(list) {
    const by = new Map();
    for (const f of Array.isArray(list) ? list : []) {
      const no = missionNo(f);
      if (!no || !(f.kind === "photo" || f.kind === "video")) continue;
      if (!by.has(no)) by.set(no, new Set());
      by.get(no).add(f.kind);
    }
    if (!by.size) return "";
    const kinds = new Set([...by.values()].flatMap((k) => [...k]));
    const both = kinds.size === 2;
    const what = both ? "photo and video are the same files" : `${[...kinds][0]} is the same file`;
    if (by.size === 1) {
      const [no] = by.keys();
      return `Its before ${what} as mission #${no}'s. Is this the cleanup for mission #${no}?`;
    }
    const nos = [...by.keys()].map((no) => "#" + no);
    return `Its before ${both ? "photos and videos are" : kinds.has("video") ? "videos are" : "photos are"} the same files as those of missions ${nos.slice(0, -1).join(", ")} and ${nos[nos.length - 1]}. Which mission is this cleanup for?`;
  }
  function head(s, mis) {
    const dupes = Array.isArray(s.possible_duplicates) ? s.possible_duplicates : [];
    const same = sameFilesLine(s.same_files);
    const no = missionNo(mis);
    const badge = no ? `<span class="am-badge">MISSION #${esc(no)}</span>` : s.mission_id ? '<span class="am-badge">MISSION</span>' : "";
    return `${badge}<h3>${esc(s.place_name)}</h3>
      <div class="sub-meta">${esc(s.partner_name)} · cleanup ${esc(s.cleanup_date)} · sent ${esc((s.created_at || "").slice(0, 16).replace("T", " "))} · ${esc(s.id.toUpperCase())}</div>
      ${dupes.length ? `<p class="msg err">Possible duplicate of ${dupes.map((d) => esc(String(d).toUpperCase())).join(", ")} (same partner, date and place).</p>` : ""}
      ${same ? `<p class="msg err">${esc(same)}</p>` : ""}`;
  }

  // A cleanup sent for a mission carries mission_id. Its mission comes with the submission (s.mission)
  // or, if the list has no such block, from the missions list (funded for PENDING, done for APPROVED).
  // PENDING also loads the funded list when a cleanup came without a mission and its partner has one
  // to link, for the money, task and now photos under "Link to mission".
  const missionOf = (s, byId) => (s.mission && typeof s.mission === "object" ? s.mission : (s.mission_id && byId[s.mission_id]) || null);
  async function missionsFor(subs, status) {
    const need = subs.some((s) => s.mission_id && !(s.mission && typeof s.mission === "object")) ||
      (status === "funded" && subs.some((s) => !s.mission_id && (!Array.isArray(s.partner_missions) || s.partner_missions.length)));
    if (!need) return {};
    const byId = {};
    try {
      const r = await api("/api/admin/missions?status=" + status);
      for (const m of (r && Array.isArray(r.missions) ? r.missions : [])) byId[m.id] = m;
    } catch { /* only extra detail: the cards still show without the mission block */ }
    return byId;
  }
  // The partner's funded missions with no pending or approved cleanup yet, soonest planned day first.
  // PENDING offers them under "Link to mission" when the crew sent a cleanup without a mission.
  // The server lists them (partner_missions); the funded list adds the money, task and now photos.
  const linkable = (s, byId) => {
    if (s.mission_id) return [];
    const base = Array.isArray(s.partner_missions) ? s.partner_missions
      : Object.values(byId).filter((m) => m && m.partner_id === s.partner_id && m.status === "funded" && !m.pending_submission && !m.submission_id);
    return base.filter((m) => m && typeof m.id === "string" && missionNo(m)).map((m) => ({ status: "funded", ...(byId[m.id] || {}), ...m }));
  };
  // The mission block on PENDING and APPROVED cards: task and the agreed money.
  function missionFacts(s, mis, pending) {
    if (!mis) {
      return s.mission_id && pending
        ? '<p class="msg err">Sent for a mission that is not funded any more (cancelled or removed). Check before approving.</p>' : "";
    }
    const no = missionNo(mis);
    const adv = isNum(mis.advance_eur) ? Number(mis.advance_eur) : 0;
    const agreed = isNum(mis.funded_eur)
      ? `${esc(eur(mis.funded_eur))} (${adv > 0 ? `advance ${esc(eur(adv))}` : "no advance"})` : "not funded";
    const gone = pending && mis.status && mis.status !== "funded";
    // A removed mission (cancelled, deactivated) keeps its money columns, but only the advance went out.
    const sent = mis.status === "removed" ? (adv > 0 ? ` Only the advance (${eur(adv)}) was sent.` : " No advance was sent.") : "";
    const what = [`#${no}`, n(mis.place_name), mis.plan_date ? `planned ${mis.plan_date}` : "", mis.status ? mis.status : ""].filter(Boolean);
    // What the crew asked when it posted the mission, as it adds up (the receipt shows it as ASKED, CREW PAY, OTHER COSTS).
    const asked = payText(mis.currency, mis.price_local, mis.crew_local, mis.crew_size);
    return `
      ${gone ? `<p class="msg err">Mission #${esc(no)} is ${esc(mis.status)}, not funded any more. Approving publishes the cleanup but does not mark the mission done.${esc(sent)}</p>` : ""}
      <dl class="kv am-facts">
        <dt>Mission</dt><dd>${esc(what.join(", "))}</dd>
        ${spotsOf(mis).length ? `<dt>Spots</dt><dd>${spotsOf(mis).map((x) => `${esc(x.no)}: ${esc(x.place_name)}, ${esc(x.date)}`).join("<br>")}</dd>` : ""}
        <dt>Task</dt><dd>${esc(mis.task || "")}</dd>
        ${asked ? `<dt>Asked</dt><dd>${esc(asked.text)}</dd>` : ""}
        <dt>Agreed</dt><dd>${agreed}</dd>
      </dl>
      ${pending && no && !gone ? `<p class="hint">The crew was asked to hold up a paper with #${esc(no)} on it in one before photo${spotsOf(mis).length ? " at each spot" : ""}. APPROVE marks the mission done.</p>` : ""}`;
  }

  // ---------- pending ----------
  // "#3 Pantai Kuta, day 2026-11-20, EUR 120" for the Link to mission list.
  const linkLabel = (m) => [`#${missionNo(m)} ${n(m.place_name)}`, m.plan_date ? `day ${m.plan_date}` : "", isNum(m.funded_eur) ? eur(m.funded_eur) : ""]
    .filter(Boolean).join(", ");
  const linkHint = (count) => `This crew has ${count === 1 ? "a funded mission" : `${count} funded missions`} with no cleanup yet. ` +
    `If this cleanup is for ${count === 1 ? "it" : "one of them"}, link it here. APPROVE then marks that mission done.`;

  // A mission just linked to a cleanup leaves the Link to mission list of the other PENDING cards.
  function unlinkable(id) {
    for (const sel of $$('.am-linkbox select[name="mission_id"]', $("#view"))) {
      const o = [...sel.options].find((x) => x.value === id);
      if (!o) continue;
      const was = o.selected;
      o.remove();
      const box = sel.closest(".am-linkbox");
      const left = sel.options.length - 1; // minus "No mission"
      if (left > 0) $("[data-link-hint]", box).textContent = linkHint(left);
      else box.hidden = true;
      if (was) sel.dispatchEvent(new Event("change"));
    }
  }

  // THE CREW'S POST on PENDING: the link the crew sent with the cleanup, to open before approving, and REMOVE LINK.
  // Outside the decide form, with its own listener. Nothing without a crew link (or before migration 0007).
  function crewPostBox(s) {
    const url = safePost(s.post_links && s.post_links.crew);
    if (!url) return "";
    const site = siteName(url);
    return `
      <div class="am-postbox" data-crewpost>
        <div class="panel-title">THE CREW'S POST</div>
        <p class="am-postlink"><a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(postHost(url))} ↗</a></p>
        <p class="hint">The crew linked its own post on ${site}. Once you approve, the receipt's COMMENTS ON ${site.toUpperCase()} button leads to it, unless you add your own post on the APPROVED card. Open it first: remove the link if the post asks for money, shows people who did not agree, or is not about this cleanup, and tell the crew why on WhatsApp.</p>
        <div class="btn-row"><button type="button" class="b b-sm b-ghost" data-post="remove-crew">REMOVE LINK</button></div>
        <div class="msg err" data-post-err></div>
      </div>`;
  }
  function wireCrewPostBox(el, s) {
    const box = $("[data-crewpost]", el);
    if (!box) return;
    box.addEventListener("click", async (ev) => {
      const btn = ev.target.closest('[data-post="remove-crew"]');
      if (!btn || !confirm("Take the link to the crew's post off this cleanup? It cannot be added back.")) return;
      btn.disabled = true;
      $("[data-post-err]", box).textContent = "";
      try {
        const r = await api("/api/admin/post-link", { id: s.id, slot: "crew", url: null });
        s.post_links = r.post_links;
        $(".am-postlink", box).textContent = "Removed. The receipt will not link the crew's post. Tell the crew why on WhatsApp.";
        btn.closest(".btn-row").remove();
      } catch (e) {
        $("[data-post-err]", box).textContent = e.message;
        btn.disabled = false;
      }
    });
  }

  // REJECT on PENDING opens a ready reply to the crew, in English or Indonesian: what comes off and why (the reasons
  // Marcus ticks), how to send the cleanup again, and that they can ask us to look again. It is the statement of reasons
  // the DSA asks for when something a crew sent comes off (docs/upload-flow.md, Reports of illegal content (DSA)). The
  // button names are the crew page's own (upload/upload.js T: card_send, plain_btn, send); tests/e2e.sh checks that they
  // match. "paper" is only offered for a cleanup sent for a mission.
  const REJECT_WHY = [
    { key: "child", label: "A photo or video shows a child",
      en: "A photo or video shows a child. The crew and everyone in the photos must be adults (18 or older).",
      id: "Ada foto atau video yang memperlihatkan anak-anak. Kru dan semua orang yang tampil di foto harus orang dewasa (18 tahun ke atas)." },
    { key: "face", label: "It shows the face of someone not on the crew",
      en: "A photo or video shows the face of someone who is not on the crew, like a person passing by.",
      id: "Ada foto atau video yang memperlihatkan wajah orang yang bukan anggota kru, misalnya orang yang lewat." },
    { key: "spot", label: "Before and after are not the same spot",
      en: "The before and after photos do not show the same spot. Take them from the same spot and the same angle.",
      id: "Foto sebelum dan sesudah tidak memperlihatkan tempat yang sama. Ambil fotonya dari tempat dan sudut yang sama." },
    { key: "paper", mission: true, label: (no) => `No before photo shows the paper with #${no}`,
      en: (no) => `No before photo shows the paper with #${no} on it.`,
      id: (no) => `Tidak ada foto sebelum yang memperlihatkan kertas bertuliskan #${no}.` },
    { key: "dark", label: "The photos are too dark or blurry",
      en: "The photos are too dark or too blurry to see the trash.",
      id: "Fotonya terlalu gelap atau buram, jadi sampahnya tidak terlihat jelas." },
  ];
  const whyText = (r, k, no) => (typeof r[k] === "function" ? r[k](no) : r[k]);
  // why: the keys of the ticked reasons. With none ticked, the message says the reason follows in the next message.
  // A cleanup for a mission that is no longer funded (cancelled meanwhile) cannot be sent for it again: no resend line.
  function cleanupRejectText(lang, s, mis, why) {
    const name = (s.contact && n(s.contact.contact_name)) || s.partner_name || "";
    const no = missionNo(mis);
    const funded = !!no && (!mis.status || mis.status === "funded");
    const videos = !!(s.media && Array.isArray(s.media.videos) && s.media.videos.length);
    const lines = REJECT_WHY.filter((r) => why.includes(r.key) && (!r.mission || no)).map((r) => "- " + whyText(r, lang, no));
    const resend = !no || funded;
    if (lang === "id") {
      return `Halo ${name}, terima kasih sudah mengirim laporan aksi bersih ${no ? `untuk misi #${no} (${s.place_name})` : `di ${s.place_name}`}. ` +
        (videos ? "Laporan ini belum bisa kami tampilkan di sapu.earth, jadi laporan ini beserta foto dan videonya akan kami hapus."
          : "Laporan ini belum bisa kami tampilkan di sapu.earth, jadi laporan ini dan fotonya akan kami hapus.") +
        (lines.length ? `\n\nAlasannya:\n${lines.join("\n")}\n\n` : " Alasannya saya jelaskan di pesan berikutnya.\n\n") +
        (resend ? `${funded ? `Misi #${no} tetap didanai. ` : ""}Tolong kirim laporannya lagi: buka halaman kru kalian (link pribadi yang kami kirim), ` +
          `tekan ${funded ? `LAPOR AKSI BERSIH #${no}` : "LAPOR AKSI BERSIH TANPA MISI"}, tambahkan lagi ${videos ? "foto, video, dan jumlah karungnya" : "foto dan jumlah karungnya"}, lalu tekan KIRIM LAPORAN.\n` : "") +
        "Kalau menurut kalian kami salah, balas pesan ini dan jelaskan alasannya, nanti kami cek lagi.\nMarcus, Sapu Earth";
    }
    return `Hi ${name}, thank you for sending the cleanup ${no ? `for mission #${no} (${s.place_name})` : `at ${s.place_name}`}. ` +
      (videos ? "We can't put it on sapu.earth as it is, so we will delete it, with its photos and videos."
        : "We can't put it on sapu.earth as it is, so we will delete it and its photos.") +
      (lines.length ? `\n\nWhy:\n${lines.join("\n")}\n\n` : " I explain why in my next message.\n\n") +
      (resend ? `${funded ? `Mission #${no} stays funded. ` : ""}Please send it again: open your crew page (the private link we sent you), ` +
        `tap ${funded ? `SEND A CLEANUP FOR #${no}` : "SEND A CLEANUP WITHOUT A MISSION"}, add the ${videos ? "photos, the videos" : "photos"} and the number of sacks again, and tap SEND CLEANUP.\n` : "") +
      "If you think we got it wrong, reply here and tell us why, and we will look at it again.\nMarcus, Sapu Earth";
  }

  // links: the partner's funded missions this cleanup can be linked to (only when it came without one).
  function pendingCard(s, mis, links = []) {
    const el = document.createElement("article");
    el.className = "sub-card";
    // A mission that is still funded prefills what we pay with the agreed amount. A removed one does
    // not: only its advance was sent, so Marcus types what was really paid.
    const agreed = mis && mis.status === "funded" && isNum(mis.funded_eur) ? cents(mis.funded_eur) : null;
    const paid = isNum(s.paid_eur) ? s.paid_eur : agreed;
    // A cleanup sent without a location takes the point of its mission, so the receipt still gets its dot
    // on the globe (crews often send from home, and "Use my location now" is only for the spot itself).
    // Rounded to 3 decimals (about 100 m, round3 in functions/_lib/events.js), what the globe shows anyway:
    // an exact mission point is private and wiped when the mission is removed, so it must never be copied
    // into a cleanup that would keep it (UNPUBLISH, or a CANCEL from another tab while this card is open).
    const r3 = (v) => Math.round(Number(v) * 1000) / 1000;
    const pointOf = (m) => (m && isNum(m.lat) && isNum(m.lng) ? { lat: r3(m.lat), lng: r3(m.lng), no: missionNo(m) } : null);
    const ownPoint = isNum(s.lat) && isNum(s.lng);
    const misPoint = ownPoint ? null : pointOf(mis);
    const linkBox = links.length ? `
        <div class="am-linkbox">
          <div class="panel-title">MISSION</div>
          <p class="hint" data-link-hint>${esc(linkHint(links.length))}</p>
          <label class="field wide"><span>Link to mission</span><select name="mission_id">
            <option value="">No mission</option>
            ${links.map((m) => `<option value="${esc(m.id)}">${esc(linkLabel(m))}</option>`).join("")}
          </select></label>
          <div data-link-facts></div>
        </div>` : "";
    el.innerHTML = `${head(s, mis)}${mediaBlock(s, mis)}${missionFacts(s, mis, true)}${facts(s)}${crewPostBox(s)}
      <form class="decide" novalidate>${linkBox}
        <div class="panel-title" style="margin-top:12px">EDIT IF NEEDED</div>
        <p class="hint" data-pt-hint hidden></p>
        <p class="hint" data-crew-hint hidden></p>
        <div class="edit-grid">
          <label class="field wide"><span>Place name</span><input type="text" name="place_name" maxlength="120" value="${esc(s.place_name)}"></label>
          <label class="field"><span>Kg</span><input type="number" step="any" name="kg" value="${esc(n(s.kg))}"></label>
          <label class="field"><span>Sacks</span><input type="number" step="1" name="sacks" value="${esc(n(s.sacks))}"></label>
          <label class="field"><span>Crew size</span><input type="number" step="1" name="crew_size" value="${esc(n(s.crew_size))}"></label>
          <label class="field"><span>Disposal</span><input type="text" name="disposal" maxlength="200" value="${esc(n(s.disposal))}"></label>
          <label class="field"><span>Lat</span><input type="number" step="any" name="lat" value="${esc(n(misPoint ? misPoint.lat : s.lat))}"></label>
          <label class="field"><span>Lng</span><input type="number" step="any" name="lng" value="${esc(n(misPoint ? misPoint.lng : s.lng))}"></label>
          <label class="field wide"><span>Notes (public)</span><textarea name="notes" maxlength="1000">${esc(n(s.notes))}</textarea></label>
        </div>
        <div class="panel-title" style="margin-top:12px">WHAT WE PAID (EUR)</div>
        <p class="hint" data-paid-hint hidden></p>
        <div class="edit-grid">
          <label class="field"><span>Paid to partner</span><input type="number" step="any" min="0" name="paid_eur" value="${esc(n(paid))}"></label>
          <label class="field"><span>Of which crew</span><input type="number" step="any" min="0" name="crew_eur" value="${esc(n(s.crew_eur))}"></label>
          <label class="field"><span>Ops + transport</span><input type="number" step="any" min="0" name="ops_eur" value="${esc(n(s.ops_eur))}"></label>
          <label class="field wide"><span>Review note (internal)</span><input type="text" name="review_note" maxlength="1000" value="${esc(n(s.review_note))}"></label>
        </div>
        <div class="btn-row">
          <button type="button" class="b b-ok" data-act="approve">APPROVE</button>
          <button type="button" class="b b-red" data-act="reject" aria-expanded="false">REJECT</button>
        </div>
        <div class="msg err" data-err></div>
      </form>`;
    wireCrewPostBox(el, s);
    const f = $("form", el);
    // REJECT only opens the reply with the reasons. Deleting is a second, separate step inside it.
    const c = s.contact && typeof s.contact === "object" ? s.contact : null;
    const misNo = missionNo(mis);
    const reply = replyBox({
      whatsapp: c && c.whatsapp, email: c && c.email,
      lang: (c && c.lang === "id") || s.country === "ID" ? "id" : "en",
      text: (l) => cleanupRejectText(l, s, mis, $$('input[name="why"]:checked', el).map((i) => i.value)),
      subject: misNo ? { en: `Your Sapu Earth cleanup for mission #${misNo}`, id: `Laporan aksi bersih Sapu Earth untuk misi #${misNo}` }
        : { en: "Your Sapu Earth cleanup", id: "Laporan aksi bersih Sapu Earth kalian" },
      title: "Tell the crew why", label: "Reject message",
      note: (c && (waDigits(c.whatsapp) || mailto(c.email)) ? "Nothing is sent automatically. "
        : "Nothing is sent automatically, and there is no WhatsApp or email on file for this crew, so send it the way you usually reach them. ") +
        "Tick why, send the message, then reject: that deletes the photos and videos for good.",
      deleteLabel: "REJECT AND DELETE",
      extra: `<fieldset class="am-why"><legend>WHY (EACH TICK GOES INTO THE MESSAGE)</legend>${REJECT_WHY.filter((r) => !r.mission || misNo).map((r) =>
        `<label class="check"><input type="checkbox" name="why" value="${esc(r.key)}"> <span>${esc(whyText(r, "label", misNo))}</span></label>`).join("")}</fieldset>`,
    });
    $(".btn-row", f).after(reply);
    reply.addEventListener("change", (ev) => { if (ev.target.name === "why") reply.refresh(); });
    const rejectBtn = $('[data-act="reject"]', f);
    const openWhy = (open) => {
      reply.hidden = !open;
      rejectBtn.setAttribute("aria-expanded", String(open));
      if (open) $(".box-title", reply).focus();
      else rejectBtn.focus();
    };
    const val = (name) => { const v = f.elements[name].value.trim(); return v === "" ? null : (f.elements[name].type === "number" ? Number(v) : v); };
    // The cleanup's own crew pay was added up on the crew page for the crew size it was sent with (what each person got
    // × that crew size). A crew size fixed here does not change that money, so the hint says so while they differ.
    const crewHint = $("[data-crew-hint]", f);
    const ownPay = isNum(s.crew_pay_local) && Number(s.crew_pay_local) > 0;
    f.elements.crew_size.addEventListener("input", () => {
      const on = ownPay && val("crew_size") !== Number(s.crew_size);
      crewHint.hidden = !on;
      crewHint.textContent = on ? `The local crew pay (${n(s.currency) || "?"} ${fmt(s.crew_pay_local)}) was added up for ${fmt(s.crew_size)} ${Number(s.crew_size) === 1 ? "person" : "people"}. It does not change with the crew size here.` : "";
    });
    // The prefilled EUR and its mission number, while the field still holds it.
    let auto = agreed !== null && !isNum(s.paid_eur) ? { eur: agreed, no: missionNo(mis) } : null;
    const paidHint = $("[data-paid-hint]", f);
    const showPaidHint = () => {
      paidHint.hidden = !auto;
      paidHint.textContent = auto ? `Paid to partner is prefilled with the ${eur(auto.eur)} agreed for mission #${auto.no}.` : "";
    };
    showPaidHint();
    f.elements.paid_eur.addEventListener("input", () => { if (auto && val("paid_eur") !== auto.eur) { auto = null; showPaidHint(); } });
    // The prefilled point and its mission number, while Lat and Lng still hold it.
    let autoPt = misPoint;
    const ptHint = $("[data-pt-hint]", f);
    const showPtHint = () => {
      ptHint.hidden = !autoPt;
      ptHint.textContent = autoPt ? `The cleanup came without a location, so Lat and Lng are prefilled with the point of mission #${autoPt.no}, rounded to about 100 m.` : "";
    };
    showPtHint();
    const ptHeld = () => !!autoPt && val("lat") === autoPt.lat && val("lng") === autoPt.lng;
    for (const name of ["lat", "lng"]) f.elements[name].addEventListener("input", () => { if (autoPt && !ptHeld()) { autoPt = null; showPtHint(); } });

    // Link to mission: the chosen funded mission, or null.
    const linkSel = links.length ? f.elements.mission_id : null;
    const linked = () => (linkSel && linkSel.value ? links.find((m) => m.id === linkSel.value) || null : null);
    if (linkSel) {
      linkSel.addEventListener("change", () => {
        const m = linked();
        const now = m && Array.isArray(m.now) ? m.now.map((p) => safeMedia(p && p.url)).filter(Boolean) : [];
        // The mission's video of the spot, under its NOW photos.
        const video = m && m.now_video ? safeMedia(m.now_video.url) : "";
        $("[data-link-facts]", f).innerHTML = m ? `${now.length ? `<h4>NOW, #${esc(missionNo(m))} (${now.length})</h4><div class="am-photos">${now
          .map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener"><img src="${esc(u)}" alt="" loading="lazy"></a>`).join("")}</div>` : ""}${video
          ? `<div class="media-v"><h4>VIDEO NOW, #${esc(missionNo(m))}</h4>${player(video)}</div>` : ""}${missionFacts(s, m, true)}` : "";
        // Prefill (or clear) the EUR only while the field is empty or still holds the last prefill.
        const cur = val("paid_eur");
        if (cur === null || (auto && cur === auto.eur)) {
          auto = m && isNum(m.funded_eur) ? { eur: cents(m.funded_eur), no: missionNo(m) } : null;
          f.elements.paid_eur.value = auto ? n(auto.eur) : "";
          showPaidHint();
        }
        // The same for the point, unless the cleanup came with its own.
        if (!ownPoint && ((val("lat") === null && val("lng") === null) || ptHeld())) {
          autoPt = pointOf(m);
          f.elements.lat.value = autoPt ? n(autoPt.lat) : "";
          f.elements.lng.value = autoPt ? n(autoPt.lng) : "";
          showPtHint();
        }
      });
    }

    f.addEventListener("click", async (ev) => {
      const act = ev.target.dataset && ev.target.dataset.act;
      if (!act) return;
      if (act === "reject") return openWhy(true);
      if (act === "cancel") return openWhy(false);
      if (act !== "approve" && act !== "delete") return; // the reply's own buttons (COPY MESSAGE) have their listeners
      if (act === "delete" && !confirm("Reject this cleanup? Its photos and videos are deleted for good." +
          (missionNo(mis) && (!mis.status || mis.status === "funded") ? ` Mission #${missionNo(mis)} stays funded and keeps its own ${nowWhat(mis)}.` : ""))) return;
      if (act === "approve" && (val("lat") === null || val("lng") === null) &&
          !confirm("No map coordinates. This cleanup will not show on the globe. Approve anyway?")) return;
      if (act === "approve" && val("paid_eur") === null &&
          !confirm("No EUR amount. The public receipt will say PAYMENT PENDING. Approve anyway?")) return;
      const body = { id: s.id, action: act === "delete" ? "reject" : act, review_note: val("review_note") };
      // Only approve links a mission, and only when the crew sent the cleanup without one.
      const link = act === "approve" ? linked() : null;
      if (act === "approve") {
        body.paid_eur = val("paid_eur"); body.crew_eur = val("crew_eur"); body.ops_eur = val("ops_eur");
        body.edits = {};
        for (const k of ["place_name", "kg", "sacks", "crew_size", "disposal", "notes", "lat", "lng"]) body.edits[k] = val(k);
        if (link) body.mission_id = link.id;
      }
      $$("button", f).forEach((b) => (b.disabled = true));
      try {
        const r = await api("/api/admin/decide", body);
        let done = act === "approve" ? `Approved. It is live: ${SITE}/r/${s.id}` : "Rejected and media deleted.";
        const target = link || mis;
        const no = missionNo(target);
        if (no && (!target.status || target.status === "funded")) {
          // The server says what became of the mission. If it says nothing, a mission the crew
          // picked is done; a link made here must be confirmed.
          const st = r && r.mission && typeof r.mission === "object" ? r.mission.status : null;
          if (act === "approve" && link && !st) {
            done += ` Mission #${no} was not confirmed as done, check MISSIONS.`;
          } else if (act === "approve" && st && st !== "done") {
            done += ` Mission #${no} is ${st}, not marked done.`;
          } else if (act === "approve") {
            const adv = isNum(target.advance_eur) ? Number(target.advance_eur) : 0;
            done += ` Mission #${no} is done.` + (body.paid_eur !== null ? ` Send the rest now: ${eur(Math.max(0, cents(body.paid_eur - adv)))}` +
              (adv > 0 ? ` (this counts the ${eur(adv)} advance as sent, so check Wise first).` : ".") : "");
          } else {
            done += ` Mission #${no} stays funded, the crew can send the cleanup again.`;
          }
        }
        flash(done);
        el.remove();
        if (link) unlinkable(link.id);
        if (!$("#view .sub-card")) render();
      } catch (e) {
        $("[data-err]", f).textContent = e.message;
        $$("button", f).forEach((b) => (b.disabled = false));
      }
    });
    return el;
  }

  // ---------- approved: the social kit ----------
  // variant: "en" | "id" | "en-ig" | "id-ig" (Instagram captions cannot carry a clickable link)
  function caption(s, variant = "en") {
    const id = variant.startsWith("id");
    const ig = variant.endsWith("-ig");
    const eur = s.crew_eur !== null && s.crew_eur !== undefined ? fmt(s.crew_eur) : null;
    const n = s.crew_size;
    if (id) {
      const amount = s.kg > 0 ? `mengangkat ${fmt(s.kg)} kg sampah` : s.sacks > 0 ? `mengangkat ${fmt(s.sacks)} karung sampah` : "membersihkan sampah";
      return `Sebelum dan sesudah di ${s.place_name}. ${n} orang kru dari ${s.partner_name} ${amount}.` +
        (eur ? ` Upah kru: €${eur}.` : "") +
        (ig ? " Bukti lengkapnya: link di bio" : ` Bukti lengkapnya: ${SITE}/r/${s.id}`) + " #sapuearth #aksibersih";
    }
    const amount = s.kg > 0 ? `cleared ${fmt(s.kg)} kg of trash` : s.sacks > 0 ? `cleared ${fmt(s.sacks)} sacks of trash` : "cleared the trash";
    return `Before and after in ${s.place_name}. A local crew of ${n} from ${s.partner_name} ${amount}.` +
      (eur ? ` The crew was paid €${eur}.` : "") +
      (ig ? " Full receipt: link in bio" : ` Full receipt: ${SITE}/r/${s.id}`) + " #sapuearth #cleanup";
  }
  // The social kit's download row: every photo and video the card shows, in its order, each saved as
  // sapu-earth-<receipt id>-<label>.<ext> (before-1, after-1, video-before, video-after; video-before-1, video-before-2
  // when a stage has several, videoRows). A cleanup that closed a mission also has the mission's photos and video of
  // the spot (now-1, now-2, video-now). The server takes a dl
  // name only as lowercase letters, digits and dashes (functions/media/[key].js); dl=1 is the old name,
  // sapu-earth-<first 8 of the key>.
  const DL_NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
  function downloads(s, mis) {
    const now = mis && Array.isArray(mis.now) ? mis.now : [];
    return [
      ...now.map((m, i) => [m, `now-${i + 1}`]),
      ...s.media.before.map((m, i) => [m, `before-${i + 1}`]),
      ...s.media.after.map((m, i) => [m, `after-${i + 1}`]),
      ...(mis && mis.now_video ? [[mis.now_video, "video-now"]] : []),
      ...videoRows(s.media.videos).map((r) => [r.v, r.dl]),
    ].map(([m, label]) => {
      const u = safeMedia(m && m.url);
      const name = `${s.id}-${label}`;
      return u ? { href: `${u}&dl=${DL_NAME_RE.test(name) ? name : "1"}`, label } : null;
    }).filter(Boolean);
  }
  // COMMENTS LINK on APPROVED: the link to Sapu Earth's own post (paste, OPEN POST, SAVE; REMOVE) and the crew's (REMOVE
  // CREW LINK), with what the receipt shows now (social: socialPick's answer, or the same worked out here on the first
  // draw). Only once migration 0007 is in (post_links not null).
  function postBoxInner(s, social) {
    const mine = safePost(s.post_links && s.post_links.sapu), theirs = safePost(s.post_links && s.post_links.crew);
    return `
      <div class="panel-title">COMMENTS LINK</div>
      <p class="hint am-shows">${esc(showsLine(social))}</p>
      <label class="field wide"><span>Your post on Instagram or TikTok</span><input type="url" name="sapu_url" value="${esc(mine)}" placeholder="https://www.instagram.com/p/..." autocomplete="off" spellcheck="false"></label>
      <div class="btn-row">
        <button type="button" class="b b-sm" data-post="save">SAVE</button>
        <button type="button" class="b b-sm b-ghost" data-post="open">OPEN POST</button>
        ${mine ? '<button type="button" class="b b-sm b-ghost" data-post="remove">REMOVE</button>' : ""}
      </div>
      <p class="hint am-postlink">${theirs ? `The crew's post: <a href="${esc(theirs)}" target="_blank" rel="noopener noreferrer">${esc(postHost(theirs))} ↗</a>` : "The crew sent no post link."}</p>
      ${theirs ? '<div class="btn-row"><button type="button" class="b b-sm b-ghost" data-post="remove-crew">REMOVE CREW LINK</button></div>' : ""}
      <p class="hint">Paste the link to your own post. Instagram: Share, then Copy link (instagram.com/p/... or instagram.com/reel/...). TikTok: the address of the video on tiktok.com in a browser (tiktok.com/@sapu.earth/video/...). The TikTok app copies a short link, which is refused because nobody can check where it leads; OPEN POST opens it, so you can copy the full address. An Instagram link does not say whose post it is, so tap OPEN POST before SAVE. The receipt shows your post when there is one, else the crew's. Public pages catch up within 5 minutes.</p>
      <div class="msg err" data-post-err></div>`;
  }
  function postBox(s) {
    const box = document.createElement("div");
    box.className = "am-postbox";
    box.dataset.postbox = "";
    const sapu = safePost(s.post_links.sapu), crew = safePost(s.post_links.crew);
    box.innerHTML = postBoxInner(s, sapu ? { site: siteOf(sapu), by: "sapu" }
      : crew && Number(s.partner_active) === 1 ? { site: siteOf(crew), by: "crew" } : null);
    const say = (text) => { $("[data-post-err]", box).textContent = text; };
    box.addEventListener("click", async (ev) => {
      const btn = ev.target.closest("[data-post]");
      if (!btn) return;
      const act = btn.dataset.post;
      const typed = box.querySelector('input[name="sapu_url"]').value.trim();
      say("");
      if (act === "open") {
        const u = openable(typed) || safePost(s.post_links.sapu);
        if (u) window.open(u, "_blank", "noopener,noreferrer");
        else say("Paste a full https:// link to the post first.");
        return;
      }
      if (act === "save" && !typed) return say("Paste the link to your post first.");
      if (act === "remove" && !confirm("Take the link to your post off this receipt? The post itself stays where it is.")) return;
      if (act === "remove-crew" && !confirm("Take the link to the crew's post off this receipt? It cannot be added back.")) return;
      btn.disabled = true;
      try {
        const r = await api("/api/admin/post-link", { id: s.id, slot: act === "remove-crew" ? "crew" : "sapu", url: act === "save" ? typed : null });
        s.post_links = r.post_links;
        box.innerHTML = postBoxInner(s, r.social);
        flash(act === "save" ? `Saved. The receipt links your post on ${siteName(r.post_links.sapu)}. Public pages catch up within 5 minutes.`
          : act === "remove" ? "Your post link was taken off the receipt."
          : "The crew's post link was taken off the receipt. Tell the crew why on WhatsApp.");
      } catch (e) {
        say(e.message);
        btn.disabled = false;
      }
    });
    return box;
  }
  function approvedCard(s, mis) {
    const el = document.createElement("article");
    el.className = "sub-card";
    const receipt = `${SITE}/r/${s.id}`;
    const mno = missionNo(mis);
    el.innerHTML = `${head(s, mis)}${mediaBlock(s, mis)}${missionFacts(s, mis, false)}
      <div class="panel-title" style="margin-top:12px">SOCIAL KIT</div>
      ${[["en", "English"], ["id", "Bahasa Indonesia"], ["en-ig", "Instagram, English"], ["id-ig", "Instagram, Indonesia"]].map(([v, label]) => `
      <div class="hint" style="margin-top:8px">${label}</div>
      <textarea class="caption" readonly>${esc(caption(s, v))}</textarea>
      <div class="btn-row"><button type="button" class="b b-sm" data-copy="caption" data-variant="${v}">COPY CAPTION</button></div>`).join("")}
      <div class="btn-row">
        <button type="button" class="b b-sm b-ghost" data-copy="link">COPY RECEIPT LINK</button>
        <a class="b b-sm b-ghost" href="/r/${esc(s.id)}" target="_blank" rel="noopener">OPEN RECEIPT</a>
        <a class="b b-sm b-ghost" href="/p/${esc(s.partner_slug)}" target="_blank" rel="noopener">PARTNER PAGE</a>
      </div>
      <p class="hint" style="margin-top:8px">${esc(receipt)}</p>
      <div class="dl-list">${downloads(s, mis).map((d) => `<a href="${esc(d.href)}" download>⬇ ${esc(d.label)}</a>`).join("")}</div>
      ${facts(s)}
      <div class="btn-row"><button type="button" class="b b-sm b-red" data-act="unpublish">UNPUBLISH AND DELETE MEDIA</button></div>
      <div class="msg err" data-err></div>`;
    if (mno) {
      // The mission link follows the mission to its receipt, so it can be shared as well.
      const row = document.createElement("div");
      row.className = "btn-row";
      row.innerHTML = `<button type="button" class="b b-sm b-ghost">COPY MISSION LINK</button>
        <a class="b b-sm b-ghost" href="/m/${esc(mno)}" target="_blank" rel="noopener">OPEN MISSION #${esc(mno)}</a>`;
      $("button", row).addEventListener("click", (ev) => copy(missionLink(mno), ev.currentTarget));
      $('[data-copy="link"]', el).parentElement.after(row);
    }
    if (s.post_links) $(".dl-list", el).after(postBox(s));
    // The receipt's standing thanks, right after COMMENTS LINK (null before migration 0007: no line).
    if (typeof s.thanks === "number") {
      const line = document.createElement("p");
      line.className = "hint am-thanks";
      line.textContent = s.thanks > 0 ? `Thanked ${fmt(s.thanks)} ${s.thanks === 1 ? "time" : "times"}.` : "No thanks yet.";
      ($("[data-postbox]", el) || $(".dl-list", el)).after(line);
    }
    $$('[data-copy="caption"]', el).forEach((b) => b.addEventListener("click", (ev) => copy(caption(s, b.dataset.variant), ev.target)));
    $('[data-copy="link"]', el).addEventListener("click", (ev) => copy(receipt, ev.target));
    $('[data-act="unpublish"]', el).addEventListener("click", async () => {
      // The posts about it on Instagram or TikTok stay up until someone deletes them there: ours, named with its link,
      // and the crew's own, which only the crew can delete.
      const mine = safePost(s.post_links && s.post_links.sapu), theirs = safePost(s.post_links && s.post_links.crew);
      if (!confirm("Take this cleanup off the site? Its photos and videos are deleted for good." +
          // Only the mission this cleanup completed (done) is removed with it.
          (s.mission_id && (!mis || !mis.status || mis.status === "done") ? ` Mission${mno ? " #" + mno : ""} is removed too, with its ${nowWhat(mis)}.` : "") +
          (mine ? ` Then delete your post on ${siteName(mine)} too: ${mine}` : " If you posted it on Instagram or TikTok, delete that post there too.") +
          (theirs ? " The crew's own post stays on its account: if a person asked to be taken down, ask the crew on WhatsApp to delete it too." : ""))) return;
      try {
        await api("/api/admin/decide", { id: s.id, action: "reject", review_note: "Unpublished after approval" });
        flash("Unpublished and media deleted." +
          (mine ? ` Now delete your post on ${siteName(mine)}: ${mine}` : " If you posted it on Instagram or TikTok, delete that post there too.") +
          (theirs ? " If a person asked to be taken down, ask the crew to delete its own post too." : ""));
        el.remove();
      } catch (e) { $("[data-err]", el).textContent = e.message; }
    });
    return el;
  }

  // ---------- partners ----------
  // Cut first, then trim: a cut that lands on a word gap must not leave a trailing dash (SLUG_RE rejects it).
  const slugify = (s) => s.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").slice(0, 40).replace(/^-+|-+$/g, "");

  function secretBox(name, link) {
    const box = document.createElement("div");
    box.className = "secret";
    box.innerHTML = `<b>Upload link for ${esc(name)}</b>. Shown only once. Send it to the partner privately (WhatsApp or email).<br><br><span>${esc(link)}</span>
      <div class="btn-row"><button type="button" class="b b-sm">COPY LINK</button></div>`;
    $("button", box).addEventListener("click", (ev) => copy(link, ev.target));
    return box;
  }

  // The PARTNERS tab says how many crew logos wait under LOGOS TO CHECK and how many TikTok accounts under TIKTOK TO
  // CHECK ("PARTNERS · 1 LOGO · 1 TIKTOK"), yellow like the other counts. It counts what waits, not partners: both are
  // rare, and the label reads as what waits. No logo count that is a number: no change. A missing TikTok count (a server
  // from before them) counts as 0.
  function setPartnerCount(counts) {
    const c = Number(counts && counts.logos);
    if (!Number.isFinite(c)) return;
    const tt = Number(counts.tiktok) > 0 ? Number(counts.tiktok) : 0;
    const parts = [];
    if (c > 0) parts.push(`${c} LOGO${c === 1 ? "" : "S"}`);
    if (tt > 0) parts.push(`${tt} TIKTOK`);
    const b = $('[data-tab="partners"]');
    b.textContent = ["PARTNERS", ...parts].join(" · ");
    b.classList.toggle("has-new", parts.length > 0);
  }
  async function refreshPartnerCount() {
    try {
      const r = await api("/api/admin/partners");
      if (r && r.counts) setPartnerCount(r.counts);
    } catch { /* only a hint; the tab shows the error when opened */ }
  }

  async function renderPartners(view) {
    const data = await api("/api/admin/partners");
    view.innerHTML = `
      <section class="panel logo-check" id="logoCheck" hidden></section>
      <section class="panel logo-check" id="tiktokCheck" hidden></section>
      <form class="panel" id="newPartner" novalidate>
        <h2 class="panel-title">NEW PARTNER</h2>
        <div class="edit-grid">
          <label class="field wide"><span>Name</span><input type="text" name="name" maxlength="80" required></label>
          <label class="field wide"><span>Website</span><input type="url" name="url" maxlength="200" placeholder="https://"></label>
          <label class="field"><span>Country (ISO2)</span><input type="text" name="country" maxlength="2" placeholder="ID" required></label>
          <label class="field"><span>Slug</span><input type="text" name="slug" maxlength="40" required></label>
        </div>
        <div class="btn-row"><button class="b" type="submit">CREATE PARTNER</button></div>
        <div class="msg err" data-err></div>
        <div data-secret></div>
      </form>
      <section class="panel"><h2 class="panel-title">PARTNERS</h2><div id="plist"></div></section>`;
    const f = $("#newPartner");
    let slugTouched = false;
    f.elements.slug.addEventListener("input", () => (slugTouched = true));
    f.elements.name.addEventListener("input", () => { if (!slugTouched) f.elements.slug.value = slugify(f.elements.name.value); });
    f.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      $("[data-err]", f).textContent = "";
      try {
        const r = await api("/api/admin/partners", {
          name: f.elements.name.value.trim(),
          url: f.elements.url.value.trim() || null,
          country: f.elements.country.value.trim().toUpperCase(),
          slug: f.elements.slug.value.trim(),
        });
        const holder = $("[data-secret]", f);
        const country = f.elements.country.value.trim().toUpperCase();
        // Reset first: the welcome box sits inside this form, and a reset would empty its message.
        f.reset();
        slugTouched = false;
        holder.textContent = "";
        holder.append(welcomeBox(r, { contact_name: "", org_name: r.name, whatsapp: "", email: "", lang: country === "ID" ? "id" : "en" }));
        await listPartners();
      } catch (e) { $("[data-err]", f).textContent = e.message; }
    });
    await listPartners(data);
  }

  // LOGOS TO CHECK, TIKTOK TO CHECK, the partner rows and the tab label, all from one answer of GET /api/admin/partners
  // ({partners, counts}; fetched when not given), so they always agree. Every action that changes a partner, a logo or a
  // TikTok account calls it again. A NEW LINK box showing in a row is the only copy of that link: it moves into the
  // redrawn row.
  async function listPartners(data) {
    if (!data) data = await api("/api/admin/partners");
    const list = $("#plist");
    if (!list) return; // another tab was opened meanwhile
    const partners = Array.isArray(data.partners) ? data.partners : [];
    drawLogoCheck(partners);
    drawTiktokCheck(partners);
    setPartnerCount(data.counts);
    const kept = {};
    for (const box of $$(".p-row [data-secret]", list)) if (box.childElementCount) kept[box.closest(".p-row").dataset.id] = box;
    if (!partners.length) { list.innerHTML = '<p class="hint">No partners yet.</p>'; return; }
    list.innerHTML = "";
    for (const p of partners) {
      const row = document.createElement("div");
      row.className = "p-row" + (p.active ? "" : " inactive");
      row.dataset.id = p.id;
      const contact = [p.contact_name, p.whatsapp, p.email].filter((x) => n(x)).map(esc).join(" · ");
      const logo = p.logo ? safeMedia(p.logo.url) : "";
      const tiktok = ttName(p.tiktok);
      row.innerHTML = `
        <div>
          ${logo ? `<img class="p-logo" src="${esc(logo)}" alt="" width="40" height="40" loading="lazy" decoding="async">` : ""}<span class="p-name">${esc(p.name)}</span>
          <small>${esc(p.slug)} · ${esc(p.country || "")} · ${p.active ? "active" : "deactivated"} · ${esc(p.pending)} pending · ${esc(p.approved)} approved</small>
          ${p.url ? `<small>${esc(p.url)}</small>` : ""}
          ${contact ? `<small>contact: ${contact}</small>` : ""}
          ${p.logo_review ? "<small>new logo waits under LOGOS TO CHECK</small>" : ""}
          ${tiktok ? `<small>tiktok: <a href="${esc(ttLink(tiktok))}" target="_blank" rel="noopener noreferrer">@${esc(tiktok)} ↗</a></small>` : ""}
          ${p.tiktok_review && ttName(p.tiktok_review.account) ? "<small>new TikTok account waits under TIKTOK TO CHECK</small>" : ""}
        </div>
        <div class="btn-row">
          ${p.active ? `<a class="b b-sm b-ghost" href="/p/${esc(p.slug)}" target="_blank" rel="noopener">PAGE</a>
          ${p.logo ? '<button type="button" class="b b-sm b-ghost" data-act="logo-remove">REMOVE LOGO</button>' : ""}
          ${tiktok ? '<button type="button" class="b b-sm b-ghost" data-act="tiktok-remove">REMOVE TIKTOK</button>' : ""}
          <button type="button" class="b b-sm b-ghost" data-act="rotate">NEW LINK</button>
          <button type="button" class="b b-sm b-red" data-act="deactivate">DEACTIVATE</button>` : ""}
        </div>
        <div data-secret style="flex-basis:100%"></div>`;
      if (kept[p.id]) $("[data-secret]", row).replaceWith(kept[p.id]);
      row.addEventListener("click", async (ev) => {
        const act = ev.target.dataset && ev.target.dataset.act;
        if (!act) return;
        if (act === "logo-remove") {
          if (!p.logo || !confirm(`Take the logo of ${p.name} off sapu.earth? It is deleted for good, and their crew page asks them for another one.`)) return;
          ev.target.disabled = true;
          try {
            await api("/api/admin/logos/decide", { key: p.logo.key, action: "remove" });
            flash(`The logo of ${p.name} was taken off sapu.earth and deleted.`);
            await listPartners();
          } catch (e) { logoFailed(e, [ev.target], null); }
          return;
        }
        if (act === "tiktok-remove") {
          if (!tiktok || !confirm(`Take the TikTok account @${tiktok} of ${p.name} off sapu.earth? It is deleted, and their crew page tells them Sapu Earth is not showing it. They can send one again.`)) return;
          ev.target.disabled = true;
          try {
            await api("/api/admin/tiktok/decide", { partner_id: p.id, account: tiktok, action: "remove" });
            flash(`The TikTok account of ${p.name} was taken off sapu.earth.`);
            await listPartners();
          } catch (e) { logoFailed(e, [ev.target], null); }
          return;
        }
        const q = act === "rotate"
          ? `Make a new upload link for ${p.name}? The old link stops working right away.`
          : `Deactivate ${p.name}? Their upload link stops working and their partner page goes offline. ` +
            "Their missions in review, open and funded are removed too, with their photos and videos. The advance of a funded mission stays with the crew. " +
            "Published cleanups and done missions stay." +
            (contact ? " Their contact details from the application are deleted too." : "") +
            (p.logo || p.logo_review ? " Their logo is deleted too." : "") +
            (p.tiktok || p.tiktok_review ? " Their TikTok account comes off sapu.earth too." : "") +
            " Links to their own posts on Instagram or TikTok come off their receipts.";
        if (!confirm(q)) return;
        try {
          const r = await api(`/api/admin/partners/${act}`, { id: p.id });
          if (act === "rotate") { const h = $("[data-secret]", row); h.textContent = ""; h.append(secretBox(p.name, r.upload_url)); }
          else {
            const gone = r && isNum(r.missions_removed) ? Number(r.missions_removed) : 0;
            // Funded ones removed: their advance stays with the crew, the rest is not due.
            const funded = (r && Array.isArray(r.funded_removed) ? r.funded_removed : [])
              .filter((m) => missionNo(m))
              .map((m) => `#${missionNo(m)} (${isNum(m.advance_eur) && Number(m.advance_eur) > 0 ? `advance ${eur(m.advance_eur)}` : "no advance"})`);
            flash(`${p.name} deactivated.` + (gone ? ` ${gone} mission${gone === 1 ? "" : "s"} removed, with ${gone === 1 ? "its photos and any video" : "their photos and any videos"}.` : "") +
              (funded.length ? ` Funded ones: ${funded.join(", ")}. The advance stays with the crew and the rest is not due.` : "") +
              (r && Number(r.logos_removed) > 0 ? " Their logo was deleted." : "") +
              (r && Number(r.tiktok_removed) > 0 ? " Their TikTok account came off sapu.earth." : "") +
              (r && Number(r.post_links_removed) > 0
                ? ` Links to their own posts came off ${Number(r.post_links_removed)} receipt${Number(r.post_links_removed) === 1 ? "" : "s"}.` : ""));
            refreshMissionCount();
            await listPartners();
          }
        } catch (e) { flash(e.message, false); }
      });
      list.append(row);
    }
  }

  // LOGOS TO CHECK, at the top of PARTNERS: the logos active crews sent from their crew page, oldest first, each next to
  // what sapu.earth shows now. APPROVE LOGO and DECLINE are one tap: DECLINE only deletes a picture the crew still has
  // and can send again, and changes nothing public (ops/production-rules.md, rule 5). Hidden when nothing waits.
  function drawLogoCheck(partners) {
    const box = $("#logoCheck");
    if (!box) return;
    const waiting = partners.filter((p) => p.active && p.logo_review && safeMedia(p.logo_review.url))
      .sort((a, b) => String(a.logo_review.created_at || "").localeCompare(String(b.logo_review.created_at || "")));
    box.hidden = !waiting.length;
    box.innerHTML = "";
    if (!waiting.length) return;
    box.innerHTML = `<h2 class="panel-title">LOGOS TO CHECK (${waiting.length})</h2>
      <p class="hint">Crews sent these from their crew page. Nothing shows on sapu.earth before you approve. APPROVE LOGO puts it next to the crew's name; public pages catch up within 5 minutes. Approve the crew's own logo, or a close-up of it on their banner or shirt. Decline people or faces (children above all), another organization's, sponsor's, party's or government's logo, phone or bank numbers, QR codes, text that asks for money, and anything you would not show on sapu.earth. DECLINE deletes it: their crew page asks them for another one, or keeps showing their current logo if they have one. A logo left here for 90 days is deleted the same way.</p>
      <div class="lc-list"></div>`;
    const list = $(".lc-list", box);
    for (const p of waiting) {
      const lr = p.logo_review;
      const age = ageDays(lr.created_at);
      const now = p.logo ? safeMedia(p.logo.url) : "";
      const item = document.createElement("div");
      item.className = "lc-item";
      item.innerHTML = `<img class="lc-new" src="${esc(safeMedia(lr.url))}" alt="New logo of ${esc(p.name)}" width="96" height="96">
        <div class="lc-text">
          <span class="p-name">${esc(p.name)}</span>
          <small>sent ${esc(String(lr.created_at || "").slice(0, 16).replace("T", " "))}${age !== null ? ` (${esc(daysAgo(age))})` : ""}</small>
          <small>now on sapu.earth: ${now ? `<img class="p-logo" src="${esc(now)}" alt="" width="40" height="40" loading="lazy" decoding="async">` : "no logo yet"}</small>
          <div class="btn-row">
            <button type="button" class="b b-sm b-ok" data-act="logo-approve">APPROVE LOGO</button>
            <button type="button" class="b b-sm b-red" data-act="logo-decline">DECLINE</button>
          </div>
          <div class="msg"></div>
        </div>`;
      item.addEventListener("click", async (ev) => {
        const act = ev.target.dataset && ev.target.dataset.act;
        if (act !== "logo-approve" && act !== "logo-decline") return;
        const btns = $$("button", item);
        btns.forEach((x) => (x.disabled = true));
        try {
          await api("/api/admin/logos/decide", { key: lr.key, action: act === "logo-approve" ? "approve" : "decline" });
          flash(act === "logo-approve" ? `The logo of ${p.name} is on sapu.earth now.`
            : `The logo of ${p.name} was declined and deleted.` + (p.logo ? " Their current logo stays on sapu.earth." : " Their crew page asks them for another one."));
          await listPartners();
        } catch (e) { logoFailed(e, btns, $(".msg", item)); }
      });
      list.append(item);
    }
  }
  // TIKTOK TO CHECK, under LOGOS TO CHECK: the TikTok accounts active crews sent from their crew page, oldest first, each
  // with OPEN ON TIKTOK and what sapu.earth links now. APPROVE TIKTOK and DECLINE are one tap: DECLINE only drops a name
  // the crew can send again, and changes nothing public (ops/production-rules.md, rule 5). Hidden when nothing waits.
  // Every decision names the account shown here, so one the crew changed meanwhile answers 409 and the list reloads.
  function drawTiktokCheck(partners) {
    const box = $("#tiktokCheck");
    if (!box) return;
    const waiting = partners.filter((p) => p.active && p.tiktok_review && ttName(p.tiktok_review.account))
      .sort((a, b) => String(a.tiktok_review.sent_at || "").localeCompare(String(b.tiktok_review.sent_at || "")));
    box.hidden = !waiting.length;
    box.innerHTML = "";
    if (!waiting.length) return;
    box.innerHTML = `<h2 class="panel-title">TIKTOK TO CHECK (${waiting.length})</h2>
      <p class="hint">Crews sent their TikTok account from their crew page. Nothing shows on sapu.earth before you approve. OPEN ON TIKTOK first: approve the crew's own account, with its cleanups. Decline another person's or organization's account, one that asks for money or shows bank or phone numbers, one that shows children or people who would not want to be shown, and anything you would not link from sapu.earth. APPROVE TIKTOK links it on their page and in the list of crews; public pages catch up within 5 minutes. DECLINE drops it: their crew page says Sapu Earth is not showing it, and they can send another one.</p>
      <div class="lc-list"></div>`;
    const list = $(".lc-list", box);
    for (const p of waiting) {
      const account = ttName(p.tiktok_review.account);
      const sent = p.tiktok_review.sent_at;
      const age = ageDays(sent);
      const now = ttName(p.tiktok);
      const item = document.createElement("div");
      item.className = "lc-item";
      item.innerHTML = `<div class="lc-text">
          <span class="p-name">${esc(p.name)}</span>
          <small>new: <b>@${esc(account)}</b> · <a href="${esc(ttLink(account))}" target="_blank" rel="noopener noreferrer">OPEN ON TIKTOK ↗</a></small>
          <small>sent ${esc(String(sent || "").slice(0, 16).replace("T", " "))}${age !== null ? ` (${esc(daysAgo(age))})` : ""}</small>
          <small>now on sapu.earth: ${now ? `@${esc(now)}` : "no TikTok yet"}</small>
          <div class="btn-row">
            <button type="button" class="b b-sm b-ok" data-act="tiktok-approve">APPROVE TIKTOK</button>
            <button type="button" class="b b-sm b-red" data-act="tiktok-decline">DECLINE</button>
          </div>
          <div class="msg"></div>
        </div>`;
      item.addEventListener("click", async (ev) => {
        const act = ev.target.dataset && ev.target.dataset.act;
        if (act !== "tiktok-approve" && act !== "tiktok-decline") return;
        const btns = $$("button", item);
        btns.forEach((x) => (x.disabled = true));
        try {
          await api("/api/admin/tiktok/decide", { partner_id: p.id, account, action: act === "tiktok-approve" ? "approve" : "decline" });
          flash(act === "tiktok-approve" ? `@${account} is linked on the page of ${p.name} now.`
            : `@${account} was declined.` + (now ? ` Their current account @${now} stays on sapu.earth.` : " Their crew page tells them."));
          await listPartners();
        } catch (e) { logoFailed(e, btns, $(".msg", item)); }
      });
      list.append(item);
    }
  }
  // A TikTok account's name as the server sends it (2 to 24 of a to z, 0 to 9, . and _), else "": only such a name
  // reaches a link or the page. ttLink: its one link.
  function ttName(v) { return typeof v === "string" && /^(?=[a-z0-9._]*[a-z0-9])[a-z0-9._]{2,24}$/.test(v) ? v : ""; }
  function ttLink(name) { return "https://www.tiktok.com/@" + name; }
  // A logo or TikTok decision that did not go through. It was decided or replaced meanwhile (another tab, the crew sent a
  // new one), or its crew was deactivated: the lists are drawn again. Otherwise the buttons work again.
  function logoFailed(e, btns, line) {
    const reload = e.code === "state" || e.code === "inactive";
    const text = e.message + (reload ? " The list was reloaded." : "");
    flash(text, false);
    if (line) { line.className = "msg err"; line.textContent = text; }
    if (reload) listPartners().catch((e2) => flash(e2.message, false));
    else btns.forEach((x) => (x.disabled = false));
  }

  // ---------- applications ----------
  const LANG_NAMES = { en: "English", id: "Bahasa Indonesia" };
  const MAIL_SUBJECT = { en: "Your Sapu Earth crew page", id: "Halaman kru Sapu Earth kalian" };
  const DECLINE_SUBJECT = { en: "Your Sapu Earth application", id: "Pendaftaran Sapu Earth kalian" };
  // Open applications are deleted by the server after 90 days (LIMITS.applyOpenDays in
  // functions/_lib/util.js, keep both in step). Cards warn from day 60.
  const EXPIRE_DAYS = 90;
  const WARN_DAYS = 60;
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  const orNone = (v) => (n(v) ? esc(v) : "not given");
  // wa.me takes digits only. Never add a text parameter: the welcome message carries the private link.
  const waDigits = (v) => { const d = String(v || "").replace(/\D/g, ""); return /^[1-9]\d{7,14}$/.test(d) ? d : ""; };
  const httpUrl = (v) => {
    if (typeof v !== "string" || !/^https?:\/\//i.test(v)) return "";
    try { return new URL(v).href; } catch { return ""; }
  };
  // Local part and domain are encoded separately, so a "?" or "&" inside an address cannot add mailto fields.
  function mailto(email, subject, body) {
    const e = String(email || "");
    if (!EMAIL_RE.test(e)) return "";
    const at = e.lastIndexOf("@");
    let u = "mailto:" + encodeURIComponent(e.slice(0, at)) + "@" + encodeURIComponent(e.slice(at + 1));
    if (subject) u += "?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(String(body || "").replace(/\r?\n/g, "\r\n"));
    return u;
  }
  // The welcome message carries what the site never says on its own: crews post a mission first, only funded
  // missions are paid, the advance and the rest, the #N paper, and a request for payout details. The button
  // names (AJUKAN MISI, LAPOR AKSI BERSIH #12, KIRIM LAPORAN and "Pakai lokasi saya sekarang") are the crew page's
  // own (upload/upload.js T: mode_mission, card_send, send, use_location); tests/e2e.sh checks that they match. The
  // link is the crew page's (HALAMAN KRU KAMU, YOUR CREW PAGE), so both messages call it that.
  // Like the funded message, it names no payment service, only where the money lands: the crew's own bank account
  // or e-wallet, in local money at the exchange rate of the day it is sent. The money can go whatever way suits the crew.
  function welcomeText(lang, a, link) {
    const name = n(a.contact_name) ? " " + a.contact_name : "";
    if (lang === "id") {
      return `Halo${name}! Selamat bergabung di Sapu Earth. Ini link pribadi ke halaman kru ${a.org_name}:\n${link}\n\n` +
        "Cara kerjanya:\n" +
        "1. Buka link ini dan tekan AJUKAN MISI: foto tempat yang kotor, apa yang akan kalian lakukan, tanggalnya, dan harga kalian dalam mata uang lokal. Untuk harganya, tulis jumlah orang yang akan bekerja, upah per orang, dan biaya lain kalau ada. Halaman itu menghitung totalnya. Tekan \"Pakai lokasi saya sekarang\" saat kalian berada di tempat itu, dan pilih tanggal paling cepat seminggu dari sekarang.\n" +
        "2. Kami periksa dulu, lalu kami kabari di sini kalau misinya kami danai. Hanya misi yang didanai yang dibayar, jadi tunggu kabar dari kami sebelum mulai.\n" +
        `3. Kalau misinya didanai, kami kabari jumlahnya dalam euro. Kami kirim uang muka (biasanya ${ADVANCE_PCT}% dari jumlah itu) ke rekening bank atau e-wallet kalian, dan sisanya setelah laporan aksi bersih kalian kami setujui. Uangnya kalian terima dalam rupiah, dengan kurs yang berlaku pada hari uang itu dikirim.\n` +
        "4. Pada harinya, ambil dulu foto sebelum dibersihkan, dan pegang kertas bertuliskan nomor misi (misalnya #12) di salah satu foto itu: kami memerlukannya untuk menyetujui laporan kalian. Di akhir, hitung karung yang sudah penuh, dan ambil foto sesudahnya dari tempat dan sudut yang sama. Lalu buka link ini, tekan LAPOR AKSI BERSIH #12 (dengan nomor misi kalian), tambahkan foto dan jumlah karungnya, lalu tekan KIRIM LAPORAN.\n\n" +
        "Tolong kirim data untuk pembayaran sekarang, supaya uang muka bisa langsung dikirim begitu misinya didanai: nama bank atau e-wallet, nomor rekening (atau nomor e-wallet), dan nama pemiliknya, persis seperti yang terdaftar. Harus milik pribadi satu orang, misalnya ketua kru, bukan milik organisasi. E-wallet harus sudah terverifikasi penuh, kalau tidak uangnya bisa tidak sampai. Kami hanya membayar ke rekening ini. Kalau berubah, kabari kami dari nomor atau email yang sama. Kami tidak pernah meminta PIN, kata sandi, atau kode OTP.\n\n" +
        "Simpan link ini untuk kalian sendiri, jangan dibagikan di grup atau di tempat umum: siapa pun yang punya link ini bisa mengajukan misi dan mengirim laporan atas nama kalian. Kalau kalian meneruskan langkah-langkah ini ke kru, hapus dulu link-nya. Kalau link ini sampai ke orang lain, kabari kami dan kami kirim link baru.\n\n" +
        "Ada pertanyaan? Balas saja pesan ini.\nMarcus, Sapu Earth";
    }
    return `Hi${name}! Welcome to Sapu Earth. This is the private link to the crew page of ${a.org_name}:\n${link}\n\n` +
      "How it works:\n" +
      "1. Open the link and tap POST A MISSION: photos of the dirty spot, what you will do, the day and your price in local money. For the price, write how many people will work, the pay for each person and any other costs. The page works out the total. Tap \"Use my location now\" while you are at the spot, and pick a day at least a week ahead.\n" +
      "2. We check it and tell you here if we fund it. Only funded missions are paid, so please wait for our OK before you start.\n" +
      `3. When we fund it, we tell you the amount in euros. We send an advance (usually ${ADVANCE_PCT}% of it) to your bank account or e-wallet, and the rest after we approve your cleanup. You receive it in your local money, at the exchange rate on the day we send it.\n` +
      "4. On the day, take the before photos first, and hold up a paper with the mission number (like #12) in one of them: we need it to approve the cleanup. At the end, count the full sacks, and take the after photos from the same spot and the same angle. Then open the link, tap SEND A CLEANUP FOR #12 (with your mission's number), add the photos and the number of sacks, and tap SEND CLEANUP.\n\n" +
      "Please send me your payout details now, so the advance can go out as soon as we fund your mission: the bank or e-wallet, the account number (or e-wallet number) and the name exactly as it is on the account. It must be one person's own account, like the crew lead's, not an organization's. An e-wallet must be fully verified, or the money may not arrive. We only pay to this account. If it changes, tell us from this same number or email. We never ask for a PIN, a password or an OTP code.\n\n" +
      "Keep this link to yourselves and don't share it in groups or in public: anyone with it can post missions and send cleanups in your name. If you forward these steps to your crew, delete the link first. If someone else gets the link, tell us and we send you a new one.\n\n" +
      "Questions? Just reply here.\nMarcus, Sapu Earth";
  }
  function declineText(lang, a) {
    if (lang === "id") {
      return `Halo ${a.contact_name}, terima kasih sudah mendaftar ke Sapu Earth bersama ${a.org_name}. ` +
        "Kami hanya bisa mendanai beberapa kru dalam satu waktu, jadi untuk sekarang kami belum bisa mulai bekerja sama dengan kalian. " +
        "Pendaftaran dan foto kalian akan kami hapus. Terima kasih sudah menjaga lingkungan kalian tetap bersih!\nMarcus, Sapu Earth";
    }
    return `Hi ${a.contact_name}, thank you for applying to Sapu Earth with ${a.org_name}. ` +
      "We can only fund a few crews at a time, so we can't start with you right now. " +
      "We will delete your application and photos. Thank you for keeping your area clean!\nMarcus, Sapu Earth";
  }
  // Whole days since the application was sent, or null if the date cannot be read.
  function ageDays(iso) {
    const t = Date.parse(String(iso || ""));
    if (!Number.isFinite(t)) return null;
    return Math.max(0, Math.floor((Date.now() - t) / 86400000));
  }
  const ageText = (d) => (d === 0 ? "open today" : `open ${d} day${d === 1 ? "" : "s"}`);

  function setAppCount(count) {
    const c = Number(count);
    if (!Number.isFinite(c)) return;
    const b = $('[data-tab="applications"]');
    b.textContent = `APPLICATIONS (${c})`;
    b.classList.toggle("has-new", c > 0);
  }
  async function refreshAppCount() {
    try {
      const r = await api("/api/admin/applications?status=new");
      if (r && r.counts) setAppCount(r.counts.new);
    } catch { /* only a hint; the tab shows the error when opened */ }
  }

  async function renderApplications(view) {
    const { counts, applications } = await api("/api/admin/applications?status=new");
    setAppCount(counts ? counts.new : applications.length);
    if (!applications.length) {
      view.innerHTML = '<p class="hint">No new applications. Share sapu.earth/apply with crews you meet.</p>';
      return;
    }
    view.innerHTML = "";
    for (const a of applications) view.append(applicationCard(a));
  }

  // Crew size shows only on an application that has one: /apply/ stopped asking the head count on 2026-11-17 (Marcus:
  // 'Drop the head count'), so only older applications carry it.
  function applicationCard(a) {
    const el = document.createElement("article");
    el.className = "sub-card app-card";
    const dupes = Array.isArray(a.possible_duplicates) ? a.possible_duplicates : [];
    const ex = a.existing_partner;
    const photos = (Array.isArray(a.photos) ? a.photos : []).map((p) => safeMedia(p && p.url)).filter(Boolean);
    const links = (Array.isArray(a.links) ? a.links : []).filter((l) => typeof l === "string" && l.trim());
    const website = links.find((l) => httpUrl(l)) || "";
    const wa = waDigits(a.whatsapp);
    const mail = mailto(a.email);
    const age = ageDays(a.created_at);
    const old = age !== null && age >= WARN_DAYS;
    // The crew's logo, sent with the application: decided with it (the box under APPROVE AS PARTNER).
    const logo = a.logo ? safeMedia(a.logo.url) : "";
    el.innerHTML = `<h3>${esc(a.org_name)}</h3>
      <div class="sub-meta">${esc(a.country)} · ${esc(a.area)} · sent ${esc(String(a.created_at || "").slice(0, 16).replace("T", " "))}${age !== null ? ` · <span class="app-age${old ? " old" : ""}">${esc(ageText(age))}</span>` : ""} · ${esc(String(a.id).toUpperCase())}</div>
      ${old ? `<p class="msg err">Deleted automatically after ${EXPIRE_DAYS} days.</p>` : ""}
      ${dupes.length ? `<p class="msg err">Possible duplicate of ${dupes.map((d) => esc(String(d).toUpperCase())).join(", ")} (same WhatsApp, email or name).</p>` : ""}
      ${ex ? `<p class="msg err">A partner with this name already exists: ${esc(ex.slug)}${ex.active === false ? " (deactivated)" : ""}</p>` : ""}
      ${logo ? `<div class="app-logo"><h4>LOGO</h4><a href="${esc(logo)}" target="_blank" rel="noopener noreferrer"><img src="${esc(logo)}" alt="Logo of ${esc(a.org_name)}" width="96" height="96"></a>
        <p class="hint">Goes on sapu.earth next to the crew's name when you approve with the box below ticked. Fine: their own logo, or a close-up of it on their banner or shirt. Not fine: people, someone else's logo, phone or bank numbers, QR codes, text that asks for money.</p></div>` : ""}
      ${photos.length
        ? `<div class="app-photos">${photos.map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener noreferrer"><img src="${esc(u)}" alt="" loading="lazy"></a>`).join("")}</div>`
        : '<p class="hint">No photos.</p>'}
      <dl class="kv">
        <dt>Contact</dt><dd>${orNone(a.contact_name)}</dd>
        <dt>WhatsApp</dt><dd>${n(a.whatsapp) ? esc(a.whatsapp) + (wa ? ` <a href="https://wa.me/${wa}" target="_blank" rel="noopener noreferrer">open chat ↗</a>` : "") : "not given"}</dd>
        <dt>Email</dt><dd>${n(a.email) ? (mail ? `<a href="${esc(mail)}">${esc(a.email)}</a>` : esc(a.email)) : "not given"}</dd>
        ${n(a.crew_size) ? `<dt>Crew size</dt><dd>${esc(a.crew_size)} people</dd>` : ""}
        <dt>About</dt><dd>${orNone(a.about)}</dd>
        <dt>Links</dt><dd>${links.length ? links.map((l) => {
          const h = httpUrl(l);
          return h ? `<a href="${esc(h)}" target="_blank" rel="noopener noreferrer">${esc(l)}</a>` : esc(l);
        }).join("\n") : "not given"}</dd>
        <dt>Heard from</dt><dd>${orNone(a.heard_from)}</dd>
        <dt>Language</dt><dd>${esc(LANG_NAMES[a.lang] || a.lang)}</dd>
      </dl>
      <form class="decide" novalidate>
        <div class="panel-title">APPROVE AS PARTNER</div>
        <p class="hint">Edit if needed. Approving creates the partner and shows the upload link once.</p>
        <div class="edit-grid">
          <label class="field wide"><span>Name</span><input type="text" name="name" maxlength="80" value="${esc(a.org_name)}"></label>
          <label class="field wide"><span>Website</span><input type="url" name="url" maxlength="200" placeholder="https://" value="${esc(website)}"></label>
          <label class="field"><span>Country (ISO2)</span><input type="text" name="country" maxlength="2" value="${esc(a.country)}"></label>
          <label class="field"><span>Slug</span><input type="text" name="slug" maxlength="40" value="${esc(slugify(String(a.org_name || "")))}"></label>
        </div>
        ${logo ? '<label class="check"><input type="checkbox" name="use_logo" checked> <span>Show this logo on sapu.earth. Untick it to leave the logo out: it is deleted, and they can send another one from their crew page.</span></label>' : ""}
        <div class="btn-row">
          <button type="button" class="b b-ok" data-act="approve">APPROVE AND CREATE PARTNER</button>
          <button type="button" class="b b-red" data-act="reject" aria-expanded="false">REJECT</button>
        </div>
        <div class="msg err" data-err></div>
      </form>`;
    const f = $("form", el);
    // REJECT only opens the reply box. Deleting is a second, separate step inside it.
    const decline = declineBox(a);
    $(".btn-row", f).after(decline);
    const rejectBtn = $('[data-act="reject"]', f);
    const openDecline = (open) => {
      decline.hidden = !open;
      rejectBtn.setAttribute("aria-expanded", String(open));
      if (open) $(".box-title", decline).focus();
      else rejectBtn.focus();
    };
    let slugTouched = false;
    f.elements.slug.addEventListener("input", () => (slugTouched = true));
    f.elements.name.addEventListener("input", () => { if (!slugTouched) f.elements.slug.value = slugify(f.elements.name.value); });
    f.addEventListener("submit", (ev) => ev.preventDefault());
    f.addEventListener("click", async (ev) => {
      const act = ev.target.dataset && ev.target.dataset.act;
      if (act === "reject") return openDecline(true);
      if (act === "cancel") return openDecline(false);
      if (act !== "approve" && act !== "delete") return;
      if (act === "delete" && !confirm(a.logo
        ? "Delete this application now? Their contact details, photos and logo are deleted for good."
        : "Delete this application now? Their contact details and photos are deleted for good.")) return;
      $("[data-err]", f).textContent = "";
      $$("button", f).forEach((b) => (b.disabled = true));
      try {
        if (act === "delete") {
          await api("/api/admin/applications/reject", { id: a.id });
          flash(a.logo ? `Application from ${a.org_name} deleted, with its contact details, photos and logo.`
            : `Application from ${a.org_name} deleted, with its contact details and photos.`);
          el.remove();
          if (!$("#view .sub-card")) return render();
        } else {
          const r = await api("/api/admin/applications/approve", {
            id: a.id,
            name: f.elements.name.value.trim(),
            url: f.elements.url.value.trim() || null,
            country: f.elements.country.value.trim().toUpperCase(),
            slug: f.elements.slug.value.trim(),
            logo: a.logo && f.elements.use_logo && f.elements.use_logo.checked ? a.logo.key : null,
          });
          for (const shown of $$(".app-photos, .app-logo", el)) shown.remove(); // deleted or moved on approve, the signed links no longer matter
          f.replaceWith(welcomeBox(r.partner, { ...a, ...(r.application || {}) }));
          // If R2 failed, the server keeps the photo keys and its cleanup deletes them later.
          const left = (Array.isArray(a.photos) ? a.photos.length : 0) - (Number(r.deleted_photos) || 0);
          const name = r.partner.name;
          const said = {
            live: `${name} is now a partner, and their logo is on sapu.earth.`,
            declined: `${name} is now a partner, without their logo (deleted).`,
            review: `${name} is now a partner. Their logo waits under PARTNERS, LOGOS TO CHECK.`,
            gone: `${name} is now a partner. Their logo's file was missing, so they can add it on their crew page.`,
          }[r.logo] || `${name} is now a partner.`;
          flash(`${said} Send the link below now, it is shown only once.` +
            (left > 0 ? " Some photos could not be deleted yet, the cleanup tries again later." : ""));
          if (r.logo === "review") refreshPartnerCount();
        }
        refreshAppCount();
      } catch (e) {
        $("[data-err]", f).textContent = e.message;
        $$("button", f).forEach((b) => (b.disabled = false));
      }
    });
    return el;
  }

  function welcomeBox(partner, a) {
    const link = String(partner.upload_url || "");
    const wa = waDigits(a.whatsapp);
    const box = document.createElement("div");
    box.className = "secret welcome";
    box.innerHTML = `<b>Upload link for ${esc(partner.name)}</b>. Shown only once. Send it to ${n(a.contact_name) ? esc(a.contact_name) : "the crew"} privately, with the welcome message below.
      <span class="secret-link">${esc(link)}</span>
      <div class="box-head">
        <span>WELCOME MESSAGE</span>
        <div class="lang" role="group" aria-label="Message language">
          <button type="button" data-lang="en" aria-pressed="false">EN</button>
          <button type="button" data-lang="id" aria-pressed="false">ID</button>
        </div>
      </div>
      <textarea class="caption" readonly aria-label="Welcome message"></textarea>
      <div class="btn-row">
        <button type="button" class="b b-sm" data-act="copy-msg">COPY MESSAGE</button>
        ${wa ? `<a class="b b-sm b-ghost" href="https://wa.me/${wa}" target="_blank" rel="noopener noreferrer">OPEN WHATSAPP CHAT</a>` : ""}
        ${mailto(a.email) ? '<a class="b b-sm b-ghost" data-mail>EMAIL</a>' : ""}
        <button type="button" class="b b-sm b-ghost" data-act="copy-link">COPY LINK</button>
      </div>
      ${wa ? '<p class="hint">WhatsApp opens an empty chat. Copy the message first, then paste it there.</p>' : ""}`;
    const ta = $("textarea", box);
    const mail = $("[data-mail]", box);
    const show = (lang) => {
      ta.value = welcomeText(lang, a, link);
      $$("[data-lang]", box).forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
      if (mail) mail.href = mailto(a.email, MAIL_SUBJECT[lang], ta.value);
    };
    $$("[data-lang]", box).forEach((b) => b.addEventListener("click", () => show(b.dataset.lang)));
    $('[data-act="copy-msg"]', box).addEventListener("click", (ev) => copy(ta.value, ev.currentTarget));
    $('[data-act="copy-link"]', box).addEventListener("click", (ev) => copy(link, ev.currentTarget));
    show(a.lang === "id" ? "id" : "en");
    return box;
  }

  // Shown when REJECT is clicked: a ready decline message, then the real delete.
  // Nothing is sent automatically, and the contact details are gone once the application is deleted.
  function declineBox(a) {
    return replyBox({
      whatsapp: a.whatsapp, email: a.email, lang: a.lang === "id" ? "id" : "en",
      text: (lang) => declineText(lang, a), subject: DECLINE_SUBJECT,
      note: "Nothing is sent automatically. Once you delete, their contact details are gone, so reply before you delete.",
      deleteLabel: "DELETE APPLICATION",
    });
  }

  // A hidden box with a ready reply (EN / ID), COPY MESSAGE, WhatsApp and email, then the real delete
  // (data-act="delete") and CANCEL (data-act="cancel"). Used by applications, missions and PENDING cleanups.
  // extra: HTML under the note (the reasons of a cleanup's REJECT); box.refresh() writes the message again in the
  // language shown, after something that text() reads has changed.
  function replyBox({ whatsapp, email, lang, text, subject, note, deleteLabel, title = "Send a short reply first", label = "Decline message", extra = "" }) {
    const wa = waDigits(whatsapp);
    const box = document.createElement("div");
    box.className = deleteLabel ? "decline" : "decline msg-box";
    box.hidden = true;
    box.innerHTML = `<div class="box-head">
        <h4 class="box-title" tabindex="-1">${esc(title)}</h4>
        <div class="lang" role="group" aria-label="Message language">
          <button type="button" data-lang="en" aria-pressed="false">EN</button>
          <button type="button" data-lang="id" aria-pressed="false">ID</button>
        </div>
      </div>
      <p class="hint">${esc(note)}</p>${extra}
      <textarea class="caption" readonly aria-label="${esc(label)}"></textarea>
      <div class="btn-row">
        <button type="button" class="b b-sm" data-act="copy-decline">COPY MESSAGE</button>
        ${wa ? `<a class="b b-sm b-ghost" href="https://wa.me/${wa}" target="_blank" rel="noopener noreferrer">OPEN WHATSAPP CHAT</a>` : ""}
        ${mailto(email) ? '<a class="b b-sm b-ghost" data-mail>EMAIL</a>' : ""}
      </div>
      ${wa ? '<p class="hint">WhatsApp opens an empty chat. Copy the message first, then paste it there.</p>' : ""}
      <div class="btn-row">${deleteLabel
        ? `<button type="button" class="b b-red" data-act="delete">${esc(deleteLabel)}</button>
        <button type="button" class="b b-ghost" data-act="cancel">CANCEL</button>`
        : '<button type="button" class="b b-ghost" data-act="cancel">CLOSE</button>'}
      </div>`;
    const ta = $("textarea", box);
    const mail = $("[data-mail]", box);
    let shown = lang === "id" ? "id" : "en";
    const show = (l) => {
      shown = l;
      ta.value = text(l);
      $$("[data-lang]", box).forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === l)));
      if (mail) mail.href = mailto(email, subject[l], ta.value);
    };
    $$("[data-lang]", box).forEach((b) => b.addEventListener("click", () => show(b.dataset.lang)));
    $('[data-act="copy-decline"]', box).addEventListener("click", (ev) => copy(ta.value, ev.currentTarget));
    box.refresh = () => show(shown);
    show(shown);
    return box;
  }

  // ---------- missions ----------
  // Missions in review or open are removed by the server after 28 days without funding, and a funded
  // mission with no cleanup in PENDING counts as late 3 days and as overdue 14 days after its planned day
  // (lateDays and overdueDays in functions/_lib/missions.js, keep in step).
  const MISSION_DAYS = 28;
  const MISSION_WARN_DAYS = 21;
  const LATE_DAYS = 3;
  const OVERDUE_DAYS = 14;
  const ADVANCE_PCT = 30;
  const day = (iso) => String(iso || "").slice(0, 10);
  const daysAgo = (d) => (d === 0 ? "today" : d === 1 ? "1 day ago" : `${d} days ago`);

  function setMissionCount(count) {
    const c = Number(count);
    if (!Number.isFinite(c)) return;
    const b = $('[data-tab="missions"]');
    b.textContent = `MISSIONS (${c})`;
    b.classList.toggle("has-new", c > 0);
  }
  async function refreshMissionCount() {
    try {
      const r = await api("/api/admin/missions?status=review");
      if (r && r.counts) setMissionCount(r.counts.review);
    } catch { /* only a hint; the tab shows the error when opened */ }
  }

  async function renderMissions(view) {
    // The review list runs the 28-day expiry on the server first, so it goes before the other two.
    const review = await api("/api/admin/missions?status=review");
    const [open, funded] = await Promise.all(["open", "funded"].map((st) => api("/api/admin/missions?status=" + st)));
    if (tab !== "missions") return; // another tab was opened meanwhile
    const rows = (r) => (r && Array.isArray(r.missions) ? r.missions : []);
    const counts = (review && review.counts) || {};
    const count = (st, r) => (isNum(counts[st]) ? Number(counts[st]) : rows(r).length);
    setMissionCount(count("review", review));
    view.innerHTML = `<p class="am-month">Funded this month: <b>${esc(eur(review && isNum(review.month_eur) ? review.month_eur : 0))}</b></p>`;
    // The server sorts each list: oldest first, funded ones by their planned day.
    for (const [st, title, r, empty] of [
      ["review", "NEW", review, "No new missions. Crews post them from their upload link (POST A MISSION)."],
      ["open", "OPEN", open, "No open missions. PUBLISH shows a new one on the globe without funding it."],
      ["funded", "FUNDED", funded, "No funded missions right now."],
    ]) {
      const sec = document.createElement("section");
      sec.className = "am-sec";
      const list = rows(r);
      sec.innerHTML = `<h2 class="panel-title">${title} (${esc(count(st, r))})</h2>${list.length ? "" : `<p class="hint">${esc(empty)}</p>`}`;
      for (const m of list) sec.append(missionCard(m));
      view.append(sec);
    }
  }

  // What it says is deleted follows the mission: its photos, and its video when it has one.
  function missionDeclineText(lang, m) {
    const name = (m.contact && n(m.contact.contact_name)) || m.partner_name || "";
    const no = missionNo(m);
    if (lang === "id") {
      return `Halo ${name}, terima kasih sudah mengirim misi #${no} (${m.place_name}). ` +
        (m.now_video ? "Untuk saat ini kami belum bisa mendanai misi ini, jadi misi ini beserta foto dan videonya akan kami hapus. "
          : "Untuk saat ini kami belum bisa mendanai misi ini, jadi misi ini dan fotonya akan kami hapus. ") +
        "Kalian boleh mengirim misi lain kapan saja. Terima kasih sudah menjaga lingkungan kalian tetap bersih!\nMarcus, Sapu Earth";
    }
    return `Hi ${name}, thank you for posting mission #${no} (${m.place_name}). ` +
      (m.now_video ? "We can't fund this mission right now, so we will delete it, with its photos and video. "
        : "We can't fund this mission right now, so we will delete it and its photos. ") +
      "You are welcome to post another mission any time. Thank you for keeping your area clean!\nMarcus, Sapu Earth";
  }

  // The ready message for a funded mission: the money, the #N paper, safety, and how to send the cleanup.
  // Copied by hand into WhatsApp or email after the advance has gone out with Wise. Like the welcome message it
  // names no payment service, only where the money lands (see welcomeText).
  function missionFundedText(lang, m) {
    const name = (m.contact && n(m.contact.contact_name)) || m.partner_name || "";
    const hi = name ? " " + name : "";
    const no = missionNo(m);
    const total = isNum(m.funded_eur) ? Number(m.funded_eur) : null;
    const adv = isNum(m.advance_eur) ? Number(m.advance_eur) : 0;
    const rest = total !== null ? Math.max(0, cents(total - adv)) : null;
    // In the crew's own number and date format, as on their upload page: "EUR 37,50" and "14 November 2026".
    const money = (v) => (isNum(v)
      ? "EUR " + cents(v).toLocaleString(lang === "id" ? "id-ID" : "en", { minimumFractionDigits: Math.round(cents(v) * 100) % 100 ? 2 : 0, maximumFractionDigits: 2 })
      : "EUR ?");
    const ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(n(m.plan_date));
    const longDay = (iso) => { const x = /^(\d{4})-(\d{2})-(\d{2})$/.exec(n(iso)); return x ? new Date(+x[1], +x[2] - 1, +x[3]).toLocaleDateString(lang === "id" ? "id-ID" : "en-GB", { day: "numeric", month: "long", year: "numeric" }) : ""; };
    const dayText = longDay(m.plan_date);
    // The crew waits for our OK, so by FUND (or a later MESSAGE) the planned day may be gone: with several spots, the
    // last of their days (docs/missions.md, Spots). Then the message names each spot with its day.
    const t = new Date(), today = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
    const past = ymd && lastDay(m) < today, lastText = longDay(lastDay(m)), spots = spotsOf(m);
    if (lang === "id") {
      const where = "Kami kirim uangnya ke rekening bank atau e-wallet kalian, dan kalian menerimanya dalam rupiah, dengan kurs yang berlaku pada hari uang itu dikirim.";
      const pay = adv > 0
        ? `Sapu Earth membayar ${money(total)} untuk misi ini: ${money(adv)} sekarang sebagai uang muka, dan ${money(rest)} setelah laporan aksi bersih kalian kami setujui. ${where}`
        : `Sapu Earth membayar ${money(total)} untuk misi ini, seluruhnya setelah laporan aksi bersih kalian kami setujui. ${where}`;
      const when = past ? `Tanggal rencana kalian (${lastText}) sudah lewat. Pilih tanggal baru secepatnya dan kabari kami di sini. Pada hari itu:`
        : spots.length ? `Misi ini punya ${spots.length} titik: ${spots.map((s) => `${s.place_name} pada ${longDay(s.date)}`).join(", lalu ")}. Di setiap titik:`
        : `Pada harinya${dayText ? ` (${dayText})` : ""}:`;
      return `Halo${hi}! Kabar baik: misi #${no} (${m.place_name}) sudah didanai. ${pay}\n\n` +
        `${when}\n` +
        `- Ambil dulu foto sebelum dibersihkan, dan pegang kertas bertuliskan #${no} di salah satu foto itu.\n` +
        "- Di akhir, hitung karung yang sudah penuh, dan ambil foto sesudahnya dari tempat dan sudut yang sama.\n" +
        "- Bawa sampahnya ke bank sampah, pengepul, atau TPS/TPA resmi. Jangan dibakar, dan jangan tinggalkan karung berisi sampah di pinggir air.\n\n" +
        "Utamakan keselamatan:\n" +
        "- Semua orang pakai sarung tangan dan sepatu tertutup. Bawa air minum dan istirahat di tempat teduh.\n" +
        "- Jangan masuk ke air yang lebih dalam dari lutut atau yang berarus deras. Perhatikan pasang surut dan ombak. Jangan bekerja saat hujan lebat atau ada petir, atau tepat setelah hujan lebat.\n" +
        "- Tutup luka dengan plester, dan cuci tangan pakai sabun sebelum makan atau minum.\n" +
        "- Jangan sentuh jarum suntik, limbah medis, bahan kimia, atau baterai.\n" +
        "- Kru hanya orang dewasa (18 tahun ke atas). Kalau ada yang terasa tidak aman, berhenti.\n\n" +
        "Kalau kalian tidak bisa pada hari itu (hujan, sakit), kabari kami di sini dulu, nanti kita pilih hari baru bersama.\n" +
        (spots.length
          ? `Setelah titik terakhir selesai, buka halaman kru kalian (link pribadi yang kami kirim), tekan LAPOR AKSI BERSIH #${no}, tambahkan foto dan tanggal setiap titik serta jumlah karungnya, lalu tekan KIRIM LAPORAN.\n`
          : `Setelah selesai, buka halaman kru kalian (link pribadi yang kami kirim), tekan LAPOR AKSI BERSIH #${no}, tambahkan foto dan jumlah karungnya, lalu tekan KIRIM LAPORAN.\n`) +
        "Ada pertanyaan? Balas saja pesan ini.\nMarcus, Sapu Earth";
    }
    const where = "We send the money to your bank account or e-wallet. You receive it in your local money, at the exchange rate on the day we send it.";
    const pay = adv > 0
      ? `Sapu Earth pays ${money(total)} for it: ${money(adv)} now as an advance, and ${money(rest)} after we approve your cleanup. ${where}`
      : `Sapu Earth pays ${money(total)} for it, all of it after we approve your cleanup. ${where}`;
    const when = past ? `Your planned day (${lastText}) has passed. Please pick a new day soon and tell us here. On that day:`
      : spots.length ? `This mission has ${spots.length} spots: ${spots.map((s) => `${s.place_name} on ${longDay(s.date)}`).join(", then ")}. At each spot:`
      : `On the day${dayText ? ` (${dayText})` : ""}:`;
    return `Hi${hi}! Good news: mission #${no} (${m.place_name}) is funded. ${pay}\n\n` +
      `${when}\n` +
      `- Take the before photos first, and hold up a paper with #${no} written on it in one of them.\n` +
      "- At the end, count the full sacks, and take the after photos from the same spot and the same angle.\n" +
      "- Bring the trash to a waste bank, a collector or the official collection point. Never burn it, and don't leave full sacks by the water.\n\n" +
      "Safety first:\n" +
      "- Gloves and closed shoes for everyone. Bring drinking water and take breaks in the shade.\n" +
      "- Nobody goes into water deeper than the knee or into fast water. Watch the tide and the waves. No work in heavy rain or thunder, or right after heavy rain.\n" +
      "- Cover any cuts, and wash your hands with soap before you eat or drink.\n" +
      "- Leave needles, medical waste, chemicals and batteries alone.\n" +
      "- Only adults (18 or older) on the crew. If anything feels unsafe, stop.\n\n" +
      "If you can't go on that day (rain, illness), tell us here first, and we pick a new day together.\n" +
      (spots.length
        ? `After the last spot, open your crew page (the private link we sent you), tap SEND A CLEANUP FOR #${no}, add the photos and the day of each spot and the number of sacks, and tap SEND CLEANUP.\n`
        : `Afterwards open your crew page (the private link we sent you), tap SEND A CLEANUP FOR #${no}, add the photos and the number of sacks, and tap SEND CLEANUP.\n`) +
      "Questions? Just reply here.\nMarcus, Sapu Earth";
  }
  // After FUND the list is drawn again: the new funded card opens its message box once.
  let msgAfterFund = null;

  // What to send now and after the receipt. Same rounding as the server: the advance to the cent.
  function fundPlan(f) {
    const raw = f.elements.funded_eur.value.trim();
    const pctRaw = f.elements.advance_pct.value.trim();
    const total = Number(raw);
    const pct = pctRaw === "" ? ADVANCE_PCT : Number(pctRaw);
    if (!raw || !Number.isFinite(total) || total <= 0) return { error: "Type the EUR amount you agree to." };
    if (!Number.isFinite(pct) || pct < 0 || pct > 100) return { error: "The advance is 0 to 100 percent." };
    const advance = Math.round(total * pct) / 100;
    return { total, pct, advance, rest: cents(total - advance) };
  }

  function fundForm(m) {
    const no = missionNo(m);
    const f = document.createElement("form");
    f.className = "am-fund";
    f.hidden = true;
    f.noValidate = true;
    // The price as it adds up, the crew's pay inside it. The message after FUND stays in EUR only.
    const asked = payText(m.currency, m.price_local, m.crew_local, m.crew_size);
    f.innerHTML = `<h4 class="box-title">FUND MISSION #${esc(no)}</h4>
      <p class="hint">They ask ${asked ? esc(asked.text) : `${esc(m.currency || "")} ${esc(fmt(m.price_local))}`}. Funding shows the mission on the globe as funded, with its ${nowWhat(m)}.</p>
      <div class="edit-grid">
        <label class="field"><span>EUR we pay</span><input type="number" step="any" min="0" inputmode="decimal" name="funded_eur"></label>
        <label class="field"><span>Advance %</span><input type="number" step="1" min="0" max="100" inputmode="numeric" name="advance_pct" value="${ADVANCE_PCT}"></label>
        <label class="field wide"><span>Review note (internal)</span><input type="text" name="review_note" maxlength="1000" value="${esc(n(m.review_note))}"></label>
      </div>
      <p class="am-live" aria-live="polite"></p>
      <div class="btn-row">
        <button type="submit" class="b b-ok">FUND MISSION #${esc(no)}</button>
        <button type="button" class="b b-ghost" data-act="fund-close">CANCEL</button>
      </div>`;
    return f;
  }

  function missionCard(m) {
    const el = document.createElement("article");
    el.className = "sub-card am-card";
    const no = missionNo(m);
    const st = m.status;
    const link = no ? missionLink(no) : "";
    const photos = (Array.isArray(m.now) ? m.now : []).map((p) => safeMedia(p && p.url)).filter(Boolean);
    const video = m.now_video ? safeMedia(m.now_video.url) : "";
    const what = nowWhat(m);
    const posted = ageDays(m.created_at);
    // The 28-day clock runs from posting (review) or from publishing (open).
    const clock = st === "review" ? posted : st === "open" ? ageDays(m.published_at || m.created_at) : null;
    const left = clock !== null ? Math.max(0, MISSION_DAYS - clock) : null;
    const late = st === "funded" ? ageDays(lastDay(m)) : null;
    const overdue = st === "funded" && (typeof m.overdue === "boolean" ? m.overdue : late !== null && late >= OVERDUE_DAYS);
    // LATE before OVERDUE: the housekeeping counts a late mission, so the GitHub note emails Marcus about it.
    const lateNow = st === "funded" && !overdue && !m.pending_submission &&
      (typeof m.late === "boolean" ? m.late : late !== null && late >= LATE_DAYS);
    const price = isNum(m.price_local) ? Number(m.price_local) : null;
    const crew = isNum(m.crew_local) ? Number(m.crew_local) : null;
    const share = price > 0 && crew !== null ? Math.round((crew / price) * 100) : null;
    // The price as it adds up. A crew pay that does not split evenly (sent as one total, like mission #2) gets an orange
    // note: ask the crew what it meant before funding.
    const pt = payText(m.currency, m.price_local, m.crew_local, m.crew_size, { share: true });
    const adv = isNum(m.advance_eur) ? Number(m.advance_eur) : 0;
    const rest = isNum(m.funded_eur) ? Math.max(0, cents(Number(m.funded_eur) - adv)) : null;
    const c = m.contact && typeof m.contact === "object" ? m.contact : null;
    const wa = c ? waDigits(c.whatsapp) : "";
    const mail = c ? mailto(c.email) : "";
    const contact = c ? [
      n(c.contact_name) ? esc(c.contact_name) : "",
      n(c.whatsapp) ? esc(c.whatsapp) + (wa ? ` <a href="https://wa.me/${wa}" target="_blank" rel="noopener noreferrer">open chat ↗</a>` : "") : "",
      n(c.email) ? (mail ? `<a href="${esc(mail)}">${esc(c.email)}</a>` : esc(c.email)) : "",
    ].filter(Boolean).join(" · ") : "";
    const buttons = st === "review"
      ? `<button type="button" class="b b-ok" data-act="fund" aria-expanded="false">FUND</button>
         <button type="button" class="b" data-act="publish">PUBLISH</button>
         <button type="button" class="b b-red" data-act="decline" aria-expanded="false">DECLINE</button>`
      : st === "open"
        ? `<button type="button" class="b b-ok" data-act="fund" aria-expanded="false">FUND</button>
           <button type="button" class="b b-red" data-act="remove">REMOVE</button>`
        : st === "funded" ? `<button type="button" class="b b-ok" data-act="message" aria-expanded="false">MESSAGE</button>
           <button type="button" class="b b-red" data-act="cancel-mission">CANCEL MISSION</button>` : "";
    el.innerHTML = `<h3>#${esc(no || "?")} ${esc(m.place_name)}</h3>
      <div class="sub-meta">${esc(m.partner_name || "")} · ${esc(m.country || "??")} · ${spotsOf(m).length ? `${spotsOf(m).length} spots, days ${esc(n(m.plan_date) || "?")} to ${esc(lastDay(m))}` : `day ${esc(m.plan_date || "?")}`} · posted ${esc(day(m.created_at))}${posted !== null ? ` (${esc(daysAgo(posted))})` : ""}${st === "open" && m.published_at ? ` · published ${esc(day(m.published_at))}` : ""}</div>
      ${overdue ? `<p class="msg err am-overdue">OVERDUE: the planned day was ${esc(lastDay(m))}${late ? ` (${esc(daysAgo(late))})` : ""} and no cleanup is approved yet. Ask the crew, or cancel the mission.</p>` : ""}
      ${lateNow ? `<p class="msg err am-late">LATE: the planned day was ${esc(lastDay(m))}${late ? ` (${esc(daysAgo(late))})` : ""} and no cleanup came in yet. Ask the crew how it went, or agree on a new day with them.</p>` : ""}
      ${pt && pt.odd ? `<p class="msg err am-odd">Check the crew pay with the crew: ${esc(n(m.currency) || "?")} ${esc(fmt(crew))} for ${esc(fmt(m.crew_size))} ${Number(m.crew_size) === 1 ? "person" : "people"} is ${esc(pt.odd)}, not the same whole amount for each person.</p>` : ""}
      ${st === "funded" && m.pending_submission ? '<p class="msg ok">A cleanup for this mission is waiting in PENDING.</p>' : ""}
      ${left !== null && clock >= MISSION_WARN_DAYS ? `<p class="msg err">Removed automatically ${left ? `in ${left} day${left === 1 ? "" : "s"}` : "today"} if it is not funded (${MISSION_DAYS} days after ${st === "open" ? "publishing" : "posting"}).</p>` : ""}
      ${photos.length
        ? `<div class="am-photos">${photos.map((u) => `<a href="${esc(u)}" target="_blank" rel="noopener noreferrer"><img src="${esc(u)}" alt="" loading="lazy"></a>`).join("")}</div>`
        : '<p class="hint">No photos.</p>'}
      ${video ? `<div class="media-v"><h4>VIDEO</h4>${player(video)}</div>` : ""}
      <dl class="kv">
        ${spotsOf(m).length ? spotKv(m) : `<dt>Map</dt><dd>${osm(m)}</dd>`}
        <dt>Task</dt><dd>${esc(m.task || "")}</dd>
        <dt>Crew</dt><dd>${esc(n(m.crew_size) || "?")} people</dd>
        <dt>Price</dt><dd>${pt ? esc(pt.text) : price !== null
          ? `${esc(m.currency || "?")} ${esc(fmt(price))} total, ${esc(fmt(crew))} to the crew${share !== null ? ` (about ${esc(share)}%)` : ""}`
          : "not given"}</dd>
        ${st === "funded" ? `<dt>Funded</dt><dd>${esc(eur(m.funded_eur))}${m.funded_at ? ` on ${esc(day(m.funded_at))}` : ""}</dd>
        <dt>Advance</dt><dd>${adv > 0 ? `${esc(eur(adv))} when funded${isNum(m.funded_eur) && Number(m.funded_eur) > 0 ? ` (${esc(Math.round((adv / Number(m.funded_eur)) * 100))}%)` : ""}` : "none"}</dd>
        <dt>Rest</dt><dd>${esc(eur(rest))} after the receipt</dd>` : ""}
        ${m.private_note ? `<dt>Private message</dt><dd class="private">${esc(m.private_note)}</dd>` : ""}
        <dt>Consent</dt><dd>${m.consent ? "yes" : "NO"}</dd>
        <dt>Contact</dt><dd>${contact || "none on file"}</dd>
        ${m.review_note ? `<dt>Review note</dt><dd>${esc(m.review_note)}</dd>` : ""}
      </dl>
      ${link && (st === "open" || st === "funded") ? `<div class="am-share">
        <span class="hint">Share link</span>
        <span class="am-link">${esc(link)}</span>
        <div class="btn-row">
          <button type="button" class="b b-sm b-ghost" data-act="copy-share">COPY LINK</button>
          <a class="b b-sm b-ghost" href="/m/${esc(no)}" target="_blank" rel="noopener">OPEN</a>
        </div>
      </div>` : ""}
      <div class="am-actions">
        <div class="btn-row">${buttons}</div>
        <div class="msg err" data-err></div>
      </div>`;

    const errBox = $("[data-err]", el);
    const row = $(".am-actions > .btn-row", el);
    const fund = st === "review" || st === "open" ? fundForm(m) : null;
    // DECLINE only opens the reply box. Deleting is a second, separate step inside it.
    const decline = st === "review" ? replyBox({
      whatsapp: c && c.whatsapp, email: c && c.email,
      lang: (c && c.lang === "id") || m.country === "ID" ? "id" : "en",
      text: (l) => missionDeclineText(l, m),
      subject: { en: `Your Sapu Earth mission #${no}`, id: `Misi Sapu Earth #${no}` },
      note: wa || mail
        ? "Nothing is sent automatically. Send the reply, then delete the mission."
        : "Nothing is sent automatically. There is no WhatsApp or email on file for this partner, so send it the way you usually reach them. Then delete the mission.",
      deleteLabel: "DELETE MISSION",
    }) : null;
    // MESSAGE on a funded card: the ready "it is funded" message, with no delete step.
    const msg = st === "funded" ? replyBox({
      whatsapp: c && c.whatsapp, email: c && c.email,
      lang: (c && c.lang === "id") || m.country === "ID" ? "id" : "en",
      text: (l) => missionFundedText(l, m),
      subject: { en: `Mission #${no} is funded`, id: `Misi #${no} sudah didanai` },
      title: "Tell the crew it is funded", label: "Funded message",
      note: (wa || mail ? "Nothing is sent automatically. " : "Nothing is sent automatically, and there is no WhatsApp or email on file for this partner, so send it the way you usually reach them. ") +
        "Send the advance with Wise first, then this message.",
    }) : null;
    if (decline) row.after(decline);
    if (fund) row.after(fund);
    if (msg) row.after(msg);
    const opener = (box) => $(`[data-act="${box === fund ? "fund" : box === msg ? "message" : "decline"}"]`, el);
    // Shows one box (or none) and moves the focus there, or back to its button.
    const show = (box) => {
      const was = [fund, decline, msg].find((b) => b && !b.hidden);
      for (const b of [fund, decline, msg]) {
        if (!b) continue;
        b.hidden = b !== box;
        const o = opener(b);
        if (o) o.setAttribute("aria-expanded", String(b === box));
      }
      errBox.textContent = "";
      if (box && box === fund) fund.elements.funded_eur.focus(); // a funded card has no FUND form
      else if (box) $(".box-title", box).focus();
      else if (was && opener(was)) opener(was).focus();
    };
    const busy = (on) => $$("button", el).forEach((b) => (b.disabled = on));
    async function decide(action, extra, okText) {
      errBox.textContent = "";
      busy(true);
      try {
        // revision: PUBLISH and FUND only go through for the version shown on this card; video: the video it
        // plays, so a mission's video never goes public unseen.
        const r = await api("/api/admin/missions/decide", { id: m.id, action, revision: m.revision, video: video ? m.now_video.key : null, ...extra });
        flash(okText(r || {}));
        render();
      } catch (e) {
        // The crew changed it meanwhile: show the new version instead of a stale card.
        if (e.code === "changed") { flash(e.message, false); render(); return; }
        errBox.textContent = e.message;
        busy(false);
      }
    }

    if (fund) {
      const live = $(".am-live", fund);
      const update = () => {
        const p = fundPlan(fund);
        live.textContent = p.error || `Send ${eur(p.advance)} now, ${eur(p.rest)} after the receipt.`;
      };
      fund.addEventListener("input", update);
      update();
      fund.addEventListener("submit", (ev) => {
        ev.preventDefault();
        const p = fundPlan(fund);
        if (p.error) { errBox.textContent = p.error; fund.elements.funded_eur.focus(); return; }
        decide("fund", { funded_eur: p.total, advance_pct: p.pct, review_note: fund.elements.review_note.value.trim() || null }, (r) => {
          msgAfterFund = m.id;
          return `Mission #${no} is funded with ${eur(p.total)}. Send ${eur(isNum(r.advance_eur) ? r.advance_eur : p.advance)} now with Wise, ` +
            `${eur(isNum(r.rest_eur) ? r.rest_eur : p.rest)} after the receipt. Then send the crew the message on its card.`;
        });
      });
    }

    if (msg && msgAfterFund === m.id) { msgAfterFund = null; queueMicrotask(() => show(msg)); }

    el.addEventListener("click", (ev) => {
      const t = ev.target.closest("[data-act]");
      if (!t || !el.contains(t)) return;
      const act = t.dataset.act;
      if (act === "fund") return show(fund && fund.hidden ? fund : null);
      if (act === "decline") return show(decline && decline.hidden ? decline : null);
      if (act === "message") return show(msg && msg.hidden ? msg : null);
      if (act === "fund-close" || act === "cancel") return show(null);
      if (act === "copy-share") return copy(link, t);
      if (act === "publish") {
        if (!confirm(`Show mission #${no} on the globe as open, without funding it yet? Its ${what} become public.`)) return;
        return decide("publish", {}, () => `Mission #${no} is on the globe as open: ${link}`);
      }
      if (act === "delete") {
        if (!confirm(`Delete mission #${no} now? Its ${what} are deleted for good.`)) return;
        return decide("decline", {}, () => `Mission #${no} declined and deleted, with its ${what}.`);
      }
      if (act === "remove") {
        if (!confirm(`Remove mission #${no} from the site? Its ${what} are deleted for good.`)) return;
        return decide("remove", {}, () => `Mission #${no} removed from the site, with its ${what}.`);
      }
      if (act === "cancel-mission") {
        if (!confirm(`Cancel mission #${no}? The advance stays with the crew. Its ${what} are deleted for good.` +
            (m.pending_submission ? " A cleanup for it is waiting in PENDING: approving that cleanup later does not mark the mission done." : ""))) return;
        return decide("cancel", {}, () => `Mission #${no} cancelled. Its ${what} are deleted.`);
      }
    });
    return el;
  }

  // ---------- start ----------
  if (token) {
    $("#login").hidden = true;
    api("/api/admin/partners").then(openApp, () => {});
  } else {
    showLogin();
  }
})();

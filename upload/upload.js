/* Sapu Earth partner upload page: the crew's own page (YOUR CREW PAGE). No build step, no dependencies.
   Made for cheap Android phones on slow networks: photos are shrunk on the phone,
   video location data is removed on the phone, files go up one at a time with retries,
   and nothing typed or picked is thrown away (fields in localStorage, files in IndexedDB).
   Three screens on one address: the crew page (#home: the crew's missions as cards with the next step,
   unsent work, the lists), POST A MISSION (#mform, docs/missions.md) and a cleanup (#form), opened from a
   funded mission's card with what the mission already says, or without a mission. The two forms share the
   upload pipeline. Each screen is a history entry of its own, so the phone's back button goes back to the
   crew page (docs/upload-flow.md, On the pages).
   Videos: the cleanup has one field for a video before the cleanup and one for a video after it (sent
   with their stage), the mission one for a video of the spot now. One clip per field. */
(function () {
  "use strict";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  // /upload/#privacy opens the notice. This line was an inline script in the page; the site's script policy
  // (_headers) allows none, so it runs first thing here, before anything waits.
  if (location.hash === "#privacy" && $("#privacy")) $("#privacy").open = true;
  // The private link is the crew's only key. A link pasted with a "." or ")" after it, or with a space in
  // it, still opens: only the token's own characters count, and the address bar gets the clean link, so a
  // saved or bookmarked link is clean too.
  const rawToken = new URLSearchParams(location.search).get("k") || "";
  const token = rawToken.replace(/[^A-Za-z0-9_-]/g, "");
  if (token && token !== rawToken) {
    try { history.replaceState(history.state, "", `${location.pathname}?k=${token}${location.hash}`); } catch { /* keep the address */ }
  }
  const tokenTag = token.slice(0, 8);
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
    del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
  };

  // ---------- text ----------
  const T = {
    en: {
      title: "YOUR CREW PAGE",
      title_mission: "POST A MISSION",
      title_cleanup_m: "CLEANUP FOR MISSION #{no}", title_plain: "CLEANUP WITHOUT A MISSION",
      back: "CREW PAGE", to_home: "BACK TO YOUR CREW PAGE",
      checking: "Checking your link…",
      uploading_as: "Crew:",
      bad_link: "This upload link is not valid anymore. Write to hello@sapu.earth, or reply to our WhatsApp or email message, and we send you a new link.",
      no_link: "This page needs your personal upload link: open it from our WhatsApp or email message. Lost it? Write to hello@sapu.earth and we send you a new one. New crew? Apply at sapu.earth/apply",
      offline_link: "Could not reach sapu.earth. Check your internet connection, then reload this page.",
      save_h: "SAVE THIS LINK",
      save_body: "This page is your private key to Sapu Earth. Save it now so you can open it again any time. Don't post it in public: anyone with this link can post missions and send cleanups in your name.",
      tip_ios: "On iPhone: tap ⋯ (or the Share button), then Share, then Add to Home Screen. Scroll down if you don't see it.",
      tip_android: "In Chrome: tap the menu (three dots ⋮), then Install and create shortcut, then Create shortcut, then Add. On older Chrome, tap Add to Home screen instead. In another browser, bookmark this page.",
      tip_samsung: "In Samsung Browser or Samsung Internet: tap the menu (⋮ or ≡) at the bottom right, then Add page to, then Home screen.",
      tip_home: "You opened this page from your home screen, so the link is saved there.",
      tip_other: "Bookmark this page.",
      save_share: "SEND TO MYSELF", save_copy: "COPY LINK", save_done: "DONE, I SAVED IT",
      save_again: "How to save this link",
      // The crew page (#home): the first step, the cards of the crew's missions, unsent work and the lists.
      mode_cleanup: "SEND A CLEANUP",
      mode_mission: "POST A MISSION", mode_mission_sub: "A dirty spot you want to clean. Ask Sapu Earth to fund it.",
      intro_h: "FIRST STEP: POST A MISSION",
      intro_body: "Find a dirty spot near you, take photos of it, and post it here as a mission with your price. Sapu Earth checks it and tells you if it is funded. Only funded missions are paid.",
      intro_1: "Post a mission", intro_2: "Wait until it is funded", intro_3: "Clean, then send the cleanup",
      m_limit_home: "You have 5 missions that are waiting for Sapu Earth, on sapu.earth or funded. You can post a new one once we approve the cleanup of a funded one, or after you withdraw one that is not funded yet.",
      plain_btn: "SEND A CLEANUP WITHOUT A MISSION",
      plain_sub: "Only funded missions are paid. Use this for a cleanup that was not one of your missions.",
      past_h: "PAST MISSIONS", past_removed: "Not funded or closed ({n})",
      page_h: "YOUR PUBLIC PAGE",
      // YOUR PUBLIC PAGE, once the crew is in the list of crews at sapu.earth/crews (GET /api/partner's listed).
      crews_listed: "Your crew is also in the list of all crews on sapu.earth.", crews_open: "SEE ALL CREWS",
      // YOUR LOGO (docs/upload-flow.md, Crew logos): the tile's line for each state, the rules above the button, and
      // what went wrong with a pick. A 404 while sending says bad_link.
      logo_h: "YOUR LOGO", logo_add: "+ ADD YOUR LOGO", logo_change: "CHANGE LOGO", logo_pick: "Your crew's logo",
      logo_none: "Add your crew's logo. Once Sapu Earth approves it, it shows next to your crew's name on sapu.earth.",
      logo_rules: "Your crew's own logo, or a close-up photo of the logo on your banner or shirt, with the logo filling the picture. No photos of people, no phone or bank account numbers, no QR codes, and no other organization's logo.",
      logo_preparing: "Preparing your logo…",
      logo_sending: "Sending your logo…",
      logo_review: "Waiting for Sapu Earth. We check it, usually within a few days. Once we approve it, it shows on sapu.earth.",
      logo_review_live: "Your new logo is waiting for Sapu Earth. Until we have checked it, sapu.earth keeps showing your current logo.",
      logo_live: "Your logo shows next to your crew's name on sapu.earth.",
      logo_declined: "Sapu Earth could not use the logo you sent. Tap + ADD YOUR LOGO to send another one.",
      logo_declined_live: "Sapu Earth could not use your new logo, so sapu.earth keeps showing this one.",
      e_logo_read: "This picture could not be opened on this phone. Choose your logo as a JPG or PNG picture.",
      e_logo_small: "This picture is too small for a logo. Choose a bigger one.",
      e_logo_send: "Your logo was not sent. Check your internet connection and try again.",
      e_logo_limit: "You sent many logos today. Please try again tomorrow.",
      e_logo_refused: "This picture was not accepted. Try another picture.",
      card_ready: "READY TO CLEAN", card_today: "TODAY",
      card_day: "Cleanup day: {day}", card_planned: "Planned day: {day}",
      card_day_past: "The planned day ({day}) has passed. If the day changed and you have not told us yet, reply to our message with the new day.",
      card_send: "SEND A CLEANUP FOR #{no}", card_continue: "CONTINUE THE CLEANUP FOR #{no}",
      card_progress: "Not sent yet. Before photos: {b}. After photos: {a}. Saved on this phone.",
      draft_photos: "Before photos: {b}. After photos: {a}.",
      st_review_body: "We are checking this mission and will tell you if it is funded. Don't start before it is funded: only funded missions are paid.",
      st_open_body: "Share it so more people see it. Don't start before it is funded.",
      st_sent_body: "We check your cleanup, usually within a few days. Once we approve it, it is shown on sapu.earth and we send you the rest of the money.",
      st_sent_body_all: "We check your cleanup, usually within a few days. Once we approve it, it is shown on sapu.earth and we send you the money.",
      share_m: "Share mission #{no}", withdraw_m: "Withdraw mission #{no}",
      draft_c_h: "CLEANUP NOT SENT YET", draft_m_h: "MISSION NOT POSTED YET",
      draft_body: "What you typed and picked is saved on this phone.",
      draft_gone: "Mission #{no} cannot take a cleanup anymore, so what you started is now a cleanup without a mission. Check the place name, country and crew size.",
      draft_go: "CONTINUE", draft_del: "DELETE",
      draft_del_q: "Delete what you have not sent? Its photos, videos and answers are removed from this phone.",
      switch_q: "You started the cleanup for mission #{from} on this phone and did not send it. Start the cleanup for mission #{to} instead? What you added for mission #{from} is then removed from this phone.",
      switch_plain_q: "You started the cleanup for mission #{from} on this phone and did not send it. Start a cleanup without a mission instead? What you added for mission #{from} is then removed from this phone.",
      move_q: "You started a cleanup without a mission on this phone. Use what you added there for the cleanup of mission #{to}?",
      // A cleanup: the mission it is for, or the question about a funded mission when it has none.
      mission_pick: "Which mission is this cleanup for?", no_mission: "No mission",
      sum_kicker: "MISSION", sum_planned: "planned {day}", sum_change: "CHANGE",
      guard_q: "Is this the cleanup for mission #{no} ({place})?", guard_yes: "YES, FOR #{no}",
      paper_hint: "Write #{no} in big numbers on a sheet of paper and hold it up in one before photo. We need it to approve the cleanup.",
      // A mission with several spots (docs/missions.md, Spots): the photos and the day of each spot, {n} its number.
      paper_hint_spots: "Write #{no} in big numbers on a sheet of paper and hold it up in one before photo at each spot. We need it to approve the cleanup.",
      before_hint_spots: "This mission has {n} spots. Add 1 to 4 photos at each spot before you start, from where you can see the whole spot.",
      after_hint_spots: "1 to 4 photos at each spot at the end, from the same places and the same angles as its before photos.",
      spot_field: "Spot {n}: {place}", spot_day: "Day at spot {n}: {place}",
      spot_before_aria: "Photos before the cleanup at spot {n}", spot_after_aria: "Photos after the cleanup at spot {n}",
      sum_planned_spots: "{n} spots, planned {from} to {to}", sum_planned_spots_1: "{n} spots, planned {day}",
      card_spot: "Spot {n}: {place} ({day})",
      before_h: "BEFORE THE CLEANUP", before_hint: "1 to 4 photos before you start, from where you can see the whole spot.",
      after_h: "AFTER THE CLEANUP", after_hint: "1 to 4 photos at the end, from the same spots and the same angles as the before photos.",
      before: "Photos before the cleanup", after: "Photos after the cleanup",
      add_photos: "+ Add photos", add_video: "+ Add video",
      video_before: "Video before the cleanup (optional)",
      video_after: "Video after the cleanup (optional)",
      videos_hint: "One video before and one after the cleanup. Short vertical clips of 15 to 30 seconds work best and send faster. Limit: 90 seconds and 95 MB each.",
      date: "Cleanup date", place: "Place name", place_ph: "Canggu river mouth",
      location: "Location", use_location: "Use my location now", locating: "Finding your location…",
      geo_hint: "Only tap this while you are at the cleanup spot.",
      geo_hint_m: "Only tap this while you are at the cleanup spot. If you skip it, the cleanup gets the location of mission #{no}, if it has one.",
      geo_fail: "Could not get your location. That is fine, you can still send without it.",
      geo_ok: "Location saved", geo_clear: "Remove",
      country: "Country",
      result_h: "RESULT",
      result_hint: "Fill in sacks, kg, or both. Estimates are fine, just be honest.",
      kg: "Trash weight (kg)", sacks: "Number of full sacks", crew: "Crew size", hours: "How many hours did the cleanup take?",
      plan_day_btn: "As planned: {day}",
      crew_src: "From mission #{no}. Change it if a different number of people worked.",
      crew_src_last: "Same as mission #{no}. Change it if it is different this time.",
      disposal: "Where did the trash go?", disposal_ph: "Waste bank, collector, landfill",
      // Chips: one tap writes what the crew used before into a field, never by themselves.
      chips_place: "Places you used before:", chips_disposal: "Tap to fill in:",
      disp_bank: "Waste bank", disp_collector: "Collector", disp_official: "Official collection point",
      chip_task: "Use the plan from mission #{no}: {task}",
      chip_price: "Same as mission #{no}: {each} for each person, {other} other costs",
      chip_price_0: "Same as mission #{no}: {each} for each person, no other costs",
      money_h: "COSTS",
      cost_paid: "Sapu Earth pays EUR {eur} for mission #{no}.",
      // {line} is price_line below: the mission's price as it adds up.
      cost_receipt_plan: "The public receipt shows your price: {line}. Fill in the costs only if the real costs were different.",
      cost_receipt: "The public receipt shows the price you asked, with the crew's pay. Fill in the costs only if the real costs were different.",
      cost_crew: "The mission was planned with a crew of {plan}, and {now} worked. If the pay changed, fill in the costs.",
      cost_toggle: "THE COSTS WERE DIFFERENT",
      money_hint: "In your local currency. These numbers make our reports transparent.",
      currency: "Currency", currency_code: "Currency code", other: "Other", choose: "Choose…",
      // COSTS adds up like PRICE: what each person got × the crew size under RESULT, plus the other costs.
      got_each: "What each person got", c_sum_h: "TOTAL COST",
      sum_people_c: "First write the crew size under RESULT.",
      e_each_c: "Write what each person got, or 0 if nobody was paid.",
      notes: "Notes (shown on the public receipt)", notes_ph: "A short story about the day",
      // The link to the crew's own post about the cleanup (docs/upload-flow.md, Post links and thanks): the field, its
      // hint and rules, the line under it once the link is read ({site} Instagram or TikTok, {link} the stored link
      // without https://www.), and what is wrong with a link that is not one post, or a short link.
      post: "Link to your post about this cleanup (optional)",
      post_hint: "Posted this cleanup on Instagram or TikTok? Paste the link here, so the receipt can link your post and people can comment there. Instagram: tap Share, then Copy link. TikTok: the app copies a short link we cannot check, so paste it into your browser's address bar first, then copy the full address from there.",
      post_rules: "Only your own post about this cleanup: no request for money or bank numbers, and only people who agreed to be shown. Otherwise we take the link off and tell you why.",
      post_ok: "Link to your {site} post: {link}",
      e_post_link: "This is not the link to one post on Instagram or TikTok. Copy the link of the post itself (Instagram: Share, then Copy link), or leave this empty.",
      e_post_short: "Short links (like vt.tiktok.com or instagram.com/share/) cannot be checked. Paste the link into your browser's address bar, wait until the post shows, then copy the full address from there (tiktok.com/@... or instagram.com/...). Or leave this empty.",
      private_note: "Message to Sapu Earth (private)", private_note_ph: "Only the Sapu Earth team reads this.",
      consent: "Everyone in these photos and videos agreed to be shown on sapu.earth, on social media and in Sapu Earth's marketing, and no children appear in them. Sapu Earth may use, edit and share these photos and videos to show and promote its work.",
      send: "SEND CLEANUP", try_again: "TRY AGAIN",
      keep_open: "Keep this page open and the screen on until you see THANK YOU.",
      thanks: "THANK YOU!",
      thanks_body: "Your cleanup was sent. We check every upload and publish it on sapu.earth, usually within a few days.",
      ref: "Reference",
      page_note: "When it is approved, your cleanup will appear on your page:",
      share_page: "SHARE YOUR PAGE", share: "SHARE", copied: "COPIED",
      mine_h: "YOUR CLEANUPS",
      st_pending: "Waiting for review", st_approved: "Published", st_rejected: "Not approved",
      // Thanks under YOUR CLEANUPS (docs/upload-flow.md, Thanks). {n} is a number, {btn} the button's words.
      mine_thanked: "thanked {n} times",
      mine_thanked_1: "thanked once",
      ty_total: "Visitors on sapu.earth thanked your crew {n} times.",
      ty_total_1: "Visitors on sapu.earth thanked your crew once.",
      ty_note: "Anyone can tap {btn} under your receipts on sapu.earth. It is not money, only a sign that people value your crew's work, and it counts taps, not people. Share your receipts so more people see them.",
      m_photos_h: "THE SPOT NOW",
      m_photos_hint: "1 to 4 photos of the dirty spot as it looks today. They are shown on sapu.earth with your mission.",
      now: "Photos of the spot now",
      now_video: "Video of the spot now (optional)",
      now_video_hint: "One short vertical clip. 15 to 30 seconds work best and send faster. Limit: 90 seconds and 95 MB. It is shown on sapu.earth with your mission.",
      m_where_h: "WHERE",
      m_geo_hint: "Only tap this while you are at the spot. Without a location the mission is not shown on the map.",
      m_plan_h: "THE PLAN",
      m_plan_hint: "What you write here is shown on sapu.earth with your mission. One or two sentences are enough.",
      task: "What will you do?",
      task_ph: "Pick up the plastic at the river mouth and on the beach next to it, sort it, bring it to the waste bank.",
      plan_date: "Planned day",
      plan_date_hint: "Pick a day at least a week ahead, so Sapu Earth has time to check the mission before the day.",
      safety_h: "SAFETY FIRST",
      safety_1: "Gloves and closed shoes for everyone. Bring drinking water and take breaks in the shade.",
      safety_2: "Nobody goes into water deeper than the knee or into fast water. Watch the tide and the waves. No work in heavy rain or thunder, or right after heavy rain.",
      safety_3: "Leave needles, medical waste, chemicals and batteries alone. Say where they are in your message to Sapu Earth.",
      safety_4: "Only adults (18 or older) on the crew. Children stay away from the water and out of the photos and videos.",
      safety_5: "Cover any cuts, and wash your hands with soap before you eat or drink. River and flood water can make people sick.",
      safety_6: "Bring the trash to a waste bank, a collector or the official collection point. Never burn it, and don't leave full sacks by the water.",
      safety_7: "If anything feels unsafe, stop.",
      safety_price: "Put gloves, sacks, drinking water, a small first aid kit and transport in OTHER COSTS, under PRICE.",
      m_money_h: "PRICE",
      m_money_hint: "In your local currency. The page works out your price: the number of people × the pay for each person, plus the other costs. Your price and how it adds up are shown with your mission. Sapu Earth decides if and how much it funds.",
      // PRICE (and COSTS, which shares other_costs, other_hint and the sum lines): the crew never types a total. The
      // line under the pay shows the crew's pay (sum_crew), the box under the other costs the whole price (sum_parts).
      // {n} people, {each} the pay for each person, {crew} the crew's pay in all, {other} the other costs, {total} the
      // price; every amount with its currency code ("IDR 100,000"), as amt() writes it.
      m_crew: "How many people will work?", m_each: "Pay for each person",
      other_costs: "Other costs",
      other_hint: "Everything besides the pay: gloves, sacks, drinking water, a small first aid kit and transport. One amount for all of it.",
      m_sum_h: "YOUR PRICE, IN ALL",
      sum_crew: "{n} people × {each} = {crew} for the crew", sum_crew_1: "1 person × {each} = {crew} for the crew",
      sum_people_m: "First write the number of people above.",
      sum_parts: "{crew} for the crew + {other} other costs = {total}", sum_parts_0: "{crew} for the crew, no other costs",
      sum_wait: "The total shows here once the number of people and the pay for each person are written.",
      e_money: "Write only the number, for example 100000 or 100,000, not 100k.",
      e_each: "Write the pay for each person. Write 0 if nobody is paid.",
      e_sum_zero: "Your price is 0. Write the pay for each person or the other costs.",
      // A stored price in one line (priceLine): on the done screen, the cards of missions in review, open and funded,
      // and the cleanup's cost line. price_line_old: a crew pay that does not split evenly (sent as one total, like
      // mission #2), with its head count, never as a pay for each person.
      price_line: "{total} in all, with {n} × {each} for the crew and {other} other costs",
      price_line_0: "{total} in all, all of it for the crew ({n} × {each})",
      price_line_old: "{total} in all, with {crew} for the crew of {n}",
      price_line_unpaid: "{total} in all, all of it other costs, with no pay for the crew",
      m_done_price: "Your price: {line}. If this is not right, tell us before we fund it.",
      card_price: "The price you asked: {line}.",
      m_consent: "Everyone in these photos and videos agreed to be shown on sapu.earth, on social media and in Sapu Earth's marketing, no children appear in them, and everyone we pay is 18 or older. Sapu Earth may use, edit and share these photos and videos to show and promote its work.",
      m_send: "POST MISSION",
      m_keep_open: "Keep this page open and the screen on until you see your mission number.",
      m_done_big: "MISSION #{no}",
      m_done_body: "Mission #{no} sent. Sapu Earth checks it and tells you if it is funded. Please don't start the cleanup before you hear from us, because only funded missions are paid.",
      m_done_updated: "Mission #{no} was already sent, and now has your changes. Sapu Earth checks it and tells you if it is funded. Please don't start the cleanup before you hear from us, because only funded missions are paid.",
      m_done_share: "Once it is on sapu.earth, you can share it from your crew page.",
      my_missions_h: "YOUR MISSIONS",
      ms_review: "Waiting for Sapu Earth", ms_open: "On sapu.earth, not funded yet", ms_done: "Done",
      ms_funded: "Funded: EUR {eur}", ms_funded_plain: "Funded", ms_advance: "Advance of EUR {eur} on its way to you",
      ms_cleanup_sent: "Cleanup sent, waiting for review",
      rm_declined: "Not funded", rm_expired: "Not funded, removed after 28 days", rm_withdrawn: "Withdrawn by you",
      rm_cancelled: "Cancelled by Sapu Earth", rm_unpublished: "Taken off the site", rm_deactivated: "Closed",
      funded_todo: "Hold up a paper with #{no} in one before photo.",
      funded_todo_spots: "Hold up a paper with #{no} in one before photo at each spot.",
      withdraw: "WITHDRAW",
      withdraw_q: "Withdraw mission #{no}? It is removed and its photos and any video are deleted.",
      e_withdraw: "Could not withdraw the mission. Check your connection and try again.",
      e_withdraw_late: "Mission #{no} is already funded or closed, so it cannot be withdrawn.",
      reload_note: "Your answers were restored, but please add the photos and videos again.",
      e_before: "Add at least one photo from before the cleanup.", e_after: "Add at least one photo from after the cleanup.",
      e_before_spot: "Add at least one photo from before the cleanup at spot {n}.", e_after_spot: "Add at least one photo from after the cleanup at spot {n}.",
      e_spot_day: "Write the day you cleaned spot {n}. It cannot be in the future.",
      e_place: "Write the place name.", e_date: "Choose the cleanup date. It cannot be in the future.",
      e_amount: "Fill in the number of sacks or the trash weight (kg).",
      e_crew: "Write how many people worked.", e_consent: "Please tick the consent box.",
      e_country: "Choose the country.", e_currency: "Write a 3-letter currency code, for example MYR.",
      e_currency_pick: "Choose the currency.",
      e_number: "Check this number. Write only the number, for example 1500000 or 12.5.",
      e_now: "Add 1 to 4 photos of the spot as it looks now.",
      e_task: "Write what you will do.",
      e_plan_date: "Choose the planned day, from today up to 4 months ahead.",
      e_m_crew: "Write how many people will work.",
      e_fix: "Some fields still need fixing. See the fields marked in orange.",
      e_decode: "This photo could not be opened on this phone. Please choose a JPG photo. If your camera saves photos as HEIF or HEIC, turn that off in the camera settings and take the photo again.",
      e_photo_big: "This photo file is too big. Please choose another photo.",
      e_max_photos: "At most 4 photos here.", e_max_videos: "Only one video here. Remove it first to choose another.",
      e_video_type: "This video type is not supported. Please use MP4, MOV or WebM.",
      e_video_big: "This video is larger than 95 MB. Please trim it to about 30 seconds, or record again at 720p.",
      e_video_long: "This video is too long. Please keep it under 90 seconds.",
      e_video_check: "This video could not be checked for location data, so it was not added. Reload the page and try again, or choose another video.",
      preparing: "Preparing photo…",
      preparing_files: "Preparing your photos and videos…",
      up_file: "Uploading file {i} of {n}…",
      up_file_mb: "Uploading file {i} of {n}… {a} of {b} MB",
      retrying: "Connection problem. Trying again in {s} seconds…",
      retrying_1: "Connection problem. Trying again in 1 second…",
      waiting_online: "You are offline. Waiting for the connection to come back…",
      sending: "Sending the details…",
      e_upload: "A file could not be uploaded. Your form is saved. Tap TRY AGAIN.",
      e_upload_video: "The video could not be uploaded. Your form is saved. Tap TRY AGAIN, or remove the video to send without it. Videos are optional.",
      e_upload_fatal: "One file could not be sent. Remove the file marked in orange, then tap TRY AGAIN.",
      e_limit: "You sent many files today. Please try again tomorrow. Your form is saved.",
      e_media: "Some files need to be sent again. Your form is saved. Tap TRY AGAIN.",
      e_rejected: "Something in the form was not accepted. Please check the numbers and the date, then try again.",
      e_submit: "Sending failed. Your form is saved. Tap TRY AGAIN.",
      e_m_limit: "You have 5 missions that are waiting for Sapu Earth, on sapu.earth or funded. You can post a new one once we approve the cleanup of a funded one, or after you withdraw one that is not funded yet. Your form is saved.",
      e_m_unavailable: "Missions are not open yet. Your form is saved. Please try again later.",
      e_mission_gone_alone: "This mission cannot take a cleanup anymore. Check the place name, country and crew size, then tap TRY AGAIN to send it without a mission.",
      e_mission_taken_alone: "A cleanup for this mission was already sent. To send this one too, check the place name, country and crew size, then tap TRY AGAIN. It will be sent without a mission.",
      e_m_resend: "This mission was already sent and can no longer be changed here. See your crew page. To post it as a new mission, tap TRY AGAIN.",
      remove: "Remove",
      // The privacy notice (#privacy). It is a promise: change it together with the code it describes
      // (docs/upload-flow.md, Privacy notices for crews and visitors).
      pv_sum: "How we handle your photos, videos and details",
      pv_foot: "PRIVACY",
      pv_who_h: "Who:", pv_who: "Sapu Earth is run by Marcus Pousette in Innsbruck, Austria. Contact:",
      pv_what_h: "What you send:",
      pv_what: "photos and videos (they may show people), the date, the place and the country, the exact location if you tap Use my location now, the numbers (kg, sacks, crew size, hours, costs and pay), where the trash went, your notes, the link to your post about the cleanup on Instagram or TikTok if you add one, and your message to Sapu Earth. For a mission also your plan, the day and the price. And your crew's logo, if you add one.",
      pv_public_h: "What is public:",
      pv_public: "once we approve a cleanup, it is a public receipt on sapu.earth with everything you sent, except your message to Sapu Earth and the exact location. The location is shown rounded to about 100 m. The receipt also shows your crew's name, website and page, and what Sapu Earth paid. A mission is public in the same way once we publish or fund it. It is also in the list of missions at sapu.earth/missions, and once it is cleaned it stays there with its receipt, also after we stop working together. Once we approve your crew's logo, it shows next to your crew's name on sapu.earth. If you add the link to your post with a cleanup, its receipt can link to it, so people can comment there, unless we link our own post about the cleanup instead. Visitors can thank your crew with one tap under each receipt. The number of thanks shows on the receipt, on your crew's page and in the list of crews. Nobody signs in to do that, and we keep nothing about who tapped, so the counts cannot show who thanked. Your crew is also in the list of crews at sapu.earth/crews from the day we start working together, with its name, logo and country. Its name there links to your crew's public page on sapu.earth, which also shows your crew's website. Once your crew has a receipt or a mission on sapu.earth, the list also shows the totals of its receipts (cleanups, kilograms, sacks and what Sapu Earth paid), its newest receipt and its open and funded missions. It leaves the list when we stop working together.",
      pv_promo_h: "Marketing:",
      pv_promo: "we also use your photos and videos, edited or as they are, to promote Sapu Earth, for example in posts, videos and ads on social media and other websites, and in print. We may name your crew and the place with them. Social networks also process what we post there, under their own rules.",
      pv_private_h: "What stays private:",
      pv_private: "your message to Sapu Earth, the exact location, and everything we have not approved or published. Only the Sapu Earth team sees them.",
      pv_phone_h: "On your phone:",
      pv_phone: "photos and your crew's logo are saved again as JPEG on your phone. This removes the camera data, including the location, before they are sent. The page also tries to remove the location and the phone brand and model from MP4 and MOV videos. WebM videos are sent as they are. Until you send, what you typed and picked stays on this phone, so nothing is lost if the page reloads. After a successful send it is deleted from the phone. The phone also remembers your language and whether you saved this link.",
      pv_why_h: "Why:",
      pv_why: "to check your cleanups and missions, to decide what we fund, to pay your crew, to show your work on sapu.earth so anyone can see where the money goes, and to promote Sapu Earth. Legal basis: our agreement to fund your crew's cleanups (GDPR Art. 6(1)(b)), the consent of everyone shown in the photos and videos (GDPR Art. 6(1)(a)), and our legitimate interest in public receipts and in making Sapu Earth known (GDPR Art. 6(1)(f)). Without the photos and the numbers we cannot fund or show a cleanup.",
      pv_where_h: "Where:",
      pv_where: "on Cloudflare servers (database and file storage), which may be outside the EU. Cloudflare stores them for us as our processor. It is certified under the EU-US Data Privacy Framework and uses the EU standard contractual clauses for other countries. This page loads all its files, fonts included, from sapu.earth.",
      pv_long_h: "How long:",
      pv_long: "photos and videos you upload but never send are deleted after 48 hours. Approved cleanups stay on sapu.earth as public receipts, also after we stop working together. If we don't approve a cleanup, or take it off the site later, we delete its photos and videos. A mission nobody funds is removed after 28 days waiting for us, or after 28 days on sapu.earth. When a mission is removed for any reason, for example because you withdraw it, its photos and video, your message and its exact location are deleted. 90 days after we decide on a cleanup, or after a mission is done, we delete your message to Sapu Earth and round the exact location to about 100 m. Your crew's logo is deleted when we do not use it, when it waits 90 days without our check, when a newer one replaces it, and when we stop working together. The link to your post is deleted when we take it off the receipt, with its cleanup when we do not approve it or take it off the site, and when we stop working together. The thanks stay with their receipt, but we may take off the thanks of a day that looks inflated. We keep the rest, such as places, dates and numbers, as our record for as long as Sapu Earth runs.",
      pv_rights_h: "Your rights:",
      pv_rights: "ask to see, correct or delete your details, withdraw a consent, or object to how we use them, by emailing",
      pv_people: "Anyone shown in a photo or video can ask us the same way to take it down. We then stop using it and remove it where we can.",
      pv_complain: "You can also complain to the Austrian data protection authority",
    },
    id: {
      title: "HALAMAN KRU KAMU",
      title_mission: "AJUKAN MISI",
      title_cleanup_m: "LAPORAN MISI #{no}", title_plain: "AKSI BERSIH TANPA MISI",
      back: "HALAMAN KRU", to_home: "KEMBALI KE HALAMAN KRU",
      checking: "Sedang mengecek link kamu…",
      uploading_as: "Kru:",
      bad_link: "Link unggah ini sudah tidak berlaku. Kirim email ke hello@sapu.earth, atau balas pesan WhatsApp atau email kami, nanti kami kirim link baru.",
      no_link: "Halaman ini butuh link unggah khusus untuk kamu: buka dari pesan WhatsApp atau email kami. Link-nya hilang? Kirim email ke hello@sapu.earth, nanti kami kirim link baru. Kru baru? Daftar di sapu.earth/apply",
      offline_link: "Tidak bisa terhubung ke sapu.earth. Cek koneksi internet kamu, lalu muat ulang halaman ini.",
      save_h: "SIMPAN LINK INI",
      save_body: "Halaman ini adalah kunci pribadi kamu ke Sapu Earth. Simpan sekarang supaya kamu bisa membukanya lagi kapan saja. Jangan dibagikan di tempat umum: siapa pun yang punya link ini bisa mengajukan misi dan mengirim laporan atas nama kamu.",
      tip_ios: "Di iPhone: ketuk ⋯ (atau tombol Bagikan), lalu Bagikan, lalu Tambah ke Layar Utama. Kalau tidak kelihatan, gulir ke bawah.",
      tip_android: "Di Chrome: ketuk menu (titik tiga ⋮), lalu Instal dan buat pintasan, lalu Buat pintasan, lalu Tambahkan. Di Chrome versi lama, pilih Tambahkan ke Layar Utama. Kalau pakai browser lain, simpan halaman ini sebagai bookmark.",
      tip_samsung: "Di Samsung Browser atau Samsung Internet: ketuk menu (⋮ atau ≡) di pojok kanan bawah, lalu Tambahkan halaman ke, lalu Layar depan.",
      tip_home: "Kamu membuka halaman ini dari layar utama, jadi link-nya sudah tersimpan di sana.",
      tip_other: "Simpan halaman ini sebagai bookmark.",
      save_share: "KIRIM KE DIRI SENDIRI", save_copy: "SALIN LINK", save_done: "OKE, SUDAH DISIMPAN",
      save_again: "Cara menyimpan link ini",
      mode_cleanup: "LAPOR AKSI BERSIH",
      mode_mission: "AJUKAN MISI", mode_mission_sub: "Ada tempat kotor yang ingin kalian bersihkan. Minta Sapu Earth mendanainya.",
      intro_h: "LANGKAH PERTAMA: AJUKAN MISI",
      intro_body: "Cari tempat kotor di dekat kamu, ambil fotonya, lalu ajukan di sini sebagai misi dengan harga kamu. Sapu Earth akan mengeceknya dan memberi tahu kamu apakah misinya didanai. Hanya misi yang didanai yang dibayar.",
      intro_1: "Ajukan misi", intro_2: "Tunggu sampai didanai", intro_3: "Bersihkan, lalu kirim laporannya",
      m_limit_home: "Kamu sudah punya 5 misi yang sedang menunggu Sapu Earth, ada di sapu.earth, atau sudah didanai. Kamu bisa mengajukan misi baru setelah kami menyetujui laporan untuk salah satu misi yang didanai, atau setelah kamu membatalkan misi yang belum didanai.",
      plain_btn: "LAPOR AKSI BERSIH TANPA MISI",
      plain_sub: "Hanya misi yang didanai yang dibayar. Pakai ini untuk aksi bersih yang bukan salah satu misi kamu.",
      past_h: "MISI SEBELUMNYA", past_removed: "Tidak didanai atau ditutup ({n})",
      page_h: "HALAMAN PUBLIK KAMU",
      crews_listed: "Kru kamu juga ada di daftar semua kru di sapu.earth.", crews_open: "LIHAT SEMUA KRU",
      logo_h: "LOGO KRU KAMU", logo_add: "+ TAMBAH LOGO", logo_change: "GANTI LOGO", logo_pick: "Logo kru kamu",
      logo_none: "Tambahkan logo kru kamu. Setelah disetujui Sapu Earth, logonya tampil di samping nama kru kamu di sapu.earth.",
      logo_rules: "Logo kru kamu sendiri, atau foto logo dari dekat di spanduk atau kaos kru kamu, sampai logonya memenuhi foto. Bukan foto orang, tanpa nomor HP, nomor rekening, atau kode QR, dan bukan logo organisasi lain.",
      logo_preparing: "Menyiapkan logo kamu…",
      logo_sending: "Mengirim logo kamu…",
      logo_review: "Menunggu dicek Sapu Earth, biasanya dalam beberapa hari. Setelah kami setujui, logo kamu tampil di sapu.earth.",
      logo_review_live: "Logo baru kamu sedang menunggu dicek Sapu Earth. Selama belum kami cek, sapu.earth tetap menampilkan logo kamu yang sekarang.",
      logo_live: "Logo kamu tampil di samping nama kru kamu di sapu.earth.",
      logo_declined: "Sapu Earth tidak bisa memakai logo yang kamu kirim. Tekan + TAMBAH LOGO untuk mengirim logo lain.",
      logo_declined_live: "Sapu Earth tidak bisa memakai logo baru kamu, jadi sapu.earth tetap menampilkan logo ini.",
      e_logo_read: "Gambar ini tidak bisa dibuka di HP ini. Pilih logo kamu dalam format JPG atau PNG.",
      e_logo_small: "Gambar ini terlalu kecil untuk logo. Pilih gambar yang lebih besar.",
      e_logo_send: "Logo kamu belum terkirim. Cek koneksi internet, lalu coba lagi.",
      e_logo_limit: "Hari ini kamu sudah mengirim banyak logo. Coba lagi besok, ya.",
      e_logo_refused: "Gambar ini tidak diterima. Coba pilih gambar lain.",
      card_ready: "SIAP DIBERSIHKAN", card_today: "HARI INI",
      card_day: "Hari aksi bersih: {day}", card_planned: "Tanggal rencana: {day}",
      card_day_past: "Tanggal rencananya ({day}) sudah lewat. Kalau jadwalnya berubah dan kamu belum memberi tahu kami, balas pesan kami dengan tanggal barunya.",
      card_send: "LAPOR AKSI BERSIH #{no}", card_continue: "LANJUTKAN LAPORAN #{no}",
      card_progress: "Belum terkirim. Foto sebelum: {b}. Foto sesudah: {a}. Tersimpan di HP ini.",
      draft_photos: "Foto sebelum: {b}. Foto sesudah: {a}.",
      st_review_body: "Kami sedang mengecek misi ini dan akan memberi tahu kamu apakah misinya didanai. Jangan mulai sebelum misinya didanai: hanya misi yang didanai yang dibayar.",
      st_open_body: "Bagikan supaya lebih banyak orang melihatnya. Jangan mulai sebelum misinya didanai.",
      st_sent_body: "Kami cek laporan kamu, biasanya dalam beberapa hari. Setelah kami setujui, laporannya tampil di sapu.earth dan kami kirim sisa uangnya.",
      st_sent_body_all: "Kami cek laporan kamu, biasanya dalam beberapa hari. Setelah kami setujui, laporannya tampil di sapu.earth dan kami kirim uangnya.",
      share_m: "Bagikan misi #{no}", withdraw_m: "Batalkan misi #{no}",
      draft_c_h: "LAPORAN BELUM TERKIRIM", draft_m_h: "MISI BELUM TERKIRIM",
      draft_body: "Yang sudah kamu isi dan pilih tersimpan di HP ini.",
      draft_gone: "Misi #{no} sudah tidak bisa menerima laporan, jadi laporan yang sudah kamu mulai berubah menjadi laporan tanpa misi. Cek nama tempat, negara, dan jumlah kru.",
      draft_go: "LANJUTKAN", draft_del: "HAPUS",
      draft_del_q: "Hapus yang belum terkirim ini? Foto, video, dan isiannya akan dihapus dari HP ini.",
      switch_q: "Kamu sudah mulai mengisi laporan untuk misi #{from} di HP ini dan belum mengirimnya. Mulai laporan untuk misi #{to}? Yang sudah kamu tambahkan untuk misi #{from} akan dihapus dari HP ini.",
      switch_plain_q: "Kamu sudah mulai mengisi laporan untuk misi #{from} di HP ini dan belum mengirimnya. Mulai laporan tanpa misi? Yang sudah kamu tambahkan untuk misi #{from} akan dihapus dari HP ini.",
      move_q: "Kamu sudah mulai mengisi laporan tanpa misi di HP ini. Pakai yang sudah kamu tambahkan itu untuk laporan misi #{to}?",
      mission_pick: "Aksi bersih ini untuk misi yang mana?", no_mission: "Tanpa misi",
      sum_kicker: "MISI", sum_planned: "rencana {day}", sum_change: "UBAH",
      guard_q: "Apakah ini laporan untuk misi #{no} ({place})?", guard_yes: "YA, UNTUK #{no}",
      paper_hint: "Tulis #{no} besar-besar di kertas, lalu pegang kertas itu di salah satu foto sebelum dibersihkan. Kami memerlukannya untuk menyetujui laporan kamu.",
      paper_hint_spots: "Tulis #{no} besar-besar di kertas, lalu pegang kertas itu di salah satu foto sebelum dibersihkan di setiap titik. Kami memerlukannya untuk menyetujui laporan kamu.",
      before_hint_spots: "Misi ini punya {n} titik. Di setiap titik, ambil 1 sampai 4 foto sebelum mulai, dari tempat yang memperlihatkan seluruh titik itu.",
      after_hint_spots: "Di setiap titik, 1 sampai 4 foto di akhir, dari tempat dan sudut yang sama seperti foto sebelum dibersihkan di titik itu.",
      spot_field: "Titik {n}: {place}", spot_day: "Tanggal di titik {n}: {place}",
      spot_before_aria: "Foto sebelum dibersihkan di titik {n}", spot_after_aria: "Foto sesudah dibersihkan di titik {n}",
      sum_planned_spots: "{n} titik, rencana {from} sampai {to}", sum_planned_spots_1: "{n} titik, rencana {day}",
      card_spot: "Titik {n}: {place} ({day})",
      before_h: "SEBELUM DIBERSIHKAN", before_hint: "1 sampai 4 foto sebelum mulai, dari tempat yang memperlihatkan seluruh lokasinya.",
      after_h: "SESUDAH DIBERSIHKAN", after_hint: "1 sampai 4 foto di akhir, dari tempat dan sudut yang sama seperti foto sebelum dibersihkan.",
      before: "Foto sebelum dibersihkan", after: "Foto sesudah dibersihkan",
      add_photos: "+ Tambah foto", add_video: "+ Tambah video",
      video_before: "Video sebelum dibersihkan (tidak wajib)",
      video_after: "Video sesudah dibersihkan (tidak wajib)",
      videos_hint: "Satu video sebelum dan satu sesudah dibersihkan. Klip vertikal pendek 15 sampai 30 detik paling bagus dan lebih cepat terkirim. Batasnya 90 detik dan 95 MB per video.",
      date: "Tanggal aksi bersih", place: "Nama tempat", place_ph: "Muara sungai Canggu",
      location: "Lokasi", use_location: "Pakai lokasi saya sekarang", locating: "Sedang mencari lokasi kamu…",
      geo_hint: "Tekan tombol ini hanya kalau kamu sedang berada di lokasi aksi bersih.",
      geo_hint_m: "Tekan tombol ini hanya saat kamu berada di lokasi aksi bersih. Kalau tidak ditekan, laporan ini memakai lokasi misi #{no} (kalau ada).",
      geo_fail: "Lokasi tidak bisa didapat. Tidak apa-apa, kamu tetap bisa mengirim tanpa lokasi.",
      geo_ok: "Lokasi tersimpan", geo_clear: "Hapus",
      country: "Negara",
      result_h: "HASIL",
      result_hint: "Isi jumlah karung, kg, atau keduanya. Perkiraan boleh, yang penting jujur.",
      kg: "Berat sampah (kg)", sacks: "Jumlah karung penuh", crew: "Jumlah kru", hours: "Lama kegiatan (jam)",
      plan_day_btn: "Sesuai rencana: {day}",
      crew_src: "Dari misi #{no}. Ubah kalau jumlah orang yang bekerja berbeda.",
      crew_src_last: "Sama seperti misi #{no}. Ubah kalau kali ini berbeda.",
      disposal: "Sampahnya dibawa ke mana?", disposal_ph: "Bank sampah, pengepul, TPA",
      chips_place: "Tempat yang pernah kamu pakai:", chips_disposal: "Ketuk untuk mengisi:",
      disp_bank: "Bank sampah", disp_collector: "Pengepul", disp_official: "TPS/TPA resmi",
      chip_task: "Pakai rencana misi #{no}: {task}",
      chip_price: "Sama seperti misi #{no}: upah {each} per orang, biaya lain {other}",
      chip_price_0: "Sama seperti misi #{no}: upah {each} per orang, tanpa biaya lain",
      money_h: "BIAYA",
      cost_paid: "Sapu Earth membayar EUR {eur} untuk misi #{no}.",
      cost_receipt_plan: "Laporan publiknya menampilkan harga kamu: {line}. Isi biayanya hanya kalau biaya sebenarnya berbeda.",
      cost_receipt: "Laporan publiknya menampilkan harga yang kamu minta, beserta upah kru. Isi biayanya hanya kalau biaya sebenarnya berbeda.",
      cost_crew: "Misi ini direncanakan dengan {plan} orang kru, dan yang bekerja {now} orang. Kalau upahnya berubah, isi biayanya.",
      cost_toggle: "BIAYANYA BERBEDA",
      money_hint: "Tulis dalam mata uang lokal. Angka ini yang membuat laporan kita transparan.",
      currency: "Mata uang", currency_code: "Kode mata uang", other: "Lainnya", choose: "Pilih…",
      got_each: "Upah per orang", c_sum_h: "TOTAL BIAYA",
      sum_people_c: "Isi dulu jumlah kru di bagian HASIL.",
      e_each_c: "Tulis upah per orang, atau 0 kalau tidak ada yang dibayar.",
      notes: "Catatan (tampil di halaman publik)", notes_ph: "Cerita singkat tentang hari ini",
      post: "Link postingan kamu tentang aksi bersih ini (tidak wajib)",
      post_hint: "Sudah posting aksi bersih ini di Instagram atau TikTok? Tempel link-nya di sini, supaya laporannya bisa menampilkan link ke postingan kamu dan orang bisa berkomentar di sana. Instagram: tekan Bagikan, lalu Salin tautan. TikTok: aplikasinya menyalin link pendek yang tidak bisa kami cek, jadi tempel dulu link itu di kolom alamat browser, lalu salin alamat lengkapnya dari sana.",
      post_rules: "Hanya postingan kamu sendiri tentang aksi bersih ini: tanpa permintaan uang atau nomor rekening, dan hanya orang yang setuju ditampilkan. Kalau tidak, link-nya kami hapus dan kami beri tahu alasannya.",
      post_ok: "Link ke postingan {site} kamu: {link}",
      e_post_link: "Ini bukan link ke satu postingan di Instagram atau TikTok. Salin link postingannya sendiri (Instagram: Bagikan, lalu Salin tautan), atau kosongkan saja.",
      e_post_short: "Link pendek (seperti vt.tiktok.com atau instagram.com/share/) tidak bisa kami cek. Tempel link-nya di kolom alamat browser, tunggu sampai postingannya muncul, lalu salin alamat lengkapnya dari sana (tiktok.com/@... atau instagram.com/...). Atau kosongkan saja.",
      private_note: "Pesan untuk tim Sapu Earth (tidak ditampilkan)", private_note_ph: "Hanya tim Sapu Earth yang membaca ini.",
      consent: "Semua orang yang terlihat di foto dan video ini sudah setuju untuk ditampilkan di sapu.earth, di media sosial, dan di promosi Sapu Earth, dan tidak ada anak-anak di dalamnya. Sapu Earth boleh memakai, mengedit, dan membagikan foto dan video ini untuk menampilkan dan mempromosikan kegiatannya.",
      send: "KIRIM LAPORAN", try_again: "COBA LAGI",
      keep_open: "Jangan tutup halaman ini dan biarkan layar tetap menyala sampai muncul TERIMA KASIH.",
      thanks: "TERIMA KASIH!",
      thanks_body: "Laporan aksi bersih kamu sudah terkirim. Kami cek dulu setiap unggahan, lalu menampilkannya di sapu.earth, biasanya dalam beberapa hari.",
      ref: "Nomor referensi",
      page_note: "Setelah disetujui, aksi bersih kamu akan tampil di halaman ini:",
      share_page: "BAGIKAN HALAMANMU", share: "BAGIKAN", copied: "TERSALIN",
      mine_h: "AKSI BERSIH KAMU",
      st_pending: "Sedang dicek", st_approved: "Sudah tayang", st_rejected: "Tidak disetujui",
      mine_thanked: "{n} ucapan terima kasih",
      mine_thanked_1: "1 ucapan terima kasih",
      ty_total: "Pengunjung sapu.earth sudah {n} kali berterima kasih atas aksi bersih kru kamu.",
      ty_total_1: "Pengunjung sapu.earth sudah 1 kali berterima kasih atas aksi bersih kru kamu.",
      ty_note: "Siapa pun bisa menekan {btn} di laporan aksi bersih kamu di sapu.earth. Ini bukan uang, hanya tanda bahwa orang menghargai kerja kru kamu, dan yang dihitung adalah jumlah ketukan, bukan jumlah orang. Bagikan laporannya supaya lebih banyak orang melihatnya.",
      m_photos_h: "KONDISI SEKARANG",
      m_photos_hint: "1 sampai 4 foto tempat kotor itu seperti hari ini. Foto ini ditampilkan di sapu.earth bersama misi kamu.",
      now: "Foto tempatnya sekarang",
      now_video: "Video tempatnya sekarang (tidak wajib)",
      now_video_hint: "Satu klip vertikal pendek. Klip 15 sampai 30 detik paling bagus dan lebih cepat terkirim. Batasnya 90 detik dan 95 MB. Video ini ditampilkan di sapu.earth bersama misi kamu.",
      m_where_h: "DI MANA",
      m_geo_hint: "Tekan tombol ini hanya kalau kamu sedang berada di tempat itu. Tanpa lokasi, misi tidak muncul di peta.",
      m_plan_h: "RENCANANYA",
      m_plan_hint: "Yang kamu tulis di sini ditampilkan di sapu.earth bersama misi kamu. Satu atau dua kalimat cukup.",
      task: "Apa yang akan kalian lakukan?",
      task_ph: "Memungut sampah plastik di muara sungai dan pantai di sebelahnya, memilahnya, lalu membawanya ke bank sampah.",
      plan_date: "Tanggal rencana",
      plan_date_hint: "Pilih tanggal paling cepat seminggu dari sekarang, supaya Sapu Earth sempat memeriksa misinya sebelum hari itu.",
      safety_h: "UTAMAKAN KESELAMATAN",
      safety_1: "Semua orang pakai sarung tangan dan sepatu tertutup. Bawa air minum dan istirahat di tempat teduh.",
      safety_2: "Jangan masuk ke air yang lebih dalam dari lutut atau yang berarus deras. Perhatikan pasang surut dan ombak. Jangan bekerja saat hujan lebat atau ada petir, atau tepat setelah hujan lebat.",
      safety_3: "Jangan sentuh jarum suntik, limbah medis, bahan kimia, atau baterai. Tulis lokasinya di pesan kamu untuk Sapu Earth.",
      safety_4: "Kru hanya orang dewasa (18 tahun ke atas). Anak-anak tidak boleh dekat air dan tidak boleh ada di foto atau video.",
      safety_5: "Tutup luka dengan plester, dan cuci tangan pakai sabun sebelum makan atau minum. Air sungai dan air banjir bisa membuat orang sakit.",
      safety_6: "Bawa sampahnya ke bank sampah, pengepul, atau TPS/TPA resmi. Jangan dibakar, dan jangan tinggalkan karung berisi sampah di pinggir air.",
      safety_7: "Kalau ada yang terasa tidak aman, berhenti.",
      safety_price: "Masukkan biaya sarung tangan, karung, air minum, kotak P3K kecil, dan transportasi ke BIAYA LAIN, di bagian HARGA.",
      m_money_h: "HARGA",
      m_money_hint: "Dalam mata uang lokal. Halaman ini menghitung harga kamu: jumlah orang × upah per orang, ditambah biaya lain. Harga kamu dan rinciannya ditampilkan bersama misi kamu. Sapu Earth yang memutuskan apakah misinya didanai dan berapa.",
      m_crew: "Berapa orang yang akan bekerja?", m_each: "Upah per orang",
      other_costs: "Biaya lain",
      other_hint: "Semua biaya selain upah: sarung tangan, karung, air minum, kotak P3K kecil, dan transportasi. Tulis satu jumlah untuk semuanya.",
      m_sum_h: "TOTAL HARGA MISI",
      sum_crew: "{n} orang × {each} = {crew} untuk upah kru", sum_crew_1: "1 orang × {each} = {crew} untuk upah kru",
      sum_people_m: "Isi dulu jumlah orang di atas.",
      sum_parts: "{crew} untuk upah kru + {other} biaya lain = {total}", sum_parts_0: "{crew} untuk upah kru, tanpa biaya lain",
      sum_wait: "Totalnya muncul di sini setelah jumlah orang dan upah per orang diisi.",
      e_money: "Tulis angkanya saja, misalnya 100000 atau 100.000, bukan 100rb.",
      e_each: "Tulis upah per orang. Tulis 0 kalau tidak ada yang dibayar.",
      e_sum_zero: "Harga kamu masih 0. Isi upah per orang atau biaya lain.",
      price_line: "total {total}, dengan upah kru {n} × {each} dan biaya lain {other}",
      price_line_0: "total {total}, semuanya untuk upah kru ({n} × {each})",
      price_line_old: "total {total}, termasuk {crew} untuk upah {n} orang kru",
      price_line_unpaid: "total {total}, semuanya biaya lain, tanpa upah kru",
      m_done_price: "Harga kamu: {line}. Kalau ini tidak benar, kabari kami sebelum misinya didanai.",
      card_price: "Harga yang kamu minta: {line}.",
      m_consent: "Semua orang yang terlihat di foto dan video ini sudah setuju untuk ditampilkan di sapu.earth, di media sosial, dan di promosi Sapu Earth, tidak ada anak-anak di dalamnya, dan semua orang yang kami bayar berusia 18 tahun ke atas. Sapu Earth boleh memakai, mengedit, dan membagikan foto dan video ini untuk menampilkan dan mempromosikan kegiatannya.",
      m_send: "KIRIM MISI",
      m_keep_open: "Jangan tutup halaman ini dan biarkan layar tetap menyala sampai nomor misi kamu muncul.",
      m_done_big: "MISI #{no}",
      m_done_body: "Misi #{no} sudah terkirim. Sapu Earth akan mengeceknya dan memberi tahu kamu apakah misinya didanai. Jangan mulai aksi bersih sebelum ada kabar dari kami, karena hanya misi yang didanai yang dibayar.",
      m_done_updated: "Misi #{no} sudah terkirim sebelumnya, dan sekarang sudah berisi perubahan kamu. Sapu Earth akan mengeceknya dan memberi tahu kamu apakah misinya didanai. Jangan mulai aksi bersih sebelum ada kabar dari kami, karena hanya misi yang didanai yang dibayar.",
      m_done_share: "Setelah ada di sapu.earth, kamu bisa membagikannya dari halaman kru kamu.",
      my_missions_h: "MISI KAMU",
      ms_review: "Menunggu Sapu Earth", ms_open: "Ada di sapu.earth, belum didanai", ms_done: "Selesai",
      ms_funded: "Didanai: EUR {eur}", ms_funded_plain: "Didanai", ms_advance: "Uang muka EUR {eur} sedang dikirim ke kamu",
      ms_cleanup_sent: "Laporan terkirim, sedang dicek",
      rm_declined: "Tidak didanai", rm_expired: "Tidak didanai, dihapus setelah 28 hari", rm_withdrawn: "Dibatalkan oleh kamu",
      rm_cancelled: "Dibatalkan oleh Sapu Earth", rm_unpublished: "Diturunkan dari situs", rm_deactivated: "Ditutup",
      funded_todo: "Pegang kertas bertuliskan #{no} di salah satu foto sebelum dibersihkan.",
      funded_todo_spots: "Pegang kertas bertuliskan #{no} di salah satu foto sebelum dibersihkan di setiap titik.",
      withdraw: "BATALKAN",
      withdraw_q: "Batalkan misi #{no}? Misi ini akan dihapus beserta fotonya, dan juga videonya kalau ada.",
      e_withdraw: "Misi gagal dibatalkan. Cek koneksi kamu, lalu coba lagi.",
      e_withdraw_late: "Misi #{no} sudah didanai atau sudah ditutup, jadi tidak bisa dibatalkan.",
      reload_note: "Isian kamu sudah dikembalikan, tapi foto dan video perlu ditambahkan lagi.",
      e_before: "Tambahkan minimal satu foto sebelum dibersihkan.", e_after: "Tambahkan minimal satu foto sesudah dibersihkan.",
      e_before_spot: "Tambahkan minimal satu foto sebelum dibersihkan di titik {n}.", e_after_spot: "Tambahkan minimal satu foto sesudah dibersihkan di titik {n}.",
      e_spot_day: "Tulis tanggal kalian membersihkan titik {n}. Tanggalnya tidak boleh di masa depan.",
      e_place: "Tulis nama tempatnya.", e_date: "Pilih tanggal aksi bersih. Tanggalnya tidak boleh di masa depan.",
      e_amount: "Isi jumlah karung atau berat sampah (kg).",
      e_crew: "Tulis berapa orang yang ikut bekerja.", e_consent: "Centang dulu kotak persetujuan, ya.",
      e_country: "Pilih negaranya.", e_currency: "Tulis kode mata uang 3 huruf, misalnya MYR.",
      e_currency_pick: "Pilih mata uangnya.",
      e_number: "Cek lagi angka ini. Tulis angkanya saja, misalnya 1500000 atau 12,5.",
      e_now: "Tambahkan 1 sampai 4 foto tempatnya seperti sekarang.",
      e_task: "Tulis apa yang akan kalian lakukan.",
      e_plan_date: "Pilih tanggal rencana, mulai hari ini sampai 4 bulan ke depan.",
      e_m_crew: "Tulis berapa orang yang akan ikut bekerja.",
      e_fix: "Masih ada isian yang perlu diperbaiki. Lihat kolom yang ditandai oranye.",
      e_decode: "Foto ini tidak bisa dibuka di HP ini. Pilih foto berformat JPG. Kalau kamera kamu menyimpan foto sebagai HEIF atau HEIC, matikan pengaturan itu di kamera, lalu foto ulang.",
      e_photo_big: "File foto ini terlalu besar. Coba pilih foto lain.",
      e_max_photos: "Maksimal 4 foto di sini.", e_max_videos: "Hanya bisa satu video di sini. Hapus dulu video yang sudah ada kalau mau memilih yang lain.",
      e_video_type: "Format video ini tidak didukung. Pakai MP4, MOV, atau WebM.",
      e_video_big: "Video ini lebih dari 95 MB. Potong jadi sekitar 30 detik, atau rekam ulang dengan resolusi 720p.",
      e_video_long: "Video ini terlalu panjang. Maksimal 90 detik.",
      e_video_check: "Data lokasi di video ini tidak bisa diperiksa, jadi video ini tidak ditambahkan. Muat ulang halaman lalu coba lagi, atau pilih video lain.",
      preparing: "Sedang menyiapkan foto…",
      preparing_files: "Sedang menyiapkan foto dan video…",
      up_file: "Mengunggah file {i} dari {n}…",
      up_file_mb: "Mengunggah file {i} dari {n}… {a} dari {b} MB",
      retrying: "Koneksi bermasalah. Mencoba lagi dalam {s} detik…",
      retrying_1: "Koneksi bermasalah. Mencoba lagi dalam 1 detik…",
      waiting_online: "Kamu sedang offline. Menunggu koneksi tersambung lagi…",
      sending: "Sedang mengirim data…",
      e_upload: "Ada file yang gagal terunggah. Isian kamu tetap tersimpan. Tekan COBA LAGI.",
      e_upload_video: "Videonya gagal terunggah. Isian kamu tetap tersimpan. Tekan COBA LAGI, atau hapus videonya supaya terkirim tanpa video. Video tidak wajib.",
      e_upload_fatal: "Ada satu file yang tidak bisa dikirim. Hapus file yang ditandai oranye, lalu tekan COBA LAGI.",
      e_limit: "Hari ini kamu sudah mengirim banyak file. Coba lagi besok, ya. Isian kamu tetap tersimpan.",
      e_media: "Beberapa file perlu dikirim ulang. Isian kamu tetap tersimpan. Tekan COBA LAGI.",
      e_rejected: "Ada isian yang tidak diterima. Cek lagi angka dan tanggalnya, lalu coba lagi.",
      e_submit: "Gagal mengirim. Isian kamu tetap tersimpan. Tekan COBA LAGI.",
      e_m_limit: "Kamu sudah punya 5 misi yang sedang menunggu Sapu Earth, ada di sapu.earth, atau sudah didanai. Kamu bisa mengajukan misi baru setelah kami menyetujui laporan untuk salah satu misi yang didanai, atau setelah kamu membatalkan misi yang belum didanai. Isian kamu tetap tersimpan.",
      e_m_unavailable: "Misi belum bisa diajukan sekarang. Isian kamu tetap tersimpan. Coba lagi nanti, ya.",
      e_mission_gone_alone: "Misi ini sudah tidak bisa menerima laporan. Cek nama tempat, negara, dan jumlah kru, lalu tekan COBA LAGI untuk mengirimnya tanpa misi.",
      e_mission_taken_alone: "Laporan untuk misi ini sudah pernah dikirim. Untuk tetap mengirim laporan ini, cek nama tempat, negara, dan jumlah kru, lalu tekan COBA LAGI. Laporan ini akan dikirim tanpa misi.",
      e_m_resend: "Misi ini sudah pernah dikirim dan tidak bisa diubah lagi dari sini. Lihat halaman kru kamu. Untuk mengajukannya sebagai misi baru, tekan COBA LAGI.",
      remove: "Hapus",
      pv_sum: "Cara kami mengelola foto, video, dan data kamu",
      pv_foot: "PRIVASI",
      pv_who_h: "Siapa:", pv_who: "Sapu Earth dijalankan oleh Marcus Pousette di Innsbruck, Austria. Kontak:",
      pv_what_h: "Yang kamu kirim:",
      pv_what: "foto dan video (bisa memperlihatkan orang), tanggal, tempat dan negara, titik lokasi yang persis kalau kamu menekan Pakai lokasi saya sekarang, angka-angkanya (kg, karung, jumlah kru, jam, biaya, dan upah), ke mana sampahnya dibawa, catatan kamu, link postingan kamu tentang aksi bersih itu di Instagram atau TikTok kalau kamu menambahkannya, dan pesan kamu untuk Sapu Earth. Untuk misi, juga rencana, tanggal, dan harganya. Juga logo kru kamu, kalau kamu menambahkannya.",
      pv_public_h: "Yang tampil untuk umum:",
      pv_public: "setelah kami setujui, aksi bersih kamu menjadi laporan publik di sapu.earth dengan semua yang kamu kirim, kecuali pesan kamu untuk Sapu Earth dan titik lokasi yang persis. Lokasinya ditampilkan dibulatkan sampai sekitar 100 m. Laporan itu juga menampilkan nama, situs web, dan halaman kru kamu, serta berapa yang dibayar Sapu Earth. Misi tampil untuk umum dengan cara yang sama setelah kami tayangkan atau danai. Misi itu juga ada di daftar misi di sapu.earth/missions, dan setelah dibersihkan tetap ada di sana bersama laporannya, juga setelah kerja sama kita berhenti. Setelah kami setujui, logo kru kamu tampil di samping nama kru kamu di sapu.earth. Kalau kamu menambahkan link postingan kamu saat mengirim aksi bersih, laporannya bisa menampilkan link ke postingan itu, supaya orang bisa berkomentar di sana, kecuali kami menampilkan link ke postingan kami sendiri tentang aksi bersih itu. Pengunjung bisa berterima kasih kepada kru kamu dengan satu ketukan di setiap laporan. Jumlah ucapan terima kasihnya tampil di laporan itu, di halaman kru kamu, dan di daftar kru. Untuk itu tidak perlu masuk dengan akun, dan kami tidak menyimpan apa pun tentang siapa yang menekan, jadi jumlahnya tidak bisa menunjukkan siapa yang berterima kasih. Kru kamu juga ada di daftar kru di sapu.earth/crews sejak kita mulai bekerja sama, dengan nama, logo, dan negaranya. Nama kru kamu di daftar itu bisa ditekan untuk membuka halaman publik kru kamu di sapu.earth, yang juga menampilkan situs web kru kamu. Setelah kru kamu punya laporan atau misi di sapu.earth, daftar itu juga menampilkan total dari semua laporannya (aksi bersih, kilogram, karung, dan berapa yang dibayar Sapu Earth), laporan terbarunya, serta misinya yang masih menunggu dana atau sudah didanai. Kru kamu keluar dari daftar itu saat kerja sama kita berhenti.",
      pv_promo_h: "Promosi:",
      pv_promo: "kami juga memakai foto dan video kamu, diedit atau apa adanya, untuk mempromosikan Sapu Earth, misalnya di postingan, video, dan iklan di media sosial dan situs lain, juga di media cetak. Kami bisa menyebut nama kru kamu dan tempatnya. Media sosial juga memproses apa yang kami posting di sana, dengan aturan mereka sendiri.",
      pv_private_h: "Yang tetap pribadi:",
      pv_private: "pesan kamu untuk Sapu Earth, titik lokasi yang persis, dan semua yang tidak kami setujui atau tayangkan. Hanya tim Sapu Earth yang melihatnya.",
      pv_phone_h: "Di HP kamu:",
      pv_phone: "foto dan logo kru kamu disimpan ulang sebagai JPEG di HP kamu. Ini menghapus data kamera, termasuk lokasinya, sebelum dikirim. Halaman ini juga berusaha menghapus lokasi serta merek dan tipe HP dari video MP4 dan MOV. Video WebM dikirim apa adanya. Sampai terkirim, isian dan file yang kamu pilih tetap tersimpan di HP ini, jadi tidak hilang kalau halamannya dimuat ulang. Setelah berhasil terkirim, semuanya dihapus dari HP. HP ini juga mengingat bahasa yang kamu pilih dan apakah link ini sudah kamu simpan.",
      pv_why_h: "Untuk apa:",
      pv_why: "untuk memeriksa aksi bersih dan misi kamu, memutuskan apa yang kami danai, membayar kru kamu, menampilkan hasil kerja kalian di sapu.earth supaya semua orang bisa melihat ke mana uangnya pergi, dan mempromosikan Sapu Earth. Dasar hukumnya: kesepakatan kita bahwa Sapu Earth mendanai aksi bersih kru kamu (GDPR Pasal 6(1)(b)), persetujuan semua orang yang terlihat di foto dan video (GDPR Pasal 6(1)(a)), dan kepentingan sah kami untuk menampilkan laporan publik dan memperkenalkan Sapu Earth (GDPR Pasal 6(1)(f)). Tanpa foto dan angka-angkanya, kami tidak bisa mendanai atau menampilkan aksi bersih.",
      pv_where_h: "Di mana:",
      pv_where: "di server Cloudflare (database dan penyimpanan file), yang bisa berada di luar Uni Eropa. Cloudflare menyimpannya untuk kami sebagai pemroses data kami. Cloudflare tersertifikasi di bawah EU-US Data Privacy Framework dan memakai klausul kontrak standar Uni Eropa untuk negara lain. Halaman ini memuat semua file, termasuk font, dari sapu.earth.",
      pv_long_h: "Berapa lama:",
      pv_long: "foto dan video yang kamu unggah tapi tidak pernah dikirim dihapus setelah 48 jam. Aksi bersih yang disetujui tetap tampil di sapu.earth sebagai laporan publik, juga setelah kerja sama kita berhenti. Kalau aksi bersih tidak kami setujui, atau nanti kami turunkan dari situs, foto dan videonya kami hapus. Misi yang tidak didanai dihapus setelah 28 hari menunggu kami, atau setelah 28 hari tampil di sapu.earth. Kalau misi dihapus karena alasan apa pun, misalnya karena kamu membatalkannya, foto dan videonya, pesan kamu, dan titik lokasinya yang persis ikut dihapus. 90 hari setelah kami memutuskan sebuah aksi bersih, atau setelah sebuah misi selesai, pesan kamu untuk Sapu Earth kami hapus dan titik lokasinya kami bulatkan sampai sekitar 100 m. Logo kru kamu dihapus kalau tidak kami pakai, kalau sudah 90 hari menunggu tanpa kami cek, kalau diganti dengan logo yang lebih baru, atau kalau kerja sama kita berhenti. Link postingan kamu dihapus kalau kami melepasnya dari laporan, bersama aksi bersihnya kalau tidak kami setujui atau kami turunkan dari situs, dan kalau kerja sama kita berhenti. Ucapan terima kasih tetap ada bersama laporannya, tapi kami bisa menghapus ucapan terima kasih dari satu hari yang jumlahnya tidak wajar. Sisanya, seperti tempat, tanggal, dan angka, kami simpan sebagai catatan kami selama Sapu Earth masih berjalan.",
      pv_rights_h: "Hak kamu:",
      pv_rights: "kamu bisa minta untuk melihat, memperbaiki, atau menghapus data kamu, menarik persetujuan, atau menolak cara kami memakainya, lewat email ke",
      pv_people: "Siapa pun yang terlihat di foto atau video bisa minta lewat cara yang sama agar foto atau video itu diturunkan. Kami lalu berhenti memakainya dan menghapusnya sebisa mungkin.",
      pv_complain: "Kamu juga bisa mengajukan pengaduan ke otoritas perlindungan data Austria",
    },
  };
  const storedLang = store.get("sapu-lang");
  let lang = storedLang || ((navigator.language || "").toLowerCase().startsWith("id") ? "id" : "en");
  const t = (k, vars) => {
    let s = (T[lang] && T[lang][k]) || T.en[k] || k;
    if (vars) for (const [a, b] of Object.entries(vars)) s = s.split("{" + a + "}").join(b);
    return s;
  };

  // ---------- reference data ----------
  const ISO = ("AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ " +
    "CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR " +
    "GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP " +
    "KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT " +
    "MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW " +
    "SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG " +
    "UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW").split(" ");
  // Always in the currency list, after the crew's own: the money of the countries we work in or look at next.
  const CURRENCIES = ["IDR", "PHP", "MYR", "THB", "VND", "INR", "LKR", "KES", "UGX", "TZS", "RWF", "NGN", "GHS", "XOF",
    "ZAR", "BRL", "USD", "EUR"];
  // The money of every country in ISO above (ISO 4217), so a crew starts on its own and a price is never read in
  // another currency. Two codes: both are in daily use there (prices are often in US dollars), so the crew must
  // choose one, like a crew whose country is not listed (the uninhabited ones). Nothing ever falls back to USD.
  const COUNTRY_CURRENCY = {
    AD: "EUR", AE: "AED", AF: "AFN", AG: "XCD", AI: "XCD", AL: "ALL", AM: "AMD", AO: "AOA", AR: "ARS", AS: "USD",
    AT: "EUR", AU: "AUD", AW: "AWG", AX: "EUR", AZ: "AZN", BA: "BAM", BB: "BBD", BD: "BDT", BE: "EUR", BF: "XOF",
    BG: "EUR", BH: "BHD", BI: "BIF", BJ: "XOF", BL: "EUR", BM: "BMD", BN: "BND", BO: "BOB", BQ: "USD", BR: "BRL",
    BS: "BSD", BT: "BTN", BW: "BWP", BY: "BYN", BZ: "BZD", CA: "CAD", CC: "AUD", CD: "CDF USD", CF: "XAF", CG: "XAF",
    CH: "CHF", CI: "XOF", CK: "NZD", CL: "CLP", CM: "XAF", CN: "CNY", CO: "COP", CR: "CRC", CU: "CUP", CV: "CVE",
    CW: "XCG", CX: "AUD", CY: "EUR", CZ: "CZK", DE: "EUR", DJ: "DJF", DK: "DKK", DM: "XCD", DO: "DOP", DZ: "DZD",
    EC: "USD", EE: "EUR", EG: "EGP", EH: "MAD", ER: "ERN", ES: "EUR", ET: "ETB", FI: "EUR", FJ: "FJD", FK: "FKP",
    FM: "USD", FO: "DKK", FR: "EUR", GA: "XAF", GB: "GBP", GD: "XCD", GE: "GEL", GF: "EUR", GG: "GBP", GH: "GHS",
    GI: "GIP", GL: "DKK", GM: "GMD", GN: "GNF", GP: "EUR", GQ: "XAF", GR: "EUR", GT: "GTQ", GU: "USD", GW: "XOF",
    GY: "GYD", HK: "HKD", HN: "HNL", HR: "EUR", HT: "HTG", HU: "HUF", ID: "IDR", IE: "EUR", IL: "ILS", IM: "GBP",
    IN: "INR", IO: "USD", IQ: "IQD", IR: "IRR", IS: "ISK", IT: "EUR", JE: "GBP", JM: "JMD", JO: "JOD", JP: "JPY",
    KE: "KES", KG: "KGS", KH: "KHR USD", KI: "AUD", KM: "KMF", KN: "XCD", KP: "KPW", KR: "KRW", KW: "KWD", KY: "KYD",
    KZ: "KZT", LA: "LAK", LB: "LBP USD", LC: "XCD", LI: "CHF", LK: "LKR", LR: "LRD USD", LS: "LSL", LT: "EUR", LU: "EUR",
    LV: "EUR", LY: "LYD", MA: "MAD", MC: "EUR", MD: "MDL", ME: "EUR", MF: "EUR", MG: "MGA", MH: "USD", MK: "MKD",
    ML: "XOF", MM: "MMK", MN: "MNT", MO: "MOP", MP: "USD", MQ: "EUR", MR: "MRU", MS: "XCD", MT: "EUR", MU: "MUR",
    MV: "MVR", MW: "MWK", MX: "MXN", MY: "MYR", MZ: "MZN", NA: "NAD", NC: "XPF", NE: "XOF", NF: "AUD", NG: "NGN",
    NI: "NIO", NL: "EUR", NO: "NOK", NP: "NPR", NR: "AUD", NU: "NZD", NZ: "NZD", OM: "OMR", PA: "USD", PE: "PEN",
    PF: "XPF", PG: "PGK", PH: "PHP", PK: "PKR", PL: "PLN", PM: "EUR", PN: "NZD", PR: "USD", PS: "ILS", PT: "EUR",
    PW: "USD", PY: "PYG", QA: "QAR", RE: "EUR", RO: "RON", RS: "RSD", RU: "RUB", RW: "RWF", SA: "SAR", SB: "SBD",
    SC: "SCR", SD: "SDG", SE: "SEK", SG: "SGD", SH: "SHP", SI: "EUR", SJ: "NOK", SK: "EUR", SL: "SLE", SM: "EUR",
    SN: "XOF", SO: "SOS USD", SR: "SRD", SS: "SSP USD", ST: "STN", SV: "USD", SX: "XCG", SY: "SYP", SZ: "SZL", TC: "USD",
    TD: "XAF", TG: "XOF", TH: "THB", TJ: "TJS", TK: "NZD", TL: "USD", TM: "TMT", TN: "TND", TO: "TOP", TR: "TRY",
    TT: "TTD", TV: "AUD", TW: "TWD", TZ: "TZS", UA: "UAH", UG: "UGX", US: "USD", UY: "UYU", UZ: "UZS", VA: "EUR",
    VC: "XCD", VE: "VES USD", VG: "USD", VI: "USD", VN: "VND", VU: "VUV", WF: "XPF", WS: "WST", YE: "YER", YT: "EUR",
    ZA: "ZAR", ZM: "ZMW", ZW: "ZWG USD",
  };
  const ownCurrencies = (country) => (COUNTRY_CURRENCY[country] || "").split(" ").filter(Boolean);
  // The currency a form starts on: the crew's own, or "" (Choose…) when it has to pick one.
  function startCurrency() {
    const own = ownCurrencies((partner && partner.country) || "");
    return own.length === 1 ? own[0] : "";
  }
  const VIDEO_EXT = { mp4: "video/mp4", m4v: "video/mp4", mov: "video/quicktime", qt: "video/quicktime", webm: "video/webm" };
  // photos and videos: per field. A cleanup takes at most 2 videos, one in each of its two video fields.
  const LIMIT = { photos: 4, videos: 1, videoBytes: 95 * 1024 * 1024, videoSecs: 95, photoInputBytes: 60 * 1024 * 1024 };
  // The video fields: before and after the cleanup, and the mission's video of the spot now.
  const VIDEO_KINDS = ["video_before", "video_after", "now_video"];
  const STALL_MS = 60000; // abort and retry an upload when no progress arrives for this long
  // The server takes a planned day up to 120 days after its own (UTC) date. One day less is safe in every time zone.
  const MISSION_AHEAD_DAYS = 119;
  // A week out by default, so the team has time to see, check and fund the mission before the day.
  const MISSION_DEFAULT_DAYS = 7;
  // How the server says why a mission was removed (functions/_lib/missions.js REMOVED_WHY).
  const REMOVED = ["declined", "cancelled", "expired", "withdrawn", "unpublished", "deactivated"];
  // The value of "No mission" in the cleanup form's mission select (under CHANGE). An empty value means not chosen
  // yet: the cleanup opened from the crew page sets it.
  const NO_MISSION = "none";
  // Typed numbers that get a "= 1,500 kg" echo under them. The money fields of PRICE and COSTS show the sum instead
  // (renderSum): the line under the pay for each person and the box with the total say how each amount was read.
  const ECHO = ["kg"];

  // ---------- crew page model (pure; tests/e2e.sh runs this block in node) ----------
  // What the crew page shows and which screen a history entry may open, from the missions of GET /api/partner
  // and what waits on this phone. Nothing here reads the page or anything outside this block.
  const ACTIVE_STATES = ["review", "open", "funded"];
  const ACTIVE_MAX = 5; // the server's MISSION_LIMITS.active
  const SPOT_MAX = 4;   // the server's SPOTS.max: a mission's spots, its own first (docs/missions.md, Spots)
  const isDay = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
  // A mission's spots as GET /api/partner sends them for a mission with several (docs/missions.md, Spots): spot 1 first,
  // [{ no, place_name, date }], 2 to SPOT_MAX of them, numbered 1, 2, ... in that order. [] for a mission with one spot,
  // and for anything else: the cleanup form then asks the photos of one spot, as for every mission before.
  function spotsOf(m) {
    const s = m && Array.isArray(m.spots) ? m.spots : [];
    const ok = s.length >= 2 && s.length <= SPOT_MAX && s.every((x, i) => !!x && x.no === i + 1
      && typeof x.place_name === "string" && x.place_name.trim() !== "" && isDay(x.date));
    return ok ? s : [];
  }
  // The newest mission with a crew size, any status: POST A MISSION starts on its crew size.
  function lastCrewMission(missions) {
    return (missions || []).find((m) => !!m && Number.isInteger(m.crew_size) && m.crew_size >= 1 && m.crew_size <= 1000) || null;
  }
  // A mission's own task and price (plan in GET /api/partner) when it is whole, else null.
  function planOf(m) {
    const p = m && m.plan;
    if (!p || typeof p !== "object") return null;
    const ok = typeof p.task === "string" && p.task.trim() !== "" && typeof p.currency === "string" && /^[A-Z]{3}$/.test(p.currency)
      && Number.isFinite(p.price_local) && p.price_local > 0 && Number.isFinite(p.crew_local) && p.crew_local >= 0 && p.crew_local <= p.price_local;
    return ok ? p : null;
  }
  // The mission whose task and price POST A MISSION offers as one-tap chips: the newest funded or done one at the place
  // the crew wrote (a spot cleaned before, dirty again), else the newest funded or done one. Never one Sapu Earth did
  // not fund (in review, open, removed): a declined price must not come back.
  function lastPlanMission(missions, place) {
    const funded = (missions || []).filter((m) => !!m && (m.status === "funded" || m.status === "done") && !!planOf(m));
    const at = String(place || "").trim().toLowerCase();
    return (at && funded.find((m) => typeof m.place_name === "string" && m.place_name.trim().toLowerCase() === at)) || funded[0] || null;
  }
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
  // The price as PRICE and COSTS add it up: the pay for each person (to the cent) times the people, plus the other costs
  // (none when empty), { people, each, crew, other, total }. null while the people or the pay are missing. SEND sends
  // total and crew as price_local and crew_local (a cleanup: total_cost_local and crew_pay_local).
  function moneySum(people, each, other) {
    if (!Number.isInteger(people) || people < 1 || people > 1000 || !Number.isFinite(each) || each < 0) return null;
    const c = (v) => Math.round(v * 100) / 100;
    const e = c(each), o = Number.isFinite(other) && other > 0 ? c(other) : 0, crew = c(e * people);
    return { people, each: e, crew, other: o, total: c(crew + o) };
  }
  // What the price chip offers from a mission (lastPlanMission): its currency, pay for each person and other costs, only
  // while its crew's pay splits evenly, so a price typed as one total is never offered as a pay for each person.
  function payOf(m) {
    const p = planOf(m), s = p && splitOf(p.price_local, p.crew_local, m.crew_size);
    return s && s.exact ? { m, currency: p.currency, each: s.each, other: s.other } : null;
  }
  // What PRICE and COSTS show (renderSum draws it, SEND sends its sum). people: numVal of the crew size; each, other:
  // readMoney ({ raw, v, bad, typing }). strict: at SEND an amount still being typed cannot be read either. line: under
  // the pay, { key, cls } (cls "warn": cannot be read, "wait": no crew size yet, "": with crew, the crew's pay); oline:
  // under the other costs, only why it cannot be read; sum: moneySum of all three or null; parts: the key under the total.
  function sumView(people, each, other, strict) {
    const why = (x) => (x.typing && !strict ? null : x.bad);
    const ew = why(each), ow = why(other), n = people.ok && people.v !== null ? people.v : null;
    const sum = n !== null && !each.bad && !other.bad ? moneySum(n, each.v, other.v) : null;
    const line = ew ? { key: ew, cls: "warn" } : each.v === null ? null : n === null ? { key: "people", cls: "wait" }
      : { key: n === 1 ? "sum_crew_1" : "sum_crew", cls: "", crew: moneySum(n, each.v, 0) };
    return { line, oline: ow ? { key: ow, cls: "warn" } : null, sum, parts: !sum ? "sum_wait" : sum.other > 0 ? "sum_parts" : "sum_parts_0" };
  }
  // The start of a text for a chip, cut at a word: "Pick up the plastic at the river mouth and…".
  function excerpt(text, max = 60) {
    const s = String(text || "").replace(/\s+/g, " ").trim();
    if (s.length <= max) return s;
    const cut = s.slice(0, max + 1), sp = cut.lastIndexOf(" ");
    return (sp >= max / 2 ? cut.slice(0, sp) : s.slice(0, max)).replace(/[\s.,;:!?]+$/, "") + "…";
  }
  // The funded mission whose planned day (YYYY-MM-DD) is nearest to today, before or after. On a tie the earlier day
  // wins: a cleanup is sent after the work is done. A mission without a day comes last.
  function nearestMission(list, today) {
    const day = (iso) => (isDay(iso) ? Date.parse(iso + "T00:00:00Z") / 86400000 : Infinity);
    const now = day(today);
    let best = null, bestGap = Infinity;
    for (const m of list || []) {
      const gap = Math.abs(day(m.plan_date) - now);
      if (best === null || gap < bestGap || (gap === bestGap && day(m.plan_date) < day(best.plan_date))) { best = m; bestGap = gap; }
    }
    return best;
  }
  // The mission the cleanup without a mission asks about ("Is this the cleanup for mission #12?"), from the funded ones
  // waiting for their cleanup (toClean). None while the form has a mission, and none once the cleanup lost its mission
  // (lost: that mission's number, else null): its before photos may show the lost mission's paper.
  function guardMission({ picked, lost, toClean, today }) {
    return picked || lost !== null ? null : nearestMission(toClean, today);
  }
  // What a tap that opens a cleanup (a card's button, the cleanup without a mission) asks first, from the unsent cleanup
  // on this phone. held: the mission it is for ("none" without one); lost: the number of the mission it lost, or null.
  // null: nothing to ask (no work, or that very cleanup). "move": work without a mission goes into the tapped mission.
  // "switch": work for a mission, or work that lost its mission, is removed once the crew says yes, so before photos
  // with one mission's paper never move to another mission by a tap.
  function openAsk({ work, held, lost, target }) {
    if (!work || target === held) return null;
    return held !== "none" || lost !== null ? "switch" : "move";
  }
  // Up to max place names the crew used before, missions first, each once (ignoring case), never the current one.
  function placeChips(missions, submissions, current, max = 3) {
    const seen = new Set([String(current || "").trim().toLowerCase()]);
    const out = [];
    for (const x of [...(missions || []), ...(submissions || [])]) {
      const name = x && typeof x.place_name === "string" ? x.place_name.trim() : "";
      if (!name || seen.has(name.toLowerCase())) continue;
      seen.add(name.toLowerCase());
      out.push(name);
      if (out.length >= max) break;
    }
    return out;
  }
  // Unsent work: extra (a file, a location, a draft that lost its files), a field of always that holds something,
  // or a field of unlessMarked that holds something other than what the page filled in (marks).
  function hasWork(values, marks, always, unlessMarked, extra) {
    if (extra) return true;
    const val = (f) => (values && values[f] != null ? String(values[f]).trim() : "");
    const mark = (f) => (marks && marks[f] != null ? String(marks[f]) : null);
    return always.some((f) => val(f) !== "") || unlessMarked.some((f) => val(f) !== "" && val(f) !== mark(f));
  }
  // Whole days from a to b (YYYY-MM-DD, UTC), or null when either is not a date.
  function daysBetween(a, b) {
    if (!isDay(a) || !isDay(b)) return null;
    const ta = Date.parse(a + "T00:00:00Z"), tb = Date.parse(b + "T00:00:00Z");
    return Number.isFinite(ta) && Number.isFinite(tb) ? Math.round((tb - ta) / 86400000) : null;
  }
  // The screen a history entry may show: no entry of ours, the crew page or a done screen (a reload of THANK YOU):
  // the crew page. POST A MISSION while missions are on. The cleanup without a mission ("none"). The cleanup of a
  // funded mission still waiting for it (toClean). Anything else, like a mission that was sent or closed since:
  // the crew page, where the work waits on its card.
  function resolveView(state, { enabled, toClean }) {
    const home = { view: "home", mission: null };
    if (!state || typeof state !== "object" || state.done) return home;
    if (state.view === "mission") return enabled ? { view: "mission", mission: null } : home;
    if (state.view !== "cleanup") return home;
    if (state.mission === "none") return { view: "cleanup", mission: "none" };
    if (typeof state.mission === "string" && (toClean || []).includes(state.mission)) return { view: "cleanup", mission: state.mission };
    return home;
  }
  // Everything the crew page draws. ready: funded missions waiting for their cleanup, the one whose cleanup was
  // started on this phone first, then the soonest planned day. waiting: in review or open, newest first. orange:
  // the one next step, the only orange button on the page. While Sapu Earth checks a mission or a sent cleanup and
  // nothing else waits, the next step is to wait: no button is orange, so POST A MISSION does not look like the
  // thing to do now.
  function homeModel({ missions, enabled, cleanup, mission }) {
    const list = enabled && Array.isArray(missions) ? missions.filter((m) => !!m && typeof m.id === "string") : [];
    const begun = (m) => !!(cleanup && cleanup.work) && m.id === cleanup.missionId;
    const day = (m) => (isDay(m.plan_date) ? m.plan_date : null);
    const ready = list.map((m, i) => ({ m, i })).filter((x) => x.m.status === "funded" && !x.m.cleanup_sent)
      .sort((a, b) => {
        if (begun(a.m) !== begun(b.m)) return begun(a.m) ? -1 : 1;
        const da = day(a.m), db = day(b.m);
        if (da !== db) return da === null ? 1 : db === null ? -1 : da < db ? -1 : 1;
        return a.i - b.i;
      }).map((x) => x.m);
    const plainDraft = !!(cleanup && cleanup.work) && !ready.some((m) => m.id === cleanup.missionId);
    const missionDraft = !!enabled && !!(mission && mission.work);
    const limit = list.filter((m) => ACTIVE_STATES.includes(m.status)).length >= ACTIVE_MAX;
    const checking = list.some((m) => m.status === "review" || m.status === "open" || (m.status === "funded" && !!m.cleanup_sent));
    const orange = ready[0] ? { kind: "ready", id: ready[0].id } : plainDraft ? { kind: "plain" }
      : missionDraft ? { kind: "mission" } : enabled && !limit && !checking ? { kind: "post" } : !enabled ? { kind: "solo" } : null;
    return {
      intro: !!enabled && !list.length && !missionDraft,
      ready, plainDraft, missionDraft,
      waiting: list.filter((m) => m.status === "review" || m.status === "open"),
      sent: list.filter((m) => m.status === "funded" && !!m.cleanup_sent),
      past: list.filter((m) => m.status === "done"),
      removed: list.filter((m) => m.status === "removed"),
      limit, orange,
    };
  }
  // ---------- end of crew page model ----------

  // ---------- state ----------
  const form = $("#form");
  const mform = $("#mform");
  // "now" are the mission's photos of the spot. They go up as before photos (docs/missions.md), its video
  // (now_video) as a video. The cleanup's two videos go up as videos with their stage (putFile).
  const files = { before: [], after: [], video_before: [], video_after: [], now: [], now_video: [] };
  // A mission with several spots (docs/missions.md, Spots): the cleanup asks the before and after photos of spots 2 to
  // SPOT_MAX in fields of their own, before_2, after_2, ... (spot 1 keeps before and after), and the day of each in
  // spot_date_2, ... (spot 1's is cleanup_date). The videos stay two, for the whole mission. A spot's photos go up with
  // &spot= (putFile).
  const SPOT_KINDS = [];
  for (let k = 2; k <= SPOT_MAX; k++) SPOT_KINDS.push(`before_${k}`, `after_${k}`);
  for (const k of SPOT_KINDS) files[k] = [];
  const SPOT_DAYS = SPOT_KINDS.filter((k) => k.startsWith("before_")).map((k) => "spot_date_" + k.slice(7));
  // "before_2" -> ["before", 2]; before, after and every other kind -> [kind, 1].
  const kindSpot = (kind) => { const x = /^(before|after)_([2-9])$/.exec(kind); return x ? [x[1], Number(x[2])] : [kind, 1]; };
  // The cleanup's files: every field's, also the fields of spots its mission does not have (what was picked there for
  // another mission stays on the phone until this cleanup is sent or deleted). sendItems: only those that go with it.
  const allItems = () => [...files.before, ...files.after, ...files.video_before, ...files.video_after, ...SPOT_KINDS.flatMap((k) => files[k])];
  const spotCount = () => spotsOf(pickedMission()).length || 1;
  const sendItems = () => allItems().filter((it) => kindSpot(it.kind)[1] <= spotCount());
  // The fields of spots 2 to SPOT_MAX, made once from spot 1's (its photos before and after, its day) and hidden until
  // the cleanup's mission has that spot (renderSpots). Each is a photo field like every other: before_2 has the id
  // f-before_2, its list data-list="before_2" and its note data-msg="before_2". Its label and the picker's name come
  // from renderSpots, in the page language.
  (function spotFields() {
    const photos = (kind, k, prev) => {
      const el = $(`#f-${kind}`).cloneNode(true), name = `${kind}_${k}`;
      el.id = "f-" + name;
      el.hidden = true;
      const input = el.querySelector('input[type="file"]');
      input.dataset.kind = name;
      delete input.dataset.i18nAria;
      el.querySelector(".thumbs").dataset.list = name;
      el.querySelector(".msg").dataset.msg = name;
      prev.after(el);
      return el;
    };
    let b = $("#f-before"), a = $("#f-after"), d = $("#planDayRow");
    for (let k = 2; k <= SPOT_MAX; k++) {
      b = photos("before", k, b);
      a = photos("after", k, a);
      const day = $("#f-date").cloneNode(true);
      day.id = "f-date_" + k;
      day.hidden = true;
      const input = day.querySelector("input");
      input.name = "spot_date_" + k;
      input.removeAttribute("required");
      d.after(day);
      d = day;
    }
  })();
  let partner = null;
  const geo = { cleanup: null, mission: null }; // {lat, lng, acc} from "Use my location now"
  let busy = false;
  // YOUR LOGO: "preparing" while the phone makes the square, "sending" while POST /api/logo runs, else null. Every
  // redraw reads it (renderLogo), so a language switch or a fresh list keeps the tile, the line and the locked picker.
  let logoPhase = null;
  let logoPreview = null; // the new square's object URL, shown while it is sent
  let logoEpoch = 0;      // logo answers so far: a list asked for before the last one must not bring the older state back
  let logoLast = null;    // the logo state of the last answer (POST /api/logo)
  // What the tile may load: a live logo, or the signed link to the waiting one.
  const LOGO_SRC = /^\/media\/[0-9a-f]{32}(\?exp=\d{10}&sig=[0-9a-f]{64})?$/;
  let sending = "cleanup"; // the form whose status line and progress bar are in use
  let seq = 0;
  const working = new Map(); // batch of picked files still being prepared -> { g: its form, seen: refusals at the pick }
  const stale = new Set();   // batches that outlived a whole wait (a conversion that never ends): not waited for again
  let waitingFiles = false;  // SEND was tapped and waits for its form's batches
  const sends = { cleanup: 0, mission: 0 }; // sends done per form: a pick made before one adds no files after it
  const doneShown = { cleanup: false, mission: false }; // the screen after a successful send
  // The screen on show: "home" (the crew page), "mission" (POST A MISSION) or "cleanup", and the history entry it
  // belongs to (setState).
  let view = "home";
  let lastState = null;
  let homeScroll = 0;     // where the crew page was when a form was opened from it
  let changeOpen = false; // CHANGE under the mission summary was tapped: the mission select and WHERE show
  let costsOpen = false;  // THE COSTS WERE DIFFERENT was tapped, or a cost is typed
  let goneNo = null;      // the number of the mission this cleanup lost (sent, closed or cancelled meanwhile)
  let lastFetch = 0;      // when GET /api/partner was last asked
  let started = false;    // start() is through: the page answers the back button
  // The restored drafts that lost files. The note asking for them again stays until each was sent or emptied.
  const reloadFor = { cleanup: false, mission: false };
  function reloadDone(g) {
    reloadFor[g] = false;
    if (!reloadFor.cleanup && !reloadFor.mission) setMsg($("#reloadNote"));
  }
  let clientRef = "";        // the mission form's retry key, kept in its draft
  let lastMissionNo = null;  // shown on the mission done screen
  let lastMissionUpdated = false; // the send updated a mission posted earlier (a resend with changes)
  let lastMissionPrice = null;    // the price the crew just sent, { currency, total, crew, people }, for the done screen

  // Per form: the form and the ids of its parts.
  const UI = {
    cleanup: { form, send: "#send", sendKey: "send", err: "#formErr", keep: "#keepOpen", progress: "#progress", status: "#status", done: "#done", other: "#f-currency-other" },
    mission: { form: mform, send: "#msend", sendKey: "m_send", err: "#mformErr", keep: "#mkeepOpen", progress: "#mprogress", status: "#mstatus", done: "#mdone", other: "#m-currency-other" },
  };
  const groupOf = (item) => formOfKind(item.kind);
  const itemsOf = (g) => (g === "mission" ? [...files.now, ...files.now_video] : sendItems());
  const newRef = () => [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");

  const localToday = (offsetDays = 0) => {
    const d = new Date(Date.now() + offsetDays * 86400000);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  };
  // "14 Nov", "14 Nov 2026", with the weekday "Sat 14 Nov" ("Sab, 14 Nov"), from YYYY-MM-DD, in the page language.
  function fmtDay(iso, withYear, weekday) {
    if (typeof iso !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return "";
    try {
      const opts = { day: "numeric", month: "short", timeZone: "UTC" };
      if (withYear) opts.year = "numeric";
      if (weekday) opts.weekday = "short";
      return new Date(iso + "T12:00:00Z").toLocaleDateString(lang === "id" ? "id-ID" : "en-GB", opts);
    } catch { return iso; }
  }
  // "95" or "28.50": cents only when there are cents.
  const eur = (n) => Number(n).toLocaleString(lang === "id" ? "id-ID" : "en-US",
    { minimumFractionDigits: Number.isInteger(Number(n)) ? 0 : 2, maximumFractionDigits: 2 });

  // ---------- language ----------
  // A text shown from a key keeps that key on its element (data-i18n), with the key's values (data-i18n-vars)
  // and any plain text around it (data-i18n-pre, data-i18n-post: a file name, a reference). applyLang shows
  // it again in the new language: labels, field messages, the line above SEND, status lines, TRY AGAIN.
  function textFor(el) {
    const d = el.dataset;
    return (d.i18nPre || "") + t(d.i18n, d.i18nVars ? JSON.parse(d.i18nVars) : null) + (d.i18nPost || "");
  }
  // Without a key it clears the text and everything kept with it, so an old message never comes back.
  function setMsg(el, key, vars, { pre, post } = {}) {
    if (!el) return;
    const keep = (name, v) => { if (key && v) el.dataset[name] = v; else delete el.dataset[name]; };
    keep("i18n", key);
    keep("i18nVars", vars && JSON.stringify(vars));
    keep("i18nPre", pre);
    keep("i18nPost", post);
    el.textContent = key ? textFor(el) : "";
  }
  function applyLang() {
    document.documentElement.lang = lang;
    $$("[data-i18n]").forEach((el) => { el.textContent = textFor(el); });
    $$("[data-ph]").forEach((el) => { el.placeholder = t(el.dataset.ph); });
    $$("[data-i18n-aria]").forEach((el) => el.setAttribute("aria-label", t(el.dataset.i18nAria)));
    $$(".lang button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
    $$(".thumb .rm").forEach((b) => b.setAttribute("aria-label", t("remove")));
    if (partner) setWho(`${t("uploading_as")} ${partner.name}`);
    else if (whoKey) setWhoKey(whoKey);
    fillCountries();
    fillCurrencies();
    renderCoords("cleanup");
    renderCoords("mission");
    ECHO.forEach(echoNum);
    renderSum("mission"); renderSum("cleanup");
    echoPost();
    renderMine();
    fillMissionPicker();
    renderHome();
    renderMissionDone();
    setCleanupFlavor();
    renderChips();
    syncMCrewSrc();
  }
  $$(".lang button").forEach((b) => b.addEventListener("click", () => {
    lang = b.dataset.lang;
    store.set("sapu-lang", lang);
    applyLang();
  }));

  function fillCountries() {
    let names = null;
    try { names = new Intl.DisplayNames([lang, "en"], { type: "region" }); } catch { /* old browser */ }
    const rows = ISO.map((c) => {
      let n = c;
      try { n = (names && names.of(c)) || c; } catch { /* unknown code */ }
      return [c, n];
    }).sort((a, b) => a[1].localeCompare(b[1], lang));
    for (const sel of [form.elements.country, mform.elements.country]) {
      // The crew's own country only on the first fill. A language switch keeps the choice, even an empty one:
      // a country emptied because its mission is gone must be chosen again, not turn into the crew's own.
      const cur = sel.options.length ? sel.value : (partner && partner.country) || "";
      sel.textContent = "";
      sel.append(new Option("", ""));
      for (const [c, n] of rows) sel.append(new Option(`${n} (${c})`, c));
      sel.value = cur;
    }
  }
  // The crew's own currency first, then the usual ones and Other. Choose… (empty) is there for a crew that must pick
  // one. Like the country, the start value only on the first fill: a language switch keeps the choice, even Choose….
  function fillCurrencies() {
    const codes = [...new Set([...ownCurrencies((partner && partner.country) || ""), ...CURRENCIES])];
    for (const u of Object.values(UI)) {
      const sel = u.form.elements.currency;
      const cur = sel.options.length ? sel.value : startCurrency();
      sel.textContent = "";
      sel.append(new Option(t("choose"), ""));
      for (const c of codes) sel.append(new Option(c, c));
      sel.append(new Option(t("other"), "other"));
      sel.value = cur;
      $(u.other).hidden = sel.value !== "other";
    }
  }
  for (const [g, u] of Object.entries(UI)) {
    u.form.elements.currency.addEventListener("change", () => {
      $(u.other).hidden = u.form.elements.currency.value !== "other";
      ECHO.forEach(echoNum);
      saveDraftOf(g);
    });
  }

  function setWho(text, bad) {
    const w = $("#who");
    w.textContent = text;
    w.classList.toggle("bad", !!bad);
    w.removeAttribute("data-i18n");
  }
  // A link problem keeps its text key, so switching language translates it. "sapu.earth/apply" becomes a link.
  let whoKey = null;
  function setWhoKey(key) {
    whoKey = key;
    setWho("", true);
    const text = t(key), link = "sapu.earth/apply", i = text.indexOf(link);
    if (i < 0) { $("#who").textContent = text; return; }
    const a = document.createElement("a");
    a.href = "/apply/";
    a.textContent = link;
    $("#who").append(text.slice(0, i), a, text.slice(i + link.length));
  }

  // ---------- screens: the crew page, POST A MISSION and a cleanup ----------
  // Before migration 0004 the partner API answers missions_enabled: false (and missions: []). The crew page then
  // has no mission cards and no POST A MISSION, and its one (orange) button is SEND A CLEANUP.
  const missionsOn = () => !!partner && partner.missions_enabled !== false && Array.isArray(partner.missions);
  // Every screen is a history entry of its own on the same address ({ sapu: 1, view, mission, fromHome, done }), so
  // the phone's back button goes from a form to the crew page while the link a crew saves, bookmarks or puts on its
  // home screen stays the plain ?k= link. Nothing writes location.hash, so /upload/#privacy keeps its meaning.
  const sendLocked = () => busy || waitingFiles;
  function setState(s, push) { lastState = s; if (push) history.pushState(s, ""); else history.replaceState(s, ""); }
  const ours = (s) => (s && typeof s === "object" && s.sapu === 1 ? s : null);
  // The cleanup's mission as its history entry names it: an id, or "none" (also while nothing is chosen yet).
  const entryMission = () => { const v = form.elements.mission_id.value; return v && v !== NO_MISSION ? v : NO_MISSION; };
  const stateFor = (next, prev) => ({ sapu: 1, view: next.view, mission: next.view === "cleanup" ? next.mission : null,
    fromHome: next.view !== "home" && !!(prev && prev.fromHome), done: false });
  const ctx = () => ({ enabled: missionsOn(), toClean: missionsToClean().map((m) => m.id) });
  // An entry of a cleanup that this phone's unsent cleanup does not belong to (another tab opened another mission):
  // the crew page, where that work waits on its own card. Photos with one mission's paper never move by themselves.
  const fit = (next) => (next.view === "cleanup" && cleanupWork() && next.mission !== entryMission() ? { view: "home", mission: null } : next);
  // Every screen change puts the focus on the H1, so a screen reader says where the crew is now.
  const focusTitle = () => $(".fp-title").focus({ preventScroll: true });
  // A new screen starts where it should at once, not with the page's smooth scroll across the old one.
  function jumpTo(y) {
    const root = document.documentElement, was = root.style.scrollBehavior;
    root.style.scrollBehavior = "auto";
    scrollTo(0, y);
    root.style.scrollBehavior = was;
  }
  // Shows a screen. Leaving a done screen empties its form, as its BACK TO YOUR CREW PAGE does. A cleanup takes its
  // mission (or none) here, POST A MISSION its crew size. Returns the screen as shown, with the cleanup's mission as
  // the form holds it.
  function show(next) {
    if (view === "cleanup" && doneShown.cleanup) resetCleanup();
    if (view === "mission" && doneShown.mission) resetMission();
    if (view === "home" && next.view !== "home") homeScroll = scrollY;
    view = next.view;
    if (view === "cleanup") pickForCleanup(next.mission);
    if (view === "mission") prefillMissionCrew();
    render();
    return { view, mission: view === "cleanup" ? entryMission() : null };
  }
  // Opens a form from the crew page as a new history entry: the phone's back button comes back to the crew page.
  function go(next, { mission } = {}) {
    if (sendLocked()) return false;
    const fromHome = view === "home";
    const shown = show({ view: next, mission: mission || NO_MISSION });
    setState(stateFor(shown, { fromHome }), true);
    jumpTo(0);
    focusTitle();
    return true;
  }
  // ← CREW PAGE and BACK TO YOUR CREW PAGE: back to the entry the form was opened from, so the browser puts the crew
  // page back where it was. Without one, the crew page on this entry, at its last place.
  function toHome() {
    if (sendLocked()) return;
    if (lastState && lastState.fromHome) { history.back(); return; }
    show({ view: "home", mission: null });
    setState(stateFor({ view: "home" }, null), false);
    jumpTo(homeScroll);
    focusTitle();
  }
  function render() {
    $("#home").hidden = view !== "home";
    for (const [g, u] of Object.entries(UI)) {
      u.form.hidden = view !== g || doneShown[g];
      $(u.done).hidden = view !== g || !doneShown[g];
    }
    $("#viewBar").hidden = view === "home" || !!doneShown[view];
    renderTitle();
    if (view === "home") renderHome();
    if (view === "cleanup") setCleanupFlavor();
  }
  // The H1 names the screen. THANK YOU keeps the title of the cleanup it thanks for.
  function renderTitle() {
    if (view === "cleanup" && doneShown.cleanup) return;
    const mark = $(".fp-title mark");
    const picked = view === "cleanup" ? pickedMission() : null;
    if (view === "mission") setMsg(mark, "title_mission");
    else if (view !== "cleanup") setMsg(mark, "title");
    else if (!missionsOn()) setMsg(mark, "mode_cleanup");
    else if (picked) setMsg(mark, "title_cleanup_m", { no: picked.no });
    else setMsg(mark, "title_plain");
  }
  // The phone's back button. While a send runs or waits for its files the form stays (the entry is pushed again),
  // with its keep-open line and progress, and beforeunload asks before a real leave.
  addEventListener("popstate", (ev) => {
    if (sendLocked()) { history.pushState(lastState, ""); return; }
    if (!started) return; // start() reads the entry itself
    const s = ours(ev.state);
    const shown = show(fit(resolveView(s, ctx())));
    setState(stateFor(shown, s), false);
    focusTitle();
  });
  addEventListener("beforeunload", (ev) => { if (sendLocked()) { ev.preventDefault(); ev.returnValue = ""; } });
  $$("[data-go]").forEach((b) => b.addEventListener("click", () => {
    if (b.dataset.go === "mission") go("mission");
    else openCleanup(NO_MISSION);
  }));
  $("#back").addEventListener("click", () => toHome());

  // ---------- drafts: typed fields in localStorage ----------
  // Consent is never saved: it must be given for the photos in front of the person now.
  // The money fields have their own names (crew_each_local, other_local), so the totals a draft from before the page added
  // them up kept (total_cost_local, crew_pay_local) are never read back as a pay for each person: the crew types it again.
  const DRAFT_FIELDS = ["cleanup_date", "place_name", "country", "kg", "sacks", "crew_size", "hours", "disposal",
    "currency", "currency_other", "crew_each_local", "other_local", "notes", "post_url", "private_note", "mission_id", ...SPOT_DAYS];
  const draftKey = () => "sapu-upload-draft:" + tokenTag;
  // What a mission filled in (el.dataset.prefilled) is saved with the draft, so a reload still knows it: also the day of
  // each spot after the first (prefillFromMission).
  const PREFILL_FIELDS = ["place_name", "country", "crew_size", ...SPOT_DAYS];
  const okCoords = (c) => !!c && Number.isFinite(c.lat) && Number.isFinite(c.lng);
  // Never while THANK YOU shows: a field edited during the upload fires its change when the focus moves to THANK YOU,
  // and what was just sent must not come back as unsent work. lost: the mission this cleanup lost (goneNo), so a later
  // load still knows that its photos may show that mission's paper.
  function saveDraft() {
    if (doneShown.cleanup) return;
    const d = {};
    for (const f of DRAFT_FIELDS) d[f] = form.elements[f].value;
    d.prefilled = {};
    for (const f of PREFILL_FIELDS) if (form.elements[f].dataset.prefilled !== undefined) d.prefilled[f] = form.elements[f].dataset.prefilled;
    d.coords = geo.cleanup;
    d.fileCount = allItems().length;
    d.lost = goneNo;
    store.set(draftKey(), JSON.stringify(d));
  }
  // Returns the draft, with dropped: the id of its mission when that mission cannot take a cleanup any more (sent,
  // closed or cancelled meanwhile). start() drops it once the files are back (dropMission).
  function loadDraft() {
    let d = null;
    try { d = JSON.parse(store.get(draftKey()) || "null"); } catch { d = null; }
    if (!d || typeof d !== "object") return null;
    for (const f of DRAFT_FIELDS) if (typeof d[f] === "string" && d[f] !== "") form.elements[f].value = d[f];
    if (d.prefilled && typeof d.prefilled === "object") {
      for (const f of PREFILL_FIELDS) if (typeof d.prefilled[f] === "string") form.elements[f].dataset.prefilled = d.prefilled[f];
    } else {
      // A draft from before the marks were saved, or from a tab still on that code: a value equal to its own
      // mission's was filled in by it.
      const m = missionList().find((x) => x.id === d.mission_id);
      if (m) for (const f of PREFILL_FIELDS) {
        const v = m[f] == null ? "" : String(m[f]);
        if (v !== "" && form.elements[f].value.trim() === v) form.elements[f].dataset.prefilled = v;
      }
    }
    // "No mission" until then, never another one quietly.
    const sel = form.elements.mission_id;
    d.dropped = null;
    if (typeof d.mission_id === "string" && d.mission_id !== "" && sel.value !== d.mission_id) {
      sel.value = NO_MISSION;
      if (d.mission_id !== NO_MISSION) d.dropped = d.mission_id;
    }
    if (sel.value === NO_MISSION && Number.isInteger(d.lost) && d.lost > 0) goneNo = d.lost;
    if (okCoords(d.coords)) geo.cleanup = d.coords;
    $("#f-currency-other").hidden = form.elements.currency.value !== "other";
    return d;
  }
  // The mission form has its own draft. Its client_ref goes with it: a retry after a lost answer,
  // even after a reload, gets the mission that was already stored instead of a second one. The price and crew pay an
  // older draft typed (price_local, crew_local) are not restored: a crew total must never come back as a pay for each
  // person, so the crew types the pay for each person again.
  const M_DRAFT_FIELDS = ["place_name", "country", "task", "plan_date", "crew_size",
    "currency", "currency_other", "crew_each_local", "other_local", "private_note"];
  const mdraftKey = () => "sapu-mission-draft:" + tokenTag;
  // Never while MISSION #N shows (see saveDraft): the mission just posted must not come back as MISSION NOT POSTED YET.
  function saveMDraft() {
    if (doneShown.mission) return;
    const d = { client_ref: clientRef };
    for (const f of M_DRAFT_FIELDS) d[f] = mform.elements[f].value;
    // The crew size the form filled in from an earlier mission, so a reload still knows it was not typed.
    d.prefilled = {};
    if (mform.elements.crew_size.dataset.prefilled !== undefined) d.prefilled.crew_size = mform.elements.crew_size.dataset.prefilled;
    d.coords = geo.mission;
    d.fileCount = itemsOf("mission").length;
    store.set(mdraftKey(), JSON.stringify(d));
  }
  function loadMDraft() {
    let d = null;
    try { d = JSON.parse(store.get(mdraftKey()) || "null"); } catch { d = null; }
    if (!d || typeof d !== "object") return null;
    for (const f of M_DRAFT_FIELDS) if (typeof d[f] === "string" && d[f] !== "") mform.elements[f].value = d[f];
    // A draft from before the mark was saved has none: its crew size counts as typed.
    if (d.prefilled && typeof d.prefilled === "object" && typeof d.prefilled.crew_size === "string") {
      mform.elements.crew_size.dataset.prefilled = d.prefilled.crew_size;
    }
    if (okCoords(d.coords)) geo.mission = d.coords;
    if (typeof d.client_ref === "string" && /^[0-9a-f]{32}$/.test(d.client_ref)) clientRef = d.client_ref;
    $("#m-currency-other").hidden = mform.elements.currency.value !== "other";
    return d;
  }
  const saveDraftOf = (g) => (g === "mission" ? saveMDraft() : saveDraft());
  for (const [g, u] of Object.entries(UI)) {
    u.form.addEventListener("input", (ev) => {
      const f = ev.target.closest(".field, .check");
      if (f) { f.classList.remove("invalid"); setMsg(fmsgFor(f, false)); }
      if (ECHO.includes(ev.target.name)) echoNum(ev.target.name);
      if (ev.target.name === "post_url") echoPost();
      saveDraftOf(g);
      afterInput(g, ev.target.name);
    });
    u.form.addEventListener("change", (ev) => { saveDraftOf(g); afterInput(g, ev.target.name); });
  }

  // ---------- files in IndexedDB: picked photos and videos survive a reload or a discarded tab ----------
  const idb = (() => {
    let dbp = null;
    const open = () => dbp || (dbp = new Promise((resolve, reject) => {
      const r = indexedDB.open("sapu-upload", 1);
      r.onupgradeneeded = () => r.result.createObjectStore("files", { keyPath: "id" });
      // Safari closes the connection when it restarts its background process: the next call opens a new one,
      // so removed and sent files still leave the phone.
      r.onsuccess = () => { r.result.onclose = () => { dbp = null; }; resolve(r.result); };
      r.onerror = () => { dbp = null; reject(r.error); };
    }));
    const run = async (mode, fn) => {
      let db = await open();
      let tx;
      try { tx = db.transaction("files", mode); } catch {
        dbp = null; // a closed connection: open again once
        db = await open();
        tx = db.transaction("files", mode);
      }
      return new Promise((resolve, reject) => {
        const req = fn(tx.objectStore("files"));
        tx.oncomplete = () => resolve(req && req.result);
        tx.onerror = tx.onabort = () => reject(tx.error);
      });
    };
    const safe = (p, dflt) => p.catch(() => dflt);
    return {
      put: (it) => safe(run("readwrite", (st) => st.put({
        id: it.id, tag: tokenTag, kind: it.kind, type: it.type, blob: it.blob, key: it.key, dur: it.dur || null,
      }))),
      del: (id) => safe(run("readwrite", (st) => st.delete(id))),
      all: () => safe(run("readonly", (st) => st.getAll()), []),
    };
  })();

  // Returns how many files came back for each form. A video picked on the page before the two video fields
  // (kind "video") has no field any more: it is dropped, and the draft's file count brings up the note to
  // add the photos and videos again.
  async function restoreFiles() {
    const recs = (await idb.all()) || [];
    const n = { cleanup: 0, mission: 0 };
    for (const r of recs.sort((a, b) => a.id - b.id)) {
      if (r.tag !== tokenTag || !r.blob || !files[r.kind]) { idb.del(r.id); continue; }
      const max = VIDEO_KINDS.includes(r.kind) ? LIMIT.videos : LIMIT.photos;
      if (files[r.kind].length >= max) continue;
      seq = Math.max(seq, r.id);
      const item = { id: r.id, kind: r.kind, type: r.type, blob: r.blob, key: r.key || null, dur: r.dur, progress: r.key ? 1 : 0 };
      files[r.kind].push(item);
      showItem(item);
      if (item.key) { item.el.classList.add("done"); setProgress(item, 1); }
      n[groupOf(item)]++;
    }
    syncDrops();
    return n;
  }

  // ---------- photos ----------
  async function decode(file) {
    if (typeof createImageBitmap === "function") {
      try { return await createImageBitmap(file, { imageOrientation: "from-image" }); } catch { /* try plain */ }
      try { return await createImageBitmap(file); } catch { /* try <img> */ }
    }
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => { resolve(img); setTimeout(() => URL.revokeObjectURL(url), 0); };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("decode")); };
      img.src = url;
    });
  }
  // Safari, and every browser on an iPhone (they all run WebKit), writes a small Exif block (colour space and
  // picture size, no location) and a Photoshop block into each canvas JPEG. The server refuses any JPEG with
  // Exif, to keep camera data out, so only the JFIF header (APP0) and a colour profile (APP2 ICC_PROFILE)
  // stay and every other APPn segment goes. The image data is not touched. Same code in apply/apply.js.
  async function cleanJpeg(blob) {
    const b = new Uint8Array(blob.arrayBuffer ? await blob.arrayBuffer() : await new Response(blob).arrayBuffer());
    if (b[0] !== 0xff || b[1] !== 0xd8) return blob;
    const keep = [b.subarray(0, 2)];
    let i = 2, cut = false;
    while (i + 4 <= b.length) {
      if (b[i] !== 0xff) return blob; // not where a segment should start: leave the file as it is
      const m = b[i + 1];
      if (m === 0xff) { i++; continue; } // fill byte
      if (m === 0xda || m === 0xd9) break; // the image data starts here
      const len = (b[i + 2] << 8) | b[i + 3];
      if (len < 2 || i + 2 + len > b.length) return blob;
      const icc = m === 0xe2 && String.fromCharCode(...b.subarray(i + 4, i + 15)) === "ICC_PROFILE";
      if (m >= 0xe1 && m <= 0xef && !icc) cut = true;
      else keep.push(b.subarray(i, i + 2 + len));
      i += 2 + len;
    }
    if (!cut) return blob;
    keep.push(b.subarray(i));
    return new Blob(keep, { type: "image/jpeg" });
  }
  // Re-encoding through a canvas drops the camera's Exif, GPS included; cleanJpeg removes what the browser adds.
  async function toJpeg(file) {
    const src = await decode(file);
    const w = src.naturalWidth || src.width, h = src.naturalHeight || src.height;
    if (!w || !h) throw new Error("decode");
    const scale = Math.min(1, 2000 / Math.max(w, h));
    const cw = Math.max(1, Math.round(w * scale)), ch = Math.max(1, Math.round(h * scale));
    const canvas = document.createElement("canvas");
    canvas.width = cw; canvas.height = ch;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, cw, ch);
    ctx.drawImage(src, 0, 0, cw, ch);
    if (src.close) src.close();
    const blob = await new Promise((res) => canvas.toBlob(res, "image/jpeg", 0.85));
    canvas.width = canvas.height = 0; // free memory on small phones
    if (!blob) throw new Error("decode");
    return cleanJpeg(blob);
  }

  // ---------- crew logo: the same block in upload/upload.js and apply/apply.js ----------
  // A crew's logo leaves the phone as a fresh 320 x 320 JPEG, whatever was picked (a photo, a PNG with a see-through
  // background, the first frame of a GIF): the whole picture fitted inside and centred, never cropped, so nothing of a
  // logo or its lettering is lost and no crop screen is needed. Only the JFIF header, the colour profile and the image
  // go (cleanJpeg): no Exif, GPS, XMP or phone data. The server takes exactly that and nothing else (logoJpegInfo in
  // functions/_lib/logos.js). 320 px stays sharp at 96 CSS px on a 3x screen and in link previews.
  const LOGO_SIDE = 320, LOGO_PAD = 10, LOGO_MIN_INPUT = 96, LOGO_MAX_BYTES = 150 * 1024;
  // Where the picture goes on the square: as big as fits inside the padding (a small picture grows too), centred.
  function logoFit(w, h) {
    const box = LOGO_SIDE - 2 * LOGO_PAD;
    const scale = Math.min(box / w, box / h);
    const dw = Math.max(1, Math.round(w * scale)), dh = Math.max(1, Math.round(h * scale));
    return { dx: Math.round((LOGO_SIDE - dw) / 2), dy: Math.round((LOGO_SIDE - dh) / 2), dw, dh };
  }
  // The colour under the picture, from its RGBA bytes. A light logo on a see-through PNG (white lettering, say) would
  // vanish on white, so more than 2% see-through with the rest light on average gets the site's ink; everything else
  // gets white.
  function logoBackground(px) {
    let clear = 0, seen = 0, light = 0;
    for (let i = 0; i + 3 < px.length; i += 4) {
      if (px[i + 3] < 128) { clear++; continue; }
      seen++;
      light += (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) / 255;
    }
    return seen > 0 && clear / (clear + seen) > 0.02 && light / seen > 0.8 ? "#1c1813" : "#ffffff";
  }
  // The square JPEG to send, or an Error: "small" (under LOGO_MIN_INPUT px, a logo would only blur), "decode".
  async function toLogoJpeg(file) {
    const src = await decode(file); // EXIF rotation applies
    const w = src.naturalWidth || src.width, h = src.naturalHeight || src.height;
    if (!w || !h) throw new Error("decode");
    if (Math.max(w, h) < LOGO_MIN_INPUT) {
      if (src.close) src.close();
      throw new Error("small");
    }
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = LOGO_SIDE;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingQuality = "high";
    const { dx, dy, dw, dh } = logoFit(w, h);
    ctx.drawImage(src, dx, dy, dw, dh);
    let bg = "#ffffff";
    try { bg = logoBackground(ctx.getImageData(dx, dy, dw, dh).data); } catch { /* pixels that cannot be read: white */ }
    // The background goes under the picture, so its half see-through edges blend into it.
    ctx.globalCompositeOperation = "destination-over";
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, LOGO_SIDE, LOGO_SIDE);
    if (src.close) src.close();
    let blob = null;
    for (const q of [0.9, 0.75]) {
      const out = await new Promise((res) => canvas.toBlob(res, "image/jpeg", q));
      if (!out || out.type !== "image/jpeg") break; // this browser cannot make a JPEG
      const clean = await cleanJpeg(out);
      if (clean.size <= LOGO_MAX_BYTES) { blob = clean; break; }
    }
    canvas.width = canvas.height = 0; // free memory on small phones
    if (!blob) throw new Error("decode");
    return blob;
  }
  // ---------- end of the crew logo block ----------

  // ---------- videos ----------
  function videoType(file) {
    const ext = (file.name.split(".").pop() || "").toLowerCase();
    const byType = ["video/mp4", "video/quicktime", "video/webm"].includes(file.type) ? file.type : null;
    return byType || VIDEO_EXT[ext] || null;
  }
  function videoDuration(file) {
    return new Promise((resolve) => {
      const v = document.createElement("video");
      const url = URL.createObjectURL(file);
      let settled = false;
      const done = (d) => { if (settled) return; settled = true; URL.revokeObjectURL(url); v.removeAttribute("src"); v.load(); resolve(d); };
      v.preload = "metadata";
      v.muted = true;
      v.onloadedmetadata = () => done(Number.isFinite(v.duration) ? v.duration : null);
      v.onerror = () => done(null);
      setTimeout(() => done(null), 10000);
      v.src = url;
    });
  }

  // ---------- adding / removing files ----------
  function fieldMsg(kind, key, vars, around) { setMsg($(`[data-msg="${kind}"]`), key, vars, around); }
  // A picked file that is turned away (too many, too big, too long, unreadable), kept per form: a SEND that waited
  // for its files learns which fields refused one since the pick started (filesReady) and points at them.
  const formOfKind = (kind) => (kind === "now" || kind === "now_video" ? "mission" : "cleanup");
  const refusedKinds = { cleanup: [], mission: [] };
  function refuse(kind, key, vars, around) {
    refusedKinds[formOfKind(kind)].push(kind);
    fieldMsg(kind, key, vars, around);
  }

  // The pickers of the two forms. The logo's picker (#logoInput) has no data-kind and is no form's: it has its own.
  $$('input[type="file"][data-kind]').forEach((input) => input.addEventListener("change", () => {
    const g = input.form === mform ? "mission" : "cleanup";
    const seen = refusedKinds[g].length;
    const job = addPicked(input, g);
    const forget = () => { working.delete(job); stale.delete(job); };
    working.set(job, { g, seen });
    job.then(forget, forget);
  }));

  // gen: the form's send count when the files were picked. Once that form is sent, the rest of the pick is dropped,
  // so a late file never lands in the sent form, on the phone or in the next form.
  async function addPicked(input, g) {
    const kind = input.dataset.kind;
    const gen = sends[g];
    const picked = [...input.files];
    input.value = "";
    fieldMsg(kind);
    const fld = $(`#f-${kind}`);
    fld.querySelector(".drop").classList.remove("invalid");
    fld.querySelector(".thumbs").classList.remove("invalid");
    setMsg($("#reloadNote"));
    // New media means the consent must be given again, for these files. Unticked at once, so a tick given
    // while they are still being prepared counts and is not undone afterwards.
    if (picked.length) input.form.elements.consent.checked = false;
    for (const file of picked) {
      if (sends[g] !== gen) break;
      if (VIDEO_KINDS.includes(kind)) await addVideo(kind, file, gen);
      else await addPhoto(kind, file, gen);
    }
    syncDrops();
    if (sends[g] === gen) saveDraftOf(g);
  }

  async function addPhoto(kind, file, gen) {
    const g = formOfKind(kind);
    if (files[kind].length >= LIMIT.photos) { refuse(kind, "e_max_photos"); return; }
    if (file.size > LIMIT.photoInputBytes) { refuse(kind, "e_photo_big"); return; }
    const item = { id: ++seq, kind, type: "image/jpeg", blob: null, key: null, progress: 0 };
    files[kind].push(item);
    const el = renderThumb(item);
    el.classList.add("busy");
    try {
      item.blob = await toJpeg(file);
      if (!files[kind].includes(item) || sends[g] !== gen) return; // removed, or its form was sent meanwhile: off the phone too
      el.classList.remove("busy");
      addPreview(item);
      idb.put(item);
    } catch {
      if (!files[kind].includes(item) || sends[g] !== gen) return;
      removeItem(item);
      refuse(kind, "e_decode", null, { pre: `${file.name}: ` });
    }
  }

  // kind: the video field (VIDEO_KINDS), one clip each.
  async function addVideo(kind, file, gen) {
    const g = formOfKind(kind);
    if (files[kind].length >= LIMIT.videos) { refuse(kind, "e_max_videos"); return; }
    const type = videoType(file);
    if (!type) { refuse(kind, "e_video_type"); return; }
    if (file.size > LIMIT.videoBytes) { refuse(kind, "e_video_big"); return; }
    const dur = await videoDuration(file);
    if (sends[g] !== gen) return; // its form was sent while the length was read
    if (dur !== null && dur > LIMIT.videoSecs) { refuse(kind, "e_video_long", null, { post: ` (${Math.round(dur)} s)` }); return; }
    // Remove GPS and phone model from MP4/MOV before anything leaves the phone (WebM goes as it is). A clip
    // the page could not check (videoclean.js did not load, or it could not read the clip) is refused, so a
    // video never goes up with its location.
    const clean = type === "video/webm" ? { blob: file }
      : window.SapuVideoClean ? await window.SapuVideoClean.stripVideoLocation(file) : { ok: false };
    if (sends[g] !== gen) return; // its form was sent while this video was being prepared
    if (clean.ok === false) { refuse(kind, "e_video_check"); return; }
    // Another clip picked in this field while this one was being prepared got in first: still one per field.
    if (files[kind].length >= LIMIT.videos) { refuse(kind, "e_max_videos"); return; }
    const item = { id: ++seq, kind, type, blob: clean.blob, key: null, progress: 0, dur };
    files[kind].push(item);
    showItem(item);
    idb.put(item);
  }

  function addPreview(item) {
    item.url = URL.createObjectURL(item.blob);
    if (VIDEO_KINDS.includes(item.kind)) {
      const v = document.createElement("video");
      v.muted = true; v.playsInline = true; v.preload = "metadata";
      v.src = item.url + "#t=0.5";
      item.el.prepend(v);
      const lab = document.createElement("span");
      lab.className = "vlabel";
      lab.textContent = "VIDEO" + (item.dur ? ` ${Math.round(item.dur)}s` : "");
      item.el.append(lab);
    } else {
      const img = document.createElement("img");
      img.alt = "";
      img.src = item.url;
      item.el.prepend(img);
    }
  }
  function showItem(item) { renderThumb(item); addPreview(item); }

  function renderThumb(item) {
    const el = document.createElement("div");
    el.className = "thumb";
    el.dataset.id = item.id;
    const rm = document.createElement("button");
    rm.type = "button"; rm.className = "rm"; rm.textContent = "✕"; rm.setAttribute("aria-label", t("remove"));
    rm.addEventListener("click", () => { if (!busy) { removeItem(item); syncDrops(); saveDraftOf(groupOf(item)); } });
    const bar = document.createElement("div");
    bar.className = "bar";
    bar.append(document.createElement("i"));
    el.append(rm, bar);
    $(`[data-list="${item.kind}"]`).append(el);
    item.el = el;
    return el;
  }
  function removeItem(item) {
    files[item.kind] = files[item.kind].filter((x) => x !== item);
    if (item.url) URL.revokeObjectURL(item.url);
    if (item.el) item.el.remove();
    idb.del(item.id);
  }
  function syncDrops() {
    for (const k of Object.keys(files)) {
      const max = VIDEO_KINDS.includes(k) ? LIMIT.videos : LIMIT.photos;
      $(`#f-${k} .drop`).classList.toggle("full", files[k].length >= max);
    }
  }
  function setProgress(item, frac) {
    item.progress = frac;
    if (item.el) item.el.querySelector(".bar i").style.width = Math.round(frac * 100) + "%";
    const g = groupOf(item);
    const all = itemsOf(g);
    const total = all.reduce((s, x) => s + (x.blob ? x.blob.size : 0), 0) || 1;
    const sent = all.reduce((s, x) => s + (x.key ? x.blob.size : x.blob ? x.blob.size * (x.progress || 0) : 0), 0);
    $(UI[g].progress + " i").style.width = Math.round((sent / total) * 100) + "%";
  }

  // ---------- location ----------
  const GEO = {
    cleanup: { box: "#coords", msg: "#geoMsg", btn: "#geo" },
    mission: { box: "#mcoords", msg: "#mgeoMsg", btn: "#mgeo" },
  };
  function renderCoords(g) {
    const box = $(GEO[g].box);
    const c = geo[g];
    box.textContent = "";
    if (!c) return;
    box.append(`${t("geo_ok")}: ${c.lat.toFixed(5)}, ${c.lng.toFixed(5)}${c.acc ? ` (±${Math.round(c.acc)} m) ` : " "}`);
    const clear = document.createElement("button");
    clear.type = "button"; clear.className = "b b-sm b-ghost"; clear.textContent = t("geo_clear");
    clear.addEventListener("click", () => { geo[g] = null; renderCoords(g); saveDraftOf(g); });
    box.append(clear);
  }
  for (const g of Object.keys(GEO)) {
    $(GEO[g].btn).addEventListener("click", () => {
      const msg = $(GEO[g].msg);
      msg.className = "msg";
      if (!navigator.geolocation) { msg.className = "msg err"; setMsg(msg, "geo_fail"); return; }
      setMsg(msg, "locating");
      navigator.geolocation.getCurrentPosition(
        (p) => {
          geo[g] = { lat: p.coords.latitude, lng: p.coords.longitude, acc: p.coords.accuracy };
          setMsg(msg);
          renderCoords(g);
          saveDraftOf(g);
        },
        () => { msg.className = "msg err"; setMsg(msg, "geo_fail"); },
        { enableHighAccuracy: true, timeout: 20000, maximumAge: 60000 }
      );
    });
  }

  // ---------- numbers ----------
  // Accepts "42.5" and "42,5". A 3-digit group after a separator means thousands in every field:
  // "1,500", "1.500" and "1 500" are all 1500 (Kenya, Philippines and South Africa write "1,500",
  // Indonesia writes "1.500"). Nobody weighs trash to 3 decimals. With both marks, the last one is the
  // decimal mark: "1,500.50" and "1.500,50" are 1500.5. Only a currency sign or code of the listed
  // currencies around the number (Rp, ₱, KSh, USh, TSh, FRw, ₦, GH₵, FCFA, CFA, R and so on), the "/=" or "/-"
  // that East Africa and India write after an amount, and kg after it, are dropped: "Rp 1.500.000,-", "₱5,000",
  // "KSh 1,500/=", "25 000 FCFA", "IDR 1500000" and "25 kg" all read. Any other word ("1,5 jt", "500 rb",
  // "45 min", "2 ton") stays an error, so it is never read as a smaller number or in another unit.
  const CUR_SIGN = "[₱$€£¥₹฿₫₩₨₦₵¢]";
  // The first word that fits is taken, so one that starts another comes after it (RF after RWF, R last).
  const CUR_WORD = "IDR|PHP|MYR|THB|VND|INR|LKR|KES|UGX|TZS|RWF|NGN|GHS|GHC|XOF|XAF|ZAR|BRL|USD|EUR|SGD|" +
    "GH₵|GH¢|KShs?|UShs?|TShs?|Shs?|FRw|RF|F\\s?CFA|CFA|Rp|Rs|RM|US|R|P|N|F";
  const LEAD = new RegExp(`^(?:(?:${CUR_WORD})\\.?\\s*)?(?:${CUR_SIGN}\\s*)?`, "i");
  const TAIL = new RegExp(`\\s*(?:${CUR_SIGN}|(?:${CUR_WORD})|kgs?)$`, "i");
  const DASH = /\s*(?:\/[=-]|[.,]-)$/; // "1,500/=", "500/-", "1.500.000,-"
  function parseNum(raw) {
    if (raw.trim() === "") return null;
    const s0 = raw.trim().replace(LEAD, "").replace(DASH, "").replace(TAIL, "").replace(DASH, "").replace(/\s+/g, "");
    if (!/^[\d.,]+$/.test(s0)) return NaN;
    if (/^\d{1,3}([.,]\d{3})+$/.test(s0)) return Number(s0.replace(/[.,]/g, ""));
    if (/^\d{1,3}(,\d{3})+\.\d{1,2}$/.test(s0)) return Number(s0.replace(/,/g, ""));
    if (/^\d{1,3}(\.\d{3})+,\d{1,2}$/.test(s0)) return Number(s0.replace(/\./g, "").replace(",", "."));
    const s = /^\d+,\d+$/.test(s0) ? s0.replace(",", ".") : s0;
    return /^\d+(\.\d+)?$/.test(s) ? Number(s) : NaN;
  }
  // ---------- post links: the same block in upload/upload.js and functions/_lib/social.js ----------
  // postLink(text): the link to one Instagram or TikTok post as people paste it (Share, then Copy link, or the address
  // bar). Returns { site: "instagram" | "tiktok", url, account }: url in its one stored form, account the TikTok account the
  // link names, in lower case (null for Instagram, whose post links do not say whose post it is). Returns { short: true }
  // for a short link that redirects and so cannot be checked, and null for anything else. A paste without https:// on one
  // of these hosts gets it.
  // Instagram: instagram.com, www. or m., then /p/<code>, /reel/<code> or /reels/<code>, also with an account in front
  //   (/<account>/p/<code>); query (?igsh=) and hash dropped: https://www.instagram.com/p/<code>/ or /reel/<code>/.
  // TikTok: tiktok.com, www. or m., then /@<account>/video/<digits> or /@<account>/photo/<digits>; query and hash
  //   dropped: https://www.tiktok.com/@<account>/video/<digits> (or /photo/).
  // Short: vm.tiktok.com, vt.tiktok.com, tiktok.com/t/..., instagr.am, instagram.com/share/... .
  // Never: http:, another host or a port, a login in the link, a space, a profile, a story, more than POST_MAX characters.
  const POST_MAX = 300;
  const IG_HOST = /^(?:www\.|m\.)?instagram\.com$/;
  const TT_HOST = /^(?:www\.|m\.)?tiktok\.com$/;
  const BARE = /^(?:(?:www\.|m\.)?(?:instagram|tiktok)\.com|v[mt]\.tiktok\.com|(?:www\.)?instagr\.am)\//i;
  function postLink(text) {
    if (typeof text !== "string") return null;
    let s = text.trim();
    if (BARE.test(s)) s = "https://" + s;
    if (!s || s.length > POST_MAX || /\s/.test(s)) return null;
    let u;
    try { u = new URL(s); } catch { return null; }
    if (u.protocol !== "https:" || u.username || u.password || u.port) return null;
    const host = u.hostname, path = u.pathname;
    if (host === "vm.tiktok.com" || host === "vt.tiktok.com" || host === "instagr.am" || host === "www.instagr.am"
      || (TT_HOST.test(host) && path.startsWith("/t/")) || (IG_HOST.test(host) && path.startsWith("/share/"))) return { short: true };
    let m = IG_HOST.test(host) && /^\/(?:[A-Za-z0-9._]{1,30}\/)?(p|reels?)\/([A-Za-z0-9_-]{5,40})\/?$/.exec(path);
    if (m) return { site: "instagram", url: `https://www.instagram.com/${m[1] === "p" ? "p" : "reel"}/${m[2]}/`, account: null };
    m = TT_HOST.test(host) && /^\/@([A-Za-z0-9._]{2,24})\/(video|photo)\/(\d{8,25})\/?$/.exec(path);
    if (m) return { site: "tiktok", url: `https://www.tiktok.com/@${m[1]}/${m[2]}/${m[3]}`, account: m[1].toLowerCase() };
    return null;
  }
  // ---------- end of the post link block ----------
  // Show how a typed number was read, for example "= 1,500 kg", so mistakes are visible. Plain digits get the line
  // from 5 digits on: "1500000" is easy to misread, "= 1.500.000 IDR" is not.
  function echoNum(name) {
    const out = $(`[data-echo="${name}"]`);
    if (!out) return;
    const f = out.closest("form");
    const raw = f.elements[name].value;
    const n = parseNum(raw);
    if (!raw.trim() || !Number.isFinite(n) || /^\d{1,4}$/.test(raw.trim())) { out.textContent = ""; return; }
    const unit = name === "kg" ? "kg" : currencyOf(f) || ""; // no unit while the currency is on Choose…
    out.textContent = `= ${n.toLocaleString(lang === "id" ? "id-ID" : "en-US", { maximumFractionDigits: 2 })}${unit ? " " + unit : ""}`;
  }
  // The line under the post link field: the link as it will be stored ("Link to your Instagram post:
  // instagram.com/p/..."), or why it is not taken, in orange. Empty while the field is.
  function echoPost() {
    const out = $('[data-echo="post_url"]');
    const raw = form.elements.post_url.value.trim();
    const p = raw ? postLink(raw) : null;
    out.classList.toggle("warn", !!raw && !(p && p.url));
    if (!raw) setMsg(out);
    else if (p && p.url) setMsg(out, "post_ok", { site: p.site === "tiktok" ? "TikTok" : "Instagram", link: p.url.replace(/^https:\/\/www\./, "") });
    else setMsg(out, p && p.short ? "e_post_short" : "e_post_link");
  }
  function numVal(name, { int = false, min = 0, max = Infinity } = {}, f = form) {
    const raw = f.elements[name].value;
    if (raw.trim() === "") return { v: null, ok: true };
    const n = parseNum(raw);
    const ok = Number.isFinite(n) && n >= min && n <= max && (!int || Number.isInteger(n));
    return { v: ok ? n : null, ok };
  }
  // The currency of a form: a listed code, "" while it is on Choose…, or the 3 letters typed under Other (null when
  // they are not valid).
  function currencyOf(f) {
    if (f.elements.currency.value !== "other") return f.elements.currency.value;
    const c = f.elements.currency_other.value.trim().toUpperCase();
    return /^[A-Z]{3}$/.test(c) ? c : null;
  }

  // ---------- validation ----------
  function collect() {
    const errors = [];
    const bad = (id, key, vars) => errors.push({ id, key, vars });
    const E = form.elements;
    // The photos of each spot of the mission (one spot without a mission), all before then all after, as on the page.
    const spots = spotsOf(pickedMission()), n = spots.length || 1;
    for (const kind of ["before", "after"]) {
      for (let k = 1; k <= n; k++) {
        const sfx = k === 1 ? "" : "_" + k;
        if (!files[kind + sfx].length) bad("f-" + kind + sfx, n > 1 ? `e_${kind}_spot` : "e_" + kind, n > 1 ? { n: k } : undefined);
      }
    }
    const date = E.cleanup_date.value;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date > localToday(1)) bad("f-date", "e_date");
    // The day of each spot after the first (spot 1's is the cleanup date).
    const spotDates = spots.slice(1).map((s) => E["spot_date_" + s.no].value);
    spotDates.forEach((d, i) => { if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || d > localToday(1)) bad("f-date_" + (i + 2), "e_spot_day", { n: i + 2 }); });
    const place = E.place_name.value.trim();
    if (!place) bad("f-place", "e_place");
    if (!E.country.value) bad("f-country", "e_country");
    const kg = numVal("kg", { max: 100000 }), sacks = numVal("sacks", { int: true, max: 10000 });
    if (!kg.ok) bad("f-kg", "e_number");
    if (!sacks.ok) bad("f-sacks", "e_number");
    if (kg.ok && sacks.ok && !(kg.v > 0) && !(sacks.v > 0)) { bad("f-sacks", "e_amount"); bad("f-kg", ""); }
    const crew = numVal("crew_size", { int: true, min: 1, max: 1000 });
    if (!crew.ok || crew.v === null) bad("f-crew", "e_crew");
    const hours = numVal("hours", { max: 72 });
    if (!hours.ok) bad("f-hours", "e_number");
    const currency = currencyOf(form);
    const costs = !!(E.crew_each_local.value.trim() || E.other_local.value.trim());
    if (currency === null) bad("f-currency-other", "e_currency");
    // A cleanup without costs needs no currency; with any typed, the crew must say which one.
    else if (!currency && costs) bad("f-currency", "e_currency_pick");
    const { each, other, sum } = renderSum("cleanup", true); // the lines under the amounts say why one cannot be read
    if (each.bad) bad("f-each", ""); // marked only: the line under the field says why
    else if (each.v === null && other.v !== null) bad("f-each", "e_each_c");
    if (other.bad) bad("f-other", ""); // the same
    if (costs && sum && sum.total > 1e12) bad("f-each", "e_number");
    if (!E.consent.checked) bad("f-consent", "e_consent");
    // The post link only while its field shows (migration 0007 is in), and only in its stored form.
    const postShown = !$("#f-post").hidden;
    const postRaw = postShown ? E.post_url.value.trim() : "";
    const post = postRaw ? postLink(postRaw) : null;
    if (postRaw && !(post && post.url)) { echoPost(); bad("f-post", ""); } // marked only: the line under the field says why
    const data = {
      cleanup_date: date, place_name: place, country: E.country.value,
      // A mission with several spots has no Use my location now: its spots' points are the mission's.
      lat: geo.cleanup && n === 1 ? Math.round(geo.cleanup.lat * 1e6) / 1e6 : null,
      lng: geo.cleanup && n === 1 ? Math.round(geo.cleanup.lng * 1e6) / 1e6 : null,
      kg: kg.v, sacks: sacks.v, crew_size: crew.v, hours: hours.v,
      currency: currency || null,
      // The two totals as the page added them up (moneySum): the crew's pay inside the cost, both to the cent.
      total_cost_local: costs && sum ? sum.total : null, crew_pay_local: costs && sum ? sum.crew : null,
      disposal: E.disposal.value.trim() || null, notes: E.notes.value.trim() || null,
      private_note: E.private_note.value.trim() || null,
      consent: E.consent.checked,
    };
    // Only sent when a mission is picked, so a cleanup without one looks exactly as before.
    if (E.mission_id.value && E.mission_id.value !== NO_MISSION) data.mission_id = E.mission_id.value;
    // The same for the days of spots 2, 3 and 4: only for a mission with several spots.
    if (n > 1) data.spot_dates = spotDates;
    // The same for the post link: only sent when there is one.
    if (post && post.url) data.post_url = post.url;
    return { errors, data };
  }
  function collectMission() {
    const errors = [];
    const bad = (id, key) => errors.push({ id, key });
    const E = mform.elements;
    if (!files.now.length) bad("f-now", "e_now");
    const place = E.place_name.value.trim();
    if (!place) bad("m-place", "e_place");
    if (!E.country.value) bad("m-country", "e_country");
    const task = E.task.value.trim();
    if (!task) bad("m-task", "e_task");
    const date = E.plan_date.value;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date < localToday() || date > localToday(MISSION_AHEAD_DAYS)) bad("m-date", "e_plan_date");
    // PRICE, in the order of the page: the currency, the people, the pay for each person, the other costs. The crew's
    // pay is part of the sum the page sends, so it can never be more than the price.
    const currency = currencyOf(mform);
    if (currency === null) bad("m-currency-other", "e_currency");
    else if (!currency) bad("m-currency", "e_currency_pick");
    const { people, each, other, sum } = renderSum("mission", true); // the lines under the amounts say why one cannot be read
    if (!people.ok || people.v === null) bad("m-crew", "e_m_crew");
    if (each.bad) bad("m-each", ""); // marked only: the line under the field says why
    else if (each.v === null) bad("m-each", "e_each");
    if (other.bad) bad("m-other", ""); // the same
    if (sum && !(sum.total > 0)) bad("m-each", "e_sum_zero");
    else if (sum && sum.total > 1e12) bad("m-each", "e_number");
    if (!E.consent.checked) bad("m-consent", "e_consent");
    return {
      errors,
      data: {
        place_name: place, country: E.country.value,
        lat: geo.mission ? Math.round(geo.mission.lat * 1e6) / 1e6 : null,
        lng: geo.mission ? Math.round(geo.mission.lng * 1e6) / 1e6 : null,
        task, plan_date: date, crew_size: people.v, currency,
        // The two totals of the sum, both to the cent: price_local the whole price, crew_local the crew's pay in it.
        price_local: sum ? sum.total : null, crew_local: sum ? sum.crew : null,
        private_note: E.private_note.value.trim() || null,
        consent: E.consent.checked,
      },
    };
  }
  // Every field gets its own message right under it; the summary above SEND stays short.
  // A field can name its message box with data-fmsg (used where the box cannot sit inside the label).
  function fmsgFor(el, create) {
    let m = document.querySelector(`[data-fmsg="${el.id}"]`) || $(".fmsg", el);
    if (!m && create) { m = document.createElement("span"); m.className = "msg err fmsg"; el.append(m); }
    return m;
  }
  const PHOTO_FIELDS = ["f-before", "f-after", "f-now"];
  // A photo field of spot 2 or later (f-before_2, f-after_3, ...) is one too.
  const isPhotoField = (id) => PHOTO_FIELDS.includes(id) || /^f-(?:before|after)_[2-9]$/.test(id);
  // The messages under the fields of a form and their red marks go: before new ones, once the form
  // passes the checks (a mark on Number of sacks stays otherwise after kg is fixed), for the next one.
  function clearMarks(f) {
    $$(".invalid", f).forEach((el) => el.classList.remove("invalid"));
    $$(".fmsg", f).forEach((el) => setMsg(el));
  }
  // errors: [{ id: field id, key: text key (empty: only marked), vars: the key's values (optional) }]
  function showErrors(errors, g = "cleanup") {
    const f = UI[g].form;
    // A field behind CHANGE or THE COSTS WERE DIFFERENT opens first: no orange mark is ever out of sight. Opening them
    // draws COSTS again as while typing (syncCosts), so COSTS are drawn once more the way SEND read them: the line under
    // an amount still being typed ("150.", "Rp") says again why it cannot be read, as in POST MISSION, since its field
    // is only marked.
    if (g === "cleanup") { errors.forEach((e) => reveal(e.id)); renderSum("cleanup", true); }
    clearMarks(f);
    for (const e of errors) {
      const el = document.getElementById(e.id);
      if (!el) continue;
      if (isPhotoField(e.id)) { el.querySelector(".drop").classList.add("invalid"); fieldMsg(e.id.slice(2), e.key, e.vars); continue; }
      el.classList.add("invalid");
      if (!e.key) continue;
      setMsg(fmsgFor(el, true), e.key, e.vars);
    }
    setMsg($(UI[g].err), "e_fix");
    const first = document.getElementById(errors[0].id);
    if (first) first.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  // ---------- network ----------
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitOnline = () => navigator.onLine === false
    ? new Promise((r) => { status("waiting_online"); addEventListener("online", r, { once: true }); })
    : Promise.resolve();
  // The status line under SEND of the form being sent. No key empties it.
  function status(key, vars, around) { setMsg($(UI[sending].status), key, vars, around); }
  async function countdown(secs) { for (let s = secs; s > 0; s--) { status(s === 1 ? "retrying_1" : "retrying", { s }); await sleep(1000); } }
  // SEND tapped while picked photos or videos of its form are still being prepared: say so, wait for them, then
  // go on with the same tap. Nobody has to guess that a second tap was needed. Returns false when a file of this
  // form was refused meanwhile (too big, too long, unreadable); the handler then points at that field. Only time
  // the page is on screen counts toward the minute after which a conversion that never ends stops the wait; such
  // a batch is not waited for again, and its busy thumbnail holds the send until it is removed.
  async function filesReady(g) {
    const pending = () => [...working].filter(([job, w]) => w.g === g && !stale.has(job)).map(([job]) => job);
    if (!pending().length) return [];
    // A refusal counts from the start of every pick still being prepared, also when it came before the tap.
    const seen = Math.min(refusedKinds[g].length, ...pending().map((job) => working.get(job).seen));
    let left = 60000;
    waitingFiles = true;
    status("preparing_files");
    try {
      while (pending().length && left > 0) {
        const t0 = performance.now(); // not Date.now(): a clock set back must not stretch the wait
        await Promise.race([Promise.all(pending().map((p) => p.catch(() => {}))), sleep(Math.min(left, 1000))]);
        if (document.visibilityState === "visible") left -= Math.min(performance.now() - t0, 1000);
      }
      pending().forEach((job) => stale.add(job));
    } finally {
      waitingFiles = false;
    }
    status();
    // Only fields whose note is still on screen: a new pick in a field clears its note, and so its refusal.
    return [...new Set(refusedKinds[g].slice(seen))].filter((k) => $(`[data-msg="${k}"]`).textContent.trim());
  }
  // Files were refused while SEND waited for them: mark their fields and go to the first, the way fields to fix
  // are shown, so the crew sees why nothing was sent. Each field keeps its own note. A full field hides its drop
  // zone, so its thumbnails carry the mark then.
  function showRefused(g, kinds) {
    const fields = [...new Set(kinds)].map((k) => document.getElementById(`f-${k}`)).filter(Boolean);
    for (const f of fields) {
      const d = f.querySelector(".drop");
      (d.classList.contains("full") ? f.querySelector(".thumbs") : d).classList.add("invalid");
    }
    setMsg($(UI[g].err), "e_fix");
    fields.sort((a, b) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1));
    if (fields[0]) fields[0].scrollIntoView({ behavior: "smooth", block: "center" });
  }
  const mb = (bytes) => (bytes / 1048576).toLocaleString(lang === "id" ? "id-ID" : "en-US", { maximumFractionDigits: 1, minimumFractionDigits: bytes < 10485760 ? 1 : 0 });

  // A Fatal error will not get better by retrying. msgKey is the local text to show, vars its values (optional),
  // field the id of the form field it belongs to (optional).
  class Fatal extends Error {
    constructor(msgKey, field, vars) { super(msgKey); this.msgKey = msgKey; this.field = field || null; this.vars = vars || null; }
  }

  // Maps a server error to local text. The server's English message is never shown.
  function uploadFailure(status, body) {
    const code = body && body.code;
    if (status === 404) return new Fatal("bad_link");
    if (code === "limit") return new Fatal("e_limit");
    // A 429 without our code is Cloudflare's rate limit rule: a 10 s block, which the countdown outlasts.
    if (code === "interrupted" || status === 408 || status === 429 || status >= 500 || status === 0) return new Error("retry");
    if (status >= 400) return new Fatal("e_upload_fatal");
    return new Error("retry");
  }

  // The server's kind, and stage, for a field: a mission's photos of the spot now are stored as before photos
  // and its video as a video; the cleanup's two video fields as videos with their stage. Other fields go as
  // they are.
  const UPLOAD_AS = { now: ["before"], now_video: ["video"], video_before: ["video", "before"], video_after: ["video", "after"] };
  // at: { i, n } for "Uploading file {i} of {n}" in the status line.
  function putFile(item, at) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      let last = Date.now();
      let settled = false;
      const finish = (fn, v) => { if (settled) return; settled = true; clearInterval(watch); fn(v); };
      // Watchdog: a frozen connection gets aborted and retried instead of hanging for ages.
      const watch = setInterval(() => {
        if (Date.now() - last > STALL_MS) { xhr.abort(); finish(reject, new Error("stalled")); }
      }, 5000);
      // A photo of spot 2 or later (before_2, after_3, ...) goes up as a before or after photo with its spot.
      const [base, spot] = kindSpot(item.kind);
      const [kind, stage] = UPLOAD_AS[base] || [base];
      xhr.open("POST", `/api/upload?k=${encodeURIComponent(token)}&kind=${kind}${stage ? `&stage=${stage}` : ""}${spot > 1 ? `&spot=${spot}` : ""}`);
      xhr.setRequestHeader("Content-Type", item.type);
      // 30 minutes, or more for a big video on slow data (about 200 kbit/s): the watchdog above still stops a
      // frozen connection after a minute.
      xhr.timeout = Math.max(30 * 60 * 1000, Math.round(item.blob.size / 25));
      xhr.upload.onprogress = (e) => {
        last = Date.now();
        if (!e.lengthComputable) return;
        setProgress(item, e.loaded / e.total);
        // A switch to the other language shows the whole line in it at once. The numbers keep the old
        // decimal mark (12.5 or 12,5) until the next progress event writes them again.
        status("up_file_mb", { ...at, a: mb(e.loaded), b: mb(e.total) });
      };
      xhr.onload = () => {
        let body = null;
        try { body = JSON.parse(xhr.responseText); } catch { /* not JSON */ }
        if (xhr.status >= 200 && xhr.status < 300 && body && body.key) return finish(resolve, body.key);
        finish(reject, uploadFailure(xhr.status, body));
      };
      xhr.onerror = () => finish(reject, new Error("network"));
      xhr.ontimeout = () => finish(reject, new Error("timeout"));
      xhr.send(item.blob);
    });
  }

  async function uploadWithRetry(item, at) {
    const waits = [2, 5, 10, 20, 30, 60];
    for (let attempt = 0; ; attempt++) {
      await waitOnline();
      try {
        item.el && item.el.classList.remove("failed");
        status("up_file", at);
        return await putFile(item, at);
      } catch (e) {
        setProgress(item, 0); // the bar never counts a file that did not get up
        if (e instanceof Fatal || attempt >= waits.length) throw e;
        await countdown(waits[attempt]);
      }
    }
  }

  // The server no longer has these files (for example they were older than 2 days). Send them again next time.
  function forgetKeys(items) {
    for (const it of items) { it.key = null; it.el && it.el.classList.remove("done"); setProgress(it, 0); idb.put(it); }
  }

  async function postSubmit(payload) {
    const waits = [2, 5, 10, 20];
    for (let attempt = 0; ; attempt++) {
      await waitOnline();
      let r, body = null;
      try {
        r = await fetch(`/api/submit?k=${encodeURIComponent(token)}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        try { body = await r.json(); } catch { /* not JSON */ }
      } catch (e) {
        // The server may have saved it anyway. Retrying is safe: the server answers a repeat with the same id.
        if (attempt >= waits.length) throw new Error("network");
        await countdown(waits[attempt]);
        continue;
      }
      if (r.ok && body && body.id) return body.id;
      if (r.status === 404) throw new Fatal("bad_link");
      if (body && body.code === "media") {
        forgetKeys(allItems());
        throw new Fatal("e_media");
      }
      // The mission is no longer funded (400) or already has a cleanup (409). The form always becomes the cleanup
      // without a mission, even when the fresh list did not come within 5 seconds (a stalled connection must not
      // hold the form for minutes), so the message and the form agree: TRY AGAIN sends it without a mission.
      if (body && body.code === "mission") {
        const no = noOf(form.elements.mission_id.value);
        await Promise.race([refreshPartner(), sleep(5000)]);
        if (form.elements.mission_id.value !== NO_MISSION) dropMission(no);
        setCleanupFlavor();
        syncEntryMission();
        throw new Fatal(r.status === 409 ? "e_mission_taken_alone" : "e_mission_gone_alone");
      }
      // The server refused the post link. The page checks it with the same block first, so this only happens while the
      // two differ (a page kept from another deploy, which browsers do for up to 4 hours).
      if (body && body.code === "post_link") throw new Fatal(body.field === "post_url" ? "e_post_link" : "e_rejected", "f-post");
      // /api/submit never answers 429 itself: that is Cloudflare's 10 s rate limit block.
      if ((r.status >= 500 || r.status === 429) && attempt < waits.length) {
        await countdown(waits[attempt]);
        continue;
      }
      throw new Fatal(r.status >= 500 || r.status === 429 ? "e_submit" : "e_rejected");
    }
  }

  // Server field name -> [form field id, message key] for POST /api/mission. The page adds the price up itself and checks
  // it first, so only a page kept from before (an old tab) can still get a 400 on price_local or crew_local.
  const MISSION_FIELDS = {
    place_name: ["m-place", "e_place"], country: ["m-country", "e_country"], task: ["m-task", "e_task"],
    plan_date: ["m-date", "e_plan_date"], crew_size: ["m-crew", "e_m_crew"], currency: ["m-currency", "e_currency_pick"],
    price_local: ["m-each", "e_number"], crew_local: ["m-each", "e_number"], consent: ["m-consent", "e_consent"],
  };
  // Retrying is safe: the server answers a repeated client_ref with the mission it already stored, and
  // while that mission is still in review it takes any changes made since.
  async function postMission(payload) {
    const waits = [2, 5, 10, 20];
    for (let attempt = 0; ; attempt++) {
      await waitOnline();
      let r, body = null;
      try {
        r = await fetch(`/api/mission?k=${encodeURIComponent(token)}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        try { body = await r.json(); } catch { /* not JSON */ }
      } catch {
        if (attempt >= waits.length) throw new Error("network");
        await countdown(waits[attempt]);
        continue;
      }
      const code = body && body.code, field = body && body.field;
      if (r.ok && body && typeof body.id === "string" && body.no != null) return body;
      if (r.status === 404) throw new Fatal("bad_link");
      if (code === "media") { forgetKeys(itemsOf("mission")); throw new Fatal("e_media"); }
      if (code === "limit") throw new Fatal("e_m_limit");
      if (code === "unavailable") throw new Fatal("e_m_unavailable");
      // The mission this form already sent can no longer be changed (Sapu Earth acted on it, or it was
      // closed). A new client_ref makes the next send a new mission. Its photos and video belong to the old
      // one (or were deleted with it), so they go up again. The crew page shows where the old one stands.
      if (code === "client_ref") {
        clientRef = newRef();
        forgetKeys(itemsOf("mission"));
        saveMDraft();
        refreshPartner(); // not awaited: the message must not wait on a slow list
        throw new Fatal("e_m_resend");
      }
      if (r.status === 400 && MISSION_FIELDS[field]) {
        let [id, key] = MISSION_FIELDS[field];
        if (field === "currency") [id, key] = mform.elements.currency.value === "other" ? ["m-currency-other", "e_currency"] : ["m-currency", "e_currency_pick"];
        throw new Fatal(key, id);
      }
      // A 429 without our code is Cloudflare's 10 s rate limit block.
      if ((r.status >= 500 || r.status === 429) && attempt < waits.length) {
        await countdown(waits[attempt]);
        continue;
      }
      throw new Fatal(r.status >= 500 || r.status === 429 ? "e_submit" : "e_rejected");
    }
  }

  // ---------- sending: both forms ----------
  // While a send runs, nothing in either form can change: what goes up was read at the tap, so a field typed in, a
  // chip, YES, FOR #12, CHANGE or the mission select would be lost, or say something other than what was sent. Every
  // control of both forms (SEND, the file pickers, the remove buttons and the chips too) and ← CREW PAGE.
  function lockForms(on) {
    for (const u of Object.values(UI)) for (const el of u.form.elements) el.disabled = on;
    $("#back").disabled = on;
    // The logo's picker is in neither form: it is locked with them, and the end of a send never unlocks it while a
    // logo is still on its way.
    $$('input[type="file"]').forEach((i) => (i.disabled = on || (i.id === "logoInput" && !!logoPhase)));
    $(".cl-pick").classList.toggle("off", $("#logoInput").disabled);
  }
  // Uploads the form's files that are not on the server yet, one at a time with retries, then posts
  // the form with post(keys). Returns the answer, or null after showing what went wrong.
  async function runSend(g, post) {
    const u = UI[g];
    const all = itemsOf(g);
    sending = g;
    busy = true;
    lockForms(true);
    $(u.progress).hidden = false;
    $(u.keep).hidden = false;
    try {
      let i = 0;
      for (const item of all) {
        i++;
        if (item.key) continue;
        try {
          // A photo kept in a draft from before cleanJpeg existed can still carry WebKit's Exif (iPhones).
          // One the phone can no longer read (its stored file is gone) gets "remove the file marked in orange".
          if (item.type === "image/jpeg") item.blob = await cleanJpeg(item.blob).catch(() => { throw new Fatal("e_upload_fatal"); });
          item.key = await uploadWithRetry(item, { i, n: all.length });
          item.el && item.el.classList.add("done");
          setProgress(item, 1);
          idb.put(item);
        } catch (e) {
          item.el && item.el.classList.add("failed");
          // A video that will not go up must not hold up the rest: the crew can remove it and send without.
          throw e instanceof Fatal ? e : new Fatal(VIDEO_KINDS.includes(item.kind) ? "e_upload_video" : "e_upload");
        }
      }
      status("sending");
      const res = await post(all.map((x) => x.key));
      setMsg($(u.send), u.sendKey); // sent: the next one starts with SEND again, not TRY AGAIN
      return res;
    } catch (e) {
      status();
      // An empty bar says nothing: it stays only when some files are up already (TRY AGAIN skips them).
      if (!all.some((x) => x.key)) $(u.progress).hidden = true;
      // The message goes under its field when the field is on screen, otherwise above SEND.
      const field = e instanceof Fatal && e.field ? document.getElementById(e.field) : null;
      if (field && g === "cleanup") reveal(e.field);
      if (field && field.offsetParent !== null) showErrors([{ id: e.field, key: e.msgKey, vars: e.vars }], g);
      else if (e instanceof Fatal) setMsg($(u.err), e.msgKey, e.vars);
      else setMsg($(u.err), "e_submit");
      setMsg($(u.send), "try_again");
      return null;
    } finally {
      busy = false;
      lockForms(false);
      $(u.keep).hidden = true;
    }
  }

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    if (busy || waitingFiles) return;
    sending = "cleanup";
    setMsg($("#formErr"));
    // Fields to fix show at once, also while files are still being prepared; after the wait the form is checked
    // again, with its files final.
    let { errors, data } = collect();
    if (errors.length) { showErrors(errors); return; }
    clearMarks(form); // the last tap's marks go now, not after the wait
    const refusedNow = await filesReady("cleanup");
    if (refusedNow.length) { showRefused("cleanup", refusedNow); return; }
    ({ errors, data } = collect());
    if (errors.length) { showErrors(errors); return; }
    clearMarks(form);
    if ($$(".thumb.busy", form).length) { status("preparing"); return; }
    const id = await runSend("cleanup", (keys) => postSubmit({ ...data, media: keys }));
    if (id) done(id, data.mission_id);
  });

  mform.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    if (busy || waitingFiles) return;
    sending = "mission";
    setMsg($("#mformErr"));
    let { errors, data } = collectMission();
    if (errors.length) { showErrors(errors, "mission"); return; }
    clearMarks(mform);
    const refusedNow = await filesReady("mission");
    if (refusedNow.length) { showRefused("mission", refusedNow); return; }
    ({ errors, data } = collectMission());
    if (errors.length) { showErrors(errors, "mission"); return; }
    clearMarks(mform);
    if ($$(".thumb.busy", mform).length) { status("preparing"); return; }
    if (!clientRef) clientRef = newRef();
    saveMDraft(); // the client_ref is on the phone before anything is sent
    const res = await runSend("mission", (keys) => postMission({ ...data, client_ref: clientRef, media: keys }));
    if (res) missionDone(res, data);
  });

  // ---------- after sending: the partner's own page, cleanups and missions, ready to share ----------
  function copyText(url, btn) {
    // COPIED, then the button's own text again, in the language shown by then.
    const show = () => {
      const o = btn.textContent;
      btn.textContent = t("copied");
      setTimeout(() => (btn.textContent = btn.dataset.i18n ? textFor(btn) : o), 1500);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(show, () => prompt("", url));
    else prompt("", url);
  }
  function shareOrCopy(url, btn) {
    if (navigator.share) { navigator.share({ title: "Sapu Earth", url }).catch(() => {}); return; }
    copyText(url, btn);
  }
  function shareButton(url) {
    const btn = document.createElement("button");
    btn.type = "button"; btn.className = "b b-row"; // 44 px: every button on the crew page is easy to hit
    setMsg(btn, "share"); // with its key, COPIED always goes back to SHARE, also after a double tap
    btn.addEventListener("click", () => shareOrCopy(url, btn));
    return btn;
  }
  // A count as this language writes it: 1,234 in English, 1.234 in Indonesian.
  const countText = (n) => n.toLocaleString(lang === "id" ? "id-ID" : "en-US");
  function renderMine() {
    const box = $("#mine");
    const list = partner && Array.isArray(partner.submissions) ? partner.submissions : [];
    box.hidden = !list.length;
    const ul = $("#mineList");
    ul.textContent = "";
    for (const s of list) {
      const li = document.createElement("li");
      const txt = document.createElement("span");
      const b = document.createElement("b");
      b.textContent = s.place_name;
      const small = document.createElement("small");
      // "11 Nov 2026", like the missions above, not 2026-11-11. A published one also says how often visitors thanked it.
      // Each piece keeps its words together and each dot stays with what it follows (no-break spaces), so a narrow phone
      // breaks only after a dot, never inside "Sudah tayang" or "4 ucapan terima kasih", and never starts a line with the
      // dot, as on /crews.
      const keep = (text) => String(text).replace(/ /g, "\u00a0");
      const thanked = Number.isInteger(s.thanks) && s.thanks > 0
        ? "\u00a0· " + keep(t(s.thanks === 1 ? "mine_thanked_1" : "mine_thanked", { n: countText(s.thanks) })) : "";
      small.textContent = `${keep(fmtDay(s.cleanup_date, true) || s.cleanup_date)}\u00a0· ${keep(t("st_" + s.status))}${thanked}`;
      txt.append(b, small);
      li.append(txt);
      if (s.share_url) li.append(shareButton(s.share_url));
      li.dataset.status = s.status;
      ul.append(li);
    }
    // Thanks (docs/upload-flow.md, Thanks): the total above the list, once there is one, and under it what the button is,
    // once the crew has a published cleanup. Neither before migration 0007 (no thanks_total) or with an older server.
    const total = partner && Number.isInteger(partner.thanks_total) ? partner.thanks_total : null;
    const tt = $("#thanksTotal");
    tt.hidden = !(total > 0);
    if (total > 0) setMsg(tt, total === 1 ? "ty_total_1" : "ty_total", { n: countText(total) }); else setMsg(tt);
    const note = $("#thanksNote");
    const published = total !== null && (total > 0 || list.some((s) => s && s.status === "approved"));
    note.hidden = !published;
    if (published) setMsg(note, "ty_note", { btn: ["ID", "MY"].includes(partner.country) ? "SAY TERIMA KASIH" : "SAY THANK YOU" }); else setMsg(note);
  }

  // ---------- missions: the crew's list ----------
  const missionList = () => (missionsOn() ? partner.missions.filter((m) => m && typeof m.id === "string") : []);
  // Funded missions still waiting for their cleanup, soonest planned day first.
  // cleanup_sent: a cleanup for it was sent and waits for review.
  const missionsToClean = () => missionList().filter((m) => m.status === "funded" && !m.cleanup_sent)
    .sort((a, b) => String(a.plan_date || "").localeCompare(String(b.plan_date || "")));
  const pickedMission = () => missionsToClean().find((m) => m.id === form.elements.mission_id.value) || null;
  // A mission's number, while the list has it.
  const noOf = (id) => { const m = missionList().find((x) => x.id === id); return m ? m.no : null; };

  // withSent: false leaves out "Cleanup sent, waiting for review" (a card that already says so in its tag).
  // withAdvance: false leaves out the advance on its way, on the card of a mission whose cleanup was sent: by then the
  // advance has arrived, and the line would read as if it had not.
  function missionStatus(m, withSent = true, withAdvance = true) {
    switch (m.status) {
      case "review": return t("ms_review");
      case "open": return t("ms_open");
      case "done": return t("ms_done");
      case "funded": {
        // Funding is stored on the FUND click and the advance goes out by hand later, so it is never called sent.
        const s = [Number.isFinite(m.funded_eur) ? t("ms_funded", { eur: eur(m.funded_eur) }) : t("ms_funded_plain")];
        if (withAdvance && Number.isFinite(m.advance_eur) && m.advance_eur > 0) s.push(t("ms_advance", { eur: eur(m.advance_eur) }));
        if (m.cleanup_sent && withSent) s.push(t("ms_cleanup_sent"));
        return s.join(". ") + ".";
      }
      case "removed": return t("rm_" + (REMOVED.includes(m.removed_why) ? m.removed_why : "declined"));
      default: return "";
    }
  }
  async function withdrawMission(m, btn) {
    if (!confirm(t("withdraw_q", { no: m.no }))) return;
    const msg = $("#missionMsg");
    setMsg(msg);
    btn.disabled = true;
    try {
      const r = await fetch(`/api/mission/withdraw?k=${encodeURIComponent(token)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: m.id }),
      });
      // 404: not this partner's (any more). The refreshed list shows what is true.
      if (r.status === 409) setMsg(msg, "e_withdraw_late", { no: m.no });
      else if (!r.ok && r.status !== 404) setMsg(msg, "e_withdraw");
    } catch {
      setMsg(msg, "e_withdraw");
    }
    btn.disabled = false;
    await refreshPartner();
  }

  // ---------- the crew page (#home) ----------
  // Unsent work on this phone, for its card on the crew page. Dates, country and currency never count, and neither
  // do a place or crew size that the page filled in, so opening a form and going back leaves no card behind. What
  // was just sent is no work (the form empties when its done screen goes).
  const C_ALWAYS = ["kg", "sacks", "hours", "disposal", "crew_each_local", "other_local", "notes", "post_url", "private_note"];
  const M_ALWAYS = ["place_name", "task", "crew_each_local", "other_local", "private_note"];
  function fieldValues(f, names) { const o = {}; for (const n of names) o[n] = f.elements[n].value; return o; }
  function fieldMarks(f, names) {
    const o = {};
    for (const n of names) if (f.elements[n].dataset.prefilled !== undefined) o[n] = f.elements[n].dataset.prefilled;
    return o;
  }
  function cleanupWork() {
    if (doneShown.cleanup) return false;
    const marked = ["place_name", "crew_size"];
    return hasWork(fieldValues(form, [...C_ALWAYS, ...marked]), fieldMarks(form, marked), C_ALWAYS, marked,
      allItems().length > 0 || reloadFor.cleanup || !!geo.cleanup);
  }
  function missionWork() {
    if (doneShown.mission) return false;
    const marked = ["crew_size"];
    return hasWork(fieldValues(mform, [...M_ALWAYS, ...marked]), fieldMarks(mform, marked), M_ALWAYS, marked,
      itemsOf("mission").length > 0 || reloadFor.mission || !!geo.mission);
  }
  const homeNow = () => homeModel({ missions: missionList(), enabled: missionsOn(),
    cleanup: { work: cleanupWork(), missionId: form.elements.mission_id.value }, mission: { work: missionWork() } });

  // Data shown as it is (a place, a number), never a text key: any key the element had goes.
  function setText(el, text) { setMsg(el); el.textContent = text; }
  function make(tag, cls) { const el = document.createElement(tag); if (cls) el.className = cls; return el; }
  function button(cls, key, vars, onClick) {
    const b = make("button", cls);
    b.type = "button";
    setMsg(b, key, vars);
    b.addEventListener("click", onClick);
    return b;
  }
  function line(key, vars, cls = "cp-line") { const p = make("p", cls); setMsg(p, key, vars); return p; }
  const shareUrlOf = (m) => (typeof m.share_url === "string" && /^https:\/\//.test(m.share_url) ? m.share_url : null);
  function shareMission(m) {
    const b = shareButton(shareUrlOf(m));
    b.setAttribute("aria-label", t("share_m", { no: m.no }));
    return b;
  }
  // The paper with the mission number that one before photo must show, at each spot of a mission with several.
  function paperRow(no, spots) {
    const row = make("div", "paper-hint");
    const paper = make("span", "paper-no");
    paper.setAttribute("aria-hidden", "true");
    setText(paper, "#" + no);
    const txt = make("span");
    setMsg(txt, spots ? "funded_todo_spots" : "funded_todo", { no });
    row.append(paper, txt);
    return row;
  }
  // How far the cleanup on this phone got: photos only, never a number the crew has to measure. With several spots, the
  // photos of all its spots.
  const photosOf = (kind) => sendItems().filter((it) => kindSpot(it.kind)[0] === kind).length;
  const progressLine = () => line("card_progress", { b: photosOf("before"), a: photosOf("after") });

  // "Spot 2: Pantai Legian (Wed 6 Jan)": one spot of a mission with several, on its card.
  const spotLine = (s) => line("card_spot", { n: s.no, place: s.place_name.trim(), day: fmtDay(s.date, false, true) });
  // A mission's card. kind: ready (funded, waiting for its cleanup), review, open or sent (cleanup sent).
  function missionCard(m, kind, model) {
    const card = make("article", "cp-card");
    card.dataset.state = kind;
    const tid = "cpt-" + m.id;
    card.setAttribute("aria-labelledby", tid);
    const title = make("h3", "cp-title");
    title.id = tid;
    setText(title, `#${m.no} ${m.place_name || ""}`.trim());
    const acts = make("div", "cp-acts");
    if (kind === "ready") {
      const today = localToday();
      card.append(line(m.plan_date === today ? "card_today" : "card_ready", null, "cp-kicker"), title);
      const status = make("p", "cp-line");
      setText(status, missionStatus(m, false));
      card.append(status);
      // A mission with several spots: each spot with its place and day, and once its last day has passed, that it has.
      const spots = spotsOf(m), last = spots.map((s) => s.date).sort().pop();
      if (spots.length) {
        for (const s of spots) card.append(spotLine(s));
        if (last < today) card.append(line("card_day_past", { day: fmtDay(last) }));
      } else if (isDay(m.plan_date)) {
        card.append(m.plan_date < today ? line("card_day_past", { day: fmtDay(m.plan_date) })
          : line("card_day", { day: fmtDay(m.plan_date, false, true) }));
      }
      // The price the crew asked, as it adds up, so a mistake shows before the crew cleans (mission #2's one total).
      const asked = askedLine(m);
      if (asked) card.append(asked);
      card.append(paperRow(m.no, spots.length > 0));
      const begun = cleanupWork() && form.elements.mission_id.value === m.id;
      if (begun) card.append(progressLine());
      const next = !!model.orange && model.orange.kind === "ready" && model.orange.id === m.id;
      acts.append(button(next ? "b b-go" : "b", begun ? "card_continue" : "card_send", { no: m.no }, () => openCleanup(m.id)));
    } else {
      const tag = make("p", "cp-tag");
      setMsg(tag, kind === "review" ? "ms_review" : kind === "open" ? "ms_open" : "ms_cleanup_sent");
      card.append(title, tag);
      if (kind === "sent") {
        const status = make("p", "cp-line");
        setText(status, missionStatus(m, false, false));
        card.append(status);
      } else if (spotsOf(m).length) {
        for (const s of spotsOf(m)) card.append(spotLine(s));
      } else if (isDay(m.plan_date)) card.append(line("card_planned", { day: fmtDay(m.plan_date, true, true) }));
      // In review and open: the price the crew asked, so it can say so before Sapu Earth funds it.
      if (kind !== "sent") { const asked = askedLine(m); if (asked) card.append(asked); }
      // After the cleanup: "the rest of the money" only when an advance went out first.
      const sentKey = Number(m.advance_eur) > 0 ? "st_sent_body" : "st_sent_body_all";
      card.append(line(kind === "review" ? "st_review_body" : kind === "open" ? "st_open_body" : sentKey));
    }
    if (shareUrlOf(m)) acts.append(shareMission(m));
    if (kind === "review" || kind === "open") {
      const w = button("b b-ghost b-row", "withdraw", null, () => withdrawMission(m, w));
      w.setAttribute("aria-label", t("withdraw_m", { no: m.no }));
      acts.append(w);
    }
    if (acts.childElementCount) card.append(acts);
    return card;
  }
  // Unsent work that is not on a mission's card: a cleanup without a mission (or one that lost its mission), or a
  // mission not posted yet. CONTINUE opens it, DELETE removes it from this phone.
  function draftCard(g, model) {
    const card = make("article", "cp-card cp-draft");
    card.dataset.state = g === "mission" ? "mission-draft" : "cleanup-draft";
    const head = make("h3", "cp-kicker");
    head.id = "cpk-" + g;
    setMsg(head, g === "mission" ? "draft_m_h" : "draft_c_h");
    card.append(head);
    const place = (g === "mission" ? mform : form).elements.place_name.value.trim();
    let label = head.id;
    if (place) {
      const title = make("p", "cp-title");
      title.id = "cpt-" + g;
      setText(title, place);
      card.append(title);
      label += " " + title.id;
    }
    card.setAttribute("aria-labelledby", label);
    if (g === "cleanup") {
      if (goneNo !== null) card.append(line("draft_gone", { no: goneNo }, "cp-line cp-gone"));
      card.append(line("draft_photos", { b: photosOf("before"), a: photosOf("after") })); // draft_body says the rest
    }
    card.append(line("draft_body"));
    const acts = make("div", "cp-acts");
    const next = !!model.orange && model.orange.kind === (g === "mission" ? "mission" : "plain");
    acts.append(button(next ? "b b-go" : "b", "draft_go", null, () => (g === "mission" ? go("mission") : go("cleanup", { mission: NO_MISSION }))));
    acts.append(button("b b-ghost b-row", "draft_del", null, () => {
      if (!confirm(t("draft_del_q"))) return;
      if (g === "mission") discardMission(); else discardCleanup();
      renderHome();
    }));
    card.append(acts);
    return card;
  }
  function pastRow(m, dim) {
    const li = make("li");
    const txt = make("span");
    const b = make("b");
    setText(b, `#${m.no} ${m.place_name || ""}`.trim());
    const small = make("small");
    setText(small, [fmtDay(m.plan_date, true), missionStatus(m)].filter(Boolean).join(" · "));
    txt.append(b, small);
    li.append(txt);
    if (dim) li.className = "cp-dim";
    else {
      li.dataset.status = m.status; // done: green, as in YOUR CLEANUPS
      if (shareUrlOf(m)) li.append(shareMission(m)); // /m/<no> of a done mission opens its receipt
    }
    return li;
  }
  // The crew page, top to bottom: the first step (no mission yet), the cards (ready, unsent work, waiting, sent),
  // POST A MISSION, the cleanup without a mission, PAST MISSIONS, YOUR CLEANUPS and YOUR PUBLIC PAGE. One orange
  // button: the next step (homeModel). The details of removed missions keep their open state.
  function renderHome() {
    if (!partner) return;
    const on = missionsOn();
    const model = homeNow();
    const post = !!model.orange && model.orange.kind === "post";
    $("#intro").hidden = !model.intro;
    $("#intro [data-go]").className = post ? "b b-go" : "b";
    const cards = $("#cards");
    cards.textContent = "";
    for (const m of model.ready) cards.append(missionCard(m, "ready", model));
    if (model.plainDraft) cards.append(draftCard("cleanup", model));
    if (model.missionDraft) cards.append(draftCard("mission", model));
    for (const m of model.waiting) cards.append(missionCard(m, m.status, model));
    for (const m of model.sent) cards.append(missionCard(m, "sent", model));
    $("#cardsH").hidden = !cards.childElementCount;
    // POST A MISSION: in the intro while there is no mission yet, on the card while one is not posted yet, and at
    // the limit (the server's count) only the line that says why.
    $("#postBox").hidden = !on || model.intro || model.missionDraft;
    $("#postMission").className = post ? "b b-go" : "b";
    $("#postMission").hidden = model.limit;
    $("#postSub").hidden = model.limit;
    $("#limitNote").hidden = !model.limit;
    // A cleanup without a mission stays possible, but as a plain link. Before migration 0004 it is the only thing to do.
    const plain = $("#plainGo");
    $("#plainBox").hidden = model.plainDraft;
    plain.className = on ? "text-btn" : "b b-go";
    setMsg(plain, on ? "plain_btn" : "mode_cleanup");
    $("#plainSub").hidden = !on;
    $("#past").hidden = !model.past.length && !model.removed.length;
    const past = $("#pastList");
    past.textContent = "";
    model.past.forEach((m) => past.append(pastRow(m, false)));
    past.hidden = !model.past.length;
    const removed = $("#removedList");
    removed.textContent = "";
    model.removed.forEach((m) => removed.append(pastRow(m, true)));
    $("#removedBox").hidden = !model.removed.length;
    setMsg($("#removedSum"), "past_removed", { n: model.removed.length });
    // The crew's public page, once the crew is in the list of crews (listed, the rule of /crews: every active crew, under
    // JUST JOINED until it has a mission or a cleanup on sapu.earth, so it is true from the first day). An older server
    // sends no listed: then once it has a cleanup on it.
    const page = partner.page_url;
    const listed = typeof partner.listed === "boolean" ? partner.listed
      : Array.isArray(partner.submissions) && partner.submissions.some((x) => x && x.status === "approved");
    const live = !!page && listed;
    $("#pubPage").hidden = !live;
    $("#crewsHint").hidden = partner.listed !== true;
    // The link to the crew's own post, once the server keeps post links (migration 0007). An older server sends no
    // post_links_enabled, and the field stays hidden.
    $("#f-post").hidden = partner.post_links_enabled !== true;
    if (live) { $("#pubLink").href = page; setText($("#pubLink"), page.replace(/^https:\/\//, "")); }
    renderMine();
    renderLogo();
  }
  $("#sharePub").addEventListener("click", (ev) => { if (partner && partner.page_url) shareOrCopy(partner.page_url, ev.currentTarget); });

  // ---------- YOUR LOGO (docs/upload-flow.md, Crew logos) ----------
  // The crew's logo, between YOUR CLEANUPS and YOUR PUBLIC PAGE: from partner.logo (GET /api/partner, or the answer
  // of POST /api/logo) and the logo on its way (logoPhase). Hidden while logos are off (logo.enabled not true: before
  // migration 0006, or an older server). The tile shows the logo on its way, else the waiting one (dashed), else the
  // live one, else the crew's letters; the line says where it stands, written only through setMsg.
  function renderLogo() {
    const box = $("#logoBox");
    const logo = partner && partner.logo;
    box.hidden = !(logo && logo.enabled === true);
    if (box.hidden) return;
    const live = typeof logo.live === "string" && LOGO_SRC.test(logo.live) ? logo.live : null;
    const review = typeof logo.review === "string" && LOGO_SRC.test(logo.review) ? logo.review : null;
    const declined = logo.declined === true;
    const src = logoPhase === "sending" && logoPreview ? logoPreview : review || live;
    $("#logoTile").dataset.state = logoPhase || (review ? "review" : live ? "live" : "none");
    const img = $("#logoImg"), mono = $("#logoMono");
    if (src) {
      // Only a new picture loads: the waiting logo's link gets a new signature with every list.
      if ((img.getAttribute("src") || "").split("?")[0] !== src.split("?")[0]) img.src = src;
      img.hidden = false;
      mono.hidden = true;
    } else {
      img.hidden = true;
      img.removeAttribute("src");
      mono.hidden = false;
      mono.textContent = typeof logo.initials === "string" ? logo.initials : "";
    }
    const key = logoPhase === "preparing" ? "logo_preparing" : logoPhase === "sending" ? "logo_sending"
      : review ? (live ? "logo_review_live" : "logo_review")
      : live ? (declined ? "logo_declined_live" : "logo_live")
      : declined ? "logo_declined" : "logo_none";
    setMsg($("#logoLine"), key);
    setMsg($("#logoBtn"), live || review ? "logo_change" : "logo_add");
    const input = $("#logoInput");
    input.disabled = !!logoPhase || busy;
    $(".cl-pick").classList.toggle("off", input.disabled); // a label cannot be [disabled]
  }
  // POST /api/logo with the square: up to 4 tries, after 2, 5 and 10 s, so a 10 s block of the rate limiting rule (a
  // 429 without our code) is outlasted, as on /apply/. Retried also without an answer, after the 60 s watchdog of the
  // uploads, and on a 5xx other than the migration answer. Returns the 201 body; anything else is a Fatal with the key
  // to show ("migration": logos are off). Nothing is kept on the phone, and no try runs once the page is closed.
  async function postLogo(blob) {
    const waits = [2, 5, 10];
    for (let attempt = 0; ; attempt++) {
      let r = null, body = null;
      const ac = typeof AbortController === "function" ? new AbortController() : null;
      const timer = ac ? setTimeout(() => ac.abort(), STALL_MS) : null;
      try {
        r = await fetch(`/api/logo?k=${encodeURIComponent(token)}`, {
          method: "POST", headers: { "Content-Type": "image/jpeg" }, body: blob, signal: ac ? ac.signal : undefined,
        });
        try { body = await r.json(); } catch { /* not JSON */ }
      } catch {
        r = null; // offline, timed out, or the answer was cut off
      } finally {
        if (timer) clearTimeout(timer);
      }
      const code = body && body.code;
      if (r && r.status === 201) return body;
      if (r && r.status === 503 && code === "migration") throw new Fatal("migration");
      if (r && r.status === 429 && code === "limit") throw new Fatal("e_logo_limit");
      if (r && r.status === 404) throw new Fatal("bad_link");
      if (r && [400, 411, 413, 415].includes(r.status)) throw new Fatal("e_logo_refused");
      if ((r && r.status < 500 && r.status !== 429) || attempt >= waits.length) throw new Fatal("e_logo_send");
      await sleep(waits[attempt] * 1000);
    }
  }
  // One pick: the square is made on the phone, then sent. The picker stays locked until it is through, and the
  // answer (the crew's new logo state) redraws the panel. A refusal or a failed send leaves the panel as it was,
  // with the reason under it; a new pick clears it.
  $("#logoInput").addEventListener("change", async () => {
    const input = $("#logoInput");
    const file = input.files && input.files[0];
    input.value = "";
    if (!file || logoPhase || busy || !partner) return;
    setMsg($("#logoMsg"));
    logoPhase = "preparing";
    renderLogo();
    try {
      if (file.size > LIMIT.photoInputBytes) throw new Fatal("e_logo_read");
      let blob;
      try {
        blob = await toLogoJpeg(file);
      } catch (e) {
        throw new Fatal(e && e.message === "small" ? "e_logo_small" : "e_logo_read");
      }
      logoPreview = URL.createObjectURL(blob);
      logoPhase = "sending";
      renderLogo();
      const body = await postLogo(blob);
      if (body && body.logo && typeof body.logo === "object") {
        logoLast = body.logo;
        logoEpoch++;
        partner.logo = body.logo;
      } else {
        refreshPartner();
      }
    } catch (e) {
      // Logos are off on the server (before migration 0006): the panel goes. Anything else says why under it.
      if (e instanceof Fatal && e.msgKey === "migration") { if (partner.logo) partner.logo.enabled = false; }
      else setMsg($("#logoMsg"), e instanceof Fatal ? e.msgKey : "e_logo_send");
    } finally {
      logoPhase = null;
      if (logoPreview) { URL.revokeObjectURL(logoPreview); logoPreview = null; }
      renderLogo();
    }
  });

  // ---------- opening a cleanup, switching, deleting ----------
  // A card's SEND A CLEANUP FOR #12, or the cleanup without a mission. A phone keeps one cleanup: before photos that
  // show one mission's paper never move to another mission by a card, so the crew is asked and they are removed. That
  // holds for work that lost its mission too (goneNo). Work without a mission can go into a mission (applyMissionPick
  // only fills what is empty or the default). openAsk decides.
  function openCleanup(target) {
    if (sendLocked()) return;
    const held = entryMission();
    const ask = openAsk({ work: cleanupWork(), held, lost: held === NO_MISSION ? goneNo : null, target });
    if (ask === "switch") {
      const from = held !== NO_MISSION ? noOf(held) : goneNo;
      if (!confirm(target === NO_MISSION ? t("switch_plain_q", { from }) : t("switch_q", { from, to: noOf(target) }))) return;
      discardCleanup();
    } else if (ask === "move" && !confirm(t("move_q", { to: noOf(target) }))) return;
    go("cleanup", { mission: target });
  }
  // The cleanup form takes the mission it is opened for while that mission waits for its cleanup, else none. Only
  // work is kept on the phone: a form opened and left without anything added leaves no draft (its history entry knows
  // the mission), so it never turns into unsent work once that mission is sent from another phone or closed.
  function pickForCleanup(mission) {
    const sel = form.elements.mission_id;
    const want = missionsToClean().some((m) => m.id === mission) ? mission : NO_MISSION;
    if (sel.value !== want) { sel.value = want; applyMissionPick(); }
    if (want !== NO_MISSION || !cleanupWork()) goneNo = null; // a cleanup that lost its mission says so while it holds work
    changeOpen = false;
    setCleanupFlavor();
    if (cleanupWork()) saveDraft(); else store.del(draftKey());
  }
  // The cleanup's mission can no longer take it (sent, closed or cancelled meanwhile; found at the start, by a refresh
  // or by a refused send): the form becomes the cleanup without a mission, never quietly another mission's. Work on it
  // keeps the place, country and crew size the mission filled in, now as the crew's own to check, and remembers which
  // mission it lost (goneNo, kept with the draft), so no card or question moves its photos into another mission. A form
  // with nothing added just empties (its country back to the crew's own) and leaves nothing on the phone. Returns
  // whether there was work.
  function dropMission(no) {
    const work = cleanupWork(); // before the marks go: what the mission filled in is not work
    form.elements.mission_id.value = NO_MISSION;
    goneNo = work && Number.isInteger(no) ? no : null;
    applyMissionPick(work);
    if (work) saveDraft(); else store.del(draftKey());
    return work;
  }
  // DELETE, or a switch to another mission: nothing of it stays, on the page or the phone. A pick of files still
  // being prepared for it adds nothing afterwards (sends).
  function discardCleanup() { sends.cleanup++; resetCleanup(); store.del(draftKey()); }
  function discardMission() { sends.mission++; resetMission(); store.del(mdraftKey()); }
  // The cleanup's history entry follows its mission, so a reload or back and forward show the same form.
  function syncEntryMission() {
    if (view !== "cleanup" || !lastState || lastState.done) return;
    const mission = entryMission();
    if (lastState.mission !== mission) setState({ ...lastState, mission }, false);
  }

  // ---------- the cleanup form: for a mission, or without one ----------
  // For a mission: its summary with CHANGE (the select and WHERE behind it), the paper above the before photos, the
  // crew size it filled in with where it came from, the date chip, and the costs folded behind the price the
  // receipt already shows. Without one: WHERE first, the question about a funded mission still waiting for its
  // cleanup (guardMission: not when the cleanup lost its mission), a note when it did, and the costs open as before.
  const BEHIND_CHANGE = ["f-place", "f-country", "f-mission"];
  const BEHIND_COSTS = ["f-currency", "f-currency-other", "f-each", "f-other"];
  function setCleanupFlavor() {
    if (!partner) return;
    const m = pickedMission();
    const E = form.elements;
    $("#missionSum").hidden = !m;
    $("#sumChange").hidden = !m || changeOpen;
    $("#sumChange").setAttribute("aria-expanded", String(changeOpen));
    $("#f-mission").hidden = !m || !changeOpen;
    $("#wherePanel").hidden = !!m && !changeOpen;
    const near = guardMission({ picked: !!m, lost: goneNo, toClean: missionsToClean(), today: localToday() });
    $("#guard").hidden = !near;
    if (near) {
      setMsg($("#guardQ"), "guard_q", { no: near.no, place: near.place_name || "" });
      setMsg($("#guardYes"), "guard_yes", { no: near.no });
      $("#guardYes").dataset.mission = near.id;
    }
    const gone = !m && goneNo !== null;
    if (gone) setMsg($("#goneNote"), "draft_gone", { no: goneNo }); else setMsg($("#goneNote"));
    $("#missionBox").hidden = !m && !near && !gone;
    if (m) {
      setText($("#sumTitle"), `#${m.no} ${E.place_name.value.trim() || m.place_name || ""}`.trim());
      const opt = E.country.options[E.country.selectedIndex];
      const country = E.country.value && opt ? opt.text : "";
      const pre = { pre: country ? country + " · " : "" };
      const days = spotsOf(m).map((s) => s.date).sort(), from = days[0], to = days[days.length - 1];
      if (days.length && from === to) setMsg($("#sumFacts"), "sum_planned_spots_1", { n: days.length, day: fmtDay(from, false, true) }, pre);
      else if (days.length) setMsg($("#sumFacts"), "sum_planned_spots", { n: days.length, from: fmtDay(from, false, true), to: fmtDay(to, false, true) }, pre);
      else if (isDay(m.plan_date)) setMsg($("#sumFacts"), "sum_planned", { day: fmtDay(m.plan_date, false, true) }, pre);
      else setText($("#sumFacts"), country);
    }
    renderSpots();
    renderPaperHint();
    if (m) setMsg($("#geoHint"), "geo_hint_m", { no: m.no }); else setMsg($("#geoHint"), "geo_hint");
    syncCrewSrc();
    syncPlanDay();
    syncCosts();
    renderTitle();
  }
  // A mission with several spots (docs/missions.md, Spots): the photo fields and the day of each of its spots show, each
  // named by its spot and place, the hints say "at each spot", and Use my location now goes, since the spots' points are
  // the mission's. One spot (or no mission): the form as for every cleanup before. Runs with every flavor change and
  // language switch (setCleanupFlavor).
  function renderSpots() {
    const spots = spotsOf(pickedMission()), n = spots.length || 1;
    for (let k = 2; k <= SPOT_MAX; k++) for (const id of [`f-before_${k}`, `f-after_${k}`, `f-date_${k}`]) document.getElementById(id).hidden = k > n;
    const label = (id) => $(`#${id} b`), pick = (id) => $(`#${id} input[type="file"]`);
    if (n > 1) {
      for (const s of spots) {
        const sfx = s.no === 1 ? "" : "_" + s.no, v = { n: s.no, place: s.place_name.trim() };
        setMsg(label("f-before" + sfx), "spot_field", v);
        setMsg(label("f-after" + sfx), "spot_field", v);
        setMsg(label("f-date" + sfx), "spot_day", v);
        pick("f-before" + sfx).setAttribute("aria-label", t("spot_before_aria", v));
        pick("f-after" + sfx).setAttribute("aria-label", t("spot_after_aria", v));
      }
      setMsg($("#beforePanel > .hint"), "before_hint_spots", { n });
      setMsg($("#afterPanel > .hint"), "after_hint_spots");
    } else {
      setMsg(label("f-before"), "before");
      setMsg(label("f-after"), "after");
      setMsg(label("f-date"), "date");
      pick("f-before").setAttribute("aria-label", t("before"));
      pick("f-after").setAttribute("aria-label", t("after"));
      setMsg($("#beforePanel > .hint"), "before_hint");
      setMsg($("#afterPanel > .hint"), "after_hint");
    }
    $("#f-geo").hidden = n > 1;
  }
  function renderPaperHint() {
    const m = pickedMission();
    $("#paperHint").hidden = !m;
    if (!m) return;
    setText($("#paperNo"), "#" + m.no);
    setMsg($("#paperText"), spotsOf(m).length ? "paper_hint_spots" : "paper_hint", { no: m.no });
  }
  // "From mission #12" under a crew size the mission filled in, while it still holds that number.
  function syncCrewSrc() {
    const m = pickedMission(), el = form.elements.crew_size;
    const on = !!m && el.dataset.prefilled !== undefined && el.value.trim() === el.dataset.prefilled;
    $("#crewSrc").hidden = !on;
    if (on) setMsg($("#crewSrc"), "crew_src", { no: m.no }); else setMsg($("#crewSrc"));
    $("#f-crew").parentElement.classList.toggle("cp-stack", on); // the line needs the width
  }
  // "As planned: Sun 15 Nov", only while the planned day was 1 to 14 days ago and the date still says today (a
  // cleanup sent the day after). The date never changes by itself.
  function syncPlanDay() {
    const m = pickedMission();
    const ago = m ? daysBetween(m.plan_date, localToday()) : null;
    const on = ago !== null && ago >= 1 && ago <= 14 && form.elements.cleanup_date.value === localToday();
    $("#planDayRow").hidden = !on;
    if (on) setMsg($("#planDay"), "plan_day_btn", { day: fmtDay(m.plan_date, false, true) }); else setMsg($("#planDay"));
  }
  $("#planDay").addEventListener("click", () => {
    const m = pickedMission();
    if (!m || !isDay(m.plan_date)) return;
    fillField(form.elements.cleanup_date, m.plan_date);
    form.elements.cleanup_date.focus();
  });
  // A cleanup for a mission folds its costs: the receipt already shows the price the crew asked (ASKED, CREW PAY,
  // OTHER COSTS), and the same price typed again would show as costs the crew claims it spent (SPENT, CREW PAY, OTHER
  // COSTS). A typed cost, a tap on THE COSTS WERE DIFFERENT or a field to fix opens them, and they stay open. The cost
  // line says the price as it adds up, and when fewer or more people worked than the mission planned, that the costs
  // are the place to say the pay changed.
  function syncCosts() {
    const E = form.elements;
    if (E.crew_each_local.value.trim() || E.other_local.value.trim()) costsOpen = true;
    const m = pickedMission();
    $("#costLine").hidden = !m;
    $("#costToggle").hidden = !m || costsOpen;
    $("#costToggle").setAttribute("aria-expanded", String(costsOpen));
    $("#costFields").hidden = !!m && !costsOpen;
    renderSum("cleanup"); // also after a mission filled in or emptied the crew size, which fires no input
    if (!m) return;
    if (Number.isFinite(m.funded_eur)) setMsg($("#costPaid"), "cost_paid", { eur: eur(m.funded_eur), no: m.no }); else setMsg($("#costPaid"));
    const plan = planOf(m), asked = plan ? priceLine(plan.currency, plan.price_local, plan.crew_local, m.crew_size) : "";
    if (asked) setMsg($("#costReceipt"), "cost_receipt_plan", { line: asked }); else setMsg($("#costReceipt"), "cost_receipt");
    const now = numVal("crew_size", { int: true, min: 1, max: 1000 }).v;
    if (asked && now !== null && now !== m.crew_size) setMsg($("#costCrew"), "cost_crew", { plan: numText(m.crew_size), now: numText(now) });
    else setMsg($("#costCrew"));
  }
  // A field to fix behind CHANGE or the costs opens them first.
  function reveal(id) {
    if (BEHIND_CHANGE.includes(id)) changeOpen = true;
    if (BEHIND_COSTS.includes(id)) costsOpen = true;
    setCleanupFlavor();
  }
  $("#sumChange").addEventListener("click", () => {
    changeOpen = true;
    setCleanupFlavor();
    form.elements.mission_id.focus();
  });
  $("#costToggle").addEventListener("click", () => {
    costsOpen = true;
    syncCosts();
    form.elements.crew_each_local.focus();
  });
  // YES, FOR #12: everything typed and picked goes into that mission's cleanup (only empty or default fields take
  // the mission's details), as if the crew had opened it from the card. Never during a send (lockForms).
  $("#guardYes").addEventListener("click", () => {
    if (sendLocked()) return;
    pickForCleanup($("#guardYes").dataset.mission);
    syncEntryMission();
    focusTitle();
  });

  // The select under CHANGE: "No mission" and the funded missions still waiting for their cleanup. The page never
  // picks one by itself: a card's button, YES, FOR #12 or the crew under CHANGE does. A mission that can no longer
  // take this cleanup (sent, closed or cancelled meanwhile) falls back to "No mission", never quietly to another
  // one (dropMission: with work the form says which mission it lost; not while THANK YOU shows, that one was just
  // sent). Returns the id of a mission it dropped, else null.
  function fillMissionPicker() {
    const sel = form.elements.mission_id;
    const list = missionsToClean();
    const cur = sel.value;
    sel.textContent = "";
    sel.append(new Option(t("no_mission"), NO_MISSION));
    for (const m of list) {
      const label = [`#${m.no} ${m.place_name || ""}`.trim(), fmtDay(m.plan_date)].filter(Boolean).join(", ");
      sel.append(new Option(label, m.id));
    }
    if (cur === NO_MISSION || list.some((m) => m.id === cur)) { sel.value = cur; return null; }
    if (!cur) { sel.value = ""; return null; } // not chosen yet: the next cleanup opened from the crew page sets it
    dropMission(noOf(cur));
    return cur;
  }
  // Picking a mission fills in its place, country and crew size, never a location (/api/partner sends none).
  // A value the crew typed themselves stays; one that is empty, the default, or filled in from another
  // mission is replaced.
  function prefillFromMission() {
    const m = pickedMission();
    if (!m) return;
    const E = form.elements;
    const fill = (el, v, dflt = "") => {
      if (v === undefined || v === null || v === "") return;
      v = String(v);
      if (el.tagName === "SELECT" && ![...el.options].some((o) => o.value === v)) return;
      const cur = el.value.trim();
      if (cur !== "" && cur !== dflt && cur !== el.dataset.prefilled) return;
      el.value = v;
      el.dataset.prefilled = v;
      const box = el.closest(".field");
      if (box) { box.classList.remove("invalid"); setMsg(fmsgFor(box, false)); }
    };
    fill(E.place_name, m.place_name);
    fill(E.country, m.country, (partner && partner.country) || "");
    fill(E.crew_size, m.crew_size);
    // The planned day of each spot after the first, once it has come: the crew sends the cleanup after its last spot,
    // and changes a day that moved. A day still to come stays empty, for the crew to write.
    for (const s of spotsOf(m).slice(1)) if (s.date <= localToday()) fill(E["spot_date_" + s.no], s.date);
  }
  // Empties what a mission filled in and the crew did not change since (the country goes back to the crew's own). Runs
  // on every change of the cleanup's mission, on its reset and at start. Except when the page dropped the mission of
  // work started for it (dropped, dropMission): the cleanup was most likely done there, so the place, country and crew
  // size stay, now as the crew's own, and the note asks the crew to check them.
  function clearMissionPrefill(dropped = false) {
    const E = form.elements;
    for (const el of [E.place_name, E.country, E.crew_size, ...SPOT_DAYS.map((f) => E[f])]) {
      if (!dropped && el.dataset.prefilled !== undefined && el.value.trim() === el.dataset.prefilled) {
        el.value = el === E.country ? (partner && partner.country) || "" : "";
      }
      delete el.dataset.prefilled;
    }
  }
  // Every change of the cleanup's mission, by the crew or by the page: first empty what a mission filled in and the
  // crew did not change, then the mission (if any) fills in what is empty. What the crew typed stays.
  function applyMissionPick(dropped = false) { clearMissionPrefill(dropped); prefillFromMission(); }
  form.elements.mission_id.addEventListener("change", () => {
    form.elements.mission_id.closest(".field").classList.remove("invalid");
    goneNo = null;
    applyMissionPick();
    setCleanupFlavor();
    syncEntryMission();
    // "No mission" turns the form into the cleanup without a mission, which has no select: the H1 says so.
    if (!pickedMission()) focusTitle();
  });

  // ---------- POST A MISSION: what the crew wrote before ----------
  // The form starts on the crew size of the crew's newest mission, with where it came from, when it is empty. The price
  // adds up with it at once: the value is set here, which fires no input.
  function prefillMissionCrew() {
    const el = mform.elements.crew_size;
    if (el.value.trim() === "") {
      const m = lastCrewMission(missionList());
      if (m) { el.value = String(m.crew_size); el.dataset.prefilled = el.value; saveMDraft(); }
    }
    syncMCrewSrc();
    renderSum("mission");
  }
  // The crew size has the whole width under PRICE, so the line under it needs no room of its own.
  function syncMCrewSrc() {
    const el = mform.elements.crew_size, mark = el.dataset.prefilled;
    const src = mark !== undefined && el.value.trim() === mark ? missionList().find((x) => String(x.crew_size) === mark) || null : null;
    $("#mCrewSrc").hidden = !src;
    if (src) setMsg($("#mCrewSrc"), "crew_src_last", { no: src.no }); else setMsg($("#mCrewSrc"));
  }

  // ---------- chips: one tap writes what the crew used before ----------
  // A chip only writes into its field when tapped, and the field stays editable. Never on photos, a video, a
  // location, consent or a number the crew measures. The money fields never have a grey example: an example amount
  // would set the wage for the crew, or pass for one already filled in.
  function fillField(el, v) { el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); }
  function renderChips() {
    const subs = partner && Array.isArray(partner.submissions) ? partner.submissions : [];
    for (const [box, f] of [[$("#placeChipsC"), form], [$("#placeChipsM"), mform]]) {
      const input = f.elements.place_name;
      const names = partner ? placeChips(missionList(), subs, input.value) : [];
      $$(".chip", box).forEach((b) => b.remove());
      for (const name of names) {
        const b = make("button", "chip");
        b.type = "button";
        setText(b, name);
        b.addEventListener("click", () => { fillField(input, name); input.focus(); });
        box.append(b);
      }
      box.hidden = !names.length;
    }
    // The task and price of the newest funded or done mission at the place written above, else of the newest funded
    // or done one: only what Sapu Earth funded comes back. The task chip shows how that plan starts. While the task chip
    // shows, the empty task has no grey example, which could pass for a plan already filled in. The price chip offers
    // that mission's pay for each person and other costs (payOf), only while its crew's pay splits evenly, never its
    // crew size: the people are counted for each mission.
    const last = partner ? lastPlanMission(missionList(), mform.elements.place_name.value) : null;
    const plan = planOf(last);
    const E = mform.elements;
    const task = !!plan && !E.task.value.trim();
    $("#taskChipRow").hidden = !task;
    $("#taskChip").dataset.mission = task ? last.id : "";
    if (task) setMsg($("#taskChip"), "chip_task", { no: last.no, task: excerpt(plan.task) }); else setMsg($("#taskChip"));
    E.task.placeholder = task ? "" : t(E.task.dataset.ph);
    const pay = payOf(last);
    const price = !!pay && !E.crew_each_local.value.trim() && !E.other_local.value.trim();
    $("#priceChipRow").hidden = !price;
    $("#priceChip").dataset.mission = price ? last.id : "";
    if (price) setMsg($("#priceChip"), pay.other > 0 ? "chip_price" : "chip_price_0", { no: last.no, each: amt(pay.currency, pay.each), other: amt(pay.currency, pay.other) });
    else setMsg($("#priceChip"));
  }
  // The plan of the mission a chip shows (data-mission), while it is still whole.
  const chipPlan = (chip) => planOf(missionList().find((m) => m.id === chip.dataset.mission) || null);
  // A number as the page writes it, "1.500.000" in Indonesian and "1,500,000" in English, so a chip's amounts read like
  // typed ones and the lines under PRICE and COSTS read like the fields. parseNum reads both.
  const numText = (n) => Number(n).toLocaleString(lang === "id" ? "id-ID" : "en-US", { maximumFractionDigits: 2 });
  // ---------- the price as the page adds it up: POST A MISSION's PRICE and a cleanup's COSTS ----------
  const SUM_LIVE = ["crew_size", "crew_each_local", "other_local", "currency", "currency_other"];
  const SUM_UI = {
    mission: { line: "#mEachLine", oline: "#mOtherLine", box: "#mSum", total: "#mSumTotal", parts: "#mSumParts", people: "sum_people_m" },
    cleanup: { line: "#fEachLine", oline: "#fOtherLine", box: "#fSum", total: "#fSumTotal", parts: "#fSumParts", people: "sum_people_c" },
  };
  const PAY_MAX = 1e9, OTHER_MAX = 1e12; // 1000 people × PAY_MAX stays within the server's 1e12
  // "IDR 1.500.000" ("IDR 1,500,000" in English), the code joined by a no-break space; the number alone on Choose….
  const amt = (cur, v) => (cur ? cur + "\u00a0" : "") + numText(v);
  // A typed amount: v null when empty or wrong; bad "e_money" (cannot be read) or "e_number" (above max); typing: it may
  // still become a number (only a currency sign or code so far, or a mark at the end, "100." or "100. "). A word with a
  // space after it ("150 ribu ") never becomes one, so it says why at once, as "150rb" does.
  function readMoney(f, name, max) {
    const raw = f.elements[name].value, v = parseNum(raw);
    if (v === null) return { raw, v: null, bad: null, typing: false };
    if (Number.isNaN(v)) return { raw, v: null, bad: "e_money", typing: raw.trim().replace(LEAD, "") === "" || /[.,]$/.test(raw.trim()) };
    return v > max ? { raw, v: null, bad: "e_number", typing: false } : { raw, v, bad: null, typing: false };
  }
  // Draws the lines and the sum, and returns what SEND reads: { people, each, other, sum }. strict: SEND.
  function renderSum(g, strict = false) {
    const u = SUM_UI[g], f = UI[g].form, cur = currencyOf(f) || "";
    const people = numVal("crew_size", { int: true, min: 1, max: 1000 }, f);
    const each = readMoney(f, "crew_each_local", PAY_MAX), other = readMoney(f, "other_local", OTHER_MAX);
    // A money field that SEND or POST MISSION marked keeps saying why it cannot be read until the crew edits that field
    // (the form's input handler takes the mark off), also when another field, the currency or the language draws the
    // sum again.
    const mark = g === "mission" ? "#m-" : "#f-";
    if ($(mark + "each").classList.contains("invalid")) each.typing = false;
    if ($(mark + "other").classList.contains("invalid")) other.typing = false;
    const v = sumView(people, each, other, strict), payLine = $(u.line), otherLine = $(u.oline);
    payLine.classList.toggle("warn", !!v.line && v.line.cls === "warn");
    payLine.classList.toggle("wait", !!v.line && v.line.cls === "wait");
    if (!v.line) setMsg(payLine);
    else if (v.line.crew) setMsg(payLine, v.line.key, { n: numText(v.line.crew.people), each: amt(cur, v.line.crew.each), crew: amt(cur, v.line.crew.crew) });
    else setMsg(payLine, v.line.key === "people" ? u.people : v.line.key);
    otherLine.classList.toggle("warn", !!v.oline);
    setMsg(otherLine, v.oline ? v.oline.key : "");
    $(u.box).hidden = g === "cleanup" && !each.raw.trim() && !other.raw.trim();
    $(u.parts).classList.toggle("wait", !v.sum);
    setText($(u.total), v.sum ? amt(cur, v.sum.total) : "");
    if (v.sum) setMsg($(u.parts), v.parts, { crew: amt(cur, v.sum.crew), other: amt(cur, v.sum.other), total: amt(cur, v.sum.total) });
    else setMsg($(u.parts), "sum_wait");
    return { people, each, other, sum: v.sum };
  }
  // A mission's price in one line, in the page's language. The crew's pay with its head count when it does not split
  // evenly (posted as one total, like mission #2). "" when the numbers do not fit together or the crew size is unknown.
  function priceLine(cur, total, crew, people) {
    const s = splitOf(total, crew, people);
    if (!s || s.each === null || !/^[A-Z]{3}$/.test(cur || "")) return "";
    const v = { total: amt(cur, total), n: numText(people), each: amt(cur, s.each), other: amt(cur, s.other), crew: amt(cur, crew) };
    return t(crew === 0 ? "price_line_unpaid" : !s.exact ? "price_line_old" : s.other > 0 ? "price_line" : "price_line_0", v);
  }
  // "The price you asked: ..." on the cards of missions in review, open and funded (plan and crew_size of GET /api/partner).
  function askedLine(m) {
    const p = planOf(m), text = p ? priceLine(p.currency, p.price_local, p.crew_local, m.crew_size) : "";
    return text ? line("card_price", { line: text }) : null;
  }
  $("#taskChip").addEventListener("click", (ev) => {
    const plan = chipPlan(ev.currentTarget);
    if (!plan) return;
    fillField(mform.elements.task, plan.task);
    mform.elements.task.focus();
  });
  // The pay for each person and the other costs of that mission, in its currency. Never the crew size: the people are
  // counted for each mission, and the sum under them shows at once what the price comes to.
  $("#priceChip").addEventListener("click", (ev) => {
    const pay = payOf(missionList().find((m) => m.id === ev.currentTarget.dataset.mission) || null);
    if (!pay) return;
    const E = mform.elements;
    if ([...E.currency.options].some((o) => o.value === pay.currency)) E.currency.value = pay.currency;
    else { E.currency.value = "other"; E.currency_other.value = pay.currency; }
    E.currency.dispatchEvent(new Event("change", { bubbles: true }));
    fillField(E.crew_each_local, numText(pay.each));
    fillField(E.other_local, pay.other > 0 ? numText(pay.other) : "");
    E.crew_each_local.focus(); // the chip is gone now: the pay it filled in, to check
  });
  // Where the trash went: the words of the safety rule, one tap each. The crew can add a name after it.
  $$("#dispChips .chip").forEach((b) => b.addEventListener("click", () => fillField(form.elements.disposal, t(b.dataset.i18n))));

  // What depends on a field the crew just changed: the sum under PRICE or COSTS, the chips, the source line under POST A
  // MISSION's crew size, and in the cleanup the summary, the source line, the date chip and the costs.
  const CLEANUP_LIVE = ["place_name", "country", "crew_size", "cleanup_date", "crew_each_local", "other_local"];
  function afterInput(g, name) {
    if (SUM_LIVE.includes(name)) renderSum(g);
    if (["place_name", "task", "crew_each_local", "other_local", "currency"].includes(name)) renderChips();
    if (g === "mission" && name === "crew_size") syncMCrewSrc();
    if (g === "cleanup" && view === "cleanup" && CLEANUP_LIVE.includes(name)) setCleanupFlavor();
  }

  async function refreshPartner() {
    lastFetch = Date.now();
    const epoch = logoEpoch;
    try {
      const r = await fetch(`/api/partner?k=${encodeURIComponent(token)}`, { cache: "no-store" });
      if (r.ok) {
        const fresh = await r.json();
        // A logo answer that came while this list was on its way is newer than the list's logo.
        if (epoch !== logoEpoch) fresh.logo = logoLast;
        partner = fresh;
        const dropped = fillMissionPicker();
        renderChips();
        renderHome();
        // A mission's cleanup form with nothing added, whose mission can no longer take it: back to the crew page, which
        // shows where that mission stands, as a reload would (resolveView). Work stays, as the cleanup without a mission.
        if (view === "cleanup" && dropped && !doneShown.cleanup && !cleanupWork()) toHome();
        else if (view === "cleanup") { setCleanupFlavor(); syncEntryMission(); }
        if (view === "mission" && !missionsOn()) toHome();
      }
    } catch { /* offline: keep the old lists */ }
  }
  // The crew page is where a crew sees that a mission was funded (or its logo checked): back on the page after 5
  // minutes or more, the lists are asked again (never during a send, and never while a logo is on its way).
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && partner && !sendLocked() && !logoPhase && Date.now() - lastFetch >= 5 * 60 * 1000) refreshPartner();
  });

  function done(id, missionId) {
    sends.cleanup++;
    store.del(draftKey());
    for (const it of allItems()) idb.del(it.id);
    reloadDone("cleanup");
    doneShown.cleanup = true;
    // Until the fresh list arrives: this mission has its cleanup now, so its card says CLEANUP SENT.
    const sent = missionId ? missionList().find((m) => m.id === missionId) : null;
    if (sent) { sent.cleanup_sent = true; renderHome(); }
    render();
    setMsg($("#ref"), "ref", null, { post: `: ${id.toUpperCase()}` });
    const page = partner && partner.page_url;
    $("#pageBox").hidden = !page;
    if (page) { $("#pageLink").href = page; $("#pageLink").textContent = page.replace(/^https:\/\//, ""); }
    // A reload of THANK YOU shows the crew page: what it thanks for was sent.
    setState({ ...lastState, done: true }, false);
    // THANK YOU goes to the top of the screen.
    $("#done").scrollIntoView({ block: "start" });
    $("#done .big").focus({ preventScroll: true });
    refreshPartner();
  }
  $("#sharePage").addEventListener("click", (ev) => { if (partner && partner.page_url) shareOrCopy(partner.page_url, ev.target); });

  // Empties the cleanup form: after THANK YOU, and for DELETE or a switch to another mission (discardCleanup).
  function resetCleanup() {
    allItems().forEach(removeItem);
    syncDrops();
    const keep = { country: form.elements.country.value, currency: form.elements.currency.value, currency_other: form.elements.currency_other.value };
    form.reset();
    Object.assign(form.elements.country, { value: keep.country });
    form.elements.currency.value = keep.currency;
    form.elements.currency_other.value = keep.currency_other;
    form.elements.cleanup_date.value = localToday();
    clearMissionPrefill(); // what the mission filled in goes, its country too
    geo.cleanup = null;
    // Not chosen yet: the next cleanup opened from the crew page takes its mission, or none.
    form.elements.mission_id.value = "";
    fillMissionPicker();
    renderCoords("cleanup");
    echoNum("kg"); renderSum("cleanup");
    echoPost();
    $("#progress").hidden = true;
    $("#progress i").style.width = "0";
    // Nothing from the last cleanup stays on the empty form: a photo's message would otherwise come back
    // in the other language at the next switch, as if it were about this one.
    clearMarks(form);
    for (const k of ["before", "after", "video_before", "video_after"]) fieldMsg(k);
    for (const k of SPOT_KINDS) fieldMsg(k);
    setMsg($("#geoMsg"));
    reloadDone("cleanup");
    setMsg($("#status"));
    setMsg($("#formErr"));
    setMsg($("#send"), "send");
    doneShown.cleanup = false;
    changeOpen = false;
    costsOpen = false;
    goneNo = null;
    renderChips();
  }
  $("#again").addEventListener("click", () => { resetCleanup(); toHome(); });

  // data: what was sent, so MISSION #N says the price again as it adds up, while the crew can still say it is wrong.
  function missionDone(res, data) {
    sends.mission++;
    store.del(mdraftKey());
    for (const it of itemsOf("mission")) idb.del(it.id);
    clientRef = newRef(); // the next mission is a new one
    reloadDone("mission");
    lastMissionNo = res.no;
    lastMissionUpdated = res.updated === true;
    lastMissionPrice = { currency: data.currency, total: data.price_local, crew: data.crew_local, people: data.crew_size };
    doneShown.mission = true;
    render();
    renderMissionDone();
    // A reload of MISSION #N shows the crew page, with the mission's card.
    setState({ ...lastState, done: true }, false);
    $("#mdone").scrollIntoView({ block: "start" });
    $("#mdone .big").focus({ preventScroll: true });
    refreshPartner();
  }
  function renderMissionDone() {
    if (lastMissionNo === null) return;
    $("#mdoneBig").textContent = t("m_done_big", { no: lastMissionNo });
    $("#mdoneBody").textContent = t(lastMissionUpdated ? "m_done_updated" : "m_done_body", { no: lastMissionNo });
    const p = lastMissionPrice, text = p ? priceLine(p.currency, p.total, p.crew, p.people) : "";
    $("#mdonePrice").hidden = !text;
    $("#mdonePrice").textContent = text ? t("m_done_price", { line: text }) : "";
  }
  // Empties POST A MISSION: after MISSION #N, and for DELETE (discardMission).
  function resetMission() {
    itemsOf("mission").forEach(removeItem);
    syncDrops();
    const E = mform.elements;
    const keep = { country: E.country.value, currency: E.currency.value, currency_other: E.currency_other.value };
    mform.reset();
    E.country.value = keep.country;
    E.currency.value = keep.currency;
    E.currency_other.value = keep.currency_other;
    E.plan_date.value = localToday(MISSION_DEFAULT_DAYS);
    delete E.crew_size.dataset.prefilled; // the next mission starts on the newest crew size again
    geo.mission = null;
    renderCoords("mission");
    renderSum("mission");
    $("#mprogress").hidden = true;
    $("#mprogress i").style.width = "0";
    clearMarks(mform);
    fieldMsg("now");
    fieldMsg("now_video");
    setMsg($("#mgeoMsg"));
    reloadDone("mission");
    setMsg($("#mstatus"));
    setMsg($("#mformErr"));
    setMsg($("#msend"), "m_send");
    clientRef = newRef();
    doneShown.mission = false;
    syncMCrewSrc();
    renderChips();
  }
  $("#mAgain").addEventListener("click", () => { resetMission(); toHome(); });

  // ---------- save this link ----------
  // The link is the partner's only key. Help them keep it, but never put it in a third-party URL.
  const savedKey = "sapu-link-saved:" + tokenTag;
  // Opened from a home-screen icon: the link is saved already. On iPhone that web app has its own storage,
  // so the saved flag from Safari is not there.
  const fromHomeScreen = (() => {
    try { return navigator.standalone === true || matchMedia("(display-mode: standalone)").matches; } catch { return false; }
  })();
  function platformTip() {
    const ua = navigator.userAgent || "";
    if (fromHomeScreen) return "tip_home";
    if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return "tip_ios";
    if (/SamsungBrowser/.test(ua)) return "tip_samsung";
    if (/Android/i.test(ua)) return "tip_android";
    return "tip_other";
  }
  function showSaveLink(show) {
    $("#saveLink").hidden = !show;
    $("#saveAgain").hidden = show;
  }
  function initSaveLink() {
    const tip = $("#saveTip");
    const key = platformTip();
    tip.setAttribute("data-i18n", key);
    tip.textContent = t(key);
    $("#saveShare").hidden = !navigator.share;
    if (fromHomeScreen) store.set(savedKey, "1");
    showSaveLink(!store.get(savedKey) && !fromHomeScreen);
  }
  $("#saveShare").addEventListener("click", () => {
    navigator.share({ title: "Sapu Earth upload link", url: location.href }).catch(() => {});
  });
  $("#saveCopy").addEventListener("click", (ev) => copyText(location.href, ev.currentTarget));
  // The focused button disappears with the card, so focus moves on (without scrolling) instead of falling to <body>.
  $("#saveDone").addEventListener("click", () => {
    store.set(savedKey, "1");
    showSaveLink(false);
    $("#saveAgain button").focus({ preventScroll: true });
  });
  $("#saveAgain button").addEventListener("click", () => {
    showSaveLink(true);
    $("#saveLink .panel-title").focus({ preventScroll: true });
    $("#saveLink").scrollIntoView({ behavior: "smooth", block: "start" });
  });

  // ---------- privacy notice ----------
  // The links to #privacy (under each consent box, in the footer) open the notice and go to it. The address
  // stays as it is, so the link a crew copies or saves never ends in #privacy.
  $$('a[href="#privacy"]').forEach((a) => a.addEventListener("click", (ev) => {
    ev.preventDefault();
    const pv = $("#privacy");
    pv.open = true;
    pv.scrollIntoView({ behavior: "smooth", block: "start" });
    $("summary", pv).focus({ preventScroll: true });
  }));

  // ---------- start ----------
  async function start() {
    // Firefox puts back what the forms held before a reload, the consent boxes included, even after
    // a cleanup was sent. Start from the HTML instead: the drafts below bring back only what we keep
    // on purpose, and consent is never kept.
    form.reset();
    mform.reset();
    applyLang();
    form.elements.cleanup_date.value = localToday();
    form.elements.cleanup_date.max = localToday(1);
    for (const f of SPOT_DAYS) form.elements[f].max = localToday(1);
    mform.elements.plan_date.value = localToday(MISSION_DEFAULT_DAYS);
    mform.elements.plan_date.min = localToday();
    mform.elements.plan_date.max = localToday(MISSION_AHEAD_DAYS);
    if (!/^[A-Za-z0-9_-]{20,100}$/.test(token)) { setWhoKey("no_link"); return; }
    let r;
    try {
      r = await fetch(`/api/partner?k=${encodeURIComponent(token)}`, { cache: "no-store" });
    } catch {
      setWhoKey("offline_link");
      return;
    }
    if (!r.ok) { setWhoKey(r.status === 404 ? "bad_link" : "offline_link"); return; }
    partner = await r.json();
    // Many Indonesian phones are set to English: an Indonesian partner gets Bahasa Indonesia unless they chose.
    if (!storedLang && partner.country === "ID") lang = "id";
    fillCountries();
    form.elements.country.value = partner.country || "";
    mform.elements.country.value = partner.country || "";
    fillCurrencies(); // now with the crew's own currency first
    const currency = startCurrency();
    form.elements.currency.value = currency;
    mform.elements.currency.value = currency;
    fillMissionPicker(); // the options first, so the draft can bring back the crew's choice
    const draft = loadDraft();
    echoPost(); // a link kept in the draft gets its line back
    const mdraft = loadMDraft();
    if (!clientRef) clientRef = newRef();
    const restored = await restoreFiles();
    reloadFor.cleanup = !!draft && (draft.fileCount || 0) > restored.cleanup;
    reloadFor.mission = !!mdraft && (mdraft.fileCount || 0) > restored.mission;
    if (reloadFor.cleanup || reloadFor.mission) setMsg($("#reloadNote"), "reload_note");
    // With the files back, the cleanup knows whether it holds work. A draft whose mission is gone (loadDraft) is
    // dropped: work keeps what the mission filled in and says which mission it lost, a form that was only opened
    // just empties. Otherwise the restored mission fills in what the draft left empty (a "No mission" the crew chose
    // has no marks, so nothing changes then). A cleanup that lost its mission earlier and holds no work any more has
    // nothing left to say.
    if (draft && draft.dropped) dropMission(noOf(draft.dropped));
    else applyMissionPick();
    if (goneNo !== null && !cleanupWork()) { goneNo = null; store.del(draftKey()); }
    lastFetch = Date.now();
    applyLang();
    // The screen of this history entry (a reload, or Android bringing back a tab it dropped while the camera was
    // open), while it still fits. A fresh open (the link from WhatsApp, a bookmark, the home-screen icon) has no
    // entry of ours and shows the crew page, where unsent work waits as CONTINUE. Back and forward into an entry
    // of an older page load the page again and end up here too.
    const s = ours(history.state);
    const shown = show(fit(resolveView(s, ctx())));
    setState(stateFor(shown, s), false);
    started = true;
    initSaveLink();
  }
  start();
})();

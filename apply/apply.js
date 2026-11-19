/* Sapu Earth partner application page. No build step, no dependencies.
   Made for cheap Android phones on slow networks: photos are shrunk and stripped of camera data
   on the phone, typed answers survive a reload (localStorage), and sending retries on its own.
   Every retry reuses the same client_ref, so the server never stores an application twice. */
(function () {
  "use strict";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  // /apply/#privacy opens the notice. This line was an inline script in the page; the site's script policy
  // (_headers) allows none, so it runs first thing here, before anything waits.
  if (location.hash === "#privacy" && $("#privacy")) $("#privacy").open = true;
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
    del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
  };

  // ---------- text ----------
  const T = {
    en: {
      title: "BECOME A PARTNER CREW",
      lead: "Do you clean beaches, rivers or streets with a team? Sapu Earth pays local crews for cleanups and shows every one on a public map. Tell us about your crew. It takes about 3 minutes.",
      free: "There are no fees, and we never ask for a PIN, a password or an OTP code.",
      how_h: "HOW IT WORKS",
      how_1: "You post a dirty spot as a mission, with your own price in local money.",
      how_2: "We check it. Only funded missions are paid, so wait for our OK before you start.",
      how_3: "We send an advance to one person's own bank account or e-wallet, and the rest after we approve your cleanup.",
      honest: "We fund a few crews at a time, so we can't say yes to everyone. We reply to every application on WhatsApp or email, usually within a week. No calls needed.",
      already: "Already a crew with us? You don't need to apply again: open the private link from our WhatsApp or email message. Lost it? Write to hello@sapu.earth and we send you a new one.",
      crew_h: "YOUR CREW",
      org_name: "Crew or group name",
      country: "Country",
      area: "City or area where you clean", area_ph: "Canggu, Bali",
      about: "What do you clean, and how often?",
      about_ph: "Example: every Saturday 6 of us clean the river mouth in Canggu. We started in 2023.",
      links: "Where can we see your cleanups?",
      links_hint: "Instagram, TikTok, Facebook or a website.",
      link_ph: "instagram.com/yourcrew or @yourcrew",
      // The crew's logo (docs/upload-flow.md, Crew logos): its own panel, decided with the application.
      logo_h: "LOGO (OPTIONAL)",
      logo_hint: "If your crew has a logo, add it here: the logo itself, or a close-up photo of the logo on your banner or shirt. If we work together, we can show it next to your crew's name on sapu.earth. No photos of people.",
      add_logo: "+ Add logo",
      photos_h: "PHOTOS (OPTIONAL)",
      photos_hint: "Up to 3 photos of your crew at a cleanup. Only the Sapu Earth team sees them, and we delete them once we decide.",
      add_photos: "+ Add photos",
      reach_h: "HOW DO WE REACH YOU?",
      contact_name: "Your name",
      reach_hint: "Fill in at least one. We reply by message or email, no calls.",
      whatsapp: "WhatsApp number", email: "Email",
      wa_echo: "We will use: {n}",
      wa_check: "Check the country code. The country you chose uses +{d}.",
      wa_country: "Choose your country above, so we add the right country code.",
      wa_len: "Check the number: it has {k} digits after +{d}, but mobile numbers in the country you chose have {n}.",
      wa_range: "{a} to {b}",
      heard: "How did you hear about Sapu Earth?", heard_ph: "TikTok, Instagram, a friend",
      consent: "Sapu Earth may store these details to review my application and to contact me about it. If we don't go ahead together, or haven't decided within 3 months, the application is deleted. If we work together, we keep my contact details for as long as we do.",
      pv_sum: "How we handle your details",
      pv_who_h: "Who:", pv_who: "Sapu Earth is run by Marcus Pousette in Innsbruck, Austria. Contact:",
      pv_what_h: "What we store:",
      pv_what: "your answers, your contact details, up to 3 photos, your crew's logo if you add one, and for about a day a scrambled code made from your internet address, to stop spam. Until you send, the answers you type stay on this phone as a draft. After sending, the phone keeps only your language choice.",
      pv_why_h: "Why:",
      pv_why: "to review your application and reply to you, and if we work together, to show your crew on sapu.earth from the first day: its name, country and logo in the list of crews at sapu.earth/crews, and on its public page also one of the links you gave us. Legal basis: your consent and steps before working together (GDPR Art. 6(1)(a) and (b)).",
      pv_where_h: "Where:",
      pv_where: "on Cloudflare servers (database and file storage), which may be outside the EU. Cloudflare stores them for us as our processor. It is certified under the EU-US Data Privacy Framework and uses the EU standard contractual clauses for other countries. This page loads all its files, fonts included, from sapu.earth.",
      pv_long_h: "How long:",
      pv_long: "photos are deleted once we decide, and so is your crew's logo, unless we work together and show it on sapu.earth: then it stays there until a newer one replaces it or we stop working together. Applications we don't take forward are deleted, and so is any application we haven't decided on within 3 months. If we work together, we keep your contact details while we do and delete them when we stop.",
      pv_rights_h: "Your rights:",
      pv_rights: "ask to see, correct or delete your details, or withdraw your consent, by emailing",
      pv_complain: "You can also complain to the Austrian data protection authority",
      send: "SEND APPLICATION", try_again: "TRY AGAIN",
      keep_open: "Keep this page open until you see THANK YOU.",
      preparing: "Preparing your pictures…",
      sending: "Sending…",
      retrying: "Connection problem. Trying again in {s} seconds…",
      retrying_1: "Connection problem. Trying again in 1 second…",
      waiting_online: "You are offline. Waiting for the connection to come back…",
      thanks: "THANK YOU!",
      thanks_body: "We got your application. We read every one and reply on WhatsApp or email, usually within a week.",
      ref: "Reference",
      follow: "Meanwhile, follow us:",
      globe: "BACK TO THE GLOBE",
      remove: "Remove",
      e_org: "Write the name of your crew or group.",
      e_country: "Choose the country.",
      e_area: "Write the city or area where you clean.",
      e_about: "Tell us what you clean and how often.",
      e_long: "This is too long. Please make it a bit shorter.",
      e_check: "Please check this answer. Maybe it is too long.",
      e_link: "Write a web address like instagram.com/yourcrew, or a handle like @yourcrew.",
      e_name: "Write your name.",
      e_whatsapp: "Please write your WhatsApp number with the country code, like +62 812 3456 7890.",
      e_email: "Check the email address. It should look like name@example.com.",
      e_contact: "Fill in your WhatsApp number or your email, so we can reply.",
      e_consent: "Please tick the box to agree.",
      e_fix: "Some answers still need fixing. See the fields marked in orange.",
      e_decode: "This photo could not be read. Please choose a JPG or PNG photo.",
      e_photo_big: "This photo is too big. Please choose another photo.",
      e_max_photos: "At most 3 photos.",
      e_photos_server: "A photo was not accepted. Remove the photos and add them again, or send without photos.",
      e_logo_read: "This picture could not be read. Choose your crew's logo as a JPG or PNG picture.",
      e_logo_small: "This picture is too small for a logo. Choose a bigger one.",
      e_logo_server: "The logo was not accepted. Remove it and add it again, or send without a logo.",
      e_rate: "You already sent a few applications today. Please wait a day, or email hello@sapu.earth.",
      e_busy: "We have a lot of applications to read right now. Please try again in a few days, or email hello@sapu.earth.",
      e_rejected: "Something was not accepted. Please check your answers and try again.",
      e_send: "Could not send. Your answers are saved. Please try again.",
    },
    id: {
      title: "GABUNG JADI KRU MITRA",
      lead: "Kamu membersihkan pantai, sungai, atau jalan bersama tim? Sapu Earth membayar kru lokal untuk aksi bersih, dan setiap aksi tampil di peta publik. Ceritakan tentang kru kamu. Cuma butuh sekitar 3 menit.",
      free: "Tidak ada biaya apa pun, dan kami tidak pernah meminta PIN, kata sandi, atau kode OTP.",
      how_h: "CARA KERJANYA",
      how_1: "Kalian mengajukan tempat yang kotor sebagai misi, dengan harga kalian sendiri dalam mata uang lokal.",
      how_2: "Kami periksa dulu. Hanya misi yang didanai yang dibayar, jadi tunggu kabar dari kami sebelum mulai.",
      how_3: "Kami kirim uang muka ke rekening bank atau e-wallet milik pribadi satu orang, dan sisanya setelah laporan aksi bersih kalian kami setujui.",
      honest: "Kami hanya bisa mendanai beberapa kru dalam satu waktu, jadi kami tidak bisa menerima semua. Kami membalas setiap pendaftaran lewat WhatsApp atau email, biasanya dalam seminggu. Tidak perlu telepon.",
      already: "Sudah jadi kru kami? Tidak perlu daftar lagi: buka link pribadi dari pesan WhatsApp atau email kami. Link-nya hilang? Kirim email ke hello@sapu.earth, nanti kami kirim link baru.",
      crew_h: "KRU KAMU",
      org_name: "Nama kru atau kelompok",
      country: "Negara",
      area: "Kota atau daerah tempat kalian bersih-bersih", area_ph: "Canggu, Bali",
      about: "Apa yang kalian bersihkan, dan seberapa sering?",
      about_ph: "Contoh: setiap Sabtu kami berenam membersihkan muara sungai di Canggu. Kami mulai sejak 2023.",
      links: "Di mana kami bisa melihat aksi bersih kalian?",
      links_hint: "Instagram, TikTok, Facebook, atau website.",
      link_ph: "instagram.com/krukamu atau @krukamu",
      logo_h: "LOGO (TIDAK WAJIB)",
      logo_hint: "Kalau kru kamu punya logo, tambahkan di sini: logonya sendiri, atau foto logo dari dekat di spanduk atau kaos kru kamu. Kalau kita bekerja sama, logo ini bisa kami tampilkan di samping nama kru kamu di sapu.earth. Bukan foto orang.",
      add_logo: "+ Tambah logo",
      photos_h: "FOTO (TIDAK WAJIB)",
      photos_hint: "Maksimal 3 foto kru kamu saat aksi bersih. Foto ini hanya dilihat tim Sapu Earth, dan kami hapus setelah ada keputusan.",
      add_photos: "+ Tambah foto",
      reach_h: "CARA MENGHUBUNGI KAMU",
      contact_name: "Nama kamu",
      reach_hint: "Isi minimal salah satu. Kami membalas lewat pesan atau email, bukan telepon.",
      whatsapp: "Nomor WhatsApp", email: "Email",
      wa_echo: "Nomor yang kami pakai: {n}",
      wa_check: "Cek lagi kode negaranya. Negara yang kamu pilih memakai kode +{d}.",
      wa_country: "Pilih negara kamu di atas dulu, supaya kode negaranya benar.",
      wa_len: "Cek lagi nomornya: ada {k} angka setelah +{d}, padahal nomor HP di negara yang kamu pilih punya {n} angka.",
      wa_range: "{a} sampai {b}",
      heard: "Dari mana kamu tahu tentang Sapu Earth?", heard_ph: "TikTok, Instagram, teman",
      consent: "Sapu Earth boleh menyimpan data ini untuk memeriksa pendaftaran saya dan menghubungi saya soal pendaftaran ini. Kalau kita tidak jadi bekerja sama, atau belum ada keputusan dalam 3 bulan, pendaftarannya dihapus. Kalau kita bekerja sama, data kontak saya disimpan selama kerja sama itu berjalan.",
      pv_sum: "Cara kami mengelola data kamu",
      pv_who_h: "Siapa:", pv_who: "Sapu Earth dijalankan oleh Marcus Pousette di Innsbruck, Austria. Kontak:",
      pv_what_h: "Apa yang kami simpan:",
      pv_what: "jawaban kamu, data kontak kamu, maksimal 3 foto, logo kru kamu kalau kamu menambahkannya, dan selama sekitar sehari sebuah kode acak yang dibuat dari alamat internet kamu, untuk mencegah spam. Sampai terkirim, jawaban yang kamu ketik tersimpan di HP ini sebagai draf. Setelah terkirim, HP ini hanya menyimpan pilihan bahasa kamu.",
      pv_why_h: "Untuk apa:",
      pv_why: "untuk memeriksa pendaftaran kamu dan membalas kamu, dan kalau kita bekerja sama, untuk menampilkan kru kamu di sapu.earth sejak hari pertama: nama, negara, dan logonya di daftar kru di sapu.earth/crews, dan di halaman publiknya juga salah satu link yang kamu berikan. Dasar hukumnya: persetujuan kamu dan langkah sebelum kita bekerja sama (GDPR Pasal 6(1)(a) dan (b)).",
      pv_where_h: "Di mana:",
      pv_where: "di server Cloudflare (database dan penyimpanan file), yang bisa berada di luar Uni Eropa. Cloudflare menyimpannya untuk kami sebagai pemroses data kami. Cloudflare tersertifikasi di bawah EU-US Data Privacy Framework dan memakai klausul kontrak standar Uni Eropa untuk negara lain. Halaman ini memuat semua file, termasuk font, dari sapu.earth.",
      pv_long_h: "Berapa lama:",
      pv_long: "foto dihapus setelah kami memutuskan, begitu juga logo kru kamu, kecuali kita bekerja sama dan logo itu kami tampilkan di sapu.earth: logo itu tetap di sana sampai diganti dengan logo yang lebih baru atau kerja sama kita berhenti. Pendaftaran yang tidak kami lanjutkan dihapus, begitu juga pendaftaran yang belum kami putuskan dalam 3 bulan. Kalau kita bekerja sama, kami menyimpan data kontak kamu selama kerja sama berjalan, lalu menghapusnya saat kerja sama berhenti.",
      pv_rights_h: "Hak kamu:",
      pv_rights: "kamu bisa minta untuk melihat, memperbaiki, atau menghapus data kamu, atau menarik persetujuan kamu, lewat email ke",
      pv_complain: "Kamu juga bisa mengajukan pengaduan ke otoritas perlindungan data Austria",
      send: "KIRIM PENDAFTARAN", try_again: "COBA LAGI",
      keep_open: "Jangan tutup halaman ini sampai muncul TERIMA KASIH.",
      preparing: "Sedang menyiapkan gambar…",
      sending: "Sedang mengirim…",
      retrying: "Koneksi bermasalah. Mencoba lagi dalam {s} detik…",
      retrying_1: "Koneksi bermasalah. Mencoba lagi dalam 1 detik…",
      waiting_online: "Kamu sedang offline. Menunggu koneksi tersambung lagi…",
      thanks: "TERIMA KASIH!",
      thanks_body: "Pendaftaran kamu sudah kami terima. Kami membaca semuanya dan membalas lewat WhatsApp atau email, biasanya dalam seminggu.",
      ref: "Nomor referensi",
      follow: "Sambil menunggu, ikuti kami:",
      globe: "KEMBALI KE PETA",
      remove: "Hapus",
      e_org: "Tulis nama kru atau kelompok kamu.",
      e_country: "Pilih negaranya.",
      e_area: "Tulis kota atau daerah tempat kalian bersih-bersih.",
      e_about: "Ceritakan apa yang kalian bersihkan dan seberapa sering.",
      e_long: "Tulisan ini terlalu panjang. Tolong dipersingkat sedikit, ya.",
      e_check: "Cek lagi isian ini. Mungkin terlalu panjang.",
      e_link: "Tulis alamat web seperti instagram.com/krukamu, atau nama akun seperti @krukamu.",
      e_name: "Tulis nama kamu.",
      e_whatsapp: "Tulis nomor WhatsApp kamu dengan kode negara, misalnya +62 812 3456 7890.",
      e_email: "Cek lagi alamat emailnya. Contohnya: nama@contoh.com.",
      e_contact: "Isi nomor WhatsApp atau email kamu, supaya kami bisa membalas.",
      e_consent: "Centang dulu kotak persetujuan, ya.",
      e_fix: "Masih ada isian yang perlu diperbaiki. Lihat kolom yang ditandai oranye.",
      e_decode: "Foto ini tidak bisa dibaca. Pilih foto berformat JPG atau PNG.",
      e_photo_big: "Foto ini terlalu besar. Coba pilih foto lain.",
      e_max_photos: "Maksimal 3 foto.",
      e_photos_server: "Ada foto yang tidak diterima. Hapus fotonya lalu tambahkan lagi, atau kirim tanpa foto.",
      e_logo_read: "Gambar ini tidak bisa dibaca. Pilih logo kru kamu dalam format JPG atau PNG.",
      e_logo_small: "Gambar ini terlalu kecil untuk logo. Pilih gambar yang lebih besar.",
      e_logo_server: "Logonya tidak diterima. Hapus logonya lalu tambahkan lagi, atau kirim tanpa logo.",
      e_rate: "Hari ini kamu sudah mengirim beberapa pendaftaran. Tunggu sehari, ya, atau kirim email ke hello@sapu.earth.",
      e_busy: "Saat ini ada banyak pendaftaran yang sedang kami baca. Coba lagi beberapa hari lagi, atau kirim email ke hello@sapu.earth.",
      e_rejected: "Ada isian yang tidak diterima. Cek lagi jawaban kamu, lalu coba lagi.",
      e_send: "Gagal mengirim. Isian kamu tetap tersimpan. Coba lagi, ya.",
    },
  };
  const storedLang = store.get("sapu-lang");
  let lang = storedLang || ((navigator.language || "").toLowerCase().startsWith("id") ? "id" : "en");
  const t = (k, vars) => {
    let s = (T[lang] && T[lang][k]) || T.en[k] || k;
    if (vars) for (const [a, b] of Object.entries(vars)) s = s.replace("{" + a + "}", b);
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
  // Spaces, invisible format marks (numbers copied from contacts often carry bidi marks), any kind of dash,
  // dots and parentheses. Browsers without \p{...} get a fixed list instead of a syntax error.
  const WA_STRIP = (() => {
    try { return new RegExp("[\\s\\p{Cf}\\p{Pd}.()]", "gu"); } catch { /* old browser */ }
    return /[\s\u00ad\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\ufeff\-\u2010-\u2015\u2212\u2e3a\u2e3b\ufe58\ufe63\uff0d.()]/g;
  })();
  const WA_RE = /^\+[1-9][0-9]{7,14}$/;
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
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  const HANDLE_RE = /^@[A-Za-z0-9._]{1,40}$/;
  const LIMIT = { photos: 3, photoBytes: 3 * 1024 * 1024, photoInputBytes: 60 * 1024 * 1024 };
  const MIN_OPEN_MS = 3500;       // the server silently drops forms sent within 3 s of opening (bot trap)
  const SEND_TIMEOUT_MS = 300000; // a hung connection is aborted and retried; retries are safe
  const DRAFT_KEY = "sapu-apply-draft";
  // Photos and consent are never saved. A draft from before 2026-11-17 may still hold crew_size (the head count the form
  // no longer asks, Marcus said 'Drop the head count'): it is not in this list, so it is never read back or sent.
  const DRAFT_FIELDS = ["org_name", "country", "area", "about", "link1", "link2", "link3",
    "contact_name", "whatsapp", "email", "heard_from"];
  // Server error field -> local message. Text fields the page already checks for empty fail on the server mostly for length.
  const FIELD_MSG = {
    org_name: "e_check", contact_name: "e_check", area: "e_check", about: "e_check", heard_from: "e_check",
    country: "e_country", links: "e_link", whatsapp: "e_whatsapp", email: "e_email",
    contact: "e_contact", photos: "e_photos_server", consent: "e_consent",
  };

  // ---------- state ----------
  const form = $("#form");
  const E = form.elements;
  const fileInput = $('#f-photos input[type="file"]');
  const photos = [];          // { blob, url, el }
  const logoInput = $('#f-logo input[type="file"]');
  let logo = null;            // the crew's logo: { blob, url, el }, never kept in the draft, like the photos
  const working = new Set();  // photo batches still being converted
  let clientRef = "";
  let refId = null;
  let busy = false;

  const newRef = () => [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const chars = (s) => [...s].length;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  // The status line under SEND. No key empties it.
  function status(key, vars) { setMsg($("#status"), key, vars); }

  // ---------- language ----------
  // A text shown from a key keeps that key on its element (data-i18n), with the key's values (data-i18n-vars)
  // and any plain text around it (data-i18n-pre, data-i18n-post: the server's detail), so switching language
  // shows it again in the new language: labels, field messages, the line above SEND, the status line, TRY AGAIN.
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
    $$(".lang button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
    $$(".thumb .rm").forEach((b) => b.setAttribute("aria-label", t("remove")));
    fillCountries();
    echoWhatsapp();
    renderRef();
  }
  $$(".lang button").forEach((b) => b.addEventListener("click", () => {
    lang = b.dataset.lang;
    store.set("sapu-lang", lang);
    applyLang();
  }));

  function fillCountries() {
    const sel = E.country;
    const cur = sel.value;
    let names = null;
    try { names = new Intl.DisplayNames([lang, "en"], { type: "region" }); } catch { /* old browser */ }
    const rows = ISO.map((c) => {
      let n = c;
      try { n = (names && names.of(c)) || c; } catch { /* unknown code */ }
      return [c, n];
    }).sort((a, b) => a[1].localeCompare(b[1], lang));
    sel.textContent = "";
    sel.append(new Option("", ""));
    for (const [c, n] of rows) sel.append(new Option(`${n} (${c})`, c));
    sel.value = cur;
  }

  // ---------- draft: typed fields in localStorage ----------
  function saveDraft() {
    const d = { client_ref: clientRef };
    for (const f of DRAFT_FIELDS) d[f] = E[f].value;
    store.set(DRAFT_KEY, JSON.stringify(d));
  }
  function loadDraft() {
    let d = null;
    try { d = JSON.parse(store.get(DRAFT_KEY) || "null"); } catch { d = null; }
    if (!d || typeof d !== "object") return;
    for (const f of DRAFT_FIELDS) if (typeof d[f] === "string" && d[f] !== "") E[f].value = d[f];
    if (typeof d.client_ref === "string" && /^[0-9a-f]{32}$/.test(d.client_ref)) clientRef = d.client_ref;
  }
  form.addEventListener("input", (ev) => {
    clearFieldError(ev.target);
    if (ev.target.name === "whatsapp" || ev.target.name === "country") echoWhatsapp();
    saveDraft();
  });
  form.addEventListener("change", (ev) => {
    if (ev.target.name === "country") echoWhatsapp();
    if (ev.target !== fileInput && ev.target !== logoInput) saveDraft();
  });

  // ---------- WhatsApp number ----------
  // What the line under the number warns about: no country chosen yet for a local number, a country we have no
  // code for and no + typed, a code that is not the chosen country's (a crew may use a phone from another country,
  // so this does not stop the send), or a number with more or fewer digits than a mobile number there has.
  function waWarning(raw, n, country) {
    if (!raw.trim()) return null;
    if (!country) return /^\s*(\+|00)/.test(raw) ? null : { key: "wa_country" };
    const d = DIAL[country];
    if (!d) return WA_RE.test(n) ? null : { key: "e_whatsapp" };
    if (!WA_RE.test(n)) return null;
    if (codeOf(n) !== d) return { key: "wa_check", vars: { d } };
    const len = waLen(country), k = n.length - 1 - d.length;
    if (!len || (k >= len[0] && k <= len[1])) return null;
    const want = len[0] === len[1] ? String(len[0]) : t("wa_range", { a: len[0], b: len[1] });
    return { key: "wa_len", vars: { k, d, n: want } };
  }
  // Show the number we will store, so a wrong country code or a missing digit is easy to spot.
  function echoWhatsapp() {
    const echo = $("#waEcho");
    const n = normWhatsapp(E.whatsapp.value, E.country.value);
    const ok = WA_RE.test(n);
    const w = waWarning(E.whatsapp.value, n, E.country.value);
    echo.classList.toggle("warn", !!w);
    echo.textContent = ok ? t("wa_echo", { n }) : "";
    if (w) {
      const hint = document.createElement("span");
      hint.className = "echo-hint";
      hint.textContent = t(w.key, w.vars);
      echo.append(ok ? " " : "", hint);
    }
  }

  // ---------- links ----------
  // Returns the line to send, or null when it is neither an http(s) address nor an @handle.
  function normLink(s) {
    if (s.startsWith("@")) return HANDLE_RE.test(s) ? s : null;
    let u = s;
    if (!/^[a-z][a-z0-9+.-]*:/i.test(u) && u.includes(".") && !/\s/.test(u)) u = "https://" + u;
    if (chars(u) > 200) return null;
    try {
      const p = new URL(u);
      return p.protocol === "https:" || p.protocol === "http:" ? u : null;
    } catch {
      return null;
    }
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
  // stay and every other APPn segment goes. The image data is not touched. Same code in upload/upload.js.
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
  async function toJpeg(file, maxSide, quality) {
    const src = await decode(file);
    const w = src.naturalWidth || src.width, h = src.naturalHeight || src.height;
    if (!w || !h) throw new Error("decode");
    const scale = Math.min(1, maxSide / Math.max(w, h));
    const cw = Math.max(1, Math.round(w * scale)), ch = Math.max(1, Math.round(h * scale));
    const canvas = document.createElement("canvas");
    canvas.width = cw; canvas.height = ch;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, cw, ch);
    ctx.drawImage(src, 0, 0, cw, ch);
    if (src.close) src.close();
    const blob = await new Promise((res) => canvas.toBlob(res, "image/jpeg", quality));
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

  function photoMsg(key) { setMsg(fmsgFor($("#f-photos"), true), key); }

  fileInput.addEventListener("change", () => {
    const picked = [...fileInput.files];
    fileInput.value = "";
    const job = addPhotos(picked);
    const forget = () => working.delete(job);
    working.add(job);
    job.then(forget, forget);
  });

  async function addPhotos(list) {
    for (const file of list) {
      if (photos.length >= LIMIT.photos) { photoMsg("e_max_photos"); break; }
      if (file.size > LIMIT.photoInputBytes) { photoMsg("e_photo_big"); continue; }
      const item = { blob: null, url: null, el: null };
      photos.push(item);
      renderThumb(item);
      syncDrop();
      let failKey = null;
      try {
        let blob = await toJpeg(file, 1600, 0.82);
        if (blob.size > LIMIT.photoBytes) blob = await toJpeg(file, 1200, 0.7);
        if (blob.size > LIMIT.photoBytes) failKey = "e_photo_big";
        else item.blob = blob;
      } catch {
        failKey = "e_decode";
      }
      if (!photos.includes(item)) continue; // removed while it was being prepared
      if (failKey) { removePhoto(item); photoMsg(failKey); continue; }
      item.url = URL.createObjectURL(item.blob);
      const img = document.createElement("img");
      img.alt = "";
      img.src = item.url;
      item.el.prepend(img);
      item.el.classList.remove("busy");
    }
    syncDrop();
  }

  function renderThumb(item) {
    const el = document.createElement("div");
    el.className = "thumb busy";
    const rm = document.createElement("button");
    rm.type = "button"; rm.className = "rm"; rm.textContent = "✕"; rm.setAttribute("aria-label", t("remove"));
    rm.addEventListener("click", () => {
      if (busy) return;
      removePhoto(item);
      syncDrop();
      clearFieldError(fileInput);
    });
    el.append(rm);
    $("#thumbs").append(el);
    item.el = el;
  }
  function removePhoto(item) {
    const i = photos.indexOf(item);
    if (i >= 0) photos.splice(i, 1);
    if (item.url) URL.revokeObjectURL(item.url);
    if (item.el) item.el.remove();
  }
  function syncDrop() { $("#f-photos .drop").classList.toggle("full", photos.length >= LIMIT.photos); }

  // ---------- the crew's logo (LOGO (OPTIONAL)) ----------
  // One logo, made into the square on the phone (toLogoJpeg) like on the crew page. A new pick replaces it. SEND waits
  // for it with the photos ("Preparing photos…"). Not kept in the draft.
  logoInput.addEventListener("change", () => {
    const file = logoInput.files && logoInput.files[0];
    logoInput.value = "";
    if (!file) return;
    const job = addLogo(file);
    const forget = () => working.delete(job);
    working.add(job);
    job.then(forget, forget);
  });
  async function addLogo(file) {
    clearFieldError(logoInput);
    if (logo) removeLogo(logo);
    const item = { blob: null, url: null, el: null };
    logo = item;
    const el = document.createElement("div");
    el.className = "thumb busy";
    const rm = document.createElement("button");
    rm.type = "button"; rm.className = "rm"; rm.textContent = "✕"; rm.setAttribute("aria-label", t("remove"));
    rm.addEventListener("click", () => {
      if (busy) return;
      removeLogo(item);
      clearFieldError(logoInput);
    });
    el.append(rm);
    $("#logoThumb").append(el);
    item.el = el;
    syncLogoDrop();
    let failKey = null;
    try {
      if (file.size > LIMIT.photoInputBytes) failKey = "e_logo_read";
      else item.blob = await toLogoJpeg(file);
    } catch (e) {
      failKey = e && e.message === "small" ? "e_logo_small" : "e_logo_read";
    }
    if (logo !== item) return; // removed, or another logo picked, while it was being prepared
    if (failKey) { removeLogo(item); setMsg(fmsgFor($("#f-logo"), true), failKey); return; }
    item.url = URL.createObjectURL(item.blob);
    const img = document.createElement("img");
    img.alt = "";
    img.src = item.url;
    el.prepend(img);
    el.classList.remove("busy");
  }
  function removeLogo(item) {
    if (logo === item) logo = null;
    if (item.url) URL.revokeObjectURL(item.url);
    if (item.el) item.el.remove();
    syncLogoDrop();
  }
  function syncLogoDrop() { $("#f-logo .drop").classList.toggle("full", !!logo); }

  // ---------- validation ----------
  function collect() {
    const errors = [];
    const bad = (id, key) => errors.push({ id, key });
    const v = (name) => E[name].value.trim();
    const d = {};
    d.org_name = v("org_name");
    if (!d.org_name) bad("f-org_name", "e_org");
    d.country = E.country.value;
    if (!/^[A-Z]{2}$/.test(d.country)) bad("f-country", "e_country");
    d.area = v("area");
    if (!d.area) bad("f-area", "e_area");
    d.about = v("about");
    if (!d.about) bad("f-about", "e_about");
    // Form uploads send each line break as CRLF; the server turns that back into one character before counting.
    else if (chars(d.about.replace(/\r\n?/g, "\n")) > 1000) bad("f-about", "e_long");
    const links = [];
    for (const name of ["link1", "link2", "link3"]) {
      const s = v(name);
      if (!s) continue;
      const l = normLink(s);
      if (l) links.push(l); else bad("f-" + name, "e_link");
    }
    d.links = links.join("\n");
    d.contact_name = v("contact_name");
    if (!d.contact_name) bad("f-contact_name", "e_name");
    d.whatsapp = normWhatsapp(E.whatsapp.value, d.country);
    // A local number before the country is chosen: the country's own message is enough, the code comes with it.
    const waLater = !d.country && !/^\s*(\+|00)/.test(E.whatsapp.value);
    if (d.whatsapp && !WA_RE.test(d.whatsapp) && !waLater) bad("f-whatsapp", "e_whatsapp");
    d.email = v("email");
    if (d.email && !(d.email.length <= 120 && EMAIL_RE.test(d.email))) bad("f-email", "e_email");
    if (!d.whatsapp && !d.email) bad("f-contact", "e_contact");
    d.heard_from = v("heard_from");
    if (!E.consent.checked) bad("f-consent", "e_consent");
    return { errors, data: d };
  }

  // Every field gets its own message box; a field can name one outside itself with data-fmsg.
  // The box goes after a <label>, not inside it, so screen readers read it as the input's description
  // (aria-describedby) and not as part of its name. Its id is "err-" + the field id.
  function fmsgFor(el, create) {
    if (!el.id) return null;
    let m = document.querySelector(`[data-fmsg="${el.id}"]`) || el.querySelector(":scope > .fmsg");
    if (!m && create) {
      m = document.createElement("span");
      m.className = "msg err fmsg";
      m.setAttribute("data-fmsg", el.id);
      if (el.tagName === "LABEL") el.after(m); else el.append(m);
    }
    if (m && !m.id) m.id = "err-" + el.id;
    return m;
  }
  // Links (or unlinks) an error box to an input: aria-describedby, plus aria-invalid while any error is linked.
  function describe(input, id, on) {
    const ids = (input.getAttribute("aria-describedby") || "").split(/\s+/).filter((x) => x && x !== id);
    if (on) ids.push(id);
    if (ids.length) input.setAttribute("aria-describedby", ids.join(" ")); else input.removeAttribute("aria-describedby");
    if (ids.some((x) => x.startsWith("err-"))) input.setAttribute("aria-invalid", "true"); else input.removeAttribute("aria-invalid");
  }
  // The inputs a field's error is about: one input, or several (the contact pair, the link lines).
  const fieldInputs = (f) => $$("input, select, textarea", f);
  function clearFieldError(target) {
    for (let f = target.closest(".field, .check"); f; f = f.parentElement && f.parentElement.closest(".field, .check")) {
      f.classList.remove("invalid");
      const m = fmsgFor(f, false);
      setMsg(m, null);
      if (m) fieldInputs(f).forEach((i) => describe(i, m.id, false));
    }
  }
  function clearErrors() {
    $$(".invalid").forEach((el) => el.classList.remove("invalid"));
    $$(".fmsg").forEach((el) => {
      setMsg(el, null);
      if (el.id) $$(`[aria-describedby~="${el.id}"]`).forEach((i) => describe(i, el.id, false));
    });
    setMsg($("#formErr"), null);
  }
  function showErrors(errors) {
    clearErrors();
    for (const e of errors) {
      const el = document.getElementById(e.id);
      if (!el) continue;
      el.classList.add("invalid");
      const m = fmsgFor(el, true);
      setMsg(m, e.key);
      fieldInputs(el).forEach((i) => describe(i, m.id, true));
    }
    setMsg($("#formErr"), "e_fix");
    const first = document.getElementById(errors[0].id);
    if (!first) return;
    const input = first.querySelector('input:not([type="file"]), select, textarea') || first.querySelector("input");
    if (input) input.focus({ preventScroll: true });
    first.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  // ---------- network ----------
  class SendError extends Error {
    constructor(status, body) { super("send"); this.status = status; this.body = body && typeof body === "object" ? body : {}; }
  }
  const waitOnline = () => navigator.onLine === false
    ? new Promise((r) => { status("waiting_online"); addEventListener("online", r, { once: true }); })
    : Promise.resolve();

  function fetchWithTimeout(url, opts) {
    if (typeof AbortController !== "function") return fetch(url, opts);
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), SEND_TIMEOUT_MS);
    return fetch(url, { ...opts, signal: ac.signal }).finally(() => clearTimeout(timer));
  }

  function buildForm(d) {
    const fd = new FormData();
    fd.append("lang", lang);
    for (const [k, v] of Object.entries(d)) if (v) fd.append(k, v);
    fd.append("consent", "1");
    fd.append("client_ref", clientRef);
    fd.append("elapsed_ms", String(Math.round(performance.now())));
    fd.append("website", E.website.value);
    photos.forEach((p, i) => { if (p.blob) fd.append("photo", p.blob, `photo-${i + 1}.jpg`); });
    if (logo && logo.blob) fd.append("logo", logo.blob, "logo.jpg");
    return fd;
  }

  async function postApply(fd) {
    const waits = [2, 5, 10];
    for (let attempt = 0; ; attempt++) {
      await waitOnline();
      status("sending");
      let r = null, body = null;
      try {
        r = await fetchWithTimeout("/api/apply", { method: "POST", body: fd });
        body = await r.json();
      } catch { /* offline, timed out, or the answer was cut off */ }
      if (r && (r.status === 200 || r.status === 201) && body && typeof body.id === "string") return body.id;
      // A lost answer may hide a stored application. Retrying is safe: the same client_ref returns the same id.
      const retry = !r || r.status >= 500 || r.ok;
      if (!retry || attempt >= waits.length) throw new SendError(r ? r.status : 0, body);
      for (let s = waits[attempt]; s > 0; s--) { status(s === 1 ? "retrying_1" : "retrying", { s }); await sleep(1000); }
    }
  }

  // Maps a failed send to local text. Nothing typed is ever cleared here.
  function showFailure(e) {
    const st = e instanceof SendError ? e.status : 0;
    const b = e instanceof SendError ? e.body : {};
    const field = typeof b.field === "string" ? b.field : "";
    if (st === 429 && (b.code === "rate" || b.code === "busy")) return setMsg($("#formErr"), b.code === "busy" ? "e_busy" : "e_rate");
    // The logo was refused (400, 413 or 415 with field logo): it stays in its field, with what to do under it.
    if (field === "logo") return showErrors([{ id: "f-logo", key: "e_logo_server" }]);
    if (st === 413 || (st === 415 && (field === "photos" || b.code === "photo"))) return showErrors([{ id: "f-photos", key: "e_photos_server" }]);
    if (st === 400 && FIELD_MSG[field]) return showErrors([{ id: "f-" + field, key: FIELD_MSG[field] }]);
    if (st === 400) return setMsg($("#formErr"), "e_rejected", null, { post: typeof b.error === "string" && b.error ? ` (${b.error})` : "" });
    setMsg($("#formErr"), "e_send");
  }

  // ---------- submit ----------
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    if (busy) return;
    clearErrors();
    const { errors, data } = collect();
    if (errors.length) { showErrors(errors); return; }

    busy = true;
    const btn = $("#send");
    btn.disabled = true;
    fileInput.disabled = true;
    logoInput.disabled = true;
    $("#keepOpen").hidden = false;
    try {
      if (working.size) { status("preparing"); await Promise.all([...working]); }
      // A person can restore a saved draft and press send within seconds; wait so it is not taken for a bot.
      const wait = MIN_OPEN_MS - performance.now();
      if (wait > 0) { status("sending"); await sleep(wait); }
      done(await postApply(buildForm(data)));
    } catch (e) {
      status();
      showFailure(e);
      setMsg(btn, "try_again");
    } finally {
      busy = false;
      btn.disabled = false;
      fileInput.disabled = false;
      logoInput.disabled = false;
      $("#keepOpen").hidden = true;
    }
  });

  function renderRef() {
    if (refId) $("#ref").textContent = `${t("ref")}: ${refId.toUpperCase()}`;
  }
  function done(id) {
    store.del(DRAFT_KEY);
    clientRef = newRef();
    refId = id;
    renderRef();
    photos.slice().forEach(removePhoto);
    if (logo) removeLogo(logo);
    status();
    form.hidden = true;
    $("#intro").hidden = true;
    $("#done").hidden = false;
    scrollTo(0, 0);
    // The focused send button is gone now; move focus to THANK YOU so a screen reader reads it out.
    $("#doneTitle").focus({ preventScroll: true });
  }

  // ---------- start ----------
  clientRef = newRef();
  applyLang();
  loadDraft();
  echoWhatsapp();
  syncDrop();
})();

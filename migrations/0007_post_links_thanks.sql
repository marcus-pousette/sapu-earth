-- Post links and thanks on receipts (docs/upload-flow.md, Post links and thanks). Four tables and one index, each with
-- IF NOT EXISTS, so a second run changes nothing. No REFERENCES on purpose, as with logos: D1 enforces foreign keys, and
-- REJECT, UNPUBLISH, DEACTIVATE, the two undos and the housekeeping delete these rows themselves (functions/_lib/social.js).
--
-- post_links: one row per cleanup that links a post on Instagram or TikTok, where people comment.
--   crew_url  the crew's own post, pasted on its crew page with the cleanup.
--   sapu_url  Sapu Earth's post, pasted on the APPROVED card in /admin/ (a TikTok one only on @sapu.earth).
--   Both are in one stored form (postLink), NULL when there is none; a row with both NULL is deleted. The receipt shows
--   sapu_url when it is set, else crew_url while the crew is active.
-- thanks: one row per published receipt with standing thanks; n is their number.
-- thanks_days: one row per receipt and UTC day with thanks. n is that day's standing count (at most
--   THANKS.perReceiptDay). undone is how many an UNDO took off (a row with undone above 0 takes no more thanks that day).
--   last is the random mark of the request that counted the last one, so one batch moves all three counts or none.
-- thanks_site: one row per UTC day. n is the whole site's standing count that day (always the sum of that day's
--   thanks_days.n). counted is every thanks counted that day, which no undo and no UNPUBLISH lowers: the site cap
--   (THANKS.perSiteDay) is on counted, so taking thanks off never makes room for more on the same day. undone is how many
--   UNDO THE WHOLE DAY took off (a day with undone above 0 takes no more thanks).
-- Nothing about visitors: no internet address or hash of one, no time of day, no device, no words.
--
-- Additive, and the code works without it (withSocial in functions/_lib/social.js): no button and no link anywhere,
-- the crew page hides the post link field, POST /api/thanks, /api/admin/post-link and /api/admin/thanks/undo answer
-- 503 code migration, and the housekeeping counts no busy day and sweeps no link. The live code never reads these
-- tables, so this can run before or after the code; before is better.
-- Apply with: sh scripts/remote-migrate.sh --apply (ops/production-rules.md).
CREATE TABLE IF NOT EXISTS post_links (
  submission_id TEXT PRIMARY KEY,   -- submissions.id
  crew_url      TEXT,               -- the crew's own post, stored form, or NULL
  sapu_url      TEXT                -- Sapu Earth's post, stored form, or NULL
);
CREATE TABLE IF NOT EXISTS thanks (
  submission_id TEXT PRIMARY KEY,   -- submissions.id of a published receipt
  n             INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS thanks_days (
  submission_id TEXT NOT NULL,
  day           TEXT NOT NULL,      -- YYYY-MM-DD, UTC
  n             INTEGER NOT NULL DEFAULT 0,
  undone        INTEGER NOT NULL DEFAULT 0,
  last          TEXT,               -- random mark of the request that counted the last one (16 hex)
  PRIMARY KEY (submission_id, day)
);
CREATE INDEX IF NOT EXISTS thanks_days_day ON thanks_days (day);
CREATE TABLE IF NOT EXISTS thanks_site (
  day     TEXT PRIMARY KEY,         -- YYYY-MM-DD, UTC
  n       INTEGER NOT NULL DEFAULT 0,
  counted INTEGER NOT NULL DEFAULT 0,
  undone  INTEGER NOT NULL DEFAULT 0
);

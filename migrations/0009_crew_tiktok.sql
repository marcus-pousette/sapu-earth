-- A crew's own TikTok account (docs/upload-flow.md, Crew TikTok accounts). Marcus asked on 2026-11-19 that crews can add
-- their TikTok links; a link per cleanup already exists (post_links, migration 0007), so this is the crew's account,
-- one per crew. The crew sends it from its crew page (YOUR TIKTOK, POST /api/tiktok). It waits for Marcus and shows
-- nowhere until APPROVE TIKTOK in /admin/ (PARTNERS, TIKTOK TO CHECK); then /p/<slug> and /crews link it while the crew
-- is active. One row per crew that sent one:
--   live         the account sapu.earth links, as TikTok writes it after the @, in lower case (2 to 24 of a to z, 0 to
--                9, . and _; tiktokAccount in functions/_lib/tiktok.js), or NULL. Every page builds the link from it.
--   review       the account waiting for Marcus, the same way, or NULL. At most one per crew: a newer one replaces it.
--   sent_at      when review was sent (the order of TIKTOK TO CHECK and the GitHub note), NULL without review.
--   declined_at  when Marcus last declined a waiting account or removed the live one, so the crew page can say so; NULL
--                again once the crew sends another one or removes its own, or Marcus approves one.
-- A declined account is not kept (DECLINE empties review), the crew's REMOVE and DEACTIVATE delete the row, and the
-- housekeeping deletes the row of a crew that is no longer active. No REFERENCES on purpose, as with logos: D1 enforces
-- foreign keys, and the code deletes these rows itself.
--
-- Additive, and the code works without it (withTiktok in functions/_lib/tiktok.js): the crew page hides YOUR TIKTOK,
-- POST /api/tiktok and POST /api/admin/tiktok/decide answer 503 code migration, /admin/ shows no TIKTOK TO CHECK, and
-- /p/<slug> and /crews link no TikTok account. The live code never reads the table, so this can run before or after the
-- code; before is better. IF NOT EXISTS, so a second run changes nothing.
-- Apply with: sh scripts/remote-migrate.sh --apply (ops/production-rules.md).
CREATE TABLE IF NOT EXISTS crew_tiktok (
  partner_id  TEXT PRIMARY KEY,   -- partners.id
  live        TEXT CHECK (live IS NULL OR (length(live) BETWEEN 2 AND 24 AND live NOT GLOB '*[^a-z0-9._]*')),
  review      TEXT CHECK (review IS NULL OR (length(review) BETWEEN 2 AND 24 AND review NOT GLOB '*[^a-z0-9._]*')),
  sent_at     TEXT,
  declined_at TEXT
);

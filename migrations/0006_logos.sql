-- Crew logos (docs/upload-flow.md, Crew logos). One row per logo file. The file is in MEDIA, the private bucket,
-- under the same random 32 hex key: a square JPEG that the crew's phone made (toLogoJpeg, 320 px). /media/<key>
-- serves it publicly only while its row is live and its crew is active; anything else needs a signed /admin/ link.
--
-- status: review   waiting for Marcus, file kept. At most one per crew. A logo sent with an application waits
--                  here with partner_id NULL until APPROVE AND CREATE PARTNER sets it.
--         live     shown on sapu.earth next to the crew's name, file kept. At most one per crew.
--         declined no file: Marcus declined it, removed it or left it out when approving the application, or it
--                  waited 90 days without a decision. The row lets the crew page say so.
--         gone     no file: replaced by a newer logo, its crew was deactivated, or its file was missing.
-- declined and gone rows are deleted 30 days after decided_at (the housekeeping, functions/_lib/logos.js).
-- No REFERENCES on purpose: D1 enforces foreign keys, and DELETE APPLICATION, the 90-day expiry and the undo in
-- approve (which deletes the new partner) must stay able to delete their rows. functions/_lib/logos.js deletes
-- logo rows itself.
--
-- Additive, and the code works without it (withLogos in functions/_lib/logos.js): no logo shows anywhere, the crew
-- page hides YOUR LOGO, /api/apply stores an application without its logo, and LOGOS TO CHECK stays empty. So it can
-- run before or after the code; before is better. Every statement has IF NOT EXISTS, so a second run changes nothing.
-- Apply with: sh scripts/remote-migrate.sh --apply (ops/production-rules.md).
CREATE TABLE IF NOT EXISTS logos (
  key            TEXT PRIMARY KEY,   -- R2 key in MEDIA, 32 hex
  partner_id     TEXT,               -- partners.id; NULL while the logo belongs to an open application
  application_id TEXT,               -- applications.id when it came with an application, else NULL
  status         TEXT NOT NULL DEFAULT 'review' CHECK (status IN ('review', 'live', 'declined', 'gone')),
  created_at     TEXT NOT NULL,      -- when it was sent; the daily limit and the 90-day expiry count from it
  decided_at     TEXT                -- approved, declined, removed, expired, replaced or deactivated
);
CREATE UNIQUE INDEX IF NOT EXISTS logos_one_review ON logos (partner_id) WHERE status = 'review';
CREATE UNIQUE INDEX IF NOT EXISTS logos_one_live ON logos (partner_id) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS logos_partner_created ON logos (partner_id, created_at);
CREATE INDEX IF NOT EXISTS logos_application ON logos (application_id);
CREATE INDEX IF NOT EXISTS logos_status_decided ON logos (status, decided_at);

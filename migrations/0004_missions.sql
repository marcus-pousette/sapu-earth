-- Missions (docs/missions.md): a crew posts a dirty spot with its price, Sapu Earth funds it or
-- not, the crew sends the cleanup for it, and the approved cleanup closes the mission.
-- Additive only: run it BEFORE the code that uses it (docs/upload-flow.md, Missions).
-- "Now" photos are rows in uploads with kind 'before', mission_id set and submission_id NULL.
-- Expiry and photo deletes live in functions/_lib/missions.js.
-- Apply with: npx wrangler@4.149.0 d1 migrations apply sapu-earth --remote -c .dev/wrangler.toml
CREATE TABLE IF NOT EXISTS missions (
  id            TEXT PRIMARY KEY,             -- randomId(10)
  no            INTEGER NOT NULL UNIQUE,      -- short public number 1, 2, 3 ... never reused
  client_ref    TEXT UNIQUE,                  -- 32 hex from the page, idempotent retries
  partner_id    TEXT NOT NULL REFERENCES partners(id),
  status        TEXT NOT NULL DEFAULT 'review' CHECK (status IN ('review', 'open', 'funded', 'done', 'removed')),
  removed_why   TEXT,                         -- declined | cancelled | expired | withdrawn | unpublished | deactivated
  place_name    TEXT NOT NULL,
  country       TEXT,                         -- ISO2
  lat           REAL,                         -- exact; public output rounds to 3 decimals
  lng           REAL,
  task          TEXT NOT NULL,                -- what the crew will do (max 600 chars)
  plan_date     TEXT NOT NULL,                -- YYYY-MM-DD, the planned day
  crew_size     INTEGER NOT NULL,
  currency      TEXT NOT NULL,                -- 3 letters
  price_local   REAL NOT NULL,                -- what the crew asks, total
  crew_local    REAL NOT NULL,                -- of which goes to the crew members, total
  private_note  TEXT,                         -- to Marcus, never public
  consent       INTEGER NOT NULL DEFAULT 0,   -- photos may be published, everyone paid is 18+, no children in photos
  funded_eur    REAL,                         -- what Marcus agreed to pay in EUR
  advance_eur   REAL,                         -- sent at funding
  review_note   TEXT,                         -- internal
  submission_id TEXT REFERENCES submissions(id), -- the approved cleanup that completed it
  created_at    TEXT NOT NULL,
  published_at  TEXT,                         -- first time open or funded
  funded_at     TEXT,
  closed_at     TEXT                          -- done or removed
);
CREATE INDEX IF NOT EXISTS missions_status_created ON missions (status, created_at);
CREATE INDEX IF NOT EXISTS missions_partner_status ON missions (partner_id, status);
ALTER TABLE uploads ADD COLUMN mission_id TEXT REFERENCES missions(id);
ALTER TABLE submissions ADD COLUMN mission_id TEXT REFERENCES missions(id);
CREATE INDEX IF NOT EXISTS uploads_mission ON uploads (mission_id);
CREATE INDEX IF NOT EXISTS submissions_mission ON submissions (mission_id);

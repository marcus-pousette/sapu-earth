-- Sapu Earth partner upload flow, v1.
-- Apply with: npx wrangler@4.149.0 d1 migrations apply sapu-earth --remote
-- (see docs/upload-flow.md)

CREATE TABLE IF NOT EXISTS partners (
  id          TEXT PRIMARY KEY,
  slug        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  url         TEXT,
  country     TEXT,
  token_hash  TEXT NOT NULL UNIQUE,   -- SHA-256 hex of the upload token, never the token itself
  active      INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS uploads (
  key           TEXT PRIMARY KEY,     -- R2 object key, 32 hex chars
  partner_id    TEXT NOT NULL REFERENCES partners(id),
  kind          TEXT NOT NULL CHECK (kind IN ('before', 'after', 'video')),
  content_type  TEXT NOT NULL,
  size          INTEGER NOT NULL,
  created_at    TEXT NOT NULL,
  submission_id TEXT NULL REFERENCES submissions(id)
);
CREATE INDEX IF NOT EXISTS uploads_partner_created ON uploads (partner_id, created_at);
CREATE INDEX IF NOT EXISTS uploads_submission ON uploads (submission_id);

CREATE TABLE IF NOT EXISTS submissions (
  id               TEXT PRIMARY KEY,  -- 10 lowercase base32 chars
  partner_id       TEXT NOT NULL REFERENCES partners(id),
  status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at       TEXT NOT NULL,
  cleanup_date     TEXT NOT NULL,
  place_name       TEXT NOT NULL,
  country          TEXT,
  lat              REAL,
  lng              REAL,
  kg               REAL,
  sacks            INTEGER,
  crew_size        INTEGER NOT NULL,
  hours            REAL,
  currency         TEXT,
  total_cost_local REAL,
  crew_pay_local   REAL,
  disposal         TEXT,
  notes            TEXT,
  consent          INTEGER NOT NULL DEFAULT 0,
  paid_eur         REAL,
  crew_eur         REAL,
  ops_eur          REAL,
  review_note      TEXT,
  reviewed_at      TEXT
);
CREATE INDEX IF NOT EXISTS submissions_status_date ON submissions (status, cleanup_date);
CREATE INDEX IF NOT EXISTS submissions_partner ON submissions (partner_id, status);

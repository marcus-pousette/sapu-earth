-- Partner applications from sapu.earth/apply/.
-- Rejected applications are deleted, not kept. Photos are deleted once an application is decided.
-- Open applications are deleted after 90 days, and deactivating a partner wipes the contact details
-- of its application (functions/_lib/applications.js, functions/api/admin/partners/deactivate.js).
-- Apply with: npx wrangler@4.149.0 d1 migrations apply sapu-earth --remote -c .dev/wrangler.toml
CREATE TABLE IF NOT EXISTS applications (
  id           TEXT PRIMARY KEY,           -- 10 lowercase base32 chars (randomId)
  client_ref   TEXT UNIQUE,                -- random id from the browser, makes retries idempotent
  status       TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'approved')),
  lang         TEXT NOT NULL DEFAULT 'en' CHECK (lang IN ('en', 'id')),
  org_name     TEXT NOT NULL,              -- crew or group name
  contact_name TEXT NOT NULL,              -- the person we talk to
  country      TEXT NOT NULL,              -- ISO2, uppercase
  area         TEXT NOT NULL,              -- city or area where they clean
  about        TEXT NOT NULL,              -- what they clean, how often, since when
  crew_size    INTEGER,                    -- usual number of people, optional
  links        TEXT,                       -- up to 3 lines: http(s) URLs or @handles
  whatsapp     TEXT,                       -- "+" then 8 to 15 digits
  email        TEXT,
  heard_from   TEXT,
  photos       TEXT NOT NULL DEFAULT '[]', -- JSON array of R2 keys (32 hex), at most 3; '[]' once decided and deleted
  ip_hash      TEXT NOT NULL,              -- HMAC of the client IP, only for rate limiting; '' after 24 h or once decided
  partner_id   TEXT REFERENCES partners(id),
  created_at   TEXT NOT NULL,
  decided_at   TEXT
);
CREATE INDEX IF NOT EXISTS applications_status_created ON applications (status, created_at);
CREATE INDEX IF NOT EXISTS applications_ip_created ON applications (ip_hash, created_at);
CREATE INDEX IF NOT EXISTS applications_partner ON applications (partner_id);

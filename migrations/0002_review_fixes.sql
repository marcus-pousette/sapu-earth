-- Review fixes for the partner upload flow.
-- Apply with: npx wrangler@4.149.0 d1 migrations apply sapu-earth --remote -c .dev/wrangler.toml

-- A message from the partner to Sapu Earth. Shown in /admin/ only, never published.
ALTER TABLE submissions ADD COLUMN private_note TEXT;

-- 1 once the file has been copied to the public media bucket (PUBLIC_MEDIA) on approval.
ALTER TABLE uploads ADD COLUMN public INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS uploads_partner_unattached ON uploads (partner_id, submission_id, created_at);
CREATE INDEX IF NOT EXISTS submissions_partner_date ON submissions (partner_id, cleanup_date);

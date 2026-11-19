#!/bin/sh
# Applies new migrations/*.sql to the REAL Cloudflare D1 database (sapu-earth), instead of
# pasting them into the dashboard console.
#
#   sh scripts/remote-migrate.sh           list the migrations the live database does not have yet
#   sh scripts/remote-migrate.sh --apply   apply them (always before deploying code that needs them)
#
# Needs .env.cloudflare in the repo root (gitignored), with a Cloudflare API token that can only
# edit D1 (see docs/upload-flow.md, "Migrations from the command line"):
#   CLOUDFLARE_API_TOKEN=...
#   CLOUDFLARE_ACCOUNT_ID=<account id>
set -eu
cd "$(dirname "$0")/.."

[ -f .env.cloudflare ] || { echo "Missing .env.cloudflare, see docs/upload-flow.md." >&2; exit 1; }
set -a
. ./.env.cloudflare
set +a
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || { echo "CLOUDFLARE_API_TOKEN is empty in .env.cloudflare." >&2; exit 1; }
[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || { echo "CLOUDFLARE_ACCOUNT_ID is empty in .env.cloudflare." >&2; exit 1; }

# Its own config, so the local dev config (.dev/wrangler.toml) can keep a fake id.
mkdir -p .dev
CONF=.dev/wrangler.remote.toml
cat > "$CONF" <<'EOF'
name = "sapu-squad-remote"
compatibility_date = "2026-10-01"

[[d1_databases]]
binding = "DB"
database_name = "sapu-earth"
database_id = "43f287fc-c279-4edb-9b5d-10acb5953372"
migrations_dir = "../migrations"
EOF

WRANGLER="npx --yes wrangler@4.149.0"
$WRANGLER d1 migrations list sapu-earth --remote -c "$CONF"
if [ "${1:-}" = "--apply" ]; then
  $WRANGLER d1 migrations apply sapu-earth --remote -c "$CONF"
fi

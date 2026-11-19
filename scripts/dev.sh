#!/bin/sh
# Runs the whole site locally: static pages, Functions, a local D1 database and a local R2 bucket.
# Nothing here touches the real Cloudflare data (every wrangler call is --local).
#
#   sh scripts/dev.sh            serve at http://127.0.0.1:8790, data kept in .wrangler/state
#   PORT=8791 STATE=.wrangler/test-state sh scripts/dev.sh
#
# The first run writes .dev.vars (gitignored) with a random ADMIN_TOKEN for the LOCAL admin page.
# It only opens this local copy. Production has its own ADMIN_TOKEN, set in the Cloudflare dashboard.
set -eu
cd "$(dirname "$0")/.."

WRANGLER="npx --yes wrangler@4.149.0"
PORT="${PORT:-8790}"
STATE="${STATE:-.wrangler/state}"
COMPAT=2026-10-01

if [ ! -f .dev.vars ]; then
  umask 077
  printf 'ADMIN_TOKEN=%s\n' "$(openssl rand -hex 24)" > .dev.vars
  echo "Created .dev.vars with a local test ADMIN_TOKEN."
fi
TOKEN=$(sed -n 's/^ADMIN_TOKEN=//p' .dev.vars)
[ -n "$TOKEN" ] || { echo ".dev.vars has no ADMIN_TOKEN line" >&2; exit 1; }

# Local wrangler config for the migrations command. The id only names the local sqlite file.
mkdir -p .dev
if [ ! -f .dev/wrangler.toml ]; then
  cat > .dev/wrangler.toml <<EOF
name = "sapu-squad-dev"
compatibility_date = "$COMPAT"
pages_build_output_dir = "../dist"

[[d1_databases]]
binding = "DB"
database_name = "sapu-earth"
database_id = "local"
migrations_dir = "../migrations"
EOF
fi
DB_ID=$(sed -n 's/^database_id *= *"\(.*\)"/\1/p' .dev/wrangler.toml)

sh scripts/build-site.sh
$WRANGLER d1 migrations apply sapu-earth --local -c .dev/wrangler.toml --persist-to "$STATE" >/dev/null
echo "Local migrations applied ($STATE)."
echo "Admin: http://127.0.0.1:$PORT/admin/  (token is in .dev.vars)"

exec $WRANGLER pages dev dist --ip 127.0.0.1 --port "$PORT" \
  --d1 "DB=$DB_ID" --r2 MEDIA=sapu-earth-media \
  --binding "ADMIN_TOKEN=$TOKEN" \
  --persist-to "$STATE" --compatibility-date "$COMPAT"

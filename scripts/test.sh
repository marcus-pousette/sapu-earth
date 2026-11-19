#!/bin/sh
# One command test drive: starts a throwaway local copy of the site on a fresh database,
# runs tests/e2e.sh against it, then stops it. Never touches the real Cloudflare data.
#
#   sh scripts/test.sh
set -eu
cd "$(dirname "$0")/.."

PORT="${PORT:-8791}"
STATE=.wrangler/test-state
LOG=.wrangler/test-server.log
# tests/e2e.sh writes a few old applications and missions straight into this local database (the 90-day and 28-day
# expiry checks, a crew with more than 20 closed missions, missions of a deactivated crew), ages some uploads (the
# 48-hour orphan cleanup check), adds 100 mission photo rows for a moment (the 100-file quota check) and a crew's day of
# rows (the 200 files and 8 GB a day checks), ages crew logos and logo records (the logo sweep), makes a crew with post
# links inactive (the post link sweep), sets thanks to their caps, seeds a day of thanks two days back (the two undos)
# and makes a day busy for a moment (the GitHub note), and renames the applications, missions and logos tables, the
# uploads.stage column, the four tables of migration 0007 (post_links, thanks, thanks_days, thanks_site) and the
# crew_tiktok table of migration 0009 for a moment (the deploy-order checks). D1_CONFIG must be the config scripts/dev.sh
# uses, so both open the same local sqlite file.
# Everything stays --local.
export STATE D1_CONFIG=.dev/wrangler.toml
rm -rf "$STATE"
mkdir -p .wrangler

PORT=$PORT STATE=$STATE sh scripts/dev.sh > "$LOG" 2>&1 &
SERVER=$!
cleanup() {
  pkill -P "$SERVER" 2>/dev/null || true
  kill "$SERVER" 2>/dev/null || true
  pkill -f "wrangler.*pages dev dist.*--port $PORT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
until curl -s -o /dev/null "http://127.0.0.1:$PORT/"; do
  i=$((i+1))
  if [ $i -gt 90 ] || ! kill -0 "$SERVER" 2>/dev/null; then
    echo "Local server did not start. Last lines of $LOG:" >&2
    tail -20 "$LOG" >&2
    exit 1
  fi
  sleep 1
done

B="http://127.0.0.1:$PORT" bash tests/e2e.sh || { echo "Server log (errors from the Functions): $LOG" >&2; exit 1; }

#!/bin/bash
# End-to-end test of the partner upload flow against a LOCAL server (sh scripts/dev.sh).
# Easiest: sh scripts/test.sh, which starts a fresh local server, runs this and stops it.
#
#   B=http://127.0.0.1:8790 bash tests/e2e.sh
#   B=http://127.0.0.1:8790 STATE=.wrangler/state bash tests/e2e.sh   (also the checks that need the database)
#
# Creates a partner, uploads photos and a video, submits, approves, checks every public page and
# the names files download under, sends a cleanup with 30 videos before and 30 after (stages; a 31st of a stage and a
# 61st video refused, the receipt and PENDING in upload order within each stage), then rejects, rotates and deactivates. Then sends crew applications to /api/apply, approves one,
# rejects one, hits the rate limit (per address, IPv6 per /64), checks how WhatsApp numbers are
# cleaned up and that deactivating a partner wipes its contact details. Then missions: three crews
# post missions, the admin publishes, funds, declines, removes and cancels them, a cleanup is sent
# for a funded mission and approved (the mission is done), a cleanup sent without a mission is
# linked to one on APPROVE, DEACTIVATE removes waiting, open and funded missions, every removal
# wipes the private note and the exact point, and the public pages follow along. A fourth crew posts
# a mission with a video of the spot, which goes everywhere its photos go and is deleted with them.
# Then crew logos, and the list of crews at /crews: who is on it (every active crew: those with an approved cleanup or a
# mission that is funded or open on sapu.earth on top, the others under JUST JOINED), its numbers against the receipts,
# the country chips, the order, NEXT UP on /p/<slug>, the links to it, and that nothing private ever shows there. And
# crew TikTok accounts: a crew's own account sent from its crew page, checked in /admin/ (TIKTOK TO CHECK), linked on
# /p/<slug> and /crews, every way it comes off, and the link preview of /p/<slug> (the logo before a receipt photo). And
# the list of missions at /missions: its open and funded missions against /api/missions, its cleaned ones against the
# receipts, the state chips and filters, the order, the 28 days of an open mission, and that nothing private shows there
# either; and that the page Functions answer HEAD as GET, without the page. Then post links: a crew's link to its own
# post on Instagram or TikTok sent with a cleanup, Sapu Earth's own on the APPROVED card, which one the receipt shows,
# short links and other links refused, and every way a link comes off (REMOVE, REMOVE CREW LINK, REJECT, UNPUBLISH,
# DEACTIVATE, the sweep).
# Then thanks: SAY TERIMA KASIH counted through POST /api/thanks only from a page of this site, nothing about the
# visitor, the counts on the receipts, /p/<slug>, /crews, the crew page and THANKS BY DAY, UNPUBLISH taking a receipt's
# thanks, and the GitHub note's busy days.
# With STATE (the server's --persist-to folder, scripts/test.sh sets it) it also writes old
# applications, missions and uploads straight into the LOCAL D1 file to check the 90-day and 28-day
# expiry, the 48-hour orphan cleanup, the 100-file quota, a crew's day (200 files, 8 GB), the mission list of a crew with many
# missions and the missions of a deactivated crew, sets thanks to their caps, seeds a day of thanks two days back for
# the two undos and makes a day busy for a moment, and renames the applications and missions tables,
# the uploads.stage column, the logos table and the four tables of migration 0007 (post_links, thanks, thanks_days,
# thanks_site) for a moment to check that the site still works before migrations 0003, 0004, 0005, 0006 and 0007.
# At the end, missions with several spots (docs/missions.md, Spots): the UPDATE that adds a spot, every place where the
# spots show, each spot's photos and day on the crew page and the APIs, PENDING, APPROVE and the receipt, LATE from the
# last day, the biggest cleanup there is (4 spots, 32 photos and 60 videos, 92 files, sent, approved and unpublished),
# and the three columns of migration 0008 renamed for a moment. /apply/ asks no head count (2026-11-17).
# Exits non-zero if any check fails.
set -u
cd "$(dirname "$0")/.."

B=${B:-http://127.0.0.1:8790}
case "$B" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing to run against $B. This test writes data, so it only runs against a local server." >&2; exit 2 ;;
esac
TOKEN=$(sed -n 's/^ADMIN_TOKEN=//p' .dev.vars 2>/dev/null)
[ -n "$TOKEN" ] || { echo "No ADMIN_TOKEN in .dev.vars. Run sh scripts/dev.sh once first." >&2; exit 2; }
A="Authorization: Bearer $TOKEN"
STATE=${STATE:-}
D1_CONFIG=${D1_CONFIG:-.dev/wrangler.toml}

F=tests/fixtures
T=$(mktemp -d)
RENAMED=
MRENAMED=
SRENAMED=
LRENAMED=
PRENAMED=
PSRENAMED=
TRENAMED=
finish() {
  # Never leave the local database without its applications, missions or logos table, or uploads without its
  # stage column, even after Ctrl-C.
  if [ -n "$RENAMED" ]; then
    d1 "ALTER TABLE applications_e2e_off RENAME TO applications" >/dev/null \
      || echo "Could not rename applications_e2e_off back to applications in $STATE. Delete that folder." >&2
  fi
  if [ -n "$MRENAMED" ]; then
    d1 "ALTER TABLE missions_e2e_off RENAME TO missions" >/dev/null \
      || echo "Could not rename missions_e2e_off back to missions in $STATE. Delete that folder." >&2
  fi
  if [ -n "$SRENAMED" ]; then
    d1 "ALTER TABLE uploads RENAME COLUMN stage_e2e_off TO stage" >/dev/null \
      || echo "Could not rename uploads.stage_e2e_off back to stage in $STATE. Delete that folder." >&2
  fi
  if [ -n "$LRENAMED" ]; then
    d1 "ALTER TABLE logos_e2e_off RENAME TO logos" >/dev/null \
      || echo "Could not rename logos_e2e_off back to logos in $STATE. Delete that folder." >&2
  fi
  if [ -n "$PRENAMED" ]; then
    son >/dev/null || echo "Could not rename the tables of migration 0007 (*_e2e_off) back in $STATE. Delete that folder." >&2
  fi
  if [ -n "$PSRENAMED" ]; then
    d1 "ALTER TABLE missions RENAME COLUMN spots_e2e_off TO spots; ALTER TABLE submissions RENAME COLUMN spots_e2e_off TO spots; ALTER TABLE uploads RENAME COLUMN spot_e2e_off TO spot" >/dev/null \
      || echo "Could not rename the columns of migration 0008 (*_e2e_off) back in $STATE. Delete that folder." >&2
  fi
  if [ -n "$TRENAMED" ]; then
    d1 "ALTER TABLE crew_tiktok_e2e_off RENAME TO crew_tiktok" >/dev/null \
      || echo "Could not rename crew_tiktok_e2e_off back to crew_tiktok in $STATE. Delete that folder." >&2
  fi
  rm -rf "$T"
}
trap finish EXIT
printf 'not really a jpeg!!' > "$T/fake.jpg"
head -c 16000000 /dev/zero > "$T/big.bin"
python3 - "$F/before.jpg" "$T/exif.jpg" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
seg = b"Exif\x00\x00" + b"MM\x00\x2a\x00\x00\x00\x08" + b"\x00" * 16
open(sys.argv[2], "wb").write(b[:2] + b"\xff\xe1" + (len(seg) + 2).to_bytes(2, "big") + seg + b[2:])
PY
# A canvas JPEG as Safari and every iPhone browser (WebKit) write it: after the JFIF header come a small Exif block
# (colour space and size, no GPS) and a Photoshop block, bytes copied from a real WebKit canvas JPEG. The ICC
# variant also carries a colour profile segment (APP2 ICC_PROFILE), which the pages must keep.
python3 - "$F/before.jpg" "$T/webkit.jpg" "$T/webkit-icc.jpg" "$T/before-icc.jpg" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
app1 = bytes.fromhex("ffe1004c4578696600004d4d002a00000008000187690004000000010000001a000000000003a00100030000000100010000a002000400000001000004b0a0030004000000010000038400000000")
app13 = bytes.fromhex("ffed003850686f746f73686f7020332e30003842494d04040000000000003842494d0425000000000010d41d8cd98f00b204e9800998ecf8427e")
icc = b"ICC_PROFILE\x00\x01\x01" + b"\x00" * 32
app2 = b"\xff\xe2" + (len(icc) + 2).to_bytes(2, "big") + icc
assert b[2:4] == b"\xff\xe0"
n = 4 + ((b[4] << 8) | b[5])  # end of the JFIF segment
open(sys.argv[2], "wb").write(b[:n] + app1 + app13 + b[n:])
open(sys.argv[3], "wb").write(b[:n] + app2 + app1 + app13 + b[n:])
open(sys.argv[4], "wb").write(b[:n] + app2 + b[n:])
PY
# Crew logos (logoJpegInfo in functions/_lib/logos.js): before.jpg made square in its header. The server never decodes
# a picture, so a patched size is enough. Taken: logo.jpg (its COM segment stays: cleanJpeg keeps comments) and
# logo-icc.jpg (a colour profile). logo-webkit.jpg carries WebKit's blocks: refused as it is, taken after cleanJpeg.
# Refused ($LOGO_BAD): camera data, XMP, the Photoshop block, a second APP0, bytes after the image (zeros, an Exif
# block with a new end marker, a whole second JPEG), an APP1 after the scan (also in a progressive frame), a picture
# that is not square, too small or too big, another kind of JPEG (SOF3). logo-heavy.jpg is over 150 KB. logo-scans.jpg
# (a table and a second scan after the first one, then the end) is taken by the node check below.
python3 - "$F/before.jpg" "$T" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); out = sys.argv[2]
def seg(m, payload): return b"\xff" + bytes([m]) + (len(payload) + 2).to_bytes(2, "big") + payload
def sof_at(x):
    i = 2
    while x[i + 1] != 0xc0: i += 2 + ((x[i + 2] << 8) | x[i + 3])
    return i
def sized(x, w, h):
    x = bytearray(x); i = sof_at(x) + 5
    x[i:i + 2] = h.to_bytes(2, "big"); x[i + 2:i + 4] = w.to_bytes(2, "big")
    return bytes(x)
logo = sized(b, 320, 320)
assert logo[2:4] == b"\xff\xe0"
n = 4 + ((logo[4] << 8) | logo[5])  # end of the JFIF segment
plus = lambda extra: logo[:n] + extra + logo[n:]
app1 = bytes.fromhex("ffe1004c4578696600004d4d002a00000008000187690004000000010000001a000000000003a00100030000000100010000a002000400000001000004b0a0030004000000010000038400000000")
app13 = bytes.fromhex("ffed003850686f746f73686f7020332e30003842494d04040000000000003842494d0425000000000010d41d8cd98f00b204e9800998ecf8427e")
sof3 = bytearray(logo); sof3[sof_at(logo) + 1] = 0xc3
sof2 = bytearray(logo); sof2[sof_at(logo) + 1] = 0xc2
def seg_at(x, m):
    i = 2
    while x[i + 1] != m: i += 2 + ((x[i + 2] << 8) | x[i + 3])
    return i
sos, dht = seg_at(logo, 0xda), seg_at(logo, 0xc4)
dht_seg = logo[dht:dht + 2 + ((logo[dht + 2] << 8) | logo[dht + 3])]
gps = seg(0xe1, b"Exif\x00\x00MM\x00\x2a\x00\x00\x00\x08" + b"GPS 47.2692N 11.4041E" + b"\x00" * 8)
files = {
  "logo.jpg": logo,
  "logo-icc.jpg": plus(seg(0xe2, b"ICC_PROFILE\x00\x01\x01" + b"\x00" * 32)),
  "logo-webkit.jpg": plus(app1 + app13),
  "logo-exif.jpg": plus(seg(0xe1, b"Exif\x00\x00MM\x00\x2a\x00\x00\x00\x08" + b"\x00" * 16)),
  "logo-xmp.jpg": plus(seg(0xe1, b"http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta/>")),
  "logo-app13.jpg": plus(app13),
  "logo-jfxx.jpg": plus(seg(0xe0, b"JFXX\x00\x10" + b"\x00" * 8)),
  "logo-tail.jpg": logo + b"\x00" * 32,
  "logo-exif-after.jpg": logo + gps + b"\xff\xd9",
  "logo-two.jpg": logo + b,
  "logo-scan-app1.jpg": logo[:-2] + gps + b"\xff\xd9",
  "logo-sof2-app1.jpg": bytes(sof2)[:-2] + gps + b"\xff\xd9",
  "logo-scans.jpg": logo[:-2] + dht_seg + logo[sos:],
  "logo-wide.jpg": sized(b, 400, 320),
  "logo-small.jpg": sized(b, 100, 100),
  "logo-big.jpg": sized(b, 1000, 1000),
  "logo-sof3.jpg": bytes(sof3),
  "logo-heavy.jpg": plus(seg(0xe2, b"ICC_PROFILE\x00\x01\x03" + b"\x00" * 59982) * 3),
}
for name, data in files.items(): open(out + "/" + name, "wb").write(data)
PY
LOGO_BAD="logo-exif logo-xmp logo-app13 logo-jfxx logo-tail logo-exif-after logo-two logo-scan-app1 logo-sof2-app1 logo-wide logo-small logo-big logo-sof3"

PASS=0; FAIL=0
ok()    { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()   { echo "FAIL  $1  :: $2"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
code()  { curl -s -o /dev/null -w '%{http_code}' "$@"; }
jget()  { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1" 2>/dev/null; }
size()  { wc -c < "$1" | tr -d ' '; }
# SQL on the LOCAL D1 database of the server under test (--local, never the real one). Prints JSON,
# one entry per statement. Only used when STATE is set.
d1()    { npx --yes wrangler@4.149.0 d1 execute sapu-earth --local -c "$D1_CONFIG" --persist-to "$STATE" --json --command "$1" 2>"$T/d1.err"; }
# soff and son: the four tables of migration 0007 renamed to <name>_e2e_off for the deploy-order checks, and back.
SOCIAL_TABLES="post_links thanks thanks_days thanks_site"
soff()  { d1 "$(for t in $SOCIAL_TABLES; do printf 'ALTER TABLE %s RENAME TO %s_e2e_off; ' "$t" "$t"; done)"; }
son()   { d1 "$(for t in $SOCIAL_TABLES; do printf 'ALTER TABLE %s_e2e_off RENAME TO %s; ' "$t" "$t"; done)"; }
# Last change time (ns) of the local R2 blob folder: any photo written or deleted changes it,
# so a request that must not touch R2 leaves it equal. Only used when STATE is set.
r2mt()  { python3 -c "import os,sys;print(os.stat(sys.argv[1]).st_mtime_ns)" "$STATE/v3/r2/sapu-earth-media/blobs" 2>/dev/null; }
# hsig <key>: a signed /media/ link made here with the local ADMIN_TOKEN, the way /admin/ gets them. It
# opens any file still in R2, row or no row, so it shows that the file itself is gone.
hsig()  { HK_TOKEN=$TOKEN python3 -c "
import hashlib,hmac,os,sys,time
k=sys.argv[1];e=str(int(time.time())+600)
print('/media/%s?exp=%s&sig=%s'%(k,e,hmac.new(os.environ['HK_TOKEN'].encode(),(k+'.'+e).encode(),hashlib.sha256).hexdigest()))" "$1"; }
# n_up <key>: how many uploads rows have this key (0 or 1).
n_up()  { d1 "SELECT COUNT(*) AS n FROM uploads WHERE key = '$1'" | jget "d[0]['results'][0]['n']"; }
# Text with <XXXX> placeholders (hex code points) turned into those characters, so this file
# holds no invisible characters itself.
uni()   { python3 -c "import re,sys;print(re.sub(r'<([0-9a-f]{4})>', lambda m: chr(int(m.group(1), 16)), sys.argv[1]), end='')" "$1"; }
# The list of crews (/crews). cxpage [query]: GET /crews (with ?<query>), prints the status, the page goes to $T/cx.html.
# cxq <expr>: a Python expression over the cards of $T/cx.html: cards (the crews with something public on sapu.earth, each
# with slug, cleanups, kg, sacks and paid from its data- attributes, and its html), card(slug) the one with that slug or
# None, at(slug) its place in that list or -1; new, jj(slug) and jat(slug) the same for the JUST JOINED cards (slug and
# html only: they carry no numbers); page the whole page.
cxpage() { curl -s -o "$T/cx.html" -w '%{http_code}' "$B/crews${1:+?$1}"; }
cxq()   { python3 -c '
import re,sys
page=open(sys.argv[1],encoding="utf-8").read()
cards=[dict(slug=m.group(1),cleanups=float(m.group(2)),kg=float(m.group(3)),sacks=float(m.group(4)),paid=float(m.group(5)),html=m.group(6))
       for m in re.finditer(r"<li class=\"cx-card\" data-slug=\"([^\"]*)\" data-cleanups=\"([^\"]*)\" data-kg=\"([^\"]*)\" data-sacks=\"([^\"]*)\" data-paid=\"([^\"]*)\">(.*?)\n    </li>",page,re.S)]
new=[dict(slug=m.group(1),html=m.group(2)) for m in re.finditer(r"<li class=\"cx-card cx-new\" data-slug=\"([^\"]*)\">(.*?)\n    </li>",page,re.S)]
card=lambda s:([c for c in cards if c["slug"]==s] or [None])[0]
at=lambda s:([i for i,c in enumerate(cards) if c["slug"]==s] or [-1])[0]
jj=lambda s:([c for c in new if c["slug"]==s] or [None])[0]
jat=lambda s:([i for i,c in enumerate(new) if c["slug"]==s] or [-1])[0]
print(eval(sys.argv[2]))' "$T/cx.html" "$1" 2>/dev/null; }
# dday <YYYY-MM-DD>: the day as /crews and /p/<slug> write it, "14 Nov 2026" (the same call as fmtDay in _lib/crews.js).
dday()  { node -e 'console.log(new Date(Date.parse(process.argv[1] + "T00:00:00Z")).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }))' "$1"; }
# ddnb <YYYY-MM-DD>: the same day as a line on /crews or NEXT UP has it, "14&nbsp;Nov&nbsp;2026" (it never breaks there).
ddnb()  { dday "$1" | sed 's/ /\&nbsp;/g'; }
# The list of missions (/missions). mxpage [query]: GET /missions (with ?<query>), prints the status, the page goes to
# $T/mx.html. mxq <expr>: a Python expression over the cards of $T/mx.html: cards (each with no, kind and its html, in
# page order), card(no) the one with that number or None, at(no) its place in the list or -1, kinds the kinds in page
# order, page the whole page (re is imported).
mxpage() { curl -s -o "$T/mx.html" -w '%{http_code}' "$B/missions${1:+?$1}"; }
mxq()   { python3 -c '
import re,sys
page=open(sys.argv[1],encoding="utf-8").read()
cards=[dict(no=int(m.group(1)),kind=m.group(2),html=m.group(3))
       for m in re.finditer(r"<li class=\"cx-card mx-card\" id=\"m-(\d+)\" data-no=\"\1\" data-kind=\"(open|funded|cleaned)\">(.*?)\n    </li>",page,re.S)]
card=lambda n:([c for c in cards if c["no"]==int(n)] or [None])[0]
at=lambda n:([i for i,c in enumerate(cards) if c["no"]==int(n)] or [-1])[0]
kinds=[c["kind"] for c in cards]
print(eval(sys.argv[2]))' "$T/mx.html" "$1" 2>/dev/null; }

check "server is up" "$(code $B/)" 200
# The list of crews on a fresh database (docs/upload-flow.md, The list of crews): no crew is active yet, so /crews says so,
# noindex, with its own description, no card, no JUST JOINED, no HOW THIS LIST WORKS, never a sample crew and never that
# crews are joining.
st=$(cxpage)
if grep -qE 'class="cx-card( cx-new)?"' "$T/cx.html"; then
  echo "NOTE  this server already lists crews, so the empty /crews is not checked (sh scripts/test.sh starts on a fresh database)"
else
  [ "$st" = 200 ] && grep -qF '<h2 class="panel-title">NO CREW IS LISTED YET</h2>' "$T/cx.html" \
    && grep -qF '<p>A crew shows up here as soon as it works with Sapu Earth.</p>' "$T/cx.html" \
    && grep -qF '<meta name="description" content="The local cleanup crews on Sapu Earth. No crew is listed yet.">' "$T/cx.html" \
    && grep -qF '<meta property="og:description" content="The local cleanup crews on Sapu Earth. No crew is listed yet.">' "$T/cx.html" \
    && grep -qF '<meta name="robots" content="noindex">' "$T/cx.html" && ! grep -qiE 'sample|joining|just joined|cx-new|cx-how|cx-chips' "$T/cx.html" \
    && grep -qF '<a class="btn btn-apply" href="/apply/">APPLY AS A CREW →</a>' "$T/cx.html" \
    && grep -qF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a></p>' "$T/cx.html" && ! grep -qF 'href="/missions"' "$T/cx.html" \
    && ok "/crews on a fresh database: 200, NO CREW IS LISTED YET with a description that says so, noindex, no card, no sample crew, nothing about crews joining, the way to apply, SEE THE GLOBE alone at the foot (no ALL MISSIONS)" \
    || bad "/crews before any crew is listed" "$st $(head -c 3000 "$T/cx.html")"
fi
# The list of missions on a fresh database (docs/upload-flow.md, The list of missions): no mission is listed yet, so
# /missions says so, noindex, with its own description, no card, no chips, no HOW THIS LIST WORKS, no ALL CREWS, no
# picture and never a sample mission, and it tells visitors (Instagram) and crews already with us what to do.
st=$(mxpage)
if grep -qF 'class="cx-card mx-card"' "$T/mx.html"; then
  echo "NOTE  this server already lists missions, so the empty /missions is not checked (sh scripts/test.sh starts on a fresh database)"
else
  [ "$st" = 200 ] && grep -qF '<h2 class="panel-title">NO MISSION IS LISTED YET</h2>' "$T/mx.html" \
    && grep -qF '<p>A mission is a spot a local crew wants to clean, with the day and the price. It shows up here once Sapu Earth publishes or funds it: open while it waits for funding, then funded, then cleaned, with its receipt.</p>' "$T/mx.html" \
    && grep -qF '<p class="cx-last"><a href="https://www.instagram.com/sapu.earth" rel="noopener"><span>FOLLOW ALONG ON INSTAGRAM</span> ↗</a></p>' "$T/mx.html" \
    && grep -qF '<p class="hint">Already a crew with us? Post a mission on your crew page: open the private link from our WhatsApp or email message.</p>' "$T/mx.html" \
    && grep -qF '<meta name="description" content="The cleanup missions on Sapu Earth. No mission is listed yet.">' "$T/mx.html" \
    && grep -qF '<meta property="og:description" content="The cleanup missions on Sapu Earth. No mission is listed yet.">' "$T/mx.html" \
    && grep -qF '<meta name="robots" content="noindex">' "$T/mx.html" && ! grep -qiE 'sample|mx-card|cx-chips|cx-how|ALL CREWS|<img' "$T/mx.html" \
    && grep -qF '<a class="btn btn-apply" href="/apply/">APPLY AS A CREW →</a>' "$T/mx.html" \
    && grep -qF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a></p>' "$T/mx.html" \
    && ok "/missions on a fresh database: 200, NO MISSION IS LISTED YET with a description that says so, noindex, no card, chips or HOW THIS LIST WORKS, no sample mission and no picture, FOLLOW ALONG ON INSTAGRAM, the line for crews already with us, the way to apply, SEE THE GLOBE alone at the foot (no ALL CREWS)" \
    || bad "/missions before any mission is listed" "$st $(head -c 3000 "$T/mx.html")"
fi

SLUG="crew-$RANDOM$RANDOM"
P=$(curl -s -X POST $B/api/admin/partners -H "$A" -H 'content-type: application/json' \
  -d "{\"name\":\"Kali Bersih <b>Crew</b>\",\"url\":\"https://example.org\",\"country\":\"ID\",\"slug\":\"$SLUG\"}")
TOK=$(echo "$P" | jget "d['token']"); PID=$(echo "$P" | jget "d['id']")
[ ${#TOK} -eq 43 ] && ok "create partner returns 43-char token" || bad "create partner" "$P"
echo "$P" | grep -q "/upload/?k=$TOK" && ok "create partner returns upload link" || bad "upload link" "$P"
check "duplicate slug -> 409" "$(code -X POST $B/api/admin/partners -H "$A" -H 'content-type: application/json' -d "{\"name\":\"x\",\"country\":\"ID\",\"slug\":\"$SLUG\"}")" 409
check "admin without token -> 401" "$(code $B/api/admin/partners)" 401
check "admin wrong token -> 401" "$(code $B/api/admin/partners -H 'Authorization: Bearer nope')" 401
curl -s $B/api/admin/partners -H "$A" | grep -q token_hash && bad "partner list leaks token_hash" "" || ok "partner list has no token_hash"

check "GET /api/partner valid" "$(curl -s "$B/api/partner?k=$TOK" | jget "d['slug']")" "$SLUG"
# Every active crew is on /crews from the day it is made (docs/upload-flow.md, The list of crews): this one, made with
# NEW PARTNER a moment ago and with nothing on sapu.earth yet, is under JUST JOINED, and GET /api/partner says listed.
st=$(cxpage)
check "a crew made with NEW PARTNER a moment ago: /crews -> 200 with it under JUST JOINED (not among the crews with something public), indexed, with the description and the line under the title for a list of crews that all just joined (on a fresh database), and GET /api/partner listed true at once" \
  "$st $(cxq "(card('$SLUG'), jj('$SLUG') is not None, 'name=\"robots\"' in page, len(cards) > 0 or ('<meta name=\"description\" content=\"The local cleanup crews on Sapu Earth. The crews listed so far just joined, and their first missions are coming.\">' in page and '<p class=\"sub\">// local cleanup crews on sapu.earth. the crews listed so far just joined.</p>' in page and 'the totals add up' not in page))") $(curl -s "$B/api/partner?k=$TOK" | jget "d.get('listed')")" \
  "200 (None, True, False, True) True"
# /crews links its page from the first day, so before its first receipt the page shows no row of zeros.
PJJ=$(curl -s $B/p/$SLUG)
! echo "$PJJ" | grep -qE 'fp-stats|<span>kg removed</span>' && echo "$PJJ" | grep -qF '<p class="hint">No published cleanups yet.</p>' \
  && [ "$(echo "$PJJ" | grep -c 'og:image"')" = 1 ] && echo "$PJJ" | grep -qF "<meta property=\"og:image\" content=\"$B/site/social/sapu-earth-mark.png\">" \
  && echo "$PJJ" | grep -qF '<meta name="twitter:card" content="summary">' \
  && ok "/p/<slug> of that crew before its first receipt: no numbers (no 0 kg removed, 0 cleanups, 0 sacks), THE RECEIPTS says No published cleanups yet., and with no logo either its link preview is the broom (a small card)" \
  || bad "/p/<slug> before the first receipt" "$(echo "$PJJ" | grep -n -E 'fp-stats|stat|RECEIPTS|No published|og:image|twitter')"
check "GET /api/partner invalid token -> 404" "$(code "$B/api/partner?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")" 404
check "upload with invalid token -> 404" "$(code -X POST "$B/api/upload?k=bad&kind=before" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)" 404

up() { curl -s -X POST "$B/api/upload?k=$TOK&kind=$1" -H "content-type: $2" --data-binary @$3 | jget "d['key']"; }
KB=$(up before image/jpeg $F/before.jpg); KA=$(up after image/jpeg $F/after.jpg); KV=$(up video video/mp4 $F/tiny.mp4)
[[ $KB =~ ^[0-9a-f]{32}$ && $KA =~ ^[0-9a-f]{32}$ && $KV =~ ^[0-9a-f]{32}$ ]] && ok "upload 2 JPEGs + MP4 -> hex keys" || bad "uploads" "$KB $KA $KV"

check "wrong magic bytes -> 415" "$(code -X POST "$B/api/upload?k=$TOK&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/fake.jpg)" 415
check "JPEG with camera data (Exif) -> 415" "$(code -X POST "$B/api/upload?k=$TOK&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/exif.jpg)" 415
check "video type for photo kind -> 415" "$(code -X POST "$B/api/upload?k=$TOK&kind=before" -H 'content-type: video/mp4' --data-binary @$F/tiny.mp4)" 415
check "jpeg sent as kind=video -> 415" "$(code -X POST "$B/api/upload?k=$TOK&kind=video" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)" 415
check "text/html upload -> 415" "$(code -X POST "$B/api/upload?k=$TOK&kind=after" -H 'content-type: text/html' --data-binary @$T/fake.jpg)" 415
check "oversized photo (16 MB) -> 413" "$(code -X POST "$B/api/upload?k=$TOK&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/big.bin)" 413
check "bad kind -> 400" "$(code -X POST "$B/api/upload?k=$TOK&kind=selfie" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)" 400
# The cleanup's videos before and after go up with their stage (uploads.stage, migration 0005). Only a
# video has one, and only before or after. upv <token> [stage]: uploads tiny.mp4 as a video, prints the key.
upv() { curl -s -X POST "$B/api/upload?k=$1&kind=video${2:+&stage=$2}" -H 'content-type: video/mp4' --data-binary @$F/tiny.mp4 | jget "d['key']"; }
KSA=$(upv $TOK after); KSB=$(upv $TOK before)
[[ $KSA =~ ^[0-9a-f]{32}$ && $KSB =~ ^[0-9a-f]{32}$ ]] && ok "a video with stage=after and one with stage=before -> hex keys" || bad "staged video uploads" "$KSA $KSB"
check "a stage on a photo, an unknown stage -> 400 400" \
  "$(code -X POST "$B/api/upload?k=$TOK&kind=before&stage=before" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg) $(code -X POST "$B/api/upload?k=$TOK&kind=video&stage=now" -H 'content-type: video/mp4' --data-binary @$F/tiny.mp4)" "400 400"

check "unsent upload is not public" "$(code $B/media/$KB)" 404

XSS='<img src=x onerror=alert(1)> "Kali" & co'
body() { python3 -c "
import json,sys
print(json.dumps({'cleanup_date':sys.argv[1],'place_name':sys.argv[2],'country':'ID','lat':-7.2575,'lng':112.7521,
 'kg':120.5,'sacks':14,'crew_size':6,'hours':4,'currency':'IDR','total_cost_local':1500000,'crew_pay_local':900000,
 'disposal':'Bank sampah','notes':'Line one\nline two','private_note':'PRIVATE-NOTE-123','consent':True,
 'media':sys.argv[3].split(',')}))" "$@"; }
TODAY=$(date -u +%F)
check "submit without consent -> 400" "$(code -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Place $KB,$KA | sed 's/"consent": true/"consent": false/')")" 400
check "submit future date -> 400" "$(code -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body 2099-01-01 Place $KB,$KA)")" 400
check "submit only before photo -> 400" "$(code -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Place $KB)")" 400
LONG=$(python3 -c "print('x'*121)")
check "submit place > 120 chars -> 400" "$(code -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY $LONG $KB,$KA)")" 400
SUB=$(curl -s -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY "$XSS" $KB,$KA,$KV)")
ID=$(echo "$SUB" | jget "d['id']")
[[ $ID =~ ^[a-z2-7]{10}$ ]] && ok "submit -> 10-char id ($ID)" || bad "submit" "$SUB"
check "re-using attached media -> 400" "$(code -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Again $KB,$KA)")" 400
# The crew page adds the crew's pay into the total cost; a page from before that (a tab kept open) could send a crew pay
# above the total. The guard answers 400 on crew_pay_local before the files are looked at: these two are attached
# already, so only the guard names that field.
check "submit with crew pay above the total -> 400 (crew_pay_local)" \
  "$(curl -s -o "$T/cp.json" -w '%{http_code}' -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Place $KB,$KA | sed 's/"crew_pay_local": 900000/"crew_pay_local": 1600000/')") $(jget "d.get('field')" < "$T/cp.json")" \
  "400 crew_pay_local"

PEND=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A")
echo "$PEND" | python3 -c "import json,sys;d=json.load(sys.stdin);s=[x for x in d['submissions'] if x['id']=='$ID'][0];assert len(s['media']['before'])==1 and len(s['media']['videos'])==1" 2>/dev/null \
  && ok "pending list contains submission with media" || bad "pending list" "$PEND"
check "events hides pending" "$(curl -s $B/api/events | grep -c $ID)" 0
check "/r/<pending id> -> 404" "$(code $B/r/$ID)" 404
check "pending media is not public" "$(code $B/media/$KB)" 404
signed() { python3 -c "import json,sys;d=json.load(sys.stdin);s=[x for x in d['submissions'] if x['id']==sys.argv[1]][0];print(s['media'][sys.argv[2]][0]['url'])" "$1" "$2" 2>/dev/null; }
SIG=$(echo "$PEND" | signed $ID before)
curl -s "$B$SIG" -o $T/rt.jpg; cmp -s $T/rt.jpg $F/before.jpg && ok "admin signed link returns the exact pending photo" || bad "signed link" "$SIG"
curl -s -D - -o /dev/null "$B$SIG" | grep -qi 'cache-control: private, no-store' && ok "signed media is never cached" || bad "signed cache-control" ""
check "tampered signature -> 404" "$(code "$B${SIG%%&sig=*}&sig=0000000000000000000000000000000000000000000000000000000000000000")" 404

DEC=$(curl -s -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' \
  -d "{\"id\":\"$ID\",\"action\":\"approve\",\"paid_eur\":95,\"crew_eur\":55,\"ops_eur\":40,\"review_note\":\"REVIEW-NOTE-456\",\"edits\":{\"kg\":118}}")
check "approve" "$(echo "$DEC" | jget "d['status']")" approved
# A crew listed by a cleanup sent with No mission alone (docs/upload-flow.md, The list of crews): on a fresh database the
# list of missions is still empty, so the foot of /crews has SEE THE GLOBE alone, never ALL MISSIONS to NO MISSION IS
# LISTED YET (missionsListed, the rule of THE MISSIONS in the homepage footer).
cxpage >/dev/null; mxpage >/dev/null
if grep -qF 'class="cx-card mx-card"' "$T/mx.html"; then
  echo "NOTE  this server already lists missions, so /crews with a crew listed by a plain cleanup alone is not checked (sh scripts/test.sh starts on a fresh database)"
else
  check "/crews with a crew listed by a cleanup sent with No mission, while /missions lists nothing: its card, and SEE THE GLOBE alone at the foot, no link to /missions" \
    "$(cxq "card('$SLUG') is not None") $(grep -cF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a></p>' "$T/cx.html") $(grep -c 'href="/missions' "$T/cx.html") $(grep -c '<h2 class="panel-title">NO MISSION IS LISTED YET</h2>' "$T/mx.html")" \
    "True 1 0 1"
fi

EV=$(curl -s -D $T/ev.h $B/api/events)
echo "$EV" | python3 -c "
import json,sys
e=[x for x in json.load(sys.stdin) if x['id']=='$ID'][0]
assert e['money']=={'paid_eur':95,'crew_eur':55,'ops_eur':40}, e['money']
assert e['result']['kg_estimate']==118
assert e['media']['before']==['/media/$KB'] and e['media']['after']==['/media/$KA'] and e['media']['videos']==['/media/$KV']
assert e['media']['video_stages']==[None], e['media']
assert e['provider']['slug']=='$SLUG' and e['local_money']['currency']=='IDR'
" 2>/dev/null && ok "/api/events shows approved event with money + media URLs, the video sent without a stage unlabelled" || bad "/api/events" "$EV"
echo "$EV" | grep -qE 'PRIVATE-NOTE-123|REVIEW-NOTE-456' && bad "/api/events leaks an internal note" "" || ok "/api/events has no internal notes"
echo "$PEND" | grep -q 'PRIVATE-NOTE-123' && ok "admin sees the partner's private note" || bad "admin private note" ""
check "partner page API hides notes" "$(curl -s "$B/api/partner?k=$TOK" | grep -cE 'PRIVATE-NOTE-123|REVIEW-NOTE-456')" 0
grep -qi 'cache-control: public, max-age=60' $T/ev.h && ok "/api/events cache-control" || bad "events cache" "$(cat $T/ev.h)"
curl -s $B/media/$KB -o $T/rt2.jpg; cmp -s $T/rt2.jpg $F/before.jpg && ok "approved photo is public and byte-exact" || bad "public round trip" "differs"

H=$(curl -s -D - -o /dev/null $B/media/$KV)
echo "$H" | grep -qi 'content-type: video/mp4' && echo "$H" | grep -qi 'immutable' && ok "GET /media video content-type + immutable" || bad "media headers" "$H"
R=$(curl -s -D - -o $T/part.bin -H 'Range: bytes=100-199' $B/media/$KV)
SZ=$(size $F/tiny.mp4)
echo "$R" | head -1 | grep -q 206 && echo "$R" | grep -qi "content-range: bytes 100-199/$SZ" && [ "$(size $T/part.bin)" -eq 100 ] \
  && cmp -s $T/part.bin <(dd if=$F/tiny.mp4 bs=1 skip=100 count=100 2>/dev/null) && ok "Range request -> 206 with exact bytes" || bad "range" "$R"
check "suffix range bytes=-10 -> 206" "$(code -H 'Range: bytes=-10' $B/media/$KV)" 206
check "unsatisfiable range -> 416" "$(code -H 'Range: bytes=99999999-' $B/media/$KV)" 416
check "media bad key format -> 404" "$(code $B/media/zzzz)" 404
check "media traversal (path-as-is) -> 404" "$(code --path-as-is $B/media/%2e%2e%2fetc)" 404
check "media uppercase key -> 404" "$(code $B/media/$(echo $KB | tr a-f A-F))" 404
check "media unknown key -> 404" "$(code $B/media/00000000000000000000000000000000)" 404

# Downloads: ?dl=1 saves a file as sapu-earth-<first 8 of the key>.<ext>, as it always did; ?dl=<name> as
# sapu-earth-<name>.<ext>, the extension from the stored type, when the name is lowercase letters, digits and dashes
# (64 at most). dl is outside the signature, so any other value gets the old name and nothing of it reaches the
# header. Signed and public links alike. dlname <url> [curl options]: the Content-Disposition, or "none".
dlname() { local h; h=$(curl -s -o /dev/null -D - "${@:2}" "$1" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Dd]isposition: *//p'); echo "${h:-none}"; }
OLDB="attachment; filename=\"sapu-earth-${KB:0:8}.jpg\""
check "/media/ without dl or with an empty dl -> no download name" "$(dlname $B/media/$KV) $(dlname "$B/media/$KV?dl=")" "none none"
check "dl=1 -> the old name, on the public video and on the signed photo" "$(dlname "$B/media/$KV?dl=1") | $(dlname "$B$SIG&dl=1")" \
  "attachment; filename=\"sapu-earth-${KV:0:8}.mp4\" | $OLDB"
check "dl=<receipt id>-video-before (public) and dl=<receipt id>-before-1 (signed) -> sapu-earth-<name>.<ext>" \
  "$(dlname "$B/media/$KV?dl=$ID-video-before") | $(dlname "$B$SIG&dl=$ID-before-1")" \
  "attachment; filename=\"sapu-earth-$ID-video-before.mp4\" | attachment; filename=\"sapu-earth-$ID-before-1.jpg\""
check "the name also comes with HEAD and with a range" \
  "$(dlname "$B/media/$KV?dl=$ID-video-before" -I) | $(dlname "$B/media/$KV?dl=$ID-video-before" -H 'Range: bytes=0-9')" \
  "attachment; filename=\"sapu-earth-$ID-video-before.mp4\" | attachment; filename=\"sapu-earth-$ID-video-before.mp4\""
N64=$(printf 'a%.0s' $(seq 64))
check "a name of 64 characters is taken" "$(dlname "$B$SIG&dl=$N64")" "attachment; filename=\"sapu-earth-$N64.jpg\""
DLBAD=""
for v in Before-1 %22x%22 'x%22%3B%20filename%3D%22evil.html' 'a%0d%0aSet-Cookie:%20e2e=1' 'a%0aX-E2E:%201' a%2fb a/b '..%2f..%2fx' \
         %c3%a9t%c3%a9 "a$N64" -x %20x x.html 'a%00b'; do
  got=$(dlname "$B$SIG&dl=$v")
  [ "$got" = "$OLDB" ] || DLBAD="$DLBAD [$v -> $got]"
  curl -s -o /dev/null -D - "$B$SIG&dl=$v" | grep -qiE '^(set-cookie|x-e2e):' && DLBAD="$DLBAD [$v added a header]"
done
[ -z "$DLBAD" ] && ok "dl with quotes, CR or LF, slashes, uppercase, 65 characters, unicode, a leading dash, a space, a dot or a NUL -> the old name, no added header" \
  || bad "dl names that must fall back to the old name" "$DLBAD"

RP=$(curl -s $B/r/$ID)
echo "$RP" | grep -q 'property="og:title" content="Cleanup in &lt;img src=x onerror=alert(1)&gt; &quot;Kali&quot; &amp; co · Sapu Earth"' && ok "/r og:title escaped" || bad "/r og:title" "$(echo "$RP" | grep og:title)"
echo "$RP" | grep -q "property=\"og:image\" content=\"$B/media/$KA\"" && ok "/r og:image absolute after photo" || bad "/r og:image" "$(echo "$RP" | grep og:image)"
echo "$RP" | grep -q 'name="twitter:card" content="summary_large_image"' && ok "/r twitter card" || bad "twitter" ""
echo "$RP" | grep -q "og:description\" content=\"118 kg removed by a crew of 6. Cleaned by Kali Bersih &lt;b&gt;Crew&lt;/b&gt;.\"" && ok "/r og:description" || bad "/r desc" "$(echo "$RP" | grep og:desc)"
echo "$RP" | grep -q "url=/#ev-$ID" && echo "$RP" | grep -q "location.replace(\"/#ev-$ID\")" && ok "/r redirects to /#ev-<id>" || bad "/r redirect" ""
echo "$RP" | grep -q '<img src=x' && bad "/r contains raw XSS" "" || ok "/r has no raw XSS payload"
echo "$RP" | grep -qE 'PRIVATE-NOTE-123|REVIEW-NOTE-456' && bad "/r leaks an internal note" "" || ok "/r has no internal notes"
check "/r bad id -> 404" "$(code $B/r/ZZZ)" 404
check "/r unknown id -> 404" "$(code $B/r/aaaaaaaaaa)" 404

PP=$(curl -s -w '\n%{http_code}' $B/p/$SLUG)
echo "$PP" | tail -1 | grep -q 200 && echo "$PP" | grep -q "/r/$ID" && echo "$PP" | grep -q '&lt;img src=x onerror' && ok "/p/<slug> lists cleanup, escaped" || bad "/p" "$(echo "$PP" | head -40)"
echo "$PP" | grep -q '<img src=x' && bad "/p contains raw XSS" "" || ok "/p has no raw XSS payload"
check "/p unknown -> 404" "$(code $B/p/nobody-here)" 404
# /p/ is rendered by a Function: it must link the same build-versioned CSS as the static pages
# (functions/_lib/asset-version.js, written by scripts/build-site.sh), and load no fonts from Google.
HV=$(curl -s $B/ | grep -oE 'site/styles\.css\?v=[A-Za-z0-9]+' | head -1 | cut -d= -f2)
for css in fonts styles forms; do
  PV=$(echo "$PP" | grep -oE "/site/$css\.css\?v=[A-Za-z0-9]+" | head -1 | cut -d= -f2)
  [ -n "$HV" ] && [ "$PV" = "$HV" ] && ok "/p/<slug> links $css.css?v=$HV like the homepage" || bad "/p/<slug> $css.css version" "page [$PV] homepage [$HV]"
done
echo "$PP" | grep -qE 'href="/site/[^"?]+\.css"' && bad "/p/<slug> links an unversioned stylesheet" "" || ok "/p/<slug> links only versioned stylesheets"
echo "$PP" | grep -qE 'fonts\.(googleapis|gstatic)\.com' && bad "/p/<slug> loads Google Fonts" "" || ok "/p/<slug> loads no Google Fonts"

# A cleanup takes up to 30 videos before and 30 after, 60 in all (LIMITS.stageVideos and LIMITS.cleanupVideos since
# 2026-11-19, one of each before): a 31st video of a stage and a 61st video (one sent without a stage counts) are refused,
# without the code "media" (the crew page would forget every key and upload all its files again), and PENDING and the
# receipt list the videos before, then after, each stage in upload order, whatever order the keys were sent in (the
# after ones first). KSA went up before KSB, so each stage starts with it. vsub <keys>: POST /api/submit, the answer in
# $T/vs.json, prints the status.
vsub() { curl -s -o "$T/vs.json" -w '%{http_code}' -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Staged "$1")"; }
VSB=$KSB; for i in $(seq 2 31); do VSB="$VSB,$(upv $TOK before)"; done
VSA=$KSA; for i in $(seq 2 31); do VSA="$VSA,$(upv $TOK after)"; done
KSN=$(upv $TOK); KB3=$(up before image/jpeg $F/before.jpg); KA3=$(up after image/jpeg $F/after.jpg)
VB30=$(echo "$VSB" | cut -d, -f1-30); VA30=$(echo "$VSA" | cut -d, -f1-30); VB29=$(echo "$VSB" | cut -d, -f1-29)
[ "$(echo "$VSB,$VSA,$KSN" | tr ',' '\n' | grep -cE '^[0-9a-f]{32}$')" = 63 ] && ok "31 videos uploaded with stage=before, 31 with stage=after and one without a stage" \
  || bad "the staged video uploads" "$VSB $VSA $KSN"
STAGE_ERR="At most 30 videos before and 30 videos after the cleanup."
check "31 videos before (none after), and 31 after with 29 before (60 in all) -> 400 each, without a code" \
  "$(vsub "$KB3,$KA3,$VSB") $(jget "(d.get('error'), d.get('code'))" < "$T/vs.json") $(vsub "$KB3,$KA3,$VB29,$VSA") $(jget "(d.get('error'), d.get('code'))" < "$T/vs.json")" \
  "400 ('$STAGE_ERR', None) 400 ('$STAGE_ERR', None)"
check "61 videos (30 before, 30 after and one sent without a stage) -> 400, without a code" \
  "$(vsub "$KB3,$KA3,$VA30,$VB30,$KSN") $(jget "(d.get('error'), d.get('code'))" < "$T/vs.json")" "400 ('At most 60 videos.', None)"
st=$(vsub "$KB3,$KA3,$VA30,$VB30"); ID3=$(jget "d.get('id')" < "$T/vs.json")
[ "$st" = 200 ] && [[ $ID3 =~ ^[a-z2-7]{10}$ ]] && ok "a cleanup with 30 videos after and 30 before, sent in that order, and its two photos (62 files) -> 200 ($ID3)" \
  || bad "cleanup with 30 videos before and 30 after" "$st $(cat "$T/vs.json")"
check "PENDING: its 60 videos, the 30 before first, each stage in upload order, with their stages" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[([v['key'] for v in s['media']['videos']] == '$VB30,$VA30'.split(','), [v['stage'] for v in s['media']['videos']] == ['before'] * 30 + ['after'] * 30) for s in d['submissions'] if s['id']=='$ID3']")" \
  "[(True, True)]"
check "approve it" "$(curl -s -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$ID3\",\"action\":\"approve\",\"paid_eur\":40}" | jget "d['status']")" approved
check "/api/events: the receipt has the 30 videos before, then the 30 after, each stage in upload order, with their stages" \
  "$(curl -s $B/api/events | jget "[(e['media']['videos'] == ['/media/' + k for k in '$VB30,$VA30'.split(',')], e['media']['video_stages'] == ['before'] * 30 + ['after'] * 30) for e in d if e['id']=='$ID3']")" \
  "[(True, True)]"
# The most files a cleanup lists (MEDIA_MAX): 8 photos for each of 4 spots and 60 videos, 92. A list of 93 is refused
# before any key is looked up; 92 unknown keys get as far as the lookup (one statement with 93 bound values, under D1's
# 100) and its "upload them again".
FK=$(python3 -c "import secrets;print(','.join(secrets.token_hex(16) for _ in range(93)))")
check "a cleanup that lists 93 files -> 400 (92 at most), 92 files it does not have -> 400 code media" \
  "$(vsub "$FK") $(jget "d.get('error')" < "$T/vs.json") $(vsub "${FK%,*}") $(jget "d.get('code')" < "$T/vs.json")" \
  "400 media must list 2 to 92 uploaded file keys. 400 media"

# Reject path: a new submission, then reject. Its media must be gone.
K1=$(up before image/jpeg $F/before.jpg); K2=$(up after image/jpeg $F/after.jpg)
ID2=$(curl -s -X POST "$B/api/submit?k=$TOK" -H 'content-type: application/json' -d "$(body $TODAY Rejectme $K1,$K2)" | jget "d['id']")
SIG2=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | signed $ID2 before)
check "admin can open media before reject" "$(code "$B$SIG2")" 200
RJ=$(curl -s -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$ID2\",\"action\":\"reject\",\"review_note\":\"blurry\"}")
check "reject reports 2 deleted media" "$(echo "$RJ" | jget "d['deleted_media']")" 2
check "rejected media gone (before)" "$(code $B/media/$K1)" 404
check "rejected media gone (after)" "$(code $B/media/$K2)" 404
check "rejected media gone for admin too" "$(code "$B$SIG2")" 404
check "rejected list has it" "$(curl -s "$B/api/admin/submissions?status=rejected" -H "$A" | grep -c $ID2)" 1

# Rotate the partner link, then deactivate the partner.
NEW=$(curl -s -X POST $B/api/admin/partners/rotate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$PID\"}" | jget "d['token']")
check "old token dead after rotate" "$(code "$B/api/partner?k=$TOK")" 404
check "new token works after rotate" "$(code "$B/api/partner?k=$NEW")" 200
curl -s -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$PID\"}" >/dev/null
check "deactivated token -> 404" "$(code "$B/api/partner?k=$NEW")" 404
check "deactivated partner page -> 404" "$(code $B/p/$SLUG)" 404
check "approved cleanup still in events after deactivate" "$(curl -s $B/api/events | grep -c $ID)" 1

# ---------- Partner applications (/apply/ and /api/apply) ----------
# Every request from this script reaches the local server from 127.0.0.1, so the per-address limit
# (3 stored applications in 24 h) would be shared by all of them. wrangler pages dev keeps a
# CF-Connecting-IP header sent by the client (checked in wrangler 4.149.0), so each run applies from
# its own documentation address instead. Each run also approves or deletes all its applications,
# so a reused address starts from zero. On Cloudflare the edge sets this header, clients cannot.
RUN=$RANDOM$RANDOM
IP="203.0.113.$((RANDOM % 254 + 1))"
IP2="198.51.100.$((RANDOM % 254 + 1))"
{ printf '\377\330\377\340'; head -c 3670016 /dev/zero; } > "$T/big35.jpg"

# POST /api/apply (multipart) from $IP, starting from a valid application. Prints the status, the
# body goes to $T/r.json. Each argument changes one field: name=value (name= sends it empty),
# -name leaves it out, photo=<file> adds a photo, logo=<file> adds a logo, ip=<address> applies from another address.
apply() {
  local ip=$IP a o skip args=()
  for a in lang=en "org_name=E2E Crew $RUN" contact_name=Ayu country=ID "area=Canggu, Bali" \
           "about=Every Saturday 6 of us clean the river mouth." crew_size=6 links= whatsapp= \
           "email=crew-$RUN@example.org" "heard_from=e2e test" consent=1 "client_ref=$(openssl rand -hex 16)" \
           elapsed_ms=45000 website=; do
    skip=
    for o in "$@"; do case "$o" in "${a%%=*}="*|"-${a%%=*}") skip=1 ;; esac; done
    [ -n "$skip" ] || args+=(--form-string "$a")
  done
  for o in "$@"; do
    case "$o" in
      -*) ;;
      ip=*) ip=${o#ip=} ;;
      photo=*) args+=(-F "photo=@${o#photo=};type=image/jpeg;filename=photo.jpg") ;;
      logo=*) args+=(-F "logo=@${o#logo=};type=image/jpeg;filename=logo.jpg") ;;
      *) args+=(--form-string "$o") ;;
    esac
  done
  curl -s -o "$T/r.json" -w '%{http_code}' -X POST "$B/api/apply" -H "CF-Connecting-IP: $ip" "${args[@]}"
}
# POST /api/admin/applications/<action> with a JSON body. Prints the status, the body goes to $T/r.json.
adm()   { curl -s -o "$T/r.json" -w '%{http_code}' -X POST "$B/api/admin/applications/$1" -H "$A" -H 'content-type: application/json' -d "$2"; }
rj()    { jget "$1" < "$T/r.json"; }
alist() { curl -s "$B/api/admin/applications?status=${1:-new}" -H "$A"; }
# Python expression over application <id> (as a) of an admin list on stdin (as d). a is None if missing.
appq()  { python3 -c "
import json,sys
d=json.load(sys.stdin);a=([x for x in d['applications'] if x['id']==sys.argv[1]] or [None])[0]
print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
mine()  { jget "sum(a['org_name'].endswith(' $RUN') for a in d['applications'])"; }

check "apply with a JSON body -> 415" "$(code -X POST $B/api/apply -H 'content-type: application/json' -d '{"org_name":"x","consent":"1"}')" 415
check "apply without consent -> 400" "$(apply consent=)" 400
st=$(apply whatsapp= email=); check "apply without WhatsApp and email -> 400 (contact)" "$st $(rj "d.get('field')")" "400 contact"
check "apply with WhatsApp \"12\" -> 400" "$(apply whatsapp=12)" 400
check "apply with country \"Indonesia\" -> 400" "$(apply country=Indonesia)" 400
check "apply without client_ref -> 400" "$(apply -client_ref)" 400
st=$(apply photo=$F/before.jpg photo=$F/after.jpg photo=$F/before.jpg photo=$F/after.jpg)
check "apply with 4 photos -> 400 (photos)" "$st $(rj "d.get('field')")" "400 photos"
st=$(apply photo=$T/exif.jpg); check "apply photo with camera data (Exif) -> 415" "$st $(rj "d.get('code')")" "415 photo"
st=$(apply photo=$T/fake.jpg); check "apply photo that is not a JPEG -> 415" "$st $(rj "d.get('code')")" "415 photo"
st=$(apply photo=$T/big35.jpg); check "apply photo of 3.5 MB -> 413 (photos)" "$st $(rj "d.get('field')")" "413 photos"
# "about" counts a line break as one character, even though the form sends it as CRLF. A fake photo
# makes the request fail after the text checks, so nothing is stored either way.
ABOUT_CRLF=$(python3 -c "print('x'*600 + '\r\n' + 'y'*399, end='')")
st=$(apply "about=$ABOUT_CRLF" photo=$T/fake.jpg); check "about of 1000 characters with a CRLF line break passes" "$st $(rj "d.get('code')")" "415 photo"
st=$(apply "about=$(python3 -c "print('x'*1001, end='')")"); check "about over 1000 characters -> 400 (about)" "$st $(rj "d.get('field')")" "400 about"
st=$(apply website=https://spam.example "org_name=Honeypot $RUN")
check "honeypot filled -> 201 with an id (looks like success)" "$st $(rj "len(d['id'])")" "201 10"
check "form sent after 0.5 s -> 201 (looks like success)" "$(apply elapsed_ms=500 "org_name=TooFast $RUN")" 201
check "form without elapsed_ms -> 201 (looks like success)" "$(apply -elapsed_ms "org_name=NoTimer $RUN")" 201
check "admin applications without token -> 401" "$(code $B/api/admin/applications)" 401
check "admin applications unknown status -> 400" "$(code "$B/api/admin/applications?status=rejected" -H "$A")" 400
check "refused and bot applications were not stored" "$(alist | mine)" 0

ORG_A="Kali Bersih Apply $RUN"; REF_A=$(openssl rand -hex 16)
APP_A=("org_name=$ORG_A" "contact_name=Ayu Lestari" "client_ref=$REF_A" "whatsapp=+62 812-3456-7890" "email=A-$RUN@Example.org"
       "links=$(printf 'https://instagram.com/e2ecrew\n@e2e_crew')" "photo=$F/before.jpg" "photo=$F/after.jpg")
st=$(apply "${APP_A[@]}"); AID=$(rj "d['id']")
[[ $st = 201 && $AID =~ ^[a-z2-7]{10}$ ]] && ok "application A with 2 photos -> 201 ($AID)" || bad "application A" "$st $(cat "$T/r.json")"
[ -n "$STATE" ] && M1=$(r2mt)
st=$(apply "${APP_A[@]}"); check "A sent again (same client_ref) -> 200, same id" "$st $(rj "d['id']") $(rj "d.get('repeated')")" "200 $AID True"
[ -n "$STATE" ] && check "the repeat wrote nothing to R2" "$(r2mt)" "$M1"

L=$(alist)
check "A is stored once" "$(echo "$L" | jget "sum(a['org_name']=='$ORG_A' for a in d['applications'])")" 1
check "A: WhatsApp normalized, email lowercased" "$(echo "$L" | appq "$AID" "a['whatsapp']+' '+a['email']")" "+6281234567890 a-$RUN@example.org"
check "A: links as a list" "$(echo "$L" | appq "$AID" "a['links']==['https://instagram.com/e2ecrew','@e2e_crew']")" True
# The form asks no head count since 2026-11-17 (Marcus: 'Drop the head count'): apply() still sends crew_size=6, as a page
# from before would, and it is not stored; /admin/ shows Crew size only on an older application that has one.
check "A: the head count an older page still sends is not stored" "$(echo "$L" | appq "$AID" "a['crew_size']")" None
APH=$(curl -s $B/apply/); APJ=$(curl -s $B/apply/apply.js)
! echo "$APH" | grep -qE 'crew_size|usually join' && ! echo "$APJ" | grep -qE '"crew_size"|e_crew|f-crew_size|usually join|Biasanya berapa orang' \
  && ! grep -qE 'fd, "crew_size"|a\.crew_size' functions/api/apply.js && grep -qF '${n(a.crew_size) ? `<dt>Crew size</dt><dd>${esc(a.crew_size)} people</dd>` : ""}' admin/admin.js \
  && ! grep -qF '<dt>Crew size</dt><dd>${n(a.crew_size) ? esc(a.crew_size) + " people" : "not given"}</dd>' admin/admin.js \
  && ok "/apply/ asks no head count (English and Indonesian), POST /api/apply ignores one, /admin/ shows it only when an application has one" \
  || bad "the head count on /apply/" ""
check "A: status new, no partner yet" "$(echo "$L" | appq "$AID" "a['status']+' '+str(a['partner'])")" "new None"
check "counts.new >= 1" "$(echo "$L" | jget "d['counts']['new']>=1")" True
echo "$L" | grep -qE "ip_hash|client_ref|$REF_A" && bad "applications list leaks ip_hash or client_ref" "" || ok "applications list has no ip_hash or client_ref"
PA=$(echo "$L" | appq "$AID" "'\n'.join(p['url'] for p in a['photos'])")
n=0
while read -r u; do
  [ -n "$u" ] || continue
  n=$((n+1))
  check "A photo $n: signed link -> 200 image/jpeg" "$(curl -s -o $T/ph.jpg -w '%{http_code} %{content_type}' "$B$u")" "200 image/jpeg"
  cmp -s $T/ph.jpg $F/before.jpg || cmp -s $T/ph.jpg $F/after.jpg && ok "A photo $n is byte-exact" || bad "A photo $n bytes differ" "$u"
  check "A photo $n: plain /media link -> 404" "$(code "$B${u%%\?*}")" 404
done <<< "$PA"
check "A has 2 signed photo links" "$n" 2

ORG_B="Pantai Bersih $RUN"
st=$(apply "org_name=$ORG_B" "whatsapp=0062 812 3456 7890" "email=b-$RUN@example.org" "photo=$F/after.jpg"); BID=$(rj "d['id']")
check "application B (same WhatsApp, other spelling) -> 201" "$st" 201
L=$(alist)
check "B lists A as a possible duplicate" "$(echo "$L" | appq "$BID" "'$AID' in a['possible_duplicates']")" True
check "A lists B as a possible duplicate" "$(echo "$L" | appq "$AID" "'$BID' in a['possible_duplicates']")" True
PB=$(echo "$L" | appq "$BID" "a['photos'][0]['url']")
check "B photo: signed link -> 200" "$(code "$B${PB:-/media/none}")" 200

ASLUG="apply-$RUN"
abody() { printf '{"id":"%s","name":"%s","url":"https://instagram.com/e2ecrew","country":"ID","slug":"%s"}' "$1" "$ORG_A" "$2"; }
check "approve without token -> 401" "$(code -X POST $B/api/admin/applications/approve -H 'content-type: application/json' -d "$(abody "$AID" "$ASLUG")")" 401
check "approve bad id -> 400" "$(adm approve "$(abody NOPE "$ASLUG")")" 400
check "approve unknown id -> 404" "$(adm approve "$(abody aaaaaaaaaa "never-$RUN")")" 404
check "approve A with a taken slug -> 409" "$(adm approve "$(abody "$AID" "$SLUG")")" 409
st=$(adm approve "$(abody "$AID" "$ASLUG")"); PTOK=$(rj "d['partner']['token']"); APID=$(rj "d['partner']['id']")
check "approve A -> 201" "$st" 201
check "approve returns the upload link" "$(rj "d['partner']['slug']+' '+d['partner']['upload_url']")" "$ASLUG https://sapu.earth/upload/?k=$PTOK"
check "approve returns the contact and 2 deleted photos" "$(rj "d['application']['id']+' '+d['application']['whatsapp']+' '+str(d['deleted_photos'])")" "$AID +6281234567890 2"
check "new partner link works on /api/partner" "$(curl -s "$B/api/partner?k=$PTOK" | jget "d['slug']")" "$ASLUG"
n=0
while read -r u; do
  [ -n "$u" ] || continue
  n=$((n+1)); check "A photo $n deleted after approve (old signed link -> 404)" "$(code "$B$u")" 404
done <<< "$PA"
check "approve A again -> 409" "$(adm approve "$(abody "$AID" "again-$RUN")")" 409
check "A is in the approved list with its partner, photos gone" \
  "$(alist approved | appq "$AID" "a['partner']['slug']+' '+str(a['partner']['active'])+' '+str(len(a['photos']))+' '+str(a['decided_at'] is not None)")" "$ASLUG True 0 True"
check "A is no longer in the new list" "$(alist | appq "$AID" "a")" None
PL=$(curl -s $B/api/admin/partners -H "$A")
check "partner list shows the applicant's contact (one row)" "$(echo "$PL" | jget "[(p['contact_name'],p['whatsapp'],p['email']) for p in d['partners'] if p['slug']=='$ASLUG']")" \
  "[('Ayu Lestari', '+6281234567890', 'a-$RUN@example.org')]"
check "partner without an application has no contact" "$(echo "$PL" | jget "[p['contact_name'] for p in d['partners'] if p['slug']=='$SLUG']")" "[None]"
check "second approve created no partner" "$(echo "$PL" | jget "sum(p['slug']=='again-$RUN' for p in d['partners'])")" 0

st=$(adm reject "{\"id\":\"$BID\"}")
check "reject B -> 200, 1 photo deleted" "$st $(rj "d.get('deleted')") $(rj "d.get('deleted_photos')")" "200 True 1"
check "B is gone from the new list" "$(alist | appq "$BID" "a")" None
check "B photo deleted (signed link -> 404)" "$(code "$B$PB")" 404
check "reject B again -> 404" "$(adm reject "{\"id\":\"$BID\"}")" 404
check "reject approved A -> 409" "$(adm reject "{\"id\":\"$AID\"}")" 409
check "reject unknown id -> 404" "$(adm reject '{"id":"aaaaaaaaaa"}')" 404
check "reject bad id -> 400" "$(adm reject '{"id":"../x"}')" 400

# Rate limit. A was approved (its address hash is cleared) and B was deleted, so $IP has 0 stored now.
st=$(apply "org_name=$(echo "$ORG_A" | tr a-z A-Z)"); CID=$(rj "d['id']"); RL=$st
check "same name as a partner -> existing_partner and duplicate of A" \
  "$(alist | appq "$CID" "a['existing_partner']['slug']+' '+str('$AID' in a['possible_duplicates'])")" "$ASLUG True"
for n in 2 3; do RL="$RL $(apply "org_name=Limit $n $RUN")"; done
check "3 applications from one address -> 201 each" "$RL" "201 201 201"
st=$(apply "org_name=Limit 4 $RUN"); check "4th application from that address in 24 h -> 429 (rate)" "$st $(rj "d.get('code')")" "429 rate"
st=$(apply "ip=$IP2" "org_name=Other address $RUN")
case "$st" in
  201) ok "another address can still apply" ;;
  429) echo "NOTE  local server ignores CF-Connecting-IP, per-address check skipped" ;;
  *)   bad "another address can still apply" "$st $(cat "$T/r.json")" ;;
esac

# IPv6 counts per /64 network: a phone or a home line gets a whole /64, so counting each address
# would let one device apply without limit. Random /64s in the documentation range 2001:db8::/32.
G3=$(printf '%x' $((RANDOM % 61440 + 4096))); G4=$((RANDOM % 61440 + 4096))
NET6="2001:db8:$G3:$(printf '%x' $G4)"
NET6B="2001:db8:$G3:$(printf '%x' $((G4 ^ 1)))"
IP6C="2001:db8:$G3:$(printf '%x' $((G4 ^ 2)))::1"   # a third /64, for the checks further down
RL=$(apply "ip=$NET6::1" "org_name=IPv6 1 $RUN")
RL="$RL $(apply "ip=$NET6:a::2" "org_name=IPv6 2 $RUN")"
RL="$RL $(apply "ip=$NET6:1:2:3:4" "org_name=IPv6 3 $RUN")"
check "3 applications from 3 IPv6 addresses in one /64 -> 201 each" "$RL" "201 201 201"
[ -n "$STATE" ] && M1=$(r2mt)
st=$(apply "ip=$NET6:ffff:ffff:ffff:fffe" "org_name=IPv6 4 $RUN" "photo=$F/before.jpg")
check "4th from another address in that /64 (with a photo) -> 429 (rate)" "$st $(rj "d.get('code')")" "429 rate"
[ -n "$STATE" ] && check "the refused application wrote nothing to R2" "$(r2mt)" "$M1"
check "an address in the neighbouring /64 can still apply" "$(apply "ip=$NET6B::1" "org_name=IPv6 other $RUN")" 201
# IPv4-mapped and malformed values are counted as they are, and never break the request.
M=$((RANDOM % 200 + 1)); RL=$(apply "ip=::ffff:192.0.2.$M" "org_name=Mapped 1 $RUN")
for n in 1 2 3; do RL="$RL $(apply "ip=::ffff:192.0.2.$((M + n))" "org_name=Mapped $((n + 1)) $RUN")"; done
check "4 IPv4-mapped addresses (::ffff:192.0.2.x) each count on their own" "$RL" "201 201 201 201"
check "address with 9 groups (malformed) -> 201, not a 500" "$(apply "ip=$G3:1:2:3:4:5:6:7:8" "org_name=Malformed $RUN")" 201

# WhatsApp numbers the way phones copy them: invisible direction marks, non-breaking hyphens and
# the national 0 after the country code. The server stores the clean number in every case. A number
# typed without its code gets the code of the chosen country, from any country on the apply page.
IP3="192.0.2.$((RANDOM % 254 + 1))"
IP6D="2001:db8:$G3:$(printf '%x' $((G4 ^ 3)))::1"   # two more /64s, 3 applications each
IP6E="2001:db8:$G3:$(printf '%x' $((G4 ^ 4)))::1"
# wa <n> <label> <address> <typed number> <stored number> [country, ID if left out]
wa() {
  local st id
  st=$(apply "ip=$3" "org_name=WhatsApp $1 $RUN" "whatsapp=$4" "country=${6:-ID}" -email); id=$(rj "d.get('id')")
  check "WhatsApp $2 -> 201, stored as $5" "$st $(alist | appq "$id" "a['whatsapp']")" "201 $5"
}
wa 1 "with a direction mark (U+200E) and non-breaking hyphens (U+2011)" "$IP3" "$(uni '<200e>+62 812<2011>3456<2011>7890')" +6281234567890
wa 2 "\"+62 0812 3456 7890\" (national 0 after the code)" "$IP3" "+62 0812 3456 7890" +6281234567890
wa 3 "\"+63 (0)917 123 4567\" wrapped in U+202A/U+202C" "$IP3" "$(uni '<202a>+63 (0)917 123 4567<202c>')" +639171234567
wa 4 "\"+39 06 1234 5678\" (Italy, keeps its 0)" "$IP6C" "+39 06 1234 5678" +390612345678
wa 5 "\"77 123 45 67\" with Senegal chosen (was +7, Russia)" "$IP6D" "77 123 45 67" +221771234567 SN
wa 6 "\"07 07 12 34 56\" with Côte d'Ivoire chosen (the 0 is part of the number)" "$IP6D" "07 07 12 34 56" +2250707123456 CI
wa 7 "\"+233 024 123 4567\" (Ghana, national 0 after the code)" "$IP6D" "+233 024 123 4567" +233241234567 GH
wa 8 "\"0803 123 4567\" with Nigeria chosen" "$IP6E" "0803 123 4567" +2348031234567 NG
st=$(apply "ip=$IP6E" "org_name=WhatsApp no code $RUN" "whatsapp=77 123 45 67" country=AQ -email)
check "a number without + for a country with no calling code (Antarctica) -> 400 (whatsapp), never a guessed code" "$st $(rj "d.get('field')")" "400 whatsapp"
# The page and the server share one block of WhatsApp rules (calling codes of every country, where a 0 is part
# of the number, mobile lengths): the same text in apply/apply.js and functions/api/apply.js, and the same
# numbers from both, run in node. The page's line under the field warns about a local number before a country
# is chosen, a code that is not the chosen country's, and a number too long or short for a mobile there.
curl -s $B/apply/apply.js > "$T/apply-page.js"
cat > "$T/wa.js" <<'JS'
const fs = require("fs");
const page = fs.readFileSync(process.argv[2], "utf8"), server = fs.readFileSync(process.argv[3], "utf8");
const START = "// ---------- WhatsApp numbers: the same block", END = "// ---------- end of the WhatsApp block ----------";
const block = (s) => s.slice(s.indexOf(START), s.indexOf(END) + END.length);
const flat = (s) => s.split("\n").map((l) => l.replace(/^ +/, "")).join("\n");
const bad = [];
if (!page.includes(START) || !server.includes(START) || flat(block(page)) !== flat(block(server))) bad.push("the two blocks differ");
const load = (s) => new Function(s.slice(s.indexOf("const WA_STRIP"), s.indexOf(END)) + "\nreturn { normWhatsapp, DIAL, CODES };")();
const P = load(page), S = load(server);
const u = (x) => x.replace(/<([0-9a-f]{4})>/g, (m, h) => String.fromCharCode(parseInt(h, 16)));
const cases = [
  ["<200e>+62 812<2011>3456<2011>7890", "ID", "+6281234567890"], ["0812 3456 7890", "ID", "+6281234567890"],
  ["812 3456 7890", "ID", "+6281234567890"], ["6281234567890", "ID", "+6281234567890"], ["0062 812 3456 7890", "ID", "+6281234567890"],
  ["<202a>+63 (0)917 123 4567<202c>", "PH", "+639171234567"], ["0917 123 4567", "PH", "+639171234567"], ["639171234567", "PH", "+639171234567"],
  ["9123456789", "IN", "+919123456789"], ["919123456789", "IN", "+919123456789"], ["+39 06 1234 5678", "ID", "+390612345678"],
  ["77 123 45 67", "SN", "+221771234567"], ["221 77 123 45 67", "SN", "+221771234567"], ["07 07 12 34 56", "CI", "+2250707123456"],
  ["+225 07 07 12 34 56", "CI", "+2250707123456"], ["024 123 4567", "GH", "+233241234567"], ["24 123 4567", "GH", "+233241234567"],
  ["+233 024 123 4567", "GH", "+233241234567"], ["0803 123 4567", "NG", "+2348031234567"], ["0772 123456", "UG", "+256772123456"],
  ["0754 123 456", "TZ", "+255754123456"], ["078 812 3456", "RW", "+250788123456"], ["082 123 4567", "ZA", "+27821234567"],
  ["0712 345678", "KE", "+254712345678"], ["254712345678", "KE", "+254712345678"], ["01 97 12 34 56", "BJ", "+2290197123456"],
  ["06 123 4567", "CG", "+242061234567"], ["876 123 4567", "JM", "+18761234567"], ["07700 900123", "GB", "+447700900123"],
  ["0812 3456 7890", "", "081234567890"], ["77 123 45 67", "AQ", "771234567"], ["+221 77 123 45 67", "", "+221771234567"],
];
for (const [raw, c, want] of cases) {
  const p = P.normWhatsapp(u(raw), c), s = S.normWhatsapp(u(raw), c);
  if (p !== want || s !== want) bad.push(`${raw} (${c || "no country"}): page ${p}, server ${s}`);
}
const ISO = page.match(/const ISO = \(([\s\S]*?)\)\.split/)[1].replace(/["+\s]+/g, " ").trim().split(" ");
const none = ISO.filter((c) => !P.DIAL[c]).join(" ");
if (none !== "AQ BV GS HM PN TF UM") bad.push("countries without a calling code: " + none);
if (P.CODES.some((a) => P.CODES.some((b) => a !== b && b.startsWith(a)))) bad.push("a calling code starts another one");
const W = new Function("t", page.slice(page.indexOf("const WA_STRIP"), page.indexOf(END)) + "\n" +
  page.slice(page.indexOf("  function waWarning"), page.indexOf("  // Show the number we will store")) +
  "\nreturn { normWhatsapp, waWarning };")((k, v) => k + (v ? JSON.stringify(v) : ""));
const warns = [
  ["77 123 45 67", "", "wa_country"], ["+221 77 123 45 67", "", null], ["77 123 45 67", "SN", null],
  ["+256 712 345 678", "KE", 'wa_check{"d":"254"}'], ["256712345678", "KE", 'wa_len{"k":12,"d":"254","n":"9"}'],
  ["+225 07 12 34 56", "CI", 'wa_len{"k":8,"d":"225","n":"10"}'], ["77 123 45 67", "AQ", "e_whatsapp"],
  ["+62 812 345", "ID", 'wa_len{"k":6,"d":"62","n":"wa_range{\\"a\\":9,\\"b\\":12}"}'], ["+62 812 3456 7890", "ID", null], ["", "KE", null],
];
for (const [raw, c, want] of warns) {
  const w = W.waWarning(raw, W.normWhatsapp(raw, c), c);
  const got = w ? w.key + (w.vars ? JSON.stringify(w.vars) : "") : null;
  if (got !== want) bad.push(`line under ${raw} (${c || "no country"}): ${got}`);
}
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
JS
WAN=$(node "$T/wa.js" "$T/apply-page.js" functions/api/apply.js 2>&1)
[ "$WAN" = ok ] && ok "apply page and server read WhatsApp numbers of every country the same way (Senegal +221, Côte d'Ivoire keeps its 0, Ghana, Nigeria, Uganda, Tanzania, Rwanda, South Africa, Kenya, Benin, Jamaica), and the page warns about a wrong code or length (node)" \
  || bad "WhatsApp rules (node)" "$WAN"
grep -qF 'f.whatsapp = at("whatsapp", () => cleanWhatsapp(str(fd, "whatsapp"), f.country));' functions/api/apply.js \
  && grep -qF 'd.whatsapp = normWhatsapp(E.whatsapp.value, d.country);' "$T/apply-page.js" \
  && ok "the server cleans the number with the chosen country, like the page" || bad "server WhatsApp with country" ""

# Deactivating a partner ends the partnership: the personal fields of its application are wiped.
# The partner row, its crew name and its approved cleanups stay.
st=$(curl -s -o "$T/r.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$APID\"}")
check "deactivate the partner from application A -> 200" "$st" 200
check "its upload link stops working" "$(code "$B/api/partner?k=$PTOK")" 404
check "partner list: no contact left for the deactivated partner" \
  "$(curl -s $B/api/admin/partners -H "$A" | jget "[(p['active'], p.get('contact_name') or None, p.get('whatsapp') or None, p.get('email') or None) for p in d['partners'] if p['slug']=='$ASLUG']")" \
  "[(False, None, None, None)]"
check "approved A after deactivate: personal fields wiped, crew name kept" \
  "$(alist approved | appq "$AID" "(a['org_name'], a['contact_name'] or None, a['about'] or None, a['whatsapp'], a['email'], a['heard_from'], a['links'], len(a['photos']), a['partner']['active'])")" \
  "('$ORG_A', None, None, None, None, None, [], 0, False)"

# ---------- Retention: needs the local database, so only with STATE ----------
# Open applications older than 90 days are deleted with their photos, and address hashes older than
# 24 hours are cleared. The job runs at the start of GET /api/admin/applications and in the background
# after each stored application. Old rows are written straight into the server's local D1 file.
ago()   { python3 -c "import datetime as t,sys;print((t.datetime.now(t.timezone.utc)-t.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1"; }
newid() { python3 -c "import secrets;print(''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz234567') for _ in range(10)))"; }
oldrow() { printf "INSERT INTO applications (id, status, lang, org_name, contact_name, country, area, about, photos, ip_hash, created_at) VALUES ('%s', 'new', 'en', '%s', 'Old', 'ID', 'Bali', 'e2e', '[]', 'e2e-old', '%s');" "$1" "$2" "$3"; }
if [ -n "$STATE" ]; then
  st=$(apply "ip=$IP6C" "org_name=Expire photo $RUN" "photo=$F/before.jpg"); XID=$(rj "d.get('id')")
  XPH=$(alist | appq "$XID" "a['photos'][0]['url']")
  check "application with a photo, to be aged -> 201, photo link works" "$st $(code "$B${XPH:-/media/none}")" "201 200"
  O100=$(newid); O30=$(newid); P100=$(newid); D100=$(ago 100); D30=$(ago 30)
  if d1 "$(oldrow "$O100" "Old 100 days $RUN" "$D100") $(oldrow "$O30" "Old 30 days $RUN" "$D30")
         UPDATE applications SET created_at = '$D100' WHERE id = '$XID';" >/dev/null; then
    L=$(alist)
    check "open application of 30 days stays (the old rows reached the server)" "$(echo "$L" | appq "$O30" "a['org_name']")" "Old 30 days $RUN"
    check "GET applications deleted the open applications older than 90 days" "$(echo "$L" | appq "$O100" "a") $(echo "$L" | appq "$XID" "a")" "None None"
    for i in 1 2 3; do st=$(code "$B${XPH:-/media/none}"); [ "$st" = 404 ] && break; sleep 1; done
    check "the expired application's photo is deleted (signed link -> 404)" "$st" 404
    check "address hash of the 30-day application cleared" \
      "$(d1 "SELECT ip_hash FROM applications WHERE id = '$O30'" | jget "repr(d[0]['results'][0]['ip_hash'])")" "''"
    # The same job after a stored application, in the background (waitUntil).
    d1 "$(oldrow "$P100" "Old 100 days b $RUN" "$D100") UPDATE applications SET ip_hash = 'e2e-old' WHERE id = '$O30';" >/dev/null
    check "another application -> 201" "$(apply "ip=$IP6C" "org_name=Expiry trigger $RUN")" 201
    for i in 1 2 3; do
      got=$(d1 "SELECT id, ip_hash FROM applications WHERE id IN ('$P100', '$O30')" | jget "[(r['id'], r['ip_hash']) for r in d[0]['results']]")
      [ "$got" = "[('$O30', '')]" ] && break; sleep 1
    done
    check "after it, the 100-day application is gone and the old hash cleared" "$got" "[('$O30', '')]"
  else
    bad "write old applications into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
else
  echo "NOTE  STATE is not set, so the 90-day expiry and deploy-order checks are skipped (sh scripts/test.sh sets it)"
fi

# Clean up, so repeated runs against one local database never pile up open applications.
for id in $(alist | jget "' '.join(a['id'] for a in d['applications'] if a['org_name'].endswith(' $RUN'))"); do
  adm reject "{\"id\":\"$id\"}" >/dev/null
done
check "test applications cleaned up" "$(alist | mine)" 0

# Deploy order: if the code goes live before migration 0003, /admin/ must still log in. Its token
# check reads the partner list, so that must work without the applications table. The table is
# renamed for a moment (finish() renames it back if the script stops in between).
if [ -n "$STATE" ]; then
  RENAMED=1
  if d1 "ALTER TABLE applications RENAME TO applications_e2e_off" >/dev/null; then
    PL=$(curl -s -w '\n%{http_code}' $B/api/admin/partners -H "$A")
    d1 "ALTER TABLE applications_e2e_off RENAME TO applications" >/dev/null && RENAMED=
    check "partner list without the applications table -> 200, contacts null" \
      "$(echo "$PL" | tail -1) $(echo "$PL" | sed '$d' | jget "len(d['partners']) > 0 and all(p.get('contact_name') is None for p in d['partners'])")" "200 True"
    check "applications table back in place" "$(code $B/api/admin/applications -H "$A")" 200
  else
    RENAMED=
    bad "rename the applications table in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# ---------- Missions (POST A MISSION, /api/missions, /m/<no>, /admin/ MISSIONS) ----------
# Fresh crews. Crew 1 posts missions. Mission 1 goes the whole way: review, open, funded, a
# cleanup sent for it, approved (done), unpublished. Missions 2 to 6 are declined, withdrawn,
# removed, or removed by DEACTIVATE. Crew 2 owns a photo and a funded mission
# crew 1 must not use, has a cleanup for its mission rejected (the mission stays funded), and its
# mission is cancelled. Crew 3 sends a cleanup without a mission, which APPROVE links to its funded
# mission, then DEACTIVATE removes its other funded mission. Every removal wipes the private note
# and the exact point; the place, the task and the money stay as the record.
MRUN=$RANDOM$RANDOM
MSLUG="mission-$MRUN"; OSLUG="mission-other-$MRUN"
newp()  { curl -s -X POST $B/api/admin/partners -H "$A" -H 'content-type: application/json' \
            -d "{\"name\":\"$1\",\"url\":\"https://example.org\",\"country\":\"$2\",\"slug\":\"$3\"}"; }
MPJ=$(newp "Mission Crew $MRUN" ID "$MSLUG"); MT=$(echo "$MPJ" | jget "d['token']"); MPID=$(echo "$MPJ" | jget "d['id']")
OPJ=$(newp "Other Mission Crew $MRUN" PH "$OSLUG"); OT=$(echo "$OPJ" | jget "d['token']"); OPID=$(echo "$OPJ" | jget "d['id']")
[ ${#MT} -eq 43 ] && [ ${#OT} -eq 43 ] && ok "two partners for the mission checks" || bad "mission partners" "$MPJ $OPJ"

# upk <token> <before|after>: uploads before.jpg or after.jpg as that kind, prints the key.
upk()   { curl -s -X POST "$B/api/upload?k=$1&kind=$2" -H 'content-type: image/jpeg' --data-binary @$F/$2.jpg | jget "d['key']"; }
N1A=$(upk $MT before); N1B=$(upk $MT before); N2=$(upk $MT before); N3=$(upk $MT before)
N4=$(upk $MT before); N5=$(upk $MT before); N6=$(upk $MT before)
CB=$(upk $MT before); CA=$(upk $MT after); CB2=$(upk $MT before); CA2=$(upk $MT after)
K2A=$(upk $OT before)
n=0; for k in $N1A $N1B $N2 $N3 $N4 $N5 $N6 $CB $CA $CB2 $CA2 $K2A; do [[ $k =~ ^[0-9a-f]{32}$ ]] && n=$((n+1)); done
check "12 photos uploaded for the mission checks" "$n" 12
# The photo check takes exactly what the page sends (jpegLikePage in functions/_lib/util.js): before the image data only
# the JFIF header, a colour profile, comments, the tables and one frame, within the first 64 KB, and the end marker as
# the last two bytes. A crew of its own, so these refusals count against nobody else's upload limits.
JPJ=$(newp "Jpeg Crew $MRUN" ID "jpeg-$MRUN"); JPT=$(echo "$JPJ" | jget "d['token']")
python3 - "$F/before.jpg" "$T" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); out = sys.argv[2]
def seg(m, p): return b"\xff" + bytes([m]) + (len(p) + 2).to_bytes(2, "big") + p
n = 4 + ((b[4] << 8) | b[5])  # end of the JFIF segment
plus = lambda x: b[:n] + x + b[n:]
files = {
  "xmp": plus(seg(0xe1, b"http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta/>")),
  "app13": plus(seg(0xed, b"Photoshop 3.0\x00" + b"\x00" * 20)),
  "jfxx": plus(seg(0xe0, b"JFXX\x00\x10" + b"\x00" * 8)),
  "stray": plus(b"\x00"),
  "tail": b + b"\x00" * 32,
  "padded": plus(seg(0xfe, b"x" * 40000) + seg(0xfe, b"x" * 40000)),
  "icc": plus(seg(0xe2, b"ICC_PROFILE\x00\x01\x01" + b"\x00" * 32)),
}
for k, v in files.items(): open(f"{out}/jp-{k}.jpg", "wb").write(v)
PY
st=""
for v in xmp app13 jfxx stray tail padded icc; do
  st="$st $(curl -s -o "$T/jp.json" -w '%{http_code}' -X POST "$B/api/upload?k=$JPT&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/jp-$v.jpg):$(jget "d.get('code', 'key')" < "$T/jp.json")"
done
check "photos: XMP, a Photoshop block, a second APP0, a stray byte, bytes after the end, a header past 64 KB -> 415 exif; with a colour profile -> taken" \
  "$st" " 415:exif 415:exif 415:exif 415:exif 415:exif 415:exif 200:key"
st=$(apply "ip=2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::c" "org_name=Jpeg Apply $MRUN" "photo=$T/jp-tail.jpg")
check "an application photo with bytes after the picture -> 415 photo" "$st $(rj "d.get('code')")" "415 photo"

dplus() { python3 -c "import datetime as t,sys;print((t.datetime.now(t.timezone.utc)+t.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%d'))" "$1"; }
add()   { [[ $1 =~ ^-?[0-9]+$ ]] && echo $(($1 + $2)); }
PLAN=$(dplus 3)
MPLACE='<b>Canggu</b> river "mouth" & co'
MPLACE_ESC='&lt;b&gt;Canggu&lt;/b&gt; river &quot;mouth&quot; &amp; co'
# JSON body for POST /api/mission, a valid mission with a fresh client_ref. Each argument changes one
# field: name=text, name:=json (for numbers, true, false, null), -name leaves it out,
# media=k1,k2 (media= sends an empty list).
mbody() { python3 -c '
import json,secrets,sys
d={"client_ref":secrets.token_hex(16),"place_name":"Canggu river mouth","country":"ID","lat":-8.659412,"lng":115.130087,
   "task":"Clear the river mouth.\nSort the plastic for the waste bank.","plan_date":sys.argv[1],"crew_size":5,
   "currency":"IDR","price_local":2000000,"crew_local":1200000,"private_note":"MISSION-PRIVATE-789",
   "consent":True,"media":[]}
for a in sys.argv[2:]:
  if a.startswith("-"): d.pop(a[1:], None); continue
  k,v=a.split("=",1)
  if k.endswith(":"): d[k[:-1]]=json.loads(v)
  elif k=="media": d[k]=[x for x in v.split(",") if x]
  else: d[k]=v
print(json.dumps(d))' "$PLAN" "$@"; }
# mpost <token> [changes]: POST /api/mission. Prints the status, the body goes to $T/m.json.
mpost() { local k=$1; shift; curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/mission?k=$k" -H 'content-type: application/json' -d "$(mbody "$@")"; }
mj()    { jget "$1" < "$T/m.json"; }
# act <id> <action> [extra JSON members]: POST /api/admin/missions/decide. Status out, body in $T/m.json.
act()   { curl -s -o "$T/m.json" -w '%{http_code}' -X POST $B/api/admin/missions/decide -H "$A" -H 'content-type: application/json' \
            -d "{\"id\":\"$1\",\"action\":\"$2\"${3:+,$3}}"; }
# wd <token> <id>: POST /api/mission/withdraw. Prints the status.
wd()    { curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/mission/withdraw?k=$1" -H 'content-type: application/json' -d "{\"id\":\"$2\"}"; }
mlist() { curl -s "$B/api/admin/missions${1:+?status=$1}" -H "$A"; }
# mfind <list> <field> <value> <expr> [extra]: m = the mission in the Python expression <list> over the
# JSON on stdin (d) whose <field> is <value> (None if missing), then prints <expr>. Extra arguments
# are sys.argv[5:].
mfind() { python3 -c "
import json,sys
d=json.load(sys.stdin);m=([x for x in eval(sys.argv[1]) if str(x.get(sys.argv[2]))==sys.argv[3]] or [None])[0]
print(eval(sys.argv[4]))" "$@" 2>/dev/null; }
mq()    { mfind "d['missions']" id "$@"; }   # /api/admin/missions and GET /api/partner, by id
pubm()  { mfind "d" no "$@"; }               # /api/missions, by number
# msub <token> <mission_id or -> <media>: POST /api/submit for a cleanup (- sends no mission_id).
msub()  { local b; b=$(body $TODAY "Mission cleanup $MRUN" "$3")
          [ "$2" = - ] || b=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);d['mission_id']=sys.argv[2];print(json.dumps(d))" "$b" "$2")
          curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/submit?k=$1" -H 'content-type: application/json' -d "$b"; }
sdec()  { curl -s -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' -d "$1" | jget "d['status']"; }
# sdst <JSON>: POST /api/admin/decide. Prints the status, the body goes to $T/m.json.
sdst()  { curl -s -o "$T/m.json" -w '%{http_code}' -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' -d "$1"; }
# gone <url>: the status of <url>, asked up to 3 times a second apart until it is 404 (R2 deletes may
# finish just after the response).
gone()  { local st i; for i in 1 2 3; do st=$(code "$1"); [ "$st" = 404 ] && break; sleep 1; done; echo "$st"; }
# m404 <no>: "404 friendly" when /m/<no> answers 404 with the small page that says the mission is no
# longer on the map, links to the globe (/) and to the list of missions (/missions), and carries generic
# Sapu Earth tags. Otherwise the status and "plain". The page stays in $T/m404.html.
m404()  { local st; st=$(curl -s -o "$T/m404.html" -w '%{http_code}' "$B/m/$1")
          if grep -qF 'This mission is no longer on the map.' "$T/m404.html" && grep -qE 'href="/"' "$T/m404.html" \
             && grep -qF '<p><a href="/missions">See the missions on sapu.earth</a></p>' "$T/m404.html" \
             && grep -qiE 'property="og:(title|site_name)" content="[^"]*sapu earth' "$T/m404.html"; then
            echo "$st friendly"; else echo "$st plain"; fi; }
# wiped <id> <place>: over a mission list on stdin, (removed_why, private_note, lat, lng, place kept,
# task kept). A removal wipes the private note and the exact point; place and task stay as the record.
wiped() { mq "$1" "(m['removed_why'], m['private_note'], m['lat'], m['lng'], m['place_name']==sys.argv[5], bool(m['task']))" "$2"; }
# Only with STATE: rows written straight into the local D1 file.
sq()    { if [ -n "$1" ]; then printf "'%s'" "$1"; else printf NULL; fi; }
# mrow <partner id> <id> <status> <plan_date> <created> [published] [funded] [funded_eur] [advance_eur]:
# an INSERT for a mission with a private note and an exact point. The number is the next free one.
mrow()  { printf "INSERT INTO missions (id, no, partner_id, status, place_name, country, lat, lng, task, plan_date, crew_size, currency, price_local, crew_local, private_note, consent, created_at, published_at, funded_at, funded_eur, advance_eur) SELECT '%s', COALESCE(MAX(no), 0) + 1, '%s', '%s', 'Old mission $MRUN', 'PH', 10.312345, 123.891234, 'e2e', '%s', 3, 'PHP', 1000, 600, 'OLD-PRIVATE-$MRUN', 1, '%s', %s, %s, %s, %s FROM missions;" \
            "$2" "$1" "$3" "$4" "$5" "$(sq "${6:-}")" "$(sq "${7:-}")" "${8:-NULL}" "${9:-NULL}"; }

ML=$(mlist)
R0=$(echo "$ML" | jget "d['counts']['review']"); O0=$(echo "$ML" | jget "d['counts']['open']")
F0=$(echo "$ML" | jget "d['counts']['funded']"); E0=$(echo "$ML" | jget "d['month_eur'] or 0")
check "admin missions without token -> 401" "$(code $B/api/admin/missions)" 401
[[ $R0 =~ ^[0-9]+$ && $O0 =~ ^[0-9]+$ && $F0 =~ ^[0-9]+$ ]] && ok "admin missions list has counts for review, open and funded" || bad "admin missions counts" "$ML"
NO0=
[ -n "$STATE" ] && NO0=$(d1 "SELECT COALESCE(MAX(no), 0) AS n FROM missions" | jget "d[0]['results'][0]['n']")

check "mission with an invalid link -> 404" "$(mpost bad "media=$N1A")" 404
REF1=$(openssl rand -hex 16)
M1ARGS=("client_ref=$REF1" "place_name=$MPLACE" "media=$N1A,$N1B")
st=$(mpost $MT "${M1ARGS[@]}"); M1=$(mj "d['id']"); NO1=$(mj "d['no']")
[[ $st = 201 && $M1 =~ ^[a-z2-7]{10}$ && $NO1 =~ ^[1-9][0-9]*$ ]] && ok "mission 1 with 2 now photos -> 201 (#$NO1)" || bad "mission 1" "$st $(cat "$T/m.json")"
[ -n "$NO0" ] && check "mission numbers go on from the highest one (1 on a fresh database)" "$NO1" "$(add "$NO0" 1)"
st=$(mpost $MT "${M1ARGS[@]}")
check "mission 1 sent again (same client_ref) -> 200, same id and number" "$st $(mj "d['id']") $(mj "d['no']") $(mj "d.get('repeated')")" "200 $M1 $NO1 True"
# The crew changed the form after a lost answer and sent it again. While nobody has acted on the
# mission, the stored one takes the changes, photos included (a photo taken out becomes a loose file).
N1C=$(upk $MT before)
st=$(mpost $MT "${M1ARGS[@]}" "place_name=Edited $MRUN" "media=$N1A,$N1C")
check "mission 1 sent again with changes while in review -> 200, same id and number, updated" \
  "$st $(mj "d['id']") $(mj "d['no']") $(mj "d.get('updated')")" "200 $M1 $NO1 True"
check "admin: mission 1 has the new place and photos" \
  "$(mlist | mq "$M1" "(m['place_name'], sorted(p['key'] for p in m['now'])==sorted(['$N1A','$N1C']))")" "('Edited $MRUN', True)"
st=$(mpost $MT "${M1ARGS[@]}" "media=$N1A,$K2A")
check "changes with another crew's photo -> 400 (media), mission 1 untouched" \
  "$st $(mj "d.get('code')") $(mlist | mq "$M1" "(m['place_name'], len(m['now']))")" "400 media ('Edited $MRUN', 2)"
st=$(mpost $MT "${M1ARGS[@]}")
check "sent again as first written -> 200 updated, back to its place and photos" \
  "$st $(mj "d.get('updated')") $(mlist | mq "$M1" "(m['place_name']==sys.argv[5], sorted(p['key'] for p in m['now'])==sorted(['$N1A','$N1B']))" "$MPLACE")" \
  "200 True (True, True)"
# PUBLISH and FUND carry the revision the /admin/ card showed: a crew edit in between makes them refuse.
RV=$(mlist | mq "$M1" "m['revision']")
[[ $RV =~ ^[0-9a-f]{16}$ ]] && ok "admin: each mission carries a revision" || bad "admin revision" "[$RV]"
st=$(mpost $MT "${M1ARGS[@]}" "place_name=Edited again $MRUN")
check "publish with the revision from before a crew edit -> 409 (changed), mission 1 stays in review" \
  "$st $(act "$M1" publish "\"revision\":\"$RV\"") $(mj "d.get('code')") $(mlist | mq "$M1" "m['status']")" "200 409 changed review"
st=$(mpost $MT "${M1ARGS[@]}")
check "the crew's edit undone -> the revision the card showed matches again" "$st $(mlist | mq "$M1" "m['revision']")" "200 $RV"
# Changes count as an edit for 2 hours after posting (MISSION_LIMITS.editMinutes). Later they are a new mission.
if [ -n "$STATE" ]; then
  C1=$(d1 "SELECT created_at FROM missions WHERE id = '$M1'" | jget "d[0]['results'][0]['created_at']")
  H3=$(python3 -c "import datetime as t;print((t.datetime.now(t.timezone.utc)-t.timedelta(hours=3)).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")
  if [ -n "$C1" ] && d1 "UPDATE missions SET created_at = '$H3' WHERE id = '$M1'" >/dev/null; then
    st=$(mpost $MT "${M1ARGS[@]}" "place_name=Edited too late $MRUN")
    check "changes sent 3 hours after posting -> 409 (client_ref), mission 1 unchanged" \
      "$st $(mj "d.get('code')") $(mlist | mq "$M1" "m['place_name']==sys.argv[5]" "$MPLACE")" "409 client_ref True"
    st=$(mpost $MT "${M1ARGS[@]}")
    check "sent unchanged 3 hours after posting -> 200, same id (a lost answer)" "$st $(mj "d['id']") $(mj "d.get('repeated')")" "200 $M1 True"
    d1 "UPDATE missions SET created_at = '$C1' WHERE id = '$M1'" >/dev/null
  else
    bad "age mission 1 in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

st=$(mpost $MT consent:=false "media=$N2"); check "mission without consent -> 400 (consent)" "$st $(mj "d.get('field')")" "400 consent"
RL=$(mpost $MT "plan_date=$(dplus -3)" "media=$N2")
RL="$RL $(mpost $MT "plan_date=$(dplus 130)" "media=$N2")"
RL="$RL $(mpost $MT "plan_date=${PLAN%-*}-32" "media=$N2")"
check "planned day 3 days ago, 130 days ahead, or day 32 -> 400 each" "$RL" "400 400 400"
check "crew share above the price -> 400" "$(mpost $MT crew_local:=2500000 "media=$N2")" 400
check "price 0 -> 400" "$(mpost $MT price_local:=0 "media=$N2")" 400
check "mission without a task -> 400" "$(mpost $MT -task "media=$N2")" 400
check "mission with lat but no lng -> 400" "$(mpost $MT -lng "media=$N2")" 400
check "client_ref that is not 32 hex -> 400" "$(mpost $MT client_ref=XYZ "media=$N2")" 400
check "mission without photos -> 400" "$(mpost $MT media=)" 400
check "mission with 5 photos -> 400" "$(mpost $MT "media=$N2,$N3,$N4,$N5,$N6")" 400
st=$(mpost $MT "media=$K2A"); check "another crew's photo -> 400 (media)" "$st $(mj "d.get('code')")" "400 media"
st=$(mpost $MT "media=$N1A"); check "a photo mission 1 already uses -> 400 (media)" "$st $(mj "d.get('code')")" "400 media"
st=$(mpost $MT "media=$CA"); check "an after photo as a now photo -> 400 (media)" "$st $(mj "d.get('code')")" "400 media"

st=$(mpost $MT "place_name=Decline me $MRUN" "media=$N2"); M2=$(mj "d['id']")
check "mission 2 -> 201, numbered right after mission 1 (refused posts use no number)" "$st $(mj "d['no']")" "201 $(add "$NO1" 1)"
REF3=$(openssl rand -hex 16)
st=$(mpost $MT "client_ref=$REF3" "place_name=Withdraw me $MRUN" "plan_date=$(dplus 0)" "media=$N3"); M3=$(mj "d['id']")
check "mission 3 planned for today -> 201" "$st" 201
st=$(mpost $MT "place_name=Remove me $MRUN" "media=$N4"); M4=$(mj "d['id']"); NO4=$(mj "d['no']")
check "mission 4 -> 201" "$st" 201
st=$(mpost $MT "place_name=Deactivate me $MRUN" "plan_date=$(dplus 120)" "media=$N5"); M5=$(mj "d['id']")
check "mission 5 planned 120 days ahead -> 201" "$st" 201
st=$(mpost $MT "media=$N6"); check "a 6th mission while 5 wait -> 429 (limit)" "$st $(mj "d.get('code')")" "429 limit"

check "a mission in review is not in /api/missions" "$(curl -s $B/api/missions | pubm "$NO1" "m")" None
check "/m/<no> of a mission in review -> 404, the small page that links to the globe" "$(m404 $NO1)" "404 friendly"
grep -qE 'Canggu|MISSION-PRIVATE-789' "$T/m404.html" && bad "the 404 page of a mission in review shows its place or note" "" || ok "the 404 page of a mission in review says nothing about it"
check "now photo of a mission in review is not public" "$(code $B/media/$N1A)" 404
check "/m/<unknown number> -> 404, the small page that links to the globe" "$(m404 999999999)" "404 friendly"
check "/m/<letters, 10 digits> -> 404" "$(code $B/m/abc) $(code $B/m/1234567890)" "404 404"

ML=$(mlist)
check "admin: 5 more missions waiting for review" "$(echo "$ML" | jget "d['counts']['review']")" "$(add "$R0" 5)"
check "admin: mission 1 with crew, exact point and private note, no client_ref, no contact" \
  "$(echo "$ML" | mq "$M1" "(m['no'], m['status'], m['partner_slug'], m['lat'], m['lng'], m['private_note'], 'client_ref' in m, m['contact'], m['overdue'])")" \
  "($NO1, 'review', '$MSLUG', -8.659412, 115.130087, 'MISSION-PRIVATE-789', False, None, False)"
check "admin: mission 1 lists both now photos" "$(echo "$ML" | mq "$M1" "sorted(p['key'] for p in m['now'])==sorted(['$N1A','$N1B'])")" True
MNOW=$(echo "$ML" | mq "$M1" "'\n'.join(p['url'] for p in m['now'])")
n=0
while read -r u; do
  [ -n "$u" ] || continue
  n=$((n+1))
  check "mission 1 now photo $n: signed link -> 200 image/jpeg" "$(curl -s -o $T/mp.jpg -w '%{http_code} %{content_type}' "$B$u")" "200 image/jpeg"
  cmp -s $T/mp.jpg $F/before.jpg && ok "mission 1 now photo $n is byte-exact" || bad "mission 1 now photo $n bytes differ" "$u"
done <<< "$MNOW"
check "mission 1 has 2 signed now photo links" "$n" 2
S2=$(echo "$ML" | mq "$M2" "m['now'][0]['url']"); S3=$(echo "$ML" | mq "$M3" "m['now'][0]['url']")
S5=$(echo "$ML" | mq "$M5" "m['now'][0]['url']")
check "signed links for the photos of missions 2, 3 and 5 work" "$(code "$B${S2:-/media/none}") $(code "$B${S3:-/media/none}") $(code "$B${S5:-/media/none}")" "200 200 200"

check "decide: unknown action, bad id, unknown id -> 400 400 404" "$(act "$M4" boost) $(act ../x publish) $(act aaaaaaaaaa publish)" "400 400 404"
check "fund without an amount, with EUR 0, with a 101% advance -> 400 each" \
  "$(act "$M4" fund) $(act "$M4" fund '"funded_eur":0') $(act "$M4" fund '"funded_eur":10,"advance_pct":101')" "400 400 400"

# Open: on the globe and the share page, photos public.
RV1=$(mlist | mq "$M1" "m['revision']")
check "publish mission 1 (with the revision the list showed) -> 200" "$(act "$M1" publish "\"revision\":\"$RV1\"")" 200
check "publish it again -> 409" "$(act "$M1" publish)" 409
st=$(mpost $MT "${M1ARGS[@]}" "place_name=Edited after publish $MRUN")
check "mission 1 sent again with changes once published -> 409 (client_ref), mission unchanged" \
  "$st $(mj "d.get('code')") $(mlist open | mq "$M1" "m['place_name']==sys.argv[5]" "$MPLACE")" "409 client_ref True"
st=$(mpost $MT "${M1ARGS[@]}")
check "mission 1 sent again unchanged once published -> 200, same id (a lost answer)" "$st $(mj "d['id']") $(mj "d.get('repeated')")" "200 $M1 True"
PM=$(curl -s -D $T/pm.h $B/api/missions)
check "/api/missions: mission 1 open, point rounded, both now photos, share link, crew, no EUR yet" \
  "$(echo "$PM" | pubm "$NO1" "(m['status'], m['lat'], m['lng'], sorted(m['now'])==sorted(['/media/$N1A','/media/$N1B']), m['url'], m['partner']['slug'], m.get('funded_eur'))")" \
  "('open', -8.659, 115.13, True, 'https://sapu.earth/m/$NO1', '$MSLUG', None)"
check "/api/missions: mission 1 as sent" \
  "$(echo "$PM" | pubm "$NO1" "(m['place_name']==sys.argv[5], m['date'], m['country'], m['crew_size'], m['currency'], m['price_local'], m['crew_local'], m['task'].count(chr(10)))" "$MPLACE")" \
  "(True, '$PLAN', 'ID', 5, 'IDR', 2000000, 1200000, 1)"
check "/api/missions: only public fields (the crew's name, slug and live logo)" \
  "$(echo "$PM" | pubm "$NO1" "sorted(set(m) - {'no','status','date','place_name','country','lat','lng','crew_size','task','currency','price_local','crew_local','funded_eur','partner','now','now_video','url'}) + sorted(set(m['partner']) - {'name','slug','logo'})")" "[]"
check "/api/missions: mission 1 has no video (now_video null)" "$(echo "$PM" | pubm "$NO1" "('now_video' in m, m.get('now_video'))")" "(True, None)"
echo "$PM" | grep -qE 'MISSION-PRIVATE-789|client_ref|private_note|review_note|advance_eur|659412|130087' \
  && bad "/api/missions leaks a private field or the exact point" "" || ok "/api/missions has no private fields and no exact point"
grep -qi 'cache-control: public, max-age=60' $T/pm.h && ok "/api/missions cache-control" || bad "/api/missions cache" "$(cat $T/pm.h)"
check "/m/<no> of an open mission -> 200" "$(code $B/m/$NO1)" 200
MG=$(curl -s $B/m/$NO1)
echo "$MG" | grep -qF "property=\"og:title\" content=\"Mission #$NO1: $MPLACE_ESC" && ok "/m og:title of an open mission, escaped" || bad "/m og:title" "$(echo "$MG" | grep og:title)"
echo "$MG" | grep -qF 'property="og:description" content="A local crew of 5 wants to clean' \
  && echo "$MG" | grep -qF 'Asking IDR 2,000,000 in all: IDR 240,000 for each person and IDR 800,000 for other costs.' \
  && ok "/m og:description of an open mission, with its price as it adds up (5 × IDR 240,000 and the other costs)" || bad "/m og:description" "$(echo "$MG" | grep og:desc)"
echo "$MG" | grep -qE "property=\"og:image\" content=\"$B/media/($N1A|$N1B)\"" && ok "/m og:image is an absolute now photo" || bad "/m og:image" "$(echo "$MG" | grep og:image)"
echo "$MG" | grep -q "url=/#m-$NO1\"" && echo "$MG" | grep -q "location.replace(\"/#m-$NO1\")" && ok "/m redirects an open mission to /#m-<no>" || bad "/m redirect" "$(echo "$MG" | grep -E 'refresh|replace')"
echo "$MG" | grep -q '<b>Canggu' && bad "/m contains raw HTML from the place name" "" || ok "/m has no raw HTML from the place name"
echo "$MG" | grep -q 'MISSION-PRIVATE-789' && bad "/m leaks the private note" "" || ok "/m has no private note"
echo "$MG" | grep -q 'og:video' && bad "/m of a mission without a video names one" "$(echo "$MG" | grep og:video)" || ok "/m of a mission without a video has no og:video"
H=$(curl -s -D - -o $T/mn.jpg $B/media/$N1A)
echo "$H" | head -1 | grep -q 200 && echo "$H" | grep -qi 'cache-control: public, max-age=3600' && ! echo "$H" | grep -qi immutable && cmp -s $T/mn.jpg $F/before.jpg \
  && ok "now photo of an open mission is public (cached 1 hour, not immutable), byte-exact" || bad "open mission photo" "$H"

check "fund with a revision that is not the mission's -> 409 (changed)" \
  "$(act "$M1" fund '"funded_eur":120,"revision":"0000000000000000"') $(mj "d.get('code')")" "409 changed"
# Funded: the advance is 30% unless the admin says otherwise.
st=$(act "$M1" fund '"funded_eur":120,"review_note":"MISSION-REVIEW-321"')
check "fund mission 1 with EUR 120 (30% advance by default) -> 200, advance 36, rest 84" "$st $(mj "(round(float(d['advance_eur']), 2), round(float(d['rest_eur']), 2))")" "200 (36.0, 84.0)"
check "wrong state -> 409: publish, fund, decline or remove funded mission 1, cancel mission 5 in review" \
  "$(act "$M1" publish) $(act "$M1" fund '"funded_eur":5') $(act "$M1" decline) $(act "$M1" remove) $(act "$M5" cancel)" "409 409 409 409 409"
check "admin: mission 1 funded with EUR 120, advance EUR 36" \
  "$(mlist funded | mq "$M1" "(m['status'], m['funded_eur'], round(float(m['advance_eur']), 2), m['funded_at'] is not None, m['published_at'] is not None, m['review_note'])")" \
  "('funded', 120, 36.0, True, True, 'MISSION-REVIEW-321')"
PM=$(curl -s $B/api/missions)
check "/api/missions: mission 1 funded with EUR 120" "$(echo "$PM" | pubm "$NO1" "(m['status'], m['funded_eur'])")" "('funded', 120)"
echo "$PM" | grep -qE 'MISSION-REVIEW-321|advance_eur' && bad "/api/missions shows the review note or the advance" "" || ok "/api/missions shows no review note and no advance"
MG=$(curl -s $B/m/$NO1)
echo "$MG" | grep -qF "property=\"og:title\" content=\"Mission #$NO1 is funded: $MPLACE_ESC" && ok "/m og:title of a funded mission" || bad "/m funded og:title" "$(echo "$MG" | grep og:title)"
echo "$MG" | grep -q "location.replace(\"/#m-$NO1\")" && ok "/m redirects a funded mission to /#m-<no>" || bad "/m funded redirect" ""
PA=$(curl -s "$B/api/partner?k=$MT")
check "GET /api/partner: mission 1 funded, with the advance and its share link" \
  "$(echo "$PA" | mq "$M1" "(m['no'], m['status'], m['funded_eur'], round(float(m['advance_eur']), 2), m['share_url'], m['place_name']==sys.argv[5])" "$MPLACE")" \
  "($NO1, 'funded', 120, 36.0, 'https://sapu.earth/m/$NO1', True)"
check "GET /api/partner: a mission in review has no share link" "$(echo "$PA" | mq "$M2" "(m['status'], m['share_url'])")" "('review', None)"
# country, crew_size and cleanup_sent are for the crew page (a cleanup opened from a funded mission's card starts on
# them, and a mission whose cleanup was sent offers none), plan for its costs line and the one-tap task and price of
# POST A MISSION. Never the exact point, the notes or the client_ref.
check "GET /api/partner: only the listed mission fields" \
  "$(echo "$PA" | jget "sorted(set(k for m in d['missions'] for k in m) - {'id','no','place_name','plan_date','status','removed_why','funded_eur','advance_eur','share_url','country','crew_size','cleanup_sent','plan'})")" "[]"
check "GET /api/partner: mission 1 carries its plan as posted (task, currency, price, crew share), mission 2 in review too" \
  "$(echo "$PA" | mq "$M1" "(m['plan']['task']=='Clear the river mouth.\\nSort the plastic for the waste bank.', m['plan']['currency'], m['plan']['price_local'], m['plan']['crew_local'], sorted(m['plan']))") $(echo "$PA" | mq "$M2" "(m['status'], m['plan']['price_local'], m['plan']['crew_local'])")" \
  "(True, 'IDR', 2000000, 1200000, ['crew_local', 'currency', 'price_local', 'task']) ('review', 2000000, 1200000)"
check "GET /api/partner: mission 1 for the crew page (country, crew size, no cleanup sent yet)" \
  "$(echo "$PA" | mq "$M1" "(m['country'], m['crew_size'], m['cleanup_sent'])")" "('ID', 5, False)"
echo "$PA" | grep -qE 'MISSION-REVIEW-321|MISSION-PRIVATE-789' && bad "GET /api/partner shows a mission note" "" || ok "GET /api/partner shows no mission notes"
check "GET /api/partner: missions_enabled true (the upload page offers POST A MISSION)" "$(echo "$PA" | jget "d.get('missions_enabled')")" True

check "publish mission 4 -> 200" "$(act "$M4" publish)" 200
check "now photo of open mission 4 is public" "$(code $B/media/$N4)" 200
st=$(mpost $OT "place_name=Other crew $MRUN" country=PH currency=PHP price_local:=5000 crew_local:=3000 "media=$K2A"); MX=$(mj "d['id']")
check "crew 2's mission with the photo refused for crew 1 -> 201" "$st" 201
st=$(act "$MX" fund '"funded_eur":50,"advance_pct":50')
check "fund it straight from review with a 50% advance -> 200, advance 25, rest 25" "$st $(mj "(round(float(d['advance_eur']), 2), round(float(d['rest_eur']), 2))")" "200 (25.0, 25.0)"
check "admin counts and funded this month: +3 review, +1 open, +2 funded, +EUR 170" \
  "$(mlist | jget "(d['counts']['review']-$R0, d['counts']['open']-$O0, d['counts']['funded']-$F0, round(float(d['month_eur'] or 0) - $E0, 2))")" "(3, 1, 2, 170.0)"

# The cleanup for mission 1.
st=$(msub $MT "$M4" "$CB,$CA"); check "cleanup for an open (not funded) mission -> 400 (mission)" "$st $(mj "d.get('code')")" "400 mission"
st=$(msub $MT "$MX" "$CB,$CA"); check "cleanup for another crew's funded mission -> 400 (mission)" "$st $(mj "d.get('code')")" "400 mission"
check "cleanup with a malformed mission_id -> 400" "$(msub $MT "../x" "$CB,$CA")" 400
st=$(msub $MT - "$N5,$CA2"); check "a cleanup cannot take a mission's now photo -> 400 (media)" "$st $(mj "d.get('code')")" "400 media"
st=$(msub $MT "$M1" "$CB,$CA"); SUBM=$(mj "d['id']")
[[ $st = 200 && $SUBM =~ ^[a-z2-7]{10}$ ]] && ok "cleanup for funded mission 1 -> 200 ($SUBM)" || bad "mission cleanup" "$st $(cat "$T/m.json")"
st=$(msub $MT "$M1" "$CB2,$CA2"); check "a second cleanup for mission 1 while one is pending -> 409 (mission)" "$st $(mj "d.get('code')")" "409 mission"
# The phone lost the answer and sends the same cleanup again: it gets its reference back, not a 409.
st=$(msub $MT "$M1" "$CB,$CA"); check "the mission cleanup sent again (same files, lost answer) -> 200, same id" "$st $(mj "d.get('id')") $(mj "d.get('repeated')")" "200 $SUBM True"
check "GET /api/partner: mission 1 says its cleanup was sent" "$(curl -s "$B/api/partner?k=$MT" | mq "$M1" "m['cleanup_sent']")" True
check "admin pending list: the cleanup carries mission 1" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[s.get('mission_id') for s in d['submissions'] if s['id']=='$SUBM']")" "['$M1']"
check "admin pending list: the mission block has the mission's point, rounded to 3 decimals (never the exact one)" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[((s.get('mission') or {}).get('lat'), (s.get('mission') or {}).get('lng')) for s in d['submissions'] if s['id']=='$SUBM']")" "[(-8.659, 115.13)]"
check "approve the mission cleanup" "$(sdec "{\"id\":\"$SUBM\",\"action\":\"approve\",\"paid_eur\":120,\"crew_eur\":72,\"ops_eur\":48}")" approved
check "mission 1 is done, linked to the cleanup" "$(mlist done | mq "$M1" "(m['status'], m['submission_id'], m['closed_at'] is not None)")" "('done', '$SUBM', True)"
st=$(msub $MT "$M1" "$CB,$CA"); check "sent again once the mission is done (lost answer) -> 200, same id" "$st $(mj "d.get('id')") $(mj "d.get('repeated')")" "200 $SUBM True"
EV=$(curl -s $B/api/events)
check "/api/events: the receipt has the mission block, with what the crew asked in local money and the crew size it was added up for" \
  "$(echo "$EV" | jget "[(e['mission']['no'], e['mission']['url'], sorted(e['mission']['now'])==sorted(['/media/$N1A','/media/$N1B']), e['mission']['funded_eur'], e['mission']['currency'], e['mission']['price_local'], e['mission']['crew_local'], e['mission']['crew_size']) for e in d if e['id']=='$SUBM']")" \
  "[($NO1, 'https://sapu.earth/m/$NO1', True, 120, 'IDR', 2000000, 1200000, 5)]"
check "/api/events: the mission block has only its public fields" \
  "$(echo "$EV" | jget "[sorted(set(e['mission']) - {'no','url','now','now_video','funded_eur','currency','price_local','crew_local','crew_size'}) for e in d if e['id']=='$SUBM']")" "[[]]"
check "/api/events: mission 1 had no video (now_video null)" "$(echo "$EV" | jget "[e['mission'].get('now_video', 'missing') for e in d if e['id']=='$SUBM']")" "[None]"
check "/api/events: a receipt without a mission has no mission block" "$(echo "$EV" | jget "[e.get('mission') for e in d if e['id']=='$ID']")" "[None]"
echo "$EV" | grep -qE 'MISSION-PRIVATE-789|MISSION-REVIEW-321|advance_eur' && bad "/api/events leaks a mission note or the advance" "" || ok "/api/events has no mission notes"
check "/api/missions no longer lists the done mission" "$(curl -s $B/api/missions | pubm "$NO1" "m")" None
MG=$(curl -s $B/m/$NO1)
echo "$MG" | grep -qF "property=\"og:title\" content=\"Mission #$NO1 done: $MPLACE_ESC" && ok "/m og:title of a done mission" || bad "/m done og:title" "$(echo "$MG" | grep og:title)"
echo "$MG" | grep -qE 'property="og:description" content="[^"]*120\.5 kg' && ok "/m og:description of a done mission has the kg" || bad "/m done og:description" "$(echo "$MG" | grep og:desc)"
echo "$MG" | grep -q "property=\"og:image\" content=\"$B/media/$CA\"" && ok "/m og:image of a done mission is the after photo" || bad "/m done og:image" "$(echo "$MG" | grep og:image)"
echo "$MG" | grep -q "url=/#ev-$SUBM\"" && echo "$MG" | grep -q "location.replace(\"/#ev-$SUBM\")" && ok "/m redirects a done mission to /#ev-<id>" || bad "/m done redirect" "$(echo "$MG" | grep -E 'refresh|replace')"
check "now photo of a done mission stays public" "$(code $B/media/$N1A)" 200
check "GET /api/partner: mission 1 done with its share link" "$(curl -s "$B/api/partner?k=$MT" | mq "$M1" "(m['status'], m['share_url'])")" "('done', 'https://sapu.earth/m/$NO1')"
# The crew page folds COSTS for a mission cleanup: left closed, the cleanup goes with total_cost_local and crew_pay_local
# null, and the receipt shows what the crew asked from the mission block (ASKED, CREW PAY and OTHER COSTS in site/app.js
# localRows). A crew of its own, so no count above or below moves.
NCJ=$(newp "No Costs Crew $MRUN" ID "nocost-$MRUN"); NCT=$(echo "$NCJ" | jget "d['token']")
NCN=$(upk $NCT before); NCB=$(upk $NCT before); NCA=$(upk $NCT after)
st=$(mpost $NCT "place_name=No costs $MRUN" price_local:=1000000 crew_local:=700000 "media=$NCN"); NCM=$(mj "d['id']")
st="$st $(act "$NCM" fund '"funded_eur":50')"
NCBODY=$(body $TODAY "No costs $MRUN" "$NCB,$NCA" | python3 -c "import json,sys;d=json.load(sys.stdin);d.update(mission_id=sys.argv[1],total_cost_local=None,crew_pay_local=None);print(json.dumps(d))" "$NCM")
st="$st $(curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/submit?k=$NCT" -H 'content-type: application/json' -d "$NCBODY")"; NCS=$(mj "d.get('id')")
st="$st $(sdec "{\"id\":\"${NCS:-none}\",\"action\":\"approve\",\"paid_eur\":50}")"
check "a mission cleanup sent without costs: the receipt has no local crew number of its own and the mission block says what the crew asked" \
  "$st $(curl -s $B/api/events | jget "[(e['local_money']['total'], e['local_money']['crew'], e['mission']['currency'], e['mission']['price_local'], e['mission']['crew_local']) for e in d if e['id']=='${NCS:-none}']")" \
  "201 200 200 approved [(None, None, 'IDR', 1000000, 700000)]"

# Decline, withdraw, remove.
check "decline mission 2 -> 200" "$(act "$M2" decline)" 200
check "the declined mission's photo is deleted (signed link -> 404)" "$(gone "$B${S2:-/media/none}")" 404
check "mission 2 removed (declined), no photos left" "$(mlist removed | mq "$M2" "(m['status'], m['removed_why'], m['now'], m['closed_at'] is not None)")" "('removed', 'declined', [], True)"
check "declined: private note and exact point wiped, place and task kept" "$(mlist removed | wiped "$M2" "Decline me $MRUN")" "('declined', None, None, None, True, True)"
[ -n "$STATE" ] && check "the declined mission's upload row is gone" "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE key = '$N2'" | jget "d[0]['results'][0]['n']")" 0
check "decline it again -> 409" "$(act "$M2" decline)" 409
check "withdraw another crew's mission -> 404, with an invalid link -> 404" "$(wd $MT "$MX") $(wd bad "$M3")" "404 404"
check "withdraw a funded mission -> 409" "$(wd $OT "$MX")" 409
check "withdraw mission 3 -> 200" "$(wd $MT "$M3")" 200
check "the withdrawn mission's photo is deleted (signed link -> 404)" "$(gone "$B${S3:-/media/none}")" 404
check "GET /api/partner: mission 3 removed (withdrawn), no share link" "$(curl -s "$B/api/partner?k=$MT" | mq "$M3" "(m['status'], m['removed_why'], m['share_url'])")" "('removed', 'withdrawn', None)"
check "withdrawn: private note and exact point wiped, place and task kept" "$(mlist removed | wiped "$M3" "Withdraw me $MRUN")" "('withdrawn', None, None, None, True, True)"
check "GET /api/partner: a removed mission has no plan (withdrawn mission 3, declined mission 2), so its price is never offered again" \
  "$(curl -s "$B/api/partner?k=$MT" | mq "$M3" "m['plan']") $(curl -s "$B/api/partner?k=$MT" | mq "$M2" "m['plan']")" "None None"
check "withdraw it again -> 409, withdraw the done mission -> 409" "$(wd $MT "$M3") $(wd $MT "$M1")" "409 409"
st=$(mpost $MT "client_ref=$REF3" "place_name=Withdraw me $MRUN" "plan_date=$(dplus 0)" "media=$N3")
check "mission 3 sent again after it was withdrawn -> 409 (client_ref), so the page posts it as a new one" "$st $(mj "d.get('code')")" "409 client_ref"
st=$(mpost $MT "place_name=Deactivate me too $MRUN" "media=$N6"); M6=$(mj "d['id']"); NO6=$(mj "d['no']")
check "with missions done, declined and withdrawn there is room again: mission 6 -> 201" "$st" 201
check "GET /api/partner lists the newest mission first" "$(curl -s "$B/api/partner?k=$MT" | jget "d['missions'][0]['id']")" "$M6"
check "publish mission 6 -> 200, /m/<no> -> 200" "$(act "$M6" publish) $(code $B/m/$NO6)" "200 200"
check "remove open mission 4 -> 200" "$(act "$M4" remove)" 200
check "mission 4 removed (cancelled), photo no longer public, /m/<no> -> the 404 page that links to the globe" \
  "$(mlist removed | mq "$M4" "(m['status'], m['removed_why'])") $(gone $B/media/$N4) $(m404 $NO4)" "('removed', 'cancelled') 404 404 friendly"
check "removed: private note and exact point wiped, place and task kept" "$(mlist removed | wiped "$M4" "Remove me $MRUN")" "('cancelled', None, None, None, True, True)"

if [ -n "$STATE" ]; then
  # The 48-hour orphan cleanup only takes files that belong to no cleanup and no mission. Age two loose
  # files and two mission photos (done mission 1, waiting mission 5), then an upload starts the cleanup.
  if d1 "UPDATE uploads SET created_at = '$(ago 3)' WHERE key IN ('$N1A', '$N5', '$CB2', '$CA2')" >/dev/null; then
    TRIG=$(upk $MT before)
    [[ $TRIG =~ ^[0-9a-f]{32}$ ]] && ok "an upload starts the orphan cleanup" || bad "orphan cleanup trigger upload" "$TRIG"
    want=$(python3 -c "import sys;print(sorted(sys.argv[1:]))" "$N1A" "$N5")
    for i in 1 2 3; do
      got=$(d1 "SELECT key FROM uploads WHERE key IN ('$N1A', '$N5', '$CB2', '$CA2')" | jget "sorted(r['key'] for r in d[0]['results'])")
      [ "$got" = "$want" ] && break; sleep 1
    done
    check "the orphan cleanup deleted the 3-day-old loose files and kept the mission photos" "$got" "$want"
    check "the done mission's photo is still public, the waiting mission's photo still opens for /admin/" "$(code $B/media/$N1A) $(code "$B${S5:-/media/none}")" "200 200"
  else
    bad "age uploads in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # Deploy order: if the code goes live before migration 0004, the homepage, the receipts and the
  # upload page must keep working. The missions table is renamed for a moment (finish() renames it
  # back if the script stops in between).
  MRENAMED=1
  if d1 "ALTER TABLE missions RENAME TO missions_e2e_off" >/dev/null; then
    W1=$(curl -s -w '\n%{http_code}' $B/api/missions)
    W2=$(curl -s -w '\n%{http_code}' $B/api/events)
    W3=$(curl -s -w '\n%{http_code}' "$B/api/partner?k=$MT")
    W4=$(m404 $NO6)
    W5="$(cxpage) $(cxq "(len(cards) > 0, all(c['cleanups'] > 0 for c in cards), card('$MSLUG') is not None, jj('$OSLUG') is not None)") $(grep -c 'href="/missions' "$T/cx.html")"
    W6="$(mxpage) $(grep -c '<h2 class="panel-title">NO MISSION IS LISTED YET</h2>' "$T/mx.html") $(grep -c '<meta name="robots" content="noindex">' "$T/mx.html") $(grep -c 'class="cx-card mx-card"' "$T/mx.html")"
    d1 "ALTER TABLE missions_e2e_off RENAME TO missions" >/dev/null && MRENAMED=
    check "without the missions table: /api/missions -> 200 []" "$(echo "$W1" | tail -1) $(echo "$W1" | sed '$d')" "200 []"
    check "without the missions table: /api/events -> 200, the mission cleanup still listed" \
      "$(echo "$W2" | tail -1) $(echo "$W2" | sed '$d' | jget "sum(e['id']=='$SUBM' for e in d)")" "200 1"
    check "without the missions table: GET /api/partner -> 200, missions_enabled false, no missions (the page hides POST A MISSION)" \
      "$(echo "$W3" | tail -1) $(echo "$W3" | sed '$d' | jget "(d.get('missions_enabled'), d.get('missions'))")" "200 (False, [])"
    check "without the missions table: /m/<no> -> the 404 page, not an error" "$W4" "404 friendly"
    check "without the missions table: /crews -> 200, on top only crews with approved cleanups (crew 1, with its mission cleanup), crew 2 (no approved cleanup) under JUST JOINED, its foot without ALL MISSIONS (the list of missions is empty then), and GET /api/partner says crew 1 is listed" \
      "$W5 $(echo "$W3" | sed '$d' | jget "d.get('listed')")" "200 (True, True, True, True) 0 True"
    check "without the missions table: /missions -> 200 with its empty state (NO MISSION IS LISTED YET, noindex, no card), not an error" "$W6" "200 1 1 0"
    check "missions table back in place" "$(code $B/api/admin/missions -H "$A")" 200
  else
    MRENAMED=
    bad "rename the missions table in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # Deploy order: if the code goes live before migration 0005, uploads, cleanups, PENDING and the receipts
  # keep working, and a video comes without its stage. The column is renamed for a moment (finish() renames
  # it back if the script stops in between).
  SRENAMED=1
  if d1 "ALTER TABLE uploads RENAME COLUMN stage TO stage_e2e_off" >/dev/null; then
    SB0=$(upk $MT before); SA0=$(upk $MT after); SV0=$(upv $MT before)
    st=$(msub $MT - "$SB0,$SA0,$SV0"); SS0=$(mj "d.get('id')")
    W5=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[[v['stage'] for v in s['media']['videos']] for s in d['submissions'] if s['id']=='$SS0']")
    W6=$(code $B/api/events)
    d1 "ALTER TABLE uploads RENAME COLUMN stage_e2e_off TO stage" >/dev/null && SRENAMED=
    check "without uploads.stage: a video sent with stage=before is stored, and its cleanup -> 200" \
      "$([[ $SV0 =~ ^[0-9a-f]{32}$ ]] && echo key) $st" "key 200"
    check "without uploads.stage: PENDING shows that video without a stage, /api/events -> 200" "$W5 $W6" "[[None]] 200"
    SV1=$(upv $MT before)
    check "uploads.stage back in place: a video sent with stage=before keeps it" \
      "$(d1 "SELECT stage FROM uploads WHERE key = '$SV1'" | jget "d[0]['results'][0]['stage']")" before
    check "reject the cleanup sent without the column, so nothing waits in PENDING" "$(sdec "{\"id\":\"${SS0:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
  else
    SRENAMED=
    bad "rename uploads.stage in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# DEACTIVATE removes the crew's missions in review, open and funded (crew 3 below has a funded one),
# a done mission stays: it is a receipt.
check "deactivate crew 1 -> 200" "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$MPID\"}")" 200
ML=$(mlist removed)
check "DEACTIVATE removed crew 1's waiting and open missions" "$(echo "$ML" | mq "$M5" "m['removed_why']") $(echo "$ML" | mq "$M6" "m['removed_why']")" "deactivated deactivated"
check "their photos are deleted, /m/<no> of the open one -> the 404 page" "$(gone "$B${S5:-/media/none}") $(gone $B/media/$N6) $(m404 $NO6)" "404 404 404 friendly"
check "deactivated: private note and exact point wiped, place and task kept (waiting, open)" \
  "$(echo "$ML" | wiped "$M5" "Deactivate me $MRUN") $(echo "$ML" | wiped "$M6" "Deactivate me too $MRUN")" \
  "('deactivated', None, None, None, True, True) ('deactivated', None, None, None, True, True)"
check "the done mission stays done after DEACTIVATE" "$(mlist done | mq "$M1" "m['status']")" done
if [ -n "$STATE" ]; then
  # Belt and braces: an open or funded mission of a deactivated crew (written straight into the
  # local D1, DEACTIVATE never leaves one) is not on /api/missions and its /m/<no> is the 404 page.
  XDO=$(newid); XDF=$(newid)
  if d1 "$(mrow "$MPID" $XDO open $(dplus 5) $(ago 2) $(ago 1)) $(mrow "$MPID" $XDF funded $(dplus 5) $(ago 50) $(ago 45) $(ago 40) 10 3)" >/dev/null; then
    read -r DOO DOF <<< "$(d1 "SELECT id, no FROM missions WHERE id IN ('$XDO', '$XDF')" | jget "' '.join(str({r['id']: r['no'] for r in d[0]['results']}[k]) for k in ('$XDO', '$XDF'))")"
    [[ ${DOO:-} =~ ^[1-9][0-9]*$ && ${DOF:-} =~ ^[1-9][0-9]*$ ]] && ok "an open and a funded mission written for the deactivated crew (#$DOO, #$DOF)" || bad "missions of a deactivated crew" "no numbers: $DOO $DOF"
    check "missions of a deactivated crew: open and funded not on /api/missions" \
      "$(curl -s $B/api/missions | jget "[m['no'] for m in d if m['no'] in (${DOO:-0}, ${DOF:-0})]")" "[]"
    mxpage >/dev/null
    check "missions of a deactivated crew: open and funded not on /missions either" "$(mxq "[n for n in (${DOO:-0}, ${DOF:-0}) if card(n)]")" "[]"
    check "missions of a deactivated crew: /m/<no> of the open and the funded one -> the 404 page" "$(m404 ${DOO:-0}) $(m404 ${DOF:-0})" "404 friendly 404 friendly"
    d1 "UPDATE missions SET status = 'removed', removed_why = 'deactivated', closed_at = '$(ago 0)', private_note = NULL, lat = NULL, lng = NULL WHERE id IN ('$XDO', '$XDF')" >/dev/null
  else
    bad "write missions of a deactivated crew into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi
# UNPUBLISH of the approved cleanup takes the mission and its photos with it.
check "unpublish the mission cleanup" "$(sdec "{\"id\":\"$SUBM\",\"action\":\"reject\",\"review_note\":\"e2e unpublish\"}")" rejected
check "UNPUBLISH removes mission 1 (unpublished)" "$(mlist removed | mq "$M1" "(m['status'], m['removed_why'])")" "('removed', 'unpublished')"
check "its now photos are deleted, /m/<no> -> the 404 page" "$(gone $B/media/$N1A) $(gone $B/media/$N1B) $(m404 $NO1)" "404 404 404 friendly"
check "unpublished: private note and exact point wiped, place, task and money kept" \
  "$(mlist removed | mq "$M1" "(m['private_note'], m['lat'], m['lng'], m['place_name']==sys.argv[5], bool(m['task']), m['funded_eur'])" "$MPLACE")" \
  "(None, None, None, True, True, 120)"
check "the unpublished cleanup is gone from /api/events" "$(curl -s $B/api/events | jget "sum(e['id']=='$SUBM' for e in d)")" 0

# Crew 2: a rejected cleanup leaves the mission funded, so the crew can send it again.
P1B=$(upk $OT before); P1A=$(upk $OT after)
st=$(msub $OT "$MX" "$P1B,$P1A"); SX1=$(mj "d['id']")
check "crew 2 sends a cleanup for its funded mission -> 200" "$st" 200
check "reject it while pending" "$(sdec "{\"id\":\"$SX1\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
check "the mission stays funded after the rejected cleanup" "$(mlist funded | mq "$MX" "m['status']")" funded
P2B=$(upk $OT before); P2A=$(upk $OT after)
st=$(msub $OT "$MX" "$P2B,$P2A"); SX2=$(mj "d['id']")
check "the crew can send the cleanup for it again -> 200" "$st" 200
sdec "{\"id\":\"$SX2\",\"action\":\"reject\",\"review_note\":\"e2e\"}" >/dev/null

if [ -n "$STATE" ]; then
  # 28-day expiry: missions in review (by created_at) and open (by published_at) are removed with their
  # photos at the start of GET /api/admin/missions and after GET /api/missions. Old missions of crew 2
  # are written straight into the local D1 file.
  K2C=$(upk $OT before); K2V=$(upv $OT)
  XO=$(newid); XR=$(newid); XK=$(newid); XF=$(newid); XW=$(newid)
  if d1 "$(mrow "$OPID" $XO open $(dplus 5) $(ago 35) $(ago 10)) $(mrow "$OPID" $XR review $(dplus 5) $(ago 30))
         $(mrow "$OPID" $XK open $(dplus 5) $(ago 40) $(ago 10)) $(mrow "$OPID" $XF funded $(dplus -20) $(ago 50) $(ago 45) $(ago 40) 10 3)
         UPDATE uploads SET mission_id = '$XO' WHERE key IN ('$K2C', '$K2V');" >/dev/null; then
    XOU=$(mlist open | mq "$XO" "m['now'][0]['url']")
    XOV=$(mlist open | mq "$XO" "(m['now_video'] or {}).get('url')")
    check "an old open mission written into the database shows with its photo and video (signed links -> 200 200)" \
      "$(code "$B${XOU:-/media/none}") $(code "$B${XOV:-/media/none}")" "200 200"
    # A removal whose photo delete failed leaves rows behind: the next /admin/ list deletes them.
    K2D=$(upk $OT before); XS=$(newid)
    d1 "$(mrow "$OPID" $XS open $(dplus 5) $(ago 2) $(ago 2)) UPDATE uploads SET mission_id = '$XS' WHERE key = '$K2D';" >/dev/null
    XSU=$(mlist open | mq "$XS" "m['now'][0]['url']")
    d1 "UPDATE missions SET status = 'removed', removed_why = 'declined', closed_at = '$(ago 0)', private_note = NULL, lat = NULL, lng = NULL WHERE id = '$XS'" >/dev/null
    check "a removed mission's leftover photo (signed link -> 200 until the sweep)" "$(code "$B${XSU:-/media/none}")" 200
    check "GET /api/admin/missions -> 200 (runs the sweep)" "$(code $B/api/admin/missions -H "$A")" 200
    check "the sweep deleted the leftover photo row and file" \
      "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE key = '$K2D'" | jget "d[0]['results'][0]['n']") $(gone "$B${XSU:-/media/none}")" "0 404"
    d1 "UPDATE missions SET published_at = '$(ago 30)' WHERE id = '$XO'" >/dev/null
    check "GET /api/admin/missions -> 200" "$(code $B/api/admin/missions -H "$A")" 200
    check "expiry: open 30 days and in review 30 days -> removed (expired); open 10 days (posted 40 days ago) and funded stay" \
      "$(d1 "SELECT id, status, removed_why, closed_at FROM missions WHERE id IN ('$XO', '$XR', '$XK', '$XF')" | jget "sorted((r['id'], r['status'], r['removed_why'], r['closed_at'] is not None) for r in d[0]['results'])")" \
      "$(python3 -c "import sys;a=sys.argv;print(sorted([(a[1],'removed','expired',True),(a[2],'removed','expired',True),(a[3],'open',None,False),(a[4],'funded',None,False)]))" "$XO" "$XR" "$XK" "$XF")"
    check "the expired mission's photo and video rows are gone" "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE key IN ('$K2C', '$K2V')" | jget "d[0]['results'][0]['n']")" 0
    check "the expired mission's photo and video are deleted (signed links -> 404 404)" "$(gone "$B${XOU:-/media/none}") $(gone "$B${XOV:-/media/none}")" "404 404"
    ML=$(mlist removed)
    check "expired (in review, open): private note and exact point wiped; the open one that stays keeps them" \
      "$(echo "$ML" | wiped "$XO" "Old mission $MRUN") $(echo "$ML" | wiped "$XR" "Old mission $MRUN") $(mlist open | mq "$XK" "(m['private_note'], m['lat'])")" \
      "('expired', None, None, None, True, True) ('expired', None, None, None, True, True) ('OLD-PRIVATE-$MRUN', 10.312345)"
    check "/m/<no> of an expired mission -> the 404 page that links to the globe" "$(m404 "$(echo "$ML" | mq "$XO" "m['no']")")" "404 friendly"
    L=$(mlist funded)
    check "a funded mission 20 days past its day is OVERDUE, one before its day is not" "$(echo "$L" | mq "$XF" "m['overdue']") $(echo "$L" | mq "$MX" "m['overdue']")" "True False"
    d1 "$(mrow "$OPID" $XW review $(dplus 5) $(ago 35))" >/dev/null
    check "GET /api/missions -> 200" "$(code $B/api/missions)" 200
    for i in 1 2 3; do
      got=$(d1 "SELECT status, removed_why FROM missions WHERE id = '$XW'" | jget "[(r['status'], r['removed_why']) for r in d[0]['results']]")
      [ "$got" = "[('removed', 'expired')]" ] && break; sleep 1
    done
    check "after GET /api/missions the expiry runs in the background too" "$got" "[('removed', 'expired')]"

    # GET /api/partner lists every mission in review, open or funded, however old, plus the 20 newest
    # others. 21 closed missions newer than the old open and funded ones would push those out of a
    # plain "newest 20", and with them their cards on the crew page.
    RIDS=$(python3 -c "import secrets;print(' '.join(''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz234567') for _ in range(10)) for _ in range(21)))")
    D1AGO=$(ago 1); P5=$(dplus 5); q=""
    for x in $RIDS; do q="$q $(mrow "$OPID" "$x" removed "$P5" "$D1AGO")"; done
    RL=$(printf "'%s'," $RIDS); RL=${RL%,}
    if d1 "$q UPDATE missions SET removed_why = 'declined', closed_at = '$D1AGO', private_note = NULL, lat = NULL, lng = NULL WHERE id IN ($RL);" >/dev/null; then
      check "GET /api/partner of a crew with more than 20 closed missions: the old open and funded ones are there, plus 20 others" \
        "$(curl -s "$B/api/partner?k=$OT" | jget "(sorted(set(['$MX', '$XK', '$XF']) - set(m['id'] for m in d['missions'])), sum(m['status'] not in ('review', 'open', 'funded') for m in d['missions']))")" "([], 20)"
    else
      bad "write closed missions into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
    fi

    # A mission's photos are not loose files: 100 photos on a mission leave the 100-file quota free (LIMITS.unattached,
    # 100 since a cleanup at 4 spots takes up to 92 files with its 60 videos). The same 100 as loose files fill it. The
    # rows go straight into the local D1 (no files in R2); with crew OT's own uploads they stay under its 200 a day, so
    # the 429 is the loose files'.
    QK=$(python3 -c "import secrets;print(' '.join(secrets.token_hex(16) for _ in range(100)))")
    QL=$(printf "'%s'," $QK); QL=${QL%,}
    NOW0=$(ago 0)
    QV=$(printf "('%s', '$OPID', 'before', 'image/jpeg', 1000, '$NOW0', '$XK')," $QK); QV=${QV%,}
    if d1 "INSERT INTO uploads (key, partner_id, kind, content_type, size, created_at, mission_id) VALUES $QV;" >/dev/null; then
      QA=$(upk $OT before)
      [[ $QA =~ ^[0-9a-f]{32}$ ]] && ok "100 photos on a mission are not loose files: another upload -> 200" || bad "upload next to 100 mission photos" "$QA"
      d1 "UPDATE uploads SET mission_id = NULL WHERE key IN ($QL)" >/dev/null
      check "the same 100 as loose files fill the quota: another upload -> 429" \
        "$(code -X POST "$B/api/upload?k=$OT&kind=before" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)" 429
      d1 "DELETE FROM uploads WHERE key IN ($QL)" >/dev/null
    else
      bad "write mission photos into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
    fi

    # A crew's day (LIMITS.uploadsPerDay and LIMITS.bytesPerDay: 200 files and 8 GB in 24 hours since 2026-11-19, so a
    # cleanup with 60 videos of 95 MB fits): rows on mission XK (not loose) fill crew OT's day to one file short of 200,
    # then, once they are gone, one row fills its bytes to one photo short of 8 GB. The last file that fits -> 200, the
    # next -> 429 limit. Each time the rows go again; the two photos that got in stay loose files.
    DAY0=$(ago 1)
    read -r UNN UNB <<< "$(d1 "SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS b FROM uploads WHERE partner_id = '$OPID' AND created_at > '$DAY0'" | jget "'%d %d' % (d[0]['results'][0]['n'], d[0]['results'][0]['b'])")"
    PSZ=$(size $F/before.jpg)
    upday() { curl -s -o "$T/day.json" -w '%{http_code}' -X POST "$B/api/upload?k=$OT&kind=before" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg; }
    if [[ ${UNN:-x} =~ ^[0-9]+$ && $UNN -lt 150 ]]; then
      DK=$(python3 -c "import secrets,sys;print(' '.join(secrets.token_hex(16) for _ in range(int(sys.argv[1]))))" $((199 - UNN)))
      DL=$(printf "'%s'," $DK); DL=${DL%,}
      DV=$(printf "('%s', '$OPID', 'before', 'image/jpeg', 1, '$NOW0', '$XK')," $DK); DV=${DV%,}
      if d1 "INSERT INTO uploads (key, partner_id, kind, content_type, size, created_at, mission_id) VALUES $DV;" >/dev/null; then
        st="$(upday) $(upday) $(jget "d.get('code')" < "$T/day.json")"
        d1 "DELETE FROM uploads WHERE key IN ($DL)" >/dev/null
        check "a crew's 200th upload of the day -> 200, the 201st -> 429 limit" "$st" "200 429 limit"
      else
        bad "write a day of uploads into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
      fi
      DBK=$(python3 -c "import secrets;print(secrets.token_hex(16))")
      if d1 "INSERT INTO uploads (key, partner_id, kind, content_type, size, created_at, mission_id) VALUES ('$DBK', '$OPID', 'video', 'video/mp4', $((8 * 1024 * 1024 * 1024 - UNB - 2 * PSZ)), '$NOW0', '$XK');" >/dev/null; then
        st="$(upday) $(upday) $(jget "d.get('code')" < "$T/day.json")"
        d1 "DELETE FROM uploads WHERE key = '$DBK'" >/dev/null
        check "the upload that brings a crew's day to 8 GB exactly -> 200, one more -> 429 limit" "$st" "200 429 limit"
      else
        bad "write a day of bytes into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
      fi
    else
      bad "crew OT's uploads today" "$UNN $UNB"
    fi
  else
    bad "write old missions into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# Crew 3: a cleanup sent without a mission (the crew left the picker on No mission) is linked to the
# crew's funded mission on APPROVE (mission_id). Only a funded mission of the same crew, and only
# while the cleanup has no mission yet. Then DEACTIVATE removes the crew's other, funded mission.
LSLUG="mission-link-$MRUN"
LPJ=$(newp "Link Mission Crew $MRUN" ID "$LSLUG"); LT=$(echo "$LPJ" | jget "d['token']"); LPID=$(echo "$LPJ" | jget "d['id']")
LN1=$(upk $LT before); LN2=$(upk $LT before); LB=$(upk $LT before); LA=$(upk $LT after)
st=$(mpost $LT "place_name=Linked later $MRUN" "media=$LN1"); MA=$(mj "d['id']"); NOA=$(mj "d['no']")
st="$st $(mpost $LT "place_name=Funded, then deactivated $MRUN" "media=$LN2")"; MB=$(mj "d['id']"); NOB=$(mj "d['no']")
check "crew 3 posts two missions -> 201 201" "$st" "201 201"
check "fund mission A with EUR 30, publish mission B -> 200 200" "$(act "$MA" fund '"funded_eur":30') $(act "$MB" publish)" "200 200"
st=$(msub $LT - "$LB,$LA"); SP=$(mj "d['id']")
[[ $st = 200 && $SP =~ ^[a-z2-7]{10}$ ]] && ok "crew 3 sends a cleanup without a mission -> 200 ($SP)" || bad "cleanup without a mission" "$st $(cat "$T/m.json")"
check "admin pending list: it has no mission" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[s.get('mission_id') for s in d['submissions'] if s['id']=='$SP']")" "[None]"
check "admin pending list: its Link to mission choices carry each mission's point, rounded to 3 decimals" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[(m.get('no'), m.get('lat'), m.get('lng')) for s in d['submissions'] if s['id']=='$SP' for m in s.get('partner_missions', [])]")" "[($NOA, -8.659, 115.13)]"
# lapp <mission id>: APPROVE crew 3's cleanup linked to that mission. Status out, body in $T/m.json.
lapp()  { sdst "{\"id\":\"$SP\",\"action\":\"approve\",\"paid_eur\":30,\"crew_eur\":18,\"ops_eur\":12,\"mission_id\":\"$1\"}"; }
check "approve it linked to another crew's funded mission, its own open mission, an unknown or a malformed id -> 400 each" \
  "$(lapp "$MX") $(lapp "$MB") $(lapp aaaaaaaaaa) $(lapp ../x)" "400 400 400 400"
check "after the refused links the cleanup is still pending and mission A still funded" \
  "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[s['status'] for s in d['submissions'] if s['id']=='$SP']") $(mlist funded | mq "$MA" "m['status']")" "['pending'] funded"
check "approve it linked to its own funded mission A -> 200 approved" "$(lapp "$MA") $(mj "d.get('status')")" "200 approved"
check "mission A is done, closed by that cleanup" "$(mlist done | mq "$MA" "(m['status'], m['submission_id'], m['closed_at'] is not None)")" "('done', '$SP', True)"
check "the approved cleanup now carries mission A" \
  "$(curl -s "$B/api/admin/submissions?status=approved" -H "$A" | jget "[s.get('mission_id') for s in d['submissions'] if s['id']=='$SP']")" "['$MA']"
check "/api/events: the linked receipt has the mission block" \
  "$(curl -s $B/api/events | jget "[(e['mission']['no'], e['mission']['funded_eur'], e['mission']['now']==['/media/$LN1']) for e in d if e['id']=='$SP']")" "[($NOA, 30, True)]"
curl -s $B/m/$NOA | grep -q "location.replace(\"/#ev-$SP\")" && ok "/m/<no> of the linked mission opens its receipt" || bad "/m linked redirect" "$(curl -s $B/m/$NOA | grep -E 'refresh|replace')"
check "fund mission B with EUR 40 and a 25% advance -> 200, advance 10" "$(act "$MB" fund '"funded_eur":40,"advance_pct":25') $(mj "round(float(d['advance_eur']), 2)")" "200 10.0"
check "approve the linked cleanup again with funded mission B -> 400 (it has a mission)" "$(lapp "$MB")" 400
check "it stays linked to mission A, mission B stays funded" "$(mlist done | mq "$MA" "m['submission_id']") $(mlist funded | mq "$MB" "m['status']")" "$SP funded"

# DEACTIVATE with a funded mission: removed (deactivated) with its photos, the money stays on record
# and the review note says the advance stays with the crew. The done mission stays.
SB=$(mlist funded | mq "$MB" "m['now'][0]['url']")
check "funded mission B is on /api/missions, its photo public" "$(curl -s $B/api/missions | pubm "$NOB" "m['status']") $(code $B/media/$LN2)" "funded 200"
EB=$(mlist | jget "d['month_eur'] or 0")
st=$(curl -s -o "$T/m.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$LPID\"}")
check "deactivate crew 3 -> 200, 1 mission removed, the funded one with its EUR 10 advance" \
  "$st $(mj "(d.get('missions_removed'), [(f['no'], round(float(f['advance_eur']), 2)) for f in d.get('funded_removed', [])])")" "200 (1, [($NOB, 10.0)])"
check "funded this month after DEACTIVATE: EUR 30 less, only the EUR 10 advance of mission B still counts" \
  "$(mlist | jget "round(float(${EB:-0}) - float(d['month_eur'] or 0), 2)")" 30.0
ML=$(mlist removed)
check "DEACTIVATE removed funded mission B, the money stays on record" \
  "$(echo "$ML" | mq "$MB" "(m['status'], m['removed_why'], m['funded_eur'], round(float(m['advance_eur']), 2), m['closed_at'] is not None)")" "('removed', 'deactivated', 40, 10.0, True)"
check "its review note says the advance (EUR 10) stays with the crew" \
  "$(echo "$ML" | mq "$MB" "bool(__import__('re').search(r'Partner deactivated[^;\n]*; advance EUR 10(\.00)? stays with the crew', m['review_note'] or ''))")" True
check "deactivated (funded): private note and exact point wiped, place and task kept" "$(echo "$ML" | wiped "$MB" "Funded, then deactivated $MRUN")" "('deactivated', None, None, None, True, True)"
check "its photo is deleted, it is gone from /api/missions, /m/<no> -> the 404 page" \
  "$(gone $B/media/$LN2) $(gone "$B${SB:-/media/none}") $(curl -s $B/api/missions | pubm "$NOB" "m") $(m404 $NOB)" "404 404 None 404 friendly"
check "mission A stays done after DEACTIVATE, its receipt stays" \
  "$(mlist done | mq "$MA" "m['status']") $(curl -s $B/api/events | jget "sum(e['id']=='$SP' for e in d)")" "done 1"

# CANCEL of crew 2's funded mission: removed (cancelled) with its photos. The advance stays with the
# crew, so "funded this month" keeps only the advance (EUR 25 of the EUR 50).
L=$(mlist funded)
SXK=$(echo "$L" | mq "$MX" "m['now'][0]['url']")
check "now photo of the funded mission is public" "$(code $B/media/$K2A)" 200
EB=$(mlist | jget "d['month_eur'] or 0")
check "cancel the funded mission -> 200" "$(act "$MX" cancel)" 200
check "cancelled: removed (cancelled), photo deleted" \
  "$(mlist removed | mq "$MX" "(m['status'], m['removed_why'])") $(gone $B/media/$K2A) $(gone "$B${SXK:-/media/none}")" "('removed', 'cancelled') 404 404"
check "funded this month after the cancel: EUR 25 less, only the EUR 25 advance still counts" \
  "$(mlist | jget "round(float(${EB:-0}) - float(d['month_eur'] or 0), 2)")" 25.0
ML=$(mlist removed)
check "cancelled: the money stays on record" "$(echo "$ML" | mq "$MX" "(m['funded_eur'], round(float(m['advance_eur']), 2))")" "(50, 25.0)"
check "cancelled: private note and exact point wiped, place and task kept" "$(echo "$ML" | wiped "$MX" "Other crew $MRUN")" "('cancelled', None, None, None, True, True)"
check "cancel it again -> 409" "$(act "$MX" cancel)" 409

# DEACTIVATE crew 2. With STATE it still has an old open and an old funded mission: both removed.
check "deactivate crew 2 -> 200" "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$OPID\"}")" 200
if [ -n "$STATE" ]; then
  ML=$(mlist removed)
  check "DEACTIVATE removed crew 2's open and funded missions, private note and exact point wiped" \
    "$(echo "$ML" | wiped "$XK" "Old mission $MRUN") $(echo "$ML" | wiped "$XF" "Old mission $MRUN")" \
    "('deactivated', None, None, None, True, True) ('deactivated', None, None, None, True, True)"
  check "the funded one keeps its money, its note says the advance (EUR 3) stays with the crew" \
    "$(echo "$ML" | mq "$XF" "(m['funded_eur'], round(float(m['advance_eur']), 2), bool(__import__('re').search(r'Partner deactivated[^;\n]*; advance EUR 3(\.00)? stays with the crew', m['review_note'] or '')))")" "(10, 3.0, True)"
fi
n=0
for s in review open funded; do
  c=$(mlist $s | jget "sum(m['partner_slug'] in ('$MSLUG', '$OSLUG', '$LSLUG') for m in d['missions'])"); n=$((n + ${c:-99}))
done
check "no test missions left in review, open or funded" "$n" 0
# A crew from Senegal prices its mission in CFA francs (the upload page starts it on XOF, checked in node
# further down): stored and listed for the admin as sent, then withdrawn, so nothing waits after this.
WPJ=$(newp "Yoff Plage Crew $MRUN" SN "yoff-$MRUN"); WT=$(echo "$WPJ" | jget "d['token']"); WN=$(upk $WT before)
st=$(mpost $WT "place_name=Plage de Yoff $MRUN" country=SN lat:=14.758 lng:=-17.472 currency=XOF price_local:=25000 crew_local:=15000 "media=$WN"); WM=$(mj "d['id']")
check "a Senegal crew posts a mission in XOF -> 201, the admin list has XOF 25000, 15000 to the crew" \
  "$st $(mlist review | mq "$WM" "(m['currency'], m['price_local'], m['crew_local'], m['country'])")" "201 ('XOF', 25000, 15000, 'SN')"
check "and withdraws it -> 200, removed" "$(wd $WT "$WM") $(mlist removed | mq "$WM" "m['removed_why']")" "200 withdrawn"

# Crew 4 posts a mission with a short video of the spot: 1 to 4 photos and at most 1 video. The video goes
# wherever the photos go (/admin/, /api/missions, /m/<no>, PENDING, the receipt) and is deleted with them.
# Every mission of this crew is closed or removed at the end, so nothing waits after this part.
VPJ=$(newp "Video Crew $MRUN" ID "video-$MRUN"); VT=$(echo "$VPJ" | jget "d['token']"); VPID=$(echo "$VPJ" | jget "d['id']")
VN=$(upk $VT before); VV1=$(upv $VT); VV2=$(upv $VT)
st="$(mpost $VT "media=$VN,$VV1,$VV2") $(mj "d.get('code')")"
st="$st $(mpost $VT "media=$VV1") $(mj "d.get('code')")"
check "a mission with a photo and 2 videos, or with only a video -> 400 media each" "$st" "400 media 400 media"
MVARGS=("client_ref=$(openssl rand -hex 16)" "place_name=Video spot $MRUN")
st=$(mpost $VT "${MVARGS[@]}" "media=$VN,$VV1"); MV=$(mj "d['id']"); NOV=$(mj "d['no']")
[[ $st = 201 && $MV =~ ^[a-z2-7]{10}$ && $NOV =~ ^[1-9][0-9]*$ ]] && ok "a mission with a photo and a video -> 201 (#$NOV)" || bad "mission with a video" "$st $(cat "$T/m.json")"
# (now photo keys, video key) of the mission, from an admin list on stdin
VNOW="(sorted(p['key'] for p in m['now']), (m['now_video'] or {}).get('key'))"
check "admin: the photo in now, the video in now_video" "$(mlist review | mq "$MV" "$VNOW")" "(['$VN'], '$VV1')"
VS1=$(mlist review | mq "$MV" "m['now_video']['url']")
check "admin: the video's signed link -> 200 video/mp4, while /media/<video> of a mission in review -> 404" \
  "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B${VS1:-/media/none}") $(code $B/media/$VV1)" "200 video/mp4 404"
# Sent again within the 2 hours: the new set must still be 1 to 4 photos and at most 1 video, and a refused
# one changes nothing.
st="$(mpost $VT "${MVARGS[@]}" "media=$VN,$VV1,$VV2") $(mj "d.get('code')") $(mlist review | mq "$MV" "$VNOW")"
check "sent again with 2 videos -> 400 media, the mission keeps its photo and video" "$st" "400 media (['$VN'], '$VV1')"
st="$(mpost $VT "${MVARGS[@]}" "media=$VV1") $(mj "d.get('code')") $(mlist review | mq "$MV" "$VNOW")"
check "sent again with only the video -> 400 media, the mission keeps its photo and video" "$st" "400 media (['$VN'], '$VV1')"
RVV=$(mlist review | mq "$MV" "m['revision']")
st=$(mpost $VT "${MVARGS[@]}" "media=$VN")
check "sent again without the video -> 200 updated, no video" "$st $(mj "d.get('updated')") $(mlist review | mq "$MV" "m['now_video']")" "200 True None"
VV3=$(upv $VT)
st=$(mpost $VT "${MVARGS[@]}" "media=$VN,$VV3")
check "sent again with another video -> 200 updated, with that video" "$st $(mj "d.get('updated')") $(mlist review | mq "$MV" "$VNOW")" "200 True (['$VN'], '$VV3')"
# Only the video changed since RVV was read, so PUBLISH with it refuses: a video is never published unseen.
check "publish with the revision from before the video changed -> 409 changed" "$(act "$MV" publish "\"revision\":\"$RVV\"") $(mj "d.get('code')")" "409 changed"
# An /admin/ tab opened before missions had videos gets the same revision but never plays the video, and
# sends no video key: it must reload first.
RVN=$(mlist review | mq "$MV" "m['revision']")
check "publish with the revision the list shows now but without its video (an older /admin/ tab) -> 409 changed, still in review" \
  "$(act "$MV" publish "\"revision\":\"$RVN\"") $(mj "d.get('code')") $(mj "'Reload the page' in d.get('error', '')") $(mlist review | mq "$MV" "m['status']")" "409 changed True review"
check "publish with the revision and another video key -> 409 changed" "$(act "$MV" publish "\"revision\":\"$RVN\",\"video\":\"$VV1\"") $(mj "d.get('code')")" "409 changed"
check "publish with the revision and the video the list shows now -> 200" "$(act "$MV" publish "\"revision\":\"$RVN\",\"video\":\"$VV3\"")" 200
check "/api/missions: the photo in now, the video in now_video" "$(curl -s $B/api/missions | pubm "$NOV" "(m['now'], m['now_video'])")" "(['/media/$VN'], '/media/$VV3')"
H=$(curl -s -D - -o /dev/null $B/media/$VV3)
echo "$H" | head -1 | grep -q 200 && echo "$H" | grep -qi 'content-type: video/mp4' && echo "$H" | grep -qi 'cache-control: public, max-age=3600' \
  && ok "the video of an open mission is public (video/mp4, cached 1 hour)" || bad "open mission video" "$H"
check "a range of that video -> 206" "$(code -H 'Range: bytes=0-9' $B/media/$VV3)" 206
MGV=$(curl -s $B/m/$NOV)
echo "$MGV" | grep -qF "property=\"og:image\" content=\"$B/media/$VN\"" && echo "$MGV" | grep -qF "property=\"og:video\" content=\"$B/media/$VV3\"" \
  && echo "$MGV" | grep -qF 'property="og:video:type" content="video/mp4"' \
  && ok "/m/<no> of a mission with an MP4 video: the photo is the picture, the video its og:video" || bad "/m og:video" "$(echo "$MGV" | grep -E 'og:(image|video)')"
check "fund it -> 200" "$(act "$MV" fund '"funded_eur":20')" 200
VCB=$(upk $VT before); VCA=$(upk $VT after); VCVA=$(upv $VT after); VCVB=$(upv $VT before)
st=$(msub $VT "$MV" "$VCB,$VCA,$VCVA,$VCVB"); SVV=$(mj "d.get('id')")
check "its cleanup with a video after and a video before -> 200" "$st" 200
PV=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A")
VMS=$(echo "$PV" | jget "[s['mission']['now_video']['url'] for s in d['submissions'] if s['id']=='$SVV'][0]")
check "PENDING: the mission's video (signed link -> 200), and the cleanup's two videos labelled, the one before first" \
  "$(code "$B${VMS:-/media/none}") $(echo "$PV" | jget "[[v['stage'] for v in s['media']['videos']] for s in d['submissions'] if s['id']=='$SVV']")" "200 [['before', 'after']]"
check "approve the cleanup" "$(sdec "{\"id\":\"$SVV\",\"action\":\"approve\",\"paid_eur\":20}")" approved
check "/api/events: the mission block has the photo and the video, the receipt its two videos labelled" \
  "$(curl -s $B/api/events | jget "[(e['mission']['now'], e['mission']['now_video'], e['media']['video_stages']) for e in d if e['id']=='$SVV']")" \
  "[(['/media/$VN'], '/media/$VV3', ['before', 'after'])]"
# APPROVED's download row: downloads() from admin.js, run in node on the real list, then each link asked for its file
# name. The row follows the card: the mission's photo of the spot before the cleanup's photos, its video before the
# cleanup's videos, each saved as sapu-earth-<receipt id>-<label>.<ext>. dlnode '<code>' [args]: runs code with
# downloads() loaded.
curl -s $B/admin/admin.js > "$T/admin.js"
cat > "$T/dlpre.js" <<'JS'
const src = require("fs").readFileSync(process.env.ADMIN_JS, "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = src.indexOf("  function downloads("), b = src.indexOf("\n  }\n", a);
if (a < 0 || b < 0) throw new Error("missing downloads()");
const c = src.indexOf("  function videoRows("), e = src.indexOf("\n  }\n", c);
if (c < 0 || e < 0) throw new Error("missing videoRows()");
eval([line(/^  const safeMedia = .*$/m), line(/^  const DL_NAME_RE = .*$/m), src.slice(c, e + 4), src.slice(a, b + 4), "globalThis.downloads = downloads; globalThis.videoRows = videoRows;"].join("\n"));
JS
dlnode() { ADMIN_JS="$T/admin.js" node -r "$T/dlpre.js" -e "$1" "${@:2}" 2>&1; }
ROWS=$(curl -s "$B/api/admin/submissions?status=approved" -H "$A" | dlnode '
const d = JSON.parse(require("fs").readFileSync(0, "utf8")), s = d.submissions.find((x) => x.id === process.argv[1]);
for (const r of downloads(s, s.mission)) console.log(r.label + " " + r.href);' "$SVV")
got=$(echo "$ROWS" | while read -r l h; do printf '%s=%s ' "$l" "$(dlname "$B$h" | sed -n 's/^attachment; filename="\(.*\)"$/\1/p')"; done)
check "APPROVED: the download row follows the card (the spot's photo, the cleanup's photos, the spot's video, the cleanup's videos), each saved as sapu-earth-<receipt id>-<label>" \
  "$got" "now-1=sapu-earth-$SVV-now-1.jpg before-1=sapu-earth-$SVV-before-1.jpg after-1=sapu-earth-$SVV-after-1.jpg video-now=sapu-earth-$SVV-video-now.mp4 video-before=sapu-earth-$SVV-video-before.mp4 video-after=sapu-earth-$SVV-video-after.mp4 "
DLU=$(dlnode '
const sig = (c) => `/media/${c.repeat(32)}?exp=1999999999&sig=${"0".repeat(64)}`;
const short = (r) => r.label + "=" + r.href.replace(/^\/media\/(.)\1{31}\?exp=1999999999&sig=0{64}&dl=/, "$1:");
const s = { id: "abcdefgh23", media: { before: [{ url: sig("1") }, { url: "https://example.org/x.jpg" }], after: [{ url: sig("2") }], videos: [{ url: sig("3"), stage: null }, { url: sig("4") }] } };
console.log(downloads(s, null).map(short).join(" ") + " | " + downloads({ ...s, id: "Odd Id" }, { now: [{ url: sig("5") }], now_video: null }).map(short).join(" "));')
check "the download row: no mission no spot files, videos without a stage video-<n>, a link that is not signed left out, an id that does not fit dl=1" "$DLU" \
  "before-1=1:abcdefgh23-before-1 after-1=2:abcdefgh23-after-1 video-1=3:abcdefgh23-video-1 video-2=4:abcdefgh23-video-2 | now-1=5:1 before-1=1:1 after-1=2:1 video-1=3:1 video-2=4:1"
# Several videos of a stage (up to 30 of each since 2026-11-19) each get a name of their own, numbered in the card's
# order, and the same titles as the card (videoRows): one of a stage keeps its plain name and title, and the ones
# without a stage count among themselves.
DLN=$(dlnode '
const sig = (c) => `/media/${c.repeat(32)}?exp=1999999999&sig=${"0".repeat(64)}`;
const v = (c, stage) => ({ url: sig(c), stage });
const s = { id: "abcdefgh23", media: { before: [], after: [], videos: [v("1", "before"), v("2", "before"), v("3", "before"), v("4", "after"), v("5", null), v("6")] } };
const names = downloads(s, { now: [], now_video: { url: sig("7") } }).map((r) => r.label).join(" ");
const titles = videoRows(s.media.videos).map((r) => r.title).join(" | ");
const thirty = videoRows(Array.from({ length: 30 }, () => v("8", "after"))).map((r) => r.title + "=" + r.dl);
console.log(names + " || " + titles + " || " + thirty[0] + " " + thirty[29] + " " + new Set(thirty).size);')
check "the download row and the card's titles with several videos of a stage: numbered within each stage, one alone plain, 30 of a stage all different (admin.js videoRows, node)" "$DLN" \
  "video-now video-before-1 video-before-2 video-before-3 video-after video-1 video-2 || VIDEO BEFORE 1/3 | VIDEO BEFORE 2/3 | VIDEO BEFORE 3/3 | VIDEO AFTER | VIDEO 1/2 | VIDEO 2/2 || VIDEO AFTER 1/30=video-after-1 VIDEO AFTER 30/30=video-after-30 30"
grep -qF '<div class="dl-list">${downloads(s, mis).map((d) => `<a href="${esc(d.href)}" download>⬇ ${esc(d.label)}</a>`).join("")}</div>' "$T/admin.js" \
  && ok "the APPROVED card draws its download row from downloads()" || bad "admin.js download row" ""
curl -s $B/m/$NOV | grep -q 'og:video' && bad "/m of a done mission names a video" "" || ok "/m of a done mission has no og:video (its receipt's photo is the picture)"
check "unpublish the cleanup -> the mission goes too (unpublished)" \
  "$(sdec "{\"id\":\"$SVV\",\"action\":\"reject\",\"review_note\":\"e2e unpublish\"}") $(mlist removed | mq "$MV" "m['removed_why']")" "rejected unpublished"
check "the mission's video is deleted: /media/<key> and its signed link -> 404 404" "$(gone $B/media/$VV3) $(gone "$B${VMS:-/media/none}")" "404 404"
[ -n "$STATE" ] && check "the mission's video row is gone" "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE key = '$VV3'" | jget "d[0]['results'][0]['n']")" 0
# The most the page sends: 4 photos and a video. One more video is too many.
VP1=$(upk $VT before); VP2=$(upk $VT before); VP3=$(upk $VT before); VP4=$(upk $VT before); VB1=$(upv $VT); VB2=$(upv $VT)
check "a mission with 4 photos and 2 videos -> 400 media" "$(mpost $VT "media=$VP1,$VP2,$VP3,$VP4,$VB1,$VB2") $(mj "d.get('code')")" "400 media"
st=$(mpost $VT "media=$VP1,$VP2,$VP3,$VP4,$VB1"); MV4=$(mj "d['id']")
check "a mission with 4 photos and a video -> 201, with 4 photos and the video" \
  "$st $(mlist review | mq "$MV4" "(len(m['now']), (m['now_video'] or {}).get('key'))")" "201 (4, '$VB1')"
VB1S=$(mlist review | mq "$MV4" "m['now_video']['url']")
check "withdraw it -> 200, its video is deleted (signed link -> 404)" "$(wd $VT "$MV4") $(gone "$B${VB1S:-/media/none}")" "200 404"
VN5=$(upk $VT before); VV5=$(upv $VT)
st=$(mpost $VT "place_name=Declined with a video $MRUN" "media=$VN5,$VV5"); MV5=$(mj "d['id']")
VS5=$(mlist review | mq "$MV5" "m['now_video']['url']")
check "another mission with a video -> 201, its video opens for /admin/" "$st $(code "$B${VS5:-/media/none}")" "201 200"
check "decline it -> 200, its video is deleted (signed link -> 404)" "$(act "$MV5" decline) $(gone "$B${VS5:-/media/none}")" "200 404"
# Two resends of one mission at the same moment, each with another video (two tabs, or on purpose): the mission
# never keeps both, so /admin/ always plays every video it holds. When they really overlap, one answers 409
# code media (the page then sends its files again).
RREF="client_ref=$(openssl rand -hex 16)"; RP=$(upk $VT before); RV0=$(upv $VT); RVA=$(upv $VT); RVB=$(upv $VT)
st=$(mpost $VT "$RREF" "place_name=Two tabs $MRUN" "media=$RP,$RV0"); MR=$(mj "d['id']")
check "a mission with a photo and a video -> 201" "$st" 201
RBA=$(mbody "$RREF" "place_name=Two tabs $MRUN" "media=$RP,$RVA"); RBB=$(mbody "$RREF" "place_name=Two tabs $MRUN" "media=$RP,$RVB")
curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/mission?k=$VT" -H 'content-type: application/json' -d "$RBA" > "$T/race-a" & RPA=$!
curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/mission?k=$VT" -H 'content-type: application/json' -d "$RBB" > "$T/race-b" & RPB=$!
wait $RPA $RPB
RST="$(cat "$T/race-a") $(cat "$T/race-b")"
case "$RST" in "200 200"|"200 409"|"409 200") ok "two resends at once, each with another video -> $RST" ;; *) bad "two resends at once" "$RST" ;; esac
check "the mission has one of the two new videos" "$(mlist review | mq "$MR" "(m['now_video'] or {}).get('key') in ('$RVA', '$RVB')")" True
if [ -n "$STATE" ]; then
  check "and only one video row" "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE mission_id = '$MR' AND kind = 'video'" | jget "d[0]['results'][0]['n']")" 1
  # Should a second video get onto a mission all the same, PUBLISH and FUND refuse it: the card plays only one.
  RX=$(mlist review | mq "$MR" "'$RVB' if (m['now_video'] or {}).get('key') == '$RVA' else '$RVA'")
  d1 "UPDATE uploads SET mission_id = '$MR' WHERE key = '$RX'" >/dev/null
  RL=$(mlist review)
  check "a second video put on it by hand: PUBLISH with the revision and the video the list shows -> 409 changed" \
    "$(act "$MR" publish "\"revision\":\"$(echo "$RL" | mq "$MR" "m['revision']")\",\"video\":\"$(echo "$RL" | mq "$MR" "m['now_video']['key']")\"") $(mj "d.get('code')")" "409 changed"
fi
check "withdraw it -> 200, removed" "$(wd $VT "$MR") $(mlist removed | mq "$MR" "m['removed_why']")" "200 withdrawn"
check "deactivate crew 4 -> 200" "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$VPID\"}")" 200

# ---------- Crew logos (POST /api/logo, LOGOS TO CHECK, /media/, the public places) ----------
# A crew sends its logo from its crew page (POST /api/logo: the square JPEG the page made). It waits for Marcus, and
# APPROVE LOGO, DECLINE and REMOVE LOGO decide it (POST /api/admin/logos/decide). The live logo of an active crew is
# public on /media/, next to the crew's name on /p/<slug> and in the receipt and mission posts; anything else needs a
# signed link. An application can bring one, decided with APPROVE AND CREATE PARTNER. Crews of their own, and
# applications from their own made-up addresses, so no count of the parts above or below moves (docs/upload-flow.md,
# Crew logos).
LRUN=$RANDOM$RANDOM
# lpost <token> <file> [content type]: POST /api/logo. Prints the status, the body goes to $T/l.json.
lpost() { curl -s -o "$T/l.json" -w '%{http_code}' -X POST "$B/api/logo?k=$1" -H "content-type: ${3:-image/jpeg}" --data-binary @"$2"; }
lj()    { jget "$1" < "$T/l.json"; }
# lkey: the key of the waiting logo in that answer, from its signed link.
lkey()  { lj "(d['logo']['review'] or '').split('?')[0].split('/')[-1]"; }
# ldec <key> <action>: POST /api/admin/logos/decide. Prints the status, the body goes to $T/l.json.
ldec()  { curl -s -o "$T/l.json" -w '%{http_code}' -X POST $B/api/admin/logos/decide -H "$A" -H 'content-type: application/json' \
            -d "{\"key\":\"$1\",\"action\":\"$2\"}"; }
# plogo <token> <expr>: a Python expression over the logo state (l) of that crew's GET /api/partner.
plogo() { curl -s "$B/api/partner?k=$1" | python3 -c "import json,sys;l=json.load(sys.stdin).get('logo');print(eval(sys.argv[1]))" "$2" 2>/dev/null; }
# plist <expr>: a Python expression over GET /api/admin/partners (d), where p(slug) is the partner with that slug.
plist() { curl -s $B/api/admin/partners -H "$A" | python3 -c "
import json,sys
d=json.load(sys.stdin);p=lambda s:([x for x in d['partners'] if x['slug']==s] or [None])[0]
print(eval(sys.argv[1]))" "$1" 2>/dev/null; }
# signed <expr>: a Python test that <expr> is a signed /media/ link (/media/<key>?exp=..&sig=..).
signed() { echo "bool(__import__('re').fullmatch(r'/media/[0-9a-f]{32}\?exp=\d{10}&sig=[0-9a-f]{64}', str($1)))"; }

LSLUG="logo-crew-$LRUN"
LPJ=$(newp "Logo Crew $LRUN" ID "$LSLUG"); LT=$(echo "$LPJ" | jget "d['token']"); LPID=$(echo "$LPJ" | jget "d['id']")
check "GET /api/partner of a new crew: logos on, none live or waiting, not declined, its letters LC" \
  "$(plogo $LT "(l['enabled'], l['live'], l['review'], l['declined'], l['initials'])")" "(True, None, None, False, 'LC')"
st="$(lpost AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA $T/logo.jpg)"
st="$st $(curl -s -o /dev/null -D "$T/l.h" -w '%{http_code}' "$B/api/logo?k=$LT") $(tr -d '\r' < "$T/l.h" | sed -n 's/^[Aa]llow: *//p')"
st="$st $(lpost $LT $T/logo.jpg image/png) $(lj "d.get('code')")"
st="$st $(lpost $LT /dev/null) $(lj "d.get('code')")"
st="$st $(lpost $LT $T/logo-heavy.jpg) $(lj "d.get('code')")"
st="$st $(lpost $LT $T/fake.jpg) $(lj "d.get('code')")"
check "POST /api/logo refused: a link that is not valid, GET (Allow: POST), image/png, an empty body, over 150 KB, not a JPEG" \
  "$st" "404 405 POST 415 type 411 size 413 size 415 logo"
LBAD=""
for f in logo-webkit $LOGO_BAD; do s2="$(lpost $LT $T/$f.jpg) $(lj "d.get('code')")"; [ "$s2" = "415 logo" ] || LBAD="$LBAD [$f: $s2]"; done
[ -z "$LBAD" ] && ok "POST /api/logo refuses WebKit's blocks as they are, camera data, XMP, the Photoshop block, a second APP0, bytes after the image (zeros, an Exif block with a new end, a whole second JPEG), an APP1 after the scan (also progressive), a picture that is not square, too small or too big, and SOF3 (415 logo each)" \
  || bad "POST /api/logo refusals" "$LBAD"
check "after the refusals nothing waits" "$(plogo $LT "l['review']")" None

st=$(lpost $LT $T/logo.jpg); LK1=$(lkey); LS1=$(lj "d['logo']['review']")
check "POST /api/logo with a square JPEG -> 201: it waits (a signed link), nothing live, not declined" \
  "$st $(lj "$(signed "d['logo']['review']")") $(lj "(d['logo']['live'], d['logo']['declined'])")" "201 True (None, False)"
H=$(curl -s -D - -o $T/lg.jpg "$B$LS1" | tr -d '\r')
echo "$H" | head -1 | grep -q 200 && echo "$H" | grep -qi '^content-type: image/jpeg' && echo "$H" | grep -qi '^cache-control: private, no-store' && cmp -s $T/lg.jpg $T/logo.jpg \
  && ok "the waiting logo's signed link -> 200 image/jpeg, never cached, the exact bytes" || bad "waiting logo, signed link" "$H"
check "the waiting logo without a signature -> 404" "$(code $B/media/$LK1)" 404
st=$(lpost $LT $T/logo-icc.jpg); LK2=$(lkey)
check "a second logo (with a colour profile) -> 201 and waits instead of the first, whose file is deleted (signed link -> 404)" \
  "$st $([ -n "$LK2" ] && [ "$LK2" != "$LK1" ] && echo new) $(gone "$B$(hsig $LK1)")" "201 new 404"
[ -n "$STATE" ] && check "the crew has one waiting logo, the first one is gone" \
  "$(d1 "SELECT key, status FROM logos WHERE partner_id = '$LPID'" | jget "sorted((r['key'] == '$LK2', r['status']) for r in d[0]['results'])")" "[(False, 'gone'), (True, 'review')]"
check "GET /api/admin/partners: logos wait (counts.logos), this crew's logo_review is the new one with a signed link, nothing live" \
  "$(plist "(d['counts']['logos'] >= 1, p('$LSLUG')['logo_review']['key'], $(signed "p('$LSLUG')['logo_review']['url']"), p('$LSLUG')['logo'])")" \
  "(True, '$LK2', True, None)"
curl -s $B/api/admin/partners -H "$A" | grep -q token_hash && bad "the partner list with logos leaks token_hash" "" || ok "the partner list with logos has no token_hash"
LC0=$(plist "d['counts']['logos']")
check "decide: without a token 401, an unknown action 400, an unknown key 404" \
  "$(code -X POST $B/api/admin/logos/decide -H 'content-type: application/json' -d "{\"key\":\"$LK2\",\"action\":\"approve\"}") $(ldec $LK2 boost) $(ldec 00000000000000000000000000000000 approve)" "401 400 404"
check "APPROVE LOGO -> 200, live, nothing replaced" "$(ldec $LK2 approve) $(lj "(d['status'], d['replaced'])")" "200 ('live', None)"
H=$(curl -s -D - -o $T/lg.jpg $B/media/$LK2 | tr -d '\r')
echo "$H" | head -1 | grep -q 200 && echo "$H" | grep -qi '^content-type: image/jpeg' && echo "$H" | grep -qi '^cache-control: public, max-age=3600$' \
  && echo "$H" | grep -qi '^x-content-type-options: nosniff' && echo "$H" | grep -qi "^content-security-policy: default-src 'none'; sandbox" && cmp -s $T/lg.jpg $T/logo-icc.jpg \
  && ok "a live logo is public: 200 image/jpeg, cached an hour (not immutable), nosniff, sandboxed, the exact bytes" || bad "live logo on /media/" "$H"
check "GET /api/partner: live /media/<key>, nothing waits, not declined" "$(plogo $LT "(l['live'], l['review'], l['declined'])")" "('/media/$LK2', None, False)"
check "counts.logos is one less" "$(plist "d['counts']['logos']")" "$(add "$LC0" -1)"
check "APPROVE LOGO again -> 409 state" "$(ldec $LK2 approve) $(lj "d.get('code')")" "409 state"
st=$(msub $LT - "$(upk $LT before),$(upk $LT after),$LK2"); check "a cleanup that names a logo's key with its photos -> 400 media (a logo is no upload)" "$st $(mj "d.get('code')")" "400 media"
st=$(lpost $LT $T/logo.jpg); LK3=$(lkey)
check "a new logo, then DECLINE -> 200 declined, its file deleted (signed link -> 404)" "$st $(ldec $LK3 decline) $(lj "d['status']") $(gone "$B$(hsig $LK3)")" "201 200 declined 404"
check "GET /api/partner: the live logo stays, nothing waits, declined (the crew page: sapu.earth keeps showing this one)" \
  "$(plogo $LT "(l['live'], l['review'], l['declined'])")" "('/media/$LK2', None, True)"
check "DECLINE again -> 409 state" "$(ldec $LK3 decline) $(lj "d.get('code')")" "409 state"
st=$(lpost $LT $T/logo.jpg); LK4=$(lkey)
check "a newer logo approved replaces the live one: the old /media/ link -> 404, the new one -> 200" \
  "$st $(ldec $LK4 approve) $(lj "d['replaced']") $(gone $B/media/$LK2) $(code $B/media/$LK4)" "201 200 $LK2 404 200"
check "GET /api/partner: the newer one is live, not declined" "$(plogo $LT "(l['live'], l['declined'])")" "('/media/$LK4', False)"
PG=$(curl -s $B/p/$LSLUG)
echo "$PG" | grep -qF "<div class=\"ph-hero\"><img class=\"ph-logo\" src=\"/media/$LK4\" alt=\"\" width=\"96\" height=\"96\"><h1 class=\"fp-title\">" \
  && echo "$PG" | grep -qF "<meta property=\"og:image\" content=\"$B/media/$LK4\">" && echo "$PG" | grep -qF '<meta name="twitter:card" content="summary">' \
  && ok "/p/<slug>: the live logo next to the name, and without a receipt the logo is its link preview (twitter:card summary)" || bad "/p/<slug> with a logo" "$(echo "$PG" | grep -E 'ph-|og:image|twitter')"
check "REMOVE LOGO -> 200 declined" "$(ldec $LK4 remove) $(lj "d['status']")" "200 declined"
check "the removed logo: /media/ -> 404, GET /api/partner: nothing live, declined" "$(gone $B/media/$LK4) $(plogo $LT "(l['live'], l['declined'])")" "404 (None, True)"
PG=$(curl -s $B/p/$LSLUG)
if echo "$PG" | grep -qE 'ph-logo|og:image" content="[^"]*/media/'; then bad "/p/<slug> after REMOVE LOGO still names a logo" "$(echo "$PG" | grep -E 'ph-logo|og:image')"
elif [ "$(echo "$PG" | grep -c 'og:image"')" != 1 ] || ! echo "$PG" | grep -qF "<meta property=\"og:image\" content=\"$B/site/social/sapu-earth-mark.png\">"; then
  bad "/p/<slug> after REMOVE LOGO: the preview picture is not the broom" "$(echo "$PG" | grep -E 'og:image|twitter')"
else ok "/p/<slug> after REMOVE LOGO: the name alone, and the broom as its preview picture"; fi
check "REMOVE LOGO again -> 409 state" "$(ldec $LK4 remove) $(lj "d.get('code')")" "409 state"

# The daily limit: 10 logos per crew in 24 hours, every status counted.
DPJ=$(newp "Daily Logos $LRUN" ID "daily-logos-$LRUN"); DT=$(echo "$DPJ" | jget "d['token']"); DPID=$(echo "$DPJ" | jget "d['id']")
RL=""; for i in 1 2 3 4 5 6 7 8 9 10; do RL="$RL$(lpost $DT $T/logo.jpg) "; done
check "10 logos in a day -> 201 each, the 11th -> 429 limit" "$RL$(lpost $DT $T/logo.jpg) $(lj "d.get('code')")" "201 201 201 201 201 201 201 201 201 201 429 limit"
[ -n "$STATE" ] && check "that crew has 10 logo rows: 9 replaced, 1 waiting" \
  "$(d1 "SELECT status, COUNT(*) AS n FROM logos WHERE partner_id = '$DPID' GROUP BY status ORDER BY status" | jget "[(r['status'], r['n']) for r in d[0]['results']]")" "[('gone', 9), ('review', 1)]"

# Logo Receipt Crew: an approved cleanup, a published mission and a live logo. The receipt names the crew's page and
# logo, the mission its logo. DEACTIVATE deletes the live and the waiting logo; the receipt stays, with the name alone.
RSLUG="logo-receipt-$LRUN"
RPJ=$(newp "Logo Receipt Crew $LRUN" ID "$RSLUG"); RT=$(echo "$RPJ" | jget "d['token']"); RPID=$(echo "$RPJ" | jget "d['id']")
RB=$(upk $RT before); RA=$(upk $RT after); RN=$(upk $RT before)
st=$(msub $RT - "$RB,$RA"); RS=$(mj "d.get('id')")
st="$st $(sdec "{\"id\":\"${RS:-none}\",\"action\":\"approve\",\"paid_eur\":30}")"
st="$st $(mpost $RT "place_name=Logo mission $LRUN" "media=$RN")"; RM=$(mj "d.get('id')"); RNO=$(mj "d.get('no')")
st="$st $(act "${RM:-none}" publish)"
st="$st $(lpost $RT $T/logo.jpg)"; RK=$(lkey)
st="$st $(ldec "$RK" approve)"
check "Logo Receipt Crew: a cleanup approved with what was paid, a mission published, a logo approved" "$st" "200 approved 201 200 201 200"
check "/api/events: its receipt names the crew's page and its live logo" \
  "$(curl -s $B/api/events | jget "[(e['provider']['page'], e['provider']['logo']) for e in d if e['id']=='$RS']")" "[('https://sapu.earth/p/$RSLUG', '/media/$RK')]"
check "/api/missions: its mission's crew has the same logo" "$(curl -s $B/api/missions | pubm "$RNO" "m['partner']['logo']")" "/media/$RK"
st=$(lpost $RT $T/logo-icc.jpg); RK2=$(lkey)
st="$st $(curl -s -o "$T/l.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$RPID\"}") $(lj "d.get('logos_removed')")"
check "it sends another logo (waiting), then DEACTIVATE -> 200, logos_removed 2" "$st" "201 200 2"
check "both files are deleted: the live one, public and signed, and the waiting one -> 404 404 404" \
  "$(gone $B/media/$RK) $(gone "$B$(hsig $RK)") $(gone "$B$(hsig $RK2)")" "404 404 404"
check "the receipt stays in /api/events, without the crew's page and logo" \
  "$(curl -s $B/api/events | jget "[(e['provider']['page'], e['provider']['logo']) for e in d if e['id']=='$RS']")" "[(None, None)]"

# Applications with a logo, each from its own made-up address. Every one is approved or deleted, so nothing waits after this.
lip()   { echo "2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::4"; }
lmine() { alist | jget "sum(a['org_name'].endswith(' $LRUN') for a in d['applications'])"; }
# lab <id> <name> <slug> [extra JSON member]: the body of an approve.
lab()   { printf '{"id":"%s","name":"%s","country":"ID","slug":"%s"%s}' "$1" "$2" "$3" "${4:+,$4}"; }
st=$(apply "ip=$(lip)" "org_name=Logo Apply $LRUN" "logo=$T/logo.jpg"); LA1=$(rj "d['id']")
L=$(alist); LA1K=$(echo "$L" | appq "$LA1" "a['logo']['key']"); LA1U=$(echo "$L" | appq "$LA1" "a['logo']['url']")
check "an application with a logo -> 201, its card has the logo (its key and a signed link)" \
  "$st $([[ $LA1K =~ ^[0-9a-f]{32}$ ]] && echo key) $(echo "$L" | appq "$LA1" "$(signed "a['logo']['url']")")" "201 key True"
curl -s -o $T/al.jpg "$B${LA1U:-/media/none}"; cmp -s $T/al.jpg $T/logo.jpg && ok "the application's logo: its signed link gives the exact bytes" || bad "application logo bytes" "$LA1U"
check "the application's logo without a signature -> 404" "$(code $B/media/$LA1K)" 404
M0=$(lmine); [ -n "$STATE" ] && LR0=$(r2mt)
st="$(apply "ip=$(lip)" "org_name=Logo Refused $LRUN" "logo=$T/logo-exif.jpg") $(rj "(d.get('field'), d.get('code'))")"
st="$st $(apply "ip=$(lip)" "org_name=Logo Two $LRUN" "logo=$T/logo.jpg" "logo=$T/logo.jpg") $(rj "d.get('field')")"
st="$st $(apply "ip=$(lip)" "org_name=Logo Heavy $LRUN" "logo=$T/logo-heavy.jpg") $(rj "d.get('field')")"
check "applications refused for their logo: camera data -> 415 (logo, logo), two logos -> 400 logo, over 150 KB -> 413 logo" "$st" "415 ('logo', 'logo') 400 logo 413 logo"
check "none of them was stored" "$(lmine)" "$M0"
[ -n "$STATE" ] && check "and none wrote to R2" "$(r2mt)" "$LR0"
st=$(adm approve "$(lab "$LA1" "Logo Apply $LRUN" "logo-apply-$LRUN" "\"logo\":\"$LA1K\"")"); LA1T=$(rj "d['partner']['token']")
check "approve it with the logo's key (the box ticked) -> 201, logo live" "$st $(rj "d.get('logo')")" "201 live"
check "the logo is public at once, and the new crew's GET /api/partner has it live" "$(code $B/media/$LA1K) $(plogo "$LA1T" "l['live']")" "200 /media/$LA1K"
st=$(apply "ip=$(lip)" "org_name=Logo Apply Two $LRUN" "logo=$T/logo.jpg"); LA2=$(rj "d['id']"); LA2U=$(alist | appq "$LA2" "a['logo']['url']")
st="$st $(adm approve "$(lab "$LA2" "Logo Apply Two $LRUN" "logo-apply-two-$LRUN" '"logo":null')") $(rj "d.get('logo')")"; LA2T=$(rj "d['partner']['token']")
check "another one approved with logo null (the box unticked) -> logo declined, its file deleted (signed link -> 404)" "$st $(gone "$B${LA2U:-/media/none}")" "201 201 declined 404"
check "that crew's GET /api/partner: declined, nothing live or waiting" "$(plogo "$LA2T" "(l['declined'], l['live'], l['review'])")" "(True, None, None)"
LC1=$(plist "d['counts']['logos']")
st=$(apply "ip=$(lip)" "org_name=Logo Apply Three $LRUN" "logo=$T/logo.jpg"); LA3=$(rj "d['id']"); LA3K=$(alist | appq "$LA3" "a['logo']['key']")
st="$st $(adm approve "$(lab "$LA3" "Logo Apply Three $LRUN" "logo-apply-three-$LRUN")") $(rj "d.get('logo')")"
check "a third one approved without the logo field (an /admin/ tab from before logos) -> the logo waits" "$st" "201 201 review"
check "GET /api/admin/partners: it waits as that crew's logo_review, and counts.logos is one more" \
  "$(plist "(p('logo-apply-three-$LRUN')['logo_review']['key'], d['counts']['logos'])")" "('$LA3K', $(add "$LC1" 1))"
check "DECLINE it under LOGOS TO CHECK -> 200" "$(ldec "$LA3K" decline)" 200
st=$(apply "ip=$(lip)" "org_name=Logo Delete $LRUN" "logo=$T/logo.jpg" "photo=$F/before.jpg"); LA4=$(rj "d['id']")
L=$(alist); LA4U=$(echo "$L" | appq "$LA4" "a['logo']['url']"); LA4K=$(echo "$L" | appq "$LA4" "a['logo']['key']")
check "DELETE APPLICATION of one with a photo and a logo -> 200, 1 photo and 1 logo deleted, the logo's link -> 404" \
  "$st $(adm reject "{\"id\":\"$LA4\"}") $(rj "(d.get('deleted_photos'), d.get('deleted_logo'))") $(gone "$B${LA4U:-/media/none}")" "201 200 (1, 1) 404"
[ -n "$STATE" ] && check "no logo row is left for it" "$(d1 "SELECT COUNT(*) AS n FROM logos WHERE key = '$LA4K'" | jget "d[0]['results'][0]['n']")" 0
if [ -n "$STATE" ]; then
  # DELETE APPLICATION and the undo in /api/apply claim the logo (gone, no crew yet) before they touch its file, so an
  # approval in the same moment can never make it live: APPROVE AND CREATE PARTNER with the box ticked leaves a claimed
  # logo out, and the next applications run deletes its row and file. DELETE APPLICATION claims a claimed logo again (a
  # retry after a failed delete) and deletes it.
  st=$(apply "ip=$(lip)" "org_name=Logo Claimed $LRUN" "logo=$T/logo.jpg"); LA6=$(rj "d['id']"); LA6K=$(alist | appq "$LA6" "a['logo']['key']")
  d1 "UPDATE logos SET status = 'gone', decided_at = '$(ago 0)' WHERE key = '${LA6K:-none}'" >/dev/null
  st="$st $(adm approve "$(lab "$LA6" "Logo Claimed $LRUN" "logo-claimed-$LRUN" "\"logo\":\"${LA6K:-none}\"")") $(rj "d.get('logo')")"; LA6T=$(rj "d['partner']['token']")
  check "a logo another request already claimed is not taken along by APPROVE AND CREATE PARTNER with the box ticked: 201, logo None, nothing live, not public" \
    "$st $(plogo "$LA6T" "l['live']") $(code $B/media/${LA6K:-none})" "201 201 None None 404"
  alist >/dev/null
  check "the next applications run deletes that claimed logo, row and file" \
    "$(d1 "SELECT COUNT(*) AS n FROM logos WHERE key = '${LA6K:-none}'" | jget "d[0]['results'][0]['n']") $(gone "$B$(hsig ${LA6K:-none})")" "0 404"
  st=$(apply "ip=$(lip)" "org_name=Logo Claimed Twice $LRUN" "logo=$T/logo.jpg"); LA7=$(rj "d['id']"); LA7K=$(alist | appq "$LA7" "a['logo']['key']")
  d1 "UPDATE logos SET status = 'gone', decided_at = '$(ago 0)' WHERE key = '${LA7K:-none}'" >/dev/null
  check "DELETE APPLICATION of one whose logo was claimed before (a retry) -> 200, deleted_logo 1, its row and file gone" \
    "$st $(adm reject "{\"id\":\"$LA7\"}") $(rj "d.get('deleted_logo')") $(d1 "SELECT COUNT(*) AS n FROM logos WHERE key = '${LA7K:-none}'" | jget "d[0]['results'][0]['n']") $(gone "$B$(hsig ${LA7K:-none})")" "201 200 1 0 404"

  # The 90-day expiry of an open application takes its logo too, file and row (sweepApplicationLogos).
  st=$(apply "ip=$(lip)" "org_name=Logo Expire $LRUN" "logo=$T/logo.jpg"); LA5=$(rj "d['id']"); LA5K=$(alist | appq "$LA5" "a['logo']['key']")
  if d1 "UPDATE applications SET created_at = '$(ago 91)' WHERE id = '$LA5'" >/dev/null; then
    check "an open application with a logo, aged to 91 days: GET applications deletes it, its logo row and its file" \
      "$st $(alist | appq "$LA5" "a") $(d1 "SELECT COUNT(*) AS n FROM logos WHERE key = '$LA5K'" | jget "d[0]['results'][0]['n']") $(gone "$B$(hsig ${LA5K:-none})")" "201 None 0 404"
  else
    bad "age an application with a logo in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # Deploy order: if the code goes live before migration 0006, the site works as without logos. The logos table is
  # renamed for a moment (finish() renames it back if the script stops in between). The housekeeping's answer without
  # it is checked at the end of the housekeeping part: its first POST there must be the one that runs the jobs.
  st=$(apply "ip=$(lip)" "org_name=Logo Before Delete $LRUN" "photo=$F/before.jpg"); LE1=$(rj "d['id']"); LE1U=$(alist | appq "$LE1" "a['photos'][0]['url']")
  EPJ=$(newp "No Logo Crew $LRUN" ID "no-logo-$LRUN"); EPID=$(echo "$EPJ" | jget "d['id']")
  # The crew from the first logo application, whose logo is live, posts a mission and it is published: it is on /crews
  # with its logo, and must show its letters there while the logos table is missing.
  st=$(mpost "$LA1T" "place_name=Logo Apply mission $LRUN" "media=$(upk "$LA1T" before)"); st="$st $(act "$(mj "d.get('id')")" publish)"
  check "the crew with a live logo from its application has a mission on sapu.earth, and /crews shows its logo" \
    "$st $(cxpage) $(cxq "'<img class=\"cx-logo\" src=\"/media/$LA1K\"' in (card('logo-apply-$LRUN') or {}).get('html', '')")" "201 200 200 True"
  LRENAMED=1
  if d1 "ALTER TABLE logos RENAME TO logos_e2e_off" >/dev/null; then
    E1="$(code "$B/api/partner?k=$LT") $(plogo $LT "(l['enabled'], l['live'], l['review'])")"
    E2="$(lpost $LT $T/logo.jpg) $(lj "d.get('code')")"
    E3M=$(r2mt); st=$(apply "ip=$(lip)" "org_name=Logo Before $LRUN" "logo=$T/logo.jpg"); LE2=$(rj "d['id']")
    E3="$st $([ "$(r2mt)" = "$E3M" ] && echo same || echo changed) $(alist | appq "$LE2" "a['logo']")"
    E4="$(adm approve "$(lab "$LE2" "Logo Before $LRUN" "logo-before-$LRUN" '"logo":null')") $(rj "d.get('logo')")"
    E5="$(adm reject "{\"id\":\"$LE1\"}") $(rj "d.get('deleted_logo')") $(gone "$B${LE1U:-/media/none}")"
    E6="$(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/admin/partners -H "$A") $(jget "(d['counts']['logos'], all(p['logo'] is None and p['logo_review'] is None for p in d['partners']))" < "$T/e.json")"
    E7="$(code $B/media/$LA1K) $(code $B/media/$KB)"
    E8="$(curl -s -o "$T/e.html" -w '%{http_code}' $B/p/logo-apply-$LRUN) $(grep -c 'ph-logo' "$T/e.html")"
    E9="$(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/events) $(jget "all(e['provider'].get('logo') is None for e in d)" < "$T/e.json")"
    E9="$E9 $(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/missions) $(jget "all(m['partner'].get('logo') is None for m in d)" < "$T/e.json")"
    E10="$(curl -s -o "$T/l.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$EPID\"}") $(lj "d.get('logos_removed')")"
    E11="$(cxpage) $(cxq "(len(cards) > 0, all('cx-logo' not in c['html'] and 'class=\"cx-mono\"' in c['html'] for c in cards + new), card('logo-apply-$LRUN') is not None)")"
    d1 "ALTER TABLE logos_e2e_off RENAME TO logos" >/dev/null && LRENAMED=
    check "without the logos table: GET /api/partner -> 200, logos off (the crew page hides YOUR LOGO)" "$E1" "200 (False, None, None)"
    check "without the logos table: POST /api/logo -> 503 migration" "$E2" "503 migration"
    check "without the logos table: an application with only a logo -> 201, nothing written to R2, its card without a logo" "$E3" "201 same None"
    check "without the logos table: approving it with logo null -> 201, logo None" "$E4" "201 None"
    check "without the logos table: DELETE APPLICATION of one with a photo -> 200, deleted_logo 0, its photo deleted" "$E5" "200 0 404"
    check "without the logos table: GET /api/admin/partners (the /admin/ login) -> 200, counts.logos 0, no logos" "$E6" "200 (0, True)"
    check "without the logos table: a live logo's /media/ -> 404, an approved photo's -> 200" "$E7" "404 200"
    check "without the logos table: /p/<slug> of a crew with a live logo -> 200 without it" "$E8" "200 0"
    check "without the logos table: /api/events and /api/missions -> 200, no logo anywhere" "$E9" "200 True 200 True"
    check "without the logos table: DEACTIVATE -> 200, logos_removed 0" "$E10" "200 0"
    check "without the logos table: /crews -> 200, every crew with its letters (JUST JOINED too), also the one whose logo is live" "$E11" "200 (True, True, True)"
    check "logos table back in place: the live logo -> 200 again, and /crews shows it again" \
      "$(code $B/media/$LA1K) $(cxpage) $(cxq "'<img class=\"cx-logo\" src=\"/media/$LA1K\"' in (card('logo-apply-$LRUN') or {}).get('html', '')")" "200 200 True"
  else
    LRENAMED=
    bad "rename the logos table in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi
check "applications with logos cleaned up" "$(lmine)" 0
check "deactivate the daily limit crew, so its logo no longer waits -> 200" \
  "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$DPID\"}")" 200

# ---------- Crew TikTok accounts (POST /api/tiktok, TIKTOK TO CHECK, /p/<slug>, /crews) ----------
# A crew sends its own TikTok account from its crew page (YOUR TIKTOK, POST /api/tiktok): its name with the @, or a link
# to its profile, read by the same block as the page's (tiktokAccount). It waits for Marcus, and APPROVE TIKTOK, DECLINE
# and REMOVE TIKTOK decide it (POST /api/admin/tiktok/decide), each naming the account Marcus saw. The live account of an
# active crew is linked on /p/<slug> and on its /crews card. And the link preview of /p/<slug>: the crew's logo first,
# then its first after photo, then the broom. Crews of their own, so no count above or below moves
# (docs/upload-flow.md, Crew TikTok accounts).
TRUN=$RANDOM$RANDOM
# tpost <token> <json>: POST /api/tiktok. Prints the status, the body goes to $T/t.json.
tpost() { curl -s -o "$T/t.json" -w '%{http_code}' -X POST "$B/api/tiktok?k=$1" -H 'content-type: application/json' -d "$2"; }
tj()    { jget "$1" < "$T/t.json"; }
# tdec <partner id> <account> <action>: POST /api/admin/tiktok/decide. Prints the status, the body goes to $T/t.json.
tdec()  { curl -s -o "$T/t.json" -w '%{http_code}' -X POST $B/api/admin/tiktok/decide -H "$A" -H 'content-type: application/json' \
            -d "{\"partner_id\":\"$1\",\"account\":\"$2\",\"action\":\"$3\"}"; }
# ptt <token> <expr>: a Python expression over the TikTok state (t) of that crew's GET /api/partner.
ptt()   { curl -s "$B/api/partner?k=$1" | python3 -c "import json,sys;t=json.load(sys.stdin).get('tiktok');print(eval(sys.argv[1]))" "$2" 2>/dev/null; }
# ttcard <slug>: that crew's card on /crews, or NO CARD.
ttcard() { curl -s $B/crews | python3 -c "
import re,sys
m = re.search(r'<li class=\"cx-card[^\"]*\" data-slug=\"' + re.escape(sys.argv[1]) + r'\">(.*?)\n    </li>', sys.stdin.read(), re.S)
print(m.group(1) if m else 'NO CARD')" "$1"; }

TSLUG="teluk-$TRUN"
TPJ=$(newp "Teluk Crew $TRUN" ID "$TSLUG"); TT=$(echo "$TPJ" | jget "d['token']"); TPID=$(echo "$TPJ" | jget "d['id']")
check "GET /api/partner of a new crew: TikTok accounts on, none live or waiting, not declined" \
  "$(ptt $TT "(t['enabled'], t['live'], t['review'], t['declined'])")" "(True, None, None, False)"
st="$(tpost AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA '{"account":"@kru"}')"
st="$st $(curl -s -o /dev/null -D "$T/t.h" -w '%{http_code}' "$B/api/tiktok?k=$TT") $(tr -d '\r' < "$T/t.h" | sed -n 's/^[Aa]llow: *//p')"
st="$st $(tpost $TT '[1]') $(tpost $TT '{"account":5}') $(tj "d.get('code')")"
st="$st $(tpost $TT '{"account":"https://vt.tiktok.com/ZSabc123/"}') $(tj "d.get('code')")"
st="$st $(tpost $TT '{"account":"https://www.instagram.com/sapu.earth/"}') $(tj "d.get('code')")"
st="$st $(tpost $TT '{"account":"kru.org"}') $(tj "d.get('code')")"
st="$st $(tpost $TT "{\"account\":\"@$(printf 'a%.0s' $(seq 1 2100))\"}")"
check "POST /api/tiktok refused: a link that is not valid, GET (Allow: POST), not an object, not text, a short link, another site, a name without its @, over 2 KB" \
  "$st" "404 405 POST 400 400 tiktok 400 short 400 tiktok 400 tiktok 413"
check "after the refusals nothing waits" "$(ptt $TT "(t['live'], t['review'])")" "(None, None)"

TC0=$(plist "d['counts']['tiktok']")
check "POST /api/tiktok with a profile link as the TikTok app copies it -> 200: the account waits, in lower case, nothing live, not declined" \
  "$(tpost $TT '{"account":"https://www.tiktok.com/@Kru.Teluk_E2E?_t=ZS-8sXabc&_r=1"}') $(tj "(d['tiktok']['review'], d['tiktok']['live'], d['tiktok']['declined'])")" \
  "200 ('kru.teluk_e2e', None, False)"
check "GET /api/admin/partners: counts.tiktok one more, this crew's tiktok_review with when it was sent, nothing live" \
  "$(plist "(d['counts']['tiktok'], p('$TSLUG')['tiktok_review']['account'], len(p('$TSLUG')['tiktok_review']['sent_at']), p('$TSLUG')['tiktok'])")" \
  "($(add "$TC0" 1), 'kru.teluk_e2e', 24, None)"
check "a waiting account shows nowhere: /p/<slug> and /crews name no TikTok of this crew" \
  "$(curl -s $B/p/$TSLUG | grep -c 'tiktok\.com') $(ttcard $TSLUG | grep -c 'tiktok')" "0 0"
check "decide: without a token 401, an unknown action 400, an account that is not a stored name 400, an unknown crew 404, another account 409 state" \
  "$(code -X POST $B/api/admin/tiktok/decide -H 'content-type: application/json' -d "{\"partner_id\":\"$TPID\",\"account\":\"kru.teluk_e2e\",\"action\":\"approve\"}") $(tdec $TPID kru.teluk_e2e boost) $(tdec $TPID '@Kru.Teluk_E2E' approve) $(tdec aaaaaaaaaa kru.teluk_e2e approve) $(tdec $TPID kru.other approve) $(tj "d.get('code')")" \
  "401 400 400 404 409 state"
check "APPROVE TIKTOK -> 200 live; GET /api/partner: live, nothing waits, not declined; counts.tiktok back" \
  "$(tdec $TPID kru.teluk_e2e approve) $(tj "(d['status'], d['account'])") $(ptt $TT "(t['live'], t['review'], t['declined'])") $(plist "d['counts']['tiktok']")" \
  "200 ('live', 'kru.teluk_e2e') ('kru.teluk_e2e', None, False) $TC0"
check "APPROVE TIKTOK again -> 409 state" "$(tdec $TPID kru.teluk_e2e approve) $(tj "d.get('code')")" "409 state"
PG=$(curl -s $B/p/$TSLUG)
echo "$PG" | grep -qF '<p class="sub">// cleanup partner · ID · <a href="https://example.org/" rel="noopener nofollow ugc" target="_blank">example.org ↗</a> · <a class="p-tiktok" href="https://www.tiktok.com/@kru.teluk_e2e" rel="noopener noreferrer nofollow ugc" target="_blank">tiktok.com/@kru.teluk_e2e ↗</a></p>' \
  && [ "$(echo "$PG" | grep -c 'tiktok\.com')" = 1 ] \
  && ok "/p/<slug>: the live account in the line under the name, after the website: tiktok.com/@..., a new tab, no referrer, nofollow ugc" \
  || bad "/p/<slug> TikTok link" "$(echo "$PG" | grep -n 'tiktok')"
TCX=$(ttcard $TSLUG)
TCW='<small>Indonesia&nbsp;· first&nbsp;mission&nbsp;coming</small></span></a>
      <p class="cx-last cx-tt"><a href="https://www.tiktok.com/@kru.teluk_e2e" rel="noopener noreferrer nofollow ugc" target="_blank"><b>TIKTOK</b><span>@kru.teluk_e2e</span>↗</a></p>'
[[ "$TCX" == *"$TCW" ]] && [ "$(echo "$TCX" | grep -c 'tiktok\.com')" = 1 ] \
  && ok "/crews: the crew's JUST JOINED card ends with its live account (TIKTOK @..., a new tab, no referrer, nofollow ugc)" || bad "/crews TikTok row" "$TCX"
grep -qF '.cx-tt a > span { text-transform: none; overflow-wrap: anywhere; }' site/forms.css \
  && ok "/crews keeps the account's own lower case letters in its upper case rows" || bad "/crews TikTok letters" ""

check "a new account while one is live: it waits, the live one stays (the crew page: sapu.earth keeps linking it)" \
  "$(tpost $TT '{"account":"@kru.baru"}') $(tj "(d['tiktok']['live'], d['tiktok']['review'])") $(curl -s $B/p/$TSLUG | grep -c 'tiktok.com/@kru.teluk_e2e ↗')" "200 ('kru.teluk_e2e', 'kru.baru') 1"
TS1=$(plist "p('$TSLUG')['tiktok_review']['sent_at']")
st="$(tpost $TT '{"account":"tiktok.com/@KRU.BARU"}')"; TS2=$(plist "p('$TSLUG')['tiktok_review']['sent_at']")
check "the waiting account sent again keeps its place (sent_at); the live one sent again clears what waits" \
  "$st $([ -n "$TS1" ] && [ "$TS1" = "$TS2" ] && echo kept) $(tpost $TT '{"account":"@kru.teluk_e2e"}') $(tj "(d['tiktok']['live'], d['tiktok']['review'], d['tiktok']['declined'])")" \
  "200 kept 200 ('kru.teluk_e2e', None, False)"
check "a video link names its account: it waits; DECLINE -> 200 declined, the live one stays, nothing waits, declined" \
  "$(tpost $TT '{"account":"https://m.tiktok.com/@kru.baru/video/7312345678901234567?is_from_webapp=1"}') $(tj "d['tiktok']['review']") $(tdec $TPID kru.baru decline) $(tj "d['status']") $(ptt $TT "(t['live'], t['review'], t['declined'])")" \
  "200 kru.baru 200 declined ('kru.teluk_e2e', None, True)"
check "DECLINE again -> 409 state, and the declined account is not kept" \
  "$(tdec $TPID kru.baru decline) $(tj "d.get('code')") $(plist "p('$TSLUG')['tiktok_review']")" "409 state None"
[ -n "$STATE" ] && check "the crew's row keeps the live account and when Marcus declined, never the declined account" \
  "$(d1 "SELECT live, review, sent_at, declined_at IS NOT NULL AS d FROM crew_tiktok WHERE partner_id = '$TPID'" | jget "[(r['live'], r['review'], r['sent_at'], r['d']) for r in d[0]['results']]")" \
  "[('kru.teluk_e2e', None, None, 1)]"
check "REMOVE TIKTOK -> 200 declined; GET /api/partner: nothing live, declined; /p/<slug> and /crews link no account" \
  "$(tdec $TPID kru.teluk_e2e remove) $(tj "d['status']") $(ptt $TT "(t['live'], t['declined'])") $(curl -s $B/p/$TSLUG | grep -c 'tiktok\.com') $(ttcard $TSLUG | grep -c 'tiktok')" \
  "200 declined (None, True) 0 0"
check "REMOVE TIKTOK again -> 409 state" "$(tdec $TPID kru.teluk_e2e remove) $(tj "d.get('code')")" "409 state"
check "the crew sends one again (no longer declined), it is approved, then the crew takes it off itself (an empty account): nothing live or waiting, not declined" \
  "$(tpost $TT '{"account":"@kru.teluk_e2e"}') $(tj "d['tiktok']['declined']") $(tdec $TPID kru.teluk_e2e approve) $(tpost $TT '{"account":""}') $(tj "(d['tiktok']['live'], d['tiktok']['review'], d['tiktok']['declined'])")" \
  "200 False 200 200 (None, None, False)"
check "account null takes a waiting one off too" \
  "$(tpost $TT '{"account":"@kru.satu"}') $(tpost $TT '{"account":null}') $(tj "(d['tiktok']['live'], d['tiktok']['review'])")" "200 200 (None, None)"
[ -n "$STATE" ] && check "taking it off deletes the crew's row" "$(d1 "SELECT COUNT(*) AS n FROM crew_tiktok WHERE partner_id = '$TPID'" | jget "d[0]['results'][0]['n']")" 0
check "a crew that changes its account while Marcus looks: APPROVE of the one he saw -> 409 state, the newer one still waits" \
  "$(tpost $TT '{"account":"@kru.satu"}') $(tpost $TT '{"account":"@kru.dua"}') $(tdec $TPID kru.satu approve) $(tj "d.get('code')") $(ptt $TT "(t['live'], t['review'])")" \
  "200 200 409 state (None, 'kru.dua')"
st="$(tdec $TPID kru.dua approve) $(tpost $TT '{"account":"@kru.tiga"}')"
st="$st $(curl -s -o "$T/t.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$TPID\"}") $(tj "d.get('tiktok_removed')")"
check "one live and one waiting, then DEACTIVATE -> 200, tiktok_removed 1" "$st" "200 200 200 1"
check "after DEACTIVATE: the crew link -> 404, its row lists no TikTok, a decision -> 409 inactive" \
  "$(tpost $TT '{"account":"@kru.empat"}') $(plist "(p('$TSLUG')['tiktok'], p('$TSLUG')['tiktok_review'])") $(tdec $TPID kru.dua remove) $(tj "d.get('code')")" \
  "404 (None, None) 409 inactive"
[ -n "$STATE" ] && check "DEACTIVATE deletes the crew's row" "$(d1 "SELECT COUNT(*) AS n FROM crew_tiktok WHERE partner_id = '$TPID'" | jget "d[0]['results'][0]['n']")" 0

# The link preview of /p/<slug> (Marcus asked on 2026-11-19 for the crew's logo there): a crew with a receipt shows its
# first after photo with a large card while it has no logo; once its logo is live, the logo with a small square card.
VSLUG="cover-$TRUN"
VPJ=$(newp "Cover Crew $TRUN" ID "$VSLUG"); VT2=$(echo "$VPJ" | jget "d['token']")
VB=$(upk $VT2 before); VA=$(upk $VT2 after)
st=$(msub $VT2 - "$VB,$VA"); VS=$(mj "d.get('id')"); st="$st $(sdec "{\"id\":\"${VS:-none}\",\"action\":\"approve\",\"paid_eur\":20}")"
PG=$(curl -s $B/p/$VSLUG)
[ "$st" = "200 approved" ] && echo "$PG" | grep -qF "<meta property=\"og:image\" content=\"$B/media/$VA\">" \
  && echo "$PG" | grep -qF '<meta name="twitter:card" content="summary_large_image">' && [ "$(echo "$PG" | grep -c 'og:image')" = 1 ] \
  && ok "/p/<slug> of a crew with a receipt and no logo: its first after photo is the link preview, absolute, with a large card" \
  || bad "/p/<slug> preview without a logo" "$st $(echo "$PG" | grep -E 'og:image|twitter')"
st=$(lpost $VT2 $T/logo.jpg); VK=$(lkey); st="$st $(ldec "$VK" approve)"
PG=$(curl -s $B/p/$VSLUG)
PGW="<meta property=\"og:image\" content=\"$B/media/$VK\">
<meta property=\"og:image:type\" content=\"image/jpeg\">
<meta property=\"og:image:alt\" content=\"The logo of Cover Crew $TRUN\">
<meta name=\"twitter:card\" content=\"summary\">"
[ "$st" = "201 200" ] && [[ "$PG" == *"$PGW"* ]] && [ "$(echo "$PG" | grep -c 'og:image')" = 3 ] && ! echo "$PG" | grep -q 'summary_large_image' \
  && [ "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' $B/media/$VK)" = "200 image/jpeg" ] \
  && ok "/p/<slug> once the crew's logo is live: the logo is the link preview before its receipt photo (absolute, public, JPEG, its alt, twitter:card summary)" \
  || bad "/p/<slug> preview with a logo" "$st $(echo "$PG" | grep -E 'og:image|twitter')"
check "deactivate the cover crew -> 200" \
  "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$(echo "$VPJ" | jget "d['id']")\"}")" 200

# The TikTok account block (tiktokAccount), run in node: the same in upload.js (as served) and functions/_lib/tiktok.js
# (leading spaces aside), and both copies read 45 typed or pasted values as they should: the account, a short link, or
# nothing. accountOf takes a stored name back only as it was, and noTiktokTable knows D1's error for the table.
curl -s $B/upload/upload.js > "$T/tt-u.js"
TTN=$(node -e '
const fs = require("fs");
const u = fs.readFileSync(process.argv[1], "utf8"), lib = fs.readFileSync("functions/_lib/tiktok.js", "utf8");
const cut = (s) => { const a = s.indexOf("// ---------- TikTok accounts: the same block"), b = s.indexOf("// ---------- end of the TikTok account block ----------");
  if (a < 0 || b < a) throw new Error("no TikTok account block"); return s.slice(a, b); };
const flat = (s) => s.split("\n").map((l) => l.replace(/^ +/, "")).join("\n");
const bad = [];
if (flat(cut(u)) !== flat(cut(lib))) bad.push("the two blocks differ");
const load = (s) => new Function(cut(s) + "\nreturn { TIKTOK_MAX, tiktokAccount };")();
const v = "https://www.tiktok.com/@sapu.earth/video/7312345678901234567";
const cases = [
  ["@sapu.earth", "sapu.earth"], ["  @Kru_Bersih  ", "kru_bersih"], ["@KRU.Bersih.2026", "kru.bersih.2026"], ["@" + "a".repeat(24), "a".repeat(24)],
  ["https://www.tiktok.com/@sapu.earth", "sapu.earth"], ["https://www.tiktok.com/@sapu.earth/", "sapu.earth"],
  ["https://www.tiktok.com/@Sapu.Earth?_t=ZS-8sXabc&_r=1", "sapu.earth"], ["https://m.tiktok.com/@kru_bersih", "kru_bersih"],
  ["https://tiktok.com/@kru_bersih#top", "kru_bersih"], ["tiktok.com/@kru_bersih", "kru_bersih"], ["www.tiktok.com/@kru_bersih?lang=id", "kru_bersih"],
  ["HTTPS://WWW.TIKTOK.COM/@KRU", "kru"], [v + "?is_from_webapp=1", "sapu.earth"], ["https://www.tiktok.com/@sapu.earth/photo/7312345678901234567", "sapu.earth"],
  ["https://vt.tiktok.com/ZSabc123/", "short"], ["https://vm.tiktok.com/ZMabc123/", "short"], ["vt.tiktok.com/ZSabc123/", "short"],
  ["https://www.tiktok.com/t/ZTabc123/", "short"],
  ["sapu.earth", null], ["tiktok.com", null], ["kru.org", null], ["@a", null], ["@" + "a".repeat(25), null], ["@...", null], ["@kru-bersih", null],
  ["@kru<script>", null], ["@@kru", null], ["http://www.tiktok.com/@sapu.earth", null], ["https://www.tiktok.com.evil.example/@sapu.earth", null],
  ["https://evil.example/@sapu.earth", null], ["https://u:pw\x40www.tiktok.com/@sapu.earth", null], ["https://www.tiktok.com:444/@sapu.earth", null],
  ["https://www.tiktok.com/sapu.earth", null], ["https://www.tiktok.com/@sapu earth", null], ["https://www.tiktok.com/@sapu.earth/live", null],
  ["https://www.tiktok.com/@sapu.earth/video/abc", null], ["https://www.instagram.com/sapu.earth/", null], ["javascript:alert(1)", null],
  ["https://www.tiktok.com/@%73apu", null], ["https://www.tiktok.com./@sapu.earth", null], ["//www.tiktok.com/@sapu.earth", null],
  ["https://www.tiktok.com/@sapu.earth?x=" + "a".repeat(280), null], ["", null], [null, null], [5, null],
];
for (const [name, s] of [["upload.js", u], ["tiktok.js", lib]]) {
  const P = load(s);
  if (P.TIKTOK_MAX !== 300) bad.push(name + " TIKTOK_MAX");
  for (const [inp, want] of cases) {
    const r = P.tiktokAccount(inp), got = r === null ? null : r.short ? "short" : r.account;
    if (got !== want) bad.push(name + " " + JSON.stringify(inp) + " -> " + JSON.stringify(got));
    if (r && r.account && r.url !== "https://www.tiktok.com/@" + r.account) bad.push(name + " url " + r.url);
  }
}
const L = new Function(lib.slice(lib.indexOf("// ---------- TikTok accounts: the same block"), lib.indexOf("// D1\x27s error when migration 0009")).replace(/^export \{.*$/gm, "").replace(/^export /gm, "") +
  "\nreturn { accountOf, tiktokUrl };")();
for (const [inp, want] of [["sapu.earth", "sapu.earth"], ["Sapu.Earth", null], ["@sapu.earth", null], ["sapu earth", null], ["a", null], ["", null], [null, null], [5, null]]) {
  if (L.accountOf(inp) !== want) bad.push("accountOf " + JSON.stringify(inp));
}
if (L.tiktokUrl("sapu.earth") !== "https://www.tiktok.com/@sapu.earth") bad.push("tiktokUrl");
const no = new Function(lib.slice(lib.indexOf("export function noTiktokTable"), lib.indexOf("// Runs fn(true)")).replace("export ", "") + "\nreturn noTiktokTable;")();
if (!no(new Error("D1_ERROR: no such table: crew_tiktok: SQLITE_ERROR"))) bad.push("noTiktokTable");
if (no(new Error("D1_ERROR: no such table: logos: SQLITE_ERROR")) || no(new Error("no such table: crew_tiktok_old"))) bad.push("noTiktokTable too wide");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + cases.length);
' "$T/tt-u.js" 2>&1)
check "the TikTok account block is the same in upload.js and functions/_lib/tiktok.js and reads 45 values right in both; accountOf, tiktokUrl, noTiktokTable (node)" "$TTN" "ok 45"

# The crew page: YOUR TIKTOK between YOUR LOGO and YOUR PUBLIC PAGE, hidden until the server says TikTok accounts are on,
# its texts in both languages without dashes, and the upload notice says what is kept, shown and deleted.
UPT=$(curl -s $B/upload/)
[ "$(echo "$UPT" | grep -n 'id="logoBox"' | cut -d: -f1)" -lt "$(echo "$UPT" | grep -n 'id="ttBox"' | cut -d: -f1)" ] \
  && [ "$(echo "$UPT" | grep -n 'id="ttBox"' | cut -d: -f1)" -lt "$(echo "$UPT" | grep -n 'id="pubPage"' | cut -d: -f1)" ] \
  && echo "$UPT" | grep -qF '<section class="panel cp-tiktok" id="ttBox" hidden>' \
  && echo "$UPT" | grep -qF '<input type="text" id="ttInput" inputmode="email" maxlength="300" autocomplete="off" autocapitalize="off" spellcheck="false" data-ph="tt_ph" placeholder="@yourcrew" aria-labelledby="ttLab" aria-describedby="ttHint ttRules ttEcho">' \
  && grep -qF '    box.hidden = !(tt && tt.enabled === true);' "$T/tt-u.js" && grep -qF 'if (ttE !== ttEpoch) fresh.tiktok = ttLast;' "$T/tt-u.js" \
  && grep -qF 'if (r && r.status === 503 && code === "migration") throw new Fatal("migration");' "$T/tt-u.js" \
  && ok "the crew page: YOUR TIKTOK between YOUR LOGO and YOUR PUBLIC PAGE, hidden until GET /api/partner says tiktok.enabled, and a list asked for before a TikTok answer never brings the older state back" \
  || bad "crew page YOUR TIKTOK" ""
TTX=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8"); const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const keys = ["tt_h", "tt_send", "tt_remove", "tt_ph", "tt_none", "tt_review", "tt_review_live", "tt_live", "tt_declined", "tt_declined_live", "tt_sending",
  "tt_label", "tt_hint", "tt_rules", "tt_ok", "tt_remove_q", "e_tt", "e_tt_short", "e_tt_empty", "e_tt_send"];
const bad = [];
for (const l of ["en", "id"]) for (const k of keys) if (typeof T[l][k] !== "string" || !T[l][k]) bad.push(l + " " + k);
for (const l of ["en", "id"]) for (const k of keys) if (/[\u2013\u2014]/.test(T[l][k] || "")) bad.push(l + " dash " + k);
for (const l of ["en", "id"]) for (const k of ["tt_review", "tt_review_live", "tt_live"]) if (!(T[l][k] || "").includes("@{acct}")) bad.push(l + " acct " + k);
for (const l of ["en", "id"]) for (const k of ["tt_review_live", "tt_declined_live"]) if (!(T[l][k] || "").includes("@{live}")) bad.push(l + " live " + k);
if (T.en.tt_h !== "YOUR TIKTOK" || T.id.tt_h !== "TIKTOK KRU KAMU") bad.push("titles");
const pv = { en: ["And your crew\x27s logo and TikTok account, if you add them.", "Once we approve your crew\x27s TikTok account, your crew\x27s public page and the list of crews link to it.",
    "with its name, logo, country and TikTok account.", "Your crew\x27s TikTok account is deleted when you remove it or another one replaces it, when we do not use it, and when we stop working together."],
  id: ["Juga logo dan akun TikTok kru kamu, kalau kamu menambahkannya.", "Setelah kami setujui juga, halaman publik kru kamu dan daftar kru menampilkan link ke akun TikTok kru kamu.",
    "dengan nama, logo, negara, dan akun TikTok-nya.", "Akun TikTok kru kamu dihapus kalau kamu menghapusnya atau akun lain menggantikannya, kalau tidak kami pakai, atau kalau kerja sama kita berhenti."] };
for (const l of ["en", "id"]) {
  const all = [T[l].pv_what, T[l].pv_public, T[l].pv_long].join(" ");
  for (const p of pv[l]) if (!all.includes(p)) bad.push(l + " notice: " + p.slice(0, 40));
}
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/tt-u.js" 2>&1)
check "YOUR TIKTOK's texts in EN and ID (no dashes, the account in each state line), and the upload notice's TikTok sentences in both languages (node)" "$TTX" ok
[ "$(echo "$UPT" | grep -cF "And your crew's logo and TikTok account, if you add them.")" = 1 ] \
  && [ "$(echo "$UPT" | grep -cF "Once we approve your crew's TikTok account, your crew's public page and the list of crews link to it.")" = 1 ] \
  && [ "$(echo "$UPT" | grep -cF "Your crew's TikTok account is deleted when you remove it or another one replaces it, when we do not use it, and when we stop working together.")" = 1 ] \
  && ok "the upload notice on the page (EN) says the TikTok account is sent, shown once approved, and deleted" || bad "upload notice TikTok on the page" ""
AJT=$(curl -s $B/admin/admin.js)
echo "$AJT" | grep -qF '"/api/admin/tiktok/decide", { partner_id: p.id, account, action: act === "tiktok-approve" ? "approve" : "decline" }' \
  && echo "$AJT" | grep -qF '"/api/admin/tiktok/decide", { partner_id: p.id, account: tiktok, action: "remove" }' \
  && echo "$AJT" | grep -qF 'drawTiktokCheck(partners);' && echo "$AJT" | grep -qF 'setPartnerCount(data.counts);' \
  && echo "$AJT" | grep -qF 'if (tt > 0) parts.push(`${tt} TIKTOK`);' \
  && echo "$AJT" | grep -qF '<a href="${esc(ttLink(account))}" target="_blank" rel="noopener noreferrer">OPEN ON TIKTOK ↗</a>' \
  && echo "$AJT" | grep -qF '(p.tiktok || p.tiktok_review ? " Their TikTok account comes off sapu.earth too." : "") +' \
  && ok "/admin/: TIKTOK TO CHECK (OPEN ON TIKTOK, APPROVE TIKTOK, DECLINE with the account shown), REMOVE TIKTOK, the tab count and DEACTIVATE's question" \
  || bad "/admin/ TikTok" ""

# Deploy order: before migration 0009 the site works as without TikTok accounts. The table is renamed for a moment
# (finish() renames it back if the script stops in between). The housekeeping's answer without it is checked at the end
# of the housekeeping part: its first POST there must be the one that runs the jobs.
if [ -n "$STATE" ]; then
  WPJ=$(newp "TikTok Before $TRUN" ID "tt-before-$TRUN"); WT=$(echo "$WPJ" | jget "d['token']"); WPID=$(echo "$WPJ" | jget "d['id']")
  st="$(tpost $WT '{"account":"@kru.before"}') $(tdec $WPID kru.before approve)"
  TRENAMED=1
  if [ "$st" = "200 200" ] && d1 "ALTER TABLE crew_tiktok RENAME TO crew_tiktok_e2e_off" >/dev/null; then
    T1="$(code "$B/api/partner?k=$WT") $(ptt $WT "(t['enabled'], t['live'], t['review'], t['declined'])")"
    T2="$(tpost $WT '{"account":"@kru.lain"}') $(tj "d.get('code')") $(tdec $WPID kru.before remove) $(tj "d.get('code')")"
    T3="$(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/admin/partners -H "$A") $(jget "(d['counts']['tiktok'], all(p['tiktok'] is None and p['tiktok_review'] is None for p in d['partners']))" < "$T/e.json")"
    T4="$(curl -s -o "$T/e.html" -w '%{http_code}' $B/p/tt-before-$TRUN) $(grep -c 'tiktok\.com' "$T/e.html") $(curl -s -o "$T/e.html" -w '%{http_code}' $B/crews) $(grep -c 'cx-tt' "$T/e.html")"
    T5="$(curl -s -o "$T/t.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$WPID\"}") $(tj "d.get('tiktok_removed')")"
    d1 "ALTER TABLE crew_tiktok_e2e_off RENAME TO crew_tiktok" >/dev/null && TRENAMED=
    check "without the crew_tiktok table: GET /api/partner -> 200, TikTok accounts off (the crew page hides YOUR TIKTOK)" "$T1" "200 (False, None, None, False)"
    check "without the crew_tiktok table: POST /api/tiktok and a decision -> 503 migration" "$T2" "503 migration 503 migration"
    check "without the crew_tiktok table: GET /api/admin/partners (the /admin/ login) -> 200, counts.tiktok 0, no accounts" "$T3" "200 (0, True)"
    check "without the crew_tiktok table: /p/<slug> of a crew with a live account and /crews -> 200, no TikTok link" "$T4" "200 0 200 0"
    check "without the crew_tiktok table: DEACTIVATE -> 200, tiktok_removed 0" "$T5" "200 0"
    check "crew_tiktok back in place: that deactivated crew's row is still there, and the housekeeping's sweep will take it" \
      "$(d1 "SELECT live FROM crew_tiktok WHERE partner_id = '$WPID'" | jget "[r['live'] for r in d[0]['results']]")" "['kru.before']"
  else
    TRENAMED=
    bad "rename the crew_tiktok table in the local D1 in $STATE" "$st $(tail -3 "$T/d1.err")"
  fi
fi

# ---------- The list of crews (/crews) ----------
# /crews (functions/crews/index.js) lists every active crew (listedCrews in functions/_lib/crews.js): those with an
# approved cleanup, or a mission that is funded or open on sapu.earth, newest activity first, with its logo or its
# letters, the totals of its approved receipts, its newest receipt and up to 3 missions; then the others under JUST
# JOINED, the newest first, with their logo or letters, name and country only. Never contact details or anything
# private. GET /api/partner's listed is true for every active crew, and NEXT UP on /p/<slug> follows the mission rule.
# Crews of their own: A comes from an application (its contact details must never show, also while it is under JUST
# JOINED), B has missions, C only a mission in review, D nothing, E only a pending and a rejected cleanup and a declined
# mission (C, D and E stay under JUST JOINED), X a name with HTML, L a live logo, P is in the Philippines, O has only a
# receipt from 30 days ago, J (Kenya, made with NEW PARTNER) goes from JUST JOINED up with its first published mission and
# off with DEACTIVATE (docs/upload-flow.md, The list of crews).
CXRUN=$RANDOM$RANDOM
# cxsub <token> <cleanup date> <place> <media>: POST /api/submit, no mission. Prints the status, the body goes to $T/c.json.
cxsub() { curl -s -o "$T/c.json" -w '%{http_code}' -X POST "$B/api/submit?k=$1" -H 'content-type: application/json' -d "$(body "$2" "$3" "$4")"; }
cj()    { jget "$1" < "$T/c.json"; }
# cxm <token> <place> [mission changes]: POST /api/mission with one fresh photo of the spot. Prints the status, the body
# goes to $T/m.json (mj).
cxm()   { local k=$1 p=$2; shift 2; mpost "$k" "place_name=$p" "media=$(upk "$k" before)" "$@"; }
# plisted <token>: GET /api/partner's listed.
plisted() { curl -s "$B/api/partner?k=$1" | jget "d.get('listed')"; }
cxoff() { code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$1\"}"; }

# /crews and /crews/: the same page, its headers (a strict CSP: no script, only this site's styles, fonts and pictures),
# the build's CSS, and the words of texts.
HVX=$(curl -s $B/ | grep -oE 'site/styles\.css\?v=[A-Za-z0-9]+' | head -1 | cut -d= -f2)
# The foot links /missions only while that list has something (missionsListed), whether or not a crew is listed.
MXLISTS=$(curl -s $B/missions | grep -c 'class="cx-card mx-card"')
CXH=""
for p in /crews /crews/; do
  st=$(curl -s -o "$T/cxh.html" -D "$T/cxh.h" -w '%{http_code}' "$B$p"); h=$(tr -d '\r' < "$T/cxh.h")
  hv() { echo "$h" | sed -n "s/^$1: *//Ip" | head -1; }
  [ "$st" = 200 ] || CXH="$CXH [$p: status $st]"
  [ "$(hv content-type)" = "text/html; charset=utf-8" ] && [ "$(hv cache-control)" = "public, max-age=300" ] \
    && [ "$(hv x-content-type-options)" = nosniff ] && [ "$(hv x-frame-options)" = DENY ] \
    && [ "$(hv referrer-policy)" = strict-origin-when-cross-origin ] && [ "$(echo "$h" | grep -ci '^content-security-policy:')" = 1 ] \
    && [ "$(hv content-security-policy)" = "default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" ] \
    || CXH="$CXH [$p: headers $(echo "$h" | grep -iE '^(content-type|cache-control|x-frame-options|content-security-policy|referrer-policy|x-content-type-options):' | tr '\n' '|')]"
  [ "$(grep -oE '/site/(fonts|styles|forms)\.css\?v=[A-Za-z0-9]+' "$T/cxh.html" | cut -d= -f2 | sort -u)" = "$HVX" ] \
    && [ "$(grep -cE '<link rel="stylesheet" href="/site/(fonts|styles|forms)\.css\?v=' "$T/cxh.html")" = 3 ] \
    && ! grep -qiE '<script|fonts\.(googleapis|gstatic)\.com| style=' "$T/cxh.html" || CXH="$CXH [$p: css, script or style]"
  grep -qF '<link rel="canonical" href="https://sapu.earth/crews">' "$T/cxh.html" && grep -qF '<title>The crews · Sapu Earth</title>' "$T/cxh.html" \
    && { if grep -qF 'class="cx-card"' "$T/cxh.html"; then CXD="The local cleanup crews on Sapu Earth, with their cleanups, kilograms and what Sapu Earth paid them, all from public receipts, and the spots they want to clean next."
         elif grep -qF 'class="cx-card cx-new"' "$T/cxh.html"; then CXD="The local cleanup crews on Sapu Earth. The crews listed so far just joined, and their first missions are coming."
         else CXD="The local cleanup crews on Sapu Earth. No crew is listed yet."; fi
         grep -qF "<meta name=\"description\" content=\"$CXD\">" "$T/cxh.html" && grep -qF "<meta property=\"og:description\" content=\"$CXD\">" "$T/cxh.html"; } \
    && grep -qF '<meta property="og:url" content="https://sapu.earth/crews">' "$T/cxh.html" && grep -qF '/site/social/sapu-earth-mark.png">' "$T/cxh.html" \
    && grep -qF '<meta name="twitter:card" content="summary">' "$T/cxh.html" && ! grep -qF 'post-01-hello' "$T/cxh.html" \
    && grep -qF '<h1 class="fp-title"><mark>THE CREWS</mark></h1>' "$T/cxh.html" \
    && { if grep -qF 'class="cx-card"' "$T/cxh.html" || ! grep -qF 'class="cx-card cx-new"' "$T/cxh.html"; then CXS="// local cleanup crews on sapu.earth. the totals add up their public receipts."; else CXS="// local cleanup crews on sapu.earth. the crews listed so far just joined."; fi
         grep -qF "<p class=\"sub\">$CXS</p>" "$T/cxh.html"; } \
    && ! grep -E '<p class="sub">|name="description"' "$T/cxh.html" | grep -q pays \
    && grep -qF '<h2 class="panel-title">RUN A CLEANUP CREW?</h2>' "$T/cxh.html" \
    && grep -qF '<p>We pay local crews for cleanups and publish each one as a receipt. There are no fees, and we never ask for a PIN, a password or an OTP code.</p>' "$T/cxh.html" \
    && grep -qF '<p class="hint" lang="id">Kamu membersihkan pantai, sungai, atau jalan bersama tim? Daftar dalam bahasa Indonesia, sekitar 3 menit. Tidak ada biaya apa pun, dan kami tidak pernah meminta PIN, kata sandi, atau kode OTP.</p>' "$T/cxh.html" \
    && grep -qF '<p><a class="btn btn-apply" href="/apply/">APPLY AS A CREW →</a></p>' "$T/cxh.html" \
    && { if [ "$MXLISTS" -gt 0 ]; then CXF='<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a> <a class="btn" href="/missions">ALL MISSIONS</a></p>'; else CXF='<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a></p>'; fi
         grep -qF "$CXF" "$T/cxh.html"; } \
    && grep -qF '<p><a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a></p>' "$T/cxh.html" \
    || CXH="$CXH [$p: words]"
done
grep -qF '.cx-last a { display: flex; gap: 8px; align-items: center; min-height: 44px;' site/forms.css \
  && grep -qF '.cl-tile[data-state="preparing"] .cl-mono { color: transparent; }' site/forms.css \
  && ok "forms.css: LAST CLEANUP on /crews is one link row at least 44 px tall, and the crew page's preparing tile hides the crew's letters behind its dots" \
  || bad "forms.css: LAST CLEANUP row or the preparing tile" ""
[ -z "$CXH" ] && ok "/crews and /crews/ -> 200 text/html, cached 5 minutes, nosniff, no framing, one strict CSP, no script, the build's three stylesheets, no Google Fonts, canonical sapu.earth/crews, the join box with its Indonesian line (no PIN, password or OTP), links to /apply/, /impressum/ and /, and ALL MISSIONS (/missions) at the foot only while /missions lists something" \
  || bad "/crews page and headers" "$CXH"
# /missions and /missions/: the same page, with the headers of /crews (PAGE_HEADERS in functions/_lib/crews.js; hv is the
# helper of the loop above), the build's CSS and the words of its texts (docs/upload-flow.md, The list of missions).
MXH=""
for p in /missions /missions/; do
  st=$(curl -s -o "$T/mxh.html" -D "$T/mxh.h" -w '%{http_code}' "$B$p"); h=$(tr -d '\r' < "$T/mxh.h")
  [ "$st" = 200 ] || MXH="$MXH [$p: status $st]"
  [ "$(hv content-type)" = "text/html; charset=utf-8" ] && [ "$(hv cache-control)" = "public, max-age=300" ] \
    && [ "$(hv x-content-type-options)" = nosniff ] && [ "$(hv x-frame-options)" = DENY ] \
    && [ "$(hv referrer-policy)" = strict-origin-when-cross-origin ] && [ "$(echo "$h" | grep -ci '^content-security-policy:')" = 1 ] \
    && [ "$(hv content-security-policy)" = "default-src 'none'; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" ] \
    || MXH="$MXH [$p: headers $(echo "$h" | grep -iE '^(content-type|cache-control|x-frame-options|content-security-policy|referrer-policy|x-content-type-options):' | tr '\n' '|')]"
  [ "$(grep -oE '/site/(fonts|styles|forms)\.css\?v=[A-Za-z0-9]+' "$T/mxh.html" | cut -d= -f2 | sort -u)" = "$HVX" ] \
    && [ "$(grep -cE '<link rel="stylesheet" href="/site/(fonts|styles|forms)\.css\?v=' "$T/mxh.html")" = 3 ] \
    && ! grep -qiE '<script|fonts\.(googleapis|gstatic)\.com| style=' "$T/mxh.html" || MXH="$MXH [$p: css, script or style]"
  grep -qF '<link rel="canonical" href="https://sapu.earth/missions">' "$T/mxh.html" && grep -qF '<title>The missions · Sapu Earth</title>' "$T/mxh.html" \
    && { if grep -qF 'class="cx-card mx-card"' "$T/mxh.html"; then MXD="The cleanup missions on Sapu Earth: the spots local crews want to clean, waiting for funding, funded or cleaned, each cleaned one with its public receipt."; else MXD="The cleanup missions on Sapu Earth. No mission is listed yet."; fi
         grep -qF "<meta name=\"description\" content=\"$MXD\">" "$T/mxh.html" && grep -qF "<meta property=\"og:description\" content=\"$MXD\">" "$T/mxh.html"; } \
    && grep -qF '<meta property="og:url" content="https://sapu.earth/missions">' "$T/mxh.html" && grep -qF '/site/social/sapu-earth-mark.png">' "$T/mxh.html" \
    && grep -qF '<meta name="twitter:card" content="summary">' "$T/mxh.html" && ! grep -qF 'post-01-hello' "$T/mxh.html" \
    && grep -qF '<h1 class="fp-title"><mark>THE MISSIONS</mark></h1>' "$T/mxh.html" \
    && grep -qF '<p class="sub">// dirty spots local crews want to clean. open = waiting for funding. funded = it happens. cleaned = done, with its receipt.</p>' "$T/mxh.html" \
    && grep -qF '<h2 class="panel-title">RUN A CLEANUP CREW?</h2>' "$T/mxh.html" \
    && grep -qF '<p>We pay local crews for cleanups and publish each one as a receipt. There are no fees, and we never ask for a PIN, a password or an OTP code.</p>' "$T/mxh.html" \
    && grep -qF '<p class="hint" lang="id">Kamu membersihkan pantai, sungai, atau jalan bersama tim? Daftar dalam bahasa Indonesia, sekitar 3 menit. Tidak ada biaya apa pun, dan kami tidak pernah meminta PIN, kata sandi, atau kode OTP.</p>' "$T/mxh.html" \
    && grep -qF '<p><a class="btn btn-apply" href="/apply/">APPLY AS A CREW →</a></p>' "$T/mxh.html" \
    && grep -qF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a>' "$T/mxh.html" \
    && grep -qF '<p><a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a></p>' "$T/mxh.html" \
    || MXH="$MXH [$p: words]"
done
cmp -s <(curl -s $B/missions) <(curl -s $B/missions/) || MXH="$MXH [/missions/ is not the same page]"
[ -z "$MXH" ] && ok "/missions and /missions/ -> the same page, 200 text/html, cached 5 minutes, nosniff, no framing, one strict CSP, no script, the build's three stylesheets, no Google Fonts, canonical sapu.earth/missions, its title, sub line and description, the join box with its Indonesian line (no PIN, password or OTP), links to /apply/, /impressum/ and /" \
  || bad "/missions page and headers" "$MXH"
grep -qF '.mx-head { display: flex; flex-direction: column; align-items: flex-start; gap: 8px; min-height: 44px;' site/forms.css \
  && grep -qF '.mx-card:target { outline: 3px solid var(--hivis); outline-offset: 3px; }' site/forms.css \
  && grep -qF '.mx-title .mpin-tag, .mx-title .cslip { flex: none; }' site/forms.css && grep -qF '.mx-title .cslip { margin-bottom: 4px; }' site/forms.css \
  && ! grep -qF 'lg-dot' site/forms.css && ! grep -qF 'lg-dot' functions/missions/index.js \
  && ok "forms.css: a card's head on /missions is one link at least 44 px tall, the card a post's ALL MISSIONS points at (#m-<no>) is outlined, and the cleaned slip keeps room for its torn edge in a section's title" \
  || bad "forms.css: the /missions card rules" ""
GLY=$(python3 - site/app.js functions/missions/index.js <<'PY'
import re, sys
app, fn = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
got = {k: re.findall(r"^ +%s: ('<svg class=\"gl\"[^']*</svg>'),$" % k, app, re.M) for k in ("open", "funded", "cleaned")}
same = all(len(v) == 1 and re.search(r"^  %s: %s,$" % (k, re.escape(v[0])), fn, re.M) for k, v in got.items())
print("ok" if same else "wrong: %s" % {k: len(v) for k, v in got.items()})
PY
)
check "the tags on /missions carry the globe's glyphs exactly as GLYPH in site/app.js has them (the trash bag, the broom, the checked box)" "$GLY" ok

# A, from an application (its contact details, area and about must never show): two cleanups approved, one with EUR 95
# and the newest without an amount (PAYMENT PENDING, adds nothing to what was paid), and a third one pending.
CXWA="+62 813 $(printf '%04d %04d' $((RANDOM % 10000)) $((RANDOM % 10000)))"; CXWAD=$(echo "$CXWA" | tr -cd '0-9')
CXAS="cx-a-$CXRUN"
st=$(apply "ip=$(lip)" "org_name=Crew A $CXRUN" "contact_name=Cx Contact $CXRUN" "whatsapp=$CXWA" "email=cx-$CXRUN@example.org" \
  "about=CX-ABOUT-$CXRUN" "area=CX-AREA-$CXRUN"); CXAPP=$(rj "d['id']")
st="$st $(adm approve "$(lab "$CXAPP" "Crew A $CXRUN" "$CXAS")")"; CXAT=$(rj "d['partner']['token']"); CXAI=$(rj "d['partner']['id']")
# Approved a moment ago, nothing on sapu.earth yet: under JUST JOINED, the newest, and nothing from its application on /crews.
cxpage >/dev/null
CXJA="$(cxq "(card('$CXAS'), jat('$CXAS'), '<small>Indonesia&nbsp;· first&nbsp;mission&nbsp;coming</small>' in (jj('$CXAS') or {}).get('html', ''))") $(plisted "$CXAT")"
for m in "Cx Contact $CXRUN" "$CXWAD" "cx-$CXRUN@example.org" "CX-ABOUT-$CXRUN" "CX-AREA-$CXRUN"; do grep -qF "$m" "$T/cx.html" && CXJA="$CXJA [leak: $m]"; done
check "crew A, approved from its application a moment ago: /crews has it first under JUST JOINED with Indonesia · first mission coming, nothing from the application anywhere on the page (contact name, WhatsApp, email, about, area), and GET /api/partner listed true" \
  "$CXJA" "(None, 0, True) True"
st="$st $(cxsub "$CXAT" "$(dplus -2)" "Crew A first $CXRUN" "$(upk "$CXAT" before),$(upk "$CXAT" after)")"; CXS1=$(cj "d.get('id')")
st="$st $(sdec "{\"id\":\"${CXS1:-none}\",\"action\":\"approve\",\"paid_eur\":95,\"review_note\":\"REVIEW-NOTE-456\"}")"
st="$st $(cxsub "$CXAT" "$TODAY" "Crew A newest $CXRUN" "$(upk "$CXAT" before),$(upk "$CXAT" after)")"; CXS2=$(cj "d.get('id')")
st="$st $(sdec "{\"id\":\"${CXS2:-none}\",\"action\":\"approve\"}")"
st="$st $(cxsub "$CXAT" "$TODAY" "Crew A pending $CXRUN" "$(upk "$CXAT" before),$(upk "$CXAT" after)")"
check "crew A from an application: two cleanups approved (EUR 95, and one PAYMENT PENDING), a third one pending" "$st" "201 201 200 approved 200 approved 200"
# B: one mission published (open). C: one mission in review. D: nothing.
CXBS="cx-b-$CXRUN"
CXBJ=$(newp "Crew B $CXRUN" ID "$CXBS"); CXBT=$(echo "$CXBJ" | jget "d['token']"); CXBI=$(echo "$CXBJ" | jget "d['id']")
CXCJ=$(newp "Crew C $CXRUN" ID "cx-c-$CXRUN"); CXCT=$(echo "$CXCJ" | jget "d['token']"); CXCI=$(echo "$CXCJ" | jget "d['id']")
CXDJ=$(newp "Crew D $CXRUN" ID "cx-d-$CXRUN"); CXDT=$(echo "$CXDJ" | jget "d['token']"); CXDI=$(echo "$CXDJ" | jget "d['id']")
# E: nothing public either, only a cleanup waiting in PENDING, a rejected one and a declined mission.
CXEJ=$(newp "Crew E $CXRUN" ID "cx-e-$CXRUN"); CXET=$(echo "$CXEJ" | jget "d['token']"); CXEI=$(echo "$CXEJ" | jget "d['id']")
st=$(cxm "$CXBT" "Muara B1 $CXRUN"); CXB1=$(mj "d.get('id')"); NB1=$(mj "d.get('no')"); st="$st $(act "${CXB1:-none}" publish)"
st="$st $(cxm "$CXCT" "Muara C $CXRUN")"; CXC1=$(mj "d.get('id')"); NC1=$(mj "d.get('no')")
st="$st $(cxsub "$CXET" "$TODAY" "Crew E pending $CXRUN" "$(upk "$CXET" before),$(upk "$CXET" after)")"
st="$st $(cxsub "$CXET" "$TODAY" "Crew E rejected $CXRUN" "$(upk "$CXET" before),$(upk "$CXET" after)")"; CXE2=$(cj "d.get('id')")
st="$st $(sdec "{\"id\":\"${CXE2:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}")"
st="$st $(cxm "$CXET" "Muara E $CXRUN")"; st="$st $(act "$(mj "d.get('id')")" decline)"
check "crew B's mission is published, crew C's waits in review, crew E has a pending and a rejected cleanup and a declined mission" "$st" "201 200 201 200 200 rejected 201 200"
cxpage >/dev/null
check "/crews lists crew A (its page, its totals equal the sums of its receipts in /api/events, LAST CLEANUP its newest receipt) and crew B (no cleanups yet, its mission) on top, not crew C, D or E there" \
  "$(cxq "(card('$CXAS') is not None and '<a class=\"cx-head\" href=\"/p/$CXAS\">' in card('$CXAS')['html'], (card('$CXAS') or {}).get('cleanups'), (card('$CXAS') or {}).get('kg'), (card('$CXAS') or {}).get('sacks'), (card('$CXAS') or {}).get('paid'), card('$CXBS') is not None, card('cx-c-$CXRUN'), card('cx-d-$CXRUN'), card('cx-e-$CXRUN'))")" \
  "$(curl -s $B/api/events | jget "(True, float(len([e for e in d if e['provider']['slug']=='$CXAS'])), float(sum(e['result']['kg_estimate'] or 0 for e in d if e['provider']['slug']=='$CXAS')), float(sum(e['result']['sacks'] or 0 for e in d if e['provider']['slug']=='$CXAS')), float(sum((e.get('money') or {}).get('paid_eur') or 0 for e in d if e['provider']['slug']=='$CXAS')), True, None, None, None)")"
check "crew A's card: Indonesia, 2 cleanups, 241 kg, 28 sacks, EUR 95 paid (the pending one and the one without an amount add nothing), and LAST CLEANUP links its newest receipt" \
  "$(cxq "'<small>Indonesia&nbsp;· 2&nbsp;cleanups&nbsp;· 241&nbsp;kg&nbsp;· 28&nbsp;sacks&nbsp;· €95&nbsp;paid</small>' in card('$CXAS')['html'] and '<p class=\"cx-last\"><a href=\"/r/$CXS2\"><b>LAST CLEANUP</b><span>$(ddnb "$TODAY")&nbsp;· Crew A newest $CXRUN</span></a></p>' in card('$CXAS')['html'] and 'cx-ms' not in card('$CXAS')['html']")" True
check "/crews JUST JOINED: crews C (a mission in review), D (nothing) and E (a pending and a rejected cleanup, a declined mission) are there, the newest first (E, D, C), each card its letters, its name linking its page and Indonesia · first mission coming, nothing else (no number, no website); A and B are not" \
  "$(cxq "(0 <= jat('cx-e-$CXRUN') < jat('cx-d-$CXRUN') < jat('cx-c-$CXRUN'), [jj(s)['html'] == '\n      <a class=\"cx-head\" href=\"/p/' + s + '\"><span class=\"cx-mono\" aria-hidden=\"true\">C' + s[3].upper() + '</span><span class=\"cx-name\"><b>Crew ' + s[3].upper() + ' $CXRUN</b><small>Indonesia&nbsp;· first&nbsp;mission&nbsp;coming</small></span></a>' for s in ('cx-c-$CXRUN', 'cx-d-$CXRUN', 'cx-e-$CXRUN')], jj('$CXAS'), jj('$CXBS'), 'example.org' in page)")" \
  "(True, [True, True, True], None, None, False)"
check "/crews: JUST JOINED · FIRST MISSION COMING once, under its own title in two halves, after the last card of the crews with something public and before HOW THIS LIST WORKS" \
  "$(cxq "(page.count('<h2 class=\"cx-title\"><span>JUST JOINED&nbsp;·</span> <span>FIRST MISSION COMING</span></h2>'), page.rfind('<li class=\"cx-card\" ') < page.find('<section class=\"cx-sec\">') < page.find('<li class=\"cx-card cx-new\"') < page.find('<section class=\"panel cx-how\">'))")" \
  "(1, True)"
check "/crews while /missions lists something (crew B's open mission among it): ALL MISSIONS (/missions) stands next to SEE THE GLOBE at the foot, the page's one link to /missions" \
  "$(grep -cF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a> <a class="btn" href="/missions">ALL MISSIONS</a></p>' "$T/cx.html") $(grep -o 'href="/missions[^"]*"' "$T/cx.html" | wc -l | tr -d ' ') $(mxpage >/dev/null; mxq "card($NB1) is not None")" "1 1 True"
check "crew B's card: Indonesia, no cleanups yet, no LAST CLEANUP, its open mission linking /m/<no>" \
  "$(cxq "'<small>Indonesia&nbsp;· no cleanups yet</small>' in card('$CXBS')['html'] and 'cx-last' not in card('$CXBS')['html'] and '<li><a href=\"/m/$NB1\"><i class=\"mpin-tag\">#$NB1</i><span>open&nbsp;· $(ddnb "$PLAN")&nbsp;· Muara B1 $CXRUN</span></a></li>' in card('$CXBS')['html']")" True
HOWX=$(sed -n '/<section class="panel cx-how">/,/<\/section>/p' "$T/cx.html")
[ "$(echo "$HOWX" | grep -c '^      <li>')" = 6 ] \
  && echo "$HOWX" | grep -qF "<li>A crew shows up here as soon as it works with Sapu Earth. Until it has a mission or a cleanup on sapu.earth, it is under JUST JOINED with its name, logo, country and TikTok only. A crew Sapu Earth stops working with leaves the list; its receipts stay on the globe.</li>" \
  && echo "$HOWX" | grep -qF "<li>The totals add up each crew's approved receipts. Crews count the sacks and weigh or estimate the kilograms themselves, and Sapu Earth checks the photos and numbers of every cleanup before it becomes a receipt.</li>" \
  && echo "$HOWX" | grep -qF "<li>An open mission is a spot a crew wants to clean, waiting for funding. A funded one is paid for by Sapu Earth, and the crew plans to clean it on the day shown.</li>" \
  && echo "$HOWX" | grep -qF "<li>Crews send their own logos and TikTok accounts, and Sapu Earth checks each one before it shows.</li>" \
  && echo "$HOWX" | grep -qF "<li>Thanks are one tap under a receipt. Nobody signs in and nothing marks who tapped, so one person can thank more than once: read them as applause, not votes. They are never money.</li>" \
  && echo "$HOWX" | grep -qF "<li>Newest activity first, and under JUST JOINED the crews that joined most recently first. No crew is ranked by kilograms, money or thanks.</li>" \
  && [ "$(echo "$HOWX" | grep -n 'Thanks are one tap' | cut -d: -f1)" -lt "$(echo "$HOWX" | grep -n 'Newest activity first' | cut -d: -f1)" ] \
  && ok "/crews HOW THIS LIST WORKS: six lines, each only what the code keeps (every crew we work with, under JUST JOINED until it has a mission or a cleanup, totals from approved receipts, kilograms weighed or estimated, a funded mission's day is the crew's plan, Sapu Earth checks each logo, thanks are applause and never money, newest first, JUST JOINED by when they joined, never by thanks)" \
  || bad "/crews HOW THIS LIST WORKS" "$HOWX"
PBD=$(curl -s $B/p/$CXBS); PAD=$(curl -s $B/p/$CXAS)
echo "$PBD" | grep -qF "<meta name=\"description\" content=\"Crew B $CXRUN, a local cleanup crew on sapu.earth. No published cleanups yet.\">" \
  && echo "$PBD" | grep -qF "<meta property=\"og:description\" content=\"Crew B $CXRUN, a local cleanup crew on sapu.earth. No published cleanups yet.\">" \
  && ! echo "$PBD" | grep -qF 'removed by' \
  && echo "$PAD" | grep -qF "<meta name=\"description\" content=\"2 cleanups, 241 kg removed by Crew A $CXRUN. Every receipt public on sapu.earth.\">" \
  && echo "$PAD" | grep -qF "<small>$TODAY&nbsp;· 120.5&nbsp;kg&nbsp;· crew&nbsp;of&nbsp;6</small>" \
  && ! echo "$PBD" | grep -q 'fp-stats' && echo "$PAD" | grep -qF '<div class="stats fp-stats">' \
  && ok "/p/<slug> description: a crew listed for a mission alone is a local cleanup crew with no published cleanups yet, never trash removed, and its page shows no row of zeros; a crew with receipts keeps its cleanups and kilograms and its numbers, and its receipt rows never break inside an amount or 'crew of 6'" \
  || bad "/p/<slug> description" "$(echo "$PBD" | grep -E 'name="description"|og:description') $(echo "$PAD" | grep 'name="description"')"
check "GET /api/partner listed: true for every active crew, A and B on top and C (a mission in review), D (nothing) and E (a pending and a rejected cleanup, a declined mission) under JUST JOINED" \
  "$(plisted "$CXAT") $(plisted "$CXBT") $(plisted "$CXCT") $(plisted "$CXDT") $(plisted "$CXET")" "True True True True True"

# X: a name with HTML in it and a mission on sapu.earth: escaped, with its letters. L: a mission on sapu.earth and a live logo.
CXXS="cx-x-$CXRUN"; CXLS="cx-l-$CXRUN"
CXXJ=$(newp "Crew <b>X</b> $CXRUN" ID "$CXXS"); CXXT=$(echo "$CXXJ" | jget "d['token']"); CXXI=$(echo "$CXXJ" | jget "d['id']")
CXLJ=$(newp "Logo Listed $CXRUN" ID "$CXLS"); CXLT=$(echo "$CXLJ" | jget "d['token']"); CXLI=$(echo "$CXLJ" | jget "d['id']")
st=$(cxm "$CXXT" "Muara X $CXRUN"); st="$st $(act "$(mj "d.get('id')")" publish)"
st="$st $(cxm "$CXLT" "Muara L $CXRUN")"; st="$st $(act "$(mj "d.get('id')")" publish)"
st="$st $(lpost "$CXLT" $T/logo.jpg)"; CXLK=$(lkey); st="$st $(ldec "${CXLK:-none}" approve)"
check "crews X and L have a mission on sapu.earth, and L's logo is approved" "$st" "201 200 201 200 201 200"
cxpage >/dev/null
check "/crews: the name with HTML is escaped and shows its letters (CB), and the crew with a live logo shows it (56 px, lazy)" \
  "$(cxq "('<span class=\"cx-mono\" aria-hidden=\"true\">CB</span><span class=\"cx-name\"><b>Crew &lt;b&gt;X&lt;/b&gt; $CXRUN</b>' in card('$CXXS')['html'], '<img class=\"cx-logo\" src=\"/media/$CXLK\" alt=\"\" width=\"56\" height=\"56\" loading=\"lazy\" decoding=\"async\">' in card('$CXLS')['html'], 'cx-mono' in card('$CXLS')['html'])") $(grep -c '<b>X</b>' "$T/cx.html") $(code $B/media/$CXLK)" \
  "(True, True, False) 0 200"

# P, in the Philippines, with a funded mission: crews from two countries, so the country chips show.
CXPS="cx-p-$CXRUN"
CXPJ=$(newp "Crew P $CXRUN" PH "$CXPS"); CXPT=$(echo "$CXPJ" | jget "d['token']"); CXPI=$(echo "$CXPJ" | jget "d['id']")
st=$(cxm "$CXPT" "Pantai P $CXRUN" country=PH currency=PHP price_local:=5000 crew_local:=3000); st="$st $(act "$(mj "d.get('id')")" fund '"funded_eur":35')"
check "crew P (Philippines) has a funded mission" "$st" "201 200"
cxpage >/dev/null; cp "$T/cx.html" "$T/cx-all.html"
CHIPS=$(sed -n '/<nav class="cx-chips" aria-label="Countries">/,/<\/nav>/p' "$T/cx.html")
echo "$CHIPS" | grep -qE '<a href="/crews" aria-current="page">ALL \([0-9]+\)</a>' && echo "$CHIPS" | grep -qE '<a href="/crews\?country=ID">INDONESIA \([0-9]+\)</a>' \
  && echo "$CHIPS" | grep -qE '<a href="/crews\?country=PH">PHILIPPINES \([0-9]+\)</a>' && [ "$(echo "$CHIPS" | grep -c 'aria-current')" = 1 ] \
  && [ "$(echo "$CHIPS" | grep -oE 'ALL \([0-9]+\)' | tr -cd '0-9')" = "$(cxq "len(cards) + len(new)")" ] \
  && [ "$(echo "$CHIPS" | grep -oE 'INDONESIA \([0-9]+\)' | tr -cd '0-9')" = "$(cxq "sum('<small>Indonesia&nbsp;·' in c['html'] for c in cards + new)")" ] \
  && ! grep -qF '<meta name="robots"' "$T/cx.html" \
  && ok "/crews with crews from two countries: chips ALL (n), INDONESIA (n) and PHILIPPINES (n), ALL is the current one, n the number of cards in both groups (JUST JOINED counted), and the list is indexed" \
  || bad "/crews country chips" "$CHIPS"
st=$(cxpage country=PH)
check "/crews?country=PH: only the crews in the Philippines (P, not A or B), JUST JOINED filtered too, noindex, PHILIPPINES is the current chip" \
  "$st $(cxq "(card('$CXPS') is not None, card('$CXAS'), card('$CXBS'), len(cards) > 0 and all('<small>Philippines' in c['html'] for c in cards + new) and jj('cx-d-$CXRUN') is None)") $(grep -c '<meta name="robots" content="noindex">' "$T/cx.html") $(grep -cE '<a href="/crews\?country=PH" aria-current="page">PHILIPPINES' "$T/cx.html")" \
  "200 (True, None, None, True) 1 1"
cp "$T/cx.html" "$T/cx-ph.html"; cxpage country=ph >/dev/null
cmp -s "$T/cx.html" "$T/cx-ph.html" && ok "/crews?country=ph (lower case) is the same page as ?country=PH" || bad "/crews?country=ph" "$(diff "$T/cx.html" "$T/cx-ph.html" | head -5)"
CXE=""
for v in zz %3Cscript%3E 'ID%22%3E%3Cb%3E' ''; do
  cxpage "country=$v" >/dev/null; cmp -s "$T/cx.html" "$T/cx-all.html" || CXE="$CXE [$v]"
done
[ -z "$CXE" ] && ok "/crews?country=zz, a script tag, a quote or nothing: the same page as /crews, everyone listed and nothing echoed" || bad "/crews with a country no chip offers" "$CXE"

# J, made with NEW PARTNER a moment ago, the only crew in Kenya and with a website: under JUST JOINED at once, the newest,
# with nothing but its letters, name and country; the chips count it, and ?country=KE lists it alone.
CXJS="cx-j-$CXRUN"
CXJJ=$(newp "Crew J $CXRUN" KE "$CXJS"); CXJT=$(echo "$CXJJ" | jget "d['token']"); CXJI=$(echo "$CXJJ" | jget "d['id']")
cxpage >/dev/null
check "crew J, made with NEW PARTNER a moment ago in Kenya: GET /api/partner listed true at once; /crews has it first under JUST JOINED with its letters, its name linking its page and Kenya · first mission coming, no number, and its website nowhere on the page" \
  "$(plisted "$CXJT") $(cxq "(card('$CXJS'), jat('$CXJS'), (jj('$CXJS') or {}).get('html') == '\n      <a class=\"cx-head\" href=\"/p/$CXJS\"><span class=\"cx-mono\" aria-hidden=\"true\">CJ</span><span class=\"cx-name\"><b>Crew J $CXRUN</b><small>Kenya&nbsp;· first&nbsp;mission&nbsp;coming</small></span></a>', 'example.org' in page)")" \
  "True (None, 0, True, False)"
check "the chips count crew J: KENYA (1), and ALL (n) still the number of cards in both groups" \
  "$(grep -cF '<a href="/crews?country=KE">KENYA (1)</a>' "$T/cx.html") $(cxq "page.count('>ALL (%d)</a>' % (len(cards) + len(new)))")" "1 1"
st=$(cxpage country=KE)
check "/crews?country=KE: crew J alone, under JUST JOINED with no list above it, noindex, KENYA the current chip" \
  "$st $(cxq "(len(cards), [c['slug'] for c in new], page.count('<ul class=\"cx-list\">'), page.find('<section class=\"cx-sec\">') > page.find('</nav>') > 0)") $(grep -c '<meta name="robots" content="noindex">' "$T/cx.html") $(grep -cF '<a href="/crews?country=KE" aria-current="page">KENYA (1)</a>' "$T/cx.html")" \
  "200 (0, ['$CXJS'], 1, True) 1 1"
# Its first mission, published: J moves up among the crews with something public, with its mission, and leaves JUST JOINED.
st=$(cxm "$CXJT" "Pantai J $CXRUN" country=KE currency=KES price_local:=20000 crew_local:=12000 lat:=-4.2797 lng:=39.5947); CXJ1=$(mj "d.get('id')"); NJ1=$(mj "d.get('no')")
st="$st $(act "${CXJ1:-none}" publish)"; cxpage >/dev/null
check "crew J's first mission is published: it moves up (Kenya · no cleanups yet, its mission row, before every JUST JOINED card) and is no longer under JUST JOINED; the chips still count it" \
  "$st $(cxq "(jj('$CXJS'), '<small>Kenya&nbsp;· no cleanups yet</small>' in (card('$CXJS') or {}).get('html', ''), '<li><a href=\"/m/$NJ1\">' in (card('$CXJS') or {}).get('html', ''), page.find('data-slug=\"$CXJS\"') < page.find('<section class=\"cx-sec\">') or page.find('<section class=\"cx-sec\">') < 0)") $(grep -cF '<a href="/crews?country=KE">KENYA (1)</a>' "$T/cx.html")" \
  "201 200 (None, True, True, True) 1"
# Its mission withdrawn: J's first mission came, so J stays on top as Kenya · no cleanups yet, with no mission row and
# after every card with something to show, and never goes back under JUST JOINED · FIRST MISSION COMING.
st=$(wd "$CXJT" "${CXJ1:-none}"); cxpage >/dev/null
check "crew J withdraws its only mission: it stays on top (Kenya · no cleanups yet, no mission row, after every card with something to show) and does not go back under JUST JOINED; the chips still count it" \
  "$st $(cxq "(jj('$CXJS'), (card('$CXJS') or {}).get('html', '').count('<small>Kenya&nbsp;· no cleanups yet</small>'), 'cx-ms' in (card('$CXJS') or {}).get('html', 'cx-ms'), at('$CXJS') >= 0 and all('cx-last' not in c['html'] and 'cx-ms' not in c['html'] for c in cards[at('$CXJS'):]))") $(grep -cF '<a href="/crews?country=KE">KENYA (1)</a>' "$T/cx.html")" \
  "200 (None, 1, False, True) 1"
# DEACTIVATE takes it off: neither group lists it, and the KENYA chip is gone with it.
st=$(cxoff "$CXJI"); cxpage >/dev/null
check "DEACTIVATE crew J -> 200: it is off /crews in both groups, and no chip offers Kenya any more" \
  "$st $(cxq "(card('$CXJS'), jj('$CXJS'))") $(grep -c 'country=KE' "$T/cx.html")" "200 (None, None) 0"

# O: only a receipt from 30 days ago. B's mission was published today, so B comes first: newest activity first.
CXOS="cx-o-$CXRUN"
CXOJ=$(newp "Crew O $CXRUN" ID "$CXOS"); CXOT=$(echo "$CXOJ" | jget "d['token']"); CXOI=$(echo "$CXOJ" | jget "d['id']")
st=$(cxsub "$CXOT" "$(dplus -30)" "Crew O old $CXRUN" "$(upk "$CXOT" before),$(upk "$CXOT" after)"); CXO1=$(cj "d.get('id')")
st="$st $(sdec "{\"id\":\"${CXO1:-none}\",\"action\":\"approve\",\"paid_eur\":28.5}")"
cxpage >/dev/null
check "a crew whose newest receipt is 30 days old comes after one whose mission was published today; its card says 1 cleanup and EUR 28.50" \
  "$st $(cxq "(at('$CXBS') >= 0 and at('$CXOS') > at('$CXBS'), '<small>Indonesia&nbsp;· 1&nbsp;cleanup&nbsp;· 120.5&nbsp;kg&nbsp;· 14&nbsp;sacks&nbsp;· €28.50&nbsp;paid</small>' in card('$CXOS')['html'], '$(ddnb "$(dplus -30)")&nbsp;· Crew O old $CXRUN</span></a>' in card('$CXOS')['html'])")" \
  "200 approved (True, True, True)"

# B gets a mission of every other kind: funded, one in review, one declined (removed), one done (funded, its cleanup
# approved), and two more open ones, one of them tomorrow, the soonest day of all. NEXT UP and the card show only the open
# and funded ones, funded first, then the soonest day.
PLAN1=$(dplus 1)
st=$(cxm "$CXBT" "Muara B2 $CXRUN" crew_size:=8); CXB2=$(mj "d.get('id')"); NB2=$(mj "d.get('no')"); st="$st $(act "${CXB2:-none}" fund '"funded_eur":40,"advance_pct":25')"
st="$st $(cxm "$CXBT" "Muara B3 $CXRUN")"; NB3=$(mj "d.get('no')")
st="$st $(cxm "$CXBT" "Muara B4 $CXRUN")"; CXB4=$(mj "d.get('id')"); NB4=$(mj "d.get('no')"); st="$st $(act "${CXB4:-none}" decline)"
st="$st $(cxm "$CXBT" "Muara B5 $CXRUN")"; CXB5=$(mj "d.get('id')"); NB5=$(mj "d.get('no')"); st="$st $(act "${CXB5:-none}" fund '"funded_eur":30')"
st="$st $(msub "$CXBT" "${CXB5:-none}" "$(upk "$CXBT" before),$(upk "$CXBT" after)")"; CXBS5=$(mj "d.get('id')")
st="$st $(sdec "{\"id\":\"${CXBS5:-none}\",\"action\":\"approve\",\"paid_eur\":30}")"
st="$st $(cxm "$CXBT" "Muara B6 $CXRUN")"; CXB6=$(mj "d.get('id')"); NB6=$(mj "d.get('no')"); st="$st $(act "${CXB6:-none}" publish)"
st="$st $(cxm "$CXBT" "Muara B7 $CXRUN" "plan_date=$PLAN1")"; CXB7=$(mj "d.get('id')"); NB7=$(mj "d.get('no')"); st="$st $(act "${CXB7:-none}" publish)"
check "crew B: a funded mission, one in review, one declined, one done (its cleanup approved), two more on sapu.earth" \
  "$st $(mlist done | mq "${CXB5:-none}" "m['status']")" "201 200 201 201 200 201 200 200 approved 201 200 201 200 done"
PB=$(curl -s -w '\n%{http_code}' $B/p/$CXBS)
NEXT=$(echo "$PB" | sed -n '/<h2 class="panel-title">NEXT UP<\/h2>/,/<\/section>/p')
check "/p/<slug> NEXT UP: the funded mission first, then the open ones by their day, never the one in review, declined or done" \
  "$(echo "$PB" | tail -1) $(echo "$NEXT" | grep -oE 'href="/m/[0-9]+"' | tr -cd '0-9\n' | tr '\n' ' ')$(for n in $NB3 $NB4 $NB5; do echo "$PB" | grep -c "href=\"/m/$n\""; done | tr '\n' ' ')" \
  "200 $NB2 $NB7 $NB1 $NB6 0 0 0 "
echo "$NEXT" | grep -qF "<b>#$NB2 Muara B2 $CXRUN</b>" && echo "$NEXT" | grep -qF "<small>funded&nbsp;· day&nbsp;$(ddnb "$PLAN")&nbsp;· crew&nbsp;of&nbsp;8</small>" \
  && echo "$NEXT" | grep -qF "<small>open, not funded yet&nbsp;· day&nbsp;$(ddnb "$PLAN1")&nbsp;· crew&nbsp;of&nbsp;5</small>" && [ "$(echo "$NEXT" | grep -c '<img src="/media/[0-9a-f]\{32\}" alt="" loading="lazy">')" = 4 ] \
  && echo "$PB" | grep -qF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a> <a class="btn" href="/crews">ALL CREWS</a></p>' \
  && [ "$(echo "$PB" | grep -n 'fp-stats' | head -1 | cut -d: -f1)" -lt "$(echo "$PB" | grep -n '>NEXT UP<' | cut -d: -f1)" ] \
  && [ "$(echo "$PB" | grep -n '>NEXT UP<' | cut -d: -f1)" -lt "$(echo "$PB" | grep -n '>THE RECEIPTS<' | cut -d: -f1)" ] \
  && ! echo "$PB" | grep -qi '<script' \
  && ok "/p/<slug> NEXT UP sits between the numbers and THE RECEIPTS: #12 and the place, funded or open, not funded yet, the day and the crew size, the first photo of the spot; ALL CREWS links /crews; no script" \
  || bad "/p/<slug> NEXT UP rows" "$NEXT"
check "/p/<slug> of a crew without missions on sapu.earth has no NEXT UP, and still links ALL CREWS" \
  "$(curl -s $B/p/$CXAS | grep -c '>NEXT UP<') $(curl -s $B/p/$CXAS | grep -c 'href="/crews">ALL CREWS</a>')" "0 1"
check "/p/<slug> NEXT UP ends with ALL MISSIONS ON SAPU.EARTH → (/missions), the page's one link there; a crew page without NEXT UP has none" \
  "$(echo "$NEXT" | grep -cF '<p class="cx-last p-all"><a href="/missions"><span>ALL MISSIONS ON SAPU.EARTH</span> →</a></p>') $(echo "$PB" | grep -c 'href="/missions') $(curl -s $B/p/$CXAS | grep -c 'href="/missions')" "1 1 0"
cxpage >/dev/null
check "crew B's card: 1 cleanup now, its first 3 missions (funded first, then the soonest day) and +1 more mission, which links its page" \
  "$(cxq "card('$CXBS')['html'].count('<li><a href=\"/m/'), '<i class=\"mpin-tag mpin-funded\">#$NB2</i><span>funded&nbsp;· $(ddnb "$PLAN")&nbsp;· Muara B2 $CXRUN</span>' in card('$CXBS')['html'], [int(x) for x in __import__('re').findall(r'href=\"/m/(\d+)\"', card('$CXBS')['html'])], '<li><a href=\"/p/$CXBS\"><span>+1 more mission</span></a></li>' in card('$CXBS')['html'], '<small>Indonesia&nbsp;· 1&nbsp;cleanup&nbsp;·' in card('$CXBS')['html']")" \
  "(3, True, [$NB2, $NB7, $NB1], True, True)"

# Q: four missions funded and cleaned, each cleanup sent on its own day, not in the order of the mission numbers (Q1 a
# day ago, Q2 6 days ago, Q3 today, Q4 3 days ago). So /missions has more than 6 cleaned missions (the newest 6, then SEE
# ALL n CLEANED MISSIONS) and the newest cleanup first can be told apart from the highest number first.
CXQS="cx-q-$CXRUN"
CXQJ=$(newp "Crew Q $CXRUN" ID "$CXQS"); CXQT=$(echo "$CXQJ" | jget "d['token']"); CXQI=$(echo "$CXQJ" | jget "d['id']")
# msubd <token> <mission id> <cleanup day> <media>: the cleanup of a funded mission, sent with that day (msub sends today).
msubd() { local b; b=$(body "$3" "Mission cleanup $CXRUN" "$4")
          b=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);d['mission_id']=sys.argv[2];print(json.dumps(d))" "$b" "$2")
          curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/submit?k=$1" -H 'content-type: application/json' -d "$b"; }
st=""; CXQM=(); NQ=(); CXQR=(); i=0
for d in -1 -6 0 -3; do
  st="$st $(cxm "$CXQT" "Muara Q$((i + 1)) $CXRUN")"; CXQM[$i]=$(mj "d.get('id')"); NQ[$i]=$(mj "d.get('no')")
  st="$st $(act "${CXQM[$i]:-none}" fund '"funded_eur":20')"
  st="$st $(msubd "$CXQT" "${CXQM[$i]:-none}" "$(dplus $d)" "$(upk "$CXQT" before),$(upk "$CXQT" after)")"; CXQR[$i]=$(mj "d.get('id')")
  st="$st $(sdec "{\"id\":\"${CXQR[$i]:-none}\",\"action\":\"approve\",\"paid_eur\":20}")"
  i=$((i + 1))
done
check "crew Q: four missions funded, each cleanup sent on its own day (a day ago, 6 days ago, today, 3 days ago) and approved, so each mission is done" \
  "$st $(for m in "${CXQM[@]}"; do mlist done | mq "${m:-none}" "m['status']"; done | tr '\n' ' ')" \
  " 201 200 200 approved 201 200 200 approved 201 200 200 approved 201 200 200 approved done done done done "

# The list of missions (/missions, docs/upload-flow.md, The list of missions): its open and funded missions are those of
# GET /api/missions, its cleaned ones the receipts with a mission block in GET /api/events, in the order a mission goes,
# never one in review or removed. The state chips, the filters (only for a chip's state, never echoed), the cards, BY,
# and a cleaned mission of a crew no longer active (crew 3 above: deactivated, its mission A done).
curl -s $B/api/events > "$T/mx-ev.json"; curl -s $B/api/missions > "$T/mx-api.json"
EVM=$(jget "[(e['mission']['no'], e['id']) for e in d if e.get('mission')][:200]" < "$T/mx-ev.json")
EVN=$(jget "sum(1 for e in d if e.get('mission'))" < "$T/mx-ev.json")
st=$(mxpage); cp "$T/mx.html" "$T/mx-all.html"
for s in open funded cleaned; do mxpage "status=$s" >/dev/null; cp "$T/mx.html" "$T/mx-$s.html"; done
cp "$T/mx-all.html" "$T/mx.html"
check "/missions -> 200: its cards grouped open, then funded, then cleaned, under the three section titles in that order, crew B's open, funded and cleaned missions among them" \
  "$st $(mxq "(kinds == sorted(kinds, key=['open', 'funded', 'cleaned'].index), [t for t, n in re.findall(r'<h2 class=\"mx-title\">.*?<span>(.*?)&nbsp;<small>\((\d+)\)</small></span></h2>', page)], all(card(n) is not None for n in ($NB1, $NB2, $NB5, $NB6, $NB7)))")" \
  "200 (True, ['OPEN · NOT FUNDED YET', 'FUNDED · CLEANUP COMING', 'CLEANED · WITH ITS RECEIPT'], True)"
check "/missions: the open and funded cards are exactly the missions of GET /api/missions, each in its state" \
  "$(mxq "sorted((c['no'], c['kind']) for c in cards if c['kind'] != 'cleaned')")" "$(jget "sorted((m['no'], m['status']) for m in d)" < "$T/mx-api.json")"
check "/missions, crew B: NB7 (tomorrow) before NB1 and NB6 (in 3 days), NB2 funded, NB5 cleaned; its mission in review, the declined one and crew C's in review never show" \
  "$(mxq "(0 <= at($NB7) < at($NB1) < at($NB6), card($NB2)['kind'], card($NB5)['kind'], card($NB3), card($NB4), card($NC1))")" "(True, 'funded', 'cleaned', None, None, None)"
# Per mission from /api/missions: the price, the pay for each person (crew_local / crew_size) and the other costs
# (price_local - crew_local), each as "IDR&nbsp;2,000,000".
MXL=$(jget "' '.join(m['currency'] + '&nbsp;' + '{:,.2f}'.format(v).rstrip('0').rstrip('.') for n in ($NB1, $NB2) for m in d if m['no'] == n for v in (float(m['price_local']), float(m['crew_local']) / m['crew_size'], float(m['price_local']) - float(m['crew_local'])))" < "$T/mx-api.json")
read -r NB1ASK NB1EACH NB1OTHER NB2ASK NB2EACH NB2OTHER <<< "$MXL"
check "/missions, NB1's card (open): its tag with the trash bag, the place, Indonesia, its day and crew of 5, what the crew asks in all, the crew pay as 5 × the pay for each person and the other costs in local money, linking /m/<no>; BY Crew B linking its page" \
  "$(mxq "('<a class=\"mx-head\" href=\"/m/$NB1\"><i class=\"mpin-tag\"><svg class=\"gl\"' in card($NB1)['html'], '#$NB1</i><span class=\"cx-name\"><b>Muara B1 $CXRUN</b><small>Indonesia&nbsp;· day&nbsp;$(ddnb "$PLAN")&nbsp;· crew&nbsp;of&nbsp;5</small><small class=\"mx-money\">asking&nbsp;$NB1ASK&nbsp;in&nbsp;all&nbsp;· crew&nbsp;pay&nbsp;5&nbsp;×&nbsp;$NB1EACH&nbsp;· other&nbsp;costs&nbsp;$NB1OTHER</small></span></a>' in card($NB1)['html'], '<p class=\"cx-last\"><a href=\"/p/$CXBS\"><b>BY</b><span>Crew B $CXRUN</span></a></p>' in card($NB1)['html'])")" "(True, True, True)"
check "/missions, NB2's card (funded): its tag with the broom, its day and crew of 8, funded €40, what the crew asked in all, the crew pay as 8 × the pay for each person and the other costs in local money (from /api/missions), linking /m/<no>; BY Crew B linking its page" \
  "$(mxq "('<a class=\"mx-head\" href=\"/m/$NB2\"><i class=\"mpin-tag mpin-funded\"><svg class=\"gl\"' in card($NB2)['html'], '#$NB2</i><span class=\"cx-name\"><b>Muara B2 $CXRUN</b><small>Indonesia&nbsp;· day&nbsp;$(ddnb "$PLAN")&nbsp;· crew&nbsp;of&nbsp;8</small><small class=\"mx-money\">funded&nbsp;€40&nbsp;· asked&nbsp;$NB2ASK&nbsp;in&nbsp;all&nbsp;· crew&nbsp;pay&nbsp;8&nbsp;×&nbsp;$NB2EACH&nbsp;· other&nbsp;costs&nbsp;$NB2OTHER</small></span></a>' in card($NB2)['html'], '<p class=\"cx-last\"><a href=\"/p/$CXBS\"><b>BY</b><span>Crew B $CXRUN</span></a></p>' in card($NB2)['html'])")" "(True, True, True)"
NB5F=$(jget "[' '.join(['{:,.1f}'.format(float(e['result']['kg_estimate'])).rstrip('0').rstrip('.'), str(e['result']['sacks']), str(e['crew']['size'])]) for e in d if e['id'] == '$CXBS5'][0]" < "$T/mx-ev.json")
read -r NB5KG NB5SACKS NB5CREW <<< "$NB5F"
[ "$NB5SACKS" = 1 ] && NB5S="1&nbsp;sack" || NB5S="$NB5SACKS&nbsp;sacks"
check "/missions, NB5's card (cleaned): the receipt's slip with the checked box and #<no>, the mission's place, the receipt's day, kilograms, sacks and crew (from /api/events) and €30 paid, linking its receipt /r/<id>; BY Crew B linking its page" \
  "$(mxq "('<a class=\"mx-head\" href=\"/r/$CXBS5\"><i class=\"cslip\"><svg class=\"gl\"' in card($NB5)['html'], '#$NB5<i class=\"cslip-edge\"></i></i><span class=\"cx-name\"><b>Muara B5 $CXRUN</b><small>Indonesia&nbsp;· cleaned&nbsp;$(ddnb "$TODAY")&nbsp;· $NB5KG&nbsp;kg&nbsp;· $NB5S&nbsp;· crew&nbsp;of&nbsp;$NB5CREW</small><small class=\"mx-money\">€30&nbsp;paid</small></span></a>' in card($NB5)['html'], '<p class=\"cx-last\"><a href=\"/p/$CXBS\"><b>BY</b><span>Crew B $CXRUN</span></a></p>' in card($NB5)['html'])")" "(True, True, True)"
MXC=$(python3 - "$T/mx-all.html" "$T/mx-open.html" "$T/mx-funded.html" "$EVN" <<'PY'
import re, sys
pages = [open(p, encoding="utf-8").read() for p in sys.argv[1:4]]
cards = lambda t, kind: len(re.findall(r'<li class="cx-card mx-card" id="m-\d+" data-no="\d+" data-kind="%s">' % kind, t))
nav = re.search(r'<nav class="cx-chips" aria-label="Missions by state">(.*?)</nav>', pages[0], re.S)
chips = {k: int(n) for k, n in re.findall(r'>(ALL|OPEN|FUNDED|CLEANED) \((\d+)\)</a>', nav.group(1))} if nav else {}
want = {k: v for k, v in {"OPEN": cards(pages[1], "open"), "FUNDED": cards(pages[2], "funded"), "CLEANED": int(sys.argv[4] or 0)}.items() if v}
want["ALL"] = sum(want.values())
current = re.findall(r'<a href="([^"]*)" aria-current="page">', nav.group(1)) if nav else []
print(chips == want, current == ["/missions"], '<meta name="robots"' not in pages[0])
PY
)
check "/missions chips: ALL (n) the sum of OPEN (n), FUNDED (n) and CLEANED (n), OPEN and FUNDED the cards on their own pages, CLEANED the receipts with a mission in /api/events; ALL is the current chip and the page is indexed" \
  "$MXC" "True True True"
MXS=""
for s in open funded cleaned; do
  [ "$(python3 -c "import re,sys;t=open(sys.argv[1],encoding='utf-8').read();print(sorted(set(re.findall(r'data-kind=\"(\w+)\"', t))))" "$T/mx-$s.html")" = "['$s']" ] \
    && grep -qF '<meta name="robots" content="noindex">' "$T/mx-$s.html" && grep -qF '<link rel="canonical" href="https://sapu.earth/missions">' "$T/mx-$s.html" \
    && [ "$(grep -c 'aria-current="page"' "$T/mx-$s.html")" = 1 ] && grep -qE "<a href=\"/missions\?status=$s\" aria-current=\"page\">" "$T/mx-$s.html" \
    || MXS="$MXS [$s]"
done
mxpage status=OPEN >/dev/null; cmp -s "$T/mx.html" "$T/mx-open.html" || MXS="$MXS [OPEN is not open]"
[ -z "$MXS" ] && ok "/missions?status=open, funded and cleaned: only that state, noindex, its chip the current one, the canonical still /missions; ?status=OPEN is the same page as ?status=open" \
  || bad "/missions filtered by state" "$MXS"
MXE=""
for v in status=zz status=%3Cscript%3E 'status=%22%3E%3Cb%3E' status= status=review status=removed status=done country=PH; do
  mxpage "$v" >/dev/null; cmp -s "$T/mx.html" "$T/mx-all.html" || MXE="$MXE [$v]"
done
[ -z "$MXE" ] && ok "/missions?status=zz, a script tag, a quote, nothing, review, removed or done, and ?country=PH: the same page as /missions, every state shown and nothing echoed" \
  || bad "/missions with a state no chip offers" "$MXE"
check "/missions with every state and more than 6 cleaned missions (crew Q's four among them): the newest 6 in the order of /api/events, then one SEE ALL n CLEANED MISSIONS → (?status=cleaned), n the receipts with a mission block" \
  "$(python3 -c "
import ast,re,sys
t=open(sys.argv[1],encoding='utf-8').read();n=int(sys.argv[2] or 0);evm=ast.literal_eval(sys.argv[3] or '[]')
shown=[int(x) for x in re.findall(r'<li class=\"cx-card mx-card\" id=\"m-(\d+)\" data-no=\"\d+\" data-kind=\"cleaned\">',t)]
more=re.findall(r'<p class=\"mx-more\"><a href=\"/missions\?status=cleaned\">SEE ALL (\d+) CLEANED MISSIONS →</a></p>',t)
print(n > 6, shown == [no for no, _ in evm][:6], more == [str(n)])" "$T/mx-all.html" "$EVN" "$EVM")" "True True True"
cp "$T/mx-cleaned.html" "$T/mx.html"
check "/missions?status=cleaned: the receipts with a mission block in /api/events, in its order, each card linking its receipt /r/<id>" \
  "$(mxq "[(c['no'], re.search(r'<a class=\"mx-head\" href=\"/r/([a-z2-7]{10})\">', c['html']).group(1)) for c in cards]")" "$EVM"
check "/missions?status=cleaned: the newest cleanup first, not the highest number (crew Q: Q3 today, Q1 a day ago, Q4 3 days ago, Q2 6 days ago), every cleaned mission on the page without SEE ALL or the cap line, Q2 with its own day and €20 paid" \
  "$(mxq "(0 <= at(${NQ[2]:-0}) < at(${NQ[0]:-0}) < at(${NQ[3]:-0}) < at(${NQ[1]:-0}), len(cards) == ${EVN:-0}, 'mx-more' in page, 'mx-cap' in page, 'cleaned&nbsp;$(ddnb "$(dplus -6)")&nbsp;·' in (card(${NQ[1]:-0}) or {}).get('html', ''), '<small class=\"mx-money\">€20&nbsp;paid</small>' in (card(${NQ[1]:-0}) or {}).get('html', ''))")" \
  "(True, True, False, False, True, True)"
check "/missions?status=cleaned keeps the cleaned mission of a crew Sapu Earth no longer works with (crew 3): its receipt, and BY with the name alone, no link to its page" \
  "$(mxq "('<a class=\"mx-head\" href=\"/r/$SP\">' in card($NOA)['html'], '<p class=\"cx-last mx-by\"><b>BY</b><span>Link Mission Crew $MRUN</span></p>' in card($NOA)['html'], '/p/mission-link-$MRUN' in page)")" "(True, True, False)"
MXHOW=$(sed -n '/<section class="panel cx-how">/,/<\/section>/p' "$T/mx-all.html")
[ "$(echo "$MXHOW" | grep -c '^      <li>')" = 6 ] \
  && echo "$MXHOW" | grep -qF "<li>A mission is a spot a local crew wants to clean, with the day and the price the crew asks in its own money. The crew's pay is part of that price, and the rest is for other costs. It shows here once Sapu Earth publishes or funds it.</li>" \
  && echo "$MXHOW" | grep -qF "<li>Open: not funded yet. An open mission nobody funds leaves this list 28 days after it was published.</li>" \
  && echo "$MXHOW" | grep -qF "<li>Funded: Sapu Earth pays for it, and the crew plans to clean it on the day shown.</li>" \
  && echo "$MXHOW" | grep -qF "<li>Cleaned: the crew sent the cleanup, and Sapu Earth checked its photos and numbers before it became a receipt. Crews count the sacks and weigh or estimate the kilograms themselves.</li>" \
  && echo "$MXHOW" | grep -qF "<li>A mission that is withdrawn, declined or cancelled never shows here. When Sapu Earth stops working with a crew, its open and funded missions leave the list, and its cleaned ones stay, like its receipts.</li>" \
  && echo "$MXHOW" | grep -qF "<li>Open and funded missions show the soonest day first and a day that has passed last, cleaned ones the newest cleanup first. Nothing is ranked by money or kilograms.</li>" \
  && ok "/missions HOW THIS LIST WORKS: six lines, each only what the code keeps (when a mission shows and that the crew's pay is inside its price, the 28 days of an open one, a funded mission's day is the crew's plan, a cleaned one was checked, removed ones never show and DEACTIVATE leaves the cleaned ones, the order)" \
  || bad "/missions HOW THIS LIST WORKS" "$MXHOW"
check "/missions: a crew name with HTML is escaped in BY and the raw tag never shows; no picture (no <img, no /media/); ALL CREWS at the foot while crews behind its missions are listed" \
  "$(grep -cF "<b>BY</b><span>Crew &lt;b&gt;X&lt;/b&gt; $CXRUN</span>" "$T/mx-all.html") $(cat "$T/mx-all.html" "$T/mx-cleaned.html" | grep -cE '<b>X</b>|<img|/media/') $(grep -cF '<p class="fp-foot"><a class="btn" href="/">SEE THE GLOBE</a> <a class="btn" href="/crews">ALL CREWS</a></p>' "$T/mx-all.html")" "1 0 1"
if [ -n "$STATE" ]; then
  # The 28 days of an open mission (PUBLIC_MISSION): one published 29 days ago is off the list even before the expiry
  # removed it, one published 27 days ago is on it. Two open missions whose day has passed (5 days ago, then 2 days ago,
  # so the older day has the lower number) come last among the open ones, the more recent day first, as in NEXT UP.
  # Written straight into the local D1 for crew B, then removed again.
  XM29=$(newid); XM27=$(newid); XMP5=$(newid); XMP2=$(newid)
  if d1 "$(mrow "$CXBI" $XM29 open $(dplus 5) $(ago 30) $(ago 29)) $(mrow "$CXBI" $XM27 open $(dplus 5) $(ago 28) $(ago 27)) $(mrow "$CXBI" $XMP5 open $(dplus -5) $(ago 9) $(ago 8)) $(mrow "$CXBI" $XMP2 open $(dplus -2) $(ago 9) $(ago 8))" >/dev/null; then
    read -r NO29 NO27 NOP5 NOP2 <<< "$(d1 "SELECT id, no FROM missions WHERE id IN ('$XM29', '$XM27', '$XMP5', '$XMP2')" | jget "' '.join(str({r['id']: r['no'] for r in d[0]['results']}[k]) for k in ('$XM29', '$XM27', '$XMP5', '$XMP2'))")"
    mxpage >/dev/null
    check "/missions and the 28 days: an open mission published 29 days ago is not listed (still open, the expiry has not removed it), one published 27 days ago is" \
      "$(mxq "(card(${NO29:-0}), (card(${NO27:-0}) or {}).get('kind'))") $(d1 "SELECT status FROM missions WHERE id = '$XM29'" | jget "d[0]['results'][0]['status']")" "(None, 'open') open"
    check "/missions: the open missions whose day has passed come last, the more recent day first (2 days ago, then 5)" \
      "$(mxq "[c['no'] for c in cards if c['kind'] == 'open'][-2:]")" "[${NOP2:-0}, ${NOP5:-0}]"
    d1 "UPDATE missions SET status = 'removed', removed_why = 'expired', closed_at = '$(ago 0)', private_note = NULL, lat = NULL, lng = NULL WHERE id IN ('$XM29', '$XM27', '$XMP5', '$XMP2')" >/dev/null
  else
    bad "write two old open missions into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# Nothing private ever shows: the application's contact details, area and about, private notes, review notes, advances,
# mission and partner ids, token hashes.
LEAK=""
for p in /crews /p/$CXAS /p/$CXBS "/crews?country=PH" /missions "/missions?status=cleaned"; do
  pg=$(curl -s "$B$p")
  for m in "Cx Contact $CXRUN" "$CXWAD" "cx-$CXRUN@example.org" "CX-ABOUT-$CXRUN" "CX-AREA-$CXRUN" PRIVATE-NOTE-123 REVIEW-NOTE-456 MISSION-PRIVATE-789 \
           "$CXAI" "$CXBI" "$CXPI" "$CXLI" "$CXQI" token_hash $CXB1 $CXB2 $CXB4 $CXB5 $CXB6 $CXB7 $CXC1 "${CXQM[@]}"; do
    echo "$pg" | grep -qF "$m" && LEAK="$LEAK [$p: $m]"
  done
  echo "$pg" | grep -qi 'advance' && LEAK="$LEAK [$p: advance]"
done
[ -z "$LEAK" ] && ok "/crews, /missions and /p/<slug> never show contact details, the application's area or about, private or review notes, advances, mission or partner ids or token hashes" \
  || bad "/crews, /missions and /p/<slug> leak" "$LEAK"

# HEAD (link checkers and some link previews ask it first): every page Function answers it with the status and headers
# of GET and no body (headOf in functions/_lib/util.js), a page that is not there too, never the site's 404 page.
# hl <method> <path>: the status and the headers that matter, sorted.
hl() { curl -s -o /dev/null -D - ${1:+$1} "$B$2" | tr -d '\r' | grep -iE '^(HTTP/|content-type:|cache-control:|content-security-policy:|x-frame-options:|x-content-type-options:)' \
         | sed -E 's#^HTTP/[0-9.]+ ([0-9]+).*#\1#' | sort | tr '\n' '|'; }
HX=""
for x in "/crews 200" "/crews/ 200" "/missions 200" "/missions/ 200" "/missions?status=cleaned 200" "/p/$CXBS 200" "/m/$NB1 200" "/m/$NB5 200" \
         "/r/$CXBS5 200" "/p/no-such-crew-$CXRUN 404" "/m/999999 404" "/r/aaaaaaaaaa 404"; do
  p=${x% *}; g=$(hl "" "$p"); h=$(hl -I "$p")
  [ "${g%%|*}" = "${x##* }" ] && [ "$g" = "$h" ] || HX="$HX [$p: GET $g HEAD $h]"
done
# Security headers of the pages a Function builds (_headers does not reach them): no framing, the origin only as
# referrer, nosniff and a script policy. /r/<id> and /m/<no> allow only their one redirect line, by its SHA-256, and
# /admin/ (static) adds its strict policy to the site's.
SH=""
for p in "/r/$CXBS5" "/m/$NB1" "/m/999999" "/p/$CXBS"; do
  h=$(curl -s -o /dev/null -D - "$B$p" | tr -d '\r')
  echo "$h" | grep -qi '^x-frame-options: DENY$' && echo "$h" | grep -qi '^referrer-policy: strict-origin-when-cross-origin$' \
    && echo "$h" | grep -qi '^x-content-type-options: nosniff$' && echo "$h" | grep -i '^content-security-policy:' | grep -qF "frame-ancestors 'none'" \
    && echo "$h" | grep -i '^content-security-policy:' | grep -qE "script-src|default-src 'none'" || SH="$SH [$p]"
done
AH=$(curl -s -o /dev/null -D - "$B/admin/" | tr -d '\r' | grep -i '^content-security-policy:')
echo "$AH" | grep -qF "script-src 'self'; object-src 'none'" && echo "$AH" | grep -qF "default-src 'none'; script-src 'self'; connect-src 'self'" || SH="$SH [/admin/: $AH]"
SHS=$(python3 - "$B" "$CXBS5" "$NB1" <<'PY'
import base64, hashlib, re, sys, urllib.request
bad = []
for p in ("/r/" + sys.argv[2], "/m/" + sys.argv[3]):
    with urllib.request.urlopen(sys.argv[1] + p) as r:
        html = r.read().decode(); csp = r.headers.get("content-security-policy", "")
    s = re.findall(r"<script>(.*?)</script>", html, re.S)
    want = "'sha256-" + base64.b64encode(hashlib.sha256(s[0].encode()).digest()).decode() + "'" if len(s) == 1 else "none"
    if f"script-src {want};" not in csp: bad.append(p)
print("ok" if not bad else "wrong: " + " ".join(bad))
PY
)
[ -z "$SH" ] && [ "$SHS" = ok ] && ok "/r, /m (and its 404) and /p send no-framing, referrer and script policies, /r and /m allow only their redirect line (by its SHA-256), /admin/ adds its strict policy" \
  || bad "Function page and admin headers" "$SH $SHS"
HB=$(python3 - "$B" <<'PY'
import socket, sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
out = []
for path in ("/crews", "/missions"):
    s = socket.create_connection((u.hostname, u.port or 80), timeout=5)
    s.sendall(f"HEAD {path} HTTP/1.1\r\nHost: {u.netloc}\r\nConnection: close\r\n\r\n".encode())
    data = b""
    try:
        while chunk := s.recv(65536):
            data += chunk
    except socket.timeout:
        pass
    head, _, body = data.partition(b"\r\n\r\n")
    out.append(f"{path} {head.split(b' ')[1].decode() if head else '-'} {len(body)}")
print(", ".join(out))
PY
)
[ -z "$HX" ] && [ "$HB" = "/crews 200 0, /missions 200 0" ] \
  && ok "HEAD on /crews, /missions (filtered too), /p/<slug>, /m/<no> and /r/<id>: the status and headers of GET (200, or 404 for a page that is not there), and no body" \
  || bad "HEAD on the page Functions" "$HX $HB"

# The way in: the homepage footer and crew box, and the crew page's YOUR PUBLIC PAGE.
HPX=$(curl -s $B/)
HCB=$(echo "$HPX" | sed -n '/<div class="crew-cta">/,/<\/div>/p')
L1=$(echo "$HCB" | grep -nF 'APPLY AS A CREW →</a>' | cut -d: -f1); L2=$(echo "$HCB" | grep -nF 'crew-list' | cut -d: -f1); L3=$(echo "$HCB" | grep -nF 'already a crew with us' | cut -d: -f1)
echo "$HPX" | grep -qF '<p class="foot-apply"><a href="/crews">THE CREWS</a><span id="footMissions" hidden> · <a href="/missions">THE MISSIONS</a></span> · <a href="/stories/">STORIES</a> · <a href="/apply/">APPLY AS A CREW</a> · <a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a></p>' \
  && [ -n "$L1" ] && [ -n "$L2" ] && [ -n "$L3" ] && [ "$((L1 + 1))" = "$L2" ] && [ "$((L2 + 1))" = "$L3" ] \
  && echo "$HCB" | grep -qF '<p class="crew-back crew-list">// crews we work with show up at <a href="/crews">sapu.earth/crews</a>, with their missions and receipts.</p>' \
  && ok "the homepage links /crews: THE CREWS first in the footer's link line (THE MISSIONS after it, hidden until /missions lists something), and the crew box line after APPLY AS A CREW and before the line for crews already with us" \
  || bad "homepage links to /crews" "$HCB"
# The code is public on GitHub: the footer's first line links it, after 100% TRANSPARENT (no-break spaces inside both).
echo "$HPX" | grep -qF '<p>SAPU = BROOM (INDONESIAN) · 100%&nbsp;TRANSPARENT · <a href="https://github.com/marcus-pousette/sapu-earth" rel="noopener">OPEN&nbsp;SOURCE</a></p>' \
  && ok "the homepage footer links the public code: OPEN SOURCE after 100% TRANSPARENT, to github.com/marcus-pousette/sapu-earth" \
  || bad "homepage footer: the OPEN SOURCE link" "$(echo "$HPX" | grep -F 'TRANSPARENT')"
# The ways on (site/app.js, the ways on; docs/upload-flow.md, Homepage): SEE THE RECEIPTS and SEE THE CREWS stand in one
# row (.cues) in the homepage's markup, the last of the first screen's bottom boxes, so the pair shows from the start in
# every state, next to the samples too, without JavaScript and when the data failed to load (Marcus decided on
# 2026-11-11). site/app.js names none of the pair's classes, so it neither builds nor hides it, and in site/styles.css
# only the satellite map's rules hide it. NEXT UP's head has ALL MISSIONS, hidden until its cards are real; a
# real mission post and a cleaned mission's receipt post end with their line to /missions. COPY LINK in a receipt post has
# its own class: the first .post-link of a post with a point is SEE THE SPOT ON SATELLITE, so its handler used to land there.
WJS=$(curl -s $B/site/app.js); WCS=$(curl -s $B/site/styles.css)
printf '%s' "$HPX" > "$T/home.html"; printf '%s' "$WJS" > "$T/home.js"; printf '%s' "$WCS" > "$T/home.css"
WAYP=$(python3 - "$T/home.html" "$T/home.js" "$T/home.css" <<'PY'
import re, sys
html, js, css = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
bad = []
pair = """    <div class="cues">
      <a class="scroll-cue" href="#main">SEE THE <span class="cue-2">RECEIPTS&nbsp;↓</span></a>
      <a class="scroll-cue cue-crews" id="crewsCue" href="/crews">SEE THE <span class="cue-2">CREWS&nbsp;→</span></a>
    </div>
  </div>
"""
st, pr, zc = html.find('<div class="stats" id="stats" hidden>'), html.find(pair), html.find('<div class="zoomctl">')
if html.count(pair) != 1 or html.count('class="scroll-cue') != 2 or html.count('class="cues"') != 1 or not (0 <= st < pr < zc):
    bad.append("first screen markup")
# site/app.js names none of the pair's classes and ids (nor the old rule's names) outside its comments, in any selector
# or string, so it neither builds nor hides the pair again
code = re.sub(r"(?m)^\s*//.*$", "", re.sub(r"(?ms)^\s*/\*.*?\*/", "", js))
if re.search(r"(?<![\w-])(cues|scroll-cue|cue-crews|crewsCue|cue-2|sampleShown|crewListed)(?![\w-])", code):
    bad.append("site/app.js still touches the first screen's pair")
head = """    <div class="sec-head">
      <h2><mark>NEXT UP</mark></h2>
      <a class="all-link" id="nextupAll" href="/missions" hidden>ALL MISSIONS →</a>
    </div>"""
if html.count(head) != 1 or html.count("<h2><mark>NEXT UP</mark></h2>") != 1:
    bad.append("NEXT UP head")
ways = """  const realMission = missions.some((m) => !m.demo);
  $("#nextupAll").hidden = !realMission;
  $("#footMissions").hidden = !(realMission || events.some((e) => e.fromApi && missionOf(e)));
"""
n, w, g = js.find('  $("#nextup").hidden = !missions.length;\n'), js.find(ways), js.find('  const el = $("#globe");')
if js.count(ways) != 1 or not (0 <= n < w < g):
    bad.append("the ways on block, after NEXT UP and before the globe")
if '<button class="post-link post-copy">COPY LINK</button>' not in js or 'overlay.querySelector(".post-copy").addEventListener("click", (ev) => {' not in js \
        or 'overlay.querySelector(".post-link")' in js:
    bad.append("COPY LINK handler")
posts = ["""<div class="post-actions"><button class="post-link post-copy">COPY LINK</button>${navigator.share ? '<button class="post-link post-share">SHARE</button>' : ""}</div>
        ${mis && e.fromApi ? `<p class="post-all"><a href="/missions?status=cleaned#m-${mis.no}">ALL CLEANED MISSIONS →</a></p>` : ""}""",
         """<div class="post-actions"><button class="post-link post-share">SHARE</button>${navigator.share ? '<button class="post-link post-copy">COPY LINK</button>' : ""}</div>
        <p class="post-all"><a href="/missions#m-${m.no}">ALL MISSIONS →</a></p>`;"""]
for i, s in enumerate(posts):
    if js.count(s) != 1:
        bad.append(("receipt", "mission")[i] + " post line")
for s in [".cues { display: flex; justify-content: center; align-items: stretch; gap: 14px; max-width: 100%; }",
          ".cues .scroll-cue:focus-visible { outline: 3px solid var(--ink); outline-offset: 3px; }",
          ".cue-crews { color: var(--ink); background: var(--paper); transform: rotate(1deg); }",
          "@media (max-width: 479px) {\n  .cues .scroll-cue { line-height: 1.15; padding: 9px 16px 8px; }\n  .cues .cue-2 { display: block; }\n}",
          "@media (max-width: 479px) and (max-height: 600px) {\n  .hero-bottom { gap: 8px; }\n}",
          "footer .foot-apply:has(#footMissions:not([hidden])) a { white-space: nowrap; }", ".all-link[hidden] { display: none; }"]:
    if s not in css:
        bad.append(s)
# only the satellite map's rules hide the pair (it steps aside there with the other boxes): no other rule naming it
# takes it away, so it shows in every other state
hides = sorted(" ".join(s.split()) + " { " + " ".join(b.split()) + " }" for s, b in re.findall(r"([^{}]+)\{([^{}]*)\}", re.sub(r"(?s)/\*.*?\*/", "", css))
               if re.search(r"(?<![\w-])(\.cues|\.scroll-cue|\.cue-crews|\.cue-2|#crewsCue)(?![\w-])", s)
               and re.search(r"display\s*:\s*none|visibility\s*:\s*hidden|opacity\s*:\s*0(\.0+)?\s*(;|!|$)", b))
map_only = [".hero.map-gone .cues { display: none; }", ".hero.map-gone :is(.tap-hint, .legend, .stats, .scroll-cue) { display: none; }",
            ".hero.map-on :is(.crew-link, .tag-demo, .pitch, .tap-hint, .legend, .stats, .scroll-cue) { opacity: 0; pointer-events: none; }"]
if hides != map_only:
    bad.append("styles.css: " + " | ".join(["hides the pair: " + h for h in hides if h not in map_only] + ["missing: " + h for h in map_only if h not in hides]))
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY
)
[ "$WAYP" = ok ] && ok "the ways on: SEE THE RECEIPTS and SEE THE CREWS in one row (.cues) in the homepage's markup, last of the first screen's bottom boxes, so the pair shows in every state, the samples too, also without JavaScript (site/app.js names none of its classes, so it neither builds nor hides it, and in styles.css only the satellite map's rules hide it); on a phone each on two lines, the boxes 8 px apart on a phone 600 px tall or less (at 320x568 the tap hint keeps clear of the - button); NEXT UP's head has ALL MISSIONS (hidden); a real mission post ends with ALL MISSIONS and a cleaned mission's receipt post with ALL CLEANED MISSIONS; COPY LINK in a receipt post has its own handler (.post-copy)" \
  || bad "the ways on (markup, site/app.js, styles.css)" "$WAYP"
# The rule in node: the block of site/app.js runs with a small fake page for each kind of data the homepage can have. It
# only sets ALL MISSIONS and THE MISSIONS (any other element, the first screen's pair included, throws): ALL MISSIONS only
# with real missions; THE MISSIONS also for a receipt that closed a mission, a crew no longer active included (/missions
# keeps cleaned missions). SEE THE CREWS is in the markup, so it stays in every state.
WAYS=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  const realMission = "), f = s.indexOf("  $(\"#footMissions\").hidden = ", a);
if (a < 0 || f < 0) throw new Error("the ways on block is missing");
const block = [line(/^  const isNo = .*$/m), line(/^  const missionOf = .*$/m), s.slice(a, s.indexOf("\n", f))].join("\n");
const run = (events, missions) => {
  const page = { "#nextupAll": { hidden: true }, "#footMissions": { hidden: true } };
  const $ = (q) => { if (!page[q]) throw new Error("touches " + q); return page[q]; };
  const doc = new Proxy({}, { get: (_, k) => { throw new Error("touches document." + String(k)); } });
  new Function("$", "document", "events", "missions", block)($, doc, events, missions);
  return "all " + (page["#nextupAll"].hidden ? "hidden" : "shown") + " / foot " + (page["#footMissions"].hidden ? "hidden" : "shown");
};
const sampleR = { id: "canggu-demo", demo: true }, sampleM = { no: 901, status: "open", demo: true }, sampleRM = { id: "mandaue-demo", demo: true, mission: { no: 902 } };
const active = { id: "a1b2c3d4e5", fromApi: true, provider: { name: "Crew", slug: "crew", page: "https://sapu.earth/p/crew" } };
const activeM = { ...active, id: "k1l2m3n4o5", mission: { no: 4 } };
const gone = { id: "f6g7h8i9j0", fromApi: true, provider: { name: "Old", slug: "old", page: null }, mission: { no: 3 } };
const own = { id: "2026-12-01-own-crew" }, mis = { no: 12, status: "funded", partner: { name: "Crew", slug: "crew" } };
const want = [
  ["samples only (today), one sample receipt with a mission block", [sampleR, sampleRM], [sampleM], "all hidden / foot hidden"],
  ["a real mission while sample receipts show", [sampleR], [mis], "all shown / foot shown"],
  ["a receipt of an active crew", [active], [], "all hidden / foot hidden"],
  ["a receipt of an active crew that closed a mission", [activeM], [], "all hidden / foot shown"],
  ["only a receipt of a crew no longer active, which closed a mission", [gone], [], "all hidden / foot shown"],
  ["no receipts (the API failed) and a real mission", [], [mis], "all shown / foot shown"],
  ["a receipt of our own crew (data/events) and no mission", [own], [], "all hidden / foot hidden"],
];
const bad = [];
for (const [n, ev, ms, w] of want) {
  let got;
  try { got = run(ev, ms); } catch (e) { got = e.message; }
  if (got !== w) bad.push(n + ": " + got + " (want " + w + ")");
}
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + want.length);
' "$T/home.js" 2>&1)
check "the ways on in node: only ALL MISSIONS and THE MISSIONS change, never the first screen's pair; samples only, a real mission next to sample receipts, a receipt of an active crew, one that closed a mission, only a crew no longer active, no receipts with a real mission, our own crew's receipt" "$WAYS" "ok 7"
# The nine fixes of 2026-11-16 (Marcus said 'Yes, build all 9'). The first screen: no sample receipts any more
# (data/events/index.json lists none, the files stay for a local look), so SAMPLE DATA stays hidden by itself; the stats
# row is hidden in the markup and shows once a receipt counts (or ? when the load failed), with "cleanup" for one, and
# the tap hint stands on a strip of paper, so the globe's outline never runs through its words (2026-11-17); the
# line that says what Sapu Earth does is the page's h1, in SAMPLE DATA's corner, which SAMPLE DATA takes back if samples
# ever show; SEE THE RECEIPTS goes to the top of <main>, so it no longer skips NEXT UP.
curl -s $B/data/events/index.json > "$T/evidx.json"
NINE=$(python3 - "$T/home.html" "$T/home.js" "$T/home.css" "$T/evidx.json" <<'PY2'
import json, re, sys, glob
html, js, css, idx = (open(p, encoding="utf-8").read() for p in sys.argv[1:5])
bad = []
if json.loads(idx) != [] or len(glob.glob("data/events/*-demo.json")) != 3:
    bad.append("data/events/index.json still lists samples, or the sample files are gone")
def opener(text, tag, cls, eid=None, extra=()):  # how many <tag ...> openers have these classes (in any order) and id
    n = 0
    for mm in re.finditer(r"<%s\b([^>]*)>" % tag, text):
        a = {k: v1 or v2 or v3 for k, v1, v2, v3 in re.findall(r"""([\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?""", mm.group(1))}
        if set(a.get("class", "").split()) == set(cls.split()) and (eid is None or a.get("id") == eid) and all(x in a for x in extra):
            n += 1
    return n
if opener(html, "div", "stats", "stats", ("hidden",)) != 1:
    bad.append("the stats row is not hidden in the markup")
# styles.css as rules, each with the @media around it, so a rule counts wherever it stands: the hint stands on its paper
# (.tap-hint, the one rule outside a @media), no rule that reaches it (it, .hero-bottom or a child of that) lets it take
# taps, gives it other paper or a display its hidden attribute could not undo, and the hidden stats row only goes away
# A rule's declarations count wherever they stand in it, before or after a rule nested in it, and those straight inside
# a group rule (@media...) nested in a style rule are that style rule's under that group rule. Property names in any case.
def rules(text):
    out, stack, buf = [], [], ""  # stack: [prelude, its declarations so far]
    def emit(sel, decl, outer):
        d = {k.strip().lower(): v.strip() for k, v in (x.split(":", 1) for x in decl.split(";") if ":" in x)}
        if not d:
            return
        if not sel.startswith("@"):
            out.append((tuple(outer), sel, d))
            return
        js_ = [i for i, x in enumerate(outer) if not x.startswith("@")]
        if js_:
            j = js_[-1]
            out.append((tuple(outer[:j] + outer[j + 1:] + [sel]), outer[j], d))
    for ch in re.sub(r"(?s)/\*.*?\*/", "", text):
        if ch == "{":
            pre, _, sel = buf.rpartition(";")
            if stack:
                stack[-1][1] += pre + ";"
            stack.append([" ".join(sel.split()), ""]); buf = ""
        elif ch == "}":
            if stack:
                stack[-1][1] += buf
                sel, decl = stack.pop()
                emit(sel, decl, [x[0] for x in stack])
            buf = ""
        elif ch == ";" and buf.strip().startswith("@"):  # a statement at-rule (@import, @layer a, b;) ends here
            buf = ""
        else:
            buf += ch
    return out
def parts(sel):  # a selector list cut at its own commas, not at those inside :is()
    out, depth, cur = [], 0, ""
    for ch in sel:
        depth += (ch == "(") - (ch == ")")
        if ch == "," and not depth:
            out.append(cur.strip()); cur = ""
        else:
            cur += ch
    return out + [cur.strip()]
R = rules(css)
base = [d for m, s, d in R if not m and s == ".tap-hint"]
if len(base) != 1 or any(base[0].get(k) != v for k, v in {"background": "var(--paper)", "padding": "3px 7px 2px 9px", "text-wrap": "balance"}.items()):
    bad.append("the tap hint does not stand on its strip of paper (.tap-hint)")
# A rule counts by the elements it reaches, not by the names it spells: a small selector matcher over an element and its
# ancestors as index.html has them, with the hero as on the globe (no .map-on, no .map-gone) and SAMPLE DATA shown, or as
# on the satellite map. A state (:hover, :focus...), :has(), a place among siblings, an attribute's value it does not
# know and a sibling (~ +) may match or not, so a selector may reach an element (must=False) or surely does (must=True);
# a pseudo-element is not the element. possible() then reads what an element gets in the end by the cascade
# (!important, specificity, order), where a rule that may or may not apply (a state, a @media, a nesting) adds what it
# would give; a printed page, a keyframe and a @media for no screen count not.
def comps(sel):  # [(the combinator before it, compound)], the subject last
    out, cur, comb, depth, i = [], "", None, 0, 0
    sel = sel.strip()
    while i < len(sel):
        ch = sel[i]
        depth += (ch in "([") - (ch in ")]")
        if not depth and ch in " >~+":
            j = i
            while j < len(sel) and sel[j] in " >~+":
                j += 1
            if cur:
                out.append((comb, cur)); cur = ""
            comb, i = sel[i:j].strip() or " ", j
            continue
        cur += ch; i += 1
    return out + ([(comb, cur)] if cur else [])
def simples(comp):
    out, i = [], 0
    m0 = re.match(r"\*|[a-zA-Z][\w-]*", comp)
    if m0:
        out.append(m0.group()); i = m0.end()
    while i < len(comp):
        if comp[i] == "&":  # the rule around it (nesting): flat() writes it out; it adds that rule's specificity
            out.append("&"); i += 1
        elif comp[i] in ".#":
            m0 = re.match(r"[.#][\w-]+", comp[i:]); out.append(m0.group()); i += m0.end()
        elif comp[i] == "[":
            j = comp.index("]", i); out.append(comp[i:j + 1]); i = j + 1
        elif comp[i] == ":":
            m0 = re.match(r"::?[\w-]+", comp[i:])
            if not m0:
                raise ValueError("a selector this check cannot read: " + comp)
            name = m0.group(); i += m0.end()
            if i < len(comp) and comp[i] == "(":
                depth, j = 0, i
                while True:
                    depth += (comp[j] == "(") - (comp[j] == ")")
                    if not depth:
                        break
                    j += 1
                name += comp[i:j + 1]; i = j + 1
            out.append(name)
        else:
            raise ValueError("a selector this check cannot read: " + comp)
    return out
def fits(comp, el, must=False):
    tag, cls, eid, attrs = el
    for q in simples(comp):
        if q.startswith("::") or q in (":before", ":after", ":first-line", ":first-letter"):
            return False
        if q in ("*", "&"):
            continue
        if q[0] == ":" and not q.startswith((":not(", ":is(", ":where(", ":root")):  # a state, :has() or a place among siblings
            if must:
                return False
            continue
        if q == ":root":
            ok_ = tag == "html"
        elif q.startswith(":not("):
            xs = parts(q[5:-1])
            ok_ = not (must and any(len(comps(x)) > 1 for x in xs)) and not any(len(comps(x)) == 1 and fits(x, el, not must) for x in xs)
        elif q.startswith((":is(", ":where(")):
            ok_ = any(fits(x, el, must) if len(comps(x)) == 1 else not must for x in parts(q[q.index("(") + 1:-1]))
        elif q[0] == ".":
            ok_ = q[1:] in cls
        elif q[0] == "#":
            ok_ = q[1:] == eid
        elif q[0] == "[":
            name, op, val = re.match(r"""\[\s*([\w-]+)\s*(?:([~|^$*]?=)\s*["']?(.*?)["']?(?:\s+[iIsS])?\s*)?\]$""", q).groups()
            if name not in attrs:
                ok_ = False
            elif op is None:
                ok_ = True
            elif name == "class" and op == "~=":
                ok_ = val in cls
            elif name == "id" and op == "=":
                ok_ = val == eid
            elif name == "class" and op == "=" and set(val.split()) != set(cls):
                ok_ = False
            else:  # a value this check does not know
                ok_ = not must
        else:
            ok_ = q.lower() == tag
        if not ok_:
            return False
    return True
def reach(sel, chain, must=False):
    cs = comps(sel)
    def at(ci, ei):
        comb, comp = cs[ci]
        if not fits(comp, chain[ei], must):
            return False
        if ci == 0:
            return True
        if comb == ">":
            return ei > 0 and at(ci - 1, ei - 1)
        if comb == " ":
            return any(at(ci - 1, k) for k in range(ei))
        return not must  # a sibling (~ +) may be there
    return bool(cs) and at(len(cs) - 1, len(chain) - 1)
def spec(sel):  # (ids, classes and the like, tags)
    n = (0, 0, 0)
    for _, comp in comps(sel):
        for q in simples(comp):
            if q.startswith("::") or q in (":before", ":after", ":first-line", ":first-letter"):
                n = (n[0], n[1], n[2] + 1)
            elif q in ("*", "&") or q.startswith(":where("):
                pass
            elif q.startswith((":is(", ":not(", ":has(")):
                x = max(spec(y) for y in parts(q[q.index("(") + 1:-1]))
                n = (n[0] + x[0], n[1] + x[1], n[2] + x[2])
            elif q[0] == "#":
                n = (n[0] + 1, n[1], n[2])
            elif re.match(r":nth-(last-)?child\(", q) and re.search(r"\sof\s", q):  # :nth-child(An+B of S): one, plus S
                x = max(spec(y) for y in parts(re.split(r"\sof\s", q[q.index("(") + 1:-1], 1)[1]))
                n = (n[0] + x[0], n[1] + 1 + x[1], n[2] + x[2])
            elif q[0] in ".[:":
                n = (n[0], n[1] + 1, n[2])
            else:
                n = (n[0], n[1], n[2] + 1)
    return n
def on_screen(m):  # may a rule inside these at-rules apply on a screen?
    for at in m:
        a = at.lower()
        if a.startswith(("@keyframes", "@-webkit-keyframes", "@font-face", "@page", "@counter-style", "@property")):
            return False
        if a.startswith("@media"):
            def may(q):
                w = q.split()
                if w and w[0] == "only":
                    w = w[1:]
                if w and w[0] == "not":
                    return w[1:] not in (["all"], ["screen"])
                return not w or w[0] in ("all", "screen") or w[0].startswith("(")
            if not any(may(q) for q in parts(a[6:].strip())):
                return False
    return True
INITIAL = {"pointer-events": "auto", "visibility": "visible", "opacity": "1", "display": "inline", "user-select": "auto", "-webkit-user-select": "auto",
           "position": "static", "overflow": "visible", "overflow-x": "visible", "overflow-y": "visible", "clip-path": "none", "contain": "none",
           "content-visibility": "visible", "border": "(none)", "max-width": "none", "transform": "none", "scale": "none", "rotate": "none",
           "translate": "none", "zoom": "normal", "clip": "auto"}
BORDERS = ["border-" + s + w for s in ("", "top-", "right-", "bottom-", "left-", "block-", "inline-", "block-start-", "block-end-", "inline-start-", "inline-end-")
           for w in ("width", "style")] + ["border-" + s for s in ("top", "right", "bottom", "left", "block", "inline", "block-start", "block-end", "inline-start", "inline-end")]
INITIAL.update({k: "(from border)" for k in BORDERS})  # none of the site's: what the border shorthand gives
INHERITED = {"pointer-events", "visibility"}
def flat(m, p):  # a selector nested in style rules, written out: & is the rule around it, else it is a descendant of it
    outs = [p]
    for x in reversed([x for x in m if not x.startswith("@")]):
        outs = [q.replace("&", o) if "&" in q else o + " " + q for o in parts(x) for q in outs]
    return outs
def norm(k, v):  # a value as one spelling: lower case, '' as "", four equal insets as one
    v = " ".join(v.lower().split())
    if k == "content" and v in ("''", '""'):
        return '""'
    if k == "inset" and len(set(v.split())) == 1:
        return v.split()[0]
    return v
def surely(m):  # a rule inside these applies on every screen (none, or @media screen or all with no condition)
    return all(re.fullmatch(r"@media\s+(only\s+)?(screen|all)", x.strip().lower()) for x in m)
def possible(chain, prop):  # every value prop may end with on the chain's last element
    up = lambda: possible(chain[:-1], prop) if len(chain) > 1 else {INITIAL[prop]}
    def base():  # with no rule of the site's: inherited, the browser's own ([hidden] is display: none) or the initial value
        if prop in INHERITED:
            return up()
        return {"none"} if prop == "display" and "hidden" in chain[-1][3] else {INITIAL[prop]}
    def val(v):
        v = v.lower()
        if v == "inherit" or (v == "unset" and prop in INHERITED):
            return up()
        if v in ("revert", "revert-layer"):
            return base()
        if v in ("initial", "unset"):
            return {INITIAL[prop]}
        return {v}
    cands = []
    for i, (m, s, d) in enumerate(R):
        if not on_screen(m):
            continue
        vs = [d[k] for k in (prop, "all") if k in d]  # all sets every property this check reads
        lay = any(x.lower().startswith("@layer") for x in m)  # a layer's rule loses to one in no layer, unless !important
        for v in vs:
            imp = bool(re.search(r"!\s*important\s*$", v, re.I))
            v = re.sub(r"(?i)\s*!\s*important\s*$", "", v).strip()
            for p in parts(s):
                fl = flat(m, p)  # a nested rule as written out (& the rule around it)
                if any(reach(q, chain) for q in fl):
                    sp = spec(p)
                    for x in m:  # a rule nested in another adds that one's specificity, as & does
                        if not x.startswith("@"):
                            sp = tuple(a + b for a, b in zip(sp, max(spec(y) for y in parts(x))))
                    cands.append(((imp, lay if imp else not lay, sp, i), v, surely([x for x in m if x.startswith("@")]) and any(reach(q, chain, True) for q in fl)))
    sure = [c for c in cands if c[2]]
    best = max(sure, key=lambda c: c[0]) if sure else None
    out = val(best[1]) if best else base()
    for k, v, s in cands:
        if not s and (best is None or k > best[0]):
            out = out | val(v)
    return out
HERO = [("html", set(), "", {"lang"}), ("body", set(), "", set()), ("header", {"hero"}, "", {"class"})]
HINT = HERO + [("div", {"hero-bottom"}, "", {"class"}), ("p", {"tap-hint"}, "tapHint", {"class", "id"})]
PITCH = HERO + [("div", {"hero-top"}, "", {"class"}), ("h1", {"pitch"}, "", {"class"})]
DEMO = PITCH[:-1] + [("div", {"tag-demo"}, "demoPill", {"class", "id"})]
hb = html[html.find('<div class="hero-bottom">'):html.find('<div class="zoomctl">')]
if html.count('<header class="hero">') != 1 or html.count("<body>") != 1 or not (html.find('<header class="hero">') < html.find('<div class="hero-top">') < html.find('<div class="hero-bottom">')) \
        or opener(hb, "p", "tap-hint", "tapHint") != 1 or opener(html, "div", "tag-demo", "demoPill", ("hidden",)) != 1:
    bad.append("index.html: the hero is not as this check reads it (header.hero, .hero-top with the pitch and SAMPLE DATA, .hero-bottom with the hint)")
# the boxes over the globe as index.html has them: only the boxes take taps, so a dot seen in a gap between them is
# there to tap (site/app.js, hidden): the satellite bar (wider than BACK TO THE GLOBE, with the credit's words on the
# map), the stats row (each stat a box of its own, none on the map) and + and - (each reaching 4 px past its edge,
# which meets the other's about the middle of the gap between them); and no style attribute there, which this check
# does not read
zc = html[html.find('<div class="zoomctl">'):html.find("</header>")]
idAt = lambda t, i: (lambda m: m.start() if m else -1)(re.search(r"""\bid\s*=\s*["']?%s["'\s>]""" % i, t))  # where an element with this id stands
if opener(hb, "div", "sat", "satBar", ("hidden",)) != 1 or opener(hb, "button", "sat-btn", "satBack") != 1 or opener(hb, "p", "sat-note sat-err", "satErr") != 1 \
        or hb.count('<p class="sat-credit">satellite <a href="#credits">') != 1 or opener(hb, "div", "stat") != 3 or opener(zc, "button", "", "zin") != 1 or opener(zc, "button", "", "zout") != 1 \
        or not (0 <= idAt(hb, "satBar") < idAt(hb, "tapHint") < idAt(hb, "stats")):
    bad.append("index.html: the satellite bar, the stats or + and - are not as this check reads them")
if re.search(r"<[^>]*\sstyle\s*=", html[html.find('<header class="hero">'):html.find("</header>")], re.I):
    bad.append("index.html: a style attribute in the hero, which this check does not read")
# nor any style but styles.css: no <style> element, and no stylesheet but site/fonts.css (its fonts only) and site/styles.css
# (the build adds ?v= to both)
sheets = re.findall(r"""<link\b[^>]*\brel\s*=\s*["']?stylesheet\b[^>]*>""", html, re.I)
fonts = open("site/fonts.css", encoding="utf-8").read()
if re.search(r"<style\b", html, re.I) or [re.search(r"""\bhref\s*=\s*["']?([^"'\s>?]+)""", x).group(1) for x in sheets] != ["site/fonts.css", "site/styles.css"] \
        or rules(fonts) != [] or re.search(r"@import\b", re.sub(r"(?s)/\*.*?\*/", "", css + fonts), re.I):
    bad.append("index.html: a style that this check does not read (a <style> element, another stylesheet, an @import, or more than fonts in site/fonts.css)")
MAP = HERO[:2] + [("header", {"hero", "map-on"}, "", {"class"})]
DEEP = HERO[:2] + [("header", {"hero", "map-on", "map-gone"}, "", {"class"})]
HB = ("div", {"hero-bottom"}, "", {"class"})
try:
    for m, s, d in R:
        if not on_screen(m):  # a printed page takes no taps; a keyframe is no selector
            continue
        for p in parts(s):
            hint = any(reach(q, HINT) for q in flat(m, p))
            if hint and ("all" in d or any(k in d and d[k] != "var(--paper)" for k in ("background", "background-color"))):
                bad.append("the tap hint's paper: " + p)
            if hint and re.sub(r"(?i)\s*!\s*important\s*$", "", d.get("display", "none")).strip().lower() != "none":
                bad.append("a display the hint's hidden attribute cannot undo: " + p)
            if any(reach(q, HINT[:i]) for q in flat(m, p) for i in range(1, len(HINT) + 1)) and any(k in d for k in ("word-break", "line-break", "white-space", "overflow-wrap", "word-wrap", "hyphens")):
                bad.append("the hint's words may break inside a part (or it inherits that): " + p)
    nv = lambda v: re.sub(r"\s*([(),:])\s*", r"\1", " ".join(v.lower().split()))  # one spelling: case, spaces
    def want(chain, prop, ok, what):
        got = {nv(v) for v in possible(chain, prop)}
        if not got <= {nv(v) for v in ok}:
            bad.append(what + " (" + prop + ": " + ", ".join(sorted(got)) + ")")
    want(HINT, "pointer-events", {"none"}, "the tap hint takes taps")
    if "none" in possible(HINT, "display"):
        bad.append("a rule takes the tap hint away on the globe")
    want(HINT, "visibility", {"visible"}, "the tap hint is not seen")
    for i in range(1, len(HINT) + 1):
        want(HINT[:i], "opacity", {"1"}, "the tap hint fades")
    for name, chain in (("the pitch", PITCH), ("SAMPLE DATA", DEMO)):
        want(chain, "pointer-events", {"auto"}, "styles.css: " + name + " lets taps through to the globe")
        want(chain, "visibility", {"visible"}, "styles.css: " + name + " is not seen, and taps go through it")
    want(HERO + [HB, ("div", {"stats"}, "stats", {"class", "id", "hidden"})], "display", {"none"}, "the hidden stats row shows")
    for cls in ({"wheel-hint"}, {"wheel-hint", "on"}):  # the wheel hint, unseen, keeps its words out of a long press's selection (iOS)
        for prop in ("user-select", "-webkit-user-select"):
            want(HERO + [("div", cls, "", {"class", "aria-hidden"})], prop, {"none"}, "styles.css: the unseen wheel hint's words can be selected")
    for hero in (MAP, DEEP):
        SAT = hero + [HB, ("div", {"sat"}, "satBar", {"class", "id"})]
        want(SAT, "pointer-events", {"none"}, "the satellite bar's see-through parts take taps")
        want(SAT + [("button", {"sat-btn"}, "satBack", {"type", "class", "id"})], "pointer-events", {"auto"}, "BACK TO THE GLOBE lets taps through")
        want(SAT + [("p", {"sat-note", "sat-err"}, "satErr", {"class", "id"})], "pointer-events", {"auto"}, "the satellite map's note lets taps through")
        want(SAT + [("p", {"sat-credit"}, "", {"class"})], "pointer-events", {"none"}, "the credit's words take taps")
        want(SAT + [("p", {"sat-credit"}, "", {"class"}), ("a", set(), "", {"href"})], "pointer-events", {"auto"}, "the credit's link lets taps through")
        want(hero + [HB, ("div", {"stats"}, "stats", {"class", "id"}), ("div", {"stat"}, "", {"class"})], "pointer-events", {"none"}, "a stat takes taps on the satellite map")
    want(HERO + [HB, ("div", {"stats"}, "stats", {"class", "id"})], "pointer-events", {"none"}, "the gaps between the stats take taps")
    want(HERO + [HB, ("div", {"stats"}, "stats", {"class", "id"}), ("div", {"stat"}, "", {"class"})], "pointer-events", {"auto"}, "a stat lets taps through")
    want(HERO + [HB, ("div", {"legend"}, "legend", {"class", "id"})], "pointer-events", {"auto"}, "the legend lets taps through")
    want(HERO + [("div", {"hero-top"}, "", {"class"})], "pointer-events", {"none"}, "the hero's top takes taps, so no dot under its bar can be tapped")
    for hero in (HERO, MAP, DEEP):
        Z = hero + [("div", {"zoomctl"}, "", {"class"})]
        want(Z, "pointer-events", {"none"}, "the gap between + and - takes taps")
        for zid in ("zin", "zout"):
            want(Z + [("button", set(), zid, {"id", "aria-label"})], "pointer-events", {"auto"}, "+ or - lets taps through")
    # + and - and BACK TO THE GLOBE reach 4 px past their edges (2 px of border, then 4): a ::after of their own, placed
    # from the button and not cut by it, that nothing else changes (Chrome gave a finger beside one to it while the gap
    # between + and - took taps, 2026-11-18)
    for hero in (HERO, MAP, DEEP):
        Z = hero + [("div", {"zoomctl"}, "", {"class"})]
        btns = [Z + [("button", set(), zid, {"id", "aria-label"})] for zid in ("zin", "zout")] + \
            [hero + [HB, ("div", {"sat"}, "satBar", {"class", "id"}), ("button", {"sat-btn"}, "satBack", {"type", "class", "id"})]]
        for chain in btns:
            want(chain, "position", {"relative"}, "+, - or BACK TO THE GLOBE: its reach is not placed from it")
            for i in range(len(chain), 3, -1):  # the button and each box around it inside the hero (which clips, 14 px away)
                for prop, ok in (("overflow", "visible"), ("overflow-x", "visible"), ("overflow-y", "visible"), ("clip-path", "none"),
                                 ("content-visibility", "visible"), ("scale", "none"), ("zoom", "normal")):
                    want(chain[:i], prop, {ok}, "+, - or BACK TO THE GLOBE: its reach is cut, moved or shrunk")
                if any(re.search(r"\b(paint|strict|content)\b", v) for v in possible(chain[:i], "contain")):  # contain that clips
                    bad.append("+, - or BACK TO THE GLOBE: its reach is cut (contain)")
                if i < len(chain):  # a box around the button: no transform but a translate, which moves both (the button's own are below)
                    for v in possible(chain[:i], "transform"):
                        if v != "none" and not re.fullmatch(r"(\s*translate(3d|x|y|z)?\([^()]*\))+\s*", v):
                            bad.append("+, - or BACK TO THE GLOBE: a transform on its box shrinks or turns its reach (" + v + ")")
                if possible(chain[:i], "position") & {"absolute", "fixed"}:  # clip cuts only an absolute or fixed box
                    want(chain[:i], "clip", {"auto"}, "+, - or BACK TO THE GLOBE: its reach is cut (clip)")
            sat = "sat-btn" in chain[-1][1]
            want(chain, "transform", {"rotate(-1deg)", "rotate(-1deg) translate(-1px, -1px)", "rotate(-1deg) translate(2px, 2px)"} if sat else
                 {"none", "translate(-1px, -1px)", "translate(2px, 2px)"}, "+, - or BACK TO THE GLOBE: a transform moves or shrinks its reach")
            for prop in ("rotate", "translate"):
                want(chain, prop, {"none"}, "+, - or BACK TO THE GLOBE: a transform moves or shrinks its reach")
            want(chain, "border", {"2px solid var(--ink)"}, "+, - or BACK TO THE GLOBE: a border other than 2 px moves its reach")
            for k in BORDERS:
                want(chain, k, {"(from border)"}, "+, - or BACK TO THE GLOBE: a border other than 2 px moves its reach")
            got = {"after": {}, "before": {}}
            for m, s, d in R:
                if not on_screen(m):
                    continue
                for p in parts(s):
                    for q in flat(m, p):
                        mm = re.fullmatch(r"(.*?)::?(after|before)", q.strip(), re.I)
                        if mm and reach(mm.group(1).strip() or "*", chain):
                            for k, v in d.items():
                                v = norm(k, v)
                                if k == "box-sizing" or (k == "z-index" and v in ("0", "auto")):
                                    continue
                                got[mm.group(2).lower()].setdefault(k, set()).add(v if surely([x for x in m if x.startswith("@")]) else "(only sometimes) " + v)
            if got != {"after": {"content": {'""'}, "position": {"absolute"}, "inset": {"-6px"}}, "before": {}}:
                bad.append("+, - or BACK TO THE GLOBE does not reach 4 px past its edge: " + str(sorted((w, sorted((k, sorted(v)) for k, v in g.items())) for w, g in got.items())))
    # the stats row: up to 700 px wide narrower than its room, so its third stat ends clear of + (read through the
    # cascade: the rule for 641 px and up, and no rule after it that takes it back)
    STATS = HERO + [HB, ("div", {"stats"}, "stats", {"class", "id"})]
    NARROW = "min(560px,calc(100% - 112px))"
    hits = [i for i, (m, s, d) in enumerate(R) if "max-width" in d and any(reach(q, STATS) for p in parts(s) for q in flat(m, p))]
    sp = lambda x: re.sub(r"\s+", "", x.lower())  # an @media with no spaces at all
    rule = [i for i in hits if nv(R[i][2]["max-width"]) == NARROW and [sp(x) for x in R[i][0]] in ([sp(q + c)] for q in (
            "@media ", "@media screen and ", "@media only screen and ", "@media all and ") for c in ("(min-width: 641px)", "(width >= 641px)"))]
    if {nv(v) for v in possible(STATS, "max-width")} != {"560px", NARROW} or len(rule) != 1 or hits[-1] != rule[0]:
        bad.append("styles.css: the stats row is not narrower from 641 px wide up to 700, clear of + (" + ", ".join(sorted(possible(STATS, "max-width"))) + ")")
except ValueError as err:
    bad.append(str(err))
# its words: each part keeps its words and its dot together (no-break spaces), so a wrap breaks only after a dot; with a
# mouse its letters stand closer sooner in a narrow window (these two rules after the two for any pointer, so they win)
if js.count(r"""  const tapHint = () => ($("#tapHint").textContent = ["drag to spin", finePointer.matches ? zoomKeys : "pinch to zoom",
    "tap a " + (mgeo.length ? "pin" : "dot")].map((p) => p.replace(/ /g, "\u00a0")).join("\u00a0· "));
""") != 1:
    bad.append("site/app.js: the hint's parts are not kept together")
nar = [css.find(t) for t in ["@media (max-width: 400px) { .tap-hint { letter-spacing: 1px; padding-right: 8px; } }",
                             "@media (max-width: 359px) { .tap-hint { letter-spacing: 0; padding-right: 9px; } }",
                             "@media (pointer: fine) and (max-width: 469px) { .tap-hint { letter-spacing: 1px; padding-right: 8px; } }",
                             "@media (pointer: fine) and (max-width: 421px) { .tap-hint { letter-spacing: 0; padding-right: 9px; } }"]]
if min(nar) < 0 or nar != sorted(nar):
    bad.append("styles.css: the hint's letters in a narrow window")
# a mission tag that meets the strip fades (tidy counts it as a tag already kept), except while it fades for the map, and
# so does one under the pointer or with focus once its middle is behind the strip; tags and strip are placed on the page,
# so a scroll is no move toward the strip
if opener(html, "p", "tap-hint", "tapHint") != 1:
    bad.append("index.html: the tap hint is not #tapHint")
if js.count('  const hintStrip = $("#tapHint");\n') != 1 or js.count("""      const x = r.left + scrollX + r.width / 2, y = r.top + scrollY + (g.rs ? hangPx + 1 + h / 2 : r.height / 2);
""") != 1 or js.count("""    const kept = [];
    const hb = hintStrip && !hintStrip.closest(".map-on") ? hintStrip.getBoundingClientRect() : null; // none while it fades for the map
    const strip = hb?.width ? { x: hb.left + scrollX + hb.width / 2, y: hb.top + scrollY + hb.height / 2, w: hb.width, h: hb.height } : null;
    if (strip) kept.push({ ...strip, nx: strip.x, ny: strip.y });
    for (const t of live) {
      const behind = !!strip && t.held && Math.abs(strip.x - t.x) < strip.w / 2 && Math.abs(strip.y - t.y) < strip.h / 2;
      const hit = behind || (!t.held && kept.some((k) => touch(k, t, k.x - t.x, k.y - t.y)));
""") != 1:
    bad.append("site/app.js: a mission tag does not fade where it meets the tap hint")
for t in ["""      const soon = !t.held && !hit && kept.some((k) => touch(k, t, k.nx - t.nx, k.ny - t.ny));
      if (soon) again = true;                          // once they stop moving, the guess goes away
      if (!hit && !soon) kept.push(t);
      setOff(t.g, hit || soon);
""", """      live.push({ g, x, y, w: tag.offsetWidth, h, held: pin.matches(":hover, :focus-within"),
        nx: dt ? x + ((x - g.seen.x) * AHEAD) / dt : x, ny: dt ? y + ((y - g.seen.y) * AHEAD) / dt : y });
      g.seen = { x, y, t: now };
""", '  el.addEventListener("pointerdown", byTouch, true);\n  el.addEventListener("pointermove", byTouch, true);\n']:
    if js.count(t) != 1:
        bad.append("site/app.js: " + t.strip().splitlines()[0])
# nor does a press on the hint's words open a receipt whose dot is hidden under it, by mouse (onPointClick) or by finger
# (the click that goes to receiptsNear), and the dot shows no preview or hand there; on the map the strip counts not
for t in ["""  const onStrip = (ev) => {
    const b = hintStrip && !hintStrip.closest(".map-on") ? hintStrip.getBoundingClientRect() : null;
    return !!b?.width && ev.clientX >= b.left && ev.clientX < b.right && ev.clientY >= b.top && ev.clientY < b.bottom;
  };
""", '    .onPointClick((d, ev) => {\n', '      if (pressType !== "mouse" || onStrip(ev)) return;\n',
          '    el.classList.toggle("on-strip", onStrip(ev));\n', '    if (pressOn === false || (mouse && !satMarks) || ev.target.closest(".mpin") || onStrip(ev)) return;\n']:
    if js.count(t) != 1:
        bad.append("site/app.js: " + t.strip().splitlines()[0])
tip = [d for m, s, d in R if not m and s == "#globe.on-strip .scene-tooltip"]
hand = [d for m, s, d in R if not m and s == "#globe.on-strip canvas.clickable"]
if len(tip) != 1 or tip[0].get("display") != "none !important" or len(hand) != 1 or hand[0].get("cursor") != "auto":
    bad.append("styles.css: a dot under the strip shows its preview over the hint's words")
if any(".scene-tooltip" in p and d.get("display", "none !important") != "none !important" for m, s, d in R for p in parts(s)):
    bad.append("styles.css: a rule shows the dots' preview again")
for t in ['  $("#stats").hidden = !events.length && !loadFailed;\n',
          """  if (totals.events === 1) $('[data-stat="events"] + span').textContent = "cleanup";\n""",
          '    if (key === "kg" && target === 0 && events.length) { el.textContent = "?"; return; } // only sacks so far: the card says ? KG too\n',
          '  const allDemo = events.length > 0 && events.every((e) => e.demo);\n  if (allDemo) $("#demoPill").hidden = false;\n']:
    if js.count(t) != 1:
        bad.append("site/app.js: " + t.strip())
if "events.every((e) => e.demo)) {" in js:
    bad.append("sample missions still show with no receipt at all")
pitch = '<h1 class="pitch">WE PAY LOCAL CREWS <br>TO CLEAN UP. EVERY <br>CLEANUP GETS A <br>PUBLIC RECEIPT.</h1>'  # a space before each <br>: the plain text keeps the words apart
top = html[html.find('<div class="hero-top">'):html.find('<div class="hero-bottom">')]
if re.sub(r"(?s)<!--.*?-->", "", html).count("<h1") != 1 or top.count(pitch) != 1 or not (0 <= top.find('id="demoPill"') < top.find(pitch)):
    bad.append("the pitch line is not the page's only h1, after SAMPLE DATA in the hero's top")
for t in [".pitch {\n  margin: 0; font-family: var(--font-mono); font-size: 11px;", "#demoPill:not([hidden]) ~ .pitch { display: none; }"]:
    if t not in css:
        bad.append("styles.css: " + t.splitlines()[0])
if html.count('<main id="main">') != 1 or html.count('href="#main"') != 1 or 'href="#receipts"' in html or html.count('id="receipts"') != 1:
    bad.append("SEE THE RECEIPTS does not go to the top of <main>")
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY2
)
check "the first screen shows only what is real: no sample receipts listed (the files stay), the stats hidden until a receipt counts (cleanup for one), the tap hint on a strip of paper that no rule takes away or lets take taps (its parts kept together up to each dot with nothing that breaks inside one, closer letters in a narrow window with a mouse, a mission tag fades where it meets it, also one under the pointer once its middle is behind it, placed on the page so a scroll fades none, and a press on its words opens no receipt dot hidden under it nor shows its preview), the line that says what Sapu Earth does as the page's h1 where SAMPLE DATA stood, the pitch and SAMPLE DATA solid boxes that let no tap through, only the boxes take taps (BACK TO THE GLOBE, its note and its credit's link but not the bar or the credit's words, each stat but not the gaps or on the satellite map, + and - but not the box between them, which their reaches cover, nor the hero's top), + and - and BACK TO THE GLOBE with a reach 4 px past their edges that no rule moves, cuts, shrinks or hides (a ::after or ::before for every element, in any case, overflow, clip-path, containment that clips, a transform, scale or zoom on the button, or one on a box around it that is more than a translate, clip on an absolute box, a border other than 2 px solid; the reach as nested CSS, with '' or four insets, read the same), the stats row narrower from 641 px wide up to 700 so its third stat stays clear of + (read through the cascade, tied to .stats in a @media for 641 px and up, also in its range form, no rule after it that sets the row's max-width; values in any case and spacing), each element read by the cascade (rules by the elements they reach, !important, layers, specificity and order, any rule that may apply, nested or not, names and keywords in any case, all, revert and the browser's own hidden rule; no style attribute in the hero, no <style> element, no @import and no stylesheet but site/fonts.css with its fonts and site/styles.css), the unseen wheel hint's words never selected, SEE THE RECEIPTS to the top of <main>" "$NINE" "ok"
# Back on a phone closes an open post or chooser (site/app.js: the block from the press to Escape, openLinked and its call,
# seeSpot), run in node with a fake history: a tap takes one step, Back, ✕, Escape and the backdrop go back over it, a
# post opened by the page's own link (also after a reload) takes none and keeps Back for the app the link came from, a
# chooser and the mission it opens share one step, a post drawn again takes no second one, the page under the step
# loses its # (#main from SEE THE RECEIPTS) and restores no scroll as the step back lands (the mode the browser sees
# right after the popstate), so going back leaves the page where it was, then gets auto once the step back is over (so
# a reload or a Back from another site puts it back), Forward shows the post again and goes past a chooser's step, SEE
# THE SPOT flies only after the step back, and two quick closes go back only once.
cat > "$T/back.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  let openedAt = 0, openX = NaN");
const b = s.indexOf('  addEventListener("keydown", (ev) => { if (ev.key === "Escape" && !overlay.hidden) leavePost(); });');
const fn = (head) => { const i = s.indexOf(head); const j = i < 0 ? -1 : s.indexOf("\n  }\n", i); return i < 0 || j < 0 ? null : s.slice(i, j + 5); };
const linkedSrc = fn("  function openLinked() {"), spotSrc = fn("  function seeSpot(lat, lng) {");
if (a < 0 || b < a || !linkedSrc || !spotSrc) { console.log("wrong: the block from the press to Escape, openLinked or seeSpot is missing"); process.exit(); }
if (s.split("\n  openLinked();\n").length !== 2 || !s.includes(linkedSrc + "  openLinked();\n")) { console.log("wrong: openLinked() is not called once, right after it"); process.exit(); }
const block = s.slice(a, s.indexOf("\n", b));
function page(start) {
  const entries = start || [{ url: "https://sapu.earth/", state: null }];
  let i = entries.length - 1, left = false;
  const tasks = [], on = {}, ov = [], log = [], restored = [];
  const fire = (t, ev) => (on[t] || []).forEach((f) => f(ev));
  // the browser decides on the scroll of the entry it lands on right after the popstate: that mode is kept in restored
  const land = () => { fire("popstate", { state: entries[i].state }); restored.push(entries[i].sr || "auto"); };
  const history = {
    get state() { return entries[i].state; },
    get scrollRestoration() { return entries[i].sr || "auto"; },
    set scrollRestoration(v) { entries[i].sr = v; },
    pushState(st, _, url) { entries.splice(i + 1); entries.push({ url: new URL(url, entries[i].url).href, state: st, sr: entries[i].sr }); i++; },
    replaceState(st, _, url) { entries[i] = { url: url == null ? entries[i].url : new URL(url, entries[i].url).href, state: st, sr: entries[i].sr }; },
    back() { tasks.push(() => { if (i === 0) { left = true; return; } i--; land(); }); },
    forward() { tasks.push(() => { if (i === entries.length - 1) return; i++; land(); }); },
  };
  const u = () => new URL(entries[i].url);
  const location = { get href() { return entries[i].url; }, get pathname() { return u().pathname; }, get search() { return u().search; }, get hash() { return u().hash; } };
  const close = { focus() {}, addEventListener(t, f) { close.click = f; } };
  const overlay = { hidden: true, innerHTML: "", querySelector: () => close, addEventListener: (t, f, cap) => { if (!cap) ov.push(f); } };
  const don = {};
  const document = { body: { classList: { add() {}, remove() {} } }, activeElement: null, visibilityState: "visible",
    addEventListener: (t, f) => (don[t] = don[t] || []).push(f) };
  const hide = () => { document.visibilityState = "hidden"; (don.visibilitychange || []).forEach((f) => f()); };
  const at = () => [i, entries.length, entries[i].url.replace("https://sapu.earth", ""), JSON.stringify(entries[i].state)].join(" ");
  const api = new Function("overlay", "document", "history", "location", "addEventListener", "setTimeout", "performance",
    "events", "missions", "missionOf", "scrollY", "scrollTo", "reduceMotion", "flyTo", "r3", "SAT_MPX", "satMin", "satBar", "$",
    "let reopen = null, stage = null, lastFocus = null;\n" + block +
    "\nfunction openPost(e) { showOverlay(\"#ev-\" + encodeURIComponent(e.id)); }\nfunction openMission(m) { showOverlay(\"#m-\" + m.no); }\n" +
    linkedSrc + "  openLinked();\n" + spotSrc + "\nreturn { showOverlay, leavePost, seeSpot };")(
    overlay, document, history, location, (t, f) => (on[t] = on[t] || []).push(f), (f) => tasks.push(f), { now: () => 0 },
    [{ id: "a" }], [{ no: 2 }, { no: 3 }], () => null, 500, () => log.push("scroll@" + at()), false,
    () => log.push("fly@" + at()), (x) => x, 12, () => 1, { hidden: true }, () => ({ focus() {} }));
  const flush = () => { while (tasks.length) tasks.shift()(); };
  return { api, overlay, close, flush, fire, log, backdrop: () => ov.forEach((f) => f({ target: overlay })),
    user: { back: () => history.back(), forward: () => history.forward() }, at, under: () => entries[0].url.replace("https://sapu.earth", ""),
    modes: () => entries.map((e) => e.sr || "auto").join(","), restored: () => restored.join(","), hide, left: () => left };
}
const want = [];
let n = 0;
const run = (name, f, w) => { n++; let got; try { got = f(); } catch (e) { got = "threw " + e.message; } if (got !== w) want.push(name + ": " + got + " (want " + w + ")"); };
run("a tap, then Back", () => { const p = page(); p.api.showOverlay("#ev-a"); const o = p.at(); p.user.back(); p.flush();
  return o + " | " + p.at() + " " + p.overlay.hidden + " " + p.left(); }, '1 2 /#ev-a {"post":1} | 0 2 / null true false');
run("a tap, then ✕", () => { const p = page(); p.api.showOverlay("#m-2"); p.close.click(); const h = p.overlay.hidden; p.flush();
  return h + " " + p.at() + " " + p.left(); }, "true 0 2 / null false");
run("a tap, then Escape", () => { const p = page(); p.api.showOverlay("#m-2"); p.fire("keydown", { key: "Escape" }); p.flush();
  return p.overlay.hidden + " " + p.at(); }, "true 0 2 / null");
run("a tap, then the backdrop", () => { const p = page(); p.api.showOverlay("#ev-a"); p.backdrop(); p.flush();
  return p.overlay.hidden + " " + p.at(); }, "true 0 2 / null");
run("the page's own link takes no step", () => { const p = page([{ url: "https://sapu.earth/#m-2", state: null }]); const o = p.at() + " " + p.overlay.hidden;
  p.close.click(); p.flush(); return o + " | " + p.at() + " " + p.left(); }, "0 1 /#m-2 null false | 0 1 / null false");
run("a reload of a tapped post", () => { const p = page([{ url: "https://sapu.earth/", state: null }, { url: "https://sapu.earth/#m-2", state: { post: 1 } }]);
  const o = p.overlay.hidden; p.close.click(); p.flush(); return o + " " + p.at() + " " + p.overlay.hidden; }, "false 0 2 / null true");
run("a chooser, then its mission", () => { const p = page(); p.api.showOverlay(null); const o = p.at(); p.api.showOverlay("#m-3"); const m = p.at();
  p.user.back(); p.flush(); return o + " | " + m + " | " + p.at() + " " + p.overlay.hidden; }, '1 2 / {"post":1} | 1 2 /#m-3 {"post":1} | 0 2 / null true');
run("a post drawn again", () => { const p = page(); p.api.showOverlay("#ev-a"); p.api.showOverlay("#ev-a"); return p.at(); }, '1 2 /#ev-a {"post":1}');
run("a tap after SEE THE RECEIPTS (#main)", () => { const p = page([{ url: "https://sapu.earth/#main", state: null }]); p.api.showOverlay("#ev-a"); const o = p.at() + " under " + p.under() + " " + p.modes();
  p.close.click(); p.flush(); return o + " | " + p.at() + " landed " + p.restored() + ", then " + p.modes(); }, '1 2 /#ev-a {"post":1} under / manual,auto | 0 2 / null landed manual, then auto,auto');
run("the browser's Back: no scroll as it lands, auto once it has", () => { const p = page(); p.api.showOverlay("#m-2"); p.user.back(); p.flush();
  return p.at() + " landed " + p.restored() + ", then " + p.modes(); }, "0 2 / null landed manual, then auto,auto");
run("a page put away with its post open", () => { const p = page(); p.api.showOverlay("#ev-a"); p.hide(); const o = p.modes(); p.close.click(); p.flush();
  return o + " | landed " + p.restored() + ", then " + p.modes(); }, "manual,auto | landed manual, then auto,auto");
run("Forward shows the post again", () => { const p = page(); p.api.showOverlay("#ev-a"); p.user.back(); p.flush(); p.user.forward(); p.flush();
  const o = p.at() + " " + p.overlay.hidden + " " + p.modes(); p.user.back(); p.flush(); return o + " | " + p.at() + " " + p.overlay.hidden + " " + p.left(); },
  '1 2 /#ev-a {"post":1} false auto,auto | 0 2 / null true false');
run("Forward goes past a chooser's step", () => { const p = page(); p.api.showOverlay(null); p.close.click(); p.flush(); p.user.forward(); p.flush();
  return p.at() + " " + p.overlay.hidden + " " + p.left(); }, "0 2 / null true false");
run("SEE THE SPOT after a tap", () => { const p = page(); p.api.showOverlay("#ev-a"); p.api.seeSpot(1, 2); const before = p.log.join(",");
  p.flush(); return before + " | " + p.overlay.hidden + " " + p.log.join(","); }, " | true scroll@0 2 / null,fly@0 2 / null");
run("SEE THE SPOT after a link", () => { const p = page([{ url: "https://sapu.earth/#ev-a", state: null }]); p.api.seeSpot(1, 2);
  return p.overlay.hidden + " " + p.log.join(","); }, "true scroll@0 1 / null,fly@0 1 / null");
run("two quick closes", () => { const p = page(); p.api.showOverlay("#ev-a"); p.close.click(); p.fire("keydown", { key: "Escape" }); p.api.leavePost(); p.flush();
  return p.at() + " " + p.left(); }, "0 2 / null false");
console.log(want.length ? "wrong: " + want.join("; ") : "ok " + n);
JS
check "Back on a phone closes an open post (site/app.js in node): a tap takes one step and Back, ✕, Escape and the backdrop go back over it; the page's own link takes none (also after a reload), a chooser and its mission share one, a redraw takes none, the page under the step loses its #main and restores no scroll as the step back lands (✕, the browser's Back, after the page was put away), then gets auto once it has, Forward shows the post again and goes past a chooser's step, SEE THE SPOT flies after the step back, two quick closes go back once" "$(node "$T/back.js" "$T/home.js" 2>&1)" "ok 16"
# Photos after Back (site/app.js): WebKit brings a page back from its back-forward cache with the photos that were
# still loading broken, so a pageshow with persisted asks again for each picture that did not load, and only for those:
# not a loaded one, not one still on its way, not one without a src or with an empty one (no write to them at all: an
# empty src read back is the page's own address, which would be asked for as a picture), and an ordinary load asks for
# none. The pictures here act as a browser's (src reads back as a full address) and as WebKit's (only a src that
# changes asks again, the same value is answered from the failed picture), so a relative and an absolute src both
# count, whichever way the block writes them. Nothing is asked during the pageshow itself, only once the page is back
# (a timer): asking during it kept WebKit from firing pagehide and pageshow on the next leave and Back. The scroll in
# the same block: a page back from the cache goes back, once it is back and at once (not smoothly), to where the last
# pagehide found it (Mobile Safari put it near the top after a visit to another site), whatever its scrollRestoration,
# and one that comes back manual gets auto; one already where it was, or with no pagehide seen, is not moved, and an
# ordinary load is left alone; nor one whose window changed width while away (a phone turned on its side: Chrome on
# Android has already placed the page in the new layout, where the old place was 300 px off the card), while one turned
# and back again is put back. A focus that is not all on the screen as the page is left is let go (WebKit scrolls a
# page back from its cache to the element that has the focus), one on the screen is kept, and the page itself or no
# focus is left alone. window here is the global object, as in a browser.
cat > "$T/pageshow.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  // ---------- photos after Back"), b = s.indexOf("  // ---------- end of photos after Back ----------");
if (a < 0 || b < a) { console.log("wrong: the block is missing"); process.exit(); }
const BASE = "https://sapu.earth/";
const img = (src, complete, w) => {
  const im = { asks: 0, writes: 0, complete, naturalWidth: w, attr: src };
  const set = (v) => { v = String(v); im.writes++; if (v !== im.attr) { im.attr = v; if (v) im.asks++; } };
  im.getAttribute = (n) => (n === "src" ? im.attr : null);
  im.removeAttribute = (n) => { if (n === "src") { im.writes++; im.attr = null; } };
  im.setAttribute = (n, v) => { if (n === "src") set(v); };
  Object.defineProperty(im, "src", { get: () => (im.attr === null ? "" : new URL(im.attr, BASE).href), set });
  return im;
};
function env(mode, y) {
  const e = { y, w: 390, h: 844, active: null, scrolls: [], timers: [], on: {}, history: { scrollRestoration: mode } };
  e.body = { blurs: 0, getBoundingClientRect: () => ({ top: -500, bottom: 5000 }), blur() { if (!e.hiding) e.body.blurs++; } };
  e.imgs = { broken: img("/media/aaa", true, 0), absolute: img("https://sapu.earth/media/ddd", true, 0), loaded: img("/media/bbb", true, 2000),
    loading: img("/media/ccc", false, 0), nosrc: img(null, true, 0), empty: img("", true, 0) };
  e.flush = () => { while (e.timers.length) e.timers.shift()(); };
  // hiding: while the pagehide runs, as in WebKit, which takes no focus change while a page goes into its cache
  e.fire = (t, ev) => { e.hiding = t === "pagehide"; try { (e.on[t] || []).slice().forEach((f) => f(ev || {})); } finally { e.hiding = false; } };
  e.asks = () => Object.entries(e.imgs).map(([k, im]) => k + ":" + im.asks).join(" ");
  for (const k of ["scrollY", "pageYOffset"]) Object.defineProperty(globalThis, k, { get: () => e.y, configurable: true });
  Object.defineProperty(globalThis, "innerWidth", { get: () => e.w, configurable: true });
  Object.defineProperty(globalThis, "innerHeight", { get: () => e.h, configurable: true });
  globalThis.scrollTo = globalThis.scroll = (o, y2) => { e.scrolls.push(typeof o === "object" ? o.top + " " + o.behavior : o + "," + y2); e.y = typeof o === "object" ? o.top : y2; };
  const add = (t, f, o) => (e.on[t] = e.on[t] || []).push(o?.once ? function g(ev) { e.on[t] = e.on[t].filter((x) => x !== g); f(ev); } : f);
  globalThis.addEventListener = add;
  globalThis.window = globalThis;
  const all = Object.values(e.imgs);
  const document = { querySelectorAll: (q) => (q === "img" ? all : q === "img[src]" ? all.filter((im) => im.getAttribute("src") !== null) : []), images: all,
    body: e.body, get activeElement() { return e.active; }, documentElement: { scrollTo: (o) => globalThis.scrollTo(o) } };
  new Function("document", "addEventListener", "setTimeout", "history", s.slice(a, b))(document, add, (f) => e.timers.push(f), e.history);
  return e;
}
const bad = [], none = "broken:0 absolute:0 loaded:0 loading:0 nosrc:0 empty:0";
let e = env("auto", 0);
if (!(e.on.pageshow || []).length) bad.push("no pageshow listener");
e.fire("pageshow", { persisted: false }); e.flush();
if (e.asks() !== none) bad.push("an ordinary load asked: " + e.asks());
e.fire("pageshow", { persisted: true });
if (e.asks() !== none) bad.push("asked during the pageshow: " + e.asks());
e.flush();
if (e.asks() !== "broken:1 absolute:1 loaded:0 loading:0 nosrc:0 empty:0") bad.push("after the first Back " + e.asks());
if (new URL(e.imgs.broken.attr, BASE).href !== BASE + "media/aaa" || new URL(e.imgs.absolute.attr, BASE).href !== BASE + "media/ddd") bad.push("asked for " + e.imgs.broken.attr + " " + e.imgs.absolute.attr);
e.fire("pageshow", { persisted: true }); e.flush();
if (e.asks() !== "broken:2 absolute:2 loaded:0 loading:0 nosrc:0 empty:0") bad.push("after a second Back " + e.asks());
if (e.imgs.nosrc.writes || e.imgs.empty.writes || e.imgs.loaded.writes || e.imgs.loading.writes) bad.push("wrote to a picture it should leave alone");
if (e.scrolls.length || e.history.scrollRestoration !== "auto") bad.push("moved a page with no pagehide seen: " + e.scrolls);
// back near the top, manual or auto: put back where it was left, once the page is back, at once; a manual one gets auto
for (const mode of ["manual", "auto"]) {
  e = env(mode, 788); e.fire("pagehide"); e.y = 62; e.fire("pageshow", { persisted: true });
  if (e.history.scrollRestoration !== "auto" || e.scrolls.length) bad.push(mode + ": during the pageshow " + e.history.scrollRestoration + " " + e.scrolls);
  e.flush();
  if (e.scrolls.join() !== "788 instant" || e.y !== 788) bad.push(mode + ": after it " + e.scrolls.join() + " at " + e.y);
  // a second leave from another place: back there, not to the first one
  e.y = 300; e.fire("pagehide"); e.y = 62; e.fire("pageshow", { persisted: true }); e.flush();
  if (e.scrolls.join() !== "788 instant,300 instant" || e.y !== 300) bad.push(mode + ": after a second leave " + e.scrolls.join() + " at " + e.y);
}
// turned while away (a phone on its side, 390 to 844 wide): the browser has placed the page in the new layout; not
// moved, manual or auto. Turned and back again before the Back: put back. Back below the place: put back too.
for (const mode of ["manual", "auto"]) {
  e = env(mode, 878); e.fire("pagehide"); e.w = 844; e.y = 574; e.fire("pageshow", { persisted: true }); e.flush();
  if (e.scrolls.length || e.y !== 574 || e.history.scrollRestoration !== "auto") bad.push(mode + ": turned while away, moved: " + e.scrolls.join() + " at " + e.y);
  e = env(mode, 878); e.fire("pagehide"); e.w = 844; e.w = 390; e.y = 62; e.fire("pageshow", { persisted: true }); e.flush();
  if (e.scrolls.join() !== "878 instant" || e.y !== 878) bad.push(mode + ": turned and back again " + e.scrolls.join() + " at " + e.y);
  e = env(mode, 788); e.fire("pagehide"); e.y = 1500; e.fire("pageshow", { persisted: true }); e.flush();
  if (e.scrolls.join() !== "788 instant" || e.y !== 788) bad.push(mode + ": back below the place " + e.scrolls.join() + " at " + e.y);
}
// the focus (the screen is 390 x 844, an element's place on the page from its top, the page left at y, its left and
// right on the screen): one wholly off the screen as the page is left, above, below or to a side, is let go once the
// page is back from the cache, by the end of its pageshow, before any timer (WebKit takes no focus change in the
// pagehide, and scrolls to such a focus right after the pageshow), and one partly or all on the screen is kept (WebKit
// moves nothing then), though the page reads as at the top for a moment as it comes back (y 0 at the pageshow);
// nothing else is let go: not the page itself, not on an ordinary load, not a focus that moved before the page came back
// row: the left and right on the screen of the row of cards it stands in (THE RECEIPTS, NEXT UP), which shows it only
// inside it
const rect = (top, bottom, left, right) => ({ top, bottom, left, right, width: right - left, height: bottom - top, x: left, y: top });
const focus = (top, bottom, left = 20, right = 370, row) => { const f = { blurs: 0, getBoundingClientRect: () => rect(top - e.y, bottom - e.y, left, right),
  closest: (q) => (q === ".cards" && row ? { getBoundingClientRect: () => rect(top - e.y, bottom - e.y, row[0], row[1]) } : null),
  blur() { if (!e.hiding && e.active === f) { f.blurs++; e.active = e.body; } } }; return f; };
for (const [what, top, bottom, y, want, left, right, row, width] of [["below the screen", 952, 1290, 0, 1], ["just below it", 844, 900, 0, 1], ["above it", 700, 960, 1000, 1],
  ["just above it", 900, 1000, 1000, 1], ["half off the top", 980, 1200, 1000, 0], ["half off the bottom", 700, 900, 0, 0],
  ["20 px of it on the screen", 824, 1434, 0, 0], ["on the screen", 1000, 1300, 900, 0], ["as tall as the screen", 1000, 1844, 1000, 0],
  ["off to the left", 100, 400, 0, 1, -1112, -844], ["just off to the left", 100, 400, 0, 1, -268, 0], ["off to the right", 100, 400, 0, 1, 390, 658],
  ["half off to the left", 100, 400, 0, 0, -100, 168],
  ["swiped out of its row, its edge still in the window", 100, 400, 0, 1, -266.6, 0.6, [16, 374]], ["swiped out of its row, 2 px of it in the window", 100, 400, 0, 1, -266, 2, [16, 374]],
  ["swiped out of its row to the right", 100, 400, 0, 1, 374, 642, [16, 374]], ["1 px of it in its row", 100, 400, 0, 1, -251, 17, [16, 374]],
  ["partly in its row", 100, 400, 0, 0, 297, 565, [16, 374]], ["1 px of it in its row on the right", 100, 400, 0, 1, 373, 641, [16, 374]],
  ["39 px of it in its row", 100, 400, 0, 1, -213, 55, [16, 374]], ["40 px of it in its row", 100, 400, 0, 0, -212, 56, [16, 374]],
  ["39 px of it in its row on the right", 100, 400, 0, 1, 335, 603, [16, 374]], ["a small link wholly in its row by the edge", 100, 130, 0, 0, 20, 50, [16, 374]],
  ["a 30 px link with 20 px of it in its row", 100, 130, 0, 1, 6, 36, [16, 374]],
  ["4 px of the next card in its row at 320 px", 100, 400, 0, 1, 300, 568, [16, 304], 320],
  ["in a row wider than the window, 10 px of it on the screen at its right edge", 100, 400, 0, 1, 380, 648, [-500, 900]],
  ["1 px of it on the screen at the left, in no row", 100, 400, 0, 0, -267, 1], ["10 px of it on the screen at the left, in no row", 100, 400, 0, 0, -258, 10],
  ["in a row wider than the window, partly on the screen", 100, 400, 0, 0, -100, 168, [-500, 900]], ["in a row wider than the window, off it", 100, 400, 0, 1, -300, -10, [-500, 900]],
  ["in its row, below the screen", 952, 1290, 0, 1, 20, 288, [16, 374]], ["a card in its row on a wide screen, out of the row", 100, 400, 0, 1, -156.6, 110.6, [126, 1154], 1280],
  ["a card on a wide screen, out of the row to the right", 100, 400, 0, 1, 1253, 1521, [126, 1154], 1280], ["a card on a wide screen, in its row", 100, 400, 0, 0, 1000, 1268, [126, 1154], 1280]]) {
  e = env("auto", y);
  if (width) e.w = width;
  const f = focus(top, bottom, left, right, row);
  e.active = f; e.fire("pagehide"); e.y = 0; e.fire("pageshow", { persisted: true });
  if (f.blurs !== want) bad.push("a focus " + what + ": " + (f.blurs ? "let go" : "kept") + " by the end of the pageshow");
  e.flush();
  if (f.blurs !== want) bad.push("a focus " + what + ": " + (f.blurs ? "let go" : "kept") + " after it");
  e.fire("pagehide"); e.y = 0; e.fire("pageshow", { persisted: true }); e.flush();
  if (f.blurs !== want) bad.push("a focus " + what + ": " + (f.blurs > want ? "let go again" : "kept") + " on a second Back");
}
e = env("auto", 0);
{ const f = focus(952, 1290); e.active = f; e.fire("pageshow", { persisted: false }); e.flush(); if (f.blurs) bad.push("an ordinary load let a focus go"); }
e = env("auto", 0);
{ const f = focus(952, 1290), g = focus(100, 400); e.active = f; e.fire("pagehide"); e.active = g; e.fire("pageshow", { persisted: true }); e.flush();
  if (f.blurs || g.blurs) bad.push("a focus that moved before the page came back was let go"); }
e = env("auto", 0); e.active = e.body; e.fire("pagehide"); e.fire("pageshow", { persisted: true }); e.flush();
if (e.body.blurs) bad.push("the page itself let go");
e = env("auto", 0); e.active = null; e.fire("pagehide"); e.fire("pageshow", { persisted: true }); e.flush();
// not moved: back already where it was, no pagehide seen, an ordinary load (left manual)
const alone = [["auto", true, true, 788], ["manual", true, true, 788], ["manual", false, true, 0], ["manual", true, false, 0]];
for (const [mode, hide, persisted, yBack] of alone) {
  e = env(mode, 788);
  if (hide) e.fire("pagehide");
  e.y = yBack; e.fire("pageshow", { persisted }); e.flush();
  const want = persisted ? "auto" : mode;
  if (e.scrolls.length || e.history.scrollRestoration !== want) bad.push(`${mode} ${hide} ${persisted} ${yBack}: ` + e.history.scrollRestoration + " " + e.scrolls);
}
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
JS
check "photos and scroll after Back (site/app.js in node, with pictures that act as a browser's and WebKit's): a page back from the back-forward cache asks once more, after the pageshow, for each picture that did not load, relative or absolute and on every Back, and only for those (no write to a loaded one, one still loading, one without a src or with an empty one), and an ordinary load asks for none; it goes back at once to where the last pagehide found it, manual or auto, on every Back, above or below it, and one that came back manual gets auto; one already in place, with no pagehide seen, from an ordinary load or whose window changed width while away (a phone turned) is not moved; a focus wholly off the screen as the page is left (above, below or to a side) is let go once it is back, by the end of the pageshow (WebKit takes no focus change in the pagehide), and one partly or all on the screen is kept, though the page reads as at the top then; a card counts only where its row shows it, and less than 40 px of it there counts as none (one swiped out of THE RECEIPTS with its edge still in the window, or the next card's 4 px sliver at 320 px, is let go; 40 px, or a small link wholly in its row, is kept)" "$(node "$T/pageshow.js" "$T/home.js" 2>&1)" "ok"
# The land after Back (site/app.js): WebKit cuts the land's file too when the visitor leaves before it has come (it
# fails before pagehide), and the globe came back a bare blue ball. The file is asked for again: at the next Back when
# it failed before it, at once when it fails after a Back (Chrome reports a cut there); never during the pageshow
# itself (a timer), never after an ordinary load or a load that came, and once per Back. Every failure is still logged.
cat > "$T/land.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  // ---------- the land after Back"), b = s.indexOf("  // ---------- end of the land after Back ----------");
if (a < 0 || b < a) { console.log("wrong: the block is missing"); process.exit(); }
if (s.split('fetch("site/vendor/countries.geojson")').length !== 2 || !s.includes('\n  landAfterBack(() => fetch("site/vendor/countries.geojson")\n')
  || s.includes('.catch((e) => console.error("countries failed to load", e))')) { console.log("wrong: the land is not loaded through it, once"); process.exit(); }
const tick = () => new Promise((r) => setImmediate(r));
function env() {
  const e = { on: {}, timers: [], loads: [], errors: 0 };
  e.fire = (t, ev) => (e.on[t] || []).slice().forEach((f) => f(ev));
  e.flush = () => { while (e.timers.length) e.timers.shift()(); };
  const add = (t, f, o) => (e.on[t] = e.on[t] || []).push(o?.once ? function g(ev) { e.on[t] = e.on[t].filter((x) => x !== g); f(ev); } : f);
  globalThis.addEventListener = add;
  globalThis.window = globalThis;
  const land = new Function("addEventListener", "setTimeout", "console", s.slice(a, b) + "\nreturn landAfterBack;")(add, (f) => e.timers.push(f), { error: () => e.errors++ });
  land(() => new Promise((res, rej) => e.loads.push({ res, rej })));
  return e;
}
(async () => {
  const bad = [], cut = () => new TypeError("Load failed");
  let e = env();                                              // came: never asked again
  if (e.loads.length !== 1) bad.push("not asked at the start: " + e.loads.length);
  e.loads[0].res(); await tick(); e.fire("pageshow", { persisted: true }); e.flush();
  if (e.loads.length !== 1) bad.push("came, asked again: " + e.loads.length);
  e = env();                                                  // failed before a Back (WebKit): at the next Back, after the pageshow
  e.loads[0].rej(cut()); await tick(); e.flush();
  if (e.loads.length !== 1) bad.push("failed, asked again without a Back: " + e.loads.length);
  e.fire("pageshow", { persisted: false }); e.flush();
  if (e.loads.length !== 1) bad.push("asked again after an ordinary load: " + e.loads.length);
  e.fire("pageshow", { persisted: true });
  if (e.loads.length !== 1) bad.push("asked during the pageshow: " + e.loads.length);
  e.fire("pageshow", { persisted: true }); e.flush();
  if (e.loads.length !== 2) bad.push("failed, then two Backs: " + e.loads.length + " asks, not 2");
  e = env();                                                  // failed after a Back (Chrome): at once, after a timer
  e.fire("pageshow", { persisted: true }); e.flush();
  e.loads[0].rej(cut()); await tick();
  if (e.loads.length !== 1) bad.push("failed after a Back, asked in the same task: " + e.loads.length);
  e.flush();
  if (e.loads.length !== 2) bad.push("failed after a Back, not asked again: " + e.loads.length);
  e.loads[1].rej(cut()); await tick(); e.flush();             // the new try fails too: it waits for the next Back
  if (e.loads.length !== 2) bad.push("the new try failed, asked again without a Back: " + e.loads.length);
  e.fire("pageshow", { persisted: true }); e.flush();
  if (e.loads.length !== 3) bad.push("the new try failed, not asked at the next Back: " + e.loads.length);
  e.loads[2].res(); await tick(); e.fire("pageshow", { persisted: true }); e.flush();
  if (e.loads.length !== 3 || e.errors !== 2) bad.push("after it came: " + e.loads.length + " asks, " + e.errors + " errors logged, not 3 and 2");
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
})().catch((err) => console.log("wrong: " + err.message));
JS
check "the land after Back (site/app.js in node): the land's file cut by the back-forward cache is asked for again, at the next Back when it failed before it, at once when it fails after one, never during the pageshow, after an ordinary load or once it came, and once per Back; every failure is logged" "$(node "$T/land.js" "$T/home.js" 2>&1)" "ok"
# The lists after Back (site/app.js): WebKit cuts /api/missions and /api/events too when the visitor leaves before they
# have come, and the page came back with no mission and COULDN'T LOAD THE CLEANUPS (no globe at all after a visit to
# /apply/) until a reload. The first screen is built once from them, so a page whose list was cut loads again: at the
# next Back when the cut came before it, at once when it came after one, never during the pageshow itself (a timer),
# once per cut, and only once a HEAD of the page itself answers (a static file, no Function): with no answer (offline,
# the site out of reach) or an error status, loading again gave the browser's error page instead of the page, so the
# page stays and the next Back tries again. Only once in a row: a page that was itself loaded again (the browser's
# navigation type says reload; nothing is kept on the device, which this site never uses) never loads again for a cut,
# so a page whose lists a blocker stops does not load again on every Back; a browser with only the old
# performance.navigation, or none at all, works the same. Only a TypeError is a cut: an error status, an answer that is
# not JSON or an abort never reloads, and the lines that turn those into plain errors are pinned. The three requests of the first screen (/api/missions, the receipts' list and /api/events)
# report a failure to it, each with the Backs counted when it was asked for.
cat > "$T/lists.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  // ---------- the lists after Back"), b = s.indexOf("  // ---------- end of the lists after Back ----------");
if (a < 0 || b < a) { console.log("wrong: the block is missing"); process.exit(); }
if (/localStorage|sessionStorage|indexedDB|document\.cookie|cookieStore|\bcaches\b|navigator\.storage/.test(s.slice(a, b))) { console.log("wrong: the block keeps something on the device"); process.exit(); }
const calls = [
  ['  const missionsP = fetch("/api/missions", fresh).then((r) => (r.ok ? r.json() : null)).catch((e) => { listLost(e, 0); return null; }); // null: failed\n', "/api/missions"],
  ['    loadFailed = true;\n    listLost(e, 0);\n    console.error("Could not load events:", e);\n', "the receipts' list"],
  ['  const apiFrom = listBacks;\n  try {\n    const r = await fetch("/api/events", fresh);\n', "/api/events, its Backs"],
  ['  } catch (e) { apiFailed = true; listLost(e, apiFrom); }\n', "/api/events, its failure"],
  ['    if (!r.ok) throw new Error("manifest HTTP " + r.status);\n', "the receipts' list's error status"],
  ['      if (!Array.isArray(api)) throw new Error("not a list");\n', "/api/events that is not a list"],
  ['    } else if (r.status !== 404 && r.status !== 503) apiFailed = true;\n', "/api/events' error status"]];
for (const [t, what] of calls) if (s.split(t).length !== 2 || s.indexOf(t) < b) { console.log("wrong: " + what + " is not once after the block as it should be"); process.exit(); }
const tick = () => new Promise((r) => setImmediate(r));
const OK = () => Promise.resolve({ ok: true, status: 200 });
const put = (k, v) => Object.defineProperty(globalThis, k, { value: v, configurable: true, writable: true });
// o.nav: how the browser says the page was loaded (navigate, reload, back_forward); "old": no navigation entry, only
// performance.navigation.type (o.old, 1 for a reload); "throws": the call throws; "none": no performance at all
function env(o = {}) {
  const e = { on: {}, timers: [], reloads: 0, probes: [], held: [], answer: o.answer || OK };
  e.fire = (t, ev) => (e.on[t] || []).slice().forEach((f) => f(ev));
  e.flush = async () => { for (let i = 0; i < 4; i++) { while (e.timers.length) e.timers.shift()(); await tick(); } };
  const add = (t, f, o2) => (e.on[t] = e.on[t] || []).push(o2?.once ? function g(ev) { e.on[t] = e.on[t].filter((x) => x !== g); f(ev); } : f);
  const nav = o.nav || "navigate";
  e.clock = 0;                                                       // performance.now(): 16 ms a frame, more by hand
  const now = () => e.clock;
  const performance = nav === "none" ? { now } : nav === "throws" ? { now, getEntriesByType: () => { throw new Error("no"); } }
    : { now, getEntriesByType: (t) => (t === "navigation" && nav !== "old" ? [{ type: nav }] : []), navigation: { type: o.old || 0 } };
  // location.reload() fires its own navigate event, where the browser has one: before it returns (Chrome) or, with
  // o.late, in a microtask after it (WebKit); e.ys: the page's scroll at each load
  e.ys = [];
  // (with o.noReloadEvent, never: WebKit drops the reload and its event when a step comes first); e.loadFrames: the
  // frame of each load
  const location = { pathname: "/", href: "https://sapu.earth/", reload: () => { e.reloads++; e.ys.push(e.y); e.loadFrames.push(e.frame);
    if (o.noReloadEvent) return;
    const ev = () => e.go(false, { navigationType: "reload", url: "https://sapu.earth/" }); if (o.late) queueMicrotask(ev); else ev(); } };
  const fetch = (u, init) => { e.probes.push(String(u) + " " + init?.method + " " + init?.cache); return e.answer(); };
  // the browser's navigate events (window.navigation; o.noNav: a browser without it): e.go(false) is a link to another
  // page (o2.url, o2.downloadRequest, o2.navigationType "traverse" for the browser's Back to another page), e.go(true) a
  // step inside the page (a post, a #; o2.navigationType "traverse": a step back); e.stopped() is navigateerror (a link
  // stopped, or a step taken after it, as Chrome 149 fires them)
  e.navOn = { navigate: [], navigateerror: [] };
  const navigation = o.noNav ? undefined : { addEventListener: (t, f) => (e.navOn[t] = e.navOn[t] || []).push(f), currentEntry: { key: "here" } };
  e.go = (sameDocument, o2 = {}) => e.navOn.navigate.forEach((f) => f({ navigationType: o2.navigationType || "push",
    downloadRequest: o2.noDl || o2.downloadRequest === undefined ? (o2.noDl ? undefined : null) : o2.downloadRequest,
    destination: { sameDocument, url: o2.url || (sameDocument ? "https://sapu.earth/#main" : "https://sapu.earth/apply/"), key: o2.key || "here" } }));
  e.stopped = () => e.navOn.navigateerror.forEach((f) => f({}));
  // frames (requestAnimationFrame, run with the timers) and the page's scroll (scrollY): e.scroll lists where a scroll
  // already on its way stands at each next frame (a smooth scroll back up)
  e.y = 0; e.scroll = []; e.frame = 0; e.loadFrames = [];
  const frame = (f) => e.timers.push(() => { e.frame++; e.clock += 16; if (e.scroll.length) e.y = e.scroll.shift(); f(); });
  Object.defineProperty(globalThis, "scrollY", { get: () => e.y, configurable: true });
  // the page's visibility: e.away() (another app or tab in front), e.here() (the page in front again)
  const document = { hidden: false, get visibilityState() { return this.hidden ? "hidden" : "visible"; }, addEventListener: (t, f, o2) => add(t, f, o2) };
  e.away = () => { document.hidden = true; e.fire("visibilitychange", {}); };
  e.here = () => { document.hidden = false; e.fire("visibilitychange", {}); };
  for (const [k, v] of Object.entries({ addEventListener: add, location, performance, fetch, navigation, document, requestAnimationFrame: frame })) put(k, v);
  put("window", globalThis);
  e.lost = new Function("addEventListener", "setTimeout", "location", "performance", "fetch", s.slice(a, b) + "\nreturn listLost;")(
    add, (f) => e.timers.push(f), location, performance, fetch);
  return e;
}
(async () => {
  const bad = [], cut = () => new TypeError("Load failed"), st = (e) => e.reloads + " loads, " + e.probes.length + " asks";
  const answer = (what) => { const f = e.held.shift(); if (f) f(); else bad.push(what + ": no HEAD was asked"); };
  let e = env();                                                     // came: never loads again
  e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads || e.probes.length) bad.push("came, then a Back: " + st(e));
  e = env();                                                         // cut before a Back (WebKit): at the next Back, once the page answers
  e.lost(cut(), 0); await e.flush();
  if (e.reloads || e.probes.length) bad.push("cut, without a Back: " + st(e));
  e.fire("pageshow", { persisted: false }); await e.flush();
  if (e.reloads || e.probes.length) bad.push("cut, then an ordinary load: " + st(e));
  e.fire("pageshow", { persisted: true });
  if (e.reloads || e.probes.length) bad.push("during the pageshow: " + st(e));
  await e.flush();
  if (e.reloads !== 1 || e.probes.join() !== "/ HEAD no-store") bad.push("cut, then a Back: " + st(e) + " (" + e.probes.join() + ")");
  // the load did not happen (the page here stays, as when the browser dropped it for an address typed while the HEAD
  // was on its way): the next Back tries again, once
  e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads !== 2 || e.probes.length !== 2) bad.push("a load the browser dropped, then a Back: " + st(e));
  e = env();                                                         // two lists cut: one load
  e.lost(cut(), 0); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads !== 1 || e.probes.length !== 1) bad.push("two cuts, then a Back: " + st(e));
  e = env();                                                         // cut after a Back (Chrome): at once, after a timer
  e.fire("pageshow", { persisted: true }); await e.flush();
  e.lost(cut(), 0);
  if (e.reloads || e.probes.length) bad.push("cut after a Back, in the same task: " + st(e));
  e.lost(cut(), 0); await e.flush();                                 // its other list too: still one
  if (e.reloads !== 1 || e.probes.length !== 1) bad.push("two cuts after a Back: " + st(e));
  e = env();                                                         // asked for after a Back and cut before the next: at the next one
  e.fire("pageshow", { persisted: true }); await e.flush();
  e.lost(cut(), 1); await e.flush();
  if (e.reloads || e.probes.length) bad.push("asked for after a Back and cut, at once: " + st(e));
  e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads !== 1) bad.push("asked for after a Back and cut, then a Back: " + st(e));
  for (const err of [new SyntaxError("Unexpected token"), new Error("manifest HTTP 500"), { name: "AbortError" }, null, undefined]) {
    e = env();                                                       // no cut: never loads again
    e.lost(err, 0); e.fire("pageshow", { persisted: true }); await e.flush(); e.lost(err, 0); await e.flush();
    if (e.reloads || e.probes.length) bad.push("after " + (err && err.name) + ": " + st(e));
  }
  // no answer at the Back (offline, the site out of reach) or an error status: the page stays, the next Back tries again
  for (const [what, answer] of [["no answer", () => Promise.reject(cut())], ["an error status", () => Promise.resolve({ ok: false, status: 503 })]]) {
    e = env({ answer });
    e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads || e.probes.length !== 1) bad.push(what + ", at a Back: " + st(e));
    e.answer = OK; e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 2) bad.push(what + ", then a Back with an answer: " + st(e));
    e = env({ answer });                                             // the same for a cut after a Back
    e.fire("pageshow", { persisted: true }); await e.flush(); e.lost(cut(), 0); await e.flush();
    if (e.reloads || e.probes.length !== 1) bad.push(what + ", cut after a Back: " + st(e));
    e.answer = OK; e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 2) bad.push(what + ", cut after a Back, then a Back with an answer: " + st(e));
  }
  // a page that was itself loaded again (this, or the visitor): a cut there loads nothing again, before or after a Back,
  // also where the browser has only the old performance.navigation; any other load may
  for (const o of [{ nav: "reload" }, { nav: "old", old: 1 }]) {
    e = env(o);
    e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
    e.lost(cut(), 1); await e.flush(); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads || e.probes.length) bad.push("a page loaded again (" + JSON.stringify(o) + "), cut again: " + st(e));
  }
  for (const o of [{ nav: "back_forward" }, { nav: "old", old: 0 }, { nav: "old", old: 2 }, { nav: "throws" }, { nav: "none" }]) {
    e = env(o);
    e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 1) bad.push("a page loaded by " + JSON.stringify(o) + ", cut: " + st(e));
  }
  for (const o of [{ nav: "reload" }, { nav: "old", old: 1 }]) {     // ... nor at once, for a cut after a Back (Chrome)
    e = env(o);
    e.fire("pageshow", { persisted: true }); await e.flush(); e.lost(cut(), 0); await e.flush();
    if (e.reloads || e.probes.length) bad.push("a page loaded again (" + JSON.stringify(o) + "), cut after a Back: " + st(e));
  }
  // a link the visitor followed since the page came back goes first (Chrome dropped it for the load): the load waits for
  // it, and if it goes, the next Back tries again; a step inside the page, a mailto: link and a download do not count,
  // and a # or a post's step taken after the link lets it go on (Chrome)
  const held = () => new Promise((r) => e.held.push(() => r({ ok: true, status: 200 })));
  for (const [what, go, want] of [
    ["a link to another page", () => e.go(false), 0],
    ["the browser's Back to another page", () => e.go(false, { navigationType: "traverse" }), 0],
    ["a step inside the page", () => e.go(true), 1],
    ["a mailto: link", () => e.go(false, { url: "mailto:hello@sapu.earth" }), 1],
    ["a download", () => e.go(false, { downloadRequest: "" }), 1],
    ["a link in a browser whose navigate event has no downloadRequest", () => e.go(false, { noDl: true }), 0],
    ["a link, then a # after it", async () => { e.go(false); e.stopped(); await null; e.go(true); }, 0],
    ["a link, then a post's step after it", async () => { e.go(false); e.stopped(); await null; e.go(true, { url: "https://sapu.earth/#m-2" }); }, 0],
    ["a link, then a second one", async () => { e.go(false); e.stopped(); await null; e.go(false, { url: "https://sapu.earth/crews" }); }, 0],
    ["a link, then Stop", () => { e.go(false); e.stopped(); }, 1],
    ["a link, then a step back (the browser's Back over a step, the post's ✕)", async () => { e.go(false); e.stopped(); await null; e.go(true, { navigationType: "traverse" }); }, 1]]) {
    e = env({ answer: held });
    e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();      // the HEAD is on its way
    await go(); await e.flush(); answer(what);
    await e.flush();
    if (e.reloads !== want || e.probes.length !== 1) bad.push(what + ", while the HEAD was on its way: " + st(e));
    if (want) continue;
    e.answer = OK; e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 2) bad.push(what + ", while the HEAD was on its way, then a Back: " + st(e));
  }
  // the HEAD answered while the link was on its way: the load goes ahead once the link stops with the visitor still
  // here (Stop: navigateerror and nothing after it; a step back; a return from an app that took the link over), not
  // for a # after it, nor for a link that says nothing when it ends (a 204, a file), which waits for the next Back
  for (const [what, then, want] of [
    ["Stop", () => e.stopped(), 1],
    ["a step back (the browser's Back over a step, the post's ✕)", async () => { e.stopped(); await null; e.go(true, { navigationType: "traverse" }); }, 1],
    ["a return from an app that took the link over", () => { e.away(); e.here(); }, 1],
    ["a # after it", async () => { e.stopped(); await null; e.go(true); }, 0],
    ["another link after it", async () => { e.stopped(); await null; e.go(false, { url: "https://sapu.earth/crews" }); }, 0],
    ["nothing (a 204, a file)", () => {}, 0]]) {
    e = env({ answer: held });
    e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
    e.go(false); answer("a link, then the HEAD's answer, then " + what); await e.flush();
    if (e.reloads) bad.push("a link, then the HEAD's answer: " + st(e));
    await then(); await e.flush();
    if (e.reloads !== want || e.probes.length !== 1) bad.push("a link the load waited for, then " + what + ": " + st(e));
    if (want) { e.away(); e.here(); await e.flush(); }                // the load is on its way: a return asks for none more
    if (e.reloads !== want || e.probes.length !== 1) bad.push("a link the load waited for, then " + what + ", then a return: " + st(e));
    e.fire("pagehide", {}); e.here();                                // gone; WebKit and Chrome show a page coming back
    if (e.reloads !== want) bad.push("a link the load waited for, then " + what + ", then the page left and shown: " + st(e));
  }
  // the link went: the page coming back loads nothing in its visibilitychange (it comes before the pageshow), its
  // Back's HEAD does, on every Back
  e = env({ answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  for (let i = 1; i <= 2; i++) {
    e.go(false); answer("a link that went (" + i + ")"); await e.flush();   // the HEAD answered while the link was on its way
    const r0 = e.reloads, p0 = e.probes.length;
    e.away(); e.fire("pagehide", {}); e.here();
    if (e.reloads !== r0) bad.push("a link that went (" + i + "), then the page shown again: " + st(e));
    e.answer = OK; e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== r0 + 1 || e.probes.length !== p0 + 1) bad.push("a link that went (" + i + "), then a Back: " + st(e));
    e.answer = held; e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();   // that load did not happen: a Back
  }
  // no answer while a link is on its way (offline): the link stops, and the page stays (the next Back tries again)
  {
    const failing = () => new Promise((_, no) => e.held.push(() => no(cut())));
    for (const [what, then] of [["Stop", () => e.stopped()], ["a step back", async () => { e.stopped(); await null; e.go(true, { navigationType: "traverse" }); }]]) {
      e = env({ answer: failing });
      e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
      e.go(false); answer("no answer while a link was on its way, then " + what); await e.flush();
      await then(); await e.flush();
      if (e.reloads || e.probes.length !== 1) bad.push("no answer while a link was on its way, then " + what + ": " + st(e));
    }
  }
  // a step back after the HEAD's answer: the load waits for the step (a load asked for in the step's own navigate
  // event reloaded the address being left, the post closed with ✕ open again, Chrome 149) and for its scroll (the
  // smooth scroll back up: a load during it landed half way down); a link tapped meanwhile goes first
  e = env({ answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false); answer("a step back after the answer"); await e.flush();
  e.y = 1688; e.scroll = [873, 600, 600, 600, 300, 300, 300, 120, 30, 0];   // with two stutters of three frames on the way
  e.stopped(); await null; e.go(true, { navigationType: "traverse" });
  if (e.reloads) bad.push("a step back after the answer: a load during the step's own navigate event");
  await null; await null;
  if (e.reloads) bad.push("a step back after the answer: a load in a microtask of the step");
  await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back after the answer: " + st(e) + " at " + e.ys.join());
  // a step back, then the HEAD's answer during its scroll (no link): the load waits for the page to stand still too
  e = env({ answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.y = 1688; e.scroll = [873, 600, 600, 600, 300, 300, 300, 120, 30, 0];
  e.go(true, { navigationType: "traverse" }); answer("a step back, then the answer"); await null; await null;
  if (e.reloads) bad.push("a step back, then the HEAD's answer during its scroll: a load at once");
  await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back, then the HEAD's answer during its scroll: " + st(e) + " at " + e.ys.join());
  // the same with the scroll starting two frames late (a busy page): still frames are counted from the frames, not
  // from when the wait began
  e = env({ answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false); answer("a step back after the answer, the scroll late"); await e.flush();
  e.y = 1688; e.scroll = [1688, 1688, 873, 600, 600, 600, 300, 0];
  e.stopped(); await null; e.go(true, { navigationType: "traverse" }); await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back after the answer, its scroll two frames late: " + st(e) + " at " + e.ys.join());
  e = env({ answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false); answer("a step back, then a link"); await e.flush();
  e.stopped(); await null; e.go(true, { navigationType: "traverse" }); e.stopped(); await null; e.go(false, { url: "https://sapu.earth/crews" }); await e.flush();
  if (e.reloads) bad.push("a step back, then a link before the step was over: " + st(e));
  e.stopped(); await e.flush();
  if (e.reloads !== 1) bad.push("a step back, then a link, then Stop: " + st(e));
  // the page's own load, its navigate event before location.reload() returns (Chrome) or after (WebKit): cut by a step
  // back it goes again after the step (never in the step's own event or a microtask of it); cut by a link it waits for
  // the link (and goes once that stops, or at the next Back); cut by a mailto: link or stopped with Stop it waits for a
  // return to the page or the next Back, and a later step back does not send it; a download or a # during it lets it go
  // on; a reload of the visitor's during it is the visitor's; the browser's Back to another page takes the page away
  for (const late of [false, true]) {
    const W = late ? " (its event after reload() returns)" : "";
    const own = async () => { e = env({ late }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
      if (e.reloads !== 1) bad.push("the page's own load" + W + ": " + st(e)); };
    await own(); e.stopped(); await null; e.go(true, { navigationType: "traverse" });
    if (e.reloads !== 1) bad.push("the page's own load cut by a step back" + W + ": a load in the step's own event");
    await null; await null;
    if (e.reloads !== 1) bad.push("the page's own load cut by a step back" + W + ": a load in a microtask of the step");
    await e.flush();
    if (e.reloads !== 2) bad.push("the page's own load cut by a step back" + W + ": " + st(e));
    await own(); e.stopped(); await null; e.go(false, { url: "https://sapu.earth/apply/" }); await e.flush();
    if (e.reloads !== 1) bad.push("the page's own load cut by a link, at once" + W + ": " + st(e));
    e.stopped(); await e.flush();
    if (e.reloads !== 2) bad.push("the page's own load cut by a link, then the link stopped" + W + ": " + st(e));
    await own(); e.stopped(); await null; e.go(false, { url: "https://sapu.earth/apply/" }); await e.flush();
    e.fire("pagehide", {}); e.here(); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 2 || e.probes.length !== 2) bad.push("the page's own load cut by a link that went, then a Back" + W + ": " + st(e));
    await own(); e.stopped(); await null; e.go(false, { url: "mailto:hello@sapu.earth" }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 1) bad.push("the page's own load cut by a mailto: link" + W + ": " + st(e));
    e.away(); e.here(); await e.flush();
    if (e.reloads !== 2 || e.probes.length !== 2) bad.push("the page's own load cut by a mailto: link, then a return" + W + ": " + st(e));
    await own(); e.go(false, { downloadRequest: "" }); e.away(); e.here(); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 1) bad.push("the page's own load, then a download and a return" + W + ": " + st(e));
    await own(); e.stopped(); await e.flush();
    if (e.reloads !== 1) bad.push("the page's own load stopped" + W + ": " + st(e));
    e.go(true); e.stopped(); await null; e.go(true, { navigationType: "traverse" }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 1) bad.push("the page's own load stopped, then a step back" + W + ": " + st(e));
    e.away(); e.here(); await e.flush();
    if (e.reloads !== 2 || e.probes.length !== 2) bad.push("the page's own load stopped, then a return" + W + ": " + st(e));
    await own(); e.stopped(); await e.flush(); e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();
    if (e.reloads !== 2 || e.probes.length !== 2) bad.push("the page's own load stopped, then a Back" + W + ": " + st(e));
    await own(); e.stopped(); await null; e.go(true); await e.flush();
    if (e.reloads !== 1) bad.push("the page's own load, then a #" + W + ": " + st(e));
    e.stopped(); await null; e.go(true, { navigationType: "traverse" }); await e.flush();
    if (e.reloads !== 2) bad.push("the page's own load, then a #, then a step back" + W + ": " + st(e));
    await own(); e.go(false, { navigationType: "reload", url: "https://sapu.earth/" }); e.stopped(); await null;
    e.go(true, { navigationType: "traverse" }); await e.flush();
    if (e.reloads !== 1) bad.push("a reload of the visitor's during the page's own, then a step back" + W + ": " + st(e));
    // left during its own load by a link to another site (WebKit fires no navigate event for it) and back: the Back's
    // HEAD decides, not WebKit's step that comes after the pageshow
    await own(); e.answer = held;
    e.fire("pagehide", {}); e.here(); e.fire("pageshow", { persisted: true }); e.go(true, { navigationType: "traverse" }); await e.flush();
    if (e.reloads !== 1 || e.probes.length !== 2) bad.push("left during the page's own load, then a Back and WebKit's step" + W + ": " + st(e));
    answer("left during the page's own load, then a Back" + W); await e.flush();
    if (e.reloads !== 2) bad.push("left during the page's own load, then a Back's answer" + W + ": " + st(e));
  }
  // WebKit: its own reload stopped with Stop (WebKit fires no navigateerror): a return does not try again, the next
  // step back loads it; a step that comes right after location.reload() drops the reload before its navigate event:
  // the page still counts the reload as its own, so the step sends it again; a link then (not the reload's event)
  // holds the load, which goes once the link stops
  e = env({ late: true }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.away(); e.here(); await e.flush();
  if (e.reloads !== 1 || e.probes.length !== 1) bad.push("WebKit: the page's own load stopped (nothing said), then a return: " + st(e));
  e.go(true, { navigationType: "traverse" }); await e.flush();
  if (e.reloads !== 2) bad.push("WebKit: the page's own load stopped (nothing said), then a step back: " + st(e));
  e = env({ noReloadEvent: true }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(true, { navigationType: "traverse" }); await e.flush();
  if (e.reloads !== 2) bad.push("a step that dropped the page's own load before its event: " + st(e));
  e = env({ noReloadEvent: true }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false, { url: "https://sapu.earth/apply/" }); await e.flush();
  if (e.reloads !== 1) bad.push("a link that dropped the page's own load before its event: " + st(e));
  e.stopped(); await e.flush();
  if (e.reloads !== 2) bad.push("a link that dropped the page's own load before its event, then Stop: " + st(e));
  // a load of the page's own whose event never came, then a Back with no answer: a later reload of the visitor's is
  // the visitor's (the Back forgets the page's ask), so a step back after it sends nothing
  e = env({ noReloadEvent: true }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.answer = () => Promise.reject(cut()); e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false, { navigationType: "reload", url: "https://sapu.earth/" }); e.stopped(); await null; e.go(true, { navigationType: "traverse" }); await e.flush();
  if (e.reloads !== 1) bad.push("a reload of the visitor's after a Back, then a step back: " + st(e));
  // a step back, then the HEAD's answer before the step's scroll has moved (Chrome moves it two frames after the step):
  // the answer waits for the step's scroll too
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.y = 1688; e.scroll = [1688, 1686, 1500, 900, 300, 0];
  e.go(true, { navigationType: "traverse" }); answer("a step back, then the answer before its scroll moved"); await tick(); await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back, then the HEAD's answer before its scroll moved: " + st(e) + " at " + e.ys.join());
  // once a step back's wait is over, or the page was left during it and came back, the answer on a still page loads
  // at the next frame again
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();   // the HEAD on its way
  e.go(true, { navigationType: "traverse" }); await e.flush();                                              // a step back, its wait over
  { const f0 = e.frame; answer("after a step back's wait"); await e.flush();
    if (e.reloads !== 1 || e.loadFrames.join() !== String(f0 + 1)) bad.push("the answer on a still page after a step back's wait: " + st(e) + ", " + (e.loadFrames[0] - f0) + " frames after"); }
  e = env({ answer: held }); e.lost(cut(), 0); e.go(true, { navigationType: "traverse" });
  e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();
  { const f0 = e.frame; answer("left during a step back's wait"); await e.flush();
    if (e.reloads !== 1 || e.loadFrames.join() !== String(f0 + 1)) bad.push("the answer on a still page after a Back that left a step's wait: " + st(e) + ", " + (e.loadFrames[0] - f0) + " frames after"); }
  // the step WebKit takes to the page's own address right after a Back is no step back: the Back's answer on a still
  // page loads at the next frame
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); e.timers.shift()();   // the Back's HEAD asked
  e.go(true, { navigationType: "traverse", url: "https://sapu.earth/" });                                  // WebKit's own step
  { const f0 = e.frame; answer("after WebKit's own step at a Back"); await tick(); await e.flush();         // answered in its wait
    if (e.reloads !== 1 || e.loadFrames.join() !== String(f0 + 1)) bad.push("the answer on a still page after WebKit's own step at a Back: " + st(e) + ", " + (e.loadFrames[0] - f0) + " frames after"); }
  // a step back between two entries at the same address a while after a Back (after SEE THE RECEIPTS, a post and its
  // ✕) is a step back with its scroll: the answer before that scroll moved waits for it too
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); e.timers.shift()();   // the Back's HEAD asked
  e.clock += 300; e.y = 899; e.scroll = [899, 897, 700, 300, 0];
  e.go(true, { navigationType: "traverse", url: "https://sapu.earth/" }); answer("a step back to the same address"); await tick(); await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back to the same address a while after a Back, the answer before its scroll moved: " + st(e) + " at " + e.ys.join());
  // the same right after a Back (a quick second Back between two entries at /): a step to another entry is a step back
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); e.timers.shift()();   // the Back's HEAD asked
  e.clock += 60; e.y = 899; e.scroll = [899, 897, 700, 300, 0];
  e.go(true, { navigationType: "traverse", url: "https://sapu.earth/", key: "before" }); answer("a quick second Back to another entry at /"); await tick(); await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a quick second Back to another entry at the same address, the answer before its scroll moved: " + st(e) + " at " + e.ys.join());
  // Stop of a link, not of the page's own load, marks no cut: on a page whose lists came a return asks nothing, and with
  // a HEAD on its way a return asks no second one
  e = env(); e.go(false); e.stopped(); await e.flush(); e.away(); e.here(); await e.flush();
  if (e.reloads || e.probes.length) bad.push("a link stopped on a page whose lists came, then a return: " + st(e));
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false); e.stopped(); await e.flush(); e.away(); e.here(); await e.flush();
  if (e.probes.length !== 1) bad.push("a HEAD on its way, a link stopped, then a return: " + st(e));
  // the HEAD's answer on a page that stands still loads at the next frame; a step back while the answer's wait runs
  // (the page moving) starts the wait again after the step; a mailto: while the HEAD is on its way frees nothing
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  { const f0 = e.frame; answer("a still page"); await e.flush();
    if (e.reloads !== 1 || e.loadFrames.join() !== String(f0 + 1)) bad.push("the HEAD's answer on a still page: " + st(e) + ", " + (e.loadFrames[0] - f0) + " frames after"); }
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.y = 500; e.scroll = [480, 480, 480, 480, 900, 600, 300, 0];
  answer("a step back during the answer's wait"); await tick();
  for (let i = 0; i < 3 && e.timers.length; i++) e.timers.shift()();  // three of its frames: 480, 480, 480
  e.go(true, { navigationType: "traverse" });                          // a step back before its fourth
  await e.flush();
  if (e.reloads !== 1 || e.ys.join() !== "0") bad.push("a step back during the answer's wait: " + st(e) + " at " + e.ys.join());
  e = env({ answer: held }); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.go(false, { url: "mailto:hello@sapu.earth" }); e.away(); e.here(); await e.flush();
  if (e.probes.length !== 1) bad.push("a mailto: while the HEAD is on its way, then a return: " + st(e));
  answer("a mailto: while the HEAD is on its way"); await e.flush();
  if (e.reloads !== 1) bad.push("a mailto: while the HEAD is on its way, then its answer: " + st(e));
  // a HEAD that got no answer (offline, or dropped by WebKit for a link) is tried again when the visitor comes back to
  // the page from another app or tab, after a Back's pageshow, never twice at once
  e = env({ answer: () => Promise.reject(cut()) });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads || e.probes.length !== 1) bad.push("no answer at a Back: " + st(e));
  e.answer = OK; e.away(); e.here(); await e.flush();
  if (e.reloads !== 1 || e.probes.length !== 2) bad.push("no answer at a Back, then a return to the page: " + st(e));
  e = env({ answer: () => Promise.reject(cut()) });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.answer = held; e.away(); await e.flush();
  if (e.probes.length !== 1) bad.push("a HEAD asked while the page was hidden: " + st(e));
  e.fire("pagehide", {}); e.here(); await null; e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.probes.length !== 2) bad.push("no answer at a Back, then a Back (the page shown, then its pageshow): " + st(e));
  e.away(); e.here(); await e.flush();
  if (e.probes.length !== 2) bad.push("a return to the page while its HEAD is on its way: " + st(e));
  answer("no answer, then a Back"); await e.flush();
  if (e.reloads !== 1) bad.push("no answer, then a Back with an answer: " + st(e));
  e = env();                                                         // a return to the page with nothing waiting: nothing
  e.away(); e.here(); e.stopped(); e.go(true, { navigationType: "traverse" }); await e.flush();
  if (e.reloads || e.probes.length) bad.push("a step back, Stop or a return with nothing waiting: " + st(e));
  e = env();                                                         // a cut, then a step back or Stop: nothing yet,
  e.lost(cut(), 0); e.stopped(); e.go(true, { navigationType: "traverse" }); await e.flush();   // then a return: the load
  if (e.reloads || e.probes.length) bad.push("a cut, then a step back or Stop: " + st(e));
  e.away(); e.here(); await e.flush();
  if (e.reloads !== 1 || e.probes.length !== 1) bad.push("a cut, then a return to the page (an app took the link over): " + st(e));
  e = env();                                                         // a cut, a link the browser told of, a return: the
  e.lost(cut(), 0); e.go(false); e.away(); e.here(); await e.flush();   // load waits for the link; it stops: the load
  if (e.reloads || e.probes.length !== 1) bad.push("a cut, a link, then a return while the link is on its way: " + st(e));
  e.stopped(); await e.flush();
  if (e.reloads !== 1) bad.push("a cut, a link, then a return, then Stop: " + st(e));
  e = env({ answer: held });                                         // a HEAD answered after the page was left and came back
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  e.fire("pagehide", {}); e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.probes.length !== 2) bad.push("left and back while the HEAD was on its way: " + st(e));
  answer("left and back while the HEAD was on its way"); await e.flush();
  if (e.reloads) bad.push("a HEAD answered after the page was left and came back: " + st(e));
  e.lost(cut(), 1); await e.flush();                                 // its HEAD is still on its way: none more
  if (e.probes.length !== 2) bad.push("a cut while the Back's HEAD is on its way: " + st(e));
  answer("the HEAD of the Back after it"); await e.flush();
  if (e.reloads !== 1 || e.probes.length !== 2) bad.push("the HEAD of the Back after it: " + st(e));
  e = env();                                                         // a link tapped after the Back, before Chrome reported the cut
  e.fire("pageshow", { persisted: true }); await e.flush(); e.go(false); e.lost(cut(), 0); await e.flush();
  if (e.reloads || e.probes.length !== 1) bad.push("a link followed after the Back, then a cut: " + st(e));
  e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads !== 1) bad.push("a link followed after the Back, then a cut, then a Back: " + st(e));
  e = env();                                                         // the visitor left by a link, then came back
  e.go(false); e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush();
  if (e.reloads !== 1) bad.push("a link followed before the last Back: " + st(e));
  e = env({ noNav: true, answer: held });
  e.lost(cut(), 0); e.fire("pageshow", { persisted: true }); await e.flush(); answer("a browser without the navigate event"); await e.flush();
  if (e.reloads !== 1) bad.push("a browser without the navigate event: " + st(e));
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
})().catch((err) => console.log("wrong: " + err.message));
JS
check "the lists after Back (site/app.js in node): a page whose /api/missions, receipts' list or /api/events was cut on its way loads again once a HEAD of the page itself answers (no Function), at the next Back when the cut came before it, at once when it came after one, never during the pageshow, once for two cuts and once per cut; with no answer or an error status there (offline, the site out of reach) it stays and the next Back tries again; a page that was itself loaded again never loads again for a cut, before or after a Back (the browser's navigation type, old or new; nothing kept on the device); a link the visitor followed since the page came back goes first, while the HEAD is on its way or before: the load waits for it, the next Back tries again if it went, and the load goes ahead once it stops with the visitor still here (Stop, a step back, a return from an app), not for a # or a post's step after it (a step inside the page, a mailto: link and a download do not count), every load only once the page stands still (after a step back's scroll, counted in frames, never in the step's own navigate event or a microtask of it), unless a link was tapped since; the page's own load, its navigate event before or after location.reload() returns, cut by a step back goes again, cut by a link waits for it, cut by a mailto: link or stopped with Stop (in Chrome) waits for a return or the next Back, stopped with nothing said (WebKit) waits for the next step back or Back, dropped before its event by a step is sent again after it, a download or a # lets it go on, and a reload of the visitor's stays the visitor's; the HEAD's answer on a still page loads at the next frame, during a step back's wait only once the step's scroll is over (WebKit's own step to the page's own entry within 150 ms of a Back is none, a step to another entry at the same address is one, also right after a Back), and a step back during a wait starts it again; Stop of a link marks no cut; on a return from another app or tab a load waiting for a link goes ahead, and a cut the page knows of is tried again (never while hidden, after a Back's own pageshow, never twice at once), its load waiting for a link the browser told of; a HEAD answered after the page was left and came back counts not, and a load the browser dropped is tried again at the next Back; an error status, an answer that is not JSON or an abort never reloads" "$(node "$T/lists.js" "$T/home.js" 2>&1)" "ok"
# A finger's tap next to a receipt dot (site/app.js, finger taps next to a receipt dot): the press tells a finger from a
# mouse, not the click, since on an iPhone the click after a finger's tap says mouse (WebKit) and a tap on a dot opened
# nothing there (iOS Simulator, 2026-11-17); and a dot no one can see (under the tap hint's strip, or under a box over
# the globe that takes taps, or with its middle off the screen) is not found by a tap next to it. receiptsNear and the
# click handler run here as written, with a fake globe.
cat > "$T/taps.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
const bad = [];
const pl = '  addEventListener("pointerdown", (ev) => {\n    pressType = ev.pointerType;\n';   // where the click handler starts
if (s.split(pl).length !== 2) bad.push("not once: " + pl.trim());
const a = s.indexOf("  const REACH = 36;\n"), b = s.indexOf("\n  // A finger has no hover.", a);
if (a < 0 || b < 0) { console.log("wrong: receiptsNear is missing"); process.exit(); }
const block = s.slice(a, b + 1);
// a fake globe seen from above lat 0, lng 0: a degree is 10 px, the point (0, 0) is at (100, 100) in #globe, and #globe
// stands at (10, 20) on a screen 390 x 844; c is 100 px away and far is on the far side. geo has a point for each spot
// of a receipt ({ of, location }); m is one receipt at two spots, (0, -1) and (0, -1.5), 10 and 15 px from the tap. By
// the screen's edges: d's middle is past the right edge (x 400 on the screen), e's is inside it (380); g's is above
// the top (y -10), f's is below it (30)
const R = (id) => ({ id }), A = R("a"), B = R("b"), C = R("c"), FAR = R("far"), M = R("m"), D = R("d"), E = R("e"), F = R("f"), G = R("g");
const geo = [{ of: A, location: { lat: 0, lng: 0 } }, { of: B, location: { lat: 0, lng: 2 } }, { of: C, location: { lat: 0, lng: 10 } },
  { of: FAR, location: { lat: 0, lng: 180 } }, { of: M, location: { lat: 0, lng: -1 } }, { of: M, location: { lat: 0, lng: -1.5 } },
  { of: D, location: { lat: 0, lng: 29 } }, { of: E, location: { lat: 0, lng: 27 } }, { of: F, location: { lat: 9, lng: 0 } }, { of: G, location: { lat: 13, lng: 0 } }];
const globe = { pointOfView: () => ({ lat: 0, lng: 0, altitude: 2 }), getScreenCoords: (lat, lng) => ({ x: 100 + lng * 10, y: 100 - lat * 10 }) };
const el = { getBoundingClientRect: () => ({ left: 10, top: 20 }), contains: (n) => !!n && n.inGlobe };
let stripAt = null, boxAt = null;                                  // the screen point under the strip, or under a box
const onStrip = (ev) => stripAt === ev.clientX + "," + ev.clientY;
const document = { elementFromPoint: (x, y) => (x < 0 || y < 0 || x >= 390 || y >= 844 ? null : boxAt === x + "," + y ? { inGlobe: false } : { inGlobe: true }) };
document.elementsFromPoint = (x, y) => { const t = document.elementFromPoint(x, y); return t ? [t] : []; };
globalThis.innerWidth = 390; globalThis.innerHeight = 844;          // the screen, for code that reads it
let near;
try {
  near = new Function("globe", "geo", "r3", "DOT_ALT", "dotLow", "el", "onStrip", "document", block + "\nreturn receiptsNear;")(
    globe, geo, (v) => Math.round(v * 1000) / 1000, 0.01, 1, el, onStrip, document);
} catch (err) { console.log("wrong: " + err.message); process.exit(); }
const ids = (x, y, r) => near(x, y, r).map((n) => n.e.id).join(",");
if (ids(100, 100) !== "a,m,b") bad.push("a finger's reach: " + ids(100, 100));   // m once, at its nearest spot
if (ids(100, 100, 5) !== "a") bad.push("a mouse's reach: " + ids(100, 100, 5));
stripAt = "130,120";                                               // b's dot, (120, 100) in #globe
if (ids(100, 100) !== "a,m") bad.push("a dot under the strip found: " + ids(100, 100));
stripAt = null; boxAt = "130,120";
if (ids(100, 100) !== "a,m") bad.push("a dot under a box found: " + ids(100, 100));
boxAt = "110,120";                                                 // a's dot under a box
if (ids(100, 100) !== "m,b") bad.push("the nearest dot under a box: " + ids(100, 100));
boxAt = "100,120";                                                 // m's nearer spot under a box: m from its other spot
if (ids(100, 100) !== "a,m,b" || near(100, 100).find((n) => n.e === M).d !== 15) bad.push("a receipt with a spot under a box: " + ids(100, 100));
boxAt = null;
if (ids(378, 100) !== "e") bad.push("by the right edge: " + ids(378, 100));            // d's middle is off the screen
if (ids(100, -14) !== "f") bad.push("by the top: " + ids(100, -14));                   // g's middle is above it
// the click handler as written: a finger's press, then a click that says mouse (an iPhone) or touch, asks for the
// finger's reach once globe.gl has had its frame and opens the nearest; a mouse's click leaves it to globe.gl, except
// on the satellite map, where it asks for the mark's reach; a tap that starts on a box beside the globe ("box": its
// press and click reach the window, not the globe) is the box's, even where WebKit gives its click to the globe; a
// post already open takes it
const c0 = s.indexOf(pl), c1 = s.indexOf("\n  // ---------- satellite map", c0);
if (c0 < 0 || c1 < 0) bad.push("the click handler is missing");
else for (const [what, steps, sat, want, open] of [
  ["an iPhone's tap (a touch press, a click that says mouse)", [["pointerdown", "touch"], ["pointerup", "touch"], ["click", "mouse"]], false, "100,100,36"],
  ["a finger's tap", [["pointerdown", "touch"], ["pointerup", "touch"], ["click", "touch"]], false, "100,100,36"],
  ["a pen", [["pointerdown", "pen"], ["pointerup", "pen"], ["click", "mouse"]], false, "100,100,36"],
  ["a mouse's click", [["pointerdown", "mouse"], ["pointerup", "mouse"], ["click", "mouse"]], false, ""],
  ["a mouse's click on the satellite map", [["pointerdown", "mouse"], ["pointerup", "mouse"], ["click", "mouse"]], true, "100,100,11"],
  ["a mouse's press, a click that says touch", [["pointerdown", "mouse"], ["click", "touch"]], false, ""],
  ["a finger's tap on the satellite map", [["pointerdown", "touch"], ["click", "mouse"]], true, "100,100,36"],
  ["a click with no press seen that says touch", [["click", "touch"]], false, "100,100,36"],
  ["a click with no press seen that says mouse", [["click", "mouse"]], false, ""],
  ["a click with no press seen and no pointerType (an older Safari)", [["click", undefined]], false, "100,100,36"],
  ["an iPhone's tap that starts on a box beside the globe, its click given to the globe", [["pointerdown", "touch", "box"], ["pointerup", "touch", "box"], ["click", "mouse"]], false, ""],
  ["a mouse's press on a box, then a click on the satellite map", [["pointerdown", "mouse", "box"], ["click", "mouse"]], true, ""],
  ["a tap on a box, then one on the globe", [["pointerdown", "touch", "box"], ["click", "mouse", "box"], ["pointerdown", "touch"], ["click", "mouse"]], false, "100,100,36"],
  ["a finger's tap on the globe, then an iPhone's tap that starts on a box, its click given to the globe", [["pointerdown", "touch"], ["click", "mouse"],
    ["pointerdown", "touch", "box"], ["pointerup", "touch", "box"], ["click", "mouse"]], false, "100,100,36"],
  ["a finger's tap on the globe, a tap on a box, then one on the globe", [["pointerdown", "touch"], ["click", "mouse"], ["pointerdown", "touch", "box"], ["click", "mouse"],
    ["pointerdown", "touch"], ["click", "mouse"]], false, "100,100,36 100,100,36"],
  ["a finger's tap with a post open", [["pointerdown", "touch"], ["click", "mouse"]], false, "", true],
  ["a finger inside a box whose press Chrome moved onto the globe's tag", [["pointerdown", "touch", "globe", "box"], ["click", "mouse"]], false, ""],
  ["a press with nothing under its point (off the screen): its target counts", [["pointerdown", "touch", "globe", "none"], ["click", "mouse"]], false, "100,100,36"]]) {
  const on = {}, won = {}, frames = [], asked = [], opened = [];
  const IN = { closest: () => null, inGlobe: true }, BOX = { closest: () => null, inGlobe: false };
  const el2 = { addEventListener: (t, f) => (on[t] = on[t] || []).push(f), getBoundingClientRect: () => ({ left: 10, top: 20 }), contains: (n) => !!n && !!n.inGlobe };
  const wadd = (t, f, o) => (won[t] = won[t] || []).push(o?.once ? function g(ev) { won[t] = won[t].filter((x) => x !== g); f(ev); } : f);
  try {
    new Function("el", "addEventListener", "satMarks", "onStrip", "requestAnimationFrame", "performance", "overlay", "pinTapAt", "pointTapAt", "receiptsNear", "markR", "REACH", "CLEAR",
      "openPost", "openReceiptChooser", "document", 'let pressType = "", pressOn = null;\n' + s.slice(c0, c1 + 1))(
      el2, wadd, sat, () => false, (f) => frames.push(f), { now: () => 10000 }, { hidden: !open }, 0, 0,
      (x, y, r) => { asked.push(x + "," + y + "," + r); return [{ e: { id: "a" }, d: 3 }]; }, 8, 36, 16, (e) => opened.push(e.id), () => opened.push("chooser"),
      { elementFromPoint: (x, y) => (x === 110 && y === 120 ? under : null) });   // the finger's point, on the screen
  } catch (err) { bad.push("the click handler: " + err.message); break; }
  let under = null;                                                 // what is under the finger's own point
  for (const [type, pointerType, where, at] of steps) {
    const ev = { pointerType, clientX: 110, clientY: 120, pageX: 110, pageY: 1120, screenX: 140, screenY: 220, target: where === "box" ? BOX : IN };
    under = at === "none" ? null : (at || where) === "box" ? BOX : IN;
    (won[type] || []).forEach((f) => f(ev));                        // the window first (a listener for the capture)
    if (where !== "box") (on[type] || []).forEach((f) => f(ev));    // the globe only for what lands on it
  }
  if (asked.length) bad.push(what + ": asked before globe.gl's frame");
  frames.splice(0).forEach((f) => f());
  if (asked.join(" ") !== want || opened.join() !== (want ? want.split(" ").map(() => "a").join() : "")) bad.push(what + ": " + (asked.join(" ") || "nothing asked") + ", opened " + (opened.join() || "nothing"));
}
// a mission tag (missionPin as written): a tap whose press starts on a box beside it is the box's, even where WebKit
// gives its click to the tag (iOS Simulator, 2026-11-18); a press on the tag, or none seen, opens its mission
const t0 = s.indexOf("  function missionPin(g) {\n"), t1 = s.indexOf("\n  }\n", t0);
if (t0 < 0 || t1 < 0) bad.push("missionPin is missing");
else {
  const tag = { on: {}, addEventListener(t, f) { (this.on[t] = this.on[t] || []).push(f); }, classList: { add() {}, remove() {}, toggle() {} } };
  const pin = { firstChild: tag, classList: { toggle() {} }, setAttribute() {}, removeAttribute() {}, style: {}, set innerHTML(v) {} };
  const M2 = { no: 2, place_name: "Pasar", date: "2026-11-26" }, opened = [];
  let mp;
  try {
    mp = new Function("document", "missionsOf", "funded", "upper", "dateStr", "glyph", "groupLabel", "groupOfTag", "setOff", "missions", "baseOf",
      "openMission", "openChooser", "performance",
      "let pinTapAt = 0, pressOn = null;\n" + s.slice(t0, t1 + 4) + "\nreturn { missionPin, press: (v) => { pressOn = v; } };")(
      { createElement: () => pin }, (ms) => ms, () => false, (v) => String(v), () => "26 NOV", () => "", () => "#2", new Map(), () => {}, [M2], (z) => z,
      (m) => opened.push("#" + m.no), (l) => opened.push("chooser"), { now: () => 1 });
    mp.missionPin({ ms: [M2] });
  } catch (err) { bad.push("missionPin: " + err.message); }
  if (mp) for (const [what, on, want] of [["a press on a box beside it, its click given to the tag", false, ""], ["a press on the tag", true, "#2"],
    ["a click with no press seen", null, "#2"], ["a press on a box, then a tap on the tag", "both", "#2"]]) {
    opened.length = 0;
    if (on === "both") { mp.press(false); (tag.on.click || []).forEach((f) => f({ clientX: 0, clientY: 0 })); mp.press(true); }
    else mp.press(on);
    (tag.on.click || []).forEach((f) => f({ clientX: 0, clientY: 0 }));
    if (opened.join() !== want) bad.push("a mission tag, " + what + ": opened " + (opened.join() || "nothing"));
  }
}
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
JS
check "a finger's tap next to a receipt dot (site/app.js in node): the press tells a finger from a mouse, not the click, so an iPhone's tap, whose click says mouse, gets the finger's 36 px; a dot under the tap hint's strip, under a box over the globe or with its middle off the screen is not found from next to it, the others are; the click handler as written asks for the finger's reach after globe.gl's frame, and a tap that starts on a box beside the globe is the box's, even where WebKit gives its click to the globe or to a mission tag (missionPin as written), also after a tap on the globe, and where Chrome moves the press itself (the press counts where the finger is)" "$(node "$T/taps.js" "$T/home.js" 2>&1)" "ok"
# The broom is the link preview of the homepage and /apply/ (they had no picture) and of /crews, /missions, the 404 page
# of /m/<no> and a /m/<no> or /r/<id> without a photo (they showed the old SAPU SQUAD picture): square, so a small card.
# A crew page /p/<slug> with neither a receipt photo nor a logo has it too (2026-11-17; it showed no picture before).
curl -s $B/apply/ > "$T/applyx.html"; curl -s $B/m/999999999 > "$T/m404x.html"
MARK=$(curl -s -o "$T/mark.png" -w '%{http_code} %{content_type}' $B/site/social/sapu-earth-mark.png)
OGX=$(python3 - "$T/home.html" "$T/applyx.html" "$T/m404x.html" "$T/mark.png" <<'PY2'
import struct, sys
home, apply_, m404 = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
png = open(sys.argv[4], "rb").read()
bad = []
url = "https://sapu.earth/site/social/sapu-earth-mark.png"
for name, h in (("/", home), ("/apply/", apply_)):
    for t in [f'<meta property="og:image" content="{url}">', '<meta property="og:image:width" content="1024">', '<meta property="og:image:height" content="1024">',
              """<meta property="og:image:alt" content="Sapu Earth's logo, a hand-drawn yellow broom">""", '<meta name="twitter:card" content="summary">']:
        if h.count(t) != 1:
            bad.append(name + ": " + t)
if "/site/social/sapu-earth-mark.png" not in m404 or '<meta name="twitter:card" content="summary">' not in m404:
    bad.append("/m/<unknown>")
if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (1024, 1024) or len(png) > 300000:
    bad.append("the picture is not a 1024 x 1024 PNG under 300 KB")
for f in ["functions/m/[no].js", "functions/r/[id].js"]:
    src = open(f, encoding="utf-8").read()
    if ': origin + "/site/social/sapu-earth-mark.png";' not in src or '<meta name="twitter:card" content="${img ? "summary_large_image" : "summary"}">' not in src:
        bad.append(f)
src = open("functions/p/[slug].js", encoding="utf-8").read()
if src.count('<meta property="og:image" content="${esc(origin + "/site/social/sapu-earth-mark.png")}">') != 1 or src.count("""<meta property="og:image:alt" content="Sapu Earth's logo, a hand-drawn yellow broom">""") != 1:
    bad.append("functions/p/[slug].js has no broom for a crew without a receipt photo or a logo")
for f in ["index.html", "apply/index.html", "functions/crews/index.js", "functions/missions/index.js", "functions/m/[no].js", "functions/r/[id].js", "functions/p/[slug].js"]:
    if "post-01-hello" in open(f, encoding="utf-8").read():
        bad.append(f + " still names the SAPU SQUAD picture")
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY2
)
check "the broom is the link preview (1024 x 1024, a small card) of /, /apply/, /crews, /missions, the 404 page of /m/<no>, a mission or receipt without a photo, and a crew page with neither a receipt photo nor a logo; nothing names the SAPU SQUAD picture" "$MARK $OGX" "200 image/png ok"
# /apply/ says before the form that there are no fees and no PIN or OTP (the line of the join box on /crews and /missions,
# both languages) and HOW IT WORKS in three steps, in English and Indonesian, the static text the same as the English.
APX=$(python3 - "$T/applyx.html" <<'PY2'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
js = open("apply/apply.js", encoding="utf-8").read()
join = open("functions/_lib/crews.js", encoding="utf-8").read()
bad = []
keys = ["free", "how_h", "how_1", "how_2", "how_3"]
intro = html[html.find('<div id="intro">'):html.find("</div>", html.find('<div id="intro">'))]
pos = [intro.find(f'data-i18n="{k}"') for k in ["lead"] + keys + ["already", "honest"]]
if min(pos) < 0 or pos != sorted(pos):
    bad.append("the intro's order: lead, free, HOW IT WORKS, already, honest")
def val(lang, k):
    blk = js[js.find(f"    {lang}: {{"):]
    m = re.search(r'\n      ' + k + r': "((?:[^"\\]|\\.)*)"', blk)
    return m.group(1) if m else None
for k in keys:
    en, idv = val("en", k), val("id", k)
    if not en or not idv or en == idv:
        bad.append(k + " in both languages")
    elif f'data-i18n="{k}">{en}</' not in intro.replace("&#39;", "'"):
        bad.append(k + ": the static text is not the English one")
if val("en", "free") != "There are no fees, and we never ask for a PIN, a password or an OTP code." or "There are no fees, and we never ask for a PIN, a password or an OTP code." not in join \
        or val("id", "free") != "Tidak ada biaya apa pun, dan kami tidak pernah meminta PIN, kata sandi, atau kode OTP." or val("id", "free") not in join:
    bad.append("the no-fees line differs from the join box's")
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY2
)
check "/apply/ says before the form that there are no fees and no PIN or OTP (the join box's line, EN and ID) and HOW IT WORKS in three steps, in both languages" "$APX" "ok"
# The stories' closer names no country it has no crew in, the Indonesian paper paragraph says what the English says (the
# association has said, mengatakan), WANT IN? has no dead TIPPING SOON box and puts Instagram first, a receipt card's
# stamp stands clear of BEFORE and AFTER, and no browser darkens the paper.
NINE2=$(python3 - "$T/home.html" "$T/home.css" <<'PY2'
import re, sys
html, css = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
html = re.sub(r"(?s)<!--.*?-->", "", html)  # what a visitor gets; a comment says why TIPPING SOON went
bad = []
for st in ["trash-in-numbers", "trash-with-a-passport"]:
    en, idp = (open(f"stories/{st}/{p}index.html", encoding="utf-8").read() for p in ("", "id/"))
    if en.count("Sapu Earth pays local crews to clean up, fairly and in local money, starting in Indonesia.") != 1 \
            or idp.count("Sapu Earth membayar kru lokal untuk bersih-bersih, dibayar layak dalam uang lokal, mulai dari Indonesia.") != 1 \
            or "Philippines" in en or "Filipina" in idp:
        bad.append(st)
pp = open("stories/trash-with-a-passport/id/index.html", encoding="utf-8").read()
if "(APKI) mengatakan ada pabrik yang membuang" not in pp or "mengakui" in pp:
    bad.append("mengatakan")
soc = html[html.find('<div class="socials">'):html.find("</div>", html.find('<div class="socials">'))]
if "TIPPING SOON" in html or "btn-soon" in html + css or not (0 <= soc.find(">INSTAGRAM</a>") < soc.find(">TIKTOK</a>")) \
        or "<p class=\"sub\">// tipping opens soon. for now, follow along.</p>" not in html:
    bad.append("WANT IN?")
if ".stamp {\n  position: absolute; top: 102px; left: 50%; z-index: 1;" not in css:
    bad.append("the stamp")
root = css[css.find(":root {"):css.find("}", css.find(":root {"))]
if "  color-scheme: only light;" not in root:
    bad.append("color-scheme")
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY2
)
check "the stories' closer says starting in Indonesia (no Philippines), the Indonesian paper paragraph says mengatakan, WANT IN? has Instagram first and no TIPPING SOON box, the receipt stamp clear of BEFORE and AFTER, and paper never darkened" "$NINE2" "ok"
UPX=$(curl -s $B/upload/); UJX=$(curl -s $B/upload/upload.js)
PUBX=$(echo "$UPX" | sed -n '/<section class="panel" id="pubPage" hidden>/,/<\/section>/p')
[ "$(echo "$PUBX" | grep -oE 'id="(pubLink|crewsHint|sharePub|crewsLink)"' | tr '\n' ' ')" = 'id="pubLink" id="crewsHint" id="sharePub" id="crewsLink" ' ] \
  && echo "$PUBX" | grep -qF '<p class="hint" id="crewsHint" data-i18n="crews_listed" hidden>Your crew is also in the list of all crews on sapu.earth.</p>' \
  && echo "$PUBX" | grep -qF '<a class="b b-ghost" id="crewsLink" href="/crews" target="_blank" rel="noopener" data-i18n="crews_open">SEE ALL CREWS</a>' \
  && echo "$UPX" | grep -qF '<meta name="referrer" content="no-referrer">' \
  && echo "$UJX" | grep -qF 'const listed = typeof partner.listed === "boolean" ? partner.listed' && echo "$UJX" | grep -qF 'const live = !!page && listed;' \
  && echo "$UJX" | grep -qF '$("#crewsHint").hidden = partner.listed !== true;' \
  && ok "the crew page: YOUR PUBLIC PAGE shows from partner.listed (an older server: a cleanup approved), with the list line and SEE ALL CREWS (/crews in a new tab, no referrer)" \
  || bad "crew page YOUR PUBLIC PAGE" "$PUBX"
printf '%s' "$UJX" > "$T/cx-u.js"
CXT=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8"); const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const want = { en: { crews_listed: "Your crew is also in the list of all crews on sapu.earth.", crews_open: "SEE ALL CREWS" },
  id: { crews_listed: "Kru kamu juga ada di daftar semua kru di sapu.earth.", crews_open: "LIHAT SEMUA KRU" } };
const bad = [];
for (const l of ["en", "id"]) for (const [k, v] of Object.entries(want[l])) if (T[l][k] !== v) bad.push(l + " " + k);
const pv = { en: "Your crew is also in the list of crews at sapu.earth/crews from the day we start working together, with its name, logo, country and TikTok account. Its name there links to your crew\x27s public page on sapu.earth, which also shows your crew\x27s website. Once your crew has a receipt or a mission on sapu.earth, the list also shows the totals of its receipts (cleanups, kilograms, sacks and what Sapu Earth paid), its newest receipt and its open and funded missions. It leaves the list when we stop working together.",
  id: "Kru kamu juga ada di daftar kru di sapu.earth/crews sejak kita mulai bekerja sama, dengan nama, logo, negara, dan akun TikTok-nya. Nama kru kamu di daftar itu bisa ditekan untuk membuka halaman publik kru kamu di sapu.earth, yang juga menampilkan situs web kru kamu. Setelah kru kamu punya laporan atau misi di sapu.earth, daftar itu juga menampilkan total dari semua laporannya (aksi bersih, kilogram, karung, dan berapa yang dibayar Sapu Earth), laporan terbarunya, serta misinya yang masih menunggu dana atau sudah didanai. Kru kamu keluar dari daftar itu saat kerja sama kita berhenti." };
for (const l of ["en", "id"]) if (/Selama kru kamu punya misi|While your crew has a mission/.test(T[l].pv_public)) bad.push(l + " the old rule");
for (const l of ["en", "id"]) if (!T[l].pv_public.endsWith(" " + pv[l])) bad.push(l + " pv_public");
if (/[\u2013\u2014]/.test(JSON.stringify([T.en.crews_listed, T.id.crews_listed, T.en.pv_public, T.id.pv_public]))) bad.push("dash");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/cx-u.js" 2>&1)
[ "$CXT" = ok ] && echo "$UPX" | grep -qF "It leaves the list when we stop working together.</span>" \
  && [ "$(echo "$UPX" | grep -cF 'Your crew is also in the list of crews at sapu.earth/crews from the day we start working together, with its name, logo, country and TikTok account. Its name there links to your crew'"'"'s public page on sapu.earth, which also shows your crew'"'"'s website. Once your crew has a receipt or a mission on sapu.earth, the list also shows')" = 1 ] \
  && ok "the crew page's list texts (crews_listed, crews_open) in EN and ID, and the upload notice names sapu.earth/crews: from the day we start working together with the crew's name, logo and country, its totals, newest receipt and missions once it has a receipt or a mission, until we stop (EN on the page and in the script, ID in the script), no dashes" \
  || bad "crew page list texts" "$CXT"
MXT=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8"); const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const want = {
  en: ["A mission is public in the same way once we publish or fund it.", "It is also in the list of missions at sapu.earth/missions, and once it is cleaned it stays there with its receipt, also after we stop working together."],
  id: ["Misi tampil untuk umum dengan cara yang sama setelah kami tayangkan atau danai.", "Misi itu juga ada di daftar misi di sapu.earth/missions, dan setelah dibersihkan tetap ada di sana bersama laporannya, juga setelah kerja sama kita berhenti."] };
const last = { en: " It leaves the list when we stop working together.", id: " Kru kamu keluar dari daftar itu saat kerja sama kita berhenti." };
const bad = [];
for (const l of ["en", "id"]) {
  const p = T[l].pv_public;
  if (p.split(want[l][1]).length !== 2 || !p.includes(want[l][0] + " " + want[l][1] + " ")) bad.push(l + " missions sentence");
  if (!p.endsWith(last[l])) bad.push(l + " crews sentence not last");
}
if (/[\u2013\u2014]/.test(T.en.pv_public + T.id.pv_public)) bad.push("dash");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/cx-u.js" 2>&1)
[ "$MXT" = ok ] && [ "$(echo "$UPX" | grep -oF 'A mission is public in the same way once we publish or fund it. It is also in the list of missions at sapu.earth/missions, and once it is cleaned it stays there with its receipt, also after we stop working together. Once we approve' | wc -l | tr -d ' ')" = 1 ] \
  && ok "the upload notice names sapu.earth/missions right after the mission sentence, and that a cleaned mission stays there with its receipt after we stop working together (EN on the page and in the script, ID in the script); the crews sentence stays last; no dashes" \
  || bad "upload notice: the list of missions" "$MXT"

# DEACTIVATE takes a crew off the list at once (its receipts stay on the globe). The other crews of this part go too.
st=$(cxoff "$CXAI"); cxpage >/dev/null
check "DEACTIVATE crew A -> 200, and it is no longer on /crews (in neither group), while its receipts stay in /api/events" \
  "$st $(cxq "(card('$CXAS'), jj('$CXAS'))") $(curl -s $B/api/events | jget "sum(e['id'] in ('$CXS1', '$CXS2') for e in d)")" "200 (None, None) 2"
st=""; for i in "$CXBI" "$CXCI" "$CXDI" "$CXEI" "$CXXI" "$CXLI" "$CXPI" "$CXOI" "$CXQI"; do st="$st$(cxoff "$i") "; done; cxpage >/dev/null
check "the other crews of this part are deactivated and off /crews, JUST JOINED included" "$st$(cxq "[c['slug'] for c in cards + new if c['slug'].endswith('-$CXRUN')]")" "200 200 200 200 200 200 200 200 200 []"
mxpage >/dev/null
check "after DEACTIVATE, crew B's open and funded missions and those of crews X, L and P are off /missions" \
  "$(mxq "[n for n in ($NB1, $NB2, $NB6, $NB7) if card(n)] + [c['no'] for c in cards if c['kind'] != 'cleaned' and ('-$CXRUN\"' in c['html'] or '$CXRUN</span>' in c['html'])]")" "[]"
mxpage status=cleaned >/dev/null
check "after DEACTIVATE, crew B's cleaned mission stays on /missions?status=cleaned with its receipt, BY with the name alone and no link to its page" \
  "$(mxq "('<a class=\"mx-head\" href=\"/r/$CXBS5\">' in card($NB5)['html'], '<p class=\"cx-last mx-by\"><b>BY</b><span>Crew B $CXRUN</span></p>' in card($NB5)['html'], 'href=\"/p/$CXBS\"' in page)")" "(True, True, False)"

# ---------- Post links on receipts (docs/upload-flow.md, Post links and thanks) ----------
# A crew can send the link to its own post about a cleanup on Instagram or TikTok (post_url in POST /api/submit), and
# Marcus can link Sapu Earth's own post on the APPROVED card (POST /api/admin/post-link, slot sapu). The receipt shows one
# of them (social in /api/events: ours when there is one, else the crew's while the crew is active), as a plain link in
# the receipt post and in the body of /r/<id>. Only full post links, in one stored form; never a short link, and a
# TikTok post in our slot only on @sapu.earth. REJECT, UNPUBLISH, REMOVE, REMOVE CREW LINK and DEACTIVATE take links
# off. Crews of their own: PL sends links, PO is deactivated with two linked receipts, PN has receipts without links
# for the deploy-order checks.
PLRUN=$RANDOM$RANDOM
# plsub <token> <place> <media> [post_url]: POST /api/submit, today, no mission, post_url only when given. Prints the
# status, the body goes to $T/p.json (pj).
plsub() { local b; b=$(body $TODAY "$2" "$3")
          [ $# -ge 4 ] && b=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);d['post_url']=sys.argv[2];print(json.dumps(d))" "$b" "$4")
          curl -s -o "$T/p.json" -w '%{http_code}' -X POST "$B/api/submit?k=$1" -H 'content-type: application/json' -d "$b"; }
pj()    { jget "$1" < "$T/p.json"; }
# plink <JSON>: POST /api/admin/post-link. Prints the status, the body goes to $T/p.json.
plink() { curl -s -o "$T/p.json" -w '%{http_code}' -X POST $B/api/admin/post-link -H "$A" -H 'content-type: application/json' -d "$1"; }
# plinks <id> <status>: that cleanup's post_links in GET /api/admin/submissions?status=<status>, in a list ([] when not there).
plinks() { curl -s "$B/api/admin/submissions?status=$2" -H "$A" | jget "[s.get('post_links') for s in d['submissions'] if s['id']=='$1']"; }
# psoc <id>: that receipt's social in /api/events, in a list ([] when it is no receipt there).
psoc()  { curl -s $B/api/events | jget "[e.get('social') for e in d if e['id']=='$1']"; }
# prow <id>: (STATE) its post_links rows in the local D1, [[crew_url, sapu_url]] or [].
prow()  { d1 "SELECT crew_url, sapu_url FROM post_links WHERE submission_id = '$1'" | jget "[[r['crew_url'], r['sapu_url']] for r in d[0]['results']]"; }
IG1=https://www.instagram.com/p/E2eAbc123/
TTK=https://www.tiktok.com/@kru_bersih/video/7312345678901234567
TTS=https://www.tiktok.com/@sapu.earth/video/7312345678901234567
PLJ=$(newp "Post Link Crew $PLRUN" ID "post-link-$PLRUN"); PLT=$(echo "$PLJ" | jget "d['token']")
POJ=$(newp "Post Link Off Crew $PLRUN" ID "post-link-off-$PLRUN"); POT=$(echo "$POJ" | jget "d['token']"); POPID=$(echo "$POJ" | jget "d['id']")
PNJ=$(newp "Post Link Plain Crew $PLRUN" ID "post-link-plain-$PLRUN"); PNT=$(echo "$PNJ" | jget "d['token']"); PNPID=$(echo "$PNJ" | jget "d['id']")
check "three crews for the post links, and GET /api/partner says post links are on (the cleanup form shows its link field)" \
  "${#PLT} ${#POT} ${#PNT} $(curl -s "$B/api/partner?k=$PLT" | jget "d.get('post_links_enabled')")" "43 43 43 True"

P1B=$(upk $PLT before); P1A=$(upk $PLT after)
st=$(plsub $PLT "Post link $PLRUN" "$P1B,$P1A" "$IG1?igsh=xyz"); PL1=$(pj "d.get('id')")
check "a cleanup with the link to the crew's Instagram post (as the app copies it, with ?igsh=) -> 200, PENDING has the link in its stored form" \
  "$st $(plinks $PL1 pending)" "200 [{'crew': '$IG1', 'sapu': None}]"
st=$(plsub $PLT "Post link $PLRUN" "$P1B,$P1A" "$IG1?igsh=xyz")
check "the same cleanup sent again (a lost answer) -> 200 with the same id, repeated" "$st $(pj "(d.get('id') == '$PL1', d.get('repeated'))")" "200 (True, True)"
[ -n "$STATE" ] && check "it still has one post_links row, the crew's link" "$(prow $PL1)" "[['$IG1', None]]"
P2B=$(upk $PLT before); P2A=$(upk $PLT after)
st="$(plsub $PLT "Post link short $PLRUN" "$P2B,$P2A" "https://vt.tiktok.com/ZSe2e123/") $(pj "(d.get('code'), d.get('field'))")"
st="$st $(plsub $PLT "Post link short $PLRUN" "$P2B,$P2A" "tiktok.com/@kru_bersih/video/7312345678901234567?is_from_webapp=1")"; PL2=$(pj "d.get('id')")
check "a short TikTok link -> 400 post_link post_url, and the same files then go with the full address pasted without https:// (the refusal attached nothing)" \
  "$st $(plinks $PL2 pending)" "400 ('post_link', 'post_url') 200 [{'crew': '$TTK', 'sapu': None}]"
P3B=$(upk $PLT before); P3A=$(upk $PLT after)
check "post_url \"not a link\", a profile, http: and a number -> 400 post_link each, nothing stored" \
  "$(plsub $PLT x "$P3B,$P3A" "not a link") $(pj "d.get('code')") $(plsub $PLT x "$P3B,$P3A" "https://www.instagram.com/sapu.earth/") $(plsub $PLT x "$P3B,$P3A" "http://www.instagram.com/p/E2eAbc123/") $(curl -s -o "$T/p.json" -w '%{http_code}' -X POST "$B/api/submit?k=$PLT" -H 'content-type: application/json' -d "$(body $TODAY x "$P3B,$P3A" | python3 -c "import json,sys;d=json.load(sys.stdin);d['post_url']=12;print(json.dumps(d))")") $(pj "d.get('code')")" \
  "400 post_link 400 400 400 post_link"
st=$(plsub $PLT "Post link none $PLRUN" "$P3B,$P3A"); PL3=$(pj "d.get('id')")
check "a cleanup without a link -> 200, PENDING post_links both None" "$st $(plinks $PL3 pending)" "200 [{'crew': None, 'sapu': None}]"
check "before APPROVE the receipt is not in /api/events; after APPROVE its social is the crew's Instagram post" \
  "$(psoc $PL1) $(sdec "{\"id\":\"$PL1\",\"action\":\"approve\",\"paid_eur\":50}") $(psoc $PL1)" "[] approved [{'site': 'instagram', 'url': '$IG1', 'by': 'crew'}]"
curl -s $B/r/$PL1 > "$T/pr.html"
grep -qF "<p><a class=\"r-more\" href=\"$IG1\" rel=\"noopener noreferrer nofollow ugc\">Comments on Instagram</a></p>" "$T/pr.html" \
  && ! grep -iE '<meta[^>]*(instagram|tiktok|comments)' "$T/pr.html" | grep -q . && grep -qF 'a.r-more{display:inline-block;min-height:44px;line-height:44px}' "$T/pr.html" \
  && ok "/r/<id>: its body links the crew's post (nofollow ugc, 44 px), and no meta tag carries the link" || bad "/r/<id> comments link" "$(grep -n 'r-more' "$T/pr.html")"
check "APPROVE the cleanup without a link: social None, /r/<id> without a comments link" \
  "$(sdec "{\"id\":\"$PL3\",\"action\":\"approve\",\"paid_eur\":30}") $(psoc $PL3) $(curl -s $B/r/$PL3 | grep -c 'class="r-more"')" "approved [None] 0"
check "POST /api/admin/post-link without the token -> 401" \
  "$(code -X POST $B/api/admin/post-link -H 'content-type: application/json' -d "{\"id\":\"$PL1\",\"slot\":\"crew\",\"url\":null}")" 401
check "slot sapu on a pending cleanup -> 409 state" \
  "$(plink "{\"id\":\"$PL2\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eOurs123/\"}") $(pj "d.get('code')")" "409 state"
check "slot sapu with our TikTok post (with ?lang=en) -> 200, stored without the query, and the receipt links ours" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":\"$TTS?lang=en\"}") $(pj "(d['post_links'], d['social'])")" \
  "200 ({'crew': '$IG1', 'sapu': '$TTS'}, {'site': 'tiktok', 'url': '$TTS', 'by': 'sapu'})"
check "/api/events agrees (our link wins over the crew's), and /r/<id> links it without nofollow" \
  "$(psoc $PL1) $(curl -s $B/r/$PL1 | grep -cF "<a class=\"r-more\" href=\"$TTS\" rel=\"noopener noreferrer\">Comments on TikTok</a>")" \
  "[{'site': 'tiktok', 'url': '$TTS', 'by': 'sapu'}] 1"
check "slot sapu with a crew's TikTok post -> 400 post_link url, ours stays" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":\"$TTK\"}") $(pj "(d.get('code'), d.get('field'))") $(plinks $PL1 approved)" \
  "400 ('post_link', 'url') [{'crew': '$IG1', 'sapu': '$TTS'}]"
check "slot sapu replaced with our Instagram reel, pasted without https:// -> 200, ours replaced" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":\"instagram.com/reel/E2eReel99/\"}") $(pj "d['post_links']['sapu']")" "200 https://www.instagram.com/reel/E2eReel99/"
check "slot sapu with a short link or a story -> 400 post_link url each, ours unchanged" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":\"https://vm.tiktok.com/ZMe2e/\"}") $(pj "(d.get('code'), d.get('field'))") $(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/stories/sapu.earth/3312345678901234567/\"}") $(plinks $PL1 approved)" \
  "400 ('post_link', 'url') 400 [{'crew': '$IG1', 'sapu': 'https://www.instagram.com/reel/E2eReel99/'}]"
check "REMOVE (slot sapu, url null) -> 200, ours gone, the receipt links the crew's post again" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"sapu\",\"url\":null}") $(pj "(d['post_links'], d['social'])") $(psoc $PL1)" \
  "200 ({'crew': '$IG1', 'sapu': None}, {'site': 'instagram', 'url': '$IG1', 'by': 'crew'}) [{'site': 'instagram', 'url': '$IG1', 'by': 'crew'}]"
check "slot crew with a link -> 400 post_link (the crew's link can only be removed)" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"crew\",\"url\":\"https://www.instagram.com/p/E2eOther12/\"}") $(pj "d.get('code')")" "400 post_link"
check "REMOVE CREW LINK (slot crew, url null) -> 200, no link left, the receipt links nothing" \
  "$(plink "{\"id\":\"$PL1\",\"slot\":\"crew\",\"url\":null}") $(pj "(d['post_links'], d['social'])") $(psoc $PL1)" "200 ({'crew': None, 'sapu': None}, None) [None]"
[ -n "$STATE" ] && check "its post_links row is deleted once both are empty" "$(prow $PL1)" "[]"
check "REJECT the pending cleanup with the crew's TikTok link -> rejected" "$(sdec "{\"id\":\"$PL2\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
[ -n "$STATE" ] && check "its post_links row went in the same batch" "$(prow $PL2)" "[]"
check "an unknown id -> 404, id BAD -> 400, slot x -> 400, a rejected cleanup -> 409 state (both slots)" \
  "$(plink '{"id":"aaaaaaaaaa","slot":"crew","url":null}') $(plink '{"id":"BAD","slot":"crew"}') $(plink "{\"id\":\"$PL1\",\"slot\":\"x\"}") $(plink "{\"id\":\"$PL2\",\"slot\":\"crew\",\"url\":null}") $(pj "d.get('code')") $(plink "{\"id\":\"$PL2\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eOurs123/\"}")" \
  "404 400 400 409 state 409"
# UNPUBLISH of a receipt with both links: the row goes in the same batch.
P4B=$(upk $PLT before); P4A=$(upk $PLT after)
st="$(plsub $PLT "Post link both $PLRUN" "$P4B,$P4A" "https://m.tiktok.com/@kru_bersih/photo/7312345678901234568/")"; PL4=$(pj "d.get('id')")
st="$st $(sdec "{\"id\":\"$PL4\",\"action\":\"approve\",\"paid_eur\":40}") $(plink "{\"id\":\"$PL4\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eOurs123/\"}")"
check "a receipt with the crew's TikTok photo post and our Instagram post: sent, approved, ours saved, the receipt links ours" \
  "$st $(psoc $PL4)" "200 approved 200 [{'site': 'instagram', 'url': 'https://www.instagram.com/p/E2eOurs123/', 'by': 'sapu'}]"
check "UNPUBLISH it -> rejected, /r/<id> -> 404, no longer in /api/events" \
  "$(sdec "{\"id\":\"$PL4\",\"action\":\"reject\",\"review_note\":\"Unpublished after approval\"}") $(code $B/r/$PL4) $(psoc $PL4)" "rejected 404 []"
[ -n "$STATE" ] && check "its post_links row, with both links, went in the same batch" "$(prow $PL4)" "[]"
# DEACTIVATE takes the crew's own links off all its receipts; our own links stay.
O1B=$(upk $POT before); O1A=$(upk $POT after); O2B=$(upk $POT before); O2A=$(upk $POT after)
st="$(plsub $POT "Post link off one $PLRUN" "$O1B,$O1A" "https://www.instagram.com/p/E2eOffOne1/")"; PO1=$(pj "d.get('id')")
st="$st $(plsub $POT "Post link off two $PLRUN" "$O2B,$O2A" "https://www.instagram.com/reels/E2eOffTwo2")"; PO2=$(pj "d.get('id')")
st="$st $(sdec "{\"id\":\"$PO1\",\"action\":\"approve\",\"paid_eur\":20}") $(sdec "{\"id\":\"$PO2\",\"action\":\"approve\",\"paid_eur\":20}")"
st="$st $(plink "{\"id\":\"$PO1\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eOursOff1/\"}")"
check "crew PO: two receipts with links to its own posts (one a /reels/ link), ours on the first" \
  "$st $(psoc $PO1) $(psoc $PO2)" "200 200 approved approved 200 [{'site': 'instagram', 'url': 'https://www.instagram.com/p/E2eOursOff1/', 'by': 'sapu'}] [{'site': 'instagram', 'url': 'https://www.instagram.com/reel/E2eOffTwo2/', 'by': 'crew'}]"
st=$(curl -s -o "$T/p.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$POPID\"}")
check "DEACTIVATE crew PO -> 200, post_links_removed 2; its receipts stay, ours still linked on the first, nothing on the second" \
  "$st $(pj "d.get('post_links_removed')") $(psoc $PO1) $(psoc $PO2)" "200 2 [{'site': 'instagram', 'url': 'https://www.instagram.com/p/E2eOursOff1/', 'by': 'sapu'}] [None]"
[ -n "$STATE" ] && check "crew PO's rows: ours alone on the first, none for the second" "$(prow $PO1) $(prow $PO2)" "[[None, 'https://www.instagram.com/p/E2eOursOff1/']] []"
# Deploy order: if the code goes live before migration 0007, the site works as without post links. Its four tables are
# renamed for a moment (finish() renames them back if the script stops in between). The housekeeping's answer without
# them is checked at the end of the housekeeping part: its first POST there must be the one that runs the jobs.
N1B=$(upk $PNT before); N1A=$(upk $PNT after); N2B=$(upk $PNT before); N2A=$(upk $PNT after)
st="$(plsub $PNT "Post link plain $PLRUN" "$N1B,$N1A")"; PN1=$(pj "d.get('id')"); st="$st $(sdec "{\"id\":\"$PN1\",\"action\":\"approve\",\"paid_eur\":25}")"
check "crew PN: a receipt without links" "$st" "200 approved"
if [ -n "$STATE" ]; then
  PRENAMED=1
  if soff >/dev/null; then
    E1="$(curl -s -o "$T/e.json" -w '%{http_code}' "$B/api/partner?k=$PNT") $(jget "d.get('post_links_enabled')" < "$T/e.json")"
    E2="$(plsub $PNT "Post link before $PLRUN" "$N2B,$N2A" "$IG1")"; PN2=$(pj "d.get('id')")
    E3="$(curl -s -o "$T/e.json" -w '%{http_code}' "$B/api/admin/submissions?status=pending" -H "$A") $(jget "all(s.get('post_links', 'missing') is None for s in d['submissions'])" < "$T/e.json")"
    E4="$(plink "{\"id\":\"$PN1\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eOurs123/\"}") $(pj "d.get('code')")"
    E5="$(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/events) $(jget "all(e.get('social', 'missing') is None for e in d)" < "$T/e.json")"
    E6="$(curl -s -o "$T/e.html" -w '%{http_code}' $B/r/$PO1) $(grep -c 'class="r-more"' "$T/e.html")"
    E7="$(sdec "{\"id\":\"$PN1\",\"action\":\"reject\",\"review_note\":\"Unpublished after approval\"}")"
    E8="$(curl -s -o "$T/e.json" -w '%{http_code}' -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$PNPID\"}") $(jget "d.get('post_links_removed')" < "$T/e.json")"
    son >/dev/null && PRENAMED=
    check "without the tables of migration 0007: GET /api/partner -> 200, post_links_enabled false (the crew page hides the link field)" "$E1" "200 False"
    check "without them: a cleanup with a good post_url -> 200 (stored, the link dropped)" "$E2" 200
    check "without them: GET /api/admin/submissions -> 200, post_links None on every card" "$E3" "200 True"
    check "without them: POST /api/admin/post-link -> 503 migration" "$E4" "503 migration"
    check "without them: /api/events -> 200, social None on every receipt" "$E5" "200 True"
    check "without them: /r/<id> of a receipt with our link -> 200, no comments link" "$E6" "200 0"
    check "without them: UNPUBLISH -> rejected" "$E7" rejected
    check "without them: DEACTIVATE -> 200, post_links_removed 0" "$E8" "200 0"
    check "tables back in place: our link shows on crew PO's receipt again, and the cleanup sent meanwhile kept no link" \
      "$(psoc $PO1) $(plinks $PN2 pending)" "[{'site': 'instagram', 'url': 'https://www.instagram.com/p/E2eOursOff1/', 'by': 'sapu'}] [{'crew': None, 'sapu': None}]"
    check "reject the cleanup sent without the tables, so nothing waits in PENDING" "$(sdec "{\"id\":\"${PN2:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
  else
    PRENAMED=
    bad "rename the tables of migration 0007 in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
else
  echo "NOTE  STATE is not set, so post links before migration 0007 are not checked (sh scripts/test.sh sets it)"
  check "deactivate crew PN" "$(cxoff "$PNPID")" 200
fi
check "deactivate crew PL, so none of this part's crews stays on /crews" "$(cxoff "$(echo "$PLJ" | jget "d['id']")")" 200

# ---------- Thanks on receipts (docs/upload-flow.md, Post links and thanks, Thanks) ----------
# SAY TERIMA KASIH in a receipt post sends POST /api/thanks with the receipt's id, only from a page of this site (its
# Origin, Sec-Fetch-Site when sent, a JSON body). countThanks counts it per receipt and UTC day and for the whole site,
# within the caps (THANKS in functions/_lib/social.js), and keeps nothing about the visitor. The counts show on the
# receipt (thanks in /api/events, the body of /r/<id>), /p/<slug>, /crews and the crew page (GET /api/partner), and in
# THANKS BY DAY on APPROVED with its two undos. Crews of their own, so the card checks of the crews above keep their
# exact lines: TY (two receipts today and a pending cleanup), TZ (one receipt, then deactivated) and TU (two receipts 3
# days old, for the order on /crews and the undos on a day seeded two to six days back). Nothing undoes today, so a
# second run against a persistent server on the same UTC day still passes. The busy days come in the housekeeping part.
TYRUN=$RANDOM$RANDOM
# ty <id> [curl options]: POST /api/thanks from this site (Origin $B, a JSON body). Prints the status, the body goes to
# $T/ty.json (tyj), the headers to $T/ty.h.
ty()    { local id=$1; shift; curl -s -o "$T/ty.json" -D "$T/ty.h" -w '%{http_code}' -X POST $B/api/thanks -H "Origin: $B" -H 'content-type: application/json' "$@" -d "{\"id\":\"$id\"}"; }
tyj()   { jget "$1" < "$T/ty.json"; }
# tyraw [curl options]: POST /api/thanks with only the given headers and body. Prints the status, the body goes to $T/ty.json.
tyraw() { curl -s -o "$T/ty.json" -w '%{http_code}' -X POST $B/api/thanks "$@"; }
# tev <id>: that receipt's thanks in /api/events, in a list ([] when it is no receipt there, 'missing' without the key).
tev()   { curl -s $B/api/events | jget "[e.get('thanks', 'missing') for e in d if e['id']=='$1']"; }
# tundo <JSON>: POST /api/admin/thanks/undo. Prints the status, the body goes to $T/ty.json.
tundo() { curl -s -o "$T/ty.json" -w '%{http_code}' -X POST $B/api/admin/thanks/undo -H "$A" -H 'content-type: application/json' -d "$1"; }
# tday <day> <expr>: <expr> over t, that day's entry of THANKS BY DAY in GET /api/admin/submissions?status=approved.
tday()  { curl -s "$B/api/admin/submissions?status=approved" -H "$A" | jget "(lambda t: $2)(([x for x in (d.get('thanks_days') or []) if x['day']=='$1'] or [None])[0])"; }
# tq <SQL>: (STATE) the first value of the first row of one read in the local D1, or None.
tq()    { d1 "$1" | jget "list(d[0]['results'][0].values())[0] if d[0]['results'] else None"; }
# tsums: (STATE) what breaks the rules of the counts, [] when nothing does: each receipt's total is the sum of its day
# rows and above 0, each site day the sum of that day's rows, and what a day counted (the site cap's count) never below
# what stands of it.
tsums() { d1 "SELECT 'receipt ' || t.submission_id AS bad FROM thanks t WHERE t.n <= 0 OR t.n <> (SELECT COALESCE(SUM(x.n), 0) FROM thanks_days x WHERE x.submission_id = t.submission_id) UNION ALL SELECT 'day ' || s.day FROM thanks_site s WHERE s.n <> (SELECT COALESCE(SUM(x.n), 0) FROM thanks_days x WHERE x.day = s.day) UNION ALL SELECT 'counted ' || s.day FROM thanks_site s WHERE s.counted < s.n" | jget "[r['bad'] for r in d[0]['results']]"; }
TYJ=$(newp "Crew TY $TYRUN" ID "ty-$TYRUN"); TYT=$(echo "$TYJ" | jget "d['token']"); TYPID=$(echo "$TYJ" | jget "d['id']")
TZJ=$(newp "Crew TZ $TYRUN" PH "tz-$TYRUN"); TZT=$(echo "$TZJ" | jget "d['token']"); TZPID=$(echo "$TZJ" | jget "d['id']")
TUJ=$(newp "Crew TU $TYRUN" ID "tu-$TYRUN"); TUT=$(echo "$TUJ" | jget "d['token']"); TUPID=$(echo "$TUJ" | jget "d['id']")
st="$(cxsub "$TYT" "$TODAY" "TY one $TYRUN" "$(upk "$TYT" before),$(upk "$TYT" after)")"; TY1=$(cj "d.get('id')")
st="$st $(cxsub "$TYT" "$TODAY" "TY two $TYRUN" "$(upk "$TYT" before),$(upk "$TYT" after)")"; TY2=$(cj "d.get('id')")
st="$st $(cxsub "$TYT" "$TODAY" "TY pending $TYRUN" "$(upk "$TYT" before),$(upk "$TYT" after)")"; TYP=$(cj "d.get('id')")
st="$st $(cxsub "$TZT" "$TODAY" "TZ one $TYRUN" "$(upk "$TZT" before),$(upk "$TZT" after)")"; TZ1=$(cj "d.get('id')")
st="$st $(cxsub "$TUT" "$(dplus -3)" "TU first $TYRUN" "$(upk "$TUT" before),$(upk "$TUT" after)")"; TU1=$(cj "d.get('id')")
st="$st $(cxsub "$TUT" "$(dplus -3)" "TU second $TYRUN" "$(upk "$TUT" before),$(upk "$TUT" after)")"; TU2=$(cj "d.get('id')")
for x in "$TY1" "$TY2" "$TZ1" "$TU1" "$TU2"; do st="$st $(sdec "{\"id\":\"${x:-none}\",\"action\":\"approve\",\"paid_eur\":30}")"; done
check "three crews for the thanks: TY with two receipts today and a pending cleanup, TZ with one receipt, TU with two receipts 3 days old" \
  "$st" "200 200 200 200 200 200 approved approved approved approved approved"
check "/api/events: a receipt without thanks carries thanks 0 (a number); the static events and the samples carry none" \
  "$(tev $TY1) $(grep -l '"thanks"' data/events/*.json site/samples/missions.json | wc -l | tr -d ' ')" "[0] 0"
PTU=$(curl -s $B/p/tu-$TYRUN); cxpage >/dev/null
! echo "$PTU" | grep -qE 'p-thanks|thanked' && [ "$(cxq "'thanked' in card('tu-$TYRUN')['html']")" = False ] \
  && ok "a crew without thanks: no thanks line on /p/<slug>, none in its rows, none on its /crews card" || bad "a crew without thanks" "$(echo "$PTU" | grep -n thank)"
st="$(ty $TY1) $(tyj "(d.get('thanks'), d.get('counted'))")"; TYH=$(tr -d '\r' < "$T/ty.h")
st="$st $(ty $TY1) $(tyj "(d.get('thanks'), d.get('counted'))")"
check "POST /api/thanks from this site -> 200 {thanks 1, counted true}, again -> {2, true}, and /api/events agrees" "$st $(tev $TY1)" "200 (1, True) 200 (2, True) [2]"
echo "$TYH" | grep -qi '^cache-control: no-store' && ! echo "$TYH" | grep -qi '^set-cookie:' && ! echo "$TYH" | grep -qi '^access-control-allow-origin:' \
  && ok "its answer is no-store, sets no cookie and allows no other site" || bad "POST /api/thanks headers" "$TYH"
st="$(curl -s -o /dev/null -D "$T/ty.h" -w '%{http_code}' $B/api/thanks) $(tr -d '\r' < "$T/ty.h" | sed -n 's/^[Aa]llow: *//p')"
st="$st $(curl -s -o /dev/null -D "$T/ty.h" -w '%{http_code}' -X OPTIONS $B/api/thanks -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type') $(grep -ci '^access-control-allow-origin:' "$T/ty.h")"
check "GET /api/thanks -> 405 Allow: POST; another site's CORS preflight -> 405 with no Access-Control-Allow-Origin" "$st" "405 POST 405 0"
st="$(tyraw -H 'content-type: application/json' -d "{\"id\":\"$TY1\"}") $(tyj "d.get('code')")"
st="$st $(tyraw -H 'Origin: https://evil.example' -H 'content-type: application/json' -d "{\"id\":\"$TY1\"}")"
st="$st $(ty $TY1 -H 'Sec-Fetch-Site: cross-site')"
st="$st $(tyraw -H "Origin: $B" -H 'content-type: text/plain' -d "{\"id\":\"$TY1\"}") $(tyj "d.get('code')")"
st="$st $(tyraw -H "Origin: $B" -H 'content-type: application/json' -d "{\"id\":\"$TY1\",\"pad\":\"$(head -c 2048 /dev/zero | tr '\0' x)\"}")"
st="$st $(ty BAD) $(ty "$TYP") $(tyj "d.get('code')") $(ty aaaaaaaaaa)"
check "refused, each counting nothing: no Origin (403 origin), another site's Origin, Sec-Fetch-Site cross-site, text/plain (415 type), a 2 KB body (413), id BAD (400), a pending cleanup (404 receipt), an unknown id (404)" \
  "$st $(tev $TY1)" "403 origin 403 403 415 type 413 400 404 receipt 404 [2]"
st="$(ty $TZ1) $(tyj "d.get('thanks')") $(cxoff "$TZPID") $(ty $TZ1) $(tyj "d.get('code')")"
check "crew TZ: its receipt thanked once, then DEACTIVATE, and a thanks for it -> 409 inactive (the receipt stays on sapu.earth with its count and takes no new thanks; 404 is only for a receipt that is gone)" "$st $(tev $TZ1)" "200 1 200 409 inactive [1]"
if [ -n "$STATE" ]; then
  check "the counts agree: each receipt's total is the sum of its day rows, each site day the sum of that day's rows" "$(tsums)" "[]"
  d1 "UPDATE thanks_days SET n = 1000 WHERE submission_id = '$TY1' AND day = '$TODAY'" >/dev/null
  st="$(ty $TY1) $(tyj "(d.get('thanks'), d.get('counted'))") $(ty $TY2) $(tyj "(d.get('thanks'), d.get('counted'))")"
  d1 "UPDATE thanks_days SET n = 2 WHERE submission_id = '$TY1' AND day = '$TODAY'" >/dev/null
  check "a receipt at its cap for the day (1,000) -> 200, counted false, its count unchanged; another receipt still counts" "$st $(tsums)" "200 (2, False) 200 (1, True) []"
  TSC=$(tq "SELECT counted FROM thanks_site WHERE day = '$TODAY'")
  d1 "UPDATE thanks_site SET counted = 5000 WHERE day = '$TODAY'" >/dev/null
  st="$(ty $TY2) $(tyj "(d.get('thanks'), d.get('counted'))") $(tday "$TODAY" "(t['full'], t['n'] < 5000)")"
  d1 "UPDATE thanks_site SET counted = ${TSC:-0} WHERE day = '$TODAY'" >/dev/null
  check "the whole site at its cap for the day: 5,000 counted with fewer standing (as after an undo or an UNPUBLISH took some off) -> counted false on any receipt, and THANKS BY DAY says the cap is reached" "$st $(tsums)" "200 (1, False) (True, True) []"
  TYD=$(dplus -1)
  d1 "INSERT INTO thanks_days (submission_id, day, n) VALUES ('$TY2', '$TYD', 1000)" >/dev/null
  st="$(ty $TY2) $(tyj "(d.get('thanks'), d.get('counted'))")"
  d1 "DELETE FROM thanks_days WHERE submission_id = '$TY2' AND day = '$TYD'" >/dev/null
  check "a receipt at its cap yesterday still counts today" "$st $(tsums)" "200 (2, True) []"
else
  echo "NOTE  STATE is not set, so the caps of thanks and the undos are not checked (sh scripts/test.sh sets it)"
  ty $TY2 >/dev/null; ty $TY2 >/dev/null
fi
check "TY's second receipt thanked a third time -> 3" "$(ty $TY2) $(tyj "d.get('thanks')")" "200 3"
st=""; for i in 1 2 3 4 5 6; do st="$st$(ty $TU1)"; done
check "TU's first receipt thanked 6 times" "$st $(tev $TU1)" "200200200200200200 [6]"
check "GET /api/partner: thanks_total adds up the crew's receipts, and only its published cleanups carry thanks" \
  "$(curl -s "$B/api/partner?k=$TYT" | jget "(d.get('thanks_total'), d.get('post_links_enabled'), sorted((s['status'], s.get('thanks', '-')) for s in d['submissions']))")" \
  "(5, True, [('approved', 2), ('approved', 3), ('pending', '-')])"
PTY=$(curl -s $B/p/ty-$TYRUN)
echo "$PTY" | grep -qF '<p class="sub p-thanks">// visitors thanked this crew 5 times on its receipts.</p>' \
  && echo "$PTY" | grep -qF '&nbsp;· crew&nbsp;of&nbsp;6&nbsp;· thanked&nbsp;3&nbsp;times</small>' && echo "$PTY" | grep -qF '&nbsp;· crew&nbsp;of&nbsp;6&nbsp;· thanked&nbsp;2&nbsp;times</small>' \
  && [ "$(echo "$PTY" | grep -n 'p-thanks' | cut -d: -f1)" -gt "$(echo "$PTY" | grep -n 'fp-stats' | cut -d: -f1)" ] \
  && [ "$(echo "$PTY" | grep -n 'p-thanks' | cut -d: -f1)" -lt "$(echo "$PTY" | grep -n 'THE RECEIPTS' | cut -d: -f1)" ] \
  && ! echo "$PTY" | grep -iE '<meta[^>]*(thanked|[0-9] times?)' | grep -q . \
  && ok "/p/<slug>: under the numbers \"// visitors thanked this crew 5 times on its receipts.\", each receipt row ends with its own count, and no meta tag carries one" \
  || bad "/p/<slug> thanks" "$(echo "$PTY" | grep -n -E 'thank|fp-stats')"
cxpage >/dev/null
check "/crews: TY's card ends with what was paid and its thanks; TU, with more thanks and older receipts, still comes after it (newest activity first, never by thanks)" \
  "$(cxq "('<small>Indonesia&nbsp;· 2&nbsp;cleanups&nbsp;· 241&nbsp;kg&nbsp;· 28&nbsp;sacks&nbsp;· €60&nbsp;paid&nbsp;· thanked&nbsp;5&nbsp;times</small>' in card('ty-$TYRUN')['html'], '€60&nbsp;paid&nbsp;· thanked&nbsp;6&nbsp;times</small>' in card('tu-$TYRUN')['html'], 0 <= at('ty-$TYRUN') < at('tu-$TYRUN'))")" \
  "(True, True, True)"
curl -s $B/r/$TY2 > "$T/tr.html"; curl -s $B/r/$TZ1 > "$T/tz.html"
grep -qF '<p>Thanked 3 times on sapu.earth.</p>' "$T/tr.html" && grep -qF '<p>Thanked 1 time on sapu.earth.</p>' "$T/tz.html" \
  && [ "$(grep -n 'Thanked 3 times' "$T/tr.html" | cut -d: -f1)" -gt "$(grep -n '^<p>.* by a crew of ' "$T/tr.html" | cut -d: -f1)" ] \
  && [ "$(grep -n 'Thanked 3 times' "$T/tr.html" | cut -d: -f1)" -lt "$(grep -n 'See the cleanup receipt' "$T/tr.html" | cut -d: -f1)" ] \
  && ! grep -iE '<meta[^>]*(thanked|[0-9] times?)' "$T/tr.html" | grep -q . && [ "$(curl -s $B/r/$TU2 | grep -c 'Thanked')" = 0 ] \
  && ok "/r/<id>: its body says \"Thanked 3 times on sapu.earth.\" after the description (1 time on the receipt of the deactivated crew), nothing at 0, and no meta tag carries a count" \
  || bad "/r/<id> thanks" "$(grep -n -i 'thank' "$T/tr.html" "$T/tz.html")"
check "GET /api/admin/submissions: approved cleanups carry their thanks and the answer thanks_caps; a pending one thanks None, and no THANKS BY DAY there" \
  "$(curl -s "$B/api/admin/submissions?status=approved" -H "$A" | jget "(sorted(s.get('thanks') for s in d['submissions'] if s['id'] in ('$TY1', '$TY2')), all(type(s.get('thanks')) is int for s in d['submissions']), d.get('thanks_caps'))") $(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "([s.get('thanks', 'missing') for s in d['submissions'] if s['id'] == '$TYP'], 'thanks_days' in d)")" \
  "([2, 3], True, {'receipt': 1000, 'site': 5000, 'busy_site': 200, 'busy_receipt': 100}) ([None], False)"
grep -qF 'export const THANKS = { perReceiptDay: 1000, perSiteDay: 5000, busySite: 200, busyReceipt: 100, days: 7 };' functions/_lib/social.js \
  && ok "thanks_caps are the THANKS of functions/_lib/social.js" || bad "THANKS in social.js" ""
check "THANKS BY DAY lists today: open, nothing taken off, under the cap, at least these 12 thanks, the receipt with the most on top (at least TU's 6)" \
  "$(tday "$TODAY" "(t['closed'], t['taken'], t['full'], t['n'] >= 12, sorted(t['top']), t['top']['n'] >= 6)")" "(False, 0, False, True, ['id', 'n', 'place_name'], True)"
[ -n "$STATE" ] && check "its count is today's sum of the day rows" "$(tday "$TODAY" "t['n']")" "$(tq "SELECT SUM(n) FROM thanks_days WHERE day = '$TODAY'")"
[ -n "$STATE" ] && TSN=$(tq "SELECT n FROM thanks_site WHERE day = '$TODAY'") && TSC=$(tq "SELECT counted FROM thanks_site WHERE day = '$TODAY'")
check "UNPUBLISH a receipt with 3 thanks, before any undo -> rejected, gone from /api/events" \
  "$(sdec "{\"id\":\"$TY2\",\"action\":\"reject\",\"review_note\":\"Unpublished after approval\"}") $(tev $TY2)" "rejected []"
[ -n "$STATE" ] && check "its thanks went in the same batch: no total or day row left, today's site count 3 lower, what today counted unchanged (no room opens under the site cap), the counts still agree" \
  "$(tq "SELECT COUNT(*) FROM thanks WHERE submission_id = '$TY2'") $(tq "SELECT COUNT(*) FROM thanks_days WHERE submission_id = '$TY2'") $(( ${TSN:-0} - $(tq "SELECT n FROM thanks_site WHERE day = '$TODAY'") )) $(( ${TSC:-0} - $(tq "SELECT counted FROM thanks_site WHERE day = '$TODAY'") )) $(tsums)" "0 0 3 0 []"
check "POST /api/admin/thanks/undo: without the token 401, day x 400, id BAD 400, a day with nothing 404 day, a receipt without thanks that day 404 day" \
  "$(code -X POST $B/api/admin/thanks/undo -H 'content-type: application/json' -d "{\"day\":\"$TODAY\"}") $(tundo '{"day":"x"}') $(tundo "{\"day\":\"$TODAY\",\"id\":\"BAD\"}") $(tundo '{"day":"2020-01-01"}') $(tyj "d.get('code')") $(tundo "{\"day\":\"$TODAY\",\"id\":\"$TU2\"}") $(tyj "d.get('code')")" \
  "401 400 400 404 day 404 day"
if [ -n "$STATE" ]; then
  # The undos, on a day of their own two to six days back (the first one without thanks), so today never closes and a
  # second run on the same day finds a day of its own.
  TD=; for k in 2 3 4 5 6; do x=$(dplus -$k); [ "$(tq "SELECT COUNT(*) FROM thanks_site WHERE day = '$x'")" = 0 ] && { TD=$x; break; }; done
  if [ -n "$TD" ]; then
    d1 "INSERT INTO thanks_days (submission_id, day, n) VALUES ('$TU1', '$TD', 30), ('$TU2', '$TD', 5); INSERT INTO thanks_site (day, n, counted) VALUES ('$TD', 35, 35);
        INSERT INTO thanks (submission_id, n) VALUES ('$TU1', 30) ON CONFLICT (submission_id) DO UPDATE SET n = n + 30;
        INSERT INTO thanks (submission_id, n) VALUES ('$TU2', 5) ON CONFLICT (submission_id) DO UPDATE SET n = n + 5;" >/dev/null
    check "a day seeded with 30 thanks on TU's first receipt and 5 on its second: in THANKS BY DAY with the first on top, the counts agree" \
      "$(tday "$TD" "(t['n'], t['closed'], t['taken'], t['top'])") $(tev $TU1) $(tev $TU2) $(tsums)" "(35, False, 0, {'id': '$TU1', 'place_name': 'TU first $TYRUN', 'n': 30}) [36] [5] []"
    st="$(tundo "{\"day\":\"$TD\",\"id\":\"$TU1\"}") $(tyj "(d.get('day') == '$TD', d.get('id') == '$TU1', d.get('taken'))")"
    check "UNDO ON THAT RECEIPT -> 200 {day, id, taken 30}: its total 30 lower, the day's site count 5 while what it counted stays 35 (no room under the site cap), its day row 0 with 30 taken off" \
      "$st $(tev $TU1) $(tq "SELECT n FROM thanks_site WHERE day = '$TD'") $(tq "SELECT counted FROM thanks_site WHERE day = '$TD'") $(d1 "SELECT n, undone FROM thanks_days WHERE day = '$TD' AND submission_id = '$TU1'" | jget "[(r['n'], r['undone']) for r in d[0]['results']]")" \
      "200 (True, True, 30) [6] 5 35 [(0, 30)]"
    check "THANKS BY DAY then: that day with 5 thanks, 30 taken off, still open, the second receipt on top" \
      "$(tday "$TD" "(t['n'], t['taken'], t['closed'], t['top'])")" "(5, 30, False, {'id': '$TU2', 'place_name': 'TU second $TYRUN', 'n': 5})"
    check "the same UNDO ON THAT RECEIPT again -> 404 day" "$(tundo "{\"day\":\"$TD\",\"id\":\"$TU1\"}") $(tyj "d.get('code')")" "404 day"
    st="$(tundo "{\"day\":\"$TD\"}") $(tyj "(d.get('id'), d.get('taken'))")"
    check "UNDO THE WHOLE DAY -> 200, taken 5: the second receipt's total 5 lower, the day closed (0 left, undone 5), listed as undone with 35 taken off" \
      "$st $(tev $TU2) $(d1 "SELECT n, undone FROM thanks_site WHERE day = '$TD'" | jget "[(r['n'], r['undone']) for r in d[0]['results']]") $(tday "$TD" "(t['n'], t['closed'], t['taken'], t['top'])")" \
      "200 (None, 5) [0] [(0, 5)] (0, True, 35, None)"
    check "the same UNDO THE WHOLE DAY again -> 404 day" "$(tundo "{\"day\":\"$TD\"}") $(tyj "d.get('code')")" "404 day"
    check "today is untouched: a thanks on the second receipt counts, and the counts agree" "$(ty $TU2) $(tyj "(d.get('thanks'), d.get('counted'))") $(tsums)" "200 (1, True) []"
  else
    echo "NOTE  the days 2 to 6 back all have thanks already (a server used for many runs this week), so the undos are not checked"
  fi
  # Deploy order: if the code goes live before migration 0007, nothing shows a count and the new endpoints answer 503.
  PRENAMED=1
  if soff >/dev/null; then
    E1="$(curl -s -o "$T/e.json" -w '%{http_code}' $B/api/events) $(jget "any('thanks' in e for e in d)" < "$T/e.json")"
    E2="$(ty $TY1) $(tyj "d.get('code')")"
    E3="$(tundo "{\"day\":\"$TODAY\"}") $(tyj "d.get('code')")"
    E4="$(curl -s -o "$T/e.html" -w '%{http_code}' $B/p/ty-$TYRUN) $(grep -c 'thanked' "$T/e.html") $(curl -s -o "$T/e.html" -w '%{http_code}' $B/crews) $(grep -c 'thanked' "$T/e.html")"
    E5="$(curl -s -o "$T/e.json" -w '%{http_code}' "$B/api/admin/submissions?status=approved" -H "$A") $(jget "(all(s.get('thanks', 'missing') is None for s in d['submissions']), d.get('thanks_days', 'missing'), d.get('thanks_caps', 'missing'))" < "$T/e.json")"
    E6="$(curl -s -o "$T/e.json" -w '%{http_code}' "$B/api/partner?k=$TYT") $(jget "('thanks_total' in d, any('thanks' in x for x in d['submissions']))" < "$T/e.json")"
    E7="$(curl -s -o "$T/e.html" -w '%{http_code}' $B/r/$TY1) $(grep -c 'Thanked' "$T/e.html")"
    son >/dev/null && PRENAMED=
    check "without the tables of migration 0007: /api/events -> 200, no receipt carries thanks (the homepage shows no button)" "$E1" "200 False"
    check "without them: POST /api/thanks -> 503 migration" "$E2" "503 migration"
    check "without them: POST /api/admin/thanks/undo -> 503 migration" "$E3" "503 migration"
    check "without them: /p/<slug> and /crews -> 200 with no thanks" "$E4" "200 0 200 0"
    check "without them: APPROVED -> 200, thanks None on every card, no THANKS BY DAY (thanks_days and thanks_caps None)" "$E5" "200 (True, None, None)"
    check "without them: GET /api/partner -> 200, no thanks_total and no thanks on its cleanups (the crew page shows no thanks line)" "$E6" "200 (False, False)"
    check "without them: /r/<id> -> 200 with no count" "$E7" "200 0"
    check "tables back in place: the counts show again" "$(tev $TY1)" "[2]"
  else
    PRENAMED=
    bad "rename the tables of migration 0007 in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi
check "reject TY's pending cleanup and deactivate crews TY and TU, so none of this part's crews stays on /crews or in PENDING" \
  "$(sdec "{\"id\":\"${TYP:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}") $(cxoff "$TYPID") $(cxoff "$TUPID")" "rejected 200 200"

# ---------- Scheduled housekeeping (POST /api/housekeeping) ----------
# GitHub Actions calls POST /api/housekeeping a few times a day (.github/workflows/housekeeping.yml): the
# mission expiry, the photo sweep, the application retention, the 48-hour cleanup of loose files of
# every crew and the logo sweep, then how much waits for Marcus (counts only). The jobs run at most once per 10 minutes per
# data center. Locally that mark is in the Cache API of the server, inside STATE, which scripts/test.sh
# starts empty, so only the first POST here does the work: the loose file is aged before it.
# Crew HK leaves a cleanup in PENDING, a mission in review, an application and a logo. Crew HO uploads two loose
# files and is deactivated, so it never uploads (and never starts its own cleanup) again.
HRUN=$RANDOM$RANDOM
# An older application waits through this part. With one waiting row of a kind, the newest and the oldest
# are the same, so the newest checks below could not tell them apart.
st=$(apply "ip=2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::9" "org_name=Housekeeping Older $HRUN"); HOLD=$(rj "d['id']")
check "an older application comes in and waits through this part" "$st" 201
HOLDT=$(alist | jget "[a['created_at'] for a in d['applications'] if a['id'] == '$HOLD'][0]")
sleep 1.1 # HT0 is a whole second, so the older application is before it
# Crew HK's cleanup, mission and application come in after this moment: the newest of each kind.
HT0=$(python3 -c "import datetime as t;print(t.datetime.now(t.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")
HKJ=$(newp "Housekeeping Crew $HRUN" ID "housekeeping-$HRUN"); HKT=$(echo "$HKJ" | jget "d['token']"); HKPID=$(echo "$HKJ" | jget "d['id']")
HOJ=$(newp "Housekeeping Loose Files $HRUN" PH "housekeeping-loose-$HRUN"); HOT=$(echo "$HOJ" | jget "d['token']"); HOPID=$(echo "$HOJ" | jget "d['id']")
HB=$(upk $HKT before); HA=$(upk $HKT after); HN=$(upk $HKT before)
st=$(msub $HKT - "$HB,$HA"); HSUB=$(mj "d['id']")
st="$st $(mpost $HKT "place_name=Housekeeping $HRUN" "media=$HN")"; HMIS=$(mj "d['id']")
st="$st $(apply "ip=2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::7" "org_name=Housekeeping $HRUN")"; HAPP=$(rj "d['id']")
st="$st $(lpost $HKT $T/logo.jpg)"; HKLK=$(lkey)
st="$st $(tpost $HKT '{"account":"@kru.housekeeping"}')"
check "crew HK leaves a cleanup in PENDING, a mission in review, an application, a logo and a TikTok account" "$st" "200 201 201 201 200"
KO=$(upk $HOT before); KF=$(upk $HOT before)
[[ $KO =~ ^[0-9a-f]{32}$ && $KF =~ ^[0-9a-f]{32}$ ]] && ok "crew HO uploads two loose files" || bad "crew HO uploads" "$KO $KF"
check "deactivate crew HO -> 200, its link stops working" \
  "$(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$HOPID\"}") $(code "$B/api/partner?k=$HOT")" "200 404"

# hk: POST /api/housekeeping. Prints the status, the body goes to $T/hk.json, the headers to $T/hk.h.
hk()    { curl -s -o "$T/hk.json" -D "$T/hk.h" -w '%{http_code}' -X POST $B/api/housekeeping; }
hkj()   { jget "$1" < "$T/hk.json"; }
HKW="(d['waiting']['applications'], d['waiting']['missions'], d['waiting']['cleanups'], d['waiting']['logos'], d['waiting']['tiktok'])"

HAGED=; HFRESH=; HTRIM=; HLOGO=; HPOST=; HTIK=
if [ -n "$STATE" ]; then
  check "both loose files are in R2 (signed links -> 200 200)" "$(code "$B$(hsig $KO)") $(code "$B$(hsig $KF)")" "200 200"
  # Older than every other loose file, so it is in the one batch of 50 even on a long-used database.
  d1 "UPDATE uploads SET created_at = '$(ago 400)' WHERE key = '$KO'" >/dev/null && HAGED=1 \
    || bad "age a loose file in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  # This run's first partner is the oldest one: the database (and so the cache) started empty.
  [ "$(d1 "SELECT id FROM partners ORDER BY created_at, id LIMIT 1" | jget "d[0]['results'][0]['id']")" = "$PID" ] && HFRESH=1
  # The 90-day trim of private details (functions/_lib/retention.js). Decided 100 days ago: the approved
  # cleanup SP, the unpublished cleanup SUBM and the done mission MA. Decided 10 days ago: a rejected cleanup
  # written here (TFRESH). Not decided: crew HK's pending cleanup. Each gets a message and an exact point.
  TRIMSET="private_note = 'e2e private', lat = 1.23456789, lng = 103.98765432"
  TFRESH=$(python3 -c "import random;print(''.join(random.choice('abcdefghijklmnopqrstuvwxyz234567') for _ in range(10)))")
  HKPID=$(echo "$HKJ" | jget "d['id']")
  d1 "UPDATE submissions SET $TRIMSET, reviewed_at = '$(ago 100)' WHERE id IN ('$SP', '$SUBM')" >/dev/null \
    && d1 "UPDATE missions SET $TRIMSET, closed_at = '$(ago 100)' WHERE id = '$MA' AND status = 'done'" >/dev/null \
    && d1 "UPDATE submissions SET $TRIMSET WHERE id = '$HSUB' AND status = 'pending'" >/dev/null \
    && d1 "INSERT INTO submissions (id, partner_id, status, created_at, cleanup_date, place_name, crew_size, consent, private_note, lat, lng, reviewed_at)
           VALUES ('$TFRESH', '$HKPID', 'rejected', '$(ago 11)', '$(ago 11 | cut -c1-10)', 'Trim $HRUN', 3, 1, 'e2e private', 1.23456789, 103.98765432, '$(ago 10)')" >/dev/null \
    && HTRIM=1 || bad "set up the 90-day trim in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  # The logo sweep (sweepLogos in functions/_lib/logos.js). Records decided 31 days ago go, one decided 5 days ago
  # stays. A waiting logo of a crew made inactive by SQL (DEACTIVATE would have taken it already) is gone with its
  # file. A logo of an active crew that waited 91 days is declined with its file, so its crew page asks for another.
  HXJ=$(newp "Housekeeping Off Logo $HRUN" ID "hk-off-logo-$HRUN"); HXT=$(echo "$HXJ" | jget "d['token']"); HXPID=$(echo "$HXJ" | jget "d['id']")
  HYJ=$(newp "Housekeeping Old Logo $HRUN" ID "hk-old-logo-$HRUN"); HYT=$(echo "$HYJ" | jget "d['token']"); HYPID=$(echo "$HYJ" | jget "d['id']")
  # The TikTok sweep (sweepCrewTiktok in functions/_lib/tiktok.js): crew HX, made inactive by SQL below (DEACTIVATE would
  # have deleted it already), has a live TikTok account. Its row goes with the next run; crew HK's waiting one stays.
  [ "$(tpost $HXT '{"account":"@kru.hx"}') $(tdec $HXPID kru.hx approve)" = "200 200" ] && HTIK=1 || bad "set up the TikTok sweep" "$(cat "$T/t.json")"
  st="$(lpost $HXT $T/logo.jpg)"; HXK=$(lkey); st="$st $(lpost $HYT $T/logo.jpg)"; HYK=$(lkey)
  HO1=$(openssl rand -hex 16); HO2=$(openssl rand -hex 16); HO3=$(openssl rand -hex 16)
  # The post link sweep (sweepCrewPostLinks in functions/_lib/social.js): crew HX, made inactive by SQL below (DEACTIVATE
  # would have taken its links already), has a receipt that links its own post, and one that links ours as well. Its
  # receipts stop showing its own links at once; the sweep then deletes them, and ours stays.
  HX1B=$(upk $HXT before); HX1A=$(upk $HXT after); HX2B=$(upk $HXT before); HX2A=$(upk $HXT after)
  hpst="$(plsub $HXT "Housekeeping link $HRUN" "$HX1B,$HX1A" "https://www.instagram.com/p/E2eSweep01/")"; HXS1=$(pj "d.get('id')")
  hpst="$hpst $(plsub $HXT "Housekeeping links $HRUN" "$HX2B,$HX2A" "https://www.instagram.com/p/E2eSweep02/")"; HXS2=$(pj "d.get('id')")
  hpst="$hpst $(sdec "{\"id\":\"$HXS1\",\"action\":\"approve\",\"paid_eur\":10}") $(sdec "{\"id\":\"$HXS2\",\"action\":\"approve\",\"paid_eur\":10}")"
  hpst="$hpst $(plink "{\"id\":\"$HXS2\",\"slot\":\"sapu\",\"url\":\"https://www.instagram.com/p/E2eSweepUs/\"}")"
  [ "$st" = "201 201" ] && d1 "UPDATE partners SET active = 0 WHERE id = '$HXPID'; UPDATE logos SET created_at = '$(ago 91)' WHERE key = '$HYK';
      INSERT INTO logos (key, partner_id, status, created_at, decided_at) VALUES
        ('$HO1', '$HYPID', 'declined', '$(ago 40)', '$(ago 31)'), ('$HO2', '$HYPID', 'gone', '$(ago 40)', '$(ago 31)'),
        ('$HO3', '$HYPID', 'declined', '$(ago 6)', '$(ago 5)');" >/dev/null \
    && HLOGO=1 || bad "set up the logo sweep in the local D1 in $STATE" "$st $(tail -3 "$T/d1.err")"
  if [ "$hpst" = "200 200 approved approved 200" ] && [ -n "$HLOGO" ]; then
    check "a receipt of a crew that is not active keeps the name alone: no website, slug, page or logo in /api/events" \
      "$(curl -s $B/api/events | jget "[(e['provider']['url'], e['provider']['slug'], e['provider']['page'], e['provider']['logo']) for e in d if e['id'] == '$HXS1']")" "[(None, None, None, None)]"
    check "the post link sweep: once crew HX is inactive, its receipts show only our link, while its own link is still stored" \
      "$(psoc $HXS1) $(psoc $HXS2) $(prow $HXS1)" "[None] [{'site': 'instagram', 'url': 'https://www.instagram.com/p/E2eSweepUs/', 'by': 'sapu'}] [['https://www.instagram.com/p/E2eSweep01/', None]]"
    HPOST=1
  else
    bad "set up the post link sweep" "$hpst"
  fi
else
  echo "NOTE  STATE is not set, so the housekeeping cleanup of a loose file is not checked (sh scripts/test.sh sets it)"
fi

st=$(hk); HRAN=$(hkj "d['ran']"); HW1=$(hkj "$HKW"); HW1A=$(hkj "d['waiting']['applications']")
HN1=$(hkj "json.dumps(d['newest'])") # {"applications": "...", ...}: double quotes only, so it fits in '...' below
check "POST /api/housekeeping -> 200 {ran, waiting: {applications, missions, cleanups, logos, tiktok, thanks, late}, newest: the same keys}, whole counts" \
  "$st $(hkj "(type(d['ran']) is bool, sorted(d), sorted(d['waiting']), all(type(v) is int and v >= 0 for v in d['waiting'].values()), sorted(d['newest']))")" \
  "200 (True, ['newest', 'ran', 'waiting'], ['applications', 'cleanups', 'late', 'logos', 'missions', 'thanks', 'tiktok'], True, ['applications', 'cleanups', 'late', 'logos', 'missions', 'thanks', 'tiktok'])"
grep -qi '^cache-control: no-store' "$T/hk.h" && ok "the housekeeping answer is never cached" || bad "housekeeping cache-control" "$(tr -d '\r' < "$T/hk.h")"
grep -qE "$HRUN|Housekeeping|housekeeping-" "$T/hk.json" && bad "the housekeeping answer names a crew" "$(cat "$T/hk.json")" || ok "the housekeeping answer has counts only, no names"
check "its counts match the admin lists: new applications, missions in review, cleanups in PENDING, logos and TikTok accounts to check" "$HW1" \
  "($(alist | jget "d['counts']['new']"), $(mlist | jget "d['counts']['review']"), $(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "len(d['submissions'])"), $(curl -s $B/api/admin/partners -H "$A" | jget "d['counts']['logos']"), $(curl -s $B/api/admin/partners -H "$A" | jget "d['counts']['tiktok']"))"
# thanks counts busy days, not something that came in, so these look at the other four (newest.thanks is null here).
HK4="('applications', 'missions', 'cleanups', 'logos', 'tiktok')"
check "crew HK's cleanup, mission, application, logo and TikTok account are counted" "$(hkj "min(d['waiting'][k] for k in $HK4) >= 1")" True
check "newest is when crew HK's cleanup, mission, application, logo and TikTok account came in (ISO times, after the start of this part)" \
  "$(hkj "all(type(v) is str and len(v) == 24 and v.endswith('Z') and v >= '$HT0' for v in (d['newest'][k] for k in $HK4))")" True
if [ -n "$HAGED" ]; then
  if [ "$HRAN" = False ] && [ -z "$HFRESH" ]; then
    echo "NOTE  this server already ran the housekeeping less than 10 minutes ago, so its cleanup of a loose file is not checked this time (sh scripts/test.sh starts a fresh server)"
  else
    check "the first housekeeping POST on a fresh server does the work (ran true)" "$HRAN" True
    check "it deleted the 400-day-old loose file of the deactivated crew: row gone, file gone (signed link -> 404), /media/<key> -> 404" \
      "$(n_up $KO) $(gone "$B$(hsig $KO)") $(code $B/media/$KO)" "0 404 404"
    check "the fresh loose file stays: row and file" "$(n_up $KF) $(code "$B$(hsig $KF)")" "1 200"
    if [ -n "$HLOGO" ]; then
      check "the logo sweep: declined and gone records decided 31 days ago are deleted, one decided 5 days ago stays" \
        "$(d1 "SELECT key FROM logos WHERE key IN ('$HO1', '$HO2', '$HO3')" | jget "[r['key'] for r in d[0]['results']]")" "['$HO3']"
      check "the logo sweep: the waiting logo of a crew that is not active is gone, its file deleted (signed link -> 404)" \
        "$(d1 "SELECT status FROM logos WHERE key = '$HXK'" | jget "d[0]['results'][0]['status']") $(gone "$B$(hsig $HXK)")" "gone 404"
      check "the logo sweep: a logo that waited 91 days is declined, its file deleted, and its crew page says so" \
        "$(d1 "SELECT status FROM logos WHERE key = '$HYK'" | jget "d[0]['results'][0]['status']") $(gone "$B$(hsig $HYK)") $(plogo $HYT "(l['declined'], l['review'])")" "declined 404 (True, None)"
      check "crew HK's fresh logo still waits" "$(plogo $HKT "l['review'] is not None")" True
    fi
    if [ -n "$HPOST" ]; then
      check "the post link sweep: crew HX's own links are deleted (the row with nothing else goes), our link stays" \
        "$(prow $HXS1) $(prow $HXS2)" "[] [[None, 'https://www.instagram.com/p/E2eSweepUs/']]"
    fi
    if [ -n "$HTIK" ]; then
      check "the TikTok sweep: the rows of crew HX (made inactive by SQL) and of the crew deactivated without the table are deleted, crew HK's stays" \
        "$(d1 "SELECT partner_id FROM crew_tiktok WHERE partner_id IN ('$HXPID', '${WPID:-none}', '$HKPID')" | jget "sorted(r['partner_id'] == '$HKPID' for r in d[0]['results'])")" "[True]"
    fi
    if [ -n "$HTRIM" ]; then
      # trimmed <table> <id>: "<private_note> <lat> <lng>" as the local D1 has them.
      trimmed() { d1 "SELECT private_note AS p, lat, lng FROM $1 WHERE id = '$2'" | jget "(lambda r: '%s %s %s' % (r['p'], r['lat'], r['lng']))(d[0]['results'][0])"; }
      check "90 days after the decision: an approved and an unpublished cleanup and a done mission lose the private message, the point is rounded to about 100 m" \
        "$(trimmed submissions $SP) | $(trimmed submissions $SUBM) | $(trimmed missions $MA)" "None 1.235 103.988 | None 1.235 103.988 | None 1.235 103.988"
      check "a cleanup decided 10 days ago and a pending one keep the private message and the exact point" \
        "$(trimmed submissions $TFRESH) | $(trimmed submissions $HSUB)" "e2e private 1.23456789 103.98765432 | e2e private 1.23456789 103.98765432"
      check "the trimmed approved cleanup stays on the globe at the same rounded point" \
        "$(curl -s $B/api/events | jget "[(e['location']['lat'], e['location']['lng']) for e in d if e['id'] == '$SP']")" "[(1.235, 103.988)]"
    fi
  fi
fi
[ -n "$HTRIM" ] && { d1 "DELETE FROM submissions WHERE id = '$TFRESH'" >/dev/null || bad "delete the trim test cleanup" "$(tail -3 "$T/d1.err")"; }
st=$(hk)
check "a second POST right after -> 200, ran false (once per 10 minutes), the same counts" "$st $(hkj "d['ran']") $(hkj "$HKW")" "200 False $HW1"
st="$(sdec "{\"id\":\"$HSUB\",\"action\":\"reject\",\"review_note\":\"e2e\"}") $(act "$HMIS" decline) $(adm reject "{\"id\":\"$HAPP\"}") $(ldec "$HKLK" decline) $(tdec "$HKPID" kru.housekeeping decline)"
check "reject crew HK's cleanup, decline its mission, its logo and its TikTok account, delete its application" "$st" "rejected 200 200 200 200"
st=$(hk)
check "the counts follow at once while the jobs wait out their 10 minutes: one less of each" \
  "$st $(hkj "d['ran']") $(hkj "(d['waiting']['applications'] + 1, d['waiting']['missions'] + 1, d['waiting']['cleanups'] + 1, d['waiting']['logos'] + 1, d['waiting']['tiktok'] + 1)")" "200 False $HW1"
check "newest goes back to an older one (or null) once crew HK's are handled" \
  "$(hkj "all(d['newest'][k] is None or d['newest'][k] < w for k, w in json.loads('$HN1').items() if k in $HK4)")" True
check "newest of the applications is now the older one still waiting: the latest left, not the earliest" \
  "$(hkj "d['newest']['applications']")" "$HOLDT"
# The case the count alone misses: one handled, a new one in. The count is back where it was, but newest
# is later, so the workflow still comments (and Marcus gets the email).
st=$(apply "ip=2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::8" "org_name=Housekeeping Again $HRUN"); HAGAIN=$(rj "d['id']")
st="$st $(hk)"
check "a new application after one was handled: the same count as before, a later newest" \
  "$st $(hkj "d['waiting']['applications']") $(hkj "d['newest']['applications'] > json.loads('$HN1')['applications']")" "201 200 $HW1A True"
check "delete crew HK's other two applications, so a run leaves none behind" \
  "$(adm reject "{\"id\":\"$HAGAIN\"}") $(adm reject "{\"id\":\"$HOLD\"}")" "200 200"
# Busy days of thanks (waiting.thanks): today or yesterday (UTC) with 200 or more standing thanks on the site, or 100 or
# more on one receipt, until an undo takes them out. Set by SQL for a moment and put back, after the first POST.
if [ -n "$STATE" ]; then
  HTS=$(tq "SELECT n FROM thanks_site WHERE day = '$TODAY'"); HTU=$(tq "SELECT n FROM thanks_days WHERE day = '$TODAY' AND submission_id = '$TU1'")
  if [[ $HTS =~ ^[0-9]+$ && $HTU =~ ^[0-9]+$ ]]; then
    d1 "UPDATE thanks_site SET n = 250 WHERE day = '$TODAY'" >/dev/null; st="$(hk) $(hkj "(d['waiting']['thanks'] >= 1, d['newest']['thanks'])")"
    d1 "UPDATE thanks_site SET n = $HTS WHERE day = '$TODAY'" >/dev/null
    check "a day with 250 thanks on the site is busy: waiting.thanks at least 1, newest.thanks that day at 00:00 UTC" "$st" "200 (True, '${TODAY}T00:00:00.000Z')"
    d1 "UPDATE thanks_days SET n = 120 WHERE day = '$TODAY' AND submission_id = '$TU1'; UPDATE thanks_site SET n = n + 120 - $HTU WHERE day = '$TODAY'" >/dev/null
    st="$(hk) $(hkj "(d['waiting']['thanks'] >= 1, d['newest']['thanks'])")"
    d1 "UPDATE thanks_days SET n = $HTU WHERE day = '$TODAY' AND submission_id = '$TU1'; UPDATE thanks_site SET n = $HTS WHERE day = '$TODAY'" >/dev/null
    check "so is a day with 120 on one receipt and fewer than 200 on the site" "$st" "200 (True, '${TODAY}T00:00:00.000Z')"
    check "put back: today is not busy, and the counts agree" "$(hk) $(hkj "d['newest']['thanks'] != '${TODAY}T00:00:00.000Z'") $(tsums)" "200 True []"
  else
    bad "set up the busy days of thanks" "$HTS $HTU"
  fi
fi
# Deploy order (crew logos): before migration 0006 the housekeeping counts no logo. Here, after this part's checks,
# because its first POST must be the one that runs the jobs; this one only counts.
if [ -n "$STATE" ]; then
  LRENAMED=1
  if d1 "ALTER TABLE logos RENAME TO logos_e2e_off" >/dev/null; then
    st=$(hk)
    d1 "ALTER TABLE logos_e2e_off RENAME TO logos" >/dev/null && LRENAMED=
    check "without the logos table: POST /api/housekeeping -> 200, waiting.logos 0, newest.logos None" "$st $(hkj "(d['waiting']['logos'], d['newest']['logos'])")" "200 (0, None)"
  else
    LRENAMED=
    bad "rename the logos table in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
  # Deploy order (post links): before migration 0007 the housekeeping answers with the same counts; its post link sweep
  # then finds no table, which noSocialTables keeps out of the log (checked in node further down).
  PRENAMED=1
  if soff >/dev/null; then
    st=$(hk)
    son >/dev/null && PRENAMED=
    check "without the tables of migration 0007: POST /api/housekeeping -> 200 with the same keys, waiting.thanks 0 and newest.thanks None" \
      "$st $(hkj "(sorted(d['waiting']), sorted(d['newest']), d['waiting']['thanks'], d['newest']['thanks'])")" "200 (['applications', 'cleanups', 'late', 'logos', 'missions', 'thanks', 'tiktok'], ['applications', 'cleanups', 'late', 'logos', 'missions', 'thanks', 'tiktok'], 0, None)"
  else
    PRENAMED=
    bad "rename the tables of migration 0007 in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
  # Deploy order (crew TikTok accounts): before migration 0009 the housekeeping answers waiting.tiktok 0 and newest.tiktok
  # None; its TikTok sweep then finds no table, which noTiktokTable keeps out of the log (checked in node above).
  TRENAMED=1
  if d1 "ALTER TABLE crew_tiktok RENAME TO crew_tiktok_e2e_off" >/dev/null; then
    st=$(hk)
    d1 "ALTER TABLE crew_tiktok_e2e_off RENAME TO crew_tiktok" >/dev/null && TRENAMED=
    check "without the crew_tiktok table: POST /api/housekeeping -> 200, waiting.tiktok 0, newest.tiktok None" "$st $(hkj "(d['waiting']['tiktok'], d['newest']['tiktok'])")" "200 (0, None)"
  else
    TRENAMED=
    bad "rename the crew_tiktok table in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi
grep -qF '["tiktok sweep", sweepCrewTiktok, noTiktokTable],' functions/api/housekeeping.js \
  && grep -qF '["tiktok", "SELECT COUNT(*) AS n, MAX(t.sent_at) AS newest FROM crew_tiktok t JOIN partners p ON p.id = t.partner_id WHERE t.review IS NOT NULL AND p.active = 1", noTiktokTable],' functions/api/housekeeping.js \
  && ok "the housekeeping runs the TikTok sweep and counts the TikTok accounts of active crews that wait, and a missing crew_tiktok table stays out of its log" || bad "housekeeping TikTok" ""
grep -qF '["post link sweep", sweepCrewPostLinks, noSocialTables],' functions/api/housekeeping.js \
  && ok "the housekeeping runs the post link sweep, and a missing table of migration 0007 stays out of its log" || bad "housekeeping post link sweep" ""
# The workflow reads the logos and the busy days of thanks too, and a run between the push and the deploy (neither in
# the answer yet) reads 0.
WF=.github/workflows/housekeeping.yml
# The public copy of this repo leaves the workflow out (its timer would run there too), so there these checks skip it.
inwf() { [ ! -f "$WF" ] || grep -qF "$1" "$WF"; }
[ -f "$WF" ] || echo "NOTE  $WF is not in this copy (the public repo leaves it out), so the checks of its text are skipped"
inwf 'const KEYS = ["applications", "missions", "cleanups", "logos", "tiktok", "thanks", "late"];' && inwf 'const OPTIONAL = ["logos", "tiktok", "thanks", "late"];' \
  && inwf 'tiktok: (n) => `${n} crew TikTok account${n === 1 ? " waits" : "s wait"} for review (PARTNERS, TIKTOK TO CHECK)`,' \
  && inwf 'if (n === undefined && OPTIONAL.includes(k)) n = 0;' \
  && inwf 'logos: (n) => `${n} crew logo${n === 1 ? " waits" : "s wait"} for review (PARTNERS, LOGOS TO CHECK)`,' \
  && inwf 'thanks: (n) => `${n} day${n === 1 ? "" : "s"} with many thanks on sapu.earth (200 or more in all, or 100 or more on one receipt), to check (APPROVED, THANKS BY DAY)`,' \
  && grep -qF 'busySite: 200, busyReceipt: 100' functions/_lib/social.js \
  && ok "the housekeeping workflow says when crew logos or TikTok accounts wait and when a day had many thanks (200 and 100, the numbers of THANKS), and reads a missing logo, TikTok or thanks count as 0" || bad "housekeeping workflow logos, TikTok and thanks" ""
st=$(curl -s -o /dev/null -D "$T/hk.h" -w '%{http_code}' $B/api/housekeeping)
check "GET /api/housekeeping -> 405 with Allow: POST, PUT -> 405" \
  "$st $(tr -d '\r' < "$T/hk.h" | sed -n 's/^[Aa]llow: *//p') $(code -X PUT $B/api/housekeeping)" "405 POST 405"
# Late missions (waiting.late): funded, MISSION_LIMITS.lateDays (3) days or more past their day, with no cleanup in
# PENDING; the workflow emails Marcus and /admin/ marks them LATE. Written by SQL for crew HK: one 4 days past its day
# (late) and one 2 days past (not yet). A cleanup sent for the late one takes it out, a reject puts it back. Here at the
# end, after this part's other counts. While that cleanup waits, PENDING shows its contact: none for crew HK (made with
# NEW PARTNER), and the applicant's for crew HR, approved from an application, for the reply REJECT opens.
grep -qF 'lateDays: 3,' functions/_lib/missions.js && grep -qF 'const LATE_DAYS = 3;' admin/admin.js \
  && inwf 'late: (n) => `${n} funded mission${n === 1 ? " is" : "s are"} 3 days or more past' \
  && grep -qF "date(MAX(\${day}), '+\${MISSION_LIMITS.lateDays} days') || 'T00:00:00.000Z' AS newest" functions/api/housekeeping.js \
  && grep -qF 'const day = spots ? LAST_DAY_SQL("m") : "m.plan_date";' functions/api/housekeeping.js \
  && ok "a funded mission is late 3 days after its day: the limit, /admin/ and the workflow's line agree" || bad "late days in step" ""
if [ -n "$STATE" ]; then
  HL4=$(newid); HL2=$(newid)
  st=$(hk); HLB=$(hkj "d['waiting']['late']")
  if d1 "$(mrow "$HKPID" $HL4 funded $(dplus -4) $(ago 12) $(ago 11) $(ago 10) 10 3) $(mrow "$HKPID" $HL2 funded $(dplus -2) $(ago 12) $(ago 11) $(ago 10) 10 3)" >/dev/null; then
    st="$st $(hk)"; HLA=$(hkj "d['waiting']['late']")
    check "a funded mission 4 days past its day counts as late, one 2 days past not yet; newest.late is the day it became late, at 00:00 UTC" \
      "$st $HLA $(hkj "d['newest']['late']")" "200 200 $(add "$HLB" 1) $(dplus -1)T00:00:00.000Z"
    L=$(mlist funded)
    check "/admin/ marks the one 4 days past LATE (not OVERDUE yet), the one 2 days past neither" \
      "$(echo "$L" | mq "$HL4" "(m['late'], m['overdue'])") $(echo "$L" | mq "$HL2" "(m['late'], m['overdue'])")" "(True, False) (False, False)"
    HLK1=$(upk $HKT before); HLK2=$(upk $HKT after)
    st=$(msub $HKT $HL4 "$HLK1,$HLK2"); HLS=$(mj "d.get('id')"); st="$st $(hk)"
    check "a cleanup sent for the late mission takes it out of the count, and /admin/ no longer marks it LATE" \
      "$st $(hkj "d['waiting']['late']") $(mlist funded | mq "$HL4" "m['late']")" "200 200 $HLB False"
    st=$(apply "ip=2001:db8:$(printf '%x:%x' $RANDOM $RANDOM)::b" "org_name=Reject Reply $HRUN" lang=id contact_name=Dewi "whatsapp=+6281211112222"); HRA=$(rj "d['id']")
    st="$st $(adm approve "$(lab "$HRA" "Reject Reply $HRUN" "reject-reply-$HRUN")")"; HRT=$(rj "d['partner']['token']"); HRP=$(rj "d['partner']['id']")
    HRK1=$(upk $HRT before); HRK2=$(upk $HRT after); st="$st $(msub $HRT - "$HRK1,$HRK2")"; HRS=$(mj "d.get('id')")
    PS=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A")
    check "PENDING carries the contact for the reply REJECT opens: the applicant's name, WhatsApp, email and language for crew HR, none for crew HK (NEW PARTNER)" \
      "$st $(echo "$PS" | jget "[s['contact'] for s in d['submissions'] if s['id'] == '$HRS']") $(echo "$PS" | jget "[s['contact'] for s in d['submissions'] if s['id'] == '$HLS']")" \
      "201 201 200 [{'contact_name': 'Dewi', 'whatsapp': '+6281211112222', 'email': 'crew-$RUN@example.org', 'lang': 'id'}] [None]"
    check "the rejected list carries no contact" "$(curl -s "$B/api/admin/submissions?status=rejected" -H "$A" | jget "all(s['contact'] is None for s in d['submissions'])")" True
    check "reject crew HR's cleanup and deactivate crew HR" \
      "$(sdec "{\"id\":\"$HRS\",\"action\":\"reject\",\"review_note\":\"e2e\"}") $(code -X POST $B/api/admin/partners/deactivate -H "$A" -H 'content-type: application/json' -d "{\"id\":\"$HRP\"}")" "rejected 200"
    st=$(sdec "{\"id\":\"$HLS\",\"action\":\"reject\",\"review_note\":\"e2e\"}"); st="$st $(hk)"
    check "rejecting the cleanup for the late mission puts it back in the count" "$st $(hkj "d['waiting']['late']")" "rejected 200 $HLA"
    d1 "UPDATE missions SET status = 'removed', removed_why = 'cancelled', closed_at = '$(ago 0)', private_note = NULL, lat = NULL, lng = NULL WHERE id IN ('$HL4', '$HL2')" >/dev/null
    check "both cancelled: the late count is back where it was" "$(hk) $(hkj "d['waiting']['late']")" "200 $HLB"
  else
    bad "set up the late missions in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# Private paths stay private, public pages still load.
for p in /ops/verification.md /README.md /readme.md /docs/upload-flow.md /docs/missions.md /migrations/0001_init.sql /migrations/0003_applications.sql \
         /migrations/0004_missions.sql /migrations/0005_video_stage.sql /functions/_lib/util.js /functions/_lib/missions.js /functions/_lib/asset-version.js \
         /data/README.md /%6fps/verification.md //ops/verification.md /%52EADME.md /scripts/dev.sh; do
  check "$p -> 404" "$(code --path-as-is "$B$p")" 404
done
# The middleware's backstop (functions/_middleware.js): any first path segment that starts with a dot (except
# /.well-known/) and the folders that are not part of the site answer its plain 404, so even a deploy of the repo
# folder itself (instead of dist/) would not serve them. /.well-known/ is left to the site: the not found page.
PB=""
for p in /.env.cloudflare /.dev.vars /.github/workflows/housekeeping.yml /.gitignore /.git/config /%2Eenv.cloudflare /tests/e2e.sh \
         /assets/brand/x /reports/x /research_notes/x /public-repo/README.md; do
  st=$(curl -s --path-as-is -o "$T/pb.txt" -w '%{http_code}' "$B$p")
  [ "$st" = 404 ] && [ "$(cat "$T/pb.txt")" = "Not found" ] || PB="$PB $p:$st"
done
st=$(curl -s -o "$T/nf.html" -w '%{http_code}' "$B/.well-known/no-such")
[ "$st" = 404 ] && grep -qF '<title>Not found · Sapu Earth</title>' "$T/nf.html" || PB="$PB /.well-known/no-such:$st"
[ -z "$PB" ] && ok "dotfiles and folders that are not the site (/.env.cloudflare, /.dev.vars, /.github/, /tests/, /assets/, /reports/) -> the middleware's plain 404; /.well-known/ is left to the site" \
  || bad "middleware backstop" "$PB"
# Any other path answers 404 with the not found page (404.html, which scripts/build-site.sh copies). Without it Pages
# takes the site for a single-page app and answers 200 with the homepage, also for /.env.cloudflare or /wrangler.toml,
# which scanners report. The file itself is never served either.
NF=""
for p in /wrangler.toml /package.json \
         /favicon.ico /sitemap-old.xml /api/no-such-route /site/no-such.css /site/fonts/no-such.woff2 /upload/no-such /admin/no-such.js \
         /apply/a/b /impressum/x /stories/no-such/ /data/events/no-such.json /no/such/page/; do
  st=$(curl -s -o "$T/nf.html" -w '%{http_code}' "$B$p")
  [ "$st" = 404 ] && grep -qF '<title>Not found · Sapu Earth</title>' "$T/nf.html" && ! grep -qF 'site/app.js' "$T/nf.html" || NF="$NF $p:$st"
done
[ -z "$NF" ] && ok "unknown paths (/wrangler.toml, /package.json, /api/, /site/, /upload/ and more) -> 404 with the not found page" \
  || bad "unknown paths -> the not found page" "$NF"
# The tab icon and the home screen icon are the broom microphone (site/brand/sapu-sketch/): a 32 px PNG for browsers
# that take no SVG icon, the SVG, and the touch icon. Every static page links all three, so does every page a Function
# renders, the three files are served as images, and nothing links the old globe icon (site/avatar.svg) any more.
IC=""
for p in / /apply/ /impressum/ /upload/ /admin/ /stories/ /stories/trash-in-numbers/ /stories/trash-in-numbers/id/ /stories/trash-with-a-passport/ /stories/trash-with-a-passport/id/ /no/such/page/; do
  curl -s "$B$p" > "$T/icon.html"
  for f in favicon-32.png favicon.svg apple-touch-icon.png; do
    grep -qF "site/brand/sapu-sketch/$f\"" "$T/icon.html" || IC="$IC $p:$f"
  done
  grep -qF 'site/avatar.' "$T/icon.html" && IC="$IC $p:avatar"
done
[ -z "$IC" ] && ok "every static page and the not found page link the broom icons (PNG, SVG, touch icon), not the old avatar" || bad "icon links in the static pages" "$IC"
IC=""
for f in functions/crews/index.js functions/missions/index.js "functions/r/[id].js" "functions/p/[slug].js" "functions/m/[no].js"; do
  for i in favicon-32.png favicon.svg apple-touch-icon.png; do
    grep -qF "\"/site/brand/sapu-sketch/$i\"" "$f" || IC="$IC $f:$i"
  done
done
grep -rlF 'site/avatar.' functions index.html 404.html apply admin impressum upload > "$T/icon.old" 2>/dev/null
[ -z "$IC" ] && [ ! -s "$T/icon.old" ] && ok "the pages a Function renders (/crews, /missions, /r, /p, /m) link the broom icons, and no source links site/avatar" \
  || bad "icon links in the Function pages" "$IC $(tr '\n' ' ' < "$T/icon.old")"
for f in favicon.svg:image/svg+xml favicon-32.png:image/png apple-touch-icon.png:image/png broom.svg:image/svg+xml broom-pointer-32.png:image/png broom-pointer-64.png:image/png; do
  check "/site/brand/sapu-sketch/${f%%:*} is served as ${f#*:}" \
    "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B/site/brand/sapu-sketch/${f%%:*}")" "200 ${f#*:}"
done
# The broom leans on the SAPU EARTH title of every page (site/styles.css, .logo::after; the small title in
# site/forms.css): CSS draws it from broom.svg with a set width and height (no aspect-ratio, Safari before 15), the
# title's text is unchanged, and on a phone narrower than 360 px there is no broom and no room kept for it, so the
# language switch of /apply/ and /upload/ stays on the screen.
curl -s "$B/site/styles.css" > "$T/broom.css"; curl -s "$B/site/forms.css" > "$T/broom-forms.css"
BR=""
grep -qF '.logo { position: relative; display: inline-block; padding-right: 1.9em; }' "$T/broom.css" || BR="$BR room"
grep -qF 'background: url("brand/sapu-sketch/broom.svg") no-repeat center / contain;' "$T/broom.css" || BR="$BR picture"
grep -qF 'width: 1.655em; height: 2em;' "$T/broom.css" || BR="$BR size"
tr '\n' ' ' < "$T/broom.css" | grep -qF '@media (max-width: 359px) {   .logo { padding-right: 0; }   .logo::after { display: none; } }' || BR="$BR narrow"
grep -qF '.logo-sm::after { width: 1.406em; height: 1.7em; }' "$T/broom-forms.css" || BR="$BR small-size"
grep -qF '@media (max-width: 359px) { .logo-sm { padding-right: 0; } }' "$T/broom-forms.css" || BR="$BR small-narrow"
[ -z "$BR" ] && ok "the title's broom: drawn by CSS from broom.svg at a set size, smaller on the small title, and gone under 360 px" \
  || bad "the title's broom in site/styles.css and site/forms.css" "$BR"
TB=""
for p in / /apply/ /impressum/ /upload/ /admin/ /crews /missions /stories/ /stories/trash-in-numbers/ /stories/trash-in-numbers/id/ /stories/trash-with-a-passport/ /stories/trash-with-a-passport/id/ /no/such/page/; do
  curl -s "$B$p" | tr '\n' ' ' | grep -qE 'class="logo( logo-sm)?"[^>]*>SAPU<br>EARTH</' || TB="$TB $p"
done
[ -z "$TB" ] && ok "every page's title is still the text SAPU EARTH (the broom adds no markup)" || bad "the title's markup" "$TB"
# With a mouse the pointer over a mission tag on the globe is the broom, and the tag sweeps once (site/styles.css,
# site/app.js missionPin): only for a mouse (hover: hover, pointer: fine), with the hand as the fallback, a 32 px and a
# 64 px picture of those sizes, the click point 5 px in, a sweep that a class runs and animationend takes off again,
# and no sweep for a visitor who asked for less motion.
curl -s "$B/site/app.js" > "$T/broom-app.js"
BP=""
tr '\n' ' ' < "$T/broom.css" | grep -qF '@media (hover: hover) and (pointer: fine) {   .mpin .mpin-tag {     cursor: url("brand/sapu-sketch/broom-pointer-32.png") 5 5, pointer;     cursor: -webkit-image-set(url("brand/sapu-sketch/broom-pointer-32.png") 1x, url("brand/sapu-sketch/broom-pointer-64.png") 2x) 5 5, pointer;     cursor: image-set(url("brand/sapu-sketch/broom-pointer-32.png") 1x, url("brand/sapu-sketch/broom-pointer-64.png") 2x) 5 5, pointer;   }   .mpin .mpin-tag.mpin-sweep { animation: mpin-sweep .7s ease-in-out; }   .mpin .mpin-funded.mpin-sweep { animation-name: mpin-sweep-funded; } }' || BP="$BP pointer-rule"
grep -qF '@keyframes mpin-sweep {' "$T/broom.css" && grep -qF '@keyframes mpin-sweep-funded {' "$T/broom.css" || BP="$BP keyframes"
grep -A2 -F '@keyframes mpin-sweep {' "$T/broom.css" | grep -qF '0%, 100% { transform: translateX(-50%) rotate(-3deg); }' || BP="$BP open-rest"
grep -A2 -F '@keyframes mpin-sweep-funded {' "$T/broom.css" | grep -qF '0%, 100% { transform: translateX(-50%) rotate(2deg); }' || BP="$BP funded-rest"
tr '\n' ' ' < "$T/broom.css" | grep -qE '@media \(prefers-reduced-motion: reduce\) \{[^@]*\.mpin \.mpin-tag\.mpin-sweep \{ animation: none; \}' || BP="$BP less-motion"
grep -qF 'tag.addEventListener("pointerenter", (ev) => { if (ev.pointerType === "mouse") tag.classList.add("mpin-sweep"); });' "$T/broom-app.js" || BP="$BP enter"
grep -qF 'tag.addEventListener("animationend", () => tag.classList.remove("mpin-sweep"));' "$T/broom-app.js" || BP="$BP end"
for s in 32 64; do
  curl -s "$B/site/brand/sapu-sketch/broom-pointer-$s.png" > "$T/broom-pointer.png"
  [ "$(od -An -tu1 -j16 -N8 "$T/broom-pointer.png" | tr -s ' ' | sed 's/^ //;s/ $//')" = "0 0 0 $s 0 0 0 $s" ] || BP="$BP size-$s"
done
[ -z "$BP" ] && ok "the broom pointer on mission tags: mouse only, 32 and 64 px pictures, the hand as fallback, one sweep that ends by itself, none with less motion" \
  || bad "the broom pointer and the sweep on mission tags" "$BP"
for f in .dev.vars tests/e2e.sh .dev/wrangler.toml .gitignore; do
  [ -f "$f" ] || continue
  if curl -s "$B/$f" | grep -qF "$(head -1 "$f")"; then bad "/$f is not served" "file content came back"; else ok "/$f is not served"; fi
done
NFP=$(curl -s $B/no-such-page)
echo "$NFP" | grep -qF '<meta name="robots" content="noindex">' && echo "$NFP" | grep -qF '<h1 class="fp-title"><mark>NOT FOUND</mark></h1>' \
  && echo "$NFP" | grep -qF '<p class="fp-lead">There is no page at this address. The link may be old, or it may have a typo.</p>' \
  && echo "$NFP" | grep -qF '<p class="hint" lang="id">Halaman ini tidak ditemukan.</p>' \
  && echo "$NFP" | grep -qF '<a class="btn" href="/">SEE THE GLOBE</a>' && echo "$NFP" | grep -qF '<a href="/impressum/">IMPRESSUM</a>' \
  && [ "$(echo "$NFP" | grep -cE 'href="/site/(fonts|styles|forms)\.css\?v=[A-Za-z0-9]+"')" = 3 ] \
  && ! echo "$NFP" | grep -qiE '<script' && ! echo "$NFP" | grep -qE '(src|href)="[^/]' \
  && ok "the not found page: noindex, NOT FOUND, one line in Indonesian, SEE THE GLOBE and IMPRESSUM, the versioned CSS, no script, every link from the root" \
  || bad "the not found page" "$(echo "$NFP" | head -20)"
# Every real path answers as before: the pages, their forms without the slash and /index.html (308), the static files,
# the Functions with their own answers, and the private paths with the middleware's 9-byte "Not found". /m/<no> and
# /p/<slug> of a live mission and crew answer 200 in their own checks above, with 404.html already in the build.
RPS=""
for pc in "/ 200" "/upload/ 200" "/admin/ 200" "/apply/ 200" "/impressum/ 200" "/index.html 308 /" "/upload 308 /upload/" "/upload/index.html 308 /upload/" \
          "/admin 308 /admin/" "/apply 308 /apply/" "/impressum 308 /impressum/" "/site/styles.css 200" "/site/app.js 200" \
          "/stories/ 200" "/stories 308 /stories/" "/stories/trash-in-numbers/ 200" "/stories/trash-in-numbers 308 /stories/trash-in-numbers/" \
          "/stories/trash-in-numbers/id/ 200" "/stories/trash-in-numbers/img/card-en.jpg 200" \
          "/stories/trash-with-a-passport/ 200" "/stories/trash-with-a-passport 308 /stories/trash-with-a-passport/" \
          "/stories/trash-with-a-passport/id/ 200" "/stories/trash-with-a-passport/img/card-id.jpg 200" \
          "/site/fonts/barlow-v13-latin-600.woff2 200" "/site/vendor/globe.gl-2.32.0.min.js 200" "/data/events/index.json 200" "/api/events 200" \
          "/api/missions 200" "/api/partner 404" "/api/admin/partners 401" "/r/$ID 200" "/media/$KB 200" "/crews 200" "/crews/ 200"; do
  read -r p want wloc <<< "$pc"
  st=$(curl -s -o /dev/null -D "$T/rp.h" -w '%{http_code}' "$B$p"); loc=$(tr -d '\r' < "$T/rp.h" | sed -n 's/^[Ll]ocation: *//p')
  [ "$st${loc:+ $loc}" = "$want${wloc:+ $wloc}" ] || RPS="$RPS [$p: $st${loc:+ $loc}]"
done
[ -z "$RPS" ] && ok "every real path answers as before: the pages, /upload and the other forms without the slash and /index.html (308), /site/, /data/events/, /api/, /r/<id>, /media/<key>, and /crews with and without the slash" \
  || bad "real paths" "$RPS"
check "the Functions and the middleware keep their own not found answers: /m/<no>, /r/<id>, /p/<slug>, /media/<key>, /ops/" \
  "$(m404 999999999) $(curl -s $B/r/aaaaaaaaaa) $(curl -s $B/p/nobody-here) $(curl -s $B/media/00000000000000000000000000000000) $(curl -s --path-as-is $B/%6fps/verification.md)" \
  "404 friendly Not found Not found Not found Not found"
check "homepage 200" "$(code $B/)" 200
curl -s $B/ | grep -q 'site/app.js' && ok "homepage HTML intact" || bad "homepage" ""
check "static demo events still served" "$(code $B/data/events/index.json)" 200
check "/upload/ 200" "$(code $B/upload/)" 200
check "/admin/ 200" "$(code $B/admin/)" 200
# Browsers keep .js and .css for 4 hours, so every page must link the build's versioned files.
AJS=$(curl -s $B/admin/ | grep -oE '/admin/admin\.js\?v=[A-Za-z0-9]+' | head -1)
[ -n "$AJS" ] && ok "/admin/ links a versioned admin.js ($AJS)" || bad "versioned admin.js" "no ?v= on the admin script"
check "the versioned admin.js is served" "$(code "$B$AJS")" 200
for p in / /upload/ /apply/ /admin/ /no-such-page; do
  PG=$(curl -s "$B$p")
  echo "$PG" | grep -vE 'site/vendor/' | grep -qE '(src|href)="/?(site|upload|apply|admin)/[^"?]+\.(js|css)"' && bad "$p links an unversioned script or stylesheet" "" || ok "$p links only versioned scripts and stylesheets"
  # Fonts are self-hosted (site/fonts.css, site/fonts/): no page asks Google for anything.
  echo "$PG" | grep -qE '(src|href)="/?site/fonts\.css\?v=[A-Za-z0-9]+"' && ok "$p links the self-hosted fonts.css" || bad "$p fonts.css" "no versioned site/fonts.css link"
  echo "$PG" | grep -qE 'fonts\.(googleapis|gstatic)\.com' && bad "$p loads Google Fonts" "" || ok "$p loads no Google Fonts"
done
FN=0
for f in $(curl -s $B/site/fonts.css | grep -oE 'fonts/[A-Za-z0-9._-]+\.woff2' | sort -u); do
  FN=$((FN+1))
  curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B/site/$f" | grep -q '^200 font/woff2' || bad "/site/$f" "not served as font/woff2"
done
check "site/fonts.css names the 14 self-hosted woff2 files, all served" "$FN" 14
# A missing file under /site/ would answer 404 with the not found page, and the text itself must be the license.
for f in OFL-ArchivoBlack OFL-Barlow OFL-SpaceMono; do
  curl -s "$B/site/fonts/$f.txt" | grep -q 'SIL Open Font License' && ok "/site/fonts/$f.txt (font license) served" || bad "/site/fonts/$f.txt" "license text not served"
done
curl -s $B/apply/ $B/apply/apply.js | grep -qiE 'fonts from Google|font dari Google' && bad "the privacy notice still says fonts come from Google" "" || ok "the privacy notice no longer says fonts come from Google"
AD=$(curl -s $B/admin/)
echo "$AD" | grep -q 'data-tab="applications"' && echo "$AD" | grep -q '/admin/admin.css' && ok "/admin/ has the APPLICATIONS tab and admin.css" || bad "/admin/ applications tab" ""
echo "$AD" | grep -q 'data-tab="missions"' && ok "/admin/ has the MISSIONS tab" || bad "/admin/ missions tab" ""
curl -s $B/site/app.js | grep -q '/api/missions' && ok "the homepage script loads /api/missions" || bad "site/app.js /api/missions" ""
SJ=$(curl -s $B/site/app.js); SC=$(curl -s $B/site/styles.css)
echo "$SJ" | grep -q 'ev.ctrlKey || ev.metaKey' && echo "$SJ" | grep -q 'scroll to zoom' && ok "the globe zooms on Ctrl or ⌘ + wheel; a plain wheel scrolls the page and shows a hint" || bad "site/app.js wheel zoom" ""
echo "$SJ" | grep -q '"mpin-off"' && echo "$SC" | grep -q '\.mpin\.mpin-off \.mpin-tag' && ok "mission tags that would touch near the rim fade out" || bad "mission tag collision pass" ""
echo "$SJ" | grep -q 'const REACH = 36' && echo "$SJ" | grep -qF 'if (near.length === 1 || near[1].d - near[0].d > CLEAR) openPost(near[0].e);' \
  && echo "$SJ" | grep -qF 'else openReceiptChooser(near.map((n) => n.e));' && echo "$SJ" | grep -qF 'if (pressType !== "mouse" || onStrip(ev)) return;' \
  && ok "a finger tap within 36 px of a receipt dot opens it, or a list when dots sit too close together" || bad "receipt dot reach" ""
echo "$SJ" | grep -qF 'el.classList.toggle("by-touch", ev.pointerType !== "mouse")' && echo "$SC" | grep -qF '.by-touch .scene-tooltip { display: none !important; }' \
  && ok "a finger tap shows no dot preview (the mouse hover still does)" || bad "touch tooltip" ""
echo "$SJ" | grep -qF 'const home = busiest();' && echo "$SJ" | grep -qF 'globe.pointOfView({ ...home, altitude: innerWidth < 600 ? 2.6 : 2.1 }, 0);' \
  && echo "$SJ" | grep -qF 'const SWAY = innerWidth < 600 ? 12 : 20, SWAY_S = 40;' && echo "$SJ" | grep -qF 'el.addEventListener("pointerdown", stopSway, { once: true });' \
  && echo "$SJ" | grep -qF 'if (!swaying || !onScreen) return;' && echo "$SJ" | grep -qF 'globe.resumeAnimation(); tidySoon(); swayOn();' \
  && ok "the globe starts at the busiest group of markers and sways around it until touched, with no frames while scrolled away" || bad "site/app.js start view and sway" ""
curl -s $B/ | grep -q 'id="lgCleaned"' && echo "$SJ" | grep -qF '$("#legend").hidden = !geo.length && !mgeo.length;' && echo "$SC" | grep -qF '.legend span[hidden] { display: none; }' \
  && echo "$SJ" | grep -qF '$("#lgCleaned").hidden = !geo.length;' \
  && ok "the legend shows whenever there are markers, with only the kinds that are there" || bad "legend" ""
LG=$(curl -s $B/ | grep -o 'id="lg[A-Za-z]*"' | tr '\n' ' ')
[ "$LG" = 'id="lgOpen" id="lgFunded" id="lgCleaned" ' ] && echo "$SJ" | grep -qF 'const CLEAN = "#007a3d", PULSE_RGB = "0, 77, 38", RIM = "#ffffff", DOT_R = 0.72, RIM_R = 0.98;' \
  && echo "$SJ" | grep -qF '.pointColor((d) => (d.ink ? INK : d.rim ? RIM : CLEAN))' && echo "$SJ" | grep -qF 'const INK = "#1c1813", INK_R = 1.16;' \
  && echo "$SJ" | grep -qF 'rgba(${PULSE_RGB}, ${Math.sqrt(1 - t)})' \
  && echo "$SJ" | grep -qF 'openPost(receiptOf(d))' && echo "$SJ" | grep -qF '.ringsData(reduceMotion ? [] : geo)' && ! echo "$SJ" | grep -qF '#ff5f00' \
  && echo "$SC" | grep -qF -- '--clean: #007a3d;' && ! echo "$SC" | grep -qE 'lg-dot|rdot' && ! echo "$SJ" | grep -qE 'lg-dot|rdot' \
  && ok "the legend reads OPEN, FUNDED, CLEANED; cleanups are safety green dots on a white rim with a dark ring around it (globe, pulse), no orange on the globe, no pulse under reduced motion, and the old legend dot is gone" || bad "cleaned colour and legend order" "$LG"
# The drawn globe looks like Sapu: one even white light so nothing is shaded, no glow, the land painted on the ball's
# own picture in one green (no hexagon dots and no shapes to draw), a dark outline ball around it, and once the
# satellite map is whole the outline stops drawing with the planet and the dots.
echo "$SJ" | grep -qF 'globe.lights([new (globe.lights()[0].constructor)(0xffffff, Math.PI)]);' \
  && echo "$SJ" | grep -qF '.showAtmosphere(false)' && ! echo "$SJ" | grep -qE 'hexPolygon|atmosphereColor|polygonsData|showAtmosphere\(true' \
  && echo "$SJ" | grep -qF 'const OCEAN = "#bde6f2", LAND = "#2bb673";' && echo "$SJ" | grep -qF 'c.fill("evenodd"); c.stroke();' \
  && echo "$SJ" | grep -qF 'map.image = cv;' && echo "$SJ" | grep -qF 'const W = Math.min(4096, globe.renderer().capabilities.maxTextureSize || 2048), H = W / 2;' \
  && echo "$SJ" | grep -qF 'const ink = new ball.material.constructor({ color: INK, side: 1 });' \
  && echo "$SJ" | grep -qF 'if (outline) outline.visible = !off3d;' && echo "$SJ" | grep -qF 'if (dots) dots.visible = !off3d;' \
  && ok "the drawn globe is flat and outlined like Sapu: one even light, no glow, the land painted on the ball in one green, a dark outline ball, and all of it stops drawing under the whole satellite map" \
  || bad "site/app.js flat and outlined globe" ""
echo "$SJ" | grep -qF '${glyph(ms.some(funded))}${groupLabel(ms)}' && echo "$SJ" | grep -qF '${glyph(funded(m))}#${m.no}' \
  && [ "$(curl -s $B/ | grep -c 'class="gl"')" = 3 ] && echo "$SC" | grep -qF '.mpin-tag .gl {' \
  && ok "mission tags carry a trash bag (open) or a broom (funded), in the globe, the pick-one list and the legend" || bad "tag glyphs" ""
curl -s "$B/site/app.js" > "$T/slip-app.js"
# A cleaned spot (site/app.js cleanGroups and cleanPin, Marcus asked on 2026-11-19 for cleaned spots that read as
# something that happened): its receipt hangs below the spot as a paper slip with a checked box and the kilograms, where
# a mission's tag stands above its own spot. In node: the slip's words (kilograms of its receipts each once, else their
# sacks), slips close together on screen share one at the newest one's dot and split when zoomed in, a tap on a slip
# opens its receipt or lists its receipts newest first (with any other slip under the finger, never a mission's tag),
# a tap whose press started on a box beside it opens nothing, and a mission tag's tap never lists a slip's receipts.
SLIPJS=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const cut = (a, b) => { const i = s.indexOf(a), j = s.indexOf(b, i); if (i < 0 || j < 0) throw new Error("missing " + a); return s.slice(i, j); };
const fn = (name) => { const i = s.indexOf("  function " + name + "(g) {\n"), j = s.indexOf("\n  }\n", i); if (i < 0 || j < 0) throw new Error("missing " + name); return s.slice(i, j + 4); };
let X;
try {
  X = new Function("funded", "r3", "hangPx",
    s.slice(s.indexOf("  const num = (v) =>"), s.indexOf("\n", s.indexOf("  const num = (v) =>"))) + "\n" +
    cut("  const TAG_ALT = 0.012;", "  // The globe also fires its own click for a receipt dot") +
    "\nreturn { amount, slipW, receiptsOf, slipHtml, cleanGroups, missionGroups, GLYPH, SLIP_H, EDGE };")(
    (m) => m.status === "funded", (v) => Math.round(v * 1000) / 1000, 7);
} catch (err) { console.log("wrong: " + err.message); process.exit(0); }
const ev = (kg, sacks, extra) => Object.assign({ result: { kg_estimate: kg, sacks } }, extra);
eq("the words", [X.amount([ev(200), ev(500)]), X.amount([ev(12400)]), X.amount([ev(12.5)]), X.amount([ev(null, 14)]), X.amount([ev(0, 1)]),
  X.amount([ev(340), ev(null, 14)]), X.amount([ev(null, null)]), X.amount([ev(-3, 0)])],
  ["700 KG", "12,400 KG", "12.5 KG", "14 SACKS", "1 SACK", "340 KG", "CLEANED", "CLEANED"]);
eq("the slip and the legend size it as drawn", [X.SLIP_H, X.EDGE, Math.round(X.slipW("700 KG")), Math.round(X.slipW("12,400 KG"))], [21, 4, 78, 102]);
const A = ev(200, null, { id: "a" }), B = ev(500, null, { id: "b" }), C = ev(12400, null, { id: "c" });
const pts = [{ of: A, lat: -0.811, lng: 100.316, i: 0 }, { of: B, lat: -0.775, lng: 100.297, i: 1 }, { of: B, lat: -0.776, lng: 100.298, i: 2 }, { of: C, lat: 10.336, lng: 123.947, i: 3 }];
const far = X.cleanGroups(pts, 19), near = X.cleanGroups(pts, 0.02);
eq("far out: two cleanups 4 km apart share one slip at the newest one dot, each receipt once", far.map((g) => [g.key, g.lat, g.lng, X.amount(X.receiptsOf(g.rs))]),
  [["r0 1 2", -0.811, 100.316, "700 KG"], ["r3", 10.336, 123.947, "12,400 KG"]]);
eq("zoomed in: a slip for each spot", near.map((g) => g.key), ["r0", "r1 2", "r3"]);
eq("a group seen before is the same object", X.cleanGroups(pts, 19)[0] === far[0], true);
eq("the slip markup", X.slipHtml([A, B]), "<i class=\"cslip\">" + X.GLYPH.cleaned + "700 KG<i class=\"cslip-edge\"></i></i>");
// a tap on a slip, and on a mission tag, with what is under the finger
const made = [];
const mkPin = () => { const tag = { on: {}, addEventListener(t, f) { (this.on[t] = this.on[t] || []).push(f); }, classList: { add() {}, remove() {} } };
  const pin = { firstChild: tag, classList: { toggle() {} }, setAttribute() {}, removeAttribute() {}, style: { setProperty() {} }, set innerHTML(v) { pin.html = v; } };
  made.push(pin); return pin; };
let under = [], opened = [];
const groupOfTag = new Map(), M4 = { no: 4 };
const doc = { createElement: mkPin, elementsFromPoint: () => under };
let P;
try {
  P = new Function("document", "receiptsOf", "missionOf", "hangPx", "upper", "dateStr", "tipMedia", "amount", "slipHtml", "groupOfTag", "setOff", "events",
    "openPost", "openReceiptChooser", "performance", "missionsOf", "funded", "glyph", "groupLabel", "missions", "baseOf", "openMission", "openChooser",
    "let pinTapAt = 0, pressOn = null;\n" + fn("missionPin") + fn("cleanPin") + "\nreturn { missionPin, cleanPin, press: (v) => { pressOn = v; } };")(
    doc, X.receiptsOf, () => null, 7, (v, d) => String(v || d), () => "19 NOV", () => "", X.amount, X.slipHtml, groupOfTag, () => {}, [A, B, C],
    (e) => opened.push(e.id), (l) => opened.push("list " + l.map((e) => e.id).join(" ")), { now: () => 1 },
    (ms) => ms, () => false, () => "", () => "#4", [M4], (z) => z, (m) => opened.push("#" + m.no), () => opened.push("missions"));
} catch (err) { console.log("wrong: the pins: " + err.message); process.exit(0); }
const one = { rs: [pts[3]] }, two = { rs: [pts[0], pts[1], pts[2]] }, mis = { ms: [M4] };
for (const g of [one, two, mis]) { g.pin = g.rs ? P.cleanPin(g) : P.missionPin(g); groupOfTag.set(g.pin.firstChild, g); }
const tap = (g, at, press = true) => { opened = []; under = at.map((x) => x.pin.firstChild); P.press(press); g.pin.firstChild.on.click.forEach((f) => f({ clientX: 5, clientY: 5 })); return opened.join(); };
eq("taps", [tap(one, [one]), tap(two, [two]), tap(two, [two, one]), tap(two, [two, mis]), tap(mis, [mis, two]), tap(one, [one], false), tap(two, [two], null)],
  ["c", "list a b", "list a b c", "list a b", "#4", "", "list a b"]);
eq("its preview under it", [made[0].html, made[1].html.slice(made[1].html.indexOf("<div"))], [X.slipHtml([C]) + "<div class=\"tip mtip ctip\"><b>CLEANED</b><br>TBA · 19 NOV<span>TAP FOR THE RECEIPT</span></div>",
  "<div class=\"tip mtip ctip\"><b>2 CLEANUPS HERE</b><br>TBA · 200 KG<br>TBA · 500 KG<span>TAP TO CHOOSE</span></div>"]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/slip-app.js" 2>&1)
check "a cleaned spot's slip (site/app.js in node): the kilograms of its receipts each once, or their sacks; slips that would touch share one at the newest one's dot and split zoomed in; a tap opens its receipt or lists its receipts newest first (with another slip under the finger, never a mission's tag), not when the press began on a box; a mission tag's tap never lists receipts" "$SLIPJS" ok
# How it hangs and moves (site/styles.css, site/app.js): from the spot's dot (--hang, set in satDraw), on the same
# layer, groups and tidy pass as the mission tags (cleaned slips kept first there), at least 44 by 44 px for a finger,
# faded like a tag, a swing the first time it shows and under a mouse but none under reduced motion; the legend's
# CLEANED, the pick-one list and /missions show the same slip with the same checked box.
SLP=""
echo "$SJ" | grep -qF '.htmlElement((g) => (g.rs ? cleanPin(g) : missionPin(g)));' || SLP="$SLP layer"
echo "$SJ" | grep -qF 'const groups = [...missionGroups(mgeo, kp), ...cleanGroups(cgeo, kp)];' || SLP="$SLP groups"
echo "$SJ" | grep -qF 'const cgeo = geo.map((p, i) => ({ of: p.of, lat: r3(p.location.lat), lng: r3(p.location.lng), i }));' || SLP="$SLP points"
echo "$SJ" | grep -qF 'const rank = (t) => (t.g.rs ? 0 : funded(lead(t)) ? 1 : 2);' || SLP="$SLP tidy-order"
echo "$SJ" | grep -qF 'const tag = pin.firstChild, r = (g.rs ? pin : tag).getBoundingClientRect();' || SLP="$SLP tidy-place"
echo "$SJ" | grep -qF 'const hang = Math.round(2 * Math.max((rDot * INK_R) / DOT_R, m > 0 ? Math.max(rDot, AREA_M / mppAt(a)) + 4 : 0)) / 2;' || SLP="$SLP hang"
echo "$SJ" | grep -qF 'for (const g of globe.htmlElementsData()) if (g.rs && g.pin) g.pin.style.setProperty("--hang", hang + "px");' || SLP="$SLP hang-set"
echo "$SJ" | grep -qF 'if (!off && g.rs && !g.hung) { g.hung = true; if (!reduceMotion) g.pin.firstChild.classList.add("cslip-in"); }' || SLP="$SLP swing-in"
echo "$SJ" | grep -qF 'tag.addEventListener("animationend", () => tag.classList.remove("cslip-in", "cslip-swing"));' || SLP="$SLP swing-end"
echo "$SJ" | grep -qF '${slipHtml([e])}' || SLP="$SLP chooser-row"
tr '\n' ' ' < <(echo "$SC") | grep -qF '.mpin .cslip {   position: absolute; left: 0; top: calc(var(--hang, 7px) + 7px);   transform: translateX(-50%) rotate(-2deg); transform-origin: 50% calc(-7px - var(--hang, 7px));' || SLP="$SLP css-hang"
tr '\n' ' ' < <(echo "$SC") | grep -qF '.mpin .cslip::before {   content: ""; position: absolute; left: 50%; top: 50%;   width: max(44px, calc(100% + 1px)); height: 44px; transform: translate(-50%, -50%); }' || SLP="$SLP css-44"
echo "$SC" | grep -qF '.mpin.mpin-off .cslip { opacity: 0; pointer-events: none; }' || SLP="$SLP css-off"
tr '\n' ' ' < <(echo "$SC") | grep -qE '@media \(prefers-reduced-motion: reduce\) \{[^@]*\.mpin \.cslip\.cslip-in, \.mpin \.cslip\.cslip-swing \{ animation: none; \}' || SLP="$SLP css-less-motion"
python3 - site/app.js index.html functions/missions/index.js <<'PY' || SLP="$SLP glyph"
import re, sys
app, page, fn = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
g = re.findall(r"^    cleaned: '(<svg class=\"gl\"[^']*</svg>)',$", app, re.M)
lg = re.search(r'<span id="lgCleaned"><i class="cslip">(<svg class="gl"[^>]*>.*?</svg>)KG<i class="cslip-edge"></i></i>CLEANED</span>', page)
sys.exit(0 if len(g) == 1 and lg and lg.group(1) == g[0] and fn.count(g[0]) == 1 else 1)
PY
[ -z "$SLP" ] && ok "a cleaned spot's slip hangs from its dot by --hang (satDraw), shares the mission tags' layer, grouping and tidy pass (kept first), takes taps on at least 44 by 44 px, fades like a tag, swings once when it shows and under a mouse but not under reduced motion; the legend, the pick-one list and /missions show the same slip and checked box" \
  || bad "the cleaned slip" "$SLP"
# Sample missions and sample pictures for an empty site (data/README.md)
SM=$(curl -s $B/site/samples/missions.json)
echo "$SM" | python3 -c "import json,sys;d=json.load(sys.stdin);s=[m['status'] for m in d];assert s.count('open')==2 and s.count('funded')==1 and all(m.get('now') and isinstance(m.get('in_days'),int) and not m.get('partner',{}).get('slug') for m in d)" 2>/dev/null \
  && ok "/site/samples/missions.json: two open and one funded sample mission, each with a picture, a day from today and no crew page" || bad "sample missions" "$(echo "$SM" | head -c 200)"
for f in $( (echo "$SM" | python3 -c "import json,sys;[print(u) for m in json.load(sys.stdin) for u in m['now']]"; for e in data/events/*-demo.json; do python3 -c "import json,sys;d=json.load(open(sys.argv[1]));[print(u) for k in ('before','after') for u in d['media'][k]]" "$e"; done) | sort -u); do
  st=$(curl -s -o "$T/svg" -w '%{http_code} %{content_type}' "$B/$f")
  if [ "${st%%;*}" = "200 image/svg+xml" ] && ! grep -qiE '<script|<image|<foreignObject|href="https?:|<text' "$T/svg"; then ok "/$f is a self-contained SVG picture"; else bad "/$f" "$st"; fi
done
echo "$SJ" | grep -qF 'if (Array.isArray(raw) && !missions.length && !loadFailed && allDemo) {' \
  && echo "$SJ" | grep -qF 'const mStamp = (m, cls) => (m.demo ? `<div class="stamp${cls}">SAMPLE</div>`' \
  && echo "$SJ" | grep -qF 'if (e.demo && Number.isInteger(e.days_ago)) e.date = dayFromToday(-e.days_ago);' \
  && ok "sample missions show only next to the sample receipts (allDemo), stamped SAMPLE; sample days count from today" || bad "site/app.js samples" ""
echo "$SJ" | grep -qF 'ev.detail && performance.now() - openedAt < 500 && Math.hypot(ev.clientX - openX, ev.clientY - openY) < 40' \
  && echo "$SJ" | grep -qF 'addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") forgetPress(); }, true);' \
  && ok "the second click of the double click that opened a post or the chooser is ignored there; ✕ works at once, also after Enter or Space opened it" || bad "site/app.js double click guard" ""
echo "$SJ" | grep -qF 'const pxPerStep = (ev) => (ev.ctrlKey && !ctrlDown ? 100 : 500);' && echo "$SJ" | grep -qF '(Math.abs(dy) >= 50 && !isMac)' \
  && ok "a pinch zooms with the fingers, Ctrl or ⌘ + touchpad scroll 5 times slower, a fast swipe on a Mac is no mouse notch" || bad "site/app.js pinch and scroll rates" ""
echo "$SJ" | grep -qF 'else if (apiFailed) { events = []; loadFailed = true; }' \
  && ok "when /api/events fails, the homepage says it couldn't load instead of showing the samples" || bad "site/app.js /api/events failure" ""
echo "$SJ" | grep -qF 'const zoomFrom = () => zoomGoal ?? (flying() ? flightAlt : globe.pointOfView().altitude);' \
  && ok "a zoom during the double click flight counts from where the flight goes" || bad "site/app.js zoom during the flight" ""
echo "$SC" | grep -q 'width: max(44px' && echo "$SC" | grep -q 'width: 44px; height: 44px' && ok "mission tags and zoom buttons take taps on at least 44 px" || bad "44 px tap targets" ""
# The satellite map (site/app.js, satellite map): zoomed in far, the drawn globe fades into EOX's satellite
# pictures. The browser loads them from tiles.maps.eox.at, never through a Function, and only after a tap that
# says so; a spot is an area as big as its rounded point's box, never a pin; the deepest zoom is 6 m a px.
SMATH=$(echo "$SJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const S = eval(s.slice(s.indexOf("// ----- satellite math"), s.indexOf("// ----- end of the satellite math -----")) +
    ";({ SAT_YEAR, SAT_URL, SAT_MAXZ, SAT_MPX, AREA_M, MAP_FROM, MAP_FULL, r3, mapShare, tileX, tileY, rowLat, tileZ, markPx, seenPx, toUnit, keepSpot, wrapLng, spotAt, holdSpot, HOLD_LAT })");
  const bad = [];
  const box = Math.hypot(0.0005, 0.0005) * 111320;           // the farthest a spot can be from its rounded point, in m
  if (!(S.AREA_M >= box)) bad.push("AREA_M " + S.AREA_M + " < " + box.toFixed(1));
  if (!(S.SAT_MPX >= 5)) bad.push("SAT_MPX " + S.SAT_MPX);
  if (S.SAT_MAXZ > 14 || S.tileZ(0.5, 0) !== S.SAT_MAXZ) bad.push("SAT_MAXZ");
  const u = S.SAT_URL(14, 13431, 8587);
  if (u !== "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-" + S.SAT_YEAR + "_3857/default/GoogleMapsCompatible/14/8587/13431.jpg") bad.push(u);
  if (S.r3(-8.6594) !== -8.659 || S.r3(115.13) !== 115.13) bad.push("r3");
  if (S.mapShare(S.MAP_FROM) !== 0 || S.mapShare(S.MAP_FROM * 1.2) !== 0 || S.mapShare(S.MAP_FULL) !== 1 || S.mapShare(0.001) !== 1) bad.push("mapShare ends");
  let last = 0;
  for (let a = S.MAP_FROM; a >= S.MAP_FULL; a *= 0.97) { const m = S.mapShare(a); if (m < last) bad.push("mapShare falls at " + a); last = m; }
  for (const lat of [-60, -8.659, 0, 14.55, 60]) for (const z of [3, 9, 14]) if (Math.abs(S.rowLat(S.tileY(lat, z), z) - lat) > 1e-9) bad.push("tileY " + lat + " " + z);
  if (Math.floor(S.tileX(115.13, 14)) !== 13431 || Math.floor(S.tileY(-8.659, 14)) !== 8587) bad.push("Canggu tile");
  if (S.markPx(6, 8) < S.AREA_M / 6 || S.markPx(100, 8) !== 8) bad.push("markPx");
  // satDraw sizes the receipt dots: at every altitude, from the deepest zoom to the whole globe and on short and
  // tall screens, a dot shows at most DOT_PX and its scale stays a positive number. Closer than the height a dot
  // stands at (0.006, about 40 m a px) a dot there would be bigger than the screen: before seenPx said so, the
  // scale turned negative and a receipt mark covered the whole screen in green (SEE THE SPOT, 9 Nov 2026).
  const num = (re) => +(s.match(re) || [0, NaN])[1];
  const DOT_ALT = num(/const DOT_ALT = ([\d.]+);/), DOT_R = num(/ DOT_R = ([\d.]+),/), DOT_PX = num(/const DOT_PX = (\d+);/);
  if (!(DOT_ALT > 0 && DOT_R > 0 && DOT_PX > 0)) bad.push("dot constants " + [DOT_ALT, DOT_R, DOT_PX]);
  for (const f of [700, 810, 965, 1600]) for (let a = 0.0005; a < 3; a *= 1.03) {
    const m = S.mapShare(a), low = 1 - m + m * Math.min(1, a / S.MAP_FROM);
    const rDot = Math.min(S.seenPx(f, DOT_R, a, DOT_ALT), DOT_PX), size = rDot / S.seenPx(f, DOT_R, a, DOT_ALT * low);
    if (!(rDot > 0 && rDot <= DOT_PX && size > 0 && isFinite(size))) { bad.push("dot size at altitude " + a.toFixed(5) + " f " + f + ": " + rDot + " px, scale " + size); break; }
  }
  if (S.seenPx(810, 0.72, 0.0015, 0.006) !== Infinity || !(S.seenPx(810, 0.72, 0.3, 0.006) > 0)) bad.push("seenPx");
  // zooming toward the pointer: the spot is seen at the same angle from the middle after the step, and the new
  // centre lies on the great circle through the old centre and the spot
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const tanAt = (c, a, P) => { const th = Math.acos(Math.min(1, dot(S.toUnit(c.lat, c.lng), P))); return Math.sin(th) / (1 + a - Math.cos(th)); };
  for (const [c, a, p, next] of [[{ lat: -6.8, lng: 127.7 }, 0.3, { lat: -7.4, lng: 126.9 }, 0.2], [{ lat: 10, lng: 120 }, 0.05, { lat: 10.2, lng: 120.3 }, 0.01],
    [{ lat: -8.6, lng: 115.1 }, 0.01, { lat: -8.62, lng: 115.13 }, 0.03], [{ lat: 0, lng: 0 }, 2, { lat: 20, lng: 15 }, 1.2]]) {
    const P = S.toUnit(p.lat, p.lng), c2 = S.keepSpot({ ...c, altitude: a }, next, P), C = S.toUnit(c.lat, c.lng);
    const n = c2 && [C[1] * P[2] - C[2] * P[1], C[2] * P[0] - C[0] * P[2], C[0] * P[1] - C[1] * P[0]];
    if (!c2 || Math.abs(tanAt(c2, next, P) - tanAt(c, a, P)) > 1e-9 || Math.abs(dot(n, S.toUnit(c2.lat, c2.lng))) > 1e-9) bad.push("keepSpot " + JSON.stringify([c, a, next]));
  }
  // a finger holds the spot it touched (spotAt, holdSpot): the spot under a px is where the tan of keepSpot and its
  // bearing from the centre put it on screen, and the centre that puts that spot back under the same px is the
  // centre it was taken from, from the deepest map to the whole globe, on short and tall screens. A finger past the
  // planet holds its rim, and with north up the centre stays within HOLD_LAT of the equator.
  let seed = 11;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647, rad = Math.PI / 180;
  for (let i = 0; i < 3000; i++) {
    const a = [0.002, 0.02, 0.2, 0.6, 2.1, 2.6, 3.2][i % 7], f = [700, 905, 1600][i % 3];
    const c = { lat: -80 + 160 * rnd(), lng: -180 + 360 * rnd(), altitude: a };
    const q = Math.asin(1 / (1 + a)) * 0.999 * Math.sqrt(rnd()), g = 2 * Math.PI * rnd();
    const dx = f * Math.tan(q) * Math.sin(g), dy = -f * Math.tan(q) * Math.cos(g);
    const p = S.spotAt(c, dx, dy, f), P = S.toUnit(p.lat, p.lng);
    const brg = Math.atan2(Math.sin((p.lng - c.lng) * rad) * Math.cos(p.lat * rad),
      Math.cos(c.lat * rad) * Math.sin(p.lat * rad) - Math.sin(c.lat * rad) * Math.cos(p.lat * rad) * Math.cos((p.lng - c.lng) * rad));
    const seen = f * tanAt(c, a, P);
    if (Math.acos(Math.min(1, dot(S.toUnit(c.lat, c.lng), P))) > 1e-6 && Math.hypot(seen * Math.sin(brg) - dx, -seen * Math.cos(brg) - dy) > 1e-6) { bad.push("spotAt " + JSON.stringify([c, dx, dy, f])); break; }
    const c2 = S.holdSpot(p, dx, dy, f, a, c.lat);
    if (Math.abs(c2.lat - c.lat) > 1e-7 || Math.abs(S.wrapLng(c2.lng - c.lng)) * Math.cos(c.lat * rad) > 1e-7) { bad.push("holdSpot " + JSON.stringify([c, dx, dy, f])); break; }
  }
  const rim = S.spotAt({ lat: 0, lng: 120, altitude: 2.6 }, 2000, 0, 905);
  if (Math.abs(Math.acos(Math.min(1, dot(S.toUnit(0, 120), S.toUnit(rim.lat, rim.lng)))) - Math.acos(1 / 3.6)) > 1e-9) bad.push("spotAt past the rim");
  const pole = S.holdSpot({ lat: 89, lng: 0 }, 0, 300, 905, 0.5, 80);
  if (!(Math.abs(pole.lat) <= S.HOLD_LAT) || S.HOLD_LAT > 85) bad.push("holdSpot past the pole " + pole.lat);
  console.log(bad.length ? bad.join("; ") : "ok");
});' 2>&1)
[ "$SMATH" = ok ] && ok "satellite map: EOX tiles, never sharper than 6 m a px, a spot always the area of its rounded 100 m box, the blend eases in from MAP_FROM to MAP_FULL; a finger holds the spot it touched (3000 views)" || bad "satellite math" "$SMATH"
HP0=$(curl -s $B/)
[ "$(echo "$SJ" | grep -oE 'https://[a-z0-9.-]+' | sort -u | tr '\n' ' ')" = 'https://sapu.earth https://tiles.maps.eox.at ' ] \
  && echo "$SJ" | grep -qF 'const m = mapShare(a), low = 1 - m + m * Math.min(1, a / MAP_FROM);' \
  && echo "$SJ" | grep -qF 'if (!m) { if (!satEl.hidden) satClear(); return; }' && echo "$SJ" | grep -qF 'if (alt < MAP_FROM) satPrefetch(lat, lng, alt);' \
  && ! echo "$HP0" | grep -q 'id="satGo"' && echo "$SJ" | grep -qF 'SEE THE SPOT ON SATELLITE' \
  && ok "satellite pictures come only from tiles.maps.eox.at, and only once the visitor zooms in below MAP_FROM or taps SEE THE SPOT ON SATELLITE (on by default, no tap asked for)" || bad "satellite map loading" ""
SY=$(echo "$SJ" | sed -n 's/^  const SAT_YEAR = \([0-9]*\);$/\1/p')
[ -n "$SY" ] && echo "$HP0" | grep -qF "EOxCloudless $SY</a> by" && echo "$HP0" | grep -qF '>EOX IT Services GmbH</a>' \
  && echo "$HP0" | grep -qF "(contains modified Copernicus Sentinel data $SY)" && echo "$HP0" | grep -qF 'href="https://creativecommons.org/licenses/by-nc-sa/4.0/"' \
  && echo "$SJ" | grep -qF 'const on = m > 0 && uiGone;' && echo "$SJ" | grep -qF 'if (satBar.hidden === on) satBar.hidden = !on;' \
  && echo "$HP0" | grep -qF '<p class="foot-credit" id="credits">' && echo "$HP0" | grep -qF '<p class="sat-credit">satellite <a href="#credits">© EOX · Copernicus Sentinel-2</a></p>' \
  && ok "EOX's credit and licence for its $SY tiles are in the homepage footer, and a short credit linking there shows whenever the satellite map does" || bad "satellite credit" "year [$SY]"
echo "$SJ" | grep -qF 'if (reduceMotion) { globe.pointOfView({ lat, lng, altitude: alt }, 0);' \
  && echo "$SJ" | grep -qF 'globe.scene().onBeforeRender = () =>' && echo "$SJ" | grep -qF 'const zmin = () => satMin();' && echo "$SJ" | grep -qF 'const setMin = () => { controls.minDistance = 100 * (1 + satMin()); };' \
  && echo "$SJ" | grep -qF 'if (pressOn === false || (mouse && !satMarks) || ev.target.closest(".mpin") || onStrip(ev)) return;' && echo "$SJ" | grep -qF '.pointLat((d) => r3(d.location.lat))' \
  && echo "$SJ" | grep -qF '...geo.map((p) => ({ ...p }))' && echo "$SC" | grep -qF '.satmap { position: absolute; inset: 0; z-index: -1;' \
  && echo "$SJ" | grep -qF 'const k = z <= 4 ? 4 : z === 5 ? 3 : z <= 7 ? 2 : 1' \
  && echo "$SJ" | grep -qF 'const rDot = Math.min(natPx(a, 1), DOT_PX), size = rDot / natPx(a, low);' && echo "$SJ" | grep -qF '.ringMaxRadius(() => 3 * dotSize)' \
  && echo "$SJ" | grep -qF 'const natPx = (a, low) => seenPx(fpx(), DOT_R, a, DOT_ALT * low);' \
  && echo "$SJ" | grep -qF 'const rd = s ? Math.min(Math.hypot(q.x - s.x, q.y - s.y), 2 * DOT_PX) : 0;' \
  && ok "receipt dots grow with the zoom only up to their size on the map, pulse included; the zoom goes down to 6 m a px, the map follows every camera move, big tiles bend with the planet in parts, marks take taps and mouse clicks, dots sit on the rounded point, reduced motion jumps" || bad "satellite map behaviour" ""
echo "$SJ" | grep -qF 'const tileShown = (t, now) => t.st === 3 || (t.st === 2 && now - t.onAt >= FADE_MS);' \
  && echo "$SJ" | grep -qF 'if (!wanted.has(k) && (t.z === z || whole || t.st === 0 || t.z > z + 2)) dropTile(k, t);' \
  && echo "$SJ" | grep -qF 'if (t.onAt - asked < 60) { t.box.classList.add("now"); t.onAt -= FADE_MS; }' && echo "$SC" | grep -qF '.sat-tile.now { transition: none; }' \
  && ok "while the zoom level changes, a level's tiles stay until the next level's are there and faded in (pictures the browser has show at once), so nothing shows through" || bad "satellite tile swaps" ""
echo "$SJ" | grep -qF 'if (a < MAP_FROM) setUi(true); else if (a > UI_BACK_AT) setUi(false);' && echo "$SJ" | grep -qF 'const UI_BACK_AT = 1.2;' \
  && echo "$SJ" | grep -qF 'const on = m > 0 && uiGone;' && echo "$SC" | grep -qF '.hero.map-gone :is(.tap-hint, .legend, .stats, .scroll-cue) { display: none; }' \
  && echo "$SC" | grep -qF '.hero.map-on :is(.crew-link, .tag-demo, .pitch, .tap-hint, .legend, .stats, .scroll-cue) { opacity: 0; pointer-events: none; }' \
  && echo "$SJ" | grep -qF 'canvas.style.touchAction = off ? "none" : "pan-y";' && echo "$SC" | grep -qF '.hero.map-on { touch-action: none; }' \
  && echo "$SC" | grep -qF 'html:has(.hero), html:has(.hero) body { overscroll-behavior-y: contain; }' && ! echo "$SJ" | grep -qF 'const ta = mk >= 1' \
  && echo "$SC" | grep -qF '.hero.map-gone .cues { display: none; }' \
  && echo "$SC" | grep -qF '.hero.map-gone :is(.crew-link, .tag-demo, .pitch) { visibility: hidden; }' \
  && ok "zoomed in to the satellite map, the crew link, SAMPLE DATA, the line that says what Sapu Earth does, the hint, legend, stats, SEE THE RECEIPTS and SEE THE CREWS (both .scroll-cue, their row leaves the layout too) step aside, and while they are away one finger moves the globe and the map every way (no page scroll, no pull to refresh from the first screen); they come back only zoomed far out (altitude 1.2); a pull down never reloads the homepage" || bad "page boxes on the satellite map" ""
# Fingers on the globe (site/app.js, one finger on the globe): fingers are the site's, a mouse is globe.gl's. One
# finger holds the spot it touched (the math is checked above); a swipe up or down scrolls the page without tilting
# the planet first, and the planet goes back when the browser takes the swipe; a flick carries on by the clock and
# every other camera move stops it; two fingers zoom at globe.gl's pinch speed within its limits; a finger on a
# mission tag acts as on the planet (#globe's touch-action).
echo "$SJ" | grep -qF 'controls.enableRotate = controls.enableZoom = ev.pointerType === "mouse";' \
  && echo "$SJ" | grep -qF 'else y = hold.y0;' && echo "$SJ" | grep -qF 'if (!hold.firm) globe.pointOfView({ ...hold.from, altitude: globe.pointOfView().altitude }, 0);' \
  && echo "$SJ" | grep -qF 'const FLING_S = 0.35;' && echo "$SJ" | grep -qF 'th = w * FLING_S * (1 - Math.exp(-t / FLING_S))' \
  && echo "$SJ" | grep -qF 'flyStop(); flingStop(); stopSway(); zoomGoal = null;' && echo "$SJ" | grep -qF 'else { flingStop(); globe.pauseAnimation(); }' \
  && [ "$(echo "$SJ" | grep -cF 'flingStop();')" -ge 5 ] \
  && echo "$SJ" | grep -qF 'const alt = Math.min(controls.maxDistance / R, Math.max(controls.minDistance / R, k)) - 1;' \
  && echo "$SJ" | grep -qF 'controls.addEventListener("change", () => { controls.zoomSpeed = pinchSpeed(globe.pointOfView().altitude); });' \
  && echo "$SC" | grep -qF '#globe { position: absolute; inset: 0; isolation: isolate; touch-action: pan-y; }' \
  && ok "one finger holds the spot it touched on the globe and the map, and a flick carries on by the clock until any other camera move; a swipe up or down scrolls the page and the planet does not tilt first; two fingers pinch at globe.gl's speed toward the fingers; a finger on a mission tag counts; a mouse keeps globe.gl's spin" || bad "fingers on the globe" ""
echo "$SJ" | grep -qF 'if (step) zoomBy(Math.exp(step), pointerSpot(ev));' && echo "$SJ" | grep -qF 'zoomTo(goalFrom(from, 1 / ev.scale), pointerSpot(ev))' \
  && echo "$SJ" | grep -qF '$("#zin").addEventListener("click", () => zoomBy(zstep(true)));' && echo "$SJ" | grep -qF 'cam.lookAt(controls.target);' \
  && ok "Ctrl or ⌘ + wheel and a trackpad pinch zoom toward the pointer, keeping the spot under it; the + and - buttons zoom at the middle" || bad "zoom toward the pointer" ""
check "/admin/admin.css 200" "$(code $B/admin/admin.css)" 200
check "/apply/ 200" "$(code $B/apply/)" 200
AP=$(curl -s $B/apply/)
echo "$AP" | grep -q 'apply\.js' && ok "/apply/ loads apply.js" || bad "/apply/ HTML" "$(echo "$AP" | head -5)"
curl -s -o /dev/null -w '%{http_code} %{content_type}' $B/apply/apply.js | grep -q '^200 .*javascript' && ok "/apply/apply.js is served as JavaScript" || bad "/apply/apply.js" ""
echo "$AP" | grep -q 'https://sapu.earth/apply/' && ok "/apply/ has its og:url" || bad "/apply/ og:url" ""
echo "$AP" | grep -qi 'noindex' && bad "/apply/ must be indexable" "noindex found" || ok "/apply/ is indexable"
# IMPRESSUM (§ 25 MedienG): a static page with no script, linked from the footer of every public page.
check "/impressum/ 200" "$(code $B/impressum/)" 200
IM=$(curl -s $B/impressum/)
echo "$IM" | grep -q '>IMPRESSUM</mark>' && echo "$IM" | grep -q 'Medieninhaber' && echo "$IM" | grep -q 'Marcus Pousette, Innsbruck, Austria' \
  && echo "$IM" | grep -q 'href="mailto:hello@sapu.earth"' && echo "$IM" | grep -q '25 of the Austrian Media Act' && echo "$IM" | grep -q 'private, self-funded project' \
  && ok "/impressum/ names the media owner, the contact, what the site is and § 25 MedienG" || bad "/impressum/ content" "$(echo "$IM" | head -30)"
curl -sL $B/impressum | grep -q 'Medieninhaber' && ok "/impressum (no slash) serves the page" || bad "/impressum" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' $B/impressum)"
echo "$IM" | grep -qi 'noindex' && bad "/impressum/ must be indexable" "noindex found" || ok "/impressum/ is indexable"
echo "$IM" | grep -qiE '<script|tel:' && bad "/impressum/ has a script or a phone number" "" || ok "/impressum/ has no script and no phone number"
[ "$(echo "$IM" | grep -cE 'href="/site/(fonts|styles|forms)\.css\?v=[A-Za-z0-9]+"')" = 3 ] && ! echo "$IM" | grep -qE 'href="[^"]*\.css"' \
  && ok "/impressum/ links only the build-versioned fonts, styles and forms CSS" || bad "/impressum/ CSS links" "$(echo "$IM" | grep -F '.css')"
echo "$IM" | grep -qE 'fonts\.(googleapis|gstatic)\.com' && bad "/impressum/ loads Google Fonts" "" || ok "/impressum/ loads no Google Fonts"
echo "$IM" | grep -q 'href="/apply/#privacy"' && echo "$IM" | grep -q 'href="/"' && ok "/impressum/ links the privacy notice and the globe" || bad "/impressum/ links" ""
echo "$AP" | grep -q '<details class="privacy" id="privacy">' && ! echo "$AP" | grep -q '<script>' \
  && curl -s $B/apply/apply.js | grep -qF 'if (location.hash === "#privacy" && $("#privacy")) $("#privacy").open = true;' \
  && ok "/apply/ has the #privacy anchor, and apply.js (no inline script) opens the notice for it" || bad "/apply/ privacy anchor" ""
for p in / /apply/ /upload/; do
  curl -s "$B$p" | grep -q 'href="/impressum/"' && ok "$p links to /impressum/" || bad "$p impressum link" ""
done
# $PP is the partner page from the start of this run (the partner is deactivated by now).
echo "$PP" | grep -q 'href="/impressum/"' && ok "/p/<slug> links to /impressum/" || bad "/p/<slug> impressum link" ""
grep -qF '"/impressum/*"' _routes.json && ok "_routes.json serves /impressum/ without a Function" || bad "_routes.json" "no /impressum/* in exclude"

# STORIES (docs/stories.md): Sapu Reports, static pages with no script, one per story and language, linked from the
# homepage (SAPU REPORTS and the footer) and the Impressum. A story that comments on how authorities answer makes sapu.earth a site that can
# shape public opinion, so the Impressum carries its basic direction (§ 25 (4) MedienG) and says how to reply.
echo "$IM" | grep -qF 'Basic direction (<span lang="de">Grundlegende Richtung</span>)' && echo "$IM" | grep -qF '<p lang="de">Berichte über die von Sapu Earth bezahlten Aufräumeinsätze' \
  && echo "$IM" | grep -qF '<div class="field" id="replies">' && echo "$IM" | grep -qF 'in Indonesian, English or German. We correct mistakes and date each correction' \
  && echo "$IM" | grep -qF 'Under <a href="/stories/">STORIES</a> it publishes reports' \
  && ok "/impressum/ has the basic direction in English and German, Replies and corrections, and links /stories/" || bad "/impressum/ basic direction and replies" ""
grep -qF '"/stories/*"' _routes.json && grep -qF 'for d in site upload admin apply impressum stories; do' scripts/build-site.sh \
  && grep -qF "\$(find dist/stories -name '*.html' 2>/dev/null)" scripts/build-site.sh \
  && ok "the build copies stories/ and versions its pages' CSS, and _routes.json serves /stories/ without a Function" || bad "stories in the build and _routes.json" ""
STY_SX=""
for p in /stories/ /stories/trash-in-numbers/ /stories/trash-in-numbers/id/ /stories/trash-with-a-passport/ /stories/trash-with-a-passport/id/; do
  sty_st=$(curl -s -o "$T/st.html" -D "$T/st.h" -w '%{http_code}' "$B$p")
  [ "$sty_st" = 200 ] || STY_SX="$STY_SX $p:$sty_st"
  tr -d '\r' < "$T/st.h" | grep -qi '^content-type: text/html' || STY_SX="$STY_SX $p:type"
  tr -d '\r' < "$T/st.h" | grep -qi '^x-frame-options: DENY' || STY_SX="$STY_SX $p:framing"
  grep -qiE '<script|tel:' "$T/st.html" && STY_SX="$STY_SX $p:script"
  grep -qi 'noindex' "$T/st.html" && STY_SX="$STY_SX $p:noindex"
  { [ "$(grep -cE 'href="/site/(fonts|styles|forms)\.css\?v=[A-Za-z0-9]+"' "$T/st.html")" = 3 ] && ! grep -qE 'href="[^"]*\.css"' "$T/st.html"; } || STY_SX="$STY_SX $p:css"
  grep -qE 'fonts\.(googleapis|gstatic)\.com' "$T/st.html" && STY_SX="$STY_SX $p:google-fonts"
  grep -q 'href="/impressum/"' "$T/st.html" || STY_SX="$STY_SX $p:impressum"
  grep -qF "<link rel=\"canonical\" href=\"https://sapu.earth$p\">" "$T/st.html" || STY_SX="$STY_SX $p:canonical"
  [ "$(grep -o 'target="_blank"' "$T/st.html" | wc -l)" = "$(grep -o 'rel="noopener" target="_blank"' "$T/st.html" | wc -l)" ] || STY_SX="$STY_SX $p:noopener"
  for sty_img in $(grep -oE 'src="/stories/[^"]+\.jpg"' "$T/st.html" | sed 's/^src="//; s/"$//'); do
    [ "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B$sty_img")" = "200 image/jpeg" ] || STY_SX="$STY_SX $p:$sty_img"
  done
done
[ -z "$STY_SX" ] && ok "/stories/ and both stories in English and Indonesian: 200 text/html, no framing, no script, indexable, canonical, the build's three stylesheets, no Google Fonts, the Impressum link, every outside link opens with noopener, and every picture is served as a JPEG" \
  || bad "the story pages" "$STY_SX"
STY_EN=$(curl -s $B/stories/trash-in-numbers/); STY_SID=$(curl -s $B/stories/trash-in-numbers/id/); STY_SIX=$(curl -s $B/stories/)
STY_SL=""
for x in STY_EN STY_SID; do
  eval "sty_pg=\$$x"
  for h in '<link rel="alternate" hreflang="en" href="https://sapu.earth/stories/trash-in-numbers/">' \
           '<link rel="alternate" hreflang="id" href="https://sapu.earth/stories/trash-in-numbers/id/">' \
           '<link rel="alternate" hreflang="x-default" href="https://sapu.earth/stories/trash-in-numbers/">'; do
    echo "$sty_pg" | grep -qF "$h" || STY_SL="$STY_SL $x:hreflang"
  done
done
echo "$STY_EN" | grep -qF '<html lang="en">' && echo "$STY_SID" | grep -qF '<html lang="id">' || STY_SL="$STY_SL lang"
echo "$STY_EN" | grep -qF '<a href="/stories/trash-in-numbers/" aria-current="page">EN</a><a href="/stories/trash-in-numbers/id/" hreflang="id" lang="id">ID</a>' || STY_SL="$STY_SL en-switch"
echo "$STY_SID" | grep -qF '<a href="/stories/trash-in-numbers/" hreflang="en" lang="en">EN</a><a href="/stories/trash-in-numbers/id/" aria-current="page">ID</a>' || STY_SL="$STY_SL id-switch"
echo "$STY_SIX" | grep -qF '<a class="b b-ghost" href="/stories/trash-in-numbers/">READ IN ENGLISH</a>' \
  && echo "$STY_SIX" | grep -qF '<a class="b b-ghost" href="/stories/trash-in-numbers/id/" hreflang="id" lang="id">BACA DALAM BAHASA INDONESIA</a>' || STY_SL="$STY_SL index-links"
[ -z "$STY_SL" ] && ok "the story's English and Indonesian pages name each other (hreflang, x-default English), say their language, switch with EN and ID, and /stories/ links both" \
  || bad "story languages" "$STY_SL"
# The second story (trash-with-a-passport, 16 Nov 2026): its two languages name each other, and /stories/ lists it on
# top with its share card as the list's own picture.
STY2_EN=$(curl -s $B/stories/trash-with-a-passport/); STY2_ID=$(curl -s $B/stories/trash-with-a-passport/id/)
STY_SL=""
for h in '<link rel="alternate" hreflang="en" href="https://sapu.earth/stories/trash-with-a-passport/">' \
         '<link rel="alternate" hreflang="id" href="https://sapu.earth/stories/trash-with-a-passport/id/">' \
         '<link rel="alternate" hreflang="x-default" href="https://sapu.earth/stories/trash-with-a-passport/">'; do
  echo "$STY2_EN" | grep -qF "$h" && echo "$STY2_ID" | grep -qF "$h" || STY_SL="$STY_SL hreflang"
done
echo "$STY2_EN" | grep -qF '<html lang="en">' && echo "$STY2_ID" | grep -qF '<html lang="id">' || STY_SL="$STY_SL lang"
echo "$STY2_EN" | grep -qF '<a href="/stories/trash-with-a-passport/" aria-current="page">EN</a><a href="/stories/trash-with-a-passport/id/" hreflang="id" lang="id">ID</a>' || STY_SL="$STY_SL en-switch"
echo "$STY2_ID" | grep -qF '<a href="/stories/trash-with-a-passport/" hreflang="en" lang="en">EN</a><a href="/stories/trash-with-a-passport/id/" aria-current="page">ID</a>' || STY_SL="$STY_SL id-switch"
echo "$STY_SIX" | grep -qF '<a class="b b-ghost" href="/stories/trash-with-a-passport/">READ IN ENGLISH</a>' \
  && echo "$STY_SIX" | grep -qF '<a class="b b-ghost" href="/stories/trash-with-a-passport/id/" hreflang="id" lang="id">BACA DALAM BAHASA INDONESIA</a>' || STY_SL="$STY_SL index-links"
[ "$(echo "$STY_SIX" | grep -nF 'href="/stories/trash-with-a-passport/"' | head -1 | cut -d: -f1)" -lt "$(echo "$STY_SIX" | grep -nF 'href="/stories/trash-in-numbers/"' | head -1 | cut -d: -f1)" ] 2>/dev/null || STY_SL="$STY_SL newest-on-top"
echo "$STY_SIX" | grep -qF '<meta property="og:image" content="https://sapu.earth/stories/trash-with-a-passport/img/card-en.jpg">' || STY_SL="$STY_SL index-card"
[ -z "$STY_SL" ] && ok "the second story's English and Indonesian pages name each other (hreflang, x-default English), say their language and switch with EN and ID, and /stories/ lists it on top with its share card" \
  || bad "the second story's languages" "$STY_SL"
# Every number on the story, with its source, on both pages, and the slides say the same numbers (its entry in STORIES in
# assets/brand/sapu-sketch/sapu-sketch.html). Numbers written the English way on the English page, the Indonesian way on the other.
SKETCH=assets/brand/sapu-sketch/sapu-sketch.html
# The slides' numbers live in the brand kit, which the public copy of this repo leaves out: there they are skipped.
[ -f "$SKETCH" ] || echo "NOTE  $SKETCH is not in this copy (the public repo leaves the brand kit out), so the stories' slides are not checked"
STY_SN=""
for n in '0 of 420' '142,000 tonnes a day' '141,926 tonnes a day' '37,001 a day' '26%' '57.2% of households' '27.6%' 'UU 18/2008, Pasal 44' \
         'That was 2013.' 'about two in three' 'Since 1 August 2026' '9,450 tonnes a day' '285 million people' 'href="/crews">sapu.earth/crews</a>'; do
  echo "$STY_EN" | grep -qF "$n" || STY_SN="$STY_SN [en: $n]"
done
for n in '0 dari 420' '142.000 ton per hari' '141.926 ton per hari' '37.001 ton per hari' '26%' '57,2% rumah tangga' '27,6%' 'UU 18/2008, Pasal 44' \
         'Batas waktunya 2013.' 'sekitar dua pertiga' 'Sejak 1 Agustus 2026' '9.450 ton per hari' '285 juta orang' 'href="/crews">sapu.earth/crews</a>'; do
  echo "$STY_SID" | grep -qF "$n" || STY_SN="$STY_SN [id: $n]"
done
for sty_src in 'kemenlh.go.id/news/detail/klhbplh-tetapkan-hasil-penilaian-kinerja-pengelolaan-sampah-kabupatenkota-tahun-2025' \
           'antaranews.com/berita/5513585/' 'metrotvnews.com/read/bzGCeDdY-' 'databoks.katadata.co.id/lingkungan/statistik/6879d6ad78a46/' \
           'data.goodstats.id/statistic/menguak-kebiasaan-pengelolaan-sampah-rumah-tangga-di-indonesia-2023' 'peraturan.go.id/files/UU%2018%20Tahun%202008.pdf' \
           'lestari.kompas.com/read/2026/02/13/184300086/' 'lestari.kompas.com/read/2026/09/08/103000586/'; do
  echo "$STY_EN" | grep -qF "$sty_src" && echo "$STY_SID" | grep -qF "$sty_src" || STY_SN="$STY_SN [source: $sty_src]"
done
for x in STY_EN STY_SID; do
  eval "sty_pg=\$$x"
  [ "$(echo "$sty_pg" | grep -oE 'class="story-slide" [^>]* alt="[^"]* Sapu: “[^"]*”"' | wc -l | tr -d ' ')" = 7 ] && ! echo "$sty_pg" | grep -qF 'story-say' \
    && [ "$(echo "$sty_pg" | grep -c 'class="hint story-src"')" = 7 ] || STY_SN="$STY_SN [$x: 7 sections]"
done
[ "$(echo "$STY_EN" | grep -oE 'src="/stories/trash-in-numbers/img/en-[1-7]\.jpg"' | sort -u | wc -l | tr -d ' ')" = 7 ] \
  && [ "$(echo "$STY_SID" | grep -oE 'src="/stories/trash-in-numbers/img/id-[1-7]\.jpg"' | sort -u | wc -l | tr -d ' ')" = 7 ] || STY_SN="$STY_SN [slides]"
for n in "big: { en: '0/420', id: '0/420' }" "big: { en: '142,000', id: '142.000' }" "big: { en: '1 IN 4', id: '1 DARI 4' }" "big: { en: '57%', id: '57%' }" \
         "big: { en: '2013', id: '2013' }" "big: { en: '9,450', id: '9.450' }" "big: { en: 'SAPU.EARTH', id: 'SAPU.EARTH' }" "Only about 28% get it picked up" "Hanya sekitar 28%"; do
  { [ ! -f "$SKETCH" ] || grep -qF "$n" "$SKETCH"; } || STY_SN="$STY_SN [slides: $n]"
done
# The story names no mission: nothing about a mission goes out before its cleanup is done (docs/stories.md).
for x in STY_EN STY_SID; do
  eval "sty_pg=\$$x"
  echo "$sty_pg" | grep -qiE 'href="/m/|25 nov|minangkabau|bandara|airport' && STY_SN="$STY_SN [$x names a mission]"
done
sty_data=$([ ! -f "$SKETCH" ] || sed -n "/^const STORIES = \[{/,/^}\];/p" "$SKETCH")
[ ! -f "$SKETCH" ] || [ "$(echo "$sty_data" | grep -c "^  name: '")" -ge 2 ] || STY_SN="$STY_SN [STORIES not found]"
echo "$sty_data" | grep -qiE "25 NOV|AIRPORT|BANDARA|/m/" && STY_SN="$STY_SN [STORIES name a mission]"
[ -z "$STY_SN" ] && ok "the story gives every number with its source in both languages (KLH, Antara, Metro TV, SKI 2023, UU 18/2008, Kompas), seven sections whose slide has Sapu's line at the end of its description and not again under it (Marcus, 2026-11-16), the seven slides of its own language, the slides say the same numbers, and neither the pages nor the slides name a mission before its cleanup" \
  || bad "story numbers and sources" "$STY_SN"
# The second story's numbers, each with its source, on both pages, and the same numbers on its slides (its entry in
# STORIES in assets/brand/sapu-sketch/sapu-sketch.html). It names no mission either.
STY_SN=""
for n in '262,900 tonnes' 'US$105 million' '252,300 tonnes of 2023' 'about 720 tonnes a day' '107,500 from the Netherlands, 59,100 from Germany and 28,800 from Belgium' \
         '19% of all the plastic waste the EU exported' '1 January 2025' 'sorted or not' '215,000 tonnes' 'Malaysia (276,000 tonnes)' 'more than 810,000 tonnes' \
         '21 November 2026' 'until 21 May 2029 at least' '2.8 million tonnes' 'at most 2% other trash' 'up to 40% plastic and hazardous waste' \
         '195,400 of 262,900 tonnes, which is 74%' 'the 366 days of 2024' 'href="/crews">sapu.earth/crews</a>'; do
  echo "$STY2_EN" | grep -qF "$n" || STY_SN="$STY_SN [en: $n]"
done
for n in '262.900 ton' 'US$105 juta' '252.300 ton pada 2023' 'sekitar 720 ton per hari' '107.500 ton dari Belanda, 59.100 dari Jerman dan 28.800 dari Belgia' \
         '19% dari semua sampah plastik yang diekspor Uni Eropa' '1 Januari 2025' 'terpilah atau tidak' '215.000 ton' 'Malaysia (276.000 ton)' 'lebih dari 810.000 ton' \
         '21 November 2026' 'setidaknya sampai 21 Mei 2029' '2,8 juta ton' 'paling banyak 2%' 'sampai 40% dalam satu kontainer' \
         '195.400 dari 262.900 ton, yaitu 74%' '366 hari di tahun 2024' 'href="/crews">sapu.earth/crews</a>'; do
  echo "$STY2_ID" | grep -qF "$n" || STY_SN="$STY_SN [id: $n]"
done
for sty_src in 'goodstats.id/article/indonesia-terima-kiriman-sampah-dari-eropa-ada-plastik-hingga-kertas-Tpiyv' 'rri.co.id/internasional/1474482/' \
           'kalsel.antaranews.com/berita/437281/' 'thediplomat.com/2025/03/indonesias-ban-on-importing-plastic-waste' \
           'environment.ec.europa.eu/news/commission-publishes-draft-list-countries-authorised-import-eu-waste-2026-09-18_en' \
           'lestari.kompas.com/read/2026/05/04/103835486/' 'environment.ec.europa.eu/topics/waste-and-recycling/waste-shipments/plastic-waste-shipments_en' \
           'eur-lex.europa.eu/eli/reg/2024/1157/oj' 'industri.kontan.co.id/news/industri-kertas-masih-impor-40-bahan-baku-daur-ulang' \
           'cnnindonesia.com/nasional/20240826190506-506-1137732/' 'have-your-say/initiatives/14861-' 'cirs-group.com/en/chemicals/eu-publishes-authorized-list'; do
  echo "$STY2_EN" | grep -qF "$sty_src" && echo "$STY2_ID" | grep -qF "$sty_src" || STY_SN="$STY_SN [source: $sty_src]"
done
for x in STY2_EN STY2_ID; do
  eval "sty_pg=\$$x"
  [ "$(echo "$sty_pg" | grep -oE 'class="story-slide" [^>]* alt="[^"]* Sapu: “[^"]*”"' | wc -l | tr -d ' ')" = 7 ] && ! echo "$sty_pg" | grep -qF 'story-say' \
    && [ "$(echo "$sty_pg" | grep -c 'class="hint story-src"')" = 7 ] || STY_SN="$STY_SN [$x: 7 sections]"
  echo "$sty_pg" | grep -qiE 'href="/m/|25 nov|minangkabau|bandara|airport' && STY_SN="$STY_SN [$x names a mission]"
done
[ "$(echo "$STY2_EN" | grep -oE 'src="/stories/trash-with-a-passport/img/en-[1-7]\.jpg"' | sort -u | wc -l | tr -d ' ')" = 7 ] \
  && [ "$(echo "$STY2_ID" | grep -oE 'src="/stories/trash-with-a-passport/img/id-[1-7]\.jpg"' | sort -u | wc -l | tr -d ' ')" = 7 ] || STY_SN="$STY_SN [slides]"
for n in "name: 'trash-with-a-passport'" "big: { en: '262,900', id: '262.900' }" "big: { en: '3 IN 4', id: '3 DARI 4' }" "big: { en: '1 JAN 2025', id: '1 JAN 2025' }" \
         "big: { en: '215,000', id: '215.000' }" "big: { en: '21 NOV 2026', id: '21 NOV 2026' }" "big: { en: '2.8 MILLION', id: '2,8 JUTA' }" \
         "Then Germany, 59,100, and Belgium, 28,800." "Ecoton found up to 40% in one container."; do
  { [ ! -f "$SKETCH" ] || grep -qF "$n" "$SKETCH"; } || STY_SN="$STY_SN [slides: $n]"
done
[ -z "$STY_SN" ] && ok "the second story gives every number with its source in both languages (BPS, Eurostat, KLH, the European Commission, Regulation (EU) 2024/1157, Kemenperin, Ecoton), seven sections with Sapu's line in each slide's description only, its own seven slides, the same numbers in STORIES, and no mission" \
  || bad "the second story's numbers and sources" "$STY_SN"
# The share cards: what a shared link shows on WhatsApp, Facebook and X. 1200 x 630, and under 300 KB, the weight at
# which WhatsApp is said to drop a link's picture without a word.
STY_SC=""
for sty_pc in "trash-in-numbers/ card-en" "trash-in-numbers/id/ card-id" "trash-with-a-passport/ card-en" "trash-with-a-passport/id/ card-id"; do
  read -r sp c <<< "$sty_pc"
  p="/stories/$sp"; s="${sp%%/*}"
  sty_pg=$(curl -s "$B$p")
  echo "$sty_pg" | grep -qF "<meta property=\"og:image\" content=\"https://sapu.earth/stories/$s/img/$c.jpg\">" || STY_SC="$STY_SC $p:og:image"
  echo "$sty_pg" | grep -qF '<meta property="og:image:width" content="1200">' && echo "$sty_pg" | grep -qF '<meta property="og:image:height" content="630">' || STY_SC="$STY_SC $p:og:size"
  echo "$sty_pg" | grep -qF "<meta property=\"og:url\" content=\"https://sapu.earth$p\">" && echo "$sty_pg" | grep -qF '<meta property="og:type" content="article">' || STY_SC="$STY_SC $p:og:url"
  echo "$sty_pg" | grep -qF '<meta name="twitter:card" content="summary_large_image">' && echo "$sty_pg" | grep -qF "<meta name=\"twitter:image\" content=\"https://sapu.earth/stories/$s/img/$c.jpg\">" || STY_SC="$STY_SC $p:twitter"
  curl -s -o "$T/$s-$c.jpg" "$B/stories/$s/img/$c.jpg"
  sty_dim=$(python3 - "$T/$s-$c.jpg" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
i = 2
while i + 9 < len(d):
    if d[i] != 0xFF: i += 1; continue
    m = d[i + 1]
    if m in (0xC0, 0xC1, 0xC2):
        h, w = struct.unpack(">HH", d[i + 5:i + 9]); print(f"{w}x{h}"); break
    if m == 0xD8 or m == 0x01 or 0xD0 <= m <= 0xD7: i += 2; continue
    i += 2 + struct.unpack(">H", d[i + 2:i + 4])[0]
PY
)
  sty_size=$(wc -c < "$T/$s-$c.jpg" | tr -d ' ')
  [ "$sty_dim" = 1200x630 ] && [ "$sty_size" -gt 20000 ] && [ "$sty_size" -lt 300000 ] || STY_SC="$STY_SC $s/$c:$sty_dim:${sty_size}B"
done
[ -z "$STY_SC" ] && ok "each language of both stories has its own share card: og:image with its size, og:url, article, a large X card, and the picture is a 1200 x 630 JPEG under 300 KB" \
  || bad "story share cards" "$STY_SC"
# The homepage shows the newest story under THE RECEIPTS (Marcus, 2026-11-16), so a visitor from the Instagram bio link
# finds the stories without the footer: the share picture, the title, READ THE STORY, the Indonesian page, ALL STORIES.
# The newest is trash-with-a-passport since 2026-11-16 (docs/stories.md, step 4 of a new story).
STY_HP=$(curl -s $B/)
STY_HR=$(echo "$STY_HP" | sed -n '/<section class="reports" id="reports">/,/<\/section>/p')
sty_ln() { echo "$STY_HP" | grep -nF "$1" | head -1 | cut -d: -f1; }
echo "$STY_HR" | grep -qF '<h2><mark>SAPU REPORTS</mark></h2>' \
  && echo "$STY_HR" | grep -qF '<a class="all-link" href="/stories/">ALL STORIES →</a>' \
  && echo "$STY_HR" | grep -qF '<a class="report-pic" href="/stories/trash-with-a-passport/"><img src="/stories/trash-with-a-passport/img/card-en.jpg" width="1200" height="630" loading="lazy" alt="262,900 tonnes of plastic waste imported in 2024.' \
  && echo "$STY_HR" | grep -qF "<h3>TRASH WITH A PASSPORT</h3>" \
  && echo "$STY_HR" | grep -qF '<a class="btn" href="/stories/trash-with-a-passport/">READ THE STORY →</a>' \
  && echo "$STY_HR" | grep -qF '<a href="/stories/trash-with-a-passport/id/" hreflang="id" lang="id">BACA DALAM BAHASA INDONESIA →</a>' \
  && ! echo "$STY_HR" | grep -qiE '<script|mission|/m/' \
  && [ "$(sty_ln '<section class="receipts" id="receipts">')" -lt "$(sty_ln '<section class="reports" id="reports">')" ] \
  && [ "$(sty_ln '<section class="reports" id="reports">')" -lt "$(sty_ln '<section class="cta">')" ] \
  && [ "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' $B/stories/trash-with-a-passport/img/card-en.jpg)" = "200 image/jpeg" ] \
  && curl -s $B/site/styles.css | grep -qF '.receipts h2, .nextup h2, .reports h2, .cta h2 {' \
  && ok "the homepage shows SAPU REPORTS between THE RECEIPTS and WANT IN?, with no script and no mission: the newest story's share picture (its size, lazy), its title, READ THE STORY, the Indonesian page and ALL STORIES" \
  || bad "homepage SAPU REPORTS" "$(echo "$STY_HR" | head -3)"
curl -s $B/ | grep -q 'href="/apply/"' && ok "homepage links to /apply/" || bad "homepage apply link" ""
UP=$(curl -s $B/upload/)
echo "$UP" | grep -q 'class="panel save-link"' && echo "$UP" | grep -q 'id="saveLink"' && ok "upload page has the save-this-link card" || bad "save-link card" ""
curl -s $B/upload/upload.js | grep -q 'sapu-link-saved:' && ok "upload.js remembers a saved link per device" || bad "upload.js save-link flag" ""
echo "$UP" | grep -q 'id="home"' && echo "$UP" | grep -q 'id="mform"' && [ "$(echo "$UP" | grep -c 'data-go="mission"')" = 2 ] \
  && [ "$(echo "$UP" | grep -c 'data-go="plain"')" = 1 ] && echo "$UP" | grep -q 'name="mission_id"' && echo "$UP" | grep -q 'id="back"' \
  && ! echo "$UP" | grep -qE 'id="mode"|data-mode=|id="fundedNote"' \
  && ok "upload page opens on the crew page, with POST A MISSION, a cleanup without a mission and the mission select" || bad "upload page crew page" ""
curl -s $B/upload/upload.js | grep -q 'sapu-mission-draft:' && ok "upload.js keeps the mission draft apart" || bad "upload.js mission draft" ""
# Language switch: every message keeps its text key and values on its element (setMsg), and applyLang shows it again.
I18U=$(curl -s $B/upload/upload.js)
I18A=$(curl -s $B/apply/apply.js)
echo "$I18U" | grep -q 'function setMsg(el, key, vars' && echo "$I18U" | grep -qF '$$("[data-i18n]").forEach((el) => { el.textContent = textFor(el); });' \
  && ok "upload.js keeps the text key of each message on its element, so switching language translates it" || bad "upload.js message keys" "no setMsg, or applyLang does not use textFor"
echo "$I18U" | grep -nE '(\$\((u\.(err|send|status)|UI\[[a-z]+\]\.(err|send|status)|GEO\[[a-z]+\]\.msg|"#(formErr|mformErr|send|msend|status|mstatus|reloadNote|missionMsg|geoMsg|mgeoMsg|ref)")\)|[^A-Za-z_.](msg|m)|fmsgFor\([^)]*\))\.textContent = ' \
  && bad "upload.js writes a message without keeping its key" "see the lines above" || ok "upload.js writes the error lines, status lines, notes and SEND labels only through setMsg"
# The other old forms: the photo and video message boxes ([data-msg]) and loops that empty the .fmsg boxes.
# Written with textContent, a box keeps its data-i18n, so the cleared message comes back at the next switch.
echo "$I18U" | grep -n 'textContent = ' | grep -E 'fmsg|data-msg|Err"|Msg"' \
  && bad "upload.js writes or clears a field, photo or video message without setMsg" "see the lines above" || ok "upload.js writes and clears the field, photo and video messages only through setMsg"
echo "$I18U" | grep -A2 -F '$$(".fmsg"' | grep -F 'textContent = ' \
  && bad "upload.js empties the .fmsg boxes in a loop without setMsg" "see the lines above" || ok "upload.js empties the .fmsg boxes only through setMsg"
printf '%s\n%s\n' "$I18U" "$I18A" | grep -nE 'inner(Text|HTML) =' \
  && bad "upload.js or apply.js writes innerText or innerHTML" "see the lines above" || ok "upload.js and apply.js never write innerText or innerHTML"
# apply.js writes text directly only in these places (setMsg, applyLang, the country list, the WhatsApp echo
# and hint, a photo's remove button, the reference): anything new goes through setMsg or is added here.
echo "$I18A" | grep -n 'textContent = ' | grep -vF -e 'el.textContent = key ? textFor(el) : "";' \
  -e '$$("[data-i18n]").forEach((el) => { el.textContent = textFor(el); });' -e 'sel.textContent = "";' \
  -e 'echo.textContent = ok ? t("wa_echo", { n }) : "";' -e 'hint.textContent = t(w.key, w.vars);' \
  -e 'rm.textContent = "✕";' -e '$("#ref").textContent = `${t("ref")}: ${refId.toUpperCase()}`;' \
  && bad "apply.js writes text without setMsg outside its known places" "see the lines above" || ok "apply.js writes its messages only through setMsg"
echo "$I18U" | grep -qF 'setMsg($(u.send), "try_again")' && echo "$I18U" | grep -qF 'setMsg($(u.send), u.sendKey)' \
  && echo "$I18U" | grep -qF 'setMsg($("#send"), "send")' && echo "$I18U" | grep -qF 'setMsg($("#msend"), "m_send")' \
  && ok "upload.js keeps TRY AGAIN as a key and goes back to SEND after a send and after BACK TO YOUR CREW PAGE" || bad "upload.js TRY AGAIN key" "setMsg for try_again or the send keys missing"
echo "$I18A" | grep -qF 'function status(key, vars) { setMsg($("#status"), key, vars); }' && echo "$I18A" | grep -qF '"e_rejected", null, { post:' \
  && echo "$I18A" | grep -qF '$$("[data-i18n]").forEach((el) => { el.textContent = textFor(el); });' \
  && ok "apply.js keeps the key of its status line and the server's detail, so switching language translates them" || bad "apply.js message keys" "status line or e_rejected detail without a key"
# The upload page fixes of the reviews, each held by its line.
echo "$I18U" | grep -qF 'setMsg(btn, "share");' \
  && echo "$I18U" | grep -qF 'status("up_file_mb", { ...at, a: mb(e.loaded), b: mb(e.total) });' && [ "$(echo "$I18U" | grep -cF 'up_file_mb: "')" = 2 ] \
  && echo "$I18U" | grep -qF 'if (!all.some((x) => x.key)) $(u.progress).hidden = true;' \
  && ok "upload.js: SHARE comes back after COPIED, the upload line translates whole, no empty bar after a failed send" || bad "upload.js SHARE, upload line or bar" ""
AGAIN=$(echo "$I18U" | sed -n '/^  function resetCleanup() {/,/^  }$/p')
MAGAIN=$(echo "$I18U" | sed -n '/^  function resetMission() {/,/^  }$/p')
echo "$AGAIN" | grep -qF 'clearMarks(form);' && echo "$AGAIN" | grep -qF 'for (const k of ["before", "after", "video_before", "video_after"]) fieldMsg(k);' \
  && echo "$AGAIN" | grep -qF 'setMsg($("#geoMsg"));' && echo "$AGAIN" | grep -qF 'reloadDone("cleanup");' \
  && echo "$MAGAIN" | grep -qF 'clearMarks(mform);' && echo "$MAGAIN" | grep -qF 'fieldMsg("now");' && echo "$MAGAIN" | grep -qF 'fieldMsg("now_video");' \
  && echo "$MAGAIN" | grep -qF 'setMsg($("#mgeoMsg"));' && echo "$MAGAIN" | grep -qF 'reloadDone("mission");' \
  && echo "$I18U" | grep -qF '$("#again").addEventListener("click", () => { resetCleanup(); toHome(); });' \
  && echo "$I18U" | grep -qF '$("#mAgain").addEventListener("click", () => { resetMission(); toHome(); });' \
  && ok "BACK TO YOUR CREW PAGE (after THANK YOU and MISSION #N) empties the form just sent and clears every message of it" || bad "upload.js resetCleanup, resetMission" "$(echo "$AGAIN" | head -3)"
[ "$(echo "$I18U" | grep -cF 'reloadDone("cleanup");')" = 2 ] && [ "$(echo "$I18U" | grep -cF 'reloadDone("mission");')" = 2 ] \
  && ok "the note to add the photos again goes once the drafts it was about are sent or emptied" || bad "upload.js reload note" ""
echo "$I18U" | grep -qF 'if (code === "limit") return new Fatal("e_limit");' && echo "$I18U" | grep -qF 'status === 429 || status >= 500' \
  && [ "$(echo "$I18U" | grep -cF '(r.status >= 500 || r.status === 429) && attempt < waits.length')" = 2 ] \
  && ok "upload.js waits out a rate limit block (a 429 without our code) instead of saying try again tomorrow" || bad "upload.js 429" ""
AJ=$(curl -s $B/admin/admin.js)
echo "$AJ" | grep -qF 'preload="none"' && ! echo "$AJ" | grep -qF 'preload="metadata"' \
  && ok "admin videos load when played, so a long list stays under the rate limit" || bad "admin.js video preload" ""
UJ=$(curl -s $B/upload/upload.js)
[ "$(echo "$UJ" | grep -cE 'e_m_resend:|e_mission_gone_alone:|e_mission_taken_alone:|m_done_updated:')" = 8 ] \
  && ok "upload.js explains an updated mission, one that can no longer be changed, and a gone mission when no picker is left (EN and ID)" \
  || bad "upload.js new mission messages" "expected 8 lines"
# What the site never says on its own goes into the ready messages (docs/upload-flow.md, docs/missions.md)
echo "$AJ" | grep -qF 'Only funded missions are paid, so please wait for our OK before you start.' && echo "$AJ" | grep -qF 'Hanya misi yang didanai yang dibayar, jadi tunggu kabar dari kami sebelum mulai.' \
  && echo "$AJ" | grep -qF 'Please send me your payout details' && echo "$AJ" | grep -qF 'Tolong kirim data untuk pembayaran' \
  && echo "$AJ" | grep -qF 'holder.append(welcomeBox(r, { contact_name: ""' \
  && ok "the welcome message explains missions, the advance, the rest and the #N paper and asks for payout details (EN and ID), also after NEW PARTNER" || bad "admin.js welcome message" ""
echo "$AJ" | grep -qF 'function missionFundedText(lang, m)' && echo "$AJ" | grep -qF 'data-act="message"' && echo "$AJ" | grep -qF 'title: "Tell the crew it is funded"' \
  && echo "$AJ" | grep -qF 'msgAfterFund = m.id;' && echo "$AJ" | grep -qF 'Utamakan keselamatan' && ! echo "$AJ" | grep -qF '} sent` : "none"' \
  && echo "$AJ" | grep -qF 'if (box && box === fund) fund.elements.funded_eur.focus();' \
  && ok "a funded mission has a ready message for the crew (EN and ID), opened right after FUND, and its card no longer says the advance was sent" || bad "admin.js funded message" ""
# The crew texts name no payment service (the money can go whatever way suits the crew): the welcome message and the
# funded message, with and without an advance, run in node, say the money goes to the crew's bank account or e-wallet,
# in local money (rupiah in Indonesian), at the exchange rate of the day it is sent ("kurs yang berlaku"). Only Marcus's
# own instructions in admin.js name Wise, and no crew page or Function does.
printf '%s' "$AJ" > "$T/admin-texts.js"
CT=$(node -e '
const src = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
eval([/^  const n = .*$/m, /^  const isNum = .*$/m, /^  const cents = .*$/m, /^  const missionNo = .*$/m, /^  const spotsOf = .*$/m, /^  const lastDay = .*$/m, /^  const ADVANCE_PCT = .*$/m].map(line).join("\n") + "\n" +
  ["welcomeText", "declineText", "missionDeclineText", "missionFundedText"].map(fn).join("\n") +
  "\nObject.assign(globalThis, { welcomeText, declineText, missionDeclineText, missionFundedText });");
const a = { contact_name: "Ayu", org_name: "Kali Crew" };
const m = (adv) => ({ no: 12, place_name: "Pantai Kuta", funded_eur: 20, advance_eur: adv, plan_date: "2099-01-05", contact: { contact_name: "Ayu" } });
const en = "We send the money to your bank account or e-wallet. You receive it in your local money, at the exchange rate on the day we send it.";
const id = "Kami kirim uangnya ke rekening bank atau e-wallet kalian, dan kalian menerimanya dalam rupiah, dengan kurs yang berlaku pada hari uang itu dikirim.";
const want = {
  "en welcome": "3. When we fund it, we tell you the amount in euros. We send an advance (usually 30% of it) to your bank account or e-wallet, and the rest after we approve your cleanup. You receive it in your local money, at the exchange rate on the day we send it.\n",
  "id welcome": "3. Kalau misinya didanai, kami kabari jumlahnya dalam euro. Kami kirim uang muka (biasanya 30% dari jumlah itu) ke rekening bank atau e-wallet kalian, dan sisanya setelah laporan aksi bersih kalian kami setujui. Uangnya kalian terima dalam rupiah, dengan kurs yang berlaku pada hari uang itu dikirim.\n",
  "en funded": "Sapu Earth pays EUR 20 for it: EUR 6 now as an advance, and EUR 14 after we approve your cleanup. " + en + "\n",
  "en funded, no advance": "Sapu Earth pays EUR 20 for it, all of it after we approve your cleanup. " + en + "\n",
  "id funded": "Sapu Earth membayar EUR 20 untuk misi ini: EUR 6 sekarang sebagai uang muka, dan EUR 14 setelah laporan aksi bersih kalian kami setujui. " + id + "\n",
  "id funded, no advance": "Sapu Earth membayar EUR 20 untuk misi ini, seluruhnya setelah laporan aksi bersih kalian kami setujui. " + id + "\n",
};
const texts = {};
for (const l of ["en", "id"]) {
  texts[l + " welcome"] = welcomeText(l, a, "https://sapu.earth/upload/?k=x");
  texts[l + " funded"] = missionFundedText(l, m(6));
  texts[l + " funded, no advance"] = missionFundedText(l, m(0));
  texts[l + " decline"] = declineText(l, a);
  texts[l + " mission decline"] = missionDeclineText(l, m(0));
}
const bad = [];
for (const [k, t] of Object.entries(texts)) {
  if (/\bwise\b/i.test(t)) bad.push(k + " names Wise");
  if (/[\u2013\u2014]/.test(t)) bad.push(k + " has an en or em dash");
  if (want[k] && !t.includes(want[k])) bad.push(k + " lacks the new money line");
}
console.log(bad.length ? bad.join("; ") : "ok " + Object.keys(texts).length);
' "$T/admin-texts.js" 2>&1)
check "the welcome, funded (with and without an advance) and decline messages name no payment service, and the money goes to the bank account or e-wallet in local money at the day's rate (EN and ID, run in node)" "$CT" "ok 10"
WL=$(echo "$AJ" | grep -w 'Wise' | grep -vF -e 'so check Wise first).' -e 'after the advance has gone out with Wise.' \
  -e '"Send the advance with Wise first, then this message.",' -e ' now with Wise, ` +')
WC=$(curl -s $B/ $B/site/app.js $B/upload/ $B/upload/upload.js $B/upload/videoclean.js $B/apply/ $B/apply/apply.js $B/impressum/ $B/no-such-page | grep -cw 'Wise')
[ -z "$WL" ] && [ "$(echo "$AJ" | grep -cw 'Wise')" = 4 ] && [ "$WC" = 0 ] && [ -z "$(grep -rlw 'Wise' functions)" ] \
  && ok "only Marcus's own steps in admin.js name Wise (check Wise first, send the advance with Wise); no crew page, script or Function does" \
  || bad "Wise in crew texts" "admin.js: $WL; pages: $WC; functions: $(grep -rlw 'Wise' functions | tr '\n' ' ')"
[ "$(echo "$UJ" | grep -cE ' (plan_date_hint|safety_h|safety_[1-7]|safety_price):')" = 20 ] && echo "$UJ" | grep -qF 'const MISSION_DEFAULT_DAYS = 7;' \
  && [ "$(echo "$UP" | grep -cE 'data-i18n="(safety_h|safety_[1-7]|safety_price|plan_date_hint)"')" = 10 ] \
  && echo "$UJ" | grep -qF 'if (each.bad) bad("m-each", "");' && echo "$UJ" | grep -qF 'else if (each.v === null) bad("m-each", "e_each");' \
  && echo "$UJ" | grep -qF 'if (other.bad) bad("m-other", "");' && echo "$UJ" | grep -qF 'if (sum && !(sum.total > 0)) bad("m-each", "e_sum_zero");' \
  && [ "$(echo "$UJ" | grep -cF 'only funded missions are paid.')" = 3 ] && [ "$(echo "$UJ" | grep -cF 'hanya misi yang didanai yang dibayar.')" = 3 ] \
  && ok "POST A MISSION starts a week ahead, shows the safety basics, says when it cannot read a price, and its done screen and the card of a mission in review say to wait for the funding (EN and ID)" || bad "upload.js mission day, safety, wait" ""
echo "$AJ" | grep -qF 'const misPoint = ownPoint ? null : pointOf(mis);' && echo "$AJ" | grep -qF 'Lat and Lng are prefilled with the point of mission #' \
  && echo "$AJ" | grep -qF '{ lat: r3(m.lat), lng: r3(m.lng), no: missionNo(m) }' \
  && echo "$AJ" | grep -qF 'if (!ownPoint && ((val("lat") === null && val("lng") === null) || ptHeld())) {' \
  && ok "PENDING fills Lat and Lng with the mission's point when a cleanup came without one (also after Link to mission)" || bad "admin.js mission point prefill" ""
HP=$(curl -s $B/)
# The three steps under the receipts (CREW SUITS UP, FILMED, NOT FAKED, LOGGED ON THE GLOBE) went on 2026-11-16 (Marcus):
# the ticker, the crew box and the globe said the same, and their one promise of their own is in THE RECEIPTS' line.
echo "$HP" | grep -qF '<p class="sub">// every cleanup. filmed before and after, location logged, who got paid.</p>' \
  && ! echo "$HP" | grep -qE 'class="how|CREW SUITS UP|LOGGED ON THE GLOBE' \
  && ! echo "$HP" | grep -qE '[0-9]+ locals' && ! echo "$HP" | grep -qi 'same day' && ! echo "$SJ" | grep -qi 'same day' \
  && ! echo "$HP" | grep -qF 'GPS on' && ! echo "$HP" | grep -qi 'forever' \
  && ! curl -s $B/site/styles.css | grep -qE '^\.how' \
  && ok "the homepage promises only what the site does: THE RECEIPTS says filmed before and after with the location logged (photos carry no GPS); no fixed crew size (each mission sets its own), no same-day pay, nothing forever (receipts can be unpublished); the three steps are gone, styles too" || bad "homepage promises" ""
# The way in for crews: the apply link on the first screen, and how a returning crew gets back in (there is no login)
APH=$(curl -s $B/apply/); APJ=$(curl -s $B/apply/apply.js)
echo "$HP" | grep -qF '<a class="crew-link" href="/apply/">CLEANUP CREW?<br>APPLY →</a>' && echo "$HP" | grep -qF '// already a crew with us? open the private link' \
  && echo "$APH" | grep -qF 'data-i18n="already"' && [ "$(echo "$APJ" | grep -cF '      already: ')" = 2 ] \
  && [ "$(echo "$UJ" | grep -E '      (no_link|bad_link): ' | grep -cF 'hello@sapu.earth')" = 4 ] \
  && ok "crews find APPLY on the first screen, and a returning crew is told to use its private link or ask hello@sapu.earth for a new one (EN and ID)" || bad "crew way in" ""
# Security headers on the static pages (_headers), and no local preview that serves the repo folder (ops/production-rules.md)
HH=$(curl -sI $B/ | tr -d '\r')
echo "$HH" | grep -qi '^x-frame-options: DENY$' && echo "$HH" | grep -qi "^content-security-policy: frame-ancestors 'none'; script-src 'self'; object-src 'none'; base-uri 'none'$" \
  && echo "$HH" | grep -qi '^x-content-type-options: nosniff$' && echo "$HH" | grep -qi '^referrer-policy: strict-origin-when-cross-origin$' \
  && { [ ! -f .claude/launch.json ] || { ! grep -q 'http.server' .claude/launch.json && grep -q 'scripts/dev.sh' .claude/launch.json; }; } \
  && ok "static pages cannot be framed, run scripts only from this site, are not sniffed, send only the origin as referrer; the preview never serves the repo folder" || bad "security headers / preview" "$(echo "$HH" | grep -iE 'frame|nosniff|referrer' | tr '\n' ' ')"
PN=$(echo "$UJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  eval(s.slice(s.indexOf("const CUR_SIGN"), s.indexOf("// Show how a typed number was read")));
  const cases = [["Rp 1.500.000,-", 1500000], ["₱5,000", 5000], ["1,500.50", 1500.5], ["1.500,50", 1500.5], ["1.500.000", 1500000], ["1,500", 1500],
    ["12,5", 12.5], ["25 kg", 25], ["IDR 1500000", 1500000], ["KSh 1,500", 1500], ["P5,000", 5000], ["1,5 jt", NaN], ["500 rb", NaN], ["1.5k", NaN],
    ["45 min", NaN], ["2 ton", NaN], ["abc", NaN], ["", null],
    ["1,500/=", 1500], ["KSh 1,500/=", 1500], ["Kshs. 1,500/=", 1500], ["1,500/= KSh", 1500], ["Rs. 500/-", 500], ["Tsh 5,000/-", 5000],
    ["25 000 FCFA", 25000], ["25.000 F CFA", 25000], ["FCFA 25 000", 25000], ["CFA 5000", 5000], ["5 000 F", 5000], ["XOF 25 000", 25000],
    ["25 000 FCFA", 25000], ["₦25,000", 25000], ["N25,000", 25000], ["NGN 25,000.00", 25000], ["GH₵ 500", 500], ["GHS 1,200", 1200],
    ["₵500", 500], ["USh 50,000", 50000], ["UGX 50,000/=", 50000], ["TSh 20,000/=", 20000], ["RWF 10,000", 10000], ["FRw 10 000", 10000],
    ["10.000 Rwf", 10000], ["R 1 500", 1500], ["R$ 50", 50], ["US$ 20", 20],
    ["500 francs", NaN], ["25 000 cedis", NaN], ["1500=", NaN], ["/=", NaN], ["KSh", NaN]];
  const wrong = cases.filter(([x, w]) => { const g = parseNum(x); return Number.isNaN(w) ? !Number.isNaN(g) : g !== w; });
  console.log(wrong.length ? "wrong: " + wrong.map((c) => c[0]).join(", ") : "ok");
});' 2>&1)
[ "$PN" = ok ] && ok "number fields read Rp 1.500.000,-, ₱5,000, 1,500.50, 25 kg, KSh 1,500/=, 500/-, 25 000 FCFA, CFA 5000, ₦25,000, GH₵ 500, USh 50,000 and FRw 10 000, and keep 1,5 jt, 500 rb, 45 min, 2 ton and 500 francs as errors" || bad "upload.js number parsing" "$PN"
# The currency a crew starts on comes from its country: every country on the page has its money, a country
# where two are in daily use (or none, the uninhabited ones) starts on Choose…, so the crew must pick one, the
# list always has the African currencies too, and nothing falls back to USD. upload.js's own tables and
# fillCurrencies, run in node on a fake select.
cat > "$T/cur.js" <<'JS'
const s = require("fs").readFileSync(process.argv[2], "utf8");
class Option { constructor(text, value) { this.text = text; this.value = value; } }
const mk = () => ({ options: [], v: "", get value() { return this.v; },
  set value(x) { this.v = this.options.some((o) => o.value === x) ? x : ""; },
  set textContent(x) { this.options = []; this.v = ""; }, append(o) { this.options.push(o); }, addEventListener() {} });
const sels = { cleanup: mk(), mission: mk() }, others = {};
const UI = { cleanup: { form: { elements: { currency: sels.cleanup } }, other: "#f-currency-other" },
             mission: { form: { elements: { currency: sels.mission } }, other: "#m-currency-other" } };
const $ = (q) => (others[q] = others[q] || {});
const code = s.slice(s.indexOf("const ISO = "), s.indexOf("const VIDEO_EXT")) +
  s.slice(s.indexOf("function fillCurrencies"), s.indexOf("function setWho"));
const P = new Function("Option", "UI", "$", "t", "let partner = null;\n" + code +
  "\nreturn { ISO, CURRENCIES, COUNTRY_CURRENCY, startCurrency, fillCurrencies, setPartner: (p) => { partner = p; } };")(Option, UI, $, (k) => k);
const bad = [];
const want = { ID: "IDR", PH: "PHP", MY: "MYR", TH: "THB", VN: "VND", IN: "INR", LK: "LKR", KE: "KES", UG: "UGX", TZ: "TZS",
  RW: "RWF", NG: "NGN", GH: "GHS", SN: "XOF", CI: "XOF", BJ: "XOF", CM: "XAF", ZA: "ZAR", BR: "BRL", US: "USD", ET: "ETB",
  ZM: "ZMW", ZW: "", KH: "", CD: "", AQ: "", "": "" };
for (const [c, w] of Object.entries(want)) {
  P.setPartner({ country: c });
  if (P.startCurrency() !== w) bad.push(`${c || "no country"} starts on ${P.startCurrency() || "Choose"}`);
}
P.setPartner(null);
if (P.startCurrency() !== "") bad.push("without a partner: " + P.startCurrency());
const keys = Object.keys(P.COUNTRY_CURRENCY);
if (keys.some((c) => !P.ISO.includes(c))) bad.push("a currency for a country not on the page");
if (P.ISO.filter((c) => !keys.includes(c)).join(" ") !== "AQ BV GS HM TF UM") bad.push("countries without money: " + P.ISO.filter((c) => !keys.includes(c)).join(" "));
if (Object.values(P.COUNTRY_CURRENCY).some((v) => !/^[A-Z]{3}( [A-Z]{3})?$/.test(v))) bad.push("a code that is not 3 letters");
if (["KES", "UGX", "TZS", "RWF", "NGN", "GHS", "XOF", "ZAR"].some((c) => !P.CURRENCIES.includes(c))) bad.push("the list misses an African currency");
const fill = (country) => { P.setPartner({ country }); for (const x of Object.values(sels)) x.textContent = ""; P.fillCurrencies(); };
fill("SN");
const o = sels.mission.options.map((x) => x.value);
if (o[0] !== "" || sels.mission.options[0].text !== "choose" || o[1] !== "XOF" || o[o.length - 1] !== "other" || sels.mission.value !== "XOF"
    || others["#m-currency-other"].hidden !== true) bad.push("Senegal: " + sels.mission.value + " of " + o.join(","));
sels.cleanup.value = "";
P.fillCurrencies(); // a language switch
if (sels.cleanup.value !== "" || sels.mission.value !== "XOF") bad.push("a language switch changed the choice");
fill("ZW");
const z = sels.cleanup.options.map((x) => x.value);
if (sels.cleanup.value !== "" || z[1] !== "ZWG" || z[2] !== "USD" || z.filter((x) => x === "USD").length !== 1) bad.push("Zimbabwe: " + sels.cleanup.value + " of " + z.join(","));
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
JS
echo "$UJ" > "$T/upload-page.js"
CUR=$(node "$T/cur.js" "$T/upload-page.js" 2>&1)
[ "$CUR" = ok ] && ok "a crew starts on its own currency (Ghana GHS, Nigeria NGN, Uganda UGX, Tanzania TZS, Rwanda RWF, South Africa ZAR, Senegal and Côte d'Ivoire XOF, and the rest of the world), or on Choose… where two are in daily use (Zimbabwe, Cambodia); a language switch keeps the choice (node)" \
  || bad "upload.js currencies (node)" "$CUR"
! echo "$UJ" | grep -qF '"USD";' && ! echo "$UJ" | grep -qF '|| "USD"' \
  && echo "$UJ" | grep -qF 'bad("f-currency", "e_currency_pick");' && echo "$UJ" | grep -qF 'else if (!currency) bad("m-currency", "e_currency_pick");' \
  && [ "$(echo "$UJ" | grep -cE '^      e_currency_pick: ')" = 2 ] && [ "$(echo "$UJ" | grep -cE ' choose: "')" = 2 ] \
  && [ "$(echo "$UP" | grep -cF '<span><b data-i18n="currency">Currency</b> <i class="req">*</i></span>')" = 1 ] \
  && ok "nothing falls back to USD: a mission, and a cleanup with costs, must name a currency (EN and ID), and the mission marks it required" || bad "upload.js currency choice" ""
# iPhones: the server refuses a WebKit canvas JPEG as it comes out of the canvas (it has Exif). The pages' own
# cleanJpeg, the same code in upload.js and apply.js, removes the Exif and Photoshop blocks, keeps a colour
# profile, and leaves every other byte as it was; the server then takes the photo. A partner of its own, so the
# other upload counts stay as they are.
AJS=$(curl -s $B/apply/apply.js)
clean_with() { node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", async () => {
  eval(s.slice(s.indexOf("async function cleanJpeg"), s.indexOf("// Re-encoding through a canvas")));
  const fs = require("fs");
  const out = await cleanJpeg(new Blob([fs.readFileSync(process.argv[1])], { type: "image/jpeg" }));
  fs.writeFileSync(process.argv[2], Buffer.from(await out.arrayBuffer()));
});' "$1" "$2"; }
echo "$UJ" | clean_with "$T/webkit.jpg" "$T/webkit-u.jpg" 2>"$T/clean.err"
echo "$AJS" | clean_with "$T/webkit.jpg" "$T/webkit-a.jpg" 2>>"$T/clean.err"
echo "$UJ" | clean_with "$T/webkit-icc.jpg" "$T/webkit-icc-u.jpg" 2>>"$T/clean.err"
echo "$UJ" | clean_with "$F/before.jpg" "$T/before-u.jpg" 2>>"$T/clean.err"
cmp -s "$T/webkit-u.jpg" "$F/before.jpg" && cmp -s "$T/webkit-a.jpg" "$F/before.jpg" && cmp -s "$T/webkit-icc-u.jpg" "$T/before-icc.jpg" && cmp -s "$T/before-u.jpg" "$F/before.jpg" \
  && ok "cleanJpeg (upload.js and apply.js) removes WebKit's Exif and Photoshop blocks, keeps the colour profile and every other byte, and leaves a clean JPEG alone" \
  || bad "cleanJpeg" "$(head -c 300 "$T/clean.err") sizes: $(size "$T/webkit-u.jpg" 2>/dev/null) $(size "$T/webkit-a.jpg" 2>/dev/null) vs $(size $F/before.jpg)"
[ "$(echo "$UJ" | sed -n '/async function cleanJpeg/,/^  }$/p')" = "$(echo "$AJS" | sed -n '/async function cleanJpeg/,/^  }$/p')" ] \
  && echo "$UJ" | grep -qF 'return cleanJpeg(blob);' && echo "$AJS" | grep -qF 'return cleanJpeg(blob);' \
  && ok "upload.js and apply.js run every canvas JPEG through the same cleanJpeg" || bad "cleanJpeg in both pages" "the functions differ, or toJpeg does not call it"
WP=$(curl -s -X POST $B/api/admin/partners -H "$A" -H 'content-type: application/json' -d "{\"name\":\"iPhone crew\",\"country\":\"PH\",\"slug\":\"iphone-$RANDOM$RANDOM\"}")
WTOK=$(echo "$WP" | jget "d['token']")
check "a WebKit (iPhone) canvas JPEG as it leaves the canvas -> 415" "$(code -X POST "$B/api/upload?k=$WTOK&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/webkit.jpg)" 415
WK=$(curl -s -X POST "$B/api/upload?k=$WTOK&kind=before" -H 'content-type: image/jpeg' --data-binary @$T/webkit-icc-u.jpg | jget "d['key']")
[[ $WK =~ ^[0-9a-f]{32}$ ]] && ok "the same photo after cleanJpeg (colour profile kept) -> stored" || bad "cleaned WebKit photo upload" "$WK"
# Crew logos, run in node: the pure block of functions/_lib/logos.js takes exactly what cleanJpeg leaves of a canvas
# JPEG (WebKit's too), square and 128 to 640 px, and nothing else; and the letters a crew without a logo shows.
echo "$UJ" | clean_with "$T/logo-webkit.jpg" "$T/logo-webkit-u.jpg" 2>>"$T/clean.err"
LGN=$(node -e '
const fs = require("fs"), dir = process.argv[1];
const s = fs.readFileSync("functions/_lib/logos.js", "utf8");
const a = s.indexOf("// ---------- logo checks (pure"), b = s.indexOf("// ---------- end of the logo checks");
if (a < 0 || b < a) throw new Error("no logo checks block");
const L = new Function(s.slice(a, b) + "return {LOGO, logoJpegInfo, monogram}")();
const info = (f) => JSON.stringify(L.logoJpegInfo(new Uint8Array(fs.readFileSync(f))));
const bad = [];
for (const f of ["logo", "logo-icc", "logo-webkit-u", "logo-scans"]) if (info(dir + "/" + f + ".jpg") !== "{\"w\":320,\"h\":320}") bad.push(f + " " + info(dir + "/" + f + ".jpg"));
const refused = [dir + "/webkit.jpg", dir + "/fake.jpg", "tests/fixtures/before.jpg",
  ...("logo-webkit logo-heavy " + process.argv[2]).split(" ").map((x) => dir + "/" + x + ".jpg")];
for (const f of refused) if (info(f) !== "null") bad.push(f.split("/").pop() + " taken: " + info(f));
if (L.logoJpegInfo(new Uint8Array(0)) !== null) bad.push("an empty file taken");
for (const [n, w] of [["Sapu Bersih Padang", "SB"], ["Pulau Biru", "PB"], ["Komunitas Uji Pantai (TEST)", "KU"],
  ["Kali Bersih <b>Crew</b>", "KB"], ["ocean", "OC"], ["", "?"]]) if (L.monogram(n) !== w) bad.push("monogram " + n + ": " + L.monogram(n));
if (L.LOGO.reviewDays !== 90 || L.LOGO.perDay !== 10) bad.push("LOGO " + JSON.stringify(L.LOGO));
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T" "$LOGO_BAD" 2>&1)
[ "$LGN" = ok ] && ok "the server takes a square logo JPEG with a comment or a colour profile, WebKit's after cleanJpeg and one with a table and a second scan, and refuses before.jpg (not square), WebKit's as it leaves the canvas, every variant with camera data, XMP, other blocks, a tail, an Exif block or a second JPEG after the end, an APP1 between scans or a wrong size, and an empty file; monograms SB, PB, KU, KB, OC, ? (node)" \
  || bad "logo checks (node)" "$LGN"
# The crew logo block, the same in upload.js and apply.js, run in node: the whole picture fitted inside 320 px and
# centred, never cropped; a light logo on a see-through PNG goes on ink, everything else on white.
LBU=$(echo "$UJ" | sed -n '/^  \/\/ ---------- crew logo: the same block/,/^  \/\/ ---------- end of the crew logo block ----------$/p')
LBA=$(echo "$AJS" | sed -n '/^  \/\/ ---------- crew logo: the same block/,/^  \/\/ ---------- end of the crew logo block ----------$/p')
LBN=$(printf '%s' "$LBU" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const B = new Function(s + "\nreturn { LOGO_SIDE, logoFit, logoBackground };")();
  const bad = [];
  const eq = (n, g, w) => { if (JSON.stringify(g) !== JSON.stringify(w)) bad.push(n + ": " + JSON.stringify(g)); };
  eq("logoFit(1000, 500)", B.logoFit(1000, 500), { dx: 10, dy: 85, dw: 300, dh: 150 });
  eq("logoFit(100, 100)", B.logoFit(100, 100), { dx: 10, dy: 10, dw: 300, dh: 300 });
  eq("logoFit(300, 900)", B.logoFit(300, 900), { dx: 110, dy: 10, dw: 100, dh: 300 });
  const px = (...groups) => new Uint8Array(groups.flatMap(([n, rgba]) => Array.from({ length: n }, () => rgba).flat()));
  const W = [255, 255, 255, 255], K = [0, 0, 0, 255], C = [255, 255, 255, 0];
  eq("50 see-through, 50 white", B.logoBackground(px([50, C], [50, W])), "#1c1813");
  eq("50 see-through, 50 black", B.logoBackground(px([50, C], [50, K])), "#ffffff");
  eq("100 white", B.logoBackground(px([100, W])), "#ffffff");
  eq("100 see-through", B.logoBackground(px([100, C])), "#ffffff");
  eq("99 white, 1 see-through", B.logoBackground(px([99, W], [1, C])), "#ffffff");
  eq("LOGO_SIDE", B.LOGO_SIDE, 320);
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
});' 2>&1)
[ -n "$LBU" ] && [ "$LBU" = "$LBA" ] && [ "$LBN" = ok ] && echo "$LBU" | grep -qF 'LOGO_SIDE = 320' && echo "$LBU" | grep -qF '"image/jpeg"' \
  && echo "$LBU" | grep -qF 'await cleanJpeg(out)' \
  && ok "the crew logo block is the same in upload.js and apply.js: the whole picture fitted in 320 px and centred, a light logo on a see-through PNG on ink, the JPEG through cleanJpeg (node)" \
  || bad "the crew logo block" "$([ "$LBU" = "$LBA" ] && echo same || echo differ) $LBN"
# A private link pasted with a "." or ")" after it, or a space in it, still opens, and the address bar gets the clean link.
echo "$UJ" | grep -qF 'const token = rawToken.replace(/[^A-Za-z0-9_-]/g, "");' && echo "$UJ" | grep -qF 'history.replaceState(history.state, "", `${location.pathname}?k=${token}${location.hash}`)' \
  && ok "upload.js keeps only the token characters of a pasted link and cleans the address bar" || bad "upload.js link repair" ""
# SEND tapped while photos are still being prepared waits for them and goes on; consent is unticked when files are picked, not after.
[ "$(echo "$UJ" | grep -cF 'await filesReady(')" = 2 ] && [ "$(echo "$UJ" | grep -cF 'if (busy || waitingFiles) return;')" = 2 ] \
  && [ "$(echo "$UJ" | sed -n '/async function addPicked/,/^  }$/p' | grep -n 'consent.checked = false' | cut -d: -f1)" -lt "$(echo "$UJ" | sed -n '/async function addPicked/,/^  }$/p' | grep -n 'for (const file of picked)' | cut -d: -f1)" ] \
  && ok "both SEND buttons wait for photos still being prepared, and picking files unticks consent before they are prepared" || bad "upload.js SEND while preparing" ""
[ "$(echo "$UJ" | grep -c 'retrying_1:')" = 2 ] && [ "$(echo "$AJS" | grep -c 'retrying_1:')" = 2 ] \
  && echo "$UJ" | grep -qF 'retrying_1: "Connection problem. Trying again in 1 second…",' && echo "$UJ" | grep -qF 'retrying_1: "Koneksi bermasalah. Mencoba lagi dalam 1 detik…",' \
  && echo "$AJS" | grep -qF 'retrying_1: "Connection problem. Trying again in 1 second…",' && echo "$AJS" | grep -qF 'retrying_1: "Koneksi bermasalah. Mencoba lagi dalam 1 detik…",' \
  && echo "$UJ" | grep -qF 'status(s === 1 ? "retrying_1" : "retrying", { s })' && echo "$AJS" | grep -qF 'status(s === 1 ? "retrying_1" : "retrying", { s })' \
  && ok "the retry countdown says 1 second, not 1 seconds (EN and ID, both pages)" || bad "retry countdown wording" ""
# The wait for files, run in node with upload.js's own refuse and filesReady and stubs around them: a SEND waits only
# for its own form's picks and shows the wait text meanwhile; it gets back the fields that refused a file since the pick
# started (also a refusal just before the tap), never one of the other form; waitingFiles is cleared after; a pick that
# never ends is waited for once, up to the cap of a minute on screen, and then not again; a pick of many clips that gets
# one more ready every 40 seconds on screen is waited for to its end, past the minute (prepared).
WF=$(echo "$UJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", async () => {
  let waitingFiles = false, statusKey = null, fake = null, onNow = null;
  const working = new Map(), stale = new Set(), notes = {};
  const fieldMsg = (kind, key) => { notes[kind] = key || ""; };
  const $ = (sel) => ({ textContent: notes[(sel.match(/data-msg="([^"]+)"/) || [])[1]] || "" });
  const status = (k) => { statusKey = k || null; };
  const sleep = (ms) => (fake !== null ? Promise.resolve() : new Promise((r) => setTimeout(r, ms)));
  const performance = { now: () => { if (fake === null) return Date.now(); fake += 1000; if (onNow) onNow(fake); return fake; } };
  global.document = { visibilityState: "visible" };
  const a = s.indexOf("const formOfKind"), b = s.lastIndexOf("\n", s.indexOf("forEach((input) => input.addEventListener(\"change\"", a));
  const c = s.indexOf("async function filesReady"), d = s.indexOf("// Files were refused while SEND waited");
  eval(s.slice(a, b) + "\n" + s.slice(c, d) + "\nglobalThis.refusedOf = (g) => refusedKinds[g].length; globalThis.bump = (g) => { prepared[g]++; };");
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const pick = (g, fn) => { const seen = refusedOf(g); const job = fn(); working.set(job, { g, seen }); const forget = () => { working.delete(job); stale.delete(job); }; job.then(forget, forget); };
  const bad = [];
  pick("cleanup", () => wait(50)); pick("mission", () => wait(1500));
  let t = Date.now();
  const p1 = filesReady("cleanup"); const shown = waitingFiles && statusKey === "preparing_files";
  const r1 = await p1;
  if (r1.length || Date.now() - t > 900 || !shown || waitingFiles || statusKey !== null) bad.push("own form only");
  pick("cleanup", async () => { await wait(30); refuse("before", "e_decode"); await wait(30); });
  const r2 = await filesReady("cleanup");
  if (r2.join() !== "before") bad.push("refusal during the wait: " + r2.join());
  pick("cleanup", async () => { refuse("after", "e_photo_big"); await wait(80); });
  await wait(20);
  const r3 = await filesReady("cleanup");
  if (r3.join() !== "after") bad.push("refusal before the tap: " + r3.join());
  pick("mission", async () => { await wait(20); refuse("now", "e_decode"); });
  pick("cleanup", () => wait(60));
  const r4 = await filesReady("cleanup");
  if (r4.length) bad.push("the other form counted: " + r4.join());
  pick("cleanup", async () => { refuse("video_before", "e_video_long"); await wait(80); });
  fieldMsg("video_before");
  const r7 = await filesReady("cleanup");
  if (r7.length) bad.push("a refusal fixed by a new pick still counted: " + r7.join());
  await wait(1600);
  fake = 0;
  pick("cleanup", () => new Promise(() => {}));
  const r5 = await filesReady("cleanup");
  const steps = fake / 2000, f5 = fake;
  const r6 = await filesReady("cleanup");
  if (r5.length || r6.length || waitingFiles || stale.size !== 1 || steps !== 60 || fake !== f5) bad.push("a pick that never ends: " + steps + " steps, then " + (fake - f5) / 2000);
  // 30 clips, one ready every 40 s on screen (each step of the wait is a second on screen): 20 minutes, never stale.
  let finish = null, made = 0;
  fake = 0;
  onNow = (v) => { if (v % 80000 === 0 && made < 30) { made++; bump("cleanup"); if (made === 30) finish(); } };
  pick("cleanup", () => new Promise((r) => { finish = r; }));
  const r8 = await filesReady("cleanup");
  onNow = null;
  if (r8.length || waitingFiles || made !== 30 || stale.size !== 1 || fake < 30 * 80000) bad.push("a pick of 30 slow clips: " + made + " made, " + stale.size + " stale, " + fake / 2000 + " steps");
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
  process.exit(0);
});' 2>&1)
[ "$WF" = ok ] && ok "SEND waits for its own form only, gets the fields that refused a file since the pick (also before the tap, not once fixed), clears waitingFiles, waits once, a minute, for a pick that never ends, and to its end for 30 clips that get ready one by one (upload.js run in node)" \
  || bad "upload.js wait for files (node)" "$WF"
# The IndexedDB wrapper, run in node with a fake indexedDB: when Safari closed the connection (transaction() throws,
# or a close event), the next write or delete opens it again, so removed and sent files still leave the phone.
IDBR=$(echo "$UJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", async () => {
  const tokenTag = "test1234", store = new Map();
  let opens = 0, throwNext = 0, db = null;
  const makeDb = () => ({
    onclose: null,
    transaction() {
      if (throwNext > 0) { throwNext--; const e = new Error("The database connection is closing."); e.name = "InvalidStateError"; throw e; }
      const tx = { oncomplete: null, onerror: null, onabort: null };
      tx.objectStore = () => ({ put: (v) => { store.set(v.id, v); return {}; }, delete: (id) => { store.delete(id); return {}; }, getAll: () => ({ result: [...store.values()] }) });
      setTimeout(() => tx.oncomplete && tx.oncomplete());
      return tx;
    },
  });
  global.indexedDB = { open: () => { opens++; const r = {}; setTimeout(() => { r.result = db = makeDb(); r.onsuccess(); }); return r; } };
  const a = s.indexOf("const idb = (() => {"), b = s.indexOf("})();", a) + 5;
  eval(s.slice(a, b) + "\nglobalThis.idbT = idb;");
  const bad = [];
  await idbT.put({ id: 1, kind: "before", type: "image/jpeg", blob: "x", key: null });
  if (!store.has(1) || opens !== 1) bad.push("first write");
  throwNext = 1;
  await idbT.del(1);
  if (store.has(1) || opens !== 2) bad.push("delete after a closing connection");
  if (typeof db.onclose === "function") db.onclose(); else bad.push("no close handler");
  await idbT.put({ id: 2, kind: "after", type: "image/jpeg", blob: "y", key: null });
  if (!store.has(2) || opens !== 3) bad.push("write after a close event");
  if ((await idbT.all()).length !== 1) bad.push("read back");
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
  process.exit(0);
});' 2>&1)
[ "$IDBR" = ok ] && ok "after Safari closed the IndexedDB connection, the next write or delete opens it again (upload.js idb run in node)" \
  || bad "upload.js IndexedDB reopen (node)" "$IDBR"
# Its wiring in the page: the handlers point at the refused fields; no screen change while a send runs or waits (the
# back button pushes the form's entry again); a pick
# made before its form was sent adds nothing after it; photos kept in a draft from before cleanJpeg are cleaned right
# before they go up (one the phone can no longer read gets the remove-the-orange-file message); a photo removed while
# it was being prepared stays removed; refusals go through refuse(); the IndexedDB connection reopens after Safari
# closed it.
ADDF=$(echo "$UJ" | sed -n -e '/async function addPhoto/,/^  }$/p' -e '/async function addVideo/,/^  }$/p')
[ "$(echo "$UJ" | grep -cF 'if (refusedNow.length) { showRefused(')" = 2 ] \
  && [ "$(echo "$UJ" | grep -A1 -E '^    clearMarks\((form|mform)\);' | grep -c 'await filesReady(')" = 2 ] \
  && echo "$UJ" | grep -qF 'if (sendLocked()) return false;' && echo "$UJ" | grep -qF 'if (sendLocked()) { history.pushState(lastState, ""); return; }' \
  && echo "$UJ" | grep -qF 'working.set(job, { g, seen });' && echo "$UJ" | grep -qF 'const forget = () => { working.delete(job); stale.delete(job); };' \
  && echo "$UJ" | grep -qF 'const seen = refusedKinds[g].length;' && echo "$UJ" | grep -qF 'const gen = sends[g];' \
  && [ "$(echo "$ADDF" | grep -cF 'if (sends[g] !== gen) return;')" = 2 ] \
  && echo "$UJ" | grep -qF 'sends.cleanup++;' && echo "$UJ" | grep -qF 'sends.mission++;' && echo "$UJ" | grep -qF 'if (sends[g] !== gen) break;' \
  && echo "$UJ" | grep -qF 'item.blob = await cleanJpeg(item.blob).catch(() => { throw new Fatal("e_upload_fatal"); });' \
  && [ "$(echo "$ADDF" | grep -cF 'if (!files[kind].includes(item) || sends[g] !== gen) return;')" = 2 ] && [ "$(echo "$ADDF" | grep -cF 'const g = formOfKind(kind);')" = 2 ] \
  && [ "$(echo "$ADDF" | grep -o 'refuse(' | wc -l | tr -d ' ')" = 11 ] && ! echo "$ADDF" | grep -q 'fieldMsg(' \
  && echo "$UJ" | grep -qF 'r.result.onclose = () => { dbp = null; };' \
  && echo "$UJ" | grep -qF 'if (document.visibilityState === "visible") left -= Math.min(performance.now() - t0, 1000);' \
  && [ "$(echo "$UJ" | grep -c 'preparing_files:')" = 2 ] && grep -qF '.thumbs.invalid {' site/forms.css \
  && ok "the wait is wired in: refused fields marked, screens locked, late picks dropped, old draft photos cleaned, removed photos stay removed, IndexedDB reopens" \
  || bad "upload.js wait for files wiring" ""
curl -s $B/admin/admin.js | grep -qF 'revision: m.revision, video: video ? m.now_video.key : null,' \
  && ok "admin.js sends the revision with PUBLISH and FUND, and the video the card plays" || bad "admin.js revision" ""
# Videos: SEND A CLEANUP has a field for the videos before and one for the videos after, up to 30 clips each and several
# picked at once (multiple), POST A MISSION one for the video of the spot now, one clip; the cleanup's go up with their
# stage, the mission's as a plain video.
UPC=$(echo "$UP" | sed -n '/<form id="form"/,/<\/form>/p'); UPM=$(echo "$UP" | sed -n '/<form id="mform"/,/<\/form>/p')
n=0; for k in video_before video_after now_video now_video_hint; do [ "$(echo "$UJ" | grep -cE "^      $k: \"")" = 2 ] && n=$((n+1)); done
echo "$UPC" | grep -qF 'data-kind="video_before"' && echo "$UPC" | grep -qF 'data-kind="video_after"' && echo "$UPM" | grep -qF 'data-kind="now_video"' \
  && ! echo "$UP" | grep -qF 'data-kind="video"' && [ "$n" = 4 ] && ! echo "$UJ" | grep -qE '^      videos: "' \
  && echo "$UJ" | grep -qF 'const UPLOAD_AS = { now: ["before"], now_video: ["video"], video_before: ["video", "before"], video_after: ["video", "after"] };' \
  && echo "$UJ" | grep -qF '&kind=${kind}${stage ? `&stage=${stage}` : ""}' \
  && echo "$UJ" | grep -qF 'const formOfKind = (kind) => (kind === "now" || kind === "now_video" ? "mission" : "cleanup");' \
  && echo "$UJ" | grep -qF 'const LIMIT = { photos: 4, videos: 30, missionVideos: 1,' && echo "$UJ" | grep -qF 'const VIDEO_KINDS = ["video_before", "video_after", "now_video"];' \
  && echo "$UJ" | grep -qF 'const maxOf = (kind) => (kind === "now_video" ? LIMIT.missionVideos : VIDEO_KINDS.includes(kind) ? LIMIT.videos : LIMIT.photos);' \
  && echo "$UPC" | grep -qF 'multiple data-kind="video_before"' && echo "$UPC" | grep -qF 'multiple data-kind="video_after"' \
  && ! echo "$UPM" | grep -F 'data-kind="now_video"' | grep -q multiple && [ "$(echo "$UPC" | grep -cF '<span data-i18n="add_videos">+ Add videos</span>')" = 2 ] \
  && echo "$UPM" | grep -qF '<span data-i18n="add_video">+ Add video</span><input type="file" accept="video/mp4,video/quicktime,video/webm,video/*" data-kind="now_video"' \
  && ok "upload page: up to 30 videos before and 30 after the cleanup (several at once), 1 of the spot now for a mission (EN and ID), sent with their stage" \
  || bad "upload page video fields" "keys found in EN and ID: $n of 4"
# addVideo run in node with upload.js's own limits, refuse and maxOf, and stubs for the length, the location check and
# the page: 31 clips one by one into a cleanup field keep 30 and refuse the 31st ("At most 30 videos here."), two picks
# of 20 at once into the other keep 30 and refuse 10 (also those let through before the others were ready), the
# mission's field keeps 1 and refuses the 2nd with its own text, and a clip too long, of a type it does not take or too
# big is refused as before. The same clip (name, size and last change) picked again, in its own field or the other one,
# or twice at once, is refused ("This video is already added."), while the same name with another size or last change is
# another clip, and the mission's field is not compared with the cleanup's. The texts: EN and ID, the page's English as
# T.en's.
ADV=$(echo "$UJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", async () => {
  const cut = (from, to) => { const a = s.indexOf(from), b = s.indexOf(to, a); if (a < 0 || b < 0) throw new Error("missing " + from); return s.slice(a, b); };
  const files = { video_before: [], video_after: [], now_video: [] }, sends = { cleanup: 0, mission: 0 }, notes = [];
  let seq = 0;
  const fieldMsg = (kind, key) => { if (key) notes.push(kind + " " + key); };
  const showItem = () => {}, idb = { put() {} };
  const sleep = () => new Promise((r) => setTimeout(r, Math.random() * 5));
  const videoDuration = async (f) => { await sleep(); return f.dur; };
  global.window = { SapuVideoClean: { stripVideoLocation: async (f) => { await sleep(); return { ok: true, blob: f }; } } };
  const a = s.indexOf("  const formOfKind"), b = s.lastIndexOf("\n", s.indexOf("forEach((input) => input.addEventListener(\"change\"", a));
  eval(cut("  const VIDEO_EXT = ", "  const STALL_MS") + cut("  function videoType(", "\n  }\n") + "\n  }\n" + s.slice(a, b) + "\n" + cut("  async function addVideo(", "\n  }\n") + "\n  }\n"
    + "globalThis.X = { addVideo, maxOf, LIMIT };");
  const clip = (i, o = {}) => ({ name: "clip" + i + ".mp4", type: "video/mp4", size: 40 * 1048576, dur: 20, ...o });
  const pick = async (kind, list) => { for (const f of list) await X.addVideo(kind, f, 0); };
  const bad = [], count = (k) => notes.filter((n) => n === k).length;
  await pick("video_before", Array.from({ length: 31 }, (_, i) => clip(i)));
  if (files.video_before.length !== 30 || notes.join() !== "video_before e_max_videos") bad.push("31 into one field: " + files.video_before.length + " " + notes.join());
  notes.length = 0;
  await Promise.all([pick("video_after", Array.from({ length: 20 }, (_, i) => clip(100 + i))), pick("video_after", Array.from({ length: 20 }, (_, i) => clip(120 + i)))]);
  if (files.video_after.length !== 30 || count("video_after e_max_videos") !== 10 || notes.length !== 10) bad.push("two picks of 20: " + files.video_after.length + " " + notes.length);
  notes.length = 0;
  await pick("now_video", [clip(1), clip(2)]);
  if (files.now_video.length !== 1 || notes.join() !== "now_video e_max_videos_1") bad.push("the mission field: " + files.now_video.length + " " + notes.join());
  notes.length = 0; files.video_before.length = 0;
  await pick("video_before", [clip(1, { dur: 120 }), clip(2, { name: "x.avi", type: "video/x-msvideo" }), clip(3, { size: 96 * 1048576 }), clip(4)]);
  if (files.video_before.length !== 1 || notes.join() !== "video_before e_video_long,video_before e_video_type,video_before e_video_big") bad.push("one clip each refused: " + notes.join());
  if (X.maxOf("video_before") !== 30 || X.maxOf("video_after") !== 30 || X.maxOf("now_video") !== 1 || X.maxOf("before_2") !== 4 || X.maxOf("now") !== 4) bad.push("maxOf");
  notes.length = 0; files.video_after.length = 0; files.now_video.length = 0;
  await pick("video_before", [clip(4)]); await pick("video_after", [clip(4)]);
  await pick("video_after", [clip(4, { lastModified: 5 }), clip(4, { size: 41 * 1048576 })]);
  await Promise.all([pick("video_after", [clip(7)]), pick("video_before", [clip(7)])]);
  await pick("now_video", [clip(4)]);
  const sevens = [...files.video_before, ...files.video_after].filter((it) => it.sig === "clip7.mp4|41943040|undefined").length;
  if (files.video_before.length + files.video_after.length !== 4 || sevens !== 1 || files.now_video.length !== 1 || notes.length !== 3
    || notes.some((n) => !n.endsWith(" e_video_twice")) || files.video_before[0].sig !== "clip4.mp4|41943040|undefined") bad.push("the same clip twice: " + notes.join() + " " + files.video_after.length);
  const t0 = s.indexOf("  const T = {"), t1 = s.indexOf("\n  };", t0);
  const T = new Function("return (" + s.slice(t0 + "  const T = ".length, t1 + 4) + ");")();
  const want = { en: { e_max_videos: "At most 30 videos here.", e_max_videos_1: "Only one video here. Remove it first to choose another.", add_videos: "+ Add videos", e_video_twice: "This video is already added.",
    video_before: "Videos before the cleanup (optional)", video_after: "Videos after the cleanup (optional)",
    videos_hint: "Up to 30 videos before the cleanup and 30 after it. Short vertical clips of 15 to 30 seconds work best and send faster. Limit: 90 seconds and 95 MB each." },
    id: { e_max_videos: "Maksimal 30 video di sini.", e_max_videos_1: "Hanya bisa satu video di sini. Hapus dulu video yang sudah ada kalau mau memilih yang lain.", add_videos: "+ Tambah video", e_video_twice: "Video ini sudah ditambahkan." } };
  for (const l of ["en", "id"]) for (const [k, v] of Object.entries(want[l])) if (T[l][k] !== v) bad.push(l + " " + k + ": " + T[l][k]);
  if (!T.en.watch_video || !T.id.watch_video || !T.en.watch_video.includes("{n}") || !T.id.watch_video.includes("{n}")) bad.push("watch_video");
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + JSON.stringify([T.en.videos_hint, T.en.video_before, T.en.video_after]));
  process.exit(0);
});' 2>&1)
ADVP=$(printf '%s' "$UP" | python3 -c "
import re,sys,json
p=sys.stdin.read()
print('ok ' + json.dumps([re.search(r'data-i18n=\"videos_hint\">([^<]*)<', p).group(1), re.search(r'data-i18n=\"video_before\">([^<]*)<', p).group(1), re.search(r'data-i18n=\"video_after\">([^<]*)<', p).group(1)], separators=(',', ':')))" 2>&1)
[ "${ADV%% *}" = ok ] && [ "$ADV" = "$ADVP" ] \
  && ok "the video fields in node: 31 clips keep 30 and refuse 1, two picks of 20 at once keep 30, the mission's keeps 1 with its own text, too long, wrong type and too big refused, the same clip picked again (or twice at once) refused in either cleanup field; the texts in EN and ID, the page's English the same" \
  || bad "upload.js addVideo and its texts (node)" "$ADV | page: $ADVP"
# The clip list of the two cleanup video fields and the screen lock of a send, run in node with a stand-in page: a clip of
# a cleanup field is one line (vrow) with no player and no link to its file, "▶ 2 · 23 s · 41 MB" numbered in the
# field's order and again after a removal, read out as "Watch video 2, 23 s, 41 MB"; ▶ plays one clip at a time under
# its line, and closing it (▶ again, another ▶) lets go of the player and revokes its link; the mission's one clip keeps
# its picture. keepAwake asks for the screen lock once, lets it go at the end, also when the end comes before the lock,
# asks again when the page shows during a send after the browser let go, and goes on without the API or when refused.
CLP=$(echo "$UJ" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", async () => {
  const cut = (from, to) => { const a = s.indexOf(from), b = s.indexOf(to, a); if (a < 0 || b < 0) throw new Error("missing " + from); return s.slice(a, b); };
  const urls = new Set(), bad = [];
  const el = (tag) => ({ tag, attrs: {}, kids: [], classes: [], textContent: "", removed: false, src: "", next: null, loads: 0,
    classList: null, setAttribute(k, v) { this.attrs[k] = String(v); }, removeAttribute(k) { delete this.attrs[k]; if (k === "src") this.src = ""; },
    append(...k) { this.kids.push(...k); }, prepend(x) { this.kids.unshift(x); }, after(x) { this.next = x; }, remove() { this.removed = true; },
    querySelector(q) { return this.kids.find((k) => (q === ".vlabel" ? k.className === "vlabel" : k.tag === q)) || null; },
    addEventListener(t, f) { this["on" + t] = f; }, pause() {}, load() { this.loads++; } });
  const mk = (tag) => { const e = el(tag); e.classList = { add: (c) => e.classes.push(c) }; return e; };
  const document = { createElement: mk };
  const URL = { createObjectURL: () => { const u = "blob:" + Math.random(); urls.add(u); return u; }, revokeObjectURL: (u) => urls.delete(u) };
  const t = (k, v) => k + ":" + v.n, mb = (b) => String(Math.round(b / 1048576));
  const files = { video_before: [], now_video: [] };
  const X = new Function("document", "URL", "t", "mb", "files", cut("  const VIDEO_KINDS = ", "  const STALL_MS")
    + cut("  // A clip of the cleanup\x27s video fields is one line", "  function renderThumb(") + "\nreturn { addPreview, rowLabels, togglePeek, closePeek };")(document, URL, t, mb, files);
  const item = (i, kind, dur, size) => { const it = { id: i, kind, blob: { size }, dur, el: mk("div") }; files[kind].push(it); return it; };
  const a = item(1, "video_before", 23.4, 41 * 1048576), b = item(2, "video_before", null, 5 * 1048576), c = item(3, "video_before", 90, 95 * 1048576);
  [a, b, c].forEach((it) => X.addPreview(it));
  const lab = (it) => it.el.kids[0];
  if ([a, b, c].some((it) => it.url || it.el.kids.length !== 1 || it.el.kids[0].tag !== "button" || !it.el.classes.includes("vrow")) || urls.size) bad.push("a clip line has a player or a link");
  if ([a, b, c].map((it) => lab(it).textContent).join(" | ") !== "▶ 1 · 23 s · 41 MB | ▶ 2 · 5 MB | ▶ 3 · 90 s · 95 MB") bad.push("the lines: " + [a, b, c].map((it) => lab(it).textContent).join(" | "));
  if (lab(a).attrs["aria-label"] !== "watch_video:1, 23 s, 41 MB" || lab(a).attrs["aria-expanded"] !== "false") bad.push("the name: " + JSON.stringify(lab(a).attrs));
  files.video_before.shift(); X.rowLabels("video_before");
  if (lab(b).textContent !== "▶ 1 · 5 MB" || lab(c).textContent !== "▶ 2 · 90 s · 95 MB") bad.push("numbered again: " + lab(b).textContent);
  lab(b).onclick();
  const pb = b.el.next, vb = pb && pb.kids[0];
  if (!vb || vb.tag !== "video" || !vb.controls || !vb.playsInline || !urls.has(vb.src) || lab(b).attrs["aria-expanded"] !== "true") bad.push("▶ plays the clip under its line");
  const ub = vb && vb.src;
  lab(c).onclick();
  const vc = c.el.next && c.el.next.kids[0];
  if (!pb.removed || urls.has(ub) || vb.src || !vb.loads || lab(b).attrs["aria-expanded"] !== "false" || !vc || urls.size !== 1) bad.push("another ▶ closes the first");
  lab(c).onclick();
  if (!c.el.next.removed || urls.size || lab(c).attrs["aria-expanded"] !== "false") bad.push("▶ again closes it");
  const n = item(4, "now_video", 12, 1048576); X.addPreview(n);
  if (!n.url || n.el.kids[0].tag !== "video" || n.el.classes.includes("vrow")) bad.push("the mission clip keeps its picture");
  // keepAwake
  const on = { visibilitychange: [] }, doc = { visibilityState: "visible", addEventListener: (k, f) => on[k].push(f) };
  let asked = 0, freed = 0, hold = null, refuse = false;
  const lock = () => ({ ls: [], addEventListener(k, f) { this.ls.push(f); }, release() { freed++; this.ls.forEach((f) => f()); return Promise.resolve(); } });
  const nav = { wakeLock: { request: (type) => { asked++; if (type !== "screen") bad.push("type " + type); if (refuse) return Promise.reject(new Error("no")); return new Promise((r) => { hold = () => r(lock()); }); } } };
  const W = new Function("navigator", "document", cut("  let wake = null, awake = false, asking = false;", "  // Uploads the form\x27s files that are not on the server yet") + "\nreturn { keepAwake, now: () => wake };")(nav, doc);
  const tick = () => new Promise((r) => setTimeout(r, 0));
  W.keepAwake(true); W.keepAwake(true); hold(); await tick();
  if (asked !== 1 || !W.now()) bad.push("one lock: " + asked);
  const l1 = W.now(); l1.release(); await tick();
  if (W.now() !== null) bad.push("the browser let go");
  doc.visibilityState = "hidden"; on.visibilitychange.forEach((f) => f());
  doc.visibilityState = "visible"; on.visibilitychange.forEach((f) => f()); hold(); await tick();
  if (asked !== 2 || !W.now()) bad.push("asked again when the page shows: " + asked);
  W.keepAwake(false); await tick();
  if (W.now() !== null || freed !== 2) bad.push("let go at the end: " + freed);
  on.visibilitychange.forEach((f) => f());
  if (asked !== 2) bad.push("asked after the end");
  W.keepAwake(true); W.keepAwake(false); hold(); await tick();
  if (W.now() !== null || freed !== 3) bad.push("the end before the lock: " + freed);
  refuse = true; W.keepAwake(true); await tick(); W.keepAwake(false);
  const N = new Function("navigator", "document", cut("  let wake = null, awake = false, asking = false;", "  // Uploads the form\x27s files that are not on the server yet") + "\nreturn { keepAwake };")({}, doc);
  N.keepAwake(true); N.keepAwake(false);
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
  process.exit(0);
});' 2>&1)
RSND=$(echo "$UJ" | sed -n '/^  async function runSend(g, post) {/,/^  }$/p')
[ "$CLP" = ok ] && [ "$(echo "$RSND" | grep -A1 -F '    lockForms(true);' | tail -1)" = '    keepAwake(true);' ] && [ "$(echo "$RSND" | grep -A1 -F '      lockForms(false);' | tail -1)" = '      keepAwake(false);' ] \
  && echo "$UJ" | grep -qF 'if (peek && peek.item === item) closePeek();' && echo "$UJ" | grep -qF 'if (LIST_KINDS.includes(k)) rowLabels(k);' \
  && [ "$(echo "$UP" | grep -cF '<div class="thumbs vlist" data-list="video_')" = 2 ] && grep -qF '.thumbs.vlist { grid-template-columns: 1fr; gap: 6px; }' site/forms.css \
  && ok "the cleanup's clip lists: one numbered line per clip with no player, read out with its number, length and size, one clip played at a time and let go when closed or removed, the mission's clip as a picture; a send keeps the screen on and lets it go (node)" \
  || bad "upload.js clip list and screen lock (node)" "$CLP"
# With 30 clips in a field its note, its marks and its player stay where the crew is: each video field's note stands
# above its list (under + Add videos, or the field's label once + Add videos hides), so it is in view after a big pick; a
# field taller than the screen is shown from its top when SEND waited and a clip was refused (its label and note in
# view), not centred; a file the server refuses, or a video that would not go up, is scrolled into view (centred) with
# the message above SEND, since it can be thousands of pixels above it; the clip ▶ plays stops when the cleanup form
# goes (render: the crew page, POST A MISSION, THANK YOU); a language switch writes the clip lines again (applyLang); and
# a clip's name, size and last change are kept with it on the phone, so one that came back after a reload is still
# known when it is picked again.
RSND2=$(echo "$UJ" | sed -n '/^  async function runSend(g, post) {/,/^  }$/p')
REND=$(echo "$UJ" | sed -n '/^  function render() {/,/^  }$/p'); APLG=$(echo "$UJ" | sed -n '/^  function applyLang() {/,/^  }$/p')
[ "$(echo "$UP" | grep -A1 -F '<div class="msg err" data-msg="video_' | grep -cF '<div class="thumbs vlist" data-list="video_')" = 2 ] \
  && [ "$(echo "$UP" | grep -A1 -F '<div class="thumbs vlist" data-list="video_' | grep -cF 'data-msg=')" = 0 ] \
  && echo "$UJ" | grep -qF 'if (fields[0]) fields[0].scrollIntoView({ behavior: "smooth", block: fields[0].offsetHeight > innerHeight ? "start" : "center" });' \
  && echo "$RSND2" | grep -qF 'const marked = e instanceof Fatal && (e.msgKey === "e_upload_fatal" || e.msgKey === "e_upload_video") && all.find((x) => x.el && x.el.classList.contains("failed"));' \
  && [ "$(echo "$RSND2" | grep -B1 -F '      return null;' | head -1)" = '      if (marked) marked.el.scrollIntoView({ behavior: "smooth", block: "center" });' ] \
  && echo "$UJ" | grep -qF 'item.el && item.el.classList.remove("failed");' \
  && echo "$REND" | grep -qxF '    if (form.hidden) closePeek();' && echo "$APLG" | grep -qxF '    LIST_KINDS.forEach(rowLabels); // the clip lines: "Watch video 2", and the size as this language writes it (0,4 MB)' \
  && echo "$UJ" | grep -qF ', dur: it.dur || null, sig: it.sig || null,' && echo "$UJ" | grep -qF ', progress: r.key ? 1 : 0, sig: r.sig || null };' \
  && ok "the crew page with 30 clips a field: each video field's note above its list, a tall field shown from its top after SEND's wait, a refused or failed file scrolled into view, the clip being watched stopped when the form goes, the lines rewritten on a language switch, a clip's signature kept on the phone" \
  || bad "upload.js notes and marks with long clip lists" ""
# On a phone the hint above "+ Add video" sat 1.5 to 4 px from the dashed border. A hint right before a picker now gets
# the same 6px as a field's label (.field > span), so its text sits 7.5 to 10 px above the box, as a label's does (8 to
# 9.5 px, measured in Chrome at 412 and 375 px, EN and ID). Only the two video hints sit right before a picker: the photo
# fields, the other hints and /apply/ (the same forms.css) do not move.
FCS=$(curl -s $B/site/forms.css)
echo "$FCS" | grep -qF '.field > .hint + .drop { margin-top: 6px; }' && echo "$FCS" | grep -qF 'text-transform: uppercase; margin-bottom: 6px;' \
  && [ "$(echo "$UP" | grep -B1 -F '<label class="drop">' | grep -cE '^ *<p class="hint" data-i18n="(videos_hint|now_video_hint)">')" = 2 ] \
  && [ "$(echo "$UP" | grep -B1 -F '<label class="drop">' | grep -c 'class="hint"')" = 2 ] \
  && [ "$(echo "$UP" | grep -B1 -F '<label class="drop">' | grep -cE '^ *<span')" = 4 ] \
  && ! curl -s $B/apply/ | grep -B1 -F '<label class="drop">' | grep -q 'class="hint"' \
  && ok "the hint above a video picker keeps the clear space of the photo fields' labels, and only the two video hints get it (not /apply/)" \
  || bad "hint spacing above the video pickers" ""
[ "$(echo "$UJ" | grep -cF 'Everyone in these photos and videos agreed')" = 2 ] && [ "$(echo "$UP" | grep -cF 'Everyone in these photos and videos agreed')" = 2 ] \
  && [ "$(echo "$UJ" | grep -cF 'di foto dan video ini')" = 2 ] && [ "$(echo "$UJ" | grep -cF 'How we handle your photos, videos and details')" = 1 ] \
  && [ "$(echo "$UP" | grep -cF 'How we handle your photos, videos and details')" = 3 ] \
  && echo "$UJ" | grep -qF 'withdraw_q: "Withdraw mission #{no}? It is removed and its photos and any video are deleted.",' \
  && echo "$UJ" | grep -qF 'withdraw_q: "Batalkan misi #{no}? Misi ini akan dihapus beserta fotonya, dan juga videonya kalau ada.",' \
  && [ "$(echo "$UJ" | grep -cF 'its photos and video, your message and its exact location are deleted.')" = 1 ] \
  && ok "both consent boxes, the notice and the withdraw question cover videos (EN and ID, page and script)" || bad "upload page video wording" ""
# A video that will not go up says it can be removed (videos are optional), a big video gets time on slow data, a
# clip the page cannot check for location data is refused, the SAFETY FIRST line keeps children out of the videos
# too, and each file picker is read out with its field's name (EN and ID).
n=0; for k in e_upload_video e_video_check; do [ "$(echo "$UJ" | grep -cE "^      $k: \"")" = 2 ] && n=$((n+1)); done
echo "$UJ" | grep -qF 'throw e instanceof Fatal ? e : new Fatal(VIDEO_KINDS.includes(item.kind) ? "e_upload_video" : "e_upload");' \
  && echo "$UJ" | grep -qF 'xhr.timeout = Math.max(30 * 60 * 1000, Math.round(item.blob.size / 25));' \
  && echo "$UJ" | grep -qF ': window.SapuVideoClean ? await window.SapuVideoClean.stripVideoLocation(file) : { ok: false };' \
  && echo "$UJ" | grep -qF 'if (clean.ok === false) { refuse(kind, "e_video_check"); return; }' && [ "$n" = 2 ] \
  && echo "$UJ" | grep -qF 'Children stay away from the water and out of the photos and videos.",' \
  && echo "$UJ" | grep -qF 'Anak-anak tidak boleh dekat air dan tidak boleh ada di foto atau video.",' \
  && echo "$UP" | grep -qF 'Children stay away from the water and out of the photos and videos.</li>' \
  && [ "$(echo "$UP" | grep -cE '<input type="file"[^>]* data-i18n-aria="(before|after|video_before|video_after|now|now_video)" aria-label="')" = 6 ] \
  && ok "upload page: a failed video says it can be removed, a big video gets time, a clip that cannot be checked for location is refused, children out of photos and videos, each picker named (EN and ID)" \
  || bad "upload page video failures, safety line and picker names" "keys found in EN and ID: $n of 2"
# upload/videoclean.js run in node: an MP4 without a location goes as it is, Android's location box (©xyz) is
# wiped in place, and a clip it cannot read says ok: false, so the page refuses it instead of sending it as it is.
VCL=$(curl -s $B/upload/videoclean.js | node -e '
new Function("window", "module", require("fs").readFileSync(0, "utf8"))(undefined, undefined);
const { stripVideoLocation } = globalThis.SapuVideoClean;
const box = (type, body) => { const b = Buffer.alloc(8 + body.length); b.writeUInt32BE(8 + body.length, 0); b.write(type, 4, "latin1"); body.copy(b, 8); return b; };
const gps = Buffer.from("\0\x12\x15\xc7+47.2692+011.4041/", "latin1");
const clip = Buffer.concat([box("ftyp", Buffer.from("isom\0\0\0\0", "latin1")), box("moov", box("udta", box("\xa9xyz", gps)))]);
(async () => {
  const bad = [];
  const plain = await stripVideoLocation(new Blob([require("fs").readFileSync(process.argv[1])], { type: "video/mp4" }));
  if (plain.ok !== true || plain.cleaned !== 0) bad.push("clip without a location: " + JSON.stringify([plain.ok, plain.cleaned]));
  const geo = await stripVideoLocation(new Blob([clip], { type: "video/mp4" }));
  const out = Buffer.from(await geo.blob.arrayBuffer()).toString("latin1");
  if (geo.ok !== true || geo.cleaned !== 1 || out.includes("+47.2692") || !out.includes("free") || out.length !== clip.length) bad.push("clip with a location: " + JSON.stringify([geo.ok, geo.cleaned]));
  const none = await stripVideoLocation(new Blob([new Uint8Array(64)], { type: "video/mp4" }));
  if (none.ok !== false || none.blob.size !== 64) bad.push("clip it cannot read: " + none.ok);
  console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
})();' "$F/tiny.mp4" 2>&1)
[ "$VCL" = ok ] && ok "videoclean.js: a clip without a location goes as it is, Android's location is wiped, a clip it cannot read is not ok (node)" \
  || bad "upload/videoclean.js (node)" "$VCL"
AJ=$(curl -s $B/admin/admin.js)
echo "$AJ" | grep -qF '"VIDEO BEFORE"' && echo "$AJ" | grep -qF '"VIDEO AFTER"' \
  && echo "$AJ" | grep -qF 'titled(`VIDEO NOW, #${missionNo(mis)}`, mis.now_video.url)' \
  && echo "$AJ" | grep -qF '<h4>VIDEO NOW, #${esc(missionNo(m))}</h4>${player(video)}' \
  && echo "$AJ" | grep -qF '<div class="media-v"><h4>VIDEO</h4>${player(video)}</div>' \
  && echo "$AJ" | grep -qF 'const nowWhat = (m) => (m && m.now_video ? "photos and video" : "photos");' \
  && echo "$AJ" | grep -qF 'so we will delete it, with its photos and video.' && echo "$AJ" | grep -qF 'jadi misi ini beserta foto dan videonya akan kami hapus.' \
  && [ "$(echo "$AJ" | grep -c 'preload=')" = 1 ] \
  && ok "/admin/: VIDEO BEFORE, VIDEO AFTER and the mission's VIDEO NOW in PENDING and APPROVED, the video on the mission card and under Link to mission, and the questions and the decline message say photos and video" \
  || bad "admin.js videos" ""
# PENDING's and APPROVED's media block (admin.js mediaBlock) in node with its own helpers: the mission's VIDEO NOW, #12
# first, then every video under its own title, numbered within its stage in the server's order (videoRows); more than
# two side by side (.media-vgrid in admin.css), one or two at the card's width as before.
MBK=$(node -e '
const src = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
eval([/^  const ESC = .*$/m, /^  const esc = .*$/m, /^  const safeMedia = .*$/m, /^  const missionNo = .*$/m, /^  const spotsOf = .*$/m, /^  const player = .*$/m].map(line).join("\n")
  + "\n" + fn("videoRows") + fn("mediaBlock") + "globalThis.mediaBlock = mediaBlock;");
const sig = (c) => `/media/${c.repeat(32)}?exp=1999999999&sig=${"0".repeat(64)}`;
const v = (c, stage) => ({ url: sig(c), stage });
const s = (videos) => ({ media: { before: [{ url: sig("a") }], after: [{ url: sig("b") }], videos } });
const heads = (h) => [...h.matchAll(/<h4>([^<]*)<\/h4>/g)].map((m) => m[1]).filter((t) => t.startsWith("VIDEO"));
const many = mediaBlock(s([v("1", "before"), v("2", "before"), v("3", "before"), v("4", "after"), v("5", null), v("6", null)]), { no: 12, now: [], now_video: { url: sig("7") } });
const two = mediaBlock(s([v("1", "before"), v("4", "after")]), null);
console.log(JSON.stringify([heads(many).join(" | "), (many.match(/<div class="media-v media-vgrid">/g) || []).length, (many.match(/<video /g) || []).length,
  (two.match(/<div class="media-v">/g) || []).length, heads(two).join(" | ")]));
' "$T/admin.js" 2>&1)
check "PENDING and APPROVED (admin.js mediaBlock, node): VIDEO NOW, #12 first, then each video titled and numbered within its stage, more than two side by side, two at the card's width" "$MBK" \
  '["VIDEO NOW, #12 | VIDEO BEFORE 1/3 | VIDEO BEFORE 2/3 | VIDEO BEFORE 3/3 | VIDEO AFTER | VIDEO 1/2 | VIDEO 2/2",1,7,1,"VIDEO BEFORE | VIDEO AFTER"]'
grep -qF '.media-vgrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 0 10px; }' admin/admin.css \
  && ok "admin.css stands more than two of a cleanup's videos side by side" || bad "admin.css .media-vgrid" ""
echo "$SJ" | grep -qF 'e.media?.video_stages' && echo "$SJ" | grep -qF '"BEFORE · VIDEO"' && echo "$SJ" | grep -qF '"AFTER · VIDEO"' \
  && echo "$SJ" | grep -qF '"NOW · VIDEO"' && echo "$SJ" | grep -qF 'const nowVideoOf = (m) => safeSrc(m?.now_video);' \
  && echo "$SJ" | grep -qF '${nowVideoOf(m) ? '"'"'<div class="vid-tag">▶ VIDEO</div>'"'"' : ""}' \
  && echo "$SJ" | grep -qF '<div class="pm pm-video"${hid ? " hidden" : ""}><span class="tag">${escapeHTML(tag)}</span><video controls' \
  && echo "$SC" | grep -qF '.post-media .pm-video .tag { position: static; display: inline-block; margin: 8px 10px 6px; }' && echo "$SC" | grep -qF '.mcard .vid-tag { top: 70px; }' \
  && echo "$SC" | grep -qxF '.post-media .pm-video video { width: 100%; height: 520px; display: block; background: #000; }' && ! echo "$SC" | grep -qF 'max-height: 520px' \
  && echo "$SJ" | grep -qxF '    const videos = foldVideos(videosIn(e)).map((v) => (v.more ? `<div class="pm pm-more"><button type="button" class="post-link pm-show">${escapeHTML(v.more)}</button></div>` : videoBox(v.src, v.tag, true, v.hid))).join("");' \
  && ! echo "$SJ" | grep -qF 'v.tag === "' && [ "$(echo "$SJ" | grep -cF 'videosIn(e)')" = 2 ] \
  && ok "homepage: receipt videos tagged BEFORE · VIDEO and AFTER · VIDEO above the player (never on its controls), numbered when a stage has several (videosIn, in both posts, never placed by their tag; a long stage folded on a phone, foldVideos), each player 520 px tall whatever its clip (no jump when a lazy one loads, WebKit has no scroll anchoring), a mission's video in its post (NOW · VIDEO) and a ▶ VIDEO badge on its NEXT UP card" \
  || bad "site/app.js videos" ""
# A mission's video always goes with its photos: the delete, the sweep of leftovers and the expiry never filter on kind.
KG=$(sed -n -e '/^async function dropPhotos/,/^}$/p' -e '/^export async function sweepRemovedPhotos/,/^}$/p' -e '/^export async function expireMissions/,/^}$/p' functions/_lib/missions.js)
[ "$(echo "$KG" | grep -c '^}$')" = 3 ] && echo "$KG" | grep -qF 'DELETE FROM uploads WHERE submission_id IS NULL AND mission_id IN' \
  && ! echo "$KG" | grep -qiE "(^|[^a-z_.])kind[[:space:]]*(=|<>|!=|in[[:space:](])" \
  && ok "every mission removal deletes all its files: dropPhotos, sweepRemovedPhotos and expireMissions never filter on kind" \
  || bad "mission file delete guard" "$(echo "$KG" | grep -inE 'kind')"
# Two resends of a mission at the same moment cannot both leave their files on it: the field UPDATE and the drop only
# apply while the mission holds no file but the old and the new set (update() in functions/api/mission/index.js).
MU=$(sed -n '/^async function update(/,/^}$/p' functions/api/mission/index.js)
[ "$(echo "$MU" | grep -cF 'AND ${allOn} AND ${only}`')" = 2 ] && [ "$(echo "$MU" | grep -cF 'prev.id, ...f.keys, prev.id, ...known));')" = 2 ] \
  && echo "$MU" | grep -qF 'const only = `NOT EXISTS (SELECT 1 FROM uploads WHERE mission_id = ? AND key NOT IN (${marksFor(known)}))`;' \
  && ok "a mission resend only goes in while the mission holds no file but the old and the new set (field UPDATE and drop)" \
  || bad "mission resend guard" ""
# The crew page (docs/upload-flow.md, On the pages): one address, three screens. SAVE THIS LINK and its "How to save
# this link" only on the crew page; the notice outside it, so it also shows without a valid link.
UPH=$(echo "$UP" | sed -n '/<section id="home"/,/<!-- \/home -->/p')
echo "$UPH" | grep -q 'id="saveLink"' && echo "$UPH" | grep -q 'id="saveAgain"' && ! echo "$UPH" | grep -q 'id="privacy"' \
  && ok "SAVE THIS LINK and How to save this link sit on the crew page (#home), the privacy notice outside it" || bad "crew page: save link, notice" ""
echo "$UP" | grep -qF '<h1 class="fp-title" tabindex="-1"><mark data-i18n="title">YOUR CREW PAGE</mark></h1>' \
  && echo "$UP" | grep -qF '<title>Crew page · Sapu Earth</title>' \
  && ok "the H1 says YOUR CREW PAGE and takes focus on every screen change, the tab says Crew page" || bad "crew page H1 and title" ""
# Every field the server reads is in its form, or worked out from it: the money totals (price_local and crew_local, a
# cleanup's total_cost_local and crew_pay_local) are added up by the page from the pay for each person and the other
# costs (moneySum), so no form has a field with those names and an old draft's typed total never comes back.
n=0; for f in cleanup_date place_name country kg sacks crew_size hours disposal currency currency_other crew_each_local other_local notes post_url private_note consent mission_id; do
  echo "$UPC" | grep -q "name=\"$f\"" && n=$((n+1)); done
k=0; for f in place_name country task plan_date crew_size currency currency_other crew_each_local other_local private_note consent; do
  echo "$UPM" | grep -q "name=\"$f\"" && k=$((k+1)); done
[ "$n" = 17 ] && [ "$k" = 11 ] && ! echo "$UP" | grep -qE 'name="(price_local|crew_local|total_cost_local|crew_pay_local)"' \
  && echo "$UJ" | grep -qF 'price_local: sum ? sum.total : null, crew_local: sum ? sum.crew : null,' \
  && echo "$UJ" | grep -qF 'total_cost_local: costs && sum ? sum.total : null, crew_pay_local: costs && sum ? sum.crew : null,' \
  && ok "every field /api/submit and /api/mission read is in its form (17 and 11), the money totals worked out by the page and sent as before" || bad "form fields" "$n of 17, $k of 11"
# Chips write what the crew used before only when tapped: never in a field the crew measures, never on consent, and
# no box is ticked by the page.
CHB=$(echo "$UP" | grep -oE '<div class="chips" id="[A-Za-z]+"' | sed 's/.*id="//;s/"$//' | LC_ALL=C sort | tr '\n' ' ')
CHP=$(echo "$UP" | grep -oE '<button type="button" class="chip"[^>]*>' | sed -E 's/.*(id|data-i18n)="([^"]+)".*/\2/' | LC_ALL=C sort | tr '\n' ' ')
CHI=""; for f in f-kg f-sacks f-hours f-each f-other f-consent m-crew m-each m-other m-consent; do
  end='<\/label>'; case $f in *-other) end='<\/div>';; esac
  echo "$UP" | sed -n "/id=\"$f\"/,/$end/p" | grep -q 'chip' && CHI="$CHI $f"; done
[ "$CHB" = "dispChips placeChipsC placeChipsM " ] && [ "$CHP" = "disp_bank disp_collector disp_official planDay priceChip taskChip " ] && [ -z "$CHI" ] \
  && ! echo "$UP" | grep -qE '<input type="checkbox"[^>]*checked' \
  && ok "the chips are the place, task, price, date and trash ones, none in kg, sacks, hours, costs, price or consent, and no box is ticked" \
  || bad "chips" "boxes: $CHB; chips: $CHP; inside: $CHI"
PHL=$(echo "$UP" | grep -n 'id="paperHint"' | cut -d: -f1); FBL=$(echo "$UP" | grep -n 'id="f-before"' | cut -d: -f1)
BPS=$(echo "$UP" | sed -n '/<section class="panel step" id="beforePanel">/,/<\/section>/p')
[ -n "$PHL" ] && [ -n "$FBL" ] && [ "$PHL" -lt "$FBL" ] && echo "$BPS" | grep -q 'id="paperHint"' && echo "$BPS" | grep -q 'id="f-geo"' \
  && ok "the #12 paper sits right above the before photos, and Use my location now in BEFORE THE CLEANUP" || bad "paper and location in BEFORE" "$PHL $FBL"
# One address: every history entry is written with no URL (the token repair keeps its own line), nothing writes the
# hash, a send keeps its form against the back button and asks before a real leave, and the old tab's mode is not read.
HCL=$(echo "$UJ" | grep -oE 'history\.(pushState|replaceState)\([^)]*\)' | grep -vF 'history.replaceState(history.state, "", `${location.pathname}?k=${token}${location.hash}`)')
[ "$(echo "$HCL" | wc -l | tr -d ' ')" = 3 ] && ! echo "$HCL" | grep -qvE '^history\.(pushState|replaceState)\([A-Za-z]+, ""\)$' \
  && ! echo "$UJ" | grep -qE 'location\.hash *=[^=]' \
  && echo "$UJ" | grep -qF 'addEventListener("beforeunload", (ev) => { if (sendLocked()) { ev.preventDefault(); ev.returnValue = ""; } });' \
  && echo "$UJ" | grep -qF 'addEventListener("popstate"' && echo "$UJ" | grep -qF 'const sendLocked = () => busy || waitingFiles;' \
  && echo "$UJ" | grep -qF 'function setState(s, push) { lastState = s; if (push) history.pushState(s, ""); else history.replaceState(s, ""); }' \
  && ! echo "$UJ" | grep -qF 'sapu-upload-mode:' \
  && ok "the screens are history entries on the same address, a send keeps its form against the back button, and the old mode is not read" \
  || bad "upload.js history" "$HCL"
printf '%s' "$UJ" > "$T/crew.js"; printf '%s' "$UP" > "$T/crew.html"; printf '%s' "$AJ" > "$T/crew-admin.js"
# Texts: the same keys in EN and ID, every key of the page in T.en, no dashes, the old keys gone, the new ones there.
CTX=$(node -e '
const fs = require("fs");
const s = fs.readFileSync(process.argv[1], "utf8"), page = fs.readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const bad = [];
const en = Object.keys(T.en), id = Object.keys(T.id);
const only = en.filter((k) => !id.includes(k)).concat(id.filter((k) => !en.includes(k)));
if (only.length) bad.push("not in both: " + only.join(" "));
const used = [...page.matchAll(/data-(?:i18n|ph|i18n-aria)="([a-z0-9_]+)"/g)].map((m) => m[1]);
const missing = [...new Set(used)].filter((k) => !(k in T.en));
if (missing.length) bad.push("page keys not in T.en: " + missing.join(" "));
const dash = Object.entries(T.en).concat(Object.entries(T.id)).filter(([, v]) => /[\u2013\u2014]/.test(v)).map(([k]) => k);
if (dash.length) bad.push("dashes: " + dash.join(" "));
const gone = ["mode_label", "mode_cleanup_sub", "funded_note", "photos_h", "photos_hint", "where_h", "again", "m_again", "e_mission_gone", "e_mission_taken",
  "crewpay_hint", "crewpay", "e_crew_local", "e_price"];
const left = gone.filter((k) => new RegExp("\\b" + k + ":").test(s));
if (left.length) bad.push("old keys left: " + left.join(" "));
// The labels of the typed totals (the price, the cleanup total, the crew share): words that are also field names, so
// looked up in T itself.
for (const k of ["price", "total", "crew_local"]) if (k in T.en || k in T.id) bad.push("old key " + k);
const fresh = ("intro_h intro_body intro_1 intro_2 intro_3 m_limit_home plain_btn plain_sub past_h past_removed page_h card_ready card_today card_day " +
  "card_planned card_day_past card_send card_continue card_progress st_review_body st_open_body st_sent_body share_m withdraw_m draft_c_h draft_m_h " +
  "draft_body draft_gone draft_go draft_del draft_del_q switch_q move_q back to_home title_cleanup_m title_plain sum_kicker sum_planned sum_change " +
  "guard_q guard_yes before_h before_hint after_h after_hint geo_hint_m plan_day_btn crew_src crew_src_last cost_paid cost_receipt_plan cost_receipt " +
  "cost_toggle chips_place chips_disposal disp_bank disp_collector disp_official chip_task chip_price draft_photos st_sent_body_all switch_plain_q " +
  "m_crew m_each other_costs other_hint m_sum_h sum_crew sum_crew_1 sum_people_m sum_parts sum_parts_0 sum_wait e_money e_each e_sum_zero " +
  "chip_price_0 m_done_price price_line price_line_0 price_line_old price_line_unpaid card_price got_each c_sum_h sum_people_c e_each_c cost_crew").split(" ");
const absent = fresh.filter((k) => !(k in T.en) || !(k in T.id));
if (absent.length) bad.push("new keys missing: " + absent.join(" "));
if (T.en.title !== "YOUR CREW PAGE" || T.id.title !== "HALAMAN KRU KAMU" || T.en.uploading_as !== "Crew:" || T.id.uploading_as !== "Kru:") bad.push("title or crew line");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + en.length + " " + fresh.length);
' "$T/crew.js" "$T/crew.html" 2>&1)
case "$CTX" in
  "ok "*" 90") ok "upload.js texts: the same keys in EN and ID ($CTX), every key of the page, no dashes, the 14 old keys gone (and the labels of the typed totals), the 90 new ones there" ;;
  *) bad "upload.js texts (node)" "$CTX" ;;
esac
# The crew messages name the page's own buttons (welcome step 1 and 4, the funded message), EN and ID, with and
# without an advance: welcomeText and missionFundedText run in node with T from upload.js.
CMS=$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8"), up = fs.readFileSync(process.argv[2], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
eval([/^  const n = .*$/m, /^  const isNum = .*$/m, /^  const cents = .*$/m, /^  const missionNo = .*$/m, /^  const spotsOf = .*$/m, /^  const lastDay = .*$/m, /^  const ADVANCE_PCT = .*$/m].map(line).join("\n") + "\n" +
  ["welcomeText", "missionFundedText"].map(fn).join("\n") + "\nObject.assign(globalThis, { welcomeText, missionFundedText });");
const a = up.indexOf("  const T = {"), b = up.indexOf("\n  };", a);
const T = new Function("return (" + up.slice(a + "  const T = ".length, b + 4) + ");")();
const app = { contact_name: "Ayu", org_name: "Kali Crew" };
const mis = (adv) => ({ no: 12, place_name: "Pantai Kuta", funded_eur: 20, advance_eur: adv, plan_date: "2099-01-05", contact: { contact_name: "Ayu" } });
const say = { en: ["tap ", " (with your mission" + String.fromCharCode(39) + "s number)", ", add the photos"], id: ["tekan ", " (dengan nomor misi kalian)", ", tambahkan foto"] };
const bad = [];
let n = 0;
for (const l of ["en", "id"]) {
  const [tap, which, add] = say[l], L = T[l], card = tap + L.card_send.split("{no}").join("12");
  const w = welcomeText(l, app, "https://sapu.earth/upload/?k=x");
  const want = [[w, tap + L.mode_mission + ":"], [w, "\"" + L.use_location + "\""], [w, card + which], [w, tap + L.send + "."]];
  for (const adv of [6, 0]) { const f = missionFundedText(l, mis(adv)); want.push([f, card + add], [f, tap + L.send + "."]); }
  for (const [text, part] of want) { n++; if (!text.includes(part)) bad.push(l + " lacks " + part); }
  for (const text of [w, missionFundedText(l, mis(6)), missionFundedText(l, mis(0))]) {
    for (const old of ["pick the mission", "pick mission #", "pilih misinya", "pilih misi #", "upload link", "link unggah"]) if (text.includes(old)) bad.push(l + " still says " + old);
  }
}
console.log(bad.length ? bad.join("; ") : "ok " + n);
' "$T/crew-admin.js" "$T/crew.js" 2>&1)
check "the welcome and funded messages name the crew page's buttons: POST A MISSION, Use my location now, SEND A CLEANUP FOR #12, SEND CLEANUP (EN and ID, node)" "$CMS" "ok 16"
# REJECT on PENDING: the ready reply to the crew (cleanupRejectText) runs in node, EN and ID: one line per ticked reason
# (the #N paper only for a cleanup sent for a mission), the crew page's own buttons from T in upload.js, the resend
# only while the mission is still funded, the next-message line when nothing is ticked, the reply-here line, no dashes, no Wise.
CRJ=$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8"), up = fs.readFileSync(process.argv[2], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
const block = (start, end) => { const a = src.indexOf(start), b = src.indexOf(end, a); if (a < 0 || b < 0) throw new Error("missing " + start); return src.slice(a, b + end.length); };
eval([/^  const n = .*$/m, /^  const missionNo = .*$/m, /^  const whyText = .*$/m].map(line).join("\n") + "\n" +
  block("  const REJECT_WHY = [", "\n  ];\n") + fn("cleanupRejectText") + "\nObject.assign(globalThis, { REJECT_WHY, whyText, cleanupRejectText });");
const a = up.indexOf("  const T = {"), b = up.indexOf("\n  };", a);
const T = new Function("return (" + up.slice(a + "  const T = ".length, b + 4) + ");")();
const sub = (videos) => ({ partner_name: "Kali Crew", place_name: "Pantai Kuta", contact: { contact_name: "Ayu" }, media: { videos: videos ? [{}] : [] } });
const mis = (status) => ({ no: 12, status });
const all = REJECT_WHY.map((r) => r.key);
const reason = (k, l) => whyText(REJECT_WHY.find((r) => r.key === k), l, "12");
const bad = [];
let n = 0;
const has = (name, text, part) => { n++; if (!text.includes(part)) bad.push(name + " lacks " + JSON.stringify(part)); };
const lacks = (name, text, part) => { n++; if (text.includes(part)) bad.push(name + " has " + JSON.stringify(part)); };
for (const l of ["en", "id"]) {
  const L = T[l], card = L.card_send.split("{no}").join("12");
  const f = cleanupRejectText(l, sub(false), mis("funded"), ["child", "paper"]);
  has(l + " funded", f, "- " + reason("child", l)); has(l + " funded", f, "- " + reason("paper", l)); lacks(l + " funded", f, reason("spot", l));
  has(l + " funded", f, card); has(l + " funded", f, L.send); has(l + " funded", f, "Ayu");
  has(l + " funded", f, l === "en" ? "Mission #12 stays funded." : "Misi #12 tetap didanai.");
  const p = cleanupRejectText(l, sub(true), null, all);
  has(l + " plain", p, L.plain_btn); lacks(l + " plain", p, "#"); has(l + " plain", p, l === "en" ? "with its photos and videos" : "beserta foto dan videonya");
  const g = cleanupRejectText(l, sub(false), mis("removed"), ["dark"]);
  lacks(l + " removed", g, card); lacks(l + " removed", g, L.send);
  const z = cleanupRejectText(l, sub(false), mis("funded"), []);
  has(l + " none", z, l === "en" ? "I explain why in my next message." : "Alasannya saya jelaskan di pesan berikutnya.");
  for (const [k, t] of [["funded", f], ["plain", p], ["removed", g], ["none", z]]) {
    has(l + " " + k, t, l === "en" ? "If you think we got it wrong, reply here and tell us why" : "Kalau menurut kalian kami salah, balas pesan ini");
    if (/[–—]/.test(t) || /\bwise\b/i.test(t)) bad.push(l + " " + k + " has a dash or Wise");
  }
}
console.log(bad.length ? bad.join("; ") : "ok " + n);
' "$T/crew-admin.js" "$T/crew.js" 2>&1)
check "REJECT on PENDING: the reply names each ticked reason (the #12 paper only for a mission), the crew page's buttons, the resend only while the mission is funded, how to ask us to look again (EN and ID, node)" "$CRJ" "ok 34"
echo "$AJ" | grep -qF 'if (act === "reject") return openWhy(true);' && echo "$AJ" | grep -qF 'if (act !== "approve" && act !== "delete") return;' \
  && echo "$AJ" | grep -qF 'action: act === "delete" ? "reject" : act,' && echo "$AJ" | grep -qF 'deleteLabel: "REJECT AND DELETE",' \
  && echo "$AJ" | grep -qF 'title: "Tell the crew why", label: "Reject message",' \
  && echo "$AJ" | grep -qF 'reply.addEventListener("change", (ev) => { if (ev.target.name === "why") reply.refresh(); });' \
  && echo "$AJ" | grep -qF 'box.refresh = () => show(shown);' \
  && ok "REJECT on PENDING only opens the reply with the reasons; REJECT AND DELETE inside it deletes, and the reply's own buttons never reach the API" || bad "admin.js reject reply" ""
echo "$SJ" | grep -qF 'const fresh = /^#(ev-|m-\d)/.test(location.hash) ? { cache: "reload" } : undefined;' \
  && echo "$SJ" | grep -qF 'fetch("/api/missions", fresh)' && echo "$SJ" | grep -qF 'fetch("/api/events", fresh)' \
  && ok "a link to one receipt or mission (#ev-, #m-) asks for both lists past the browser's 60 s cache, so a receipt approved a moment ago opens" || bad "app.js fresh deep links" ""
grep -qF 'const signKey = (env) => (typeof env.MEDIA_KEY === "string" && env.MEDIA_KEY ? env.MEDIA_KEY : env.ADMIN_TOKEN);' functions/_lib/util.js \
  && ! grep -qE 'hmacHex\(env\.ADMIN_TOKEN' functions/_lib/util.js && [ "$(grep -cF 'hmacHex(signKey(env)' functions/_lib/util.js)" = 2 ] \
  && grep -qF '`${set} WHERE id = ? AND status = ?`' functions/api/admin/decide.js \
  && grep -qF "AND EXISTS (SELECT 1 FROM submissions WHERE id = ? AND mission_id = ? AND status = 'approved')" functions/api/admin/decide.js \
  && [ "$(grep -cF 'WHERE ${guard}${same}`' functions/api/admin/missions/decide.js)" = 2 ] && [ "$(grep -cF '...sameVals).run();' functions/api/admin/missions/decide.js)" = 2 ] \
  && ok "signed media links and the IP hash use MEDIA_KEY (the admin token only until it is set); APPROVE needs the status it read; PUBLISH and FUND check the crew's version inside the UPDATE" \
  || bad "security guards in the code" ""
# The crew page model, the pure block of upload.js, run in node: which cards show in which order, the one orange
# button, the screen a history entry may show, unsent work, what the chips and the crew size offer, and the price as
# PRICE and COSTS add it up (moneySum, read back by splitOf to the cent, the price chip only for an even split, and
# what the lines under the amounts say while the crew types and at SEND).
CPM=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  // ---------- crew page model (pure; tests/e2e.sh runs this block in node) ----------");
const b = s.indexOf("  // ---------- end of crew page model ----------");
if (a < 0 || b < a) throw new Error("no model block");
const M = new Function(s.slice(a, b) + "\nreturn { ACTIVE_STATES, ACTIVE_MAX, lastCrewMission, planOf, lastPlanMission, excerpt, nearestMission, guardMission, openAsk, placeChips, hasWork, daysBetween, resolveView, homeModel, splitOf, moneySum, payOf, sumView };")();
const bad = [];
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": " + JSON.stringify(got)); };
const plan = (price = 1000000, crew = 700000, task = "Clear the beach.", currency = "IDR") => ({ task, currency, price_local: price, crew_local: crew });
const mi = (no, status, extra = {}) => Object.assign({ id: "m" + no, no, status, place_name: "Place " + no, plan_date: null, cleanup_sent: false, crew_size: 5, plan: plan() }, extra);
const list = [mi(9, "removed", { plan: null }), mi(5, "review"), mi(4, "open"), mi(3, "funded", { plan_date: "2026-11-20" }),
  mi(2, "funded", { plan_date: "2026-11-12" }), mi(1, "funded", { cleanup_sent: true }), mi(0, "done")];
const ids = (xs) => xs.map((m) => m.id);
const home = (missions, enabled, work, missionId, mwork) => M.homeModel({ missions, enabled, cleanup: { work, missionId }, mission: { work: mwork } });
let h = home(list, true, true, "m3", false);
eq("work for #3", [ids(h.ready), h.orange, h.plainDraft, ids(h.waiting), ids(h.sent), ids(h.past), ids(h.removed), h.limit, h.intro],
  [["m3", "m2"], { kind: "ready", id: "m3" }, false, ["m5", "m4"], ["m1"], ["m0"], ["m9"], true, false]);
h = home(list, true, false, "", false);
eq("no work", [ids(h.ready), h.orange], [["m2", "m3"], { kind: "ready", id: "m2" }]);
h = home(list, true, true, "none", false);
eq("work without a mission", [h.plainDraft, h.orange], [true, { kind: "ready", id: "m2" }]);
h = home([], true, false, "", false);
eq("no missions", [h.intro, h.orange], [true, { kind: "post" }]);
h = home([], true, false, "", true);
eq("a mission not posted yet", [h.intro, h.missionDraft, h.orange], [false, true, { kind: "mission" }]);
h = home([], false, false, "", true);
eq("missions off", [h.orange, h.missionDraft, h.intro], [{ kind: "solo" }, false, false]);
eq("missions off with a cleanup", home([], false, true, "", false).orange, { kind: "plain" });
const on = { enabled: true, toClean: ["m2", "m3"] }, off = { enabled: false, toClean: [] };
const rv = (st, c = on) => { const r = M.resolveView(st, c); return r.view + ":" + r.mission; };
eq("resolveView", [rv(null), rv({ sapu: 1, view: "home" }), rv({ view: "cleanup", mission: "m2", done: true }), rv({ view: "mission" }), rv({ view: "mission" }, off),
  rv({ view: "cleanup", mission: "none" }), rv({ view: "cleanup", mission: "none" }, off), rv({ view: "cleanup", mission: "m3" }), rv({ view: "cleanup", mission: "m1" })],
  ["home:null", "home:null", "home:null", "mission:null", "home:null", "cleanup:none", "cleanup:none", "cleanup:m3", "home:null"]);
const A = ["kg", "notes"], U = ["place_name", "crew_size"];
eq("hasWork", [M.hasWork({}, {}, A, U, false), M.hasWork({ place_name: "Kuta", crew_size: "8" }, { place_name: "Kuta", crew_size: "8" }, A, U, false),
  M.hasWork({ crew_size: "9" }, { crew_size: "8" }, A, U, false), M.hasWork({ kg: "0" }, {}, A, U, false), M.hasWork({}, {}, A, U, true),
  M.hasWork({ place_name: "  " }, {}, A, U, false)], [false, false, true, true, true, false]);
eq("placeChips", M.placeChips([{ place_name: " Pantai Kuta " }, { place_name: "pantai kuta" }, { place_name: "" }, { place_name: 7 }, { place_name: "Sanur" }],
  [{ place_name: "Canggu" }, { place_name: "Jimbaran" }], "SANUR"), ["Pantai Kuta", "Canggu", "Jimbaran"]);
eq("placeChips max", M.placeChips([{ place_name: "A" }, { place_name: "B" }], [{ place_name: "C" }], "", 2), ["A", "B"]);
eq("planOf", [!!M.planOf({ plan: plan() }), M.planOf({ plan: plan(1000, 500, "") }), M.planOf({ plan: plan(1000, 500, "x", "idr") }), M.planOf({ plan: plan(0, 0) }),
  M.planOf({ plan: plan(1000, 1001) }), M.planOf({ plan: null }), M.planOf(null)], [true, null, null, null, null, null, null]);
eq("lastPlanMission", (M.lastPlanMission([mi(4, "open"), mi(3, "removed", { plan: null }), mi(2, "funded"), mi(1, "done")]) || {}).id, "m2");
eq("lastCrewMission", (M.lastCrewMission([mi(4, "open", { crew_size: 0 }), mi(3, "review", { crew_size: 1001 }), mi(2, "removed", { crew_size: "8" }), mi(1, "done", { crew_size: 6 })]) || {}).id, "m1");
eq("daysBetween", [M.daysBetween("2026-11-15", "2026-11-16"), M.daysBetween("2026-11-16", "2026-11-15"), M.daysBetween("2026-13-01", "2026-11-16"), M.daysBetween("2026-11-15", null)], [1, -1, null, null]);
eq("limit", [M.ACTIVE_MAX, M.ACTIVE_STATES], [5, ["review", "open", "funded"]]);
// While Sapu Earth checks a mission (in review, open) or a sent cleanup and nothing else waits, no button is orange:
// the next step is to wait. Past missions only: POST A MISSION. Unsent work and ready missions still come first.
eq("orange while waiting", [home([mi(1, "review")], true, false, "", false).orange, home([mi(1, "open")], true, false, "", false).orange,
  home([mi(1, "funded", { cleanup_sent: true })], true, false, "", false).orange, home([mi(2, "done"), mi(1, "removed", { plan: null })], true, false, "", false).orange,
  home([mi(1, "review")], true, false, "", true).orange, home([mi(1, "review")], true, true, "none", false).orange, home([mi(2, "review"), mi(1, "funded")], true, false, "", false).orange],
  [null, null, null, { kind: "post" }, { kind: "mission" }, { kind: "plain" }, { kind: "ready", id: "m1" }]);
// The plan and price chips of POST A MISSION: the newest funded or done mission at the place written (case and spaces
// do not count), else the newest funded or done one, never one in review.
const at = [mi(4, "done", { place_name: "Muara Tukad Mati, Kuta" }), mi(3, "review", { place_name: "Pantai Kedonganan" }),
  mi(2, "done", { place_name: " pantai kedonganan " }), mi(1, "funded", { place_name: "Sanur" })];
eq("lastPlanMission at a place", [M.lastPlanMission(at, "Pantai Kedonganan").id, M.lastPlanMission(at, "  PANTAI KEDONGANAN").id, M.lastPlanMission(at, "Nowhere").id,
  M.lastPlanMission(at, "").id, M.lastPlanMission(at, "Sanur").id, M.lastPlanMission([mi(1, "review", { place_name: "X" })], "X")], ["m2", "m2", "m4", "m4", "m1", null]);
eq("excerpt", [M.excerpt("Clear the river mouth.\nSort the plastic for the waste bank."), M.excerpt("Pick up the plastic at the river mouth and on the beach next to it, sort it, bring it to the waste bank."),
  M.excerpt("x".repeat(70)), M.excerpt(""), M.excerpt("  a   b  ")],
  ["Clear the river mouth. Sort the plastic for the waste bank.", "Pick up the plastic at the river mouth and on the beach next\u2026", "x".repeat(60) + "\u2026", "", "a b"]);
// The question of the cleanup without a mission: the funded mission nearest to today (a tie goes to the earlier day), none
// while a mission is picked, and none once the cleanup lost its mission (its photos may show that paper).
const tc = [mi(7, "funded", { plan_date: "2026-11-09" }), mi(8, "funded", { plan_date: "2026-11-13" }), mi(6, "funded")];
eq("nearestMission", [M.nearestMission(tc, "2026-11-11").id, M.nearestMission(tc, "2026-11-12").id, M.nearestMission([mi(6, "funded")], "2026-11-11").id, M.nearestMission([], "2026-11-11")],
  ["m7", "m8", "m6", null]);
const gm = (picked, lost, toClean) => M.guardMission({ picked, lost, toClean, today: "2026-11-11" });
eq("guardMission", [gm(false, null, tc).id, gm(true, null, tc), gm(false, 19, tc), gm(false, null, [])], ["m7", null, null, null]);
// What a card or the plain link asks first: nothing without work or for the same cleanup; move work without a mission into
// a mission; switch (ask, then remove) work for another mission, and work that lost its mission.
const ask = (work, held, lost, target) => M.openAsk({ work, held, lost, target });
eq("openAsk", [ask(false, "m12", null, "m13"), ask(true, "m12", null, "m12"), ask(true, "m12", null, "m13"), ask(true, "m12", null, "none"),
  ask(true, "none", null, "m13"), ask(true, "none", null, "none"), ask(true, "none", 19, "m13"), ask(true, "none", 19, "none")],
  [null, null, "switch", "switch", "move", null, "switch", null]);
// The price as the page adds it up: the pay for each person to the cent times the people, plus the other costs; read back
// (splitOf) it gives the same pay for each person and other costs, exact; a stored crew pay sent as one total (mission #2)
// is not exact. The price chip only offers an even split. While typing, an amount that may still become a number says
// nothing; at SEND it says why it cannot be read.
eq("moneySum", [M.moneySum(15, 100000, 1500000), M.moneySum(15, 100000, null).total, M.moneySum(3, 0.1, 0).crew, [M.moneySum(4, 1250.555, 0).each, M.moneySum(4, 1250.555, 0).crew],
  M.moneySum(15, 0, 0).total, M.moneySum(1000, 1e9, 0).crew, M.moneySum(0, 1, 0), M.moneySum(1001, 1, 0), M.moneySum(2.5, 1, 0), M.moneySum(15, NaN, 0), M.moneySum(5, null, 0), M.moneySum(5, -1, 0)],
  [{ people: 15, each: 100000, crew: 1500000, other: 1500000, total: 3000000 }, 1500000, 0.3, [1250.56, 5002.24], 0, 1e12, null, null, null, null, null, null]);
eq("splitOf", [M.splitOf(3000000, 1500000, 15), M.splitOf(3000000, 100000, 15), M.splitOf(1000, 600, null), M.splitOf(1801.5, 1801.5, 3), M.splitOf(1000, 0, 5),
  M.splitOf(2000000, 1200000, 5), M.splitOf(1000, 1001, 4), M.splitOf(1000, -1, 4), M.splitOf(NaN, 0, 5)],
  [{ each: 100000, other: 1500000, exact: true }, { each: 6666.67, other: 2900000, exact: false }, { each: null, other: 400, exact: false }, { each: 600.5, other: 0, exact: true },
   { each: 0, other: 1000, exact: true }, { each: 240000, other: 800000, exact: true }, null, null, null]);
const po = (m) => { const x = M.payOf(m); return x && [x.m.id, x.currency, x.each, x.other]; };
eq("payOf", [po(mi(2, "funded", { crew_size: 15, plan: plan(3000000, 1500000) })), po(mi(2, "funded", { crew_size: 15, plan: plan(3000000, 100000) })),
  po(mi(3, "done", { crew_size: 4, plan: plan(1000000, 1000000) })), po(mi(4, "funded", { plan: null })), po(null)],
  [["m2", "IDR", 100000, 1500000], null, ["m3", "IDR", 250000, 0], null, null]);
let rt = 0;
for (const p of [1, 3, 7, 15, 1000]) for (const e of [0, 0.1, 12.5, 600.5, 100000, 187500]) for (const o of [0, 0.5, 1500000]) {
  const s = M.moneySum(p, e, o), b = M.splitOf(s.total, s.crew, p);
  if (!b || !b.exact || b.each !== s.each || b.other !== s.other) rt++;
}
eq("round trip", rt, 0);
const rm = (raw, v, bad = null, typing = false) => ({ raw, v, bad, typing }), E0 = rm("", null), P15 = { v: 15, ok: true };
const sv = (people, each, other, strict = false) => { const r = M.sumView(people, each, other, strict); return [r.line && r.line.key, r.line && r.line.cls, r.oline && r.oline.key, r.sum && r.sum.total, r.parts]; };
eq("sumView", [sv(P15, E0, E0), sv(P15, rm("100.000", 100000), E0), sv(P15, rm("100.000", 100000), rm("1.500.000", 1500000)), sv({ v: null, ok: true }, rm("100.000", 100000), E0),
  sv({ v: null, ok: false }, rm("100.000", 100000), E0), sv({ v: 1, ok: true }, rm("100.000", 100000), E0), sv(P15, rm("100rb", null, "e_money"), E0),
  sv(P15, rm("100.", null, "e_money", true), E0), sv(P15, rm("100.", null, "e_money", true), E0, true), sv(P15, rm("2000000000", null, "e_number"), E0),
  sv(P15, rm("100.000", 100000), rm("tidak ada", null, "e_money")), sv(P15, rm("0", 0), E0)],
  [[null, null, null, null, "sum_wait"], ["sum_crew", "", null, 1500000, "sum_parts_0"], ["sum_crew", "", null, 3000000, "sum_parts"], ["people", "wait", null, null, "sum_wait"],
   ["people", "wait", null, null, "sum_wait"], ["sum_crew_1", "", null, 100000, "sum_parts_0"], ["e_money", "warn", null, null, "sum_wait"],
   [null, null, null, null, "sum_wait"], ["e_money", "warn", null, null, "sum_wait"], ["e_number", "warn", null, null, "sum_wait"],
   ["sum_crew", "", "e_money", null, "sum_wait"], ["sum_crew", "", null, 0, "sum_parts_0"]]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/crew.js" 2>&1)
[ "$CPM" = ok ] && ok "crew page model (node): ready missions first (the one started on this phone, then the soonest day), one orange button and none while Sapu Earth checks, unsent work, the screen an entry may show, chips and crew size only from what the crew wrote before (the plan at the same place first), the question of the cleanup without a mission, what a card asks first, and the price as the page adds it up and reads it back (the price chip only for an even split)" \
  || bad "crew page model (node)" "$CPM"
# Review of the crew page: a send locks every control of both forms (YES, FOR #12, CHANGE, the mission select, the chips,
# Use my location now; form.elements covers them, so they must sit inside their form), no draft is written while THANK
# YOU or MISSION #N shows, a cleanup opened and left empty keeps no draft, a cleanup that lost its mission keeps its place,
# country and crew size and the mission's number in its draft, the guard and the card buttons go through guardMission and
# openAsk, an empty form whose mission went away goes back to the crew page, and the H1 has no orange ring.
n=0; for x in 'id="guardYes"' 'id="sumChange"' 'name="mission_id"' 'id="planDay"' 'id="placeChipsC"' 'id="dispChips"' 'id="costToggle"' 'id="geo"'; do
  echo "$UPC" | grep -qF "$x" && n=$((n+1)); done
k=0; for x in 'id="taskChip"' 'id="priceChip"' 'id="placeChipsM"' 'id="mgeo"'; do echo "$UPM" | grep -qF "$x" && k=$((k+1)); done
SDR=$(echo "$UJ" | sed -n '/^  function saveDraft() {/,/^  }$/p'); SMD=$(echo "$UJ" | sed -n '/^  function saveMDraft() {/,/^  }$/p')
PFC=$(echo "$UJ" | sed -n '/^  function pickForCleanup(mission) {/,/^  }$/p'); DRM=$(echo "$UJ" | sed -n '/^  function dropMission(no) {/,/^  }$/p')
[ "$n" = 8 ] && [ "$k" = 4 ] \
  && echo "$UJ" | grep -qF 'for (const u of Object.values(UI)) for (const el of u.form.elements) el.disabled = on;' \
  && echo "$SDR" | grep -qF 'if (doneShown.cleanup) return;' && echo "$SDR" | grep -qF 'd.lost = goneNo;' && echo "$SMD" | grep -qF 'if (doneShown.mission) return;' \
  && echo "$UJ" | grep -qF 'if (sel.value === NO_MISSION && Number.isInteger(d.lost) && d.lost > 0) goneNo = d.lost;' \
  && echo "$PFC" | grep -qF 'if (cleanupWork()) saveDraft(); else store.del(draftKey());' \
  && echo "$DRM" | grep -qF 'const work = cleanupWork();' && echo "$DRM" | grep -qF 'applyMissionPick(work);' && echo "$DRM" | grep -qF 'if (work) saveDraft(); else store.del(draftKey());' \
  && echo "$UJ" | grep -qF 'if (!dropped && el.dataset.prefilled !== undefined && el.value.trim() === el.dataset.prefilled) {' \
  && echo "$UJ" | grep -qF 'if (form.elements.mission_id.value !== NO_MISSION) dropMission(no);' && echo "$UJ" | grep -qF 'dropMission(noOf(cur));' \
  && echo "$UJ" | grep -qF 'if (draft && draft.dropped) dropMission(noOf(draft.dropped));' \
  && echo "$UJ" | grep -qF 'if (view === "cleanup" && dropped && !doneShown.cleanup && !cleanupWork()) toHome();' \
  && echo "$UJ" | grep -qF 'const near = guardMission({ picked: !!m, lost: goneNo, toClean: missionsToClean(), today: localToday() });' \
  && echo "$UJ" | grep -qF 'const ask = openAsk({ work: cleanupWork(), held, lost: held === NO_MISSION ? goneNo : null, target });' \
  && grep -qF '.fp-title:focus, .fp-title:focus-visible { outline: none; }' site/forms.css \
  && ok "a send locks every control of both forms, nothing sent comes back as unsent work, an empty cleanup keeps no draft, a cleanup that lost its mission keeps its answers and never moves into another mission, and the H1 has no orange ring" \
  || bad "upload.js send lock, drafts and lost missions" "controls in #form $n of 8, in #mform $k of 4"
# The chips and numbers: the plan and price of the mission at the place written, the plan's start on its chip, no grey
# example under the task chip and none ever on the money, the price chip only for an even split (payOf) with its pay for
# each person and other costs written with thousands marks, an echo line for long plain numbers; the sent card shows the
# funded amount without the advance and says "the rest of the money" only after an advance.
echo "$UJ" | grep -qF 'const last = partner ? lastPlanMission(missionList(), mform.elements.place_name.value) : null;' \
  && echo "$UJ" | grep -qF 'setMsg($("#taskChip"), "chip_task", { no: last.no, task: excerpt(plan.task) });' \
  && echo "$UJ" | grep -qF 'E.task.placeholder = task ? "" : t(E.task.dataset.ph);' \
  && echo "$UJ" | grep -qF 'const pay = payOf(last);' && echo "$UJ" | grep -qF 'const price = !!pay && !E.crew_each_local.value.trim() && !E.other_local.value.trim();' \
  && echo "$UJ" | grep -qF 'fillField(E.crew_each_local, numText(pay.each));' && echo "$UJ" | grep -qF 'fillField(E.other_local, pay.other > 0 ? numText(pay.other) : "");' \
  && ! echo "$UJ" | grep -qF 'PRICE_PH' \
  && echo "$UJ" | grep -qF '/^\d{1,4}$/.test(raw.trim())' \
  && echo "$UJ" | grep -qF 'setText(status, missionStatus(m, false, false));' \
  && echo "$UJ" | grep -qF 'const sentKey = Number(m.advance_eur) > 0 ? "st_sent_body" : "st_sent_body_all";' \
  && ok "POST A MISSION offers the plan and price of the mission at the same place and shows how the plan starts, the price chip only for an even split and as the pay for each person and other costs (1.500.000), no grey example on the money, and the sent card never says the advance is on its way" \
  || bad "upload.js chips, numbers, sent card" ""
echo "$UP" | grep -q 'apple-touch-icon' && ok "/upload/ has an apple-touch-icon" || bad "/upload/ apple-touch-icon" ""
echo "$UP" | grep -qE 'rel="?manifest' && bad "/upload/ must not link a web app manifest" "" || ok "/upload/ has no web app manifest"

# YOUR LOGO on the crew page (docs/upload-flow.md, Crew logos): between YOUR CLEANUPS and YOUR PUBLIC PAGE, the tile,
# its line, the rules, then the picker (no data-kind: it is no form's, and the six named pickers stay six), its
# message. Still one orange button on the crew page.
LBX=$(echo "$UPH" | sed -n '/<section class="panel cp-logo" id="logoBox" hidden>/,/<\/section>/p')
MI=$(echo "$UPH" | grep -n 'id="mine"' | cut -d: -f1); LBI=$(echo "$UPH" | grep -n 'id="logoBox"' | cut -d: -f1); PPI=$(echo "$UPH" | grep -n 'id="pubPage"' | cut -d: -f1)
ORD=$(echo "$LBX" | grep -oE 'id="logo(Tile|Line|Input|Msg)"|data-i18n="logo_rules"|class="b b-row b-ghost cl-pick"' | tr '\n' ' ')
LIN=$(echo "$LBX" | grep -oE '<input [^>]*id="logoInput"[^>]*>')
[ -n "$MI" ] && [ -n "$LBI" ] && [ -n "$PPI" ] && [ "$MI" -lt "$LBI" ] && [ "$LBI" -lt "$PPI" ] \
  && [ "$ORD" = 'id="logoTile" id="logoLine" data-i18n="logo_rules" class="b b-row b-ghost cl-pick" id="logoInput" id="logoMsg" ' ] \
  && echo "$LIN" | grep -qF 'type="file"' && echo "$LIN" | grep -qF 'accept="image/*"' && echo "$LIN" | grep -qF 'data-i18n-aria="logo_pick"' \
  && ! echo "$LIN" | grep -qE 'multiple|capture|data-kind' \
  && [ "$(echo "$UP" | grep -cE '<input type="file"[^>]* data-i18n-aria="(before|after|video_before|video_after|now|now_video)" aria-label="')" = 6 ] \
  && [ "$(echo "$UP" | grep -B1 -F '<label class="drop">' | grep -c 'class="hint"')" = 2 ] && [ "$(echo "$UP" | grep -B1 -F '<label class="drop">' | grep -cE '^ *<span')" = 4 ] \
  && [ "$(echo "$UPH" | grep -o 'b-go' | wc -l | tr -d ' ')" = 1 ] \
  && ok "the crew page has YOUR LOGO between YOUR CLEANUPS and YOUR PUBLIC PAGE: the tile, its line, the rules above the picker (image/*, no data-kind, multiple or capture), its message; six named pickers, one orange button" \
  || bad "crew page YOUR LOGO markup" "$MI $LBI $PPI [$ORD] $LIN"
LGJ=$(echo "$UJ" | sed -n '/^  function renderLogo() {/,/^  }$/p')
echo "$UJ" | grep -qF "\$\$('input[type=\"file\"][data-kind]').forEach((input) => input.addEventListener(\"change\", () => {" \
  && echo "$UJ" | grep -qF 'r = await fetch(`/api/logo?k=${encodeURIComponent(token)}`, {' && echo "$UJ" | grep -qF 'headers: { "Content-Type": "image/jpeg" }, body: blob,' \
  && echo "$UJ" | grep -qF 'const waits = [2, 5, 10];' \
  && echo "$UJ" | grep -qF "\$\$('input[type=\"file\"]').forEach((i) => (i.disabled = on || (i.id === \"logoInput\" && !!logoPhase)));" \
  && echo "$UJ" | grep -qF 'if (epoch !== logoEpoch) fresh.logo = logoLast;' \
  && [ -n "$LGJ" ] && echo "$LGJ" | grep -qF 'logoPhase' && echo "$UJ" | grep -qF 'renderMine();
    renderLogo();' \
  && echo "$UJ" | grep -qF 'partner && !sendLocked() && !logoPhase && !ttPhase && Date.now() - lastFetch' \
  && ! echo "$UJ" | grep -qE '"#logo(Line|Btn|Msg)"\)\.textContent' \
  && ok "upload.js: the form pickers only by data-kind, the logo posted as image/jpeg with retries after 2, 5 and 10 s, kept locked by the end of a send and by a slow list while it is on its way, renderLogo reads the phase, nothing comes back with a 5-minute refresh during it, its lines only through setMsg" \
  || bad "upload.js YOUR LOGO wiring" ""
printf '%s' "$UJ" > "$T/lg-u.js"; printf '%s' "$AJS" > "$T/lg-a.js"
LTX=$(node -e '
const fs = require("fs");
const T = (f) => { const s = fs.readFileSync(f, "utf8"); const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
  return new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")(); };
const U = T(process.argv[1]), P = T(process.argv[2]);
const bad = [];
const has = (t, name, list) => { for (const k of list.split(" ")) for (const l of ["en", "id"]) {
  const v = t[l][k];
  if (typeof v !== "string" || !v) bad.push(name + " " + l + " " + k);
  else if (/[\u2013\u2014]/.test(v)) bad.push(name + " " + k + " has a dash");
  else if (l === "id" && /\bkalian\b/.test(v)) bad.push(name + " " + k + " says kalian");
} };
has(U, "upload.js", "logo_h logo_add logo_change logo_pick logo_none logo_rules logo_preparing logo_sending logo_review logo_review_live logo_live logo_declined logo_declined_live e_logo_read e_logo_small e_logo_send e_logo_limit e_logo_refused");
has(P, "apply.js", "logo_h logo_hint add_logo e_logo_read e_logo_small e_logo_server");
if (U.id.logo_h !== "LOGO KRU KAMU" || U.en.logo_h !== "YOUR LOGO" || P.en.logo_h !== "LOGO (OPTIONAL)") bad.push("titles");
// A logo shows only once Sapu Earth approves it: the texts say so, and never that it shows after a check alone.
for (const [t, l, k, w] of [[U, "en", "logo_none", "Once Sapu Earth approves it"], [U, "id", "logo_none", "Setelah disetujui Sapu Earth"],
  [U, "en", "logo_review", "Once we approve it"], [U, "id", "logo_review", "Setelah kami setujui"],
  [P, "en", "logo_hint", "we can show it"], [P, "id", "logo_hint", "bisa kami tampilkan"],
  [U, "en", "logo_rules", "no QR codes"], [U, "id", "logo_rules", "kode QR"]]) if (!String(t[l][k]).includes(w)) bad.push(l + " " + k + " lacks: " + w);
if (/checked it/.test(U.en.logo_none + U.en.logo_review) || /kami cek, logo/.test(U.id.logo_review)) bad.push("a logo text promises it shows after a check");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/lg-u.js" "$T/lg-a.js" 2>&1)
[ "$LTX" = ok ] && ok "the logo texts are in EN and ID on the crew page and the apply page, no dashes, the Indonesian says kamu (LOGO KRU KAMU), a logo shows once approved (never only checked), and the rules name QR codes" || bad "logo texts" "$LTX"
APL=$(echo "$AP" | grep -oE 'data-i18n="(crew_h|logo_h|photos_h)"' | tr '\n' ' ')
L413=$(echo "$AJS" | grep -nF 'if (field === "logo") return showErrors([{ id: "f-logo", key: "e_logo_server" }]);' | cut -d: -f1)
P413=$(echo "$AJS" | grep -nF 'if (st === 413 || (st === 415 && (field === "photos"' | cut -d: -f1)
[ "$APL" = 'data-i18n="crew_h" data-i18n="logo_h" data-i18n="photos_h" ' ] && echo "$AP" | grep -qF '<div class="field" id="f-logo">' \
  && echo "$AP" | grep -qF '<label class="drop"><span data-i18n="add_logo">+ Add logo</span><input type="file" accept="image/*"></label>' \
  && echo "$AP" | grep -qF '<div class="thumbs" id="logoThumb"></div>' && ! echo "$AP" | grep -B1 -F '<label class="drop">' | grep -q 'class="hint"' \
  && echo "$AJS" | grep -qF 'if (logo && logo.blob) fd.append("logo", logo.blob, "logo.jpg");' \
  && [ -n "$L413" ] && [ -n "$P413" ] && [ "$L413" -lt "$P413" ] && echo "$AJS" | grep -qF 'logoInput.disabled = true;' && echo "$AJS" | grep -qF 'if (logo) removeLogo(logo);' \
  && echo "$AJS" | grep -qF 'preparing: "Preparing your pictures…",' && echo "$AJS" | grep -qF 'preparing: "Sedang menyiapkan gambar…",' \
  && ok "/apply/: LOGO (OPTIONAL) between YOUR CREW and PHOTOS (its hint for the panel, not right before the picker), sent as logo, a refused logo marked in its field, and SEND waiting for it says pictures, not photos" \
  || bad "/apply/ logo" "[$APL] $L413 $P413"
AJL=$(echo "$AJ" | sed -n '/^  async function listPartners(data) {/,/^  }$/p')
echo "$AJ" | grep -qF 'logo: a.logo && f.elements.use_logo && f.elements.use_logo.checked ? a.logo.key : null,' \
  && echo "$AJ" | grep -qF '"/api/admin/logos/decide"' \
  && echo "$AJ" | grep -qF 'if (c > 0) parts.push(`${c} LOGO${c === 1 ? "" : "S"}`);' && echo "$AJ" | grep -qF 'b.textContent = ["PARTNERS", ...parts].join(" · ");' \
  && echo "$AJL" | grep -qF 'drawLogoCheck(partners);' && echo "$AJL" | grep -qF 'setPartnerCount(data.counts);' \
  && echo "$AJ" | grep -qF '<img class="p-logo" src="${esc(logo)}" alt="" width="40" height="40" loading="lazy" decoding="async">' \
  && echo "$AJ" | grep -qF 'const reload = e.code === "state" || e.code === "inactive";' \
  && echo "$AJ" | grep -qF 'Take the logo of ${p.name} off sapu.earth? It is deleted for good, and their crew page asks them for another one.' \
  && echo "$AJ" | grep -qF '(p.logo ? " Their current logo stays on sapu.earth." : " Their crew page asks them for another one.")' \
  && echo "$AJ" | grep -qF "APPROVE LOGO puts it next to the crew's name; public pages catch up within 5 minutes." \
  && echo "$AJ" | grep -qF "DECLINE deletes it: their crew page asks them for another one, or keeps showing their current logo if they have one." \
  && echo "$AJ" | grep -qF "Not fine: people, someone else's logo, phone or bank numbers, QR codes, text that asks for money." \
  && echo "$AJ" | grep -qF '(p.logo || p.logo_review ? " Their logo is deleted too." : "")' \
  && echo "$AJ" | grep -qF 'Delete this application now? Their contact details, photos and logo are deleted for good.' \
  && echo "$AJ" | grep -qF '<label class="check"><input type="checkbox" name="use_logo" checked>' \
  && ok "/admin/: LOGOS TO CHECK and the tab label from one partner list, lazy row logos, REMOVE LOGO asks first, a reload on state or inactive, the application's logo with its box ticked, the questions name the logo, DECLINE says whether a live logo stays, and both checklists name QR codes" \
  || bad "admin.js logos" ""
echo "$SJ" | grep -qF 'const logoSrc = (u) => (typeof u === "string" && /^\/media\/[0-9a-f]{32}$/.test(u) ? u : null);' \
  && [ "$(echo "$SJ" | grep -cF 'byRow(e, true)')" = 1 ] && echo "$SJ" | sed -n '/^  function openPost(e) {/,/^  }$/p' | grep -qF '${byRow(e, true)}' \
  && echo "$SJ" | grep -qF '${byRow(e)}' \
  && echo "$SJ" | grep -qF 'const link = typeof p.page === "string" && typeof slug === "string" && /^[a-z0-9-]{1,40}$/.test(slug)' \
  && echo "$SJ" | grep -qF '${by ? `<div><dt>BY</dt><dd>${linkPartner ? crewLogo(m.partner?.logo) : ""}${byHtml}</dd></div>` : ""}' \
  && echo "$SC" | grep -qF '.r-logo { width: 20px; height: 20px; object-fit: cover;' \
  && ok "homepage: a crew's logo (only /media/<32 hex>) and the link to its page in the receipt post's CLEANED BY and the mission post's BY, never on the cards" \
  || bad "site/app.js logos" ""

# Privacy notices (GDPR Art. 13): crew uploads at /upload/#privacy (EN and ID), visitors at /impressum/#privacy.
echo "$UP" | grep -q '<details class="privacy" id="privacy">' && ! echo "$UP" | grep -q '<script>' \
  && echo "$UJ" | grep -qF 'if (location.hash === "#privacy" && $("#privacy")) $("#privacy").open = true;' \
  && ok "/upload/ has the #privacy anchor, and upload.js (no inline script) opens the notice for it" || bad "/upload/ privacy anchor" ""
# Outside both forms, so it also shows without a valid link (the IMPRESSUM link has none).
echo "$UP" | sed -n -e '/<form id="form"/,/<\/form>/p' -e '/<form id="mform"/,/<\/form>/p' | grep -q 'id="privacy"' \
  && bad "/upload/ privacy notice sits inside a form" "it would be hidden without a valid link" || ok "/upload/ privacy notice sits outside the forms, so it shows without a link too"
[ "$(echo "$UP" | grep -c '<p class="pv-link"><a href="#privacy" data-i18n="pv_sum">')" = 2 ] \
  && echo "$UP" | sed -n '/<footer>/,/<\/footer>/p' | grep -qF '<a href="/impressum/">IMPRESSUM</a> · <a href="#privacy" data-i18n="pv_foot">PRIVACY</a>' \
  && ok "/upload/ links its notice under both consent boxes and in the footer" || bad "/upload/ privacy links" ""
echo "$I18U" | grep -qF "\$\$('a[href=\"#privacy\"]').forEach((a) => a.addEventListener(\"click\", (ev) => {" && echo "$I18U" | grep -qF 'pv.open = true;' \
  && ok "upload.js opens the notice from those links without changing the address" || bad "upload.js privacy links" ""
# Every key of a notice in both languages, the same English in the page and in its script, no dashes.
cat > "$T/pv.py" <<'PY'
import html, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
cut = js.index("\n    id: {")
dicts = {"en": js[:cut], "id": js[cut:js.index("\n  };", cut)]}
dashes = (chr(0x2013), chr(0x2014))
def val(lang, k):
    m = re.search(r"\b" + k + r': "((?:[^"\\]|\\.)*)"', dicts[lang])
    return m.group(1) if m else None
shown = re.findall(r'data-i18n="(pv_\w+)">([^<]*)<', page)
keys = sorted({k for k, _ in shown})
bad = []
for k, text in shown:
    if val("en", k) is not None and val("en", k) != html.unescape(text):
        bad.append(k + ": the page and the script differ in English")
for k in keys:
    en, idn = val("en", k), val("id", k)
    if en is None or idn is None:
        bad.append(k + " is missing in " + ("EN" if en is None else "ID"))
    elif en == idn:
        bad.append(k + " is not translated")
    if any(d in (en or "") + (idn or "") for d in dashes):
        bad.append(k + " has an en or em dash")
for lang, d in dicts.items():
    for k in re.findall(r"\b(pv_\w+): \"", d):
        if k not in keys:
            bad.append(k + " (" + lang + ") is not on the page")
print("; ".join(bad) if bad else "OK %d" % len(keys))
PY
printf '%s' "$UP" > "$T/up.html"; printf '%s' "$I18U" > "$T/up.js"
printf '%s' "$AP" > "$T/ap.html"; printf '%s' "$I18A" > "$T/ap.js"
PV=$(python3 "$T/pv.py" "$T/up.html" "$T/up.js")
case "$PV" in
  "OK 24") ok "the upload notice has all 24 keys in English and Indonesian, the same English on the page and in upload.js, no dashes" ;;
  *) bad "upload privacy notice keys" "$PV (expected OK 24)" ;;
esac
PV=$(python3 "$T/pv.py" "$T/ap.html" "$T/ap.js")
case "$PV" in
  "OK 14") ok "the application notice has all 14 keys in English and Indonesian, the same English on the page and in apply.js, no dashes" ;;
  *) bad "application privacy notice keys" "$PV (expected OK 14)" ;;
esac
# The logo sentences of both notices, EN on the page and in the script, ID in the script; the 90 days are the code's.
grep -qF 'reviewDays: 90,' functions/_lib/logos.js \
  && [ "$(printf '%s\n%s\n' "$UP" "$I18U" | grep -cF ' And your crew'"'"'s logo and TikTok account, if you add them.')" = 2 ] \
  && [ "$(printf '%s\n%s\n' "$UP" "$I18U" | grep -cF 'Once we approve your crew'"'"'s logo, it shows next to your crew'"'"'s name on sapu.earth.')" = 2 ] \
  && [ "$(printf '%s\n%s\n' "$UP" "$I18U" | grep -cF 'photos and your crew'"'"'s logo are saved again as JPEG on your phone.')" = 2 ] \
  && [ "$(printf '%s\n%s\n' "$UP" "$I18U" | grep -cF 'Your crew'"'"'s logo is deleted when we do not use it, when it waits 90 days without our check, when a newer one replaces it, and when we stop working together.')" = 2 ] \
  && echo "$I18U" | grep -qF ' Juga logo dan akun TikTok kru kamu, kalau kamu menambahkannya.' && echo "$I18U" | grep -qF 'Setelah kami setujui, logo kru kamu tampil di samping nama kru kamu di sapu.earth.' \
  && echo "$I18U" | grep -qF 'foto dan logo kru kamu disimpan ulang sebagai JPEG di HP kamu.' && echo "$I18U" | grep -qF 'kalau sudah 90 hari menunggu tanpa kami cek' \
  && [ "$(printf '%s\n%s\n' "$AP" "$I18A" | grep -cF 'up to 3 photos, your crew'"'"'s logo if you add one,')" = 2 ] \
  && [ "$(printf '%s\n%s\n' "$AP" "$I18A" | grep -cF 'and if we work together, to show your crew on sapu.earth from the first day: its name, country and logo in the list of crews at sapu.earth/crews, and on its public page also one of the links you gave us.')" = 2 ] \
  && [ "$(printf '%s\n%s\n' "$AP" "$I18A" | grep -cF 'and so is your crew'"'"'s logo, unless we work together and show it on sapu.earth')" = 2 ] \
  && echo "$I18A" | grep -qF 'logo kru kamu kalau kamu menambahkannya' \
  && echo "$I18A" | grep -qF 'untuk menampilkan kru kamu di sapu.earth sejak hari pertama: nama, negara, dan logonya di daftar kru di sapu.earth/crews, dan di halaman publiknya juga salah satu link yang kamu berikan.' \
  && ok "both crew notices name the logo (EN on the page and in the script, ID in the script), the application notice says the crew shows on sapu.earth from the first day (its name, country and logo in the list of crews, one of its links on its public page), and the upload notice's 90 days are LOGO.reviewDays" \
  || bad "privacy notices: logos" ""
VN=$(echo "$IM" | sed -n '/<section class="panel" id="privacy">/,/<\/section>/p')
echo "$VN" | grep -q 'PRIVACY FOR VISITORS' && echo "$VN" | grep -q 'Sapu Earth is run by Marcus Pousette in Innsbruck, Austria' \
  && echo "$VN" | grep -q 'href="mailto:hello@sapu.earth"' && echo "$VN" | grep -q 'Cloudflare hosts this site for us, as our processor' \
  && echo "$VN" | grep -q 'receive your internet address (IP address)' && echo "$VN" | grep -q 'counts the requests from each internet address' \
  && echo "$VN" | grep -q 'never store your internet address' && echo "$VN" | grep -q 'This site sets no cookies' \
  && echo "$VN" | grep -qF 'GDPR Art. 6(1)(f)' && echo "$VN" | grep -q 'may be outside the EU' \
  && echo "$VN" | grep -q 'object to this processing' && echo "$VN" | grep -q 'href="https://www.dsb.gv.at/"' \
  && ok "/impressum/#privacy tells visitors who runs the site, Cloudflare as processor, the IP and the flood rule, no cookies, the legal basis, where and their rights" \
  || bad "/impressum/ visitor notice" "$(echo "$VN" | head -5)"
echo "$VN" | grep -qF 'the pages load nothing from other companies, except satellite pictures when you zoom in far on the globe (below).' \
  && echo "$VN" | grep -qF 'when you zoom in far on the globe on the homepage, or tap SEE THE SPOT ON SATELLITE' \
  && echo "$VN" | grep -qF 'EOX IT Services GmbH in Vienna, Austria' && echo "$VN" | grep -qF 'receives your internet address' \
  && echo "$VN" | grep -qF 'Nothing loads from EOX before you zoom in that far' \
  && echo "$VN" | grep -qF 'our legitimate interest in showing you the places you zoom in to (GDPR Art. 6(1)(f))' \
  && ok "/impressum/#privacy says satellite pictures load from EOX in Vienna when the visitor zooms in far, what EOX then receives and the legal basis" || bad "/impressum/ visitor notice: satellite map" ""
echo "$IM" | grep -q '<a class="b b-ghost" href="#privacy">Privacy notice for visitors</a>' \
  && echo "$IM" | grep -q '<a class="b b-ghost" href="/upload/#privacy">Privacy notice for crew uploads</a>' \
  && echo "$IM" | grep -q '<a class="b b-ghost" href="/apply/#privacy">Privacy notice for crew applications</a>' \
  && ok "/impressum/ links the notices for visitors, crew uploads and crew applications" || bad "/impressum/ privacy links" ""
echo "$VN" | grep -q 'want it taken down, email <a href="mailto:hello@sapu.earth">' && echo "$VN" | grep -q 'href="/upload/#privacy">notice for crew uploads</a>' \
  && ok "the visitor notice tells anyone shown in a photo how to have it taken down" || bad "/impressum/ take-down line" ""
DASHES=$(printf '\342\200\223|\342\200\224') # en dash | em dash, as UTF-8 bytes
printf '%s\n%s\n' "$VN" "$(echo "$UP" | sed -n '/<details class="privacy" id="privacy">/,/<\/details>/p')" | grep -qE "$DASHES" \
  && bad "a privacy notice has an em or en dash" "" || ok "the visitor and upload notices have no em or en dash"
# Cloudflare's safeguards for servers outside the EU, in all three notices (EN and ID where there are two).
[ "$(echo "$I18U" | grep -c 'EU-US Data Privacy Framework')" = 2 ] && [ "$(echo "$I18A" | grep -c 'EU-US Data Privacy Framework')" = 2 ] \
  && echo "$VN" | grep -q 'certified under the EU-US Data Privacy Framework and uses the EU standard contractual clauses' \
  && ok "all three notices name Cloudflare's safeguards: the Data Privacy Framework and the standard contractual clauses" || bad "transfer safeguards" ""
# Marketing: both consent boxes, in both languages and on the page, and the notice says how.
[ "$(echo "$I18U" | grep -cF "on social media and in Sapu Earth's marketing")" = 2 ] && [ "$(echo "$I18U" | grep -cF 'di media sosial, dan di promosi Sapu Earth')" = 2 ] \
  && [ "$(echo "$UP" | grep -cF "on social media and in Sapu Earth's marketing")" = 2 ] && [ "$(echo "$I18U" | grep -cF 'to show and promote its work.')" = 2 ] \
  && ok "both consent boxes cover marketing (use, edit, share), in English and Indonesian" || bad "consent boxes and marketing" ""
# The notice's numbers are the code's: loose files, unfunded missions and the trim of private details.
grep -qF 'orphanHours: 48,' functions/_lib/util.js && grep -qF 'privateDays: 90,' functions/_lib/util.js && grep -qF 'expireDays: 28,' functions/_lib/missions.js \
  && echo "$I18U" | grep -qF 'never send are deleted after 48 hours.' && echo "$I18U" | grep -qF 'after 28 days waiting for us, or after 28 days on sapu.earth.' \
  && echo "$I18U" | grep -qF '90 days after we decide on a cleanup, or after a mission is done' && echo "$I18U" | grep -qF '90 hari setelah kami memutuskan sebuah aksi bersih' \
  && grep -qF '["private details", trimPrivate, never],' functions/api/housekeeping.js \
  && ok "the upload notice's 48 hours, 28 days and 90 days are the code's, and the housekeeping runs the 90-day trim" || bad "notice numbers vs code" ""
curl -s $B/ | grep -qF '<a href="/impressum/">IMPRESSUM</a> · <a href="/impressum/#privacy">PRIVACY</a>' \
  && ok "the homepage footer links the visitor notice as PRIVACY" || bad "homepage privacy link" ""
# Post links (docs/upload-flow.md, Post links and thanks), run in node: the post link block is the same in upload.js and
# functions/_lib/social.js (leading spaces aside), and both copies read 43 pasted links as they should: the stored form,
# a short link, or nothing. Every stored form passes the homepage's IG_POST or TT_POST and /admin/'s POST_URL_RE, the
# TikTok account comes in lower case, and /admin/'s openable takes only https on Instagram or TikTok (www., m. or bare)
# and TikTok's short links, a bare paste with https:// in front. The housekeeping's check for the missing tables knows
# D1's error for each of the four.
printf '%s' "$UJ" > "$T/pl-u.js"; printf '%s' "$SJ" > "$T/pl-app.js"; printf '%s' "$AJ" > "$T/pl-admin.js"
PLN=$(node -e '
const fs = require("fs");
const [u, app, adm] = process.argv.slice(1).map((f) => fs.readFileSync(f, "utf8"));
const lib = fs.readFileSync("functions/_lib/social.js", "utf8");
const cut = (s) => { const a = s.indexOf("// ---------- post links: the same block"), b = s.indexOf("// ---------- end of the post link block ----------");
  if (a < 0 || b < a) throw new Error("no post link block"); return s.slice(a, b); };
const flat = (s) => s.split("\n").map((l) => l.replace(/^ +/, "")).join("\n");
const bad = [];
if (flat(cut(u)) !== flat(cut(lib))) bad.push("the two blocks differ");
const load = (s) => new Function(cut(s) + "\nreturn { POST_MAX, postLink };")();
const line = (s, re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const R = new Function(line(app, /^ *const IG_POST = .*$/m) + "\n" + line(app, /^ *const TT_POST = .*$/m) + "\n" + line(adm, /^ *const POST_URL_RE = .*$/m) +
  "\n" + line(adm, /^ *const OPENABLE_HOST = .*$/m) + "\n" + adm.slice(adm.indexOf("  const openable = (v) => {"), adm.indexOf("\n  };", adm.indexOf("  const openable = (v) => {")) + 5) +
  "\nreturn { IG_POST, TT_POST, POST_URL_RE, openable };")();
const ig = "https://www.instagram.com/p/DAbc123xyz/", reel = "https://www.instagram.com/reel/C9xY_z-12/", tts = "https://www.tiktok.com/@sapu.earth/video/7312345678901234567";
const cases = [
  [ig, ig], [ig + "?igsh=MWZ0aGs4bXk=", ig], ["https://instagram.com/reel/C9xY_z-12/", reel], ["https://m.instagram.com/reels/C9xY_z-12", reel],
  ["https://www.instagram.com/sapu.earth/p/DAbc123xyz/", ig], [tts + "?is_from_webapp=1&sender_device=pc", tts],
  ["https://m.tiktok.com/@kru_bersih/photo/7312345678901234567/", "https://www.tiktok.com/@kru_bersih/photo/7312345678901234567"],
  ["  " + ig + "  ", ig], ["HTTPS://WWW.INSTAGRAM.COM/p/DAbc123xyz/", ig], [ig + "#comments", ig], ["www.instagram.com/p/DAbc123xyz/", ig],
  ["instagram.com/reel/C9xY_z-12/?igsh=abc", reel], ["tiktok.com/@sapu.earth/video/7312345678901234567", tts],
  ["https://vt.tiktok.com/ZSabc123/", "short"], ["https://vm.tiktok.com/ZMabc123/", "short"], ["vt.tiktok.com/ZSabc123/", "short"],
  ["https://www.tiktok.com/t/ZTabc123/", "short"], ["https://www.instagram.com/share/BAabc123", "short"], ["https://instagr.am/p/DAbc123xyz/", "short"],
  ["http://www.instagram.com/p/DAbc123xyz/", null], ["https://www.instagram.com.evil.example/p/DAbc123xyz/", null],
  ["www.instagram.com.evil.example/p/DAbc123xyz/", null], ["https://evilinstagram.com/p/DAbc123xyz/", null], ["https://www.instagram.com/sapu.earth/", null],
  ["https://www.instagram.com/stories/sapu.earth/3312345678901234567/", null], ["https://www.tiktok.com/@sapu.earth", null], ["javascript:alert(1)", null],
  ["data:text/html,hi", null], [ig + " look at this", null], ["https://user:pw@www.instagram.com/p/DAbc123xyz/", null],
  ["https://www.instagram.com:444/p/DAbc123xyz/", null], ["www.instagram.com:444/p/DAbc123xyz/", null], ["https://www.tiktok.com/@sapu.earth/video/abc", null],
  ["https://www.instagram.com/p/" + "a".repeat(290) + "/", null], ["https://xn--instagram-9db.com/p/DAbc123xyz/", null],
  ["https://www.instagram.com/tv/CAbc12345/", null], [null, null], ["", null], ["https://www.instagram.com/p/DAb%3Cscript/", null],
  ["https://www.instagram.com./p/DAbc123xyz/", null], ["https://www.instagram.com/p/DAbc123xyz/c/17890000000000000/", null],
  ["//www.instagram.com/p/DAbc123xyz/", null], ["https://m.tiktok.com/v/7312345678901234567.html", null],
];
for (const [name, s] of [["upload.js", u], ["social.js", lib]]) {
  const P = load(s);
  if (P.POST_MAX !== 300) bad.push(name + " POST_MAX");
  for (const [inp, want] of cases) {
    const r = P.postLink(inp), got = r === null ? null : r.short ? "short" : r.url;
    if (got !== want) bad.push(name + " " + JSON.stringify(inp) + " -> " + JSON.stringify(got));
    if (r && r.url && !(R.IG_POST.test(r.url) || R.TT_POST.test(r.url))) bad.push("app.js refuses " + r.url);
    if (r && r.url && !R.POST_URL_RE.test(r.url)) bad.push("admin.js refuses " + r.url);
  }
  const acc = P.postLink("https://www.tiktok.com/@Sapu.Earth/video/7312345678901234567");
  if (!acc || acc.account !== "sapu.earth" || acc.site !== "tiktok") bad.push(name + " TikTok account " + JSON.stringify(acc));
  if (P.postLink(ig).account !== null) bad.push(name + " Instagram account");
}
const op = [["https://www.instagram.com/p/DAbc123xyz/", "https://www.instagram.com/p/DAbc123xyz/"], ["instagram.com/reel/C9xY_z-12/", "https://instagram.com/reel/C9xY_z-12/"],
  ["vt.tiktok.com/ZSabc123/", "https://vt.tiktok.com/ZSabc123/"], ["https://m.tiktok.com/@a.b/video/12345678", "https://m.tiktok.com/@a.b/video/12345678"],
  ["http://www.instagram.com/p/DAbc123xyz/", ""], ["https://user:pw@www.instagram.com/p/DAbc123xyz/", ""], ["https://www.instagram.com:444/p/DAbc123xyz/", ""],
  ["https://evil.example/", ""], ["javascript:alert(1)", ""], ["https://www.instagram.com.evil.example/p/x", ""], ["", ""], ["instagr.am/p/DAbc123xyz/", ""]];
for (const [inp, want] of op) if (R.openable(inp) !== want) bad.push("openable " + JSON.stringify(inp) + " -> " + JSON.stringify(R.openable(inp)));
const S = fs.readFileSync("functions/_lib/social.js", "utf8");
const no = new Function(S.slice(S.indexOf("export function noSocialTables"), S.indexOf("// Runs fn(true)")).replace("export ", "") + "\nreturn noSocialTables;")();
for (const t of ["post_links", "thanks", "thanks_days", "thanks_site"]) if (!no(new Error("D1_ERROR: no such table: " + t + ": SQLITE_ERROR"))) bad.push("noSocialTables " + t);
if (no(new Error("D1_ERROR: no such table: logos: SQLITE_ERROR")) || no(new Error("no such table: post_links_old"))) bad.push("noSocialTables too wide");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + cases.length);
' "$T/pl-u.js" "$T/pl-app.js" "$T/pl-admin.js" 2>&1)
check "the post link block is the same in upload.js and functions/_lib/social.js and reads 43 pasted links right in both; every stored form passes app.js and admin.js; openable; noSocialTables (node)" "$PLN" "ok 43"
# The mission money block (splitOf: a stored price read back as the pay for each person and the other costs) is the same
# in upload.js, site/app.js, admin.js and functions/_lib/missions.js (leading spaces aside), and the server's copy, the
# one /missions and /m/<no> import, reads an even split, mission #2's one total, a crew pay above the price and a price
# without a crew size as the pages do.
MMB=$(node -e '
const fs = require("fs");
const files = process.argv.slice(1).concat("functions/_lib/missions.js");
const cut = (s) => { const a = s.indexOf("// ---------- mission money: the same block"), b = s.indexOf("// ---------- end of the mission money block ----------");
  if (a < 0 || b < a) throw new Error("no mission money block"); return s.slice(a, b); };
const flat = (s) => s.split("\n").map((l) => l.replace(/^ +/, "")).join("\n");
const blocks = files.map((f) => flat(cut(fs.readFileSync(f, "utf8"))));
const bad = files.filter((f, i) => blocks[i] !== blocks[3]).map((f) => f + " differs from the server copy");
const splitOf = new Function(blocks[3] + "\nreturn splitOf;")();
const cases = [[splitOf(3000000, 1500000, 15), { each: 100000, other: 1500000, exact: true }], [splitOf(3000000, 100000, 15), { each: 6666.67, other: 2900000, exact: false }],
  [splitOf(1000, 1001, 4), null], [splitOf(1000, 600, null), { each: null, other: 400, exact: false }]];
cases.forEach(([got, want], i) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push("case " + i + ": " + JSON.stringify(got)); });
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + files.length);
' "$T/crew.js" "$T/pl-app.js" "$T/crew-admin.js" 2>&1)
check "the mission money block is the same in upload.js, site/app.js, admin.js and functions/_lib/missions.js, and the server copy reads an even split, one total, a crew pay above the price and no crew size (node)" "$MMB" "ok 4"
# The receipt post's comments link, run in node with site/app.js's own socialOf and commentsRow: only a real receipt's
# social in a stored form, a plain link in a new tab with no referrer, nofollow ugc on a crew's post, the arrow hidden from
# screen readers, and each line as written.
PLC=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  const IG_POST = "), b = s.indexOf("\n  };", s.indexOf("  const commentsRow = (e) => {"));
const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "\x27": "&#39;" };
const escapeHTML = (v) => String(v ?? "").replace(/[&<>"\x27]/g, (c) => ESC[c]);
const C = new Function("escapeHTML", s.slice(a, b + 5) + "\nreturn commentsRow;")(escapeHTML);
const ig = "https://www.instagram.com/p/DAbc123xyz/", tt = "https://www.tiktok.com/@kru_bersih/video/7312345678901234567";
const want = [
  [{ fromApi: true, social: { site: "instagram", url: ig, by: "sapu" } }, "<div class=\"post-comments\"><a class=\"post-cbtn\" href=\"" + ig + "\" target=\"_blank\" rel=\"noopener noreferrer\">COMMENTS ON INSTAGRAM<span aria-hidden=\"true\"> ↗</span></a><p class=\"post-cline\">// on our instagram post. tap to read the comments there or write one.</p></div>"],
  [{ fromApi: true, social: { site: "tiktok", url: tt, by: "crew" } }, "<div class=\"post-comments\"><a class=\"post-cbtn\" href=\"" + tt + "\" target=\"_blank\" rel=\"noopener noreferrer nofollow ugc\">COMMENTS ON TIKTOK<span aria-hidden=\"true\"> ↗</span></a><p class=\"post-cline\">// on the crew&#39;s own tiktok post. tap to read the comments there or write one.</p></div>"],
  [{ demo: true, social: { site: "instagram", url: ig, by: "sapu" } }, ""],
  [{ fromApi: true, social: null }, ""], [{ fromApi: true }, ""],
  [{ fromApi: true, social: { site: "instagram", url: "javascript:alert(1)", by: "sapu" } }, ""],
  [{ fromApi: true, social: { site: "instagram", url: tt, by: "crew" } }, ""],
  [{ fromApi: true, social: { site: "tiktok", url: ig + "\" onclick=\"x", by: "sapu" } }, ""],
  [{ fromApi: true, social: { site: "instagram", url: ig, by: "someone" } }, ""],
];
const bad = want.map(([e, w], i) => [i, C(e), w]).filter(([, g, w]) => g !== w).map(([i, g]) => i + ": " + g);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + want.length);
' "$T/pl-app.js" 2>&1)
check "the receipt post's comments link (site/app.js commentsRow, node): ours and a crew's, never on a sample, no social, a script link, the wrong site, a quote or an unknown by" "$PLC" "ok 9"
OPOST=$(echo "$SJ" | sed -n '/^  function openPost(e) {/,/^  }$/p')
NL=$(echo "$OPOST" | grep -nF '<p class="post-notes">' | cut -d: -f1); CL=$(echo "$OPOST" | grep -nF '${commentsRow(e)}' | cut -d: -f1); SL=$(echo "$OPOST" | grep -nF '${satRow(e.location?.lat, e.location?.lng, spotsE(e))}' | cut -d: -f1)
[ -n "$NL" ] && [ -n "$CL" ] && [ -n "$SL" ] && [ "$((NL + 1))" = "$CL" ] && [ "$((CL + 1))" = "$SL" ] && [ "$(echo "$SJ" | grep -cF 'commentsRow(e)')" = 1 ] \
  && echo "$SJ" | grep -qF 'const IG_POST = /^https:\/\/www\.instagram\.com\/(?:p|reel)\/[A-Za-z0-9_-]{5,40}\/$/;' \
  && echo "$SJ" | grep -qF 'const TT_POST = /^https:\/\/www\.tiktok\.com\/@[A-Za-z0-9._]{2,24}\/(?:video|photo)\/\d{8,25}$/;' \
  && echo "$SC" | grep -qF '.post-cbtn { display: inline-flex; align-items: center; justify-content: center; min-height: 44px; max-width: 100%;' \
  && echo "$SC" | grep -qF '.post-cline { font-size: 11px; line-height: 1.45; color: var(--dim); padding: 6px 0 0; overflow-wrap: anywhere; }' \
  && ok "COMMENTS ON INSTAGRAM sits in the receipt post right after the notes and before SEE THE SPOT ON SATELLITE, never on a card, at least 44 px tall" \
  || bad "the receipt post's comments link (app.js, styles.css)" "$NL $CL $SL"
# The crew page's link field: in the cleanup form right after the notes and before the message to Sapu Earth, hidden
# until GET /api/partner says post links are on; its label, hint and rules read with it; the line under it says how the
# link is stored or why it is not taken. A pasted link is unsent work: it stays in the draft until the cleanup is sent.
UPC=$(echo "$UP" | sed -n '/<form id="form"/,/<\/form>/p')
FP=$(echo "$UPC" | sed -n '/<div class="field" id="f-post" hidden>/,/<\/div>/p')
LN=$(echo "$UPC" | grep -n 'name="notes"' | cut -d: -f1); LP=$(echo "$UPC" | grep -n 'id="f-post"' | cut -d: -f1); LM=$(echo "$UPC" | grep -n 'name="private_note"' | cut -d: -f1)
[ "$(echo "$FP" | grep -oE 'id="(postLab|postHint|postRules|postUrl|postEcho)"' | tr '\n' ' ')" = 'id="postLab" id="postHint" id="postRules" id="postUrl" id="postEcho" ' ] \
  && echo "$FP" | grep -qF '<span id="postLab" data-i18n="post">Link to your post about this cleanup (optional)</span>' \
  && echo "$FP" | grep -qF '<p class="hint" id="postHint" data-i18n="post_hint">' && echo "$FP" | grep -qF '<p class="hint" id="postRules" data-i18n="post_rules">' \
  && echo "$FP" | grep -qF '<input type="url" name="post_url" id="postUrl" inputmode="url" maxlength="300" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="https://www.instagram.com/p/..." aria-labelledby="postLab" aria-describedby="postHint postRules postEcho">' \
  && echo "$FP" | grep -qF '<small class="echo" id="postEcho" data-echo="post_url" aria-live="polite"></small>' \
  && [ -n "$LN" ] && [ -n "$LP" ] && [ -n "$LM" ] && [ "$LN" -lt "$LP" ] && [ "$LP" -lt "$LM" ] \
  && echo "$UJ" | grep -qF '$("#f-post").hidden = partner.post_links_enabled !== true;' \
  && echo "$UJ" | grep -qF '"crew_each_local", "other_local", "notes", "post_url", "private_note", "mission_id", ...SPOT_DAYS];' \
  && echo "$UJ" | grep -qF 'const C_ALWAYS = ["kg", "sacks", "hours", "disposal", "crew_each_local", "other_local", "notes", "post_url", "private_note"];' \
  && echo "$UJ" | grep -qF '"currency", "currency_other", "crew_each_local", "other_local", "private_note"];' \
  && echo "$UJ" | grep -qF 'const M_ALWAYS = ["place_name", "task", "crew_each_local", "other_local", "private_note"];' \
  && echo "$UJ" | grep -qF 'if (postRaw && !(post && post.url)) { echoPost(); bad("f-post", ""); }' && echo "$UJ" | grep -qF 'if (post && post.url) data.post_url = post.url;' \
  && echo "$UJ" | grep -qF 'if (ev.target.name === "post_url") echoPost();' && [ "$(echo "$UJ" | grep -cE '^ +echoPost\(\);')" = 3 ] \
  && echo "$UJ" | grep -qF 'if (body && body.code === "post_link") throw new Fatal(body.field === "post_url" ? "e_post_link" : "e_rejected", "f-post");' \
  && grep -qF '#f-post .echo { overflow-wrap: anywhere; }' site/forms.css && grep -qF '#f-post .hint { margin: 0 0 6px; }' site/forms.css \
  && ok "the crew page's post link field: after the notes and before the message to Sapu Earth, hidden until post links are on, read with its hint and rules, kept in the draft, checked with the block before SEND (marked, its line says why), only a stored form sent" \
  || bad "the crew page's post link field" "$LN $LP $LM $FP"
PLX=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8"), page = require("fs").readFileSync(process.argv[2], "utf8");
const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const keys = ["post", "post_hint", "post_rules", "post_ok", "e_post_link", "e_post_short"];
const bad = [];
for (const l of ["en", "id"]) for (const k of keys) if (typeof T[l][k] !== "string" || !T[l][k] || /[\u2013\u2014]/.test(T[l][k])) bad.push(l + " " + k);
const html = (k) => { const m = page.match(new RegExp("data-i18n=\"" + k + "\">([^<]*)<")); return m ? m[1] : null; };
for (const k of ["post", "post_hint", "post_rules"]) if (html(k) !== T.en[k]) bad.push("page " + k);
if (T.en.post_ok !== "Link to your {site} post: {link}" || T.id.post_ok !== "Link ke postingan {site} kamu: {link}") bad.push("post_ok");
if (!T.en.post_hint.includes("TikTok: the app copies a short link we cannot check, so paste it into your browser\x27s address bar first, then copy the full address from there.")) bad.push("en hint");
if (!T.id.post_hint.includes("supaya laporannya bisa menampilkan link ke postingan kamu") || !T.id.post_hint.includes("jadi tempel dulu link itu di kolom alamat browser, lalu salin alamat lengkapnya dari sana.") || /menautkan/.test(T.id.post_hint)) bad.push("id hint");
// The short-link line names both sites, since postLink calls instagr.am and instagram.com/share/ short too.
if (!T.en.e_post_short.startsWith("Short links (like vt.tiktok.com or instagram.com/share/) cannot be checked. Paste the link into your browser\x27s address bar,")) bad.push("en short");
if (!T.id.e_post_short.startsWith("Link pendek (seperti vt.tiktok.com atau instagram.com/share/) tidak bisa kami cek. Tempel link-nya di kolom alamat browser,")) bad.push("id short");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/crew.js" "$T/crew.html" 2>&1)
check "the crew page's post link texts: post, post_hint, post_rules, post_ok, e_post_link and e_post_short in EN and ID, no dashes, the page's English the script's (node)" "$PLX" ok
# /admin/: THE CREW'S POST on PENDING, COMMENTS LINK on APPROVED, and what UNPUBLISH and DEACTIVATE say about the posts.
PLA=""
for t in 'const POST_URL_RE = /^https:\/\/www\.(?:instagram\.com\/(?:p|reel)\/[A-Za-z0-9_-]{5,40}\/|tiktok\.com\/@[A-Za-z0-9._]{2,24}\/(?:video|photo)\/\d{8,25})$/;' \
         '<div class="panel-title">THE CREW'"'"'S POST</div>' \
         'The crew linked its own post on ${site}. Once you approve, the receipt'"'"'s COMMENTS ON ${site.toUpperCase()} button leads to it, unless you add your own post on the APPROVED card. Open it first: remove the link if the post asks for money, shows people who did not agree, or is not about this cleanup, and tell the crew why on WhatsApp.' \
         'Take the link to the crew'"'"'s post off this cleanup? It cannot be added back.' \
         'Removed. The receipt will not link the crew'"'"'s post. Tell the crew why on WhatsApp.' \
         '<div class="panel-title">COMMENTS LINK</div>' '<label class="field wide"><span>Your post on Instagram or TikTok</span>' \
         '<p class="hint am-postlink">${theirs ? `The crew'"'"'s post: <a href="${esc(theirs)}" target="_blank" rel="noopener noreferrer">${esc(postHost(theirs))} ↗</a>` : "The crew sent no post link."}</p>' \
         'Paste a full https:// link to the post first.' 'Paste the link to your post first.' \
         'Take the link to your post off this receipt? The post itself stays where it is.' 'Take the link to the crew'"'"'s post off this receipt? It cannot be added back.' \
         'Your post link was taken off the receipt.' 'The crew'"'"'s post link was taken off the receipt. Tell the crew why on WhatsApp.' \
         'Saved. The receipt links your post on ${siteName(r.post_links.sapu)}. Public pages catch up within 5 minutes.' \
         'Paste the link to your own post. Instagram: Share, then Copy link (instagram.com/p/... or instagram.com/reel/...). TikTok: the address of the video on tiktok.com in a browser (tiktok.com/@sapu.earth/video/...). The TikTok app copies a short link, which is refused because nobody can check where it leads; OPEN POST opens it, so you can copy the full address. An Instagram link does not say whose post it is, so tap OPEN POST before SAVE. The receipt shows your post when there is one, else the crew'"'"'s. Public pages catch up within 5 minutes.' \
         '(mine ? ` Then delete your post on ${siteName(mine)} too: ${mine}` : " If you posted it on Instagram or TikTok, delete that post there too.") +' \
         '(theirs ? " The crew'"'"'s own post stays on its account: if a person asked to be taken down, ask the crew on WhatsApp to delete it too." : ""))) return;' \
         '(mine ? ` Now delete your post on ${siteName(mine)}: ${mine}` : " If you posted it on Instagram or TikTok, delete that post there too.") +' \
         '(theirs ? " If a person asked to be taken down, ask the crew to delete its own post too." : ""));' \
         '" Links to their own posts on Instagram or TikTok come off their receipts.";' \
         '? ` Links to their own posts came off ${Number(r.post_links_removed)} receipt${Number(r.post_links_removed) === 1 ? "" : "s"}.` : ""));' \
         'if (u) window.open(u, "_blank", "noopener,noreferrer");'; do
  echo "$AJ" | grep -qF -- "$t" || PLA="$PLA [$t]"
done
[ -z "$PLA" ] && grep -qF '.am-postbox { margin-top: 12px; padding: 10px; border: 2px dashed var(--ink); background: #fff; overflow-wrap: anywhere; }' admin/admin.css \
  && ok "/admin/: THE CREW'S POST on PENDING with REMOVE LINK, COMMENTS LINK on APPROVED (SAVE, OPEN POST, REMOVE, REMOVE CREW LINK) with their questions, hints and answers, and UNPUBLISH and DEACTIVATE name the posts on Instagram and TikTok" \
  || bad "admin.js post link texts" "$PLA"
# /impressum/: how to report illegal content (EU Digital Services Act), and the visitor notice on post links and emails.
DSA="Think something on sapu.earth is illegal? Email <a href=\"mailto:hello@sapu.earth\">hello@sapu.earth</a> with the link to it and why you think it is illegal, and say that what you write is true as far as you know. You may add your name, but you do not have to. We confirm that your report arrived and tell you what we decided. How we handle your email is in the privacy notice below. This address is also our contact point for authorities and users under the EU Digital Services Act. Crews can also write to us in their WhatsApp chat with Sapu Earth. We answer in English or German."
REP=$(echo "$IM" | sed -n '/<div class="field" id="report">/,/<\/div>/p')
echo "$REP" | grep -qF '<span>Report illegal content</span>' && echo "$REP" | grep -qF "<p>$DSA</p>" \
  && [ "$(echo "$IM" | grep -n 'id="report"' | cut -d: -f1)" -gt "$(echo "$IM" | grep -n '<span>Contact</span>' | cut -d: -f1)" ] \
  && [ "$(echo "$IM" | grep -n 'id="report"' | cut -d: -f1)" -lt "$(echo "$IM" | grep -n '<span>What this site is</span>' | cut -d: -f1)" ] \
  && ! echo "$REP" | grep -qE "$DASHES" && grep -qF '#report a { color: var(--ink);' site/forms.css \
  && ok "/impressum/ says how to report illegal content right after the contact: by email, the link and why, in good faith, a name optional, a confirmation and the decision, the privacy notice, the DSA contact point, the crews' WhatsApp chat, last: in English or German" \
  || bad "/impressum/ report paragraph" "$REP"
echo "$VN" | grep -qF "<li><b>Instagram and TikTok:</b> a receipt may link to a post about it on Instagram or TikTok, ours or the crew's own, where people can comment, and a crew's page and the list of crews may link to the crew's own TikTok account. Each is a plain link: nothing loads from Instagram or TikTok until you tap it, and we never show their posts, comments or counts on sapu.earth. After the tap you are on their site or in their app, where their own privacy notices apply. These links do not tell them which of our pages you came from.</li>" \
  && echo "$VN" | grep -qF '<li><b>Emails and reports:</b> if you email <a href="mailto:hello@sapu.earth">hello@sapu.earth</a>, for example to report something illegal, we use your email address, your name if you give it, and what you write only to handle it and to answer you. If we take something down after your report, we tell the crew why, but not who reported it. Emails reach us through Cloudflare (its Email Routing) and are kept in our mailbox at Google. We delete them at the latest one year after the matter is closed. A report a crew sends in its WhatsApp chat with us is used the same way, only to handle it and to answer, and we delete it from that chat at the latest one year after the matter is closed. Legal basis: for a report, our legal duty to handle it (GDPR Art. 6(1)(c), with Art. 16 of the EU Digital Services Act); otherwise our legitimate interest in answering you (GDPR Art. 6(1)(f)).</li>' \
  && echo "$VN" | grep -qF 'Cloudflare is certified under the EU-US Data Privacy Framework and uses the EU standard contractual clauses for other countries. Our mailbox is with Google, which may also use servers outside the EU and is certified under the same framework.</li>' \
  && [ "$(echo "$VN" | grep -n '<b>Satellite map:</b>' | cut -d: -f1)" -lt "$(echo "$VN" | grep -n '<b>Instagram and TikTok:</b>' | cut -d: -f1)" ] \
  && [ "$(echo "$VN" | grep -n '<b>Shown in a photo or video?</b>' | cut -d: -f1)" -lt "$(echo "$VN" | grep -n '<b>Emails and reports:</b>' | cut -d: -f1)" ] \
  && [ "$(echo "$VN" | grep -n '<b>Emails and reports:</b>' | cut -d: -f1)" -lt "$(echo "$VN" | grep -n '<b>Why:</b>' | cut -d: -f1)" ] \
  && ok "/impressum/#privacy: Instagram and TikTok after the satellite map (a plain link, nothing loads before the tap), Emails and reports after the take-down line (purpose, the crew never learns who reported, Cloudflare Email Routing and Google, a year after the matter is closed, a report in a crew's WhatsApp chat the same way, the legal basis), and Where names the Google mailbox" \
  || bad "/impressum/ visitor notice: post links and emails" ""
# The upload notice: the link to the crew's post in what it sends, on its receipt, and when it goes (EN on the page and in
# the script, ID in the script); the sentence on the receipt comes right after the logo and TikTok sentences, before the
# list of crews.
PLV1="your notes, the link to your post about the cleanup on Instagram or TikTok if you add one, and your message to Sapu Earth."
PLV2="Once we approve your crew's logo, it shows next to your crew's name on sapu.earth. Once we approve your crew's TikTok account, your crew's public page and the list of crews link to it. If you add the link to your post with a cleanup, its receipt can link to it, so people can comment there, unless we link our own post about the cleanup instead. Visitors can thank your crew with one tap under each receipt. The number of thanks shows on the receipt, on your crew's page and in the list of crews. Nobody signs in to do that, and we keep nothing about who tapped, so the counts cannot show who thanked. Your crew is also in the list of crews at sapu.earth/crews"
PLV3="when a newer one replaces it, and when we stop working together. Your crew's TikTok account is deleted when you remove it or another one replaces it, when we do not use it, and when we stop working together. The link to your post is deleted when we take it off the receipt, with its cleanup when we do not approve it or take it off the site, and when we stop working together. The thanks stay with their receipt, but we may take off the thanks of a day that looks inflated. We keep the rest"
PLI1="catatan kamu, link postingan kamu tentang aksi bersih itu di Instagram atau TikTok kalau kamu menambahkannya, dan pesan kamu untuk Sapu Earth."
PLI2="Setelah kami setujui, logo kru kamu tampil di samping nama kru kamu di sapu.earth. Setelah kami setujui juga, halaman publik kru kamu dan daftar kru menampilkan link ke akun TikTok kru kamu. Kalau kamu menambahkan link postingan kamu saat mengirim aksi bersih, laporannya bisa menampilkan link ke postingan itu, supaya orang bisa berkomentar di sana, kecuali kami menampilkan link ke postingan kami sendiri tentang aksi bersih itu. Pengunjung bisa berterima kasih kepada kru kamu dengan satu ketukan di setiap laporan. Jumlah ucapan terima kasihnya tampil di laporan itu, di halaman kru kamu, dan di daftar kru. Untuk itu tidak perlu masuk dengan akun, dan kami tidak menyimpan apa pun tentang siapa yang menekan, jadi jumlahnya tidak bisa menunjukkan siapa yang berterima kasih. Kru kamu juga ada di daftar kru di sapu.earth/crews"
PLI3="atau kalau kerja sama kita berhenti. Akun TikTok kru kamu dihapus kalau kamu menghapusnya atau akun lain menggantikannya, kalau tidak kami pakai, atau kalau kerja sama kita berhenti. Link postingan kamu dihapus kalau kami melepasnya dari laporan, bersama aksi bersihnya kalau tidak kami setujui atau kami turunkan dari situs, dan kalau kerja sama kita berhenti. Ucapan terima kasih tetap ada bersama laporannya, tapi kami bisa menghapus ucapan terima kasih dari satu hari yang jumlahnya tidak wajar. Sisanya"
n=0; for t in "$PLV1" "$PLV2" "$PLV3"; do [ "$(printf '%s\n%s\n' "$UP" "$I18U" | grep -cF -- "$t")" = 2 ] && n=$((n+1)); done
for t in "$PLI1" "$PLI2" "$PLI3"; do [ "$(echo "$I18U" | grep -cF -- "$t")" = 1 ] && n=$((n+1)); done
check "the upload notice names the link to the crew's post and the thanks: what it sends, that its receipt can link it and that visitors can thank (right after the logo and TikTok sentences, and that nobody can tell who thanked), and when the link is deleted and what happens to thanks (EN on the page and in the script, ID in the script)" "$n" 6
# Thanks on the homepage (site/app.js), run in node with its own thanksRow and thankedRow: SAY TERIMA KASIH (lang id or
# ms) or SAY THANK YOU on real receipts of active crews and on samples, the count only for a crew no longer active, the
# stamp for a tap made while the page is open, every line as written, and THANKED on a card only above 0, never on a
# sample. Then the rest by the text: where the button sits, the request, the answers, no device storage, the CSS.
TYN=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  const thankedHere = new Set();"), b = s.indexOf("\n", s.indexOf("? `<div class=\"r-thanked\">"));
const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "\x27": "&#39;" };
const escapeHTML = (v) => String(v ?? "").replace(/[&<>"\x27]/g, (c) => ESC[c]);
const cc = (e) => (/^[A-Z]{2}$/.test(e.location?.country || "") ? e.location.country : "??");
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? Number(v.toFixed(1)).toLocaleString("en") : "?");
const X = new Function("escapeHTML", "cc", "num", s.slice(a, b) + "\nreturn { thanksRow, thankedRow, thankedHere };")(escapeHTML, cc, num);
const ID = { country: "ID" }, MY = { country: "MY" }, PH = { country: "PH" }, page = "https://sapu.earth/p/kru";
const btn = (w, l, line) => "<div class=\"post-thanks\"><button type=\"button\" class=\"thanks-btn\">SAY <span lang=\"" + l + "\">" + w + "</span></button><p class=\"thanks-line\" role=\"status\">" + line + "</p></div>";
const tail = " the crew sees the count on its crew page.";
const want = [
  [{ demo: true, location: ID }, btn("TERIMA KASIH", "id", "// sample receipt: nothing is counted.")],
  [{ demo: true, location: PH, thanks: 9 }, btn("THANK YOU", "en", "// sample receipt: nothing is counted.")],
  [{ fromApi: true, id: "r1", location: ID, thanks: 46, provider: { page } }, btn("TERIMA KASIH", "id", "// thanked 46 times. terima kasih is thank you in indonesian." + tail)],
  [{ fromApi: true, id: "r2", location: MY, thanks: 0, provider: { page } }, btn("TERIMA KASIH", "ms", "// be the first to thank this crew. terima kasih is thank you in malay." + tail)],
  [{ fromApi: true, id: "r3", location: PH, thanks: 1, provider: { page } }, btn("THANK YOU", "en", "// thanked 1 time." + tail)],
  [{ fromApi: true, id: "r4", location: ID, thanks: 1234, provider: { page } }, btn("TERIMA KASIH", "id", "// thanked 1,234 times. terima kasih is thank you in indonesian." + tail)],
  [{ fromApi: true, id: "r5", location: ID, thanks: 46, provider: { page: null } }, "<div class=\"post-thanks\"><p class=\"thanks-line\">// thanked 46 times.</p></div>"],
  [{ fromApi: true, id: "r6", location: ID, thanks: 0, provider: { page: null } }, ""],
  [{ fromApi: true, id: "r7", location: ID, provider: { page } }, ""],
  [{ fromApi: true, id: "r8", location: ID, thanks: "46", provider: { page } }, ""],
  [{ location: ID, thanks: 46, provider: { page } }, ""],
];
const bad = want.map(([e, w], i) => [i, X.thanksRow(e), w]).filter(([, g, w]) => g !== w).map(([i, g]) => i + ": " + g);
X.thankedHere.add("r1");
const done = X.thanksRow({ fromApi: true, id: "r1", location: ID, thanks: 47, provider: { page } });
if (done !== "<div class=\"post-thanks\"><button type=\"button\" class=\"thanks-btn thanks-done\" aria-disabled=\"true\"><span lang=\"id\">TERIMA KASIH</span> ✓</button><p class=\"thanks-line\" role=\"status\">// counted. thanked 47 times so far." + tail + "</p></div>") bad.push("stamped: " + done);
const cards = [[{ fromApi: true, thanks: 46 }, "<div class=\"r-thanked\"><dt>THANKED</dt><dd>46 TIMES</dd></div>"], [{ fromApi: true, thanks: 1 }, "<div class=\"r-thanked\"><dt>THANKED</dt><dd>1 TIME</dd></div>"],
  [{ fromApi: true, thanks: 0 }, ""], [{ demo: true, fromApi: true, thanks: 5 }, ""], [{ thanks: 5 }, ""], [{ fromApi: true }, ""]];
for (const [e, w] of cards) if (X.thankedRow(e) !== w) bad.push("card " + JSON.stringify(e) + ": " + X.thankedRow(e));
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + (want.length + 1 + cards.length));
' "$T/pl-app.js" 2>&1)
check "the receipt post's thank-you button (site/app.js thanksRow and thankedRow, node): the words and lang per country, samples count nothing, a crew no longer active shows its count only, the stamp, every line, THANKED on a card only above 0" "$TYN" "ok 18"
OPOST=$(echo "$SJ" | sed -n '/^  function openPost(e) {/,/^  }$/p')
ML=$(echo "$OPOST" | grep -nF '<div class="post-media">' | cut -d: -f1); TL=$(echo "$OPOST" | grep -nF '${thanksRow(e)}' | cut -d: -f1); RL=$(echo "$OPOST" | grep -nF '<dl class="r-rows">' | cut -d: -f1)
TYX=""
[ -n "$ML" ] && [ -n "$TL" ] && [ -n "$RL" ] && [ "$((ML + 1))" = "$TL" ] && [ "$((TL + 1))" = "$RL" ] && [ "$(echo "$SJ" | grep -cF 'thanksRow(e)')" = 1 ] || TYX="$TYX [placement $ML $TL $RL]"
echo "$SJ" | grep -qF '${byRow(e)}${thankedRow(e)}' && [ "$(echo "$SJ" | grep -cF 'thankedRow(e)')" = 2 ] || TYX="$TYX [card]"
echo "$OPOST" | grep -qF 'overlay.querySelector(".thanks-btn")?.addEventListener("click", (ev) => sayThanks(e, ev.currentTarget));' || TYX="$TYX [handler]"
for t in 'r = await fetch("/api/thanks", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }), keepalive: true, cache: "no-store" });' \
         'btn.setAttribute("aria-disabled", "true");' 'if (btn.getAttribute("aria-disabled") === "true") return;' \
         'say("// sending…");' 'say("// today'"'"'s thanks are full. try again tomorrow.");' 'say("// this receipt is no longer on sapu.earth.");' \
         'if (r && r.status === 409 && body && body.code === "inactive") {' \
         'btn.remove(); say(e.thanks > 0 ? `// thanked ${times(e.thanks)}. this receipt takes no more thanks.` : "// this receipt takes no more thanks."); return;' \
         'say("// not sent. check your connection and tap again.");' 'say("// sample receipt: nothing is counted.");' \
         'e.thanks = Math.max(e.thanks || 0, body.thanks); // /api/events may be a minute old'; do
  echo "$SJ" | grep -qF -- "$t" || TYX="$TYX [$t]"
done
echo "$SJ" | grep -qE 'localStorage|sessionStorage|indexedDB|document\.cookie' && TYX="$TYX [device storage]"
TYC=$(echo "$SC" | sed -n '/^\/\* SAY TERIMA KASIH under the photos of a receipt post/,/^\.thanks-line /p')
echo "$TYC" | grep -qF '.thanks-btn { display: block; width: 100%; min-height: 44px;' && echo "$TYC" | grep -qF '.thanks-line { font-size: 11px;' \
  && echo "$TYC" | grep -qF 'border: 3px solid var(--clean); box-shadow: none; transform: rotate(-1deg); }' \
  && ! echo "$TYC" | sed 's#/\*.*##; s#.*\*/##' | grep -qE 'transition|animation' || TYX="$TYX [css]"
[ -z "$TYX" ] && ok "SAY TERIMA KASIH sits right under the photos of a receipt post and THANKED on its card; one POST /api/thanks (JSON, keepalive), the stamp keeps focus (aria-disabled), every answer's line, nothing saved on the device, at least 44 px and no animation" \
  || bad "the thank-you button (app.js, styles.css)" "$TYX"
# The wide post (site/app.js, the wide post's slides; styles.css, the wide post; docs/upload-flow.md, Homepage: the post on
# a wide screen). Its slides in node with site/app.js's own helpers: a cleanup starts with its first before and first after
# side by side (PHOTO SOON for a missing one), then every photo and video alone in the order of the day; a mission NOW 1/3
# to 3/3, then NOW · VIDEO; unsafe links and odd stages dropped or plain VIDEO; the dialog's markup (the paper first, one
# slide shown, videos preload none, photos lazy, the arrows only with two slides or more, the post's own links in the bar
# after the arrows, and no box for them when there are none).
WSL=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  // ---------- the wide post\x27s slides (pure; tests/e2e.sh runs this block in node) ----------");
const b = s.indexOf("  // ---------- end of the wide post\x27s slides ----------");
if (a < 0 || b < a) throw new Error("the block is missing");
const k = s.indexOf("  const safeSrc = (u) =>"), safe = s.slice(k, s.indexOf("\n", s.indexOf("\n", k) + 1));
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m, /^  const nowOf = .*$/m, /^  const nowVideoOf = .*$/m].map(line).join("\n");
const sp = s.slice(s.indexOf("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------"), s.indexOf("  // ---------- end of the spots ----------"));
const X = new Function(helpers + "\n" + safe + "\n" + sp + "\n" + s.slice(a, b) + "\nreturn { receiptSlides, missionSlides, wideHtml, videosIn };")();
const tags = (sl) => sl.map((x) => x.map((it) => it.tag + (it.video ? " [v]" : "") + (it.src ? "" : " [soon]")).join(" | "));
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const M = (k) => "/media/" + k.repeat(32).slice(0, 32);
const full = { id: "r1", fromApi: true, media: { before: [M("a"), M("b"), M("c")], after: [M("d"), M("e")], videos: [M("f"), M("1"), M("2")], video_stages: ["before", "after", null] },
  mission: { no: 8, now: [M("3"), M("4")], now_video: M("5") } };
eq("a full receipt", tags(X.receiptSlides(full)), ["BEFORE 1/3 | AFTER 1/2", "NOW 1/2 · MISSION #8", "NOW 2/2 · MISSION #8", "NOW · MISSION #8 · VIDEO [v]", "BEFORE 1/3", "BEFORE 2/3", "BEFORE 3/3", "BEFORE · VIDEO [v]", "AFTER 1/2", "AFTER 2/2", "AFTER · VIDEO [v]", "VIDEO [v]"]);
eq("its first pair", X.receiptSlides(full)[0].map((it) => it.src), [M("a"), M("d")]);
eq("one before, one after", tags(X.receiptSlides({ media: { before: [M("a")], after: [M("d")] } })), ["BEFORE | AFTER", "BEFORE", "AFTER"]);
eq("no before", tags(X.receiptSlides({ media: { before: [], after: [M("d")] } })), ["BEFORE [soon] | AFTER", "AFTER"]);
eq("no media", tags(X.receiptSlides({})), ["BEFORE [soon] | AFTER [soon]"]);
eq("unsafe links, odd stages, a mission without a number", tags(X.receiptSlides({ media: { before: ["javascript:alert(1)", M("a"), "/media/x\"y"], after: [M("d")], videos: ["https://evil.example/v.mp4\"", M("f")], video_stages: ["BEFORE", { x: 1 }] }, mission: { no: "8", now: [M("3")] } })),
  ["BEFORE | AFTER", "BEFORE", "AFTER", "VIDEO [v]"]);
eq("a mission, three photos and a video", tags(X.missionSlides({ no: 7, now: [M("a"), M("b"), M("c")], now_video: M("v") })), ["NOW 1/3", "NOW 2/3", "NOW 3/3", "NOW · VIDEO [v]"]);
eq("a mission, one photo", tags(X.missionSlides({ no: 7, now: [M("a")] })), ["NOW"]);
eq("a mission, no photo, a video", tags(X.missionSlides({ no: 7, now: [], now_video: M("v") })), ["NOW [soon]", "NOW · VIDEO [v]"]);
eq("the sample receipt", tags(X.receiptSlides({ demo: true, media: { before: ["site/samples/canggu-before.svg"], after: ["site/samples/canggu-after.svg"], clips: [] } })), ["BEFORE | AFTER", "BEFORE", "AFTER"]);
// A receipt of a mission with 2 spots (docs/missions.md, Spots): each photo names its spot and counts in it; an unsafe link
// drops out and the other photos keep their spots; a broken spot list is one spot again.
const two = [{ no: 1, name: "Pantai Kuta", lat: -0.79, lng: 100.29, date: "2026-11-25" }, { no: 2, name: "Pantai Losari", lat: null, lng: null, date: "2026-11-26" }];
eq("a receipt with 2 spots", tags(X.receiptSlides({ spots: two, media: { before: [M("a"), "javascript:x", M("b"), M("c")], after: [M("d"), M("e")], before_spots: [1, 1, 1, 2], after_spots: [1, 2], videos: [M("f")], video_stages: ["after"] } })),
  ["BEFORE 1/2 · SPOT 1 | AFTER · SPOT 1", "BEFORE 1/2 · SPOT 1", "BEFORE 2/2 · SPOT 1", "BEFORE · SPOT 2", "AFTER · SPOT 1", "AFTER · SPOT 2", "AFTER · VIDEO [v]"]);
eq("a broken spot list, and spots with no photo of spot 1", [tags(X.receiptSlides({ spots: [two[0]], media: { before: [M("a")], after: [M("d")], before_spots: [2], after_spots: [2] } })),
  tags(X.receiptSlides({ spots: two, media: { before: [M("b")], after: [M("e")], before_spots: [2], after_spots: [2] } }))],
  [["BEFORE | AFTER", "BEFORE", "AFTER"], ["BEFORE · SPOT 2 | AFTER · SPOT 2", "BEFORE · SPOT 2", "AFTER · SPOT 2"]]);
// Several videos of a stage (up to 30 before and 30 after since 2026-11-19), numbered like the photos in the order they
// came (upload order), each group where its stage belongs, whatever their tags say: the slides go by stage (videosIn).
eq("several videos of a stage", tags(X.receiptSlides({ media: { before: [M("a")], after: [M("d")], videos: [M("f"), M("1"), M("2"), M("3"), M("4"), M("5")], video_stages: ["before", "before", "before", "after", "after", null] } })),
  ["BEFORE | AFTER", "BEFORE", "BEFORE · VIDEO 1/3 [v]", "BEFORE · VIDEO 2/3 [v]", "BEFORE · VIDEO 3/3 [v]", "AFTER", "AFTER · VIDEO 1/2 [v]", "AFTER · VIDEO 2/2 [v]", "VIDEO [v]"]);
const K = (i) => "/media/" + i.toString(16).padStart(32, "0");
const big = { media: { before: [M("a"), M("b")], after: [M("d")], videos: Array.from({ length: 60 }, (_, i) => K(i)), video_stages: Array.from({ length: 60 }, (_, i) => (i % 2 ? "after" : "before")) } };
const bs = X.receiptSlides(big), bt = tags(bs);
eq("30 before and 30 after sent in turns: each 30 numbered in their order, after their photos", [bt.length, bt[3], bt[4], bt[32], bt[33], bt[34], bt[35], bt[63], bs[3]?.[0].src, bs[4]?.[0].src, bs[34]?.[0].src, bs[63]?.[0].src],
  [64, "BEFORE · VIDEO 1/30 [v]", "BEFORE · VIDEO 2/30 [v]", "BEFORE · VIDEO 30/30 [v]", "AFTER", "AFTER · VIDEO 1/30 [v]", "AFTER · VIDEO 2/30 [v]", "AFTER · VIDEO 30/30 [v]", K(0), K(2), K(1), K(59)]);
eq("an unsafe link among three videos before is left out before the count", tags(X.receiptSlides({ media: { before: [M("a")], after: [M("d")], videos: [M("1"), "javascript:alert(1)", M("2")], video_stages: ["before", "before", "before"] } })),
  ["BEFORE | AFTER", "BEFORE", "BEFORE · VIDEO 1/2 [v]", "BEFORE · VIDEO 2/2 [v]", "AFTER"]);
eq("videos with no stages, and stages that are none: VIDEO 1/2 and 2/2 at the end", [tags(X.receiptSlides({ media: { before: [M("a")], after: [M("d")], videos: [M("1"), M("2")] } })),
  X.videosIn({ media: { videos: [M("1"), M("2"), M("3")], video_stages: ["BEFORE", { x: 1 }, "after"] } }).map((v) => v.tag + " " + v.stage)],
  [["BEFORE | AFTER", "BEFORE", "AFTER", "VIDEO 1/2 [v]", "VIDEO 2/2 [v]"], ["AFTER · VIDEO after", "VIDEO 1/2 null", "VIDEO 2/2 null"]]);
eq("the one-column post has the same videos as the wide post (videosIn), in the same order", X.videosIn(big).map((v) => v.tag + " " + v.src), bs.filter((x) => x[0].video).map((x) => x[0].tag + " " + x[0].src));
const bh = X.wideHtml("Cleanup receipt", bs, "", "", "");
eq("the wide post of 60 videos: 60 players that load nothing, each named by its tag", [(bh.match(/<video controls playsinline preload="none" src="/g) || []).length, bh.includes("aria-label=\"before · video 3/30\""), bh.includes("aria-label=\"after · video 30/30\"")], [60, true, true]);
const h = X.wideHtml("Mission #7", X.missionSlides({ no: 7, now: [M("a"), M("b")], now_video: M("v") }), "<div class=\"stamp\">S</div>", "<div class=\"post-paper\">P</div>", "<p class=\"post-all\">A</p>");
const sl = h.match(/<div class="pv-slide(?: pv-two)?"( hidden)?>/g) || [];
if (!h.includes("<div class=\"post-frame\" role=\"dialog\" aria-modal=\"true\" aria-label=\"Mission #7\"><div class=\"post-paper\">P</div>") || h.indexOf("post-paper") > h.indexOf("pv-stage")) bad.push("the frame, the paper first");
if (sl.length !== 3 || sl[0].includes("hidden") || !sl.slice(1).every((x) => x.includes(" hidden"))) bad.push("one slide shown: " + sl.join(""));
if ((h.match(/<video /g) || []).length !== 1 || !h.includes("<video controls playsinline preload=\"none\" src=\"" + M("v") + "\" aria-label=\"now · video\"></video>")) bad.push("the video");
if ((h.match(/<img /g) || []).length !== 2 || (h.match(/ loading="lazy" decoding="async">/g) || []).length !== 2) bad.push("the photos");
if (!h.includes("<div class=\"pv-bar\"><div class=\"stamp\">S</div><div class=\"pv-nav\"><button type=\"button\" class=\"pv-prev\" aria-label=\"Previous photo or video\">←</button><span class=\"pv-count\"></span><button type=\"button\" class=\"pv-next\" aria-label=\"Next photo or video\">→</button></div><div class=\"pv-acts\"><p class=\"post-all\">A</p></div><p class=\"pv-live\" aria-live=\"polite\"></p></div>")) bad.push("the bar");
const one = X.wideHtml("Mission #3", X.missionSlides({ no: 3, now: [M("a")] }), "", "", "");
if (one.includes("pv-nav") || one.includes(" hidden") || one.includes("pv-acts")) bad.push("one slide with arrows, or a box for no links");
const solo = X.wideHtml("Cleanup receipt", [[{ src: M("a"), tag: "BEFORE" }]], "", "", "<b>A</b>");
if (!solo.includes("<div class=\"pv-bar\"><div class=\"pv-acts\"><b>A</b></div><p class=\"pv-live\" aria-live=\"polite\"></p></div>")) bad.push("links without arrows");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 25");
' "$T/pl-app.js" 2>&1)
check "the wide post's slides (site/app.js, node): a cleanup's first before and after side by side, then every photo and video alone in the order of the day, several videos of a stage numbered (30 before and 30 after, by stage, in upload order, unsafe ones left out first), the same videos in the one-column post; a mission's NOW photos and video; unsafe links dropped; the dialog with the paper first, one slide shown, videos that load nothing, lazy photos, arrows only with two slides, the post's own links in the bar after the arrows" "$WSL" "ok 25"
# The receipt with 30 videos before and 30 after sent at the start ($ID3), as the server gives it: the homepage's videosIn
# (both posts) and /admin/'s videoRows number its videos in upload order within each stage, BEFORE · VIDEO 1/30 first
# and AFTER · VIDEO 30/30 last on the receipt, VIDEO BEFORE 1/30 to VIDEO AFTER 30/30 with 60 different download names on
# the APPROVED card.
curl -s $B/api/events > "$T/ev60.json"; curl -s "$B/api/admin/submissions?status=approved" -H "$A" > "$T/ap60.json"
R60=$(node -e '
const fs = require("fs"), s = fs.readFileSync(process.argv[1], "utf8"), aj = fs.readFileSync(process.argv[2], "utf8");
const line = (src, re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  // ---------- the wide post\x27s slides (pure; tests/e2e.sh runs this block in node) ----------"), b = s.indexOf("  // ---------- end of the wide post\x27s slides ----------");
const k = s.indexOf("  const safeSrc = (u) =>"), safe = s.slice(k, s.indexOf("\n", s.indexOf("\n", k) + 1));
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m, /^  const nowOf = .*$/m, /^  const nowVideoOf = .*$/m].map((re) => line(s, re)).join("\n");
const sp = s.slice(s.indexOf("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------"), s.indexOf("  // ---------- end of the spots ----------"));
const X = new Function(helpers + "\n" + safe + "\n" + sp + "\n" + s.slice(a, b) + "\nreturn { receiptSlides, videosIn };")();
const c = aj.indexOf("  function videoRows("), d = aj.indexOf("\n  }\n", c);
const videoRows = new Function(aj.slice(c, d + 4) + "\nreturn videoRows;")();
const [id, before, after] = process.argv.slice(3), keys = (l) => l.split(",").map((x) => "/media/" + x);
const e = JSON.parse(fs.readFileSync(process.argv[6], "utf8")).find((x) => x.id === id);
const sub = JSON.parse(fs.readFileSync(process.argv[7], "utf8")).submissions.find((x) => x.id === id);
if (!e || !sub) { console.log("missing " + id); process.exit(0); }
const vs = X.receiptSlides(e).filter((x) => x[0].video).map((x) => x[0]), vi = X.videosIn(e), rows = videoRows(sub.media.videos);
const want = [...keys(before), ...keys(after)];
console.log(JSON.stringify([vs.length, vs[0].tag, vs[29].tag, vs[30].tag, vs[59].tag, JSON.stringify(vs.map((v) => v.src)) === JSON.stringify(want),
  JSON.stringify(vi.map((v) => v.tag)) === JSON.stringify(vs.map((v) => v.tag)), rows[0].title, rows[59].title, new Set(rows.map((r) => r.dl)).size, rows[0].dl, rows[30].dl]));
' "$T/pl-app.js" "$T/admin.js" "$ID3" "$VB30" "$VA30" "$T/ev60.json" "$T/ap60.json" 2>&1)
check "the receipt with 60 videos as the server sends it: on the homepage BEFORE · VIDEO 1/30 to AFTER · VIDEO 30/30 in upload order (both posts), on APPROVED VIDEO BEFORE 1/30 to VIDEO AFTER 30/30 with 60 download names" "$R60" \
  '[60,"BEFORE · VIDEO 1/30","BEFORE · VIDEO 30/30","AFTER · VIDEO 1/30","AFTER · VIDEO 30/30",true,true,"VIDEO BEFORE 1/30","VIDEO AFTER 30/30",60,"video-before-1","video-after-1"]'
# Below WIDE the post is the one column as before: openPost's and openMission's templates, run in node with stand-ins for
# their helpers and with their own links (acts) as each function builds them, give the phone markup with wide false (the
# dialog on the paper, the stamp, the photos, and COPY LINK, SHARE and ALL MISSIONS exactly as at 65bd0bf) and none of it
# with wide true, where the bar under the photos has the links.
WPH=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const fn = (name) => { const a = s.indexOf("  function " + name + "("), b = s.indexOf("\n  }\n", a); return s.slice(a, b + 4); };
const tpl = (body) => { const a = body.indexOf("const paper = `"), b = body.indexOf("</div>`;", a); if (a < 0 || b < 0) throw new Error("no template"); return body.slice(a + 14, b + 7); };
const actsOf = (name) => { const body = fn(name), a = body.indexOf("    const acts = "), b = body.indexOf("`;\n", a); if (a < 0 || b < 0) throw new Error("no acts in " + name); return body.slice(a + 17, b + 1); };
const names = ["phOr", "videoBox", "thanksRow", "byRow", "moneyRows", "commentsRow", "satRow", "dateStr", "upper", "num", "cc", "rid", "escapeHTML", "mStamp", "mRows", "nowVideoOf", "funded", "mNote", "spotsE", "spotsM", "spotRows", "spotPairs"];
const fake = Object.fromEntries(names.map((n) => [n, (...a) => "[" + n + "(" + a.map((x) => JSON.stringify(x)).join(",") + ")]"]));
fake.funded = (m) => m.status === "funded"; fake.nowVideoOf = (m) => m?.now_video || null;
fake.spotsE = fake.spotsM = () => []; fake.spotRows = fake.spotPairs = () => ""; // a post with one spot, as before spots
const e = { id: "r1", fromApi: true, media: { before: ["/media/a"], after: ["/media/b"] }, location: {} }, m = { no: 7, status: "funded", now: ["/media/x"], now_video: "/media/v" };
const actsR = (nav, ev) => new Function("navigator", "mis", "e", "return " + actsOf("openPost") + ";")(nav, { no: 8 }, ev);
const actsM = (nav, mm) => new Function("navigator", "m", "return " + actsOf("openMission") + ";")(nav, mm);
const run = (name, wide) => new Function(...names, "e", "m", "navigator", "wide", "stamp", "clips", "mis", "misNow", "misVideo", "videos", "shots", "acts", "return " + tpl(fn(name)) + ";")(
  ...names.map((n) => fake[n]), e, m, {}, wide, "<div class=\"stamp stamp-ok post-stamp\">VERIFIED</div>", "", { no: 8 }, "/media/n", null, "", "[shots]", name === "openPost" ? actsR({}, e) : actsM({}, m));
const bad = [];
const r = run("openPost", false), rw = run("openPost", true), p = run("openMission", false), pw = run("openMission", true);
if (!r.includes("\n        <div class=\"barcode\" aria-hidden=\"true\"></div>\n        <div class=\"post-actions\"><button class=\"post-link post-copy\">COPY LINK</button></div>\n        <p class=\"post-all\"><a href=\"/missions?status=cleaned#m-8\">ALL CLEANED MISSIONS →</a></p>\n        <div class=\"r-id\">[rid(")
  || !p.includes("\n        <div class=\"m-link\">SAPU.EARTH/M/7</div>\n        <div class=\"post-actions\"><button class=\"post-link post-share\">SHARE</button></div>\n        <p class=\"post-all\"><a href=\"/missions#m-7\">ALL MISSIONS →</a></p>\n        <div class=\"r-id\">MISSION #7 · FUNDED</div>")
  || /post-actions|post-all/.test(rw + pw)
  || !actsR({ share() {} }, e).startsWith("<div class=\"post-actions\"><button class=\"post-link post-copy\">COPY LINK</button><button class=\"post-link post-share\">SHARE</button></div>")
  || !actsM({ share() {} }, m).startsWith("<div class=\"post-actions\"><button class=\"post-link post-share\">SHARE</button><button class=\"post-link post-copy\">COPY LINK</button></div>")
  || actsR({}, { id: "d", demo: true }).includes("post-all") || actsM({}, { no: 3, demo: true }) !== "") bad.push("the links: in the paper below WIDE as before, under the photos on a wide screen");
if (!r.startsWith("\n      <div class=\"post-paper\" role=\"dialog\" aria-modal=\"true\" aria-label=\"Cleanup receipt\">\n        <button class=\"post-close\" aria-label=\"Close\">✕</button>\n        <div class=\"stamp stamp-ok post-stamp\">VERIFIED</div>\n        <div class=\"r-head\">SAPU EARTH<span>CLEANUP RECEIPT · [dateStr({\"id\":\"r1\"") || !r.includes("\n        <div class=\"post-media\">[phOr(\"/media/n\",\"NOW · MISSION #8\",\"pm\")][phOr(\"/media/a\",\"BEFORE\",\"pm\")][phOr(\"/media/b\",\"AFTER\",\"pm\")]</div>\n        [thanksRow(")) bad.push("receipt, one column");
if (/role=|post-stamp|post-media/.test(rw) || !rw.startsWith("\n      <div class=\"post-paper\">\n        <button class=\"post-close\" aria-label=\"Close\">✕</button>")) bad.push("receipt, wide");
if (!p.startsWith("\n      <div class=\"post-paper mpost mpost-funded\" role=\"dialog\" aria-modal=\"true\" aria-label=\"Mission #7\">\n        <button class=\"post-close\" aria-label=\"Close\">✕</button>\n        [mStamp(") || !p.includes("<div class=\"post-media\">[shots][videoBox(\"/media/v\",\"NOW · VIDEO\")]</div>")) bad.push("mission, one column");
if (/role=|mStamp|post-media/.test(pw)) bad.push("mission, wide");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 5");
' "$T/pl-app.js" 2>&1)
check "below WIDE a receipt and a mission post are the one column as before (the dialog on the paper, the stamp, the photos, COPY LINK, SHARE and ALL MISSIONS as at 65bd0bf), and the wide post's paper has none of them (node)" "$WPH" "ok 5"
# The money rows of NEXT UP's cards, the mission post and a receipt (site/app.js, the local money rows), run in node with
# app.js's own helpers: the price first, then CREW PAY as people × the pay for each person (with its head count when it
# does not split evenly, IN ALL without a crew size, NONE for 0) and OTHER COSTS; a receipt's own costs as SPENT, CREW PAY
# and OTHER COSTS, never a pay for each person (APPROVE can change the crew size, not the money); and the rows of before
# (CREW ASKED, OF WHICH TO CREW, CREW, LOCAL MONEY) gone.
LMR=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const part = (start, end) => { const a = s.indexOf(start), b = s.indexOf(end); if (a < 0 || b < a) throw new Error("missing " + start); return s.slice(a, b); };
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const num = .*$/m, /^  const eur = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m].map(line).join("\n");
const X = new Function(helpers + "\n" + part("  // ---------- mission money: the same block", "  // ---------- end of the mission money block ----------") +
  part("  // ---------- local money rows (pure; tests/e2e.sh runs this block in node) ----------", "  // ---------- end of the local money rows ----------") + "\nreturn { mMoney, localRows };")();
const top = (dt, dd) => `<div class="r-total"><dt>${dt}</dt><dd>${dd}</dd></div>`;
const sub = (dt, dd, local = "") => `<div class="r-sub${local}"><dt>${dt}</dt><dd>${dd}</dd></div>`;
const m2 = { status: "funded", funded_eur: 150, currency: "IDR", price_local: 3000000, crew_local: 1500000, crew_size: 15 };
const mis = { no: 2, currency: "IDR", price_local: 3000000, crew_local: 1500000, crew_size: 15 };
const own = (total, crew) => ({ mission: mis, local_money: { currency: "IDR", total, crew } });
const asked = sub("ASKED", "IDR 3,000,000", " r-local") + sub("CREW PAY", "15 × IDR 100,000") + sub("OTHER COSTS", "IDR 1,500,000");
const want = [
  ["open", X.mMoney({ ...m2, status: "open" }), top("ASKING", "IDR 3,000,000") + sub("CREW PAY", "15 × IDR 100,000") + sub("OTHER COSTS", "IDR 1,500,000")],
  ["funded", X.mMoney(m2), top("FUNDED", "€150") + sub("ASKED", "IDR 3,000,000") + sub("CREW PAY", "15 × IDR 100,000") + sub("OTHER COSTS", "IDR 1,500,000")],
  ["not even", X.mMoney({ ...m2, crew_local: 100000 }), top("FUNDED", "€150") + sub("ASKED", "IDR 3,000,000") + sub("CREW PAY", "IDR 100,000 FOR 15 PPL") + sub("OTHER COSTS", "IDR 2,900,000")],
  ["no other costs", X.mMoney({ ...m2, status: "open", crew_local: 3000000 }), top("ASKING", "IDR 3,000,000") + sub("CREW PAY", "15 × IDR 200,000") + sub("OTHER COSTS", "NONE")],
  ["no crew pay", X.mMoney({ ...m2, status: "open", crew_local: 0 }), top("ASKING", "IDR 3,000,000") + sub("CREW PAY", "NONE") + sub("OTHER COSTS", "IDR 3,000,000")],
  ["bad currency", X.mMoney({ ...m2, status: "open", currency: "idr" }), top("ASKING", "?")],
  ["receipt, asked", X.localRows({ mission: mis }), asked],
  ["receipt, a block without crew_size", X.localRows({ mission: { ...mis, crew_size: undefined } }),
    sub("ASKED", "IDR 3,000,000", " r-local") + sub("CREW PAY", "IDR 1,500,000 IN ALL") + sub("OTHER COSTS", "IDR 1,500,000")],
  ["receipt, own costs", X.localRows(own(1500000, 900000)), sub("SPENT", "IDR 1,500,000", " r-local") + sub("CREW PAY", "IDR 900,000") + sub("OTHER COSTS", "IDR 600,000")],
  ["receipt, own crew pay only", X.localRows(own(null, 900000)), sub("CREW PAY", "IDR 900,000", " r-local")],
  ["receipt, own total below its crew pay", X.localRows(own(500000, 900000)), sub("CREW PAY", "IDR 900,000", " r-local")],
  ["plain receipt", X.localRows({ id: "r1" }), ""],
];
const bad = want.filter(([, got, w]) => got !== w).map(([name, got]) => name + ": " + got);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + want.length);
' "$T/pl-app.js" 2>&1)
check "the money rows (site/app.js mMoney and localRows, node): ASKING or FUNDED and ASKED first, CREW PAY as 15 × IDR 100,000 (IDR 100,000 FOR 15 PPL when it does not split evenly, IN ALL without a crew size, NONE for 0), OTHER COSTS, a receipt's own costs as SPENT, CREW PAY and OTHER COSTS, and no rows for a currency the page cannot show" \
  "$LMR $(grep -cE 'CREW ASKED|OF WHICH TO CREW|CREW, LOCAL MONEY' "$T/pl-app.js")" "ok 12 0"
# /admin/ says a price as it adds up (payText, run in node with admin.js's own helpers): the mission card's Price with the
# crew's share, an orange note when the crew pay does not split evenly (sent as one total, like mission #2), the FUND hint,
# Asked on PENDING and APPROVED, a cleanup's own costs without a pay for each person, and the hint under the crew size of
# APPROVE (a crew size fixed there does not change the money).
APT=$(node -e '
const src = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
const P = new Function([/^  const n = .*$/m, /^  const fmt = .*$/m, /^  const isNum = .*$/m].map(line).join("\n") + "\n" + fn("splitOf") + fn("payText") + "\nreturn payText;")();
const want = [
  [P("IDR", 3000000, 1500000, 15, { share: true }), { text: "IDR 3,000,000 in all: crew pay 15 × 100,000 = 1,500,000 (50%), other costs 1,500,000", odd: "" }],
  [P("IDR", 3000000, 100000, 15, { share: true }), { text: "IDR 3,000,000 in all: crew pay 100,000 for 15 people (about 6,666.67 each, 3%), other costs 2,900,000", odd: "about 6,666.67 each" }],
  [P("IDR", 3000000, 1500000, 15), { text: "IDR 3,000,000 in all: crew pay 15 × 100,000 = 1,500,000, other costs 1,500,000", odd: "" }],
  [P("IDR", 1500000, 1500000, 15), { text: "IDR 1,500,000 in all: crew pay 15 × 100,000 = 1,500,000, no other costs", odd: "" }],
  [P("PHP", 5000, 0, 5, { share: true }), { text: "PHP 5,000 in all: no crew pay, other costs 5,000", odd: "" }],
  [P("IDR", 1500000, 900000, 6, { each: false }), { text: "IDR 1,500,000 in all: crew pay 900,000 for 6 people, other costs 600,000", odd: "" }],
  [[P("IDR", 1000, 1001, 4), P("IDR", null, 5, 4)], [null, null]],
];
const bad = want.map(([got, w], i) => [i, got, w]).filter(([, got, w]) => JSON.stringify(got) !== JSON.stringify(w)).map(([i, got]) => i + ": " + JSON.stringify(got));
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok " + want.length);
' "$T/crew-admin.js" 2>&1)
[ "$APT" = "ok 7" ] \
  && echo "$AJ" | grep -qF 'const pt = payText(m.currency, m.price_local, m.crew_local, m.crew_size, { share: true });' \
  && echo "$AJ" | grep -qF '${pt && pt.odd ? `<p class="msg err am-odd">Check the crew pay with the crew: ' \
  && echo "$AJ" | grep -qF 'const asked = payText(mis.currency, mis.price_local, mis.crew_local, mis.crew_size);' \
  && echo "$AJ" | grep -qF '${asked ? `<dt>Asked</dt><dd>${esc(asked.text)}</dd>` : ""}' \
  && echo "$AJ" | grep -qF 'const asked = payText(m.currency, m.price_local, m.crew_local, m.crew_size);' \
  && echo "$AJ" | grep -qF 'const own = payText(s.currency, s.total_cost_local, s.crew_pay_local, s.crew_size, { each: false });' \
  && echo "$AJ" | grep -qF '<p class="hint" data-crew-hint hidden></p>' && echo "$AJ" | grep -qF 'It does not change with the crew size here.' \
  && ok "/admin/ says a price as it adds up (payText, node): crew pay 15 × 100,000 = 1,500,000 with its share, about 6,666.67 each and an orange note for one total, the FUND hint, Asked, a cleanup's own costs for its crew size, and the hint under APPROVE's crew size" \
  || bad "admin.js payText" "$APT"
# The markup of PRICE and COSTS: PRICE asks the currency, the people, the pay for each person and the other costs, then
# shows the sum (THE PLAN has no crew size any more); COSTS asks what each person got and the other costs under the
# currency, then its sum; the cost line has room for the crew size note, the done screen for the price, and no money
# field has a grey example.
MPX=$(echo "$UPM" | sed -n '/data-i18n="m_money_h"/,/<\/section>/p'); MSF=$(echo "$UPM" | sed -n '/data-i18n="m_plan_h"/,/<\/section>/p')
CFX=$(echo "$UPC" | sed -n '/<div id="costFields">/,/<\/section>/p')
[ "$(echo "$MPX" | grep -oE 'id="(m-currency|priceChipRow|m-crew|m-each|m-other|mSum)"' | tr '\n' ' ')" = 'id="m-currency" id="priceChipRow" id="m-crew" id="m-each" id="m-other" id="mSum" ' ] \
  && [ -n "$MSF" ] && ! echo "$MSF" | grep -qF 'name="crew_size"' \
  && [ "$(echo "$CFX" | grep -oE 'id="(f-currency|f-each|f-other|fSum)"' | tr '\n' ' ')" = 'id="f-currency" id="f-each" id="f-other" id="fSum" ' ] \
  && echo "$UPC" | grep -qF '<span id="costCrew"></span>' && echo "$UP" | grep -qF '<p id="mdonePrice" hidden></p>' \
  && [ "$(echo "$UP" | grep -cE 'name="(crew_each_local|other_local)"')" = 4 ] && ! echo "$UP" | grep -E 'name="(crew_each_local|other_local)"' | grep -q 'placeholder' \
  && ok "PRICE asks the currency, the people, the pay for each person and the other costs, then shows the sum (no crew size in THE PLAN); COSTS asks what each person got and the other costs, then its sum; the cost line's crew note and the done screen's price have their place; no money field has a grey example" \
  || bad "PRICE and COSTS markup" "$(echo "$MPX" | grep -oE 'id="[^"]+"' | tr '\n' ' ') | $(echo "$CFX" | grep -oE 'id="[^"]+"' | tr '\n' ' ')"
# The wiring: the echo only under kg, the sum drawn on every change of the people, the amounts and the currency, and on a
# language switch; the fields behind THE COSTS WERE DIFFERENT, a typed cost keeps them open, an old tab's 400 on the price
# lands under the pay, the done screen gets what was sent, and syncCosts draws the cleanup's sum before it stops for a
# cleanup without a mission (a mission filled in or emptied the crew size without an input).
SYX=$(echo "$UJ" | sed -n '/^  function syncCosts() {/,/^  }$/p')
RLN=$(echo "$SYX" | grep -nF 'renderSum("cleanup");' | cut -d: -f1); MLN=$(echo "$SYX" | grep -nF 'if (!m) return;' | cut -d: -f1)
echo "$UJ" | grep -qF 'const ECHO = ["kg"];' && echo "$UJ" | grep -qF 'const SUM_LIVE = ["crew_size", "crew_each_local", "other_local", "currency", "currency_other"];' \
  && echo "$UJ" | grep -qF 'if (SUM_LIVE.includes(name)) renderSum(g);' && echo "$UJ" | grep -qF 'renderSum("mission"); renderSum("cleanup");' \
  && echo "$UJ" | grep -qF 'const BEHIND_COSTS = ["f-currency", "f-currency-other", "f-each", "f-other"];' \
  && echo "$UJ" | grep -qF 'if (E.crew_each_local.value.trim() || E.other_local.value.trim()) costsOpen = true;' \
  && echo "$UJ" | grep -qF 'price_local: ["m-each", "e_number"], crew_local: ["m-each", "e_number"],' \
  && echo "$UJ" | grep -qF 'if (res) missionDone(res, data);' \
  && [ -n "$RLN" ] && [ -n "$MLN" ] && [ "$(echo "$RLN" | wc -l | tr -d ' ')" = 1 ] && [ "$RLN" -lt "$MLN" ] \
  && ok "the sum is drawn on every change of the people, the amounts and the currency and on a language switch (the echo only under kg), the cost fields stay open once typed in, an old tab's 400 lands under the pay, the done screen gets the price sent, and syncCosts draws the cleanup's sum before it stops without a mission" \
  || bad "upload.js sum wiring" "syncCosts: renderSum at [$RLN], return at [$MLN]"
# What the lines under the amounts say, with the real readMoney, renderSum and showErrors of upload.js run in node on a
# stub page (a text shows as its key; reveal draws COSTS as while typing, the way setCleanupFlavor and syncCosts do; a
# keystroke takes the field's own mark and message off, as the form's input handler does). An amount that may still
# become a number ("Rp ", "100. ", "1.500.000,") says nothing while it is typed; a word says why at once, also with a space
# after it ("150 ribu "). SEND CLEANUP and POST MISSION say why under an amount they cannot read, once (its field is only
# marked), and the line stays when the crew size, the other amount or the language changes, until the crew edits that
# amount. Before 2026-11-16 SEND CLEANUP opened COSTS after drawing that line and so emptied it again: an orange field
# with no reason under it.
SUMX=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const cut = (from, to) => { const a = s.indexOf(from), b = s.indexOf(to, a); if (a < 0 || b < a) throw new Error("no " + from.trim()); return s.slice(a, b); };
const code = cut("  const CUR_SIGN", "  // Show how a typed number was read") + cut("  function numVal(", "  // ---------- validation ----------")
  + cut("  // ---------- crew page model (pure; tests/e2e.sh runs this block in node) ----------", "  // ---------- end of crew page model ----------")
  + cut("  const PHOTO_FIELDS = ", "  // ---------- network ----------") + cut("  const numText = ", "  // A mission\x27s price in one line");
const els = {};
const mk = (id, form) => {
  const e = { id, form, text: "", hidden: false, c: new Set(), fmsg: null, scrollIntoView() {} };
  e.classList = { add: (x) => e.c.add(x), remove: (x) => e.c.delete(x), contains: (x) => e.c.has(x), toggle: (x, on) => (on ? e.c.add(x) : e.c.delete(x)) };
  return (els["#" + id] = e);
};
const fv = () => ({ elements: Object.fromEntries(["currency", "currency_other", "crew_size", "crew_each_local", "other_local"].map((k) => [k, { value: k === "currency" ? "IDR" : "" }])) });
const cf = fv(), mf = fv(), UI = { cleanup: { form: cf, err: "#formErr" }, mission: { form: mf, err: "#mformErr" } };
for (const id of ["fEachLine", "fOtherLine", "fSum", "fSumTotal", "fSumParts", "f-crew", "f-each", "f-other", "formErr"]) mk(id, cf);
for (const id of ["mEachLine", "mOtherLine", "mSum", "mSumTotal", "mSumParts", "m-crew", "m-each", "m-other", "mformErr"]) mk(id, mf);
const $ = (q) => els[q], $$ = (q, f) => Object.values(els).filter((e) => e.form === f && e.c.has(q.slice(1)));
const fmsgFor = (el, create) => { if (!el.fmsg && create) { el.fmsg = mk(el.id + "-msg", el.form); el.fmsg.c.add("fmsg"); } return el.fmsg; };
const R = new Function("$", "$$", "document", "UI", "fmsgFor", "setMsg", "setText", "fieldMsg",
  "let lang = \"en\";\nconst reveal = () => renderSum(\"cleanup\");\n" + code + "\nreturn { renderSum, readMoney, showErrors, setLang: (l) => { lang = l; } };")(
  $, $$, { getElementById: (id) => els["#" + id] || null }, UI, fmsgFor, (el, key) => { if (el) el.text = key || ""; }, (el, x) => { el.text = x; }, () => {});
const bad = [];
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": " + JSON.stringify(got)); };
const P = { cleanup: "f-", mission: "m-" };
// [the line under the pay, the line under the other costs, pay marked, other costs marked, the message box of the pay
// field, the message box of the other costs field]
const look = (g) => { const p = P[g], L = g === "mission" ? "#m" : "#f", fm = (e) => (e.fmsg ? e.fmsg.text : "");
  return [els[L + "EachLine"].text, els[L + "OtherLine"].text, els["#" + p + "each"].c.has("invalid"), els["#" + p + "other"].c.has("invalid"), fm(els["#" + p + "each"]), fm(els["#" + p + "other"])]; };
const FIELD = { crew_size: "crew", crew_each_local: "each", other_local: "other" };
const type = (g, name, value) => {
  UI[g].form.elements[name].value = value;
  const f = els["#" + P[g] + FIELD[name]]; f.classList.remove("invalid"); if (f.fmsg) f.fmsg.text = "";
  R.renderSum(g);
  if (g === "cleanup") R.renderSum("cleanup"); // setCleanupFlavor after a cleanup field: syncCosts draws it once more
};
// SEND CLEANUP and POST MISSION as far as the amounts go: collect and collectMission draw the sum strict and only mark an
// amount that cannot be read (both pinned), then showErrors.
const send = (g) => {
  const r = R.renderSum(g, true), errors = [];
  if (r.each.bad) errors.push({ id: P[g] + "each", key: "" });
  if (r.other.bad) errors.push({ id: P[g] + "other", key: "" });
  if (errors.length) R.showErrors(errors, g);
};
const rd = (raw) => { const r = R.readMoney({ elements: { x: { value: raw } } }, "x", 1e9); return [r.v, r.bad, r.typing]; };
eq("readMoney", ["Rp", "Rp ", "IDR ", "US$ ", "100.", "100. ", "1.500.000,", "150 ribu ", "tidak ada ", "150rb", "100rb ", "2000000000", "150.000 ", ""].map(rd),
  [[null, "e_money", true], [null, "e_money", true], [null, "e_money", true], [null, "e_money", true], [null, "e_money", true], [null, "e_money", true],
   [null, "e_money", true], [null, "e_money", false], [null, "e_money", false], [null, "e_money", false], [null, "e_money", false], [null, "e_number", false],
   [150000, null, false], [null, null, false]]);
type("cleanup", "crew_size", "6");
type("cleanup", "crew_each_local", "150000. ");
eq("costs while typing", look("cleanup"), ["", "", false, false, "", ""]);
send("cleanup");
eq("costs at SEND", look("cleanup"), ["e_money", "", true, false, "", ""]);
type("cleanup", "crew_size", "7");
eq("costs after the crew size", look("cleanup"), ["e_money", "", true, false, "", ""]);
R.setLang("id"); R.renderSum("mission"); R.renderSum("cleanup"); R.setLang("en");
eq("costs after a language switch", look("cleanup"), ["e_money", "", true, false, "", ""]);
type("cleanup", "crew_each_local", "150000.");
eq("costs as the pay is edited", look("cleanup"), ["", "", false, false, "", ""]);
type("cleanup", "crew_each_local", "150000");
eq("costs fixed", look("cleanup"), ["sum_crew", "", false, false, "", ""]);
type("cleanup", "other_local", "Rp");
send("cleanup");
type("cleanup", "crew_size", "6");
eq("other costs Rp", look("cleanup"), ["sum_crew", "e_money", false, true, "", ""]);
type("cleanup", "other_local", "Rp 300.000");
eq("other costs fixed", look("cleanup"), ["sum_crew", "", false, false, "", ""]);
type("cleanup", "crew_each_local", "150 ribu ");
eq("a word in COSTS", look("cleanup"), ["e_money", "", false, false, "", ""]);
send("cleanup");
eq("a word at SEND", look("cleanup"), ["e_money", "", true, false, "", ""]);
type("mission", "crew_each_local", "100.000.");
eq("price while typing", look("mission"), ["", "", false, false, "", ""]);
send("mission");
eq("price at POST MISSION", look("mission"), ["e_money", "", true, false, "", ""]);
type("mission", "crew_size", "15");
eq("price after the crew size", look("mission"), ["e_money", "", true, false, "", ""]);
type("mission", "crew_each_local", "100.000");
eq("price fixed", look("mission"), ["sum_crew", "", false, false, "", ""]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/crew.js" 2>&1)
[ "$SUMX" = ok ] && echo "$UJ" | grep -qF 'if (each.bad) bad("f-each", ""); // marked only: the line under the field says why' \
  && echo "$UJ" | grep -qF 'if (other.bad) bad("f-other", ""); // the same' \
  && echo "$UJ" | grep -qF 'if (f) { f.classList.remove("invalid"); setMsg(fmsgFor(f, false)); }' \
  && ok "the lines under the amounts (node): an amount still being typed (Rp, 100., 1.500.000,) says nothing, a word says why at once also with a space after it (150 ribu), and SEND CLEANUP and POST MISSION say why under an amount they cannot read, once, until the crew edits that amount, also after the crew size or the language changed" \
  || bad "upload.js lines under the amounts" "$SUMX"
# The wiring by the text: one query, reopen and stage, the one-column string assigned as before, the paper's links left out
# of it and handed to wideHtml on a wide screen, the stage started after showOverlay, every chooser and closePost clearing
# both, ← and → (not on a video, not with a modifier), the redraw across WIDE (300 ms, never during full screen, only when
# the post no longer fits; its listener guarded, since Safari before 14 has only addListener and an unguarded call stops
# the whole homepage script there), the paper's fade (pv-more: on open, on its scroll, on any change of its size or its
# parts' sizes, and on resize; only with more than its 18 blank px below), and a video that loads nothing until its slide
# has shown for 300 ms (preload none in the wide post, loadShown run in node below; videoBox's preload none for a
# receipt's videos in the one column, lazyVideos below, metadata for the mission post's one video).
OPM=$(echo "$SJ" | sed -n '/^  function openMission(m) {/,/^  }$/p'); OPR=$(echo "$SJ" | sed -n '/^  function openPost(e) {/,/^  }$/p')
WX=""
[ "$(echo "$SJ" | grep -cF 'const WIDE = matchMedia("(min-width: 900px) and (min-height: 520px)");')" = 1 ] && echo "$SJ" | grep -qxF '  let reopen = null, stage = null;' || WX="$WX [query]"
echo "$SC" | grep -qF '(min-width: 900px) and (min-height: 520px), a post opens in two columns' || WX="$WX [css comment]"
for t in '    reopen = () => openPost(e);' '    const wide = WIDE.matches, slides = wide ? receiptSlides(e) : null;' '        ${wide ? "" : acts}' \
         '    overlay.innerHTML = wide ? wideHtml("Cleanup receipt", slides, stamp, paper, acts) : paper;' '    if (slides) startStage(slides);'; do
  echo "$OPR" | grep -qxF -- "$t" || WX="$WX [openPost: $t]"
done
for t in '    reopen = () => openMission(m);' '    const wide = WIDE.matches, slides = wide ? missionSlides(m) : null;' '        ${wide ? "" : acts}`}' \
         '    overlay.innerHTML = wide ? wideHtml("Mission #" + m.no, slides, mStamp(m, " post-stamp"), paper, acts) : paper;' '    if (slides) startStage(slides);'; do
  echo "$OPM" | grep -qxF -- "$t" || WX="$WX [openMission: $t]"
done
[ "$(echo "$OPR" | grep -A2 -F '    overlay.innerHTML = wide ? wideHtml(' | tr '\n' '|')" = '    overlay.innerHTML = wide ? wideHtml("Cleanup receipt", slides, stamp, paper, acts) : paper;|    showOverlay("#ev-" + encodeURIComponent(e.id));|    if (slides) startStage(slides);|' ] || WX="$WX [openPost order]"
[ "$(echo "$SJ" | grep -cF 'WIDE.addEventListener(')" = 1 ] && echo "$SJ" | grep -qxF '  if (WIDE.addEventListener) WIDE.addEventListener("change", redraw); else WIDE.addListener?.(redraw);' || WX="$WX [the WIDE listener, guarded]"
[ "$(echo "$SJ" | sed -n '/^  function startStage(slides) {/,/^  }$/p' | tail -4 | tr '\n' '|')" = '    stage = st;|    st.go(0, false);|    st.more();|  }|' ] || WX="$WX [the fade on open]"
[ "$(echo "$SJ" | grep -cxF '    reopen = stage = null;')" = 3 ] && echo "$SJ" | sed -n '/^  function closePost() {/,/^  }$/p' | sed -n 2p | grep -qxF '    reopen = stage = null;' || WX="$WX [clear]"
for t in 'if (!stage || overlay.hidden || (ev.key !== "ArrowLeft" && ev.key !== "ArrowRight") || ev.altKey || ev.ctrlKey || ev.metaKey || ev.shiftKey) return;' \
         'if (ev.target instanceof Element && ev.target.closest("video")) return;' 'stage.step(ev.key === "ArrowLeft" ? -1 : 1);' \
         'if (overlay.hidden || !reopen || document.fullscreenElement || document.webkitFullscreenElement) return;' \
         'if (!!overlay.querySelector(".post-frame") !== WIDE.matches) reopen();' '}, 300);' \
         'document.addEventListener("fullscreenchange", redraw);' 'addEventListener("resize", () => { if (stage) { stage.lay(); stage.more(); } });' \
         '    st.more = () => paper.classList.toggle("pv-more", paper.scrollHeight - paper.clientHeight - paper.scrollTop > 18);' \
         '    paper.addEventListener("scroll", st.more, { passive: true });' \
         '    if (typeof ResizeObserver === "function") { const ro = new ResizeObserver(() => st.more()); [paper, ...paper.children].forEach((el) => ro.observe(el)); }' \
         '      st.at = i;' '      loadShown();' '      }, Math.max(300, vlast + 1000 - performance.now()));' \
         '        vs.forEach((v) => { if (v.preload === "none") v.preload = "metadata"; else v.load(); });' \
         'if (j !== i) el.querySelectorAll("video").forEach((v) => v.pause());' "el?.querySelectorAll('img[loading=\"lazy\"]').forEach((im) => { im.loading = \"eager\"; });"; do
  echo "$SJ" | grep -qF -- "$t" || WX="$WX [$t]"
done
[ "$(echo "$SJ" | grep -oF '<video controls playsinline preload="none" src=' | wc -l | tr -d ' ')" = 1 ] \
  && [ "$(echo "$SJ" | grep -oF '<video controls playsinline preload="${lazy ? "none" : "metadata"}" src=' | wc -l | tr -d ' ')" = 1 ] \
  && ! echo "$SJ" | grep -qF 'preload="metadata" src=' || WX="$WX [preload]"
[ "$(echo "$SJ" | sed -n '/^  function startStage(slides) {/,/^  }$/p' | grep -A1 -xF '      st.at = i;' | tail -1)" = '      loadShown();' ] \
  && ! echo "$SJ" | grep -qF "querySelectorAll('video[preload=\"none\"]')" || WX="$WX [loadShown in go]"
[ -z "$WX" ] && ok "the wide post's wiring: one query (WIDE), the one-column post assigned as before below it, the paper's links handed to the bar on a wide screen, the stage started after showOverlay, closePost and both choosers clear it, ← and → (never on a video or with a modifier), the redraw across WIDE (300 ms, never during full screen, only when the post no longer fits, its listener guarded for Safari before 14), the paper's fade while more is below, videos that load nothing until their slide shows" \
  || bad "the wide post's wiring (site/app.js)" "$WX"
# The wide post's videos (loadShown in startStage, site/app.js) run in node with a stand-in clock and slides: a slide's
# video loads its first frame (metadata) only once the slide has stayed 300 ms, and one at most every second, so holding
# → (a step every 80 ms) loads only where it stops and a step every 0.4 s loads every third; a video whose load failed (a
# 429 of the rate limiting rule) loads again when its slide shows again, a loaded one never again, and nothing loads once
# the post was closed or drawn again (stage is no longer this one).
STG=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("    let vt = 0, vlast = -1e9;"), b = s.indexOf("    st.go = (i, say) => {", a);
if (a < 0 || b < 0) throw new Error("loadShown is missing");
let now = 0, timers = [];
const setTimeout = (f, ms) => { timers.push({ f, at: now + ms }); return timers.length; };
const clearTimeout = (id) => { if (id && timers[id - 1]) timers[id - 1].f = null; };
const run = (to) => { for (;;) { const t = timers.filter((x) => x.f && x.at <= to).sort((x, y) => x.at - y.at)[0]; if (!t) break; now = t.at; const f = t.f; t.f = null; f(); } now = to; };
const performance = { now: () => now };
const got = [];
const vid = (i) => { let p = "none"; return { error: null, get preload() { return p; }, set preload(x) { if (x === "metadata" && p === "none") got.push(i + "@" + now); p = x; }, load() { got.push(i + " again@" + now); this.error = null; } }; };
const vids = Array.from({ length: 12 }, (_, i) => vid(i + 1));
const slide = (v) => ({ querySelectorAll: (q) => (q === "video" && v ? [v] : []) });
const els = [slide(null), ...vids.map(slide)];
const st = { at: 0 }, S = { stage: st };
const code = s.slice(a, b);
if (code.split("stage === st").length !== 2) throw new Error("loadShown checks stage once");
const X = new Function("els", "st", "S", "setTimeout", "clearTimeout", "performance", code.replace("stage === st", "S.stage === st") + "\nreturn { loadShown };")(els, st, S, setTimeout, clearTimeout, performance);
const go = (i) => { st.at = i; X.loadShown(); };
const bad = [], take = () => got.splice(0).join(" ");
go(0); for (let i = 1; i <= 8; i++) { run(80 * i); go(i); }
run(929); const held = take(); run(2000);
if (held !== "" || take() !== "8@940") bad.push("holding: only where it stops, 300 ms later");
for (let k = 0; k < 4; k++) { run(3000 + 400 * k); go(9 + k); }
run(6000);
if (take() !== "9@3300 12@4500") bad.push("a step every 0.4 s: one a second at most");
vids[8].error = { code: 4 };
run(7000); go(9); run(7290); go(10); run(8000);
const failed = take();
run(9000); go(9); run(10000);
if (failed !== "10@7590" || take() !== "9 again@9300") bad.push("a failed video loads again on its next showing: " + failed);
run(11000); go(10); run(12000);
if (take() !== "") bad.push("a loaded video loaded again");
run(13000); go(11); S.stage = null; run(15000);
if (take() !== "") bad.push("loaded after the post was closed");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/pl-app.js" 2>&1)
[ "$STG" = ok ] && ok "the wide post's videos (node): a slide's video loads 300 ms after it shows and one a second at most (holding → loads only where it stops, a step every 0.4 s every third), a failed one loads again on its next showing, a loaded one never again, nothing after the post closed" \
  || bad "site/app.js loadShown" "$STG"
# A receipt's videos in the one-column post (lazyVideos, site/app.js) run in node with a stand-in IntersectionObserver and
# clock: they load nothing (preload none) until each has been within 300 px of the paper's view for 250 ms, then their
# first frame (metadata), each once and one at most every second (also one that comes near only after the last started),
# those that came near first first; one that leaves sooner, or is gone from the page by then, loads nothing; a new post
# or closePost (lazyStop) ends the watch and its wait; without IntersectionObserver nothing loads before a tap on play.
# It is called after every receipt post is drawn, and closePost stops it.
LZV=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  let lazyStop = () => {};"), b = s.indexOf("\n  }\n", s.indexOf("  function lazyVideos(", a));
if (a < 0 || b < 0) throw new Error("lazyVideos is missing");
let now = 0, timers = [], io = null, made = 0;
const setTimeout = (f, ms) => { timers.push({ f, at: now + ms }); return timers.length; };
const clearTimeout = (id) => { if (id && timers[id - 1]) timers[id - 1].f = null; };
const run = (to) => { for (;;) { const t = timers.filter((x) => x.f && x.at <= to).sort((x, y) => x.at - y.at)[0]; if (!t) break; now = t.at; const f = t.f; t.f = null; f(); } now = to; };
const performance = { now: () => now };
class IO { constructor(cb, opt) { made++; io = this; this.cb = cb; this.opt = opt; this.seen = new Set(); this.off = false; }
  observe(v) { this.seen.add(v); } unobserve(v) { this.seen.delete(v); } disconnect() { this.off = true; this.seen.clear(); }
  fire(list) { this.cb(list.map(([v, on]) => ({ target: v, isIntersecting: on }))); } }
const vid = () => ({ preload: "none", isConnected: true });
let vids = [], paper = { p: 1 };
const overlay = { querySelector: (q) => (q === ".post-paper" ? paper : null), querySelectorAll: (q) => (q === ".post-media video[preload=\"none\"]" ? vids : []) };
let IntersectionObserver = IO;
const code = s.slice(a, b + 4);
const X = new Function("overlay", "setTimeout", "clearTimeout", "IO", "performance", code.replace("typeof IntersectionObserver", "typeof IO").replace("new IntersectionObserver(", "new IO(")
  + "\nreturn { lazyVideos, stop: () => lazyStop() };")(overlay, setTimeout, clearTimeout, IO, performance);
const bad = [], pre = () => vids.map((v) => v.preload[0]).join("");
vids = [vid(), vid(), vid()];
X.lazyVideos();
if (made !== 1 || io.opt.root !== paper || io.opt.rootMargin !== "300px 0px" || io.seen.size !== 3) bad.push("the watch: " + JSON.stringify([made, io.opt.rootMargin, io.seen.size]));
io.fire([[vids[0], true], [vids[1], true]]); run(100);
if (pre() !== "nnn") bad.push("loaded before 250 ms: " + pre());
io.fire([[vids[1], false]]); run(1000);
if (pre() !== "mnn" || io.seen.has(vids[0]) || !io.seen.has(vids[1])) bad.push("near for 250 ms, and one that left: " + pre());
io.fire([[vids[1], true], [vids[2], true]]); vids[2].isConnected = false; run(3000);
if (pre() !== "mmn") bad.push("near again, and one gone from the page: " + pre());
vids = [vid(), vid()];
X.lazyVideos(); now = 4000; io.fire([[vids[0], true]]); now = 4100; io.fire([[vids[0], false]]); now = 4200; io.fire([[vids[1], true]]);
run(4300); const early = pre(); run(4500);
if (early + " " + pre() !== "nn nm") bad.push("a video that came near after the wait began waits its own 250 ms: " + early + " " + pre());
vids = [vid(), vid(), vid(), vid()];
X.lazyVideos(); vids.forEach((v, i) => { now = 6000 + 10 * i; io.fire([[v, true]]); });
const steps = [6260, 7240, 7260, 8260, 9260].map((t) => { run(t); return pre(); });
if (steps.join() !== "mnnn,mnnn,mmnn,mmmn,mmmm") bad.push("one every second, in the order they came near: " + steps.join());
vids = [vid(), vid()];
X.lazyVideos(); now = 10000; io.fire([[vids[0], true]]); run(10260); now = 10300; io.fire([[vids[1], true]]);
run(11240); const mid = pre(); run(11260);
if (mid + " " + pre() !== "mn mm") bad.push("one that comes near after the last started waits the rest of its second: " + mid + " " + pre());
vids = [vid()]; const old = io;
X.lazyVideos();
if (!old.off || made !== 5) bad.push("a new post does not end the old watch");
now = 12000; io.fire([[vids[0], true]]); run(12100); X.stop(); run(16000);
if (pre() !== "n" || !io.off) bad.push("lazyStop left a wait: " + pre());
vids = []; X.lazyVideos();
if (made !== 5) bad.push("a watch with no video");
vids = [vid()]; IntersectionObserver = undefined;
const Y = new Function("overlay", "setTimeout", "clearTimeout", "performance", code + "\nreturn { lazyVideos };")(overlay, setTimeout, clearTimeout, performance);
Y.lazyVideos(); run(30000);
if (pre() !== "n") bad.push("without IntersectionObserver: " + pre());
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/pl-app.js" 2>&1)
OPR2=$(echo "$SJ" | sed -n '/^  function openPost(e) {/,/^  }$/p')
[ "$LZV" = ok ] && echo "$OPR2" | grep -qxF '    lazyVideos(); // the one column'"'"'s videos (a wide post has none in its paper)' \
  && [ "$(echo "$SJ" | sed -n '/^  function closePost() {/,/^  }$/p' | sed -n 3p)" = '    lazyStop();' ] \
  && echo "$OPR2" | grep -qF '${misVideo ? videoBox(misVideo, "NOW · MISSION #" + mis.no + " · VIDEO", true) : ""}' \
  && ok "a receipt's videos in the one-column post load their first frame only after 250 ms near the paper's view, each once and one every second at most, never once gone or after the post closed, and not without IntersectionObserver (node); every receipt post starts the watch, closePost ends it" \
  || bad "site/app.js lazyVideos" "$LZV"
# A long stage on a phone (site/app.js foldVideos and showRest, styles.css; Marcus on 2026-11-19: "Yes, shorten them", the
# originals kept): in the one-column post a stage of more than 3 videos shows its first 2, then SHOW ALL 30 BEFORE VIDEOS
# (SHOW ALL 30 AFTER VIDEOS, SHOW ALL 12 VIDEOS for those without a stage), and the rest of the stage waits hidden right
# after the button's box, loading nothing. foldVideos and the post's own markup (openPost's line, videoBox) in node:
# stages of 1, 2, 3, 4 and 30 and one without a stage, the words and counts, an unsafe link left out before the count,
# videosIn's videos in its order with its tags and numbers, every box of the strip a .pm (one dashed rule above each box
# but the first, folded or shown), the hidden ones with the hidden attribute and every player with preload none.
FLD=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  // ---------- the wide post\x27s slides (pure; tests/e2e.sh runs this block in node) ----------");
const b = s.indexOf("  // ---------- end of the wide post\x27s slides ----------");
if (a < 0 || b < a) throw new Error("the block is missing");
const k = s.indexOf("  const safeSrc = (u) =>"), safe = s.slice(k, s.indexOf("\n", s.indexOf("\n", k) + 1));
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m, /^  const nowOf = .*$/m, /^  const nowVideoOf = .*$/m, /^  const videoBox = .*$/m].map(line).join("\n");
const sp = s.slice(s.indexOf("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------"), s.indexOf("  // ---------- end of the spots ----------"));
const X = new Function(helpers + "\n" + safe + "\n" + sp + "\n" + s.slice(a, b) + "\nconst phone = (e) => {\n" + line(/^    const videos = foldVideos\(.*$/m) + "\n  return videos;\n};\nreturn { foldVideos, videosIn, phone };")();
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const K = (i) => "/media/" + i.toString(16).padStart(32, "0");
const rec = (stages) => ({ media: { videos: stages.map((_, i) => K(i)), video_stages: stages } });
const n = (k, st) => Array(k).fill(st);
// what the one column lists: each video by its tag, [h] when it waits hidden, and a button by its words in brackets
const col = (e) => X.foldVideos(X.videosIn(e)).map((v) => (v.more ? "[" + v.more + "]" : v.tag + (v.hid ? " [h]" : "")));
eq("a stage of 1, 2 or 3 shows whole", [col(rec(n(1, "before"))), col(rec(n(2, "after"))), col(rec(n(3, "before")))],
  [["BEFORE · VIDEO"], ["AFTER · VIDEO 1/2", "AFTER · VIDEO 2/2"], ["BEFORE · VIDEO 1/3", "BEFORE · VIDEO 2/3", "BEFORE · VIDEO 3/3"]]);
eq("a stage of 4: 2, the button, 2 hidden", col(rec(n(4, "before"))), ["BEFORE · VIDEO 1/4", "BEFORE · VIDEO 2/4", "[SHOW ALL 4 BEFORE VIDEOS]", "BEFORE · VIDEO 3/4 [h]", "BEFORE · VIDEO 4/4 [h]"]);
eq("3 before, 4 after and 12 without a stage", col(rec([...n(3, "before"), ...n(4, "after"), ...n(12, null)])).filter((t) => !t.endsWith(" [h]")),
  ["BEFORE · VIDEO 1/3", "BEFORE · VIDEO 2/3", "BEFORE · VIDEO 3/3", "AFTER · VIDEO 1/4", "AFTER · VIDEO 2/4", "[SHOW ALL 4 AFTER VIDEOS]", "VIDEO 1/12", "VIDEO 2/12", "[SHOW ALL 12 VIDEOS]"]);
eq("an unsafe link left out before the count: 3 of 4 show whole", col({ media: { videos: [K(0), "javascript:alert(1)", K(1), K(2)], video_stages: n(4, "after") } }),
  ["AFTER · VIDEO 1/3", "AFTER · VIDEO 2/3", "AFTER · VIDEO 3/3"]);
// 30 before and 30 after, sent in turns: each stage 2 shown, its button, 28 hidden; the videos those of videosIn, in
// its order, with its tags, numbers and stages
const big = rec(Array.from({ length: 60 }, (_, i) => (i % 2 ? "after" : "before"))), f = X.foldVideos(X.videosIn(big)), vi = X.videosIn(big);
eq("30 before and 30 after", [f.length, f.map((v, i) => (v.more ? i + " " + v.more : "")).filter(Boolean), f.filter((v) => !v.more && !v.hid).map((v) => v.tag + " " + v.src.slice(-2))],
  [62, ["2 SHOW ALL 30 BEFORE VIDEOS", "33 SHOW ALL 30 AFTER VIDEOS"], ["BEFORE · VIDEO 1/30 00", "BEFORE · VIDEO 2/30 02", "AFTER · VIDEO 1/30 01", "AFTER · VIDEO 2/30 03"]]);
eq("the same videos in the same order, tags, numbers and stages unchanged", f.filter((v) => !v.more).map((v) => [v.src, v.tag, v.stage, v.video]), vi.map((v) => [v.src, v.tag, v.stage, v.video]));
eq("hidden: the 3rd to the 30th of each stage, each right after its button", [f.filter((v) => v.hid).map((v) => v.tag).join(), f[3].tag, f[34].tag],
  [[...Array(28)].map((_, i) => "BEFORE · VIDEO " + (i + 3) + "/30").concat([...Array(28)].map((_, i) => "AFTER · VIDEO " + (i + 3) + "/30")).join(), "BEFORE · VIDEO 3/30", "AFTER · VIDEO 3/30"]);
eq("no video, and the words: plain capitals and digits, no dash", [X.foldVideos(X.videosIn({})), f.filter((v) => v.more).every((v) => /^SHOW ALL \d+ (BEFORE |AFTER )?VIDEOS$/.test(v.more))], [[], true]);
// the markup of the one column, from the line in openPost and videoBox: the button in a box of its own right after the 2nd
// video, every box of the strip a .pm (one dashed rule above each but the first, folded or not), the 56 hidden with the
// hidden attribute, and all 60 players loading nothing (preload none) until lazyVideos
const h = X.phone(big), boxes = h.match(/<div class="pm [^"]*"( hidden)?>/g) || [];
eq("the markup", [boxes.length, boxes.filter((x) => x.endsWith(" hidden>")).length, h.split("<div").length - 1, (h.match(/<video controls playsinline preload="none" src="/g) || []).length, (h.match(/<video /g) || []).length,
  h.includes("<div class=\"pm pm-video\"><span class=\"tag\">BEFORE · VIDEO 2/30</span><video controls playsinline preload=\"none\" src=\"" + K(2) + "\" aria-label=\"before · video 2/30\"></video></div><div class=\"pm pm-more\"><button type=\"button\" class=\"post-link pm-show\">SHOW ALL 30 BEFORE VIDEOS</button></div><div class=\"pm pm-video\" hidden><span class=\"tag\">BEFORE · VIDEO 3/30</span><video controls playsinline preload=\"none\" src=\"" + K(4) + "\" aria-label=\"before · video 3/30\"></video></div>"),
  h.endsWith("<div class=\"pm pm-video\" hidden><span class=\"tag\">AFTER · VIDEO 30/30</span><video controls playsinline preload=\"none\" src=\"" + K(59) + "\" aria-label=\"after · video 30/30\"></video></div>")],
  [62, 56, 62, 60, 60, true, true]);
eq("a stage of 3 in the markup: no button, nothing hidden", [X.phone(rec(n(3, "after"))).includes("pm-more"), X.phone(rec(n(3, "after"))).includes(" hidden")], [false, false]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 10");
' "$T/pl-app.js" 2>&1)
check "a long stage on a phone (site/app.js foldVideos, node): a stage of 1, 2 or 3 videos whole, one of 4 or 30 its first 2, then SHOW ALL 4 (30) BEFORE VIDEOS, SHOW ALL 30 AFTER VIDEOS or SHOW ALL 12 VIDEOS without a stage, then the rest hidden; the videos, order, tags and numbers of videosIn unchanged; in the markup the button in a .pm box of its own, 56 of 60 boxes hidden and all 60 players preload none" "$FLD" "ok 10"
# The press (showRest, run in node on a stand-in for the strip read from that markup): SHOW ALL 30 BEFORE VIDEOS goes, the
# 28 others of its stage show under the first 2 in order, the after stage stays folded until its own button, the focus
# goes to the first video shown once it shows, with no scroll (preventScroll), the paper keeps its scroll (the stand-in
# moves it as Chrome's scroll anchoring did with the top of the view in the button's box, unless showRest sets it back),
# and the post's double-click guard is armed at the press. openPost wires each button to it once the post is drawn,
# nothing else calls it, and it calls no scroll.
FRV=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  // ---------- the wide post\x27s slides (pure; tests/e2e.sh runs this block in node) ----------");
const b = s.indexOf("  // ---------- end of the wide post\x27s slides ----------");
if (a < 0 || b < a) throw new Error("the block is missing");
const k = s.indexOf("  const safeSrc = (u) =>"), safe = s.slice(k, s.indexOf("\n", s.indexOf("\n", k) + 1));
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m, /^  const nowOf = .*$/m, /^  const nowVideoOf = .*$/m, /^  const videoBox = .*$/m].map(line).join("\n");
const sp = s.slice(s.indexOf("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------"), s.indexOf("  // ---------- end of the spots ----------"));
const X = new Function(helpers + "\n" + safe + "\n" + sp + "\n" + s.slice(a, b) + "\nconst phone = (e) => {\n" + line(/^    const videos = foldVideos\(.*$/m) + "\n  return videos;\n};\nreturn { videosIn, phone };")();
const fa = s.indexOf("  function showRest(box) {"), fb = s.indexOf("\n  }\n", fa);
if (fa < 0 || fb < 0) throw new Error("showRest is missing");
// showRest with the double-click guard of the post around it (openedAt, openX, openY), the press at 120, 340
const G = new Function("performance", "let openedAt = 0, openX = NaN, openY = NaN, pressX = 120, pressY = 340;\n" + s.slice(fa, fb + 4)
  + "\nreturn { showRest, guard: () => [openedAt, openX, openY] };")({ now: () => 4242 }), showRest = G.showRest;
// a stand-in for the strip of the post: its boxes in order, read from the markup of the one column; a box knows its next
// sibling, can be removed, and gives its player and its paper; a player takes the focus and says with what, and whether
// its box was still hidden then. The paper as Chrome lays it out with the top of its view in the button box: each box
// shown moves the scroll down by its height at the next layout (a read or a write of scrollTop), as the scroll anchoring
// of Chrome held the first video of the next stage in place; a write sets the scroll after that layout.
const focus = [];
const paper = { at: 1690, moved: 0, get scrollTop() { this.at += this.moved; this.moved = 0; return this.at; }, set scrollTop(y) { this.moved = 0; this.at = y; } };
const strip = (html) => {
  const kids = [];
  for (const m of html.matchAll(/<div class="pm (pm-[a-z]+)"( hidden)?>(.*?)<\/div>/g)) {
    const v = m[3].match(/^<span class="tag">([^<]*)<\/span><video controls playsinline preload="(\w+)" src="([^"]*)"/);
    let hid = !!m[2];
    const box = { cls: m[1], words: v ? null : m[3].replace(/<[^>]*>/g, ""),
      get hidden() { return hid; }, set hidden(x) { if (hid && !x) paper.moved += 562; hid = !!x; },
      video: v ? { tag: v[1], preload: v[2], isConnected: true, focus(o) { focus.push((hid ? "while hidden: " : "") + v[1] + " " + JSON.stringify(o)); } } : null,
      get nextElementSibling() { const i = kids.indexOf(this); return i < 0 ? null : kids[i + 1] || null; },
      remove() { const i = kids.indexOf(this); if (i >= 0) kids.splice(i, 1); },
      closest(q) { return q === ".post-paper" ? paper : null; },
      querySelector(q) { return q === "video" ? this.video : null; } };
    kids.push(box);
  }
  return kids;
};
const K = (i) => "/media/" + i.toString(16).padStart(32, "0");
const big = { media: { videos: Array.from({ length: 61 }, (_, i) => K(i)), video_stages: Array.from({ length: 61 }, (_, i) => (i === 60 ? null : i < 30 ? "before" : "after")) } };
const all = X.videosIn(big).map((v) => v.tag);
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const kids = strip(X.phone(big));
const shown = () => kids.filter((x) => !x.hidden).map((x) => (x.video ? x.video.tag : "[" + x.words + "]"));
eq("folded", shown(), ["BEFORE · VIDEO 1/30", "BEFORE · VIDEO 2/30", "[SHOW ALL 30 BEFORE VIDEOS]", "AFTER · VIDEO 1/30", "AFTER · VIDEO 2/30", "[SHOW ALL 30 AFTER VIDEOS]", "VIDEO"]);
showRest(kids.find((x) => x.words === "SHOW ALL 30 BEFORE VIDEOS"));
eq("SHOW ALL 30 BEFORE VIDEOS: its button gone, the 28 others of its stage shown under the first 2 in order, the after stage still folded, the focus on BEFORE · VIDEO 3/30 once shown, with no scroll, the paper where it was and the double-click guard armed at the press",
  [kids.length, shown(), focus, paper.scrollTop, G.guard()], [62, [...all.slice(0, 32), "[SHOW ALL 30 AFTER VIDEOS]", "VIDEO"], ["BEFORE · VIDEO 3/30 {\"preventScroll\":true}"], 1690, [4242, 120, 340]]);
paper.scrollTop = 18000;
showRest(kids.find((x) => x.words === "SHOW ALL 30 AFTER VIDEOS"));
eq("then SHOW ALL 30 AFTER VIDEOS: every video in the order of videosIn, no button left, the focus on AFTER · VIDEO 3/30, the paper where it was",
  [kids.length, shown(), kids.every((x) => x.video && !x.hidden && x.video.preload === "none"), focus.slice(1), paper.scrollTop], [61, all, true, ["AFTER · VIDEO 3/30 {\"preventScroll\":true}"], 18000]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 3");
' "$T/pl-app.js" 2>&1)
[ "$FRV" = "ok 3" ] && echo "$OPR2" | grep -qxF '    overlay.querySelectorAll(".pm-show").forEach((b) => b.addEventListener("click", () => showRest(b.parentElement)));' \
  && [ "$(echo "$OPR2" | grep -nF '    overlay.innerHTML = ' | cut -d: -f1)" -lt "$(echo "$OPR2" | grep -nF '    overlay.querySelectorAll(".pm-show")' | cut -d: -f1)" ] \
  && [ "$(echo "$SJ" | grep -cF 'showRest(')" = 2 ] && ! echo "$SJ" | sed -n '/^  function showRest(box) {/,/^  }$/p' | grep -qE 'scrollIntoView|scrollTo\(|scrollBy\(' \
  && ok "SHOW ALL 30 BEFORE VIDEOS pressed (site/app.js showRest, node): its button goes, the 28 others of its stage show under the first 2 in order, the other stage stays folded, the focus moves to the first video shown once it shows, with no scroll, the paper keeps its scroll where Chrome's scroll anchoring moved it, and the second click of a double click there does nothing (the post's guard); openPost wires every such button once the post is drawn, and showRest calls no scroll" \
  || bad "site/app.js showRest" "$FRV"
# lazyVideos and showRest together in node, with a stand-in layout and IntersectionObserver that never finds a hidden box
# near: the post of 30 before and 30 after watches all 60 videos from the start, the 56 hidden too; nothing hidden loads
# while it waits, read down to its button or not; once SHOW ALL is pressed the video shown where the button was loads 250
# ms later and the next one near it a second after, and reading on loads the rest one by one, as for any video.
FLZ=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const a = s.indexOf("  // ---------- the wide post\x27s slides (pure; tests/e2e.sh runs this block in node) ----------");
const b = s.indexOf("  // ---------- end of the wide post\x27s slides ----------");
if (a < 0 || b < a) throw new Error("the block is missing");
const k = s.indexOf("  const safeSrc = (u) =>"), safe = s.slice(k, s.indexOf("\n", s.indexOf("\n", k) + 1));
const helpers = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m, /^  const isNo = .*$/m, /^  const missionOf = .*$/m, /^  const nowOf = .*$/m, /^  const nowVideoOf = .*$/m, /^  const videoBox = .*$/m].map(line).join("\n");
const sp = s.slice(s.indexOf("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------"), s.indexOf("  // ---------- end of the spots ----------"));
const X = new Function(helpers + "\n" + safe + "\n" + sp + "\n" + s.slice(a, b) + "\nconst phone = (e) => {\n" + line(/^    const videos = foldVideos\(.*$/m) + "\n  return videos;\n};\nreturn { phone };")();
const fa = s.indexOf("  function showRest(box) {"), fb = s.indexOf("\n  }\n", fa);
if (fa < 0 || fb < 0) throw new Error("showRest is missing");
const showRest = new Function("performance", "let openedAt = 0, openX = NaN, openY = NaN, pressX = NaN, pressY = NaN;\n" + s.slice(fa, fb + 4) + "\nreturn showRest;")({ now: () => 0 });
const la = s.indexOf("  let lazyStop = () => {};"), lb = s.indexOf("\n  }\n", s.indexOf("  function lazyVideos(", la));
if (la < 0 || lb < 0) throw new Error("lazyVideos is missing");
// the strip of the post as in the reveal check: its boxes in order, from the markup of the one column, and their paper
const strip = (html) => {
  const kids = [];
  for (const m of html.matchAll(/<div class="pm (pm-[a-z]+)"( hidden)?>(.*?)<\/div>/g)) {
    const v = m[3].match(/^<span class="tag">([^<]*)<\/span><video controls playsinline preload="(\w+)" src="([^"]*)"/);
    kids.push({ hidden: !!m[2], words: v ? null : m[3].replace(/<[^>]*>/g, ""), video: v ? { tag: v[1], preload: v[2], isConnected: true, focus() {} } : null,
      get nextElementSibling() { const i = kids.indexOf(this); return i < 0 ? null : kids[i + 1] || null; },
      remove() { const i = kids.indexOf(this); if (i >= 0) kids.splice(i, 1); },
      closest(q) { return q === ".post-paper" ? paper : null; },
      querySelector(q) { return q === "video" ? this.video : null; } });
  }
  return kids;
};
const K = (i) => "/media/" + i.toString(16).padStart(32, "0");
const kids = strip(X.phone({ media: { videos: Array.from({ length: 60 }, (_, i) => K(i)), video_stages: Array.from({ length: 60 }, (_, i) => (i < 30 ? "before" : "after")) } }));
// A stand-in layout and IntersectionObserver, as a browser runs them: the photos take the first 600 px of the paper, a
// video box 562 and the button box 72, a hidden box none; the paper shows 776 px. On each layout (look) the observer
// tells of every watched video whose state changed, near being within 300 px above or below the view, never while its
// box is hidden; the first look tells of every one.
const paper = { scrollTop: 0, clientHeight: 776 };
const top = (box) => { let y = 600; for (const x of kids) { if (x === box) return y; if (!x.hidden) y += x.video ? 562 : 72; } return null; };
const near = (v) => { const box = kids.find((x) => x.video === v), y = box && !box.hidden ? top(box) : null;
  return y !== null && y < paper.scrollTop + paper.clientHeight + 300 && y + 562 > paper.scrollTop - 300; };
let now = 0, timers = [], io = null;
const setTimeout = (f, ms) => { timers.push({ f, at: now + ms }); return timers.length; };
const clearTimeout = (id) => { if (id && timers[id - 1]) timers[id - 1].f = null; };
const run = (to) => { for (;;) { const t = timers.filter((x) => x.f && x.at <= to).sort((x, y) => x.at - y.at)[0]; if (!t) break; now = t.at; const f = t.f; t.f = null; f(); } now = to; };
const performance = { now: () => now };
class IO { constructor(cb, opt) { io = this; this.cb = cb; this.opt = opt; this.seen = new Map(); }
  observe(v) { this.seen.set(v, null); } unobserve(v) { this.seen.delete(v); } disconnect() { this.seen.clear(); }
  look() { const list = []; for (const [v, was] of this.seen) { const on = near(v); if (on !== was) { this.seen.set(v, on); list.push({ target: v, isIntersecting: on }); } } if (list.length) this.cb(list); } }
const overlay = { querySelector: (q) => (q === ".post-paper" ? paper : null),
  querySelectorAll: (q) => (q === ".post-media video[preload=\"none\"]" ? kids.filter((x) => x.video && x.video.preload === "none").map((x) => x.video) : []) };
const L = new Function("overlay", "setTimeout", "clearTimeout", "IO", "performance", s.slice(la, lb + 4).replace("typeof IntersectionObserver", "typeof IO").replace("new IntersectionObserver(", "new IO(")
  + "\nreturn { lazyVideos };")(overlay, setTimeout, clearTimeout, IO, performance);
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
// the 60 players in the order of the strip, m for metadata (loaded) and n for none
const pre = () => kids.filter((x) => x.video).map((x) => x.video.preload[0]).join("");
const m = (i) => "m".repeat(i), n = (i) => "n".repeat(i);
const scrollTo = (y, ms) => { paper.scrollTop = y; io.look(); run(now + ms); };
L.lazyVideos();
if (!io) { console.log("wrong: no watch at all"); process.exit(0); }
const watched = io.seen.size;
io.look(); run(5000);
eq("open: all 60 watched, the 56 hidden too, and at the top only BEFORE · VIDEO 1/30 loads", [watched, pre()], [60, m(1) + n(59)]);
const more = kids.find((x) => x.words === "SHOW ALL 30 BEFORE VIDEOS");
scrollTo(top(more) - 500, 5000);
eq("at SHOW ALL 30 BEFORE VIDEOS: its 2nd video and AFTER · VIDEO 1/30 under it load, none of the 28 hidden", pre(), m(2) + n(28) + m(1) + n(29));
showRest(more); io.look(); run(now + 500);
const b3 = pre(); run(now + 1000);
eq("pressed: BEFORE · VIDEO 3/30, shown where the button was, loads 250 ms later and 4/30, near under it, a second after", [b3, pre()], [m(3) + n(27) + m(1) + n(29), m(4) + n(26) + m(1) + n(29)]);
for (let y = paper.scrollTop; y < top(kids.find((x) => x.words === "SHOW ALL 30 AFTER VIDEOS")) - 500; y += 562) scrollTo(y, 1500);
scrollTo(top(kids.find((x) => x.words === "SHOW ALL 30 AFTER VIDEOS")) - 500, 5000);
eq("read down to SHOW ALL 30 AFTER VIDEOS: all 30 before load one by one, and AFTER · VIDEO 2/30, none of the 28 still hidden", pre(), m(32) + n(28));
showRest(kids.find((x) => x.words === "SHOW ALL 30 AFTER VIDEOS")); io.look(); run(now + 500);
const a3 = pre(); run(now + 1000);
eq("pressed: AFTER · VIDEO 3/30 loads, then 4/30", [a3, pre()], [m(33) + n(27), m(34) + n(26)]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 5");
' "$T/pl-app.js" 2>&1)
check "the hidden videos of a long stage load nothing (preload none) until SHOW ALL, and lazyVideos, which watched them from the start, loads them once shown and near, one a second (site/app.js, node)" "$FLZ" "ok 5"
FOC=""
for t in '.post-media .pm[hidden] { display: none; }' '.post-media .pm-more { padding: 12px 14px 16px; text-align: center; }' '.post-media .pm-show { min-height: 44px; }' \
         '.post-media .pm + .pm { border-top: 2px dashed var(--rule); }'; do
  echo "$SC" | grep -qxF -- "$t" || FOC="$FOC [$t]"
done
[ "$(echo "$SC" | grep -cE 'pm-more|pm-show')" = 2 ] || FOC="$FOC [another rule names the button]"
[ -z "$FOC" ] && ok "styles.css: SHOW ALL in a box of its own between the dashed rules (one above each box on show, folded or not), the post's yellow button 44 px tall, hidden boxes take no room" \
  || bad "styles.css, the folded stage" "$FOC"
# The one-column post is never taller than the screen as it shows (site/styles.css .post-paper): 100dvh after the 100vh
# fallback, in that order. With 100vh alone the paper stood 38 px taller than an iPhone 17 Pro on its side, the overlay
# scrolled, and only 4 px of the ✕ at the paper's top was in view (Mobile Safari, iOS Simulator, 2026-11-20).
PPR=$(echo "$SC" | awk '/^\.post-paper [{]/ { p = 1 } p && /max-height/ { print; exit } p && /^[}]/ { exit }')
check "styles.css: a phone's post is at most as high as the screen as it shows (100dvh after the 100vh fallback), so its ✕ stays on screen while the browser's bars show" \
  "$PPR" "  max-height: calc(100vh - 36px); max-height: calc(100dvh - 36px);"
# ... and never starts above the screen (.post-overlay): safe center after the center fallback, in that order. With
# center alone a paper taller than the backdrop put half of the extra above the top, where no scroll reaches: with
# Safari's address bar at the top the ✕ sat at -51 to -17 px, under the bar, and took no tap (iOS Simulator, 2026-11-20).
POV=$(echo "$SC" | awk '/^\.post-overlay [{]/ { p = 1 } p && /place-items/ { print; exit } p && /^[}]/ { exit }')
check "styles.css: a post taller than the backdrop starts at its top and scrolls (safe center after the center fallback), so its ✕ never sits above the screen" \
  "$POV" "  display: grid; place-items: center; place-items: safe center; padding: 18px;"
# Tab and Shift+Tab stay in every open post and chooser (site/app.js): the handler itself, run in node with four controls
# (the last one hidden, so it has no client rects) and a stand-in for the focus. Tab on the last shown control goes to the
# first, Shift+Tab on the first to the last, Tab or Shift+Tab from outside the dialog to the first or last, each with the
# browser's own move stopped; anywhere else, with another key, or with nothing open, it does nothing.
WTAB=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  // Tab and Shift+Tab stay in the open post or chooser"), b = s.indexOf("\n  });\n", a);
if (a < 0 || b < a) throw new Error("the Tab handler is missing");
let handler = null, asked = "";
const doc = { activeElement: null };
const el = (name, shown = true) => ({ name, getClientRects: () => (shown ? [{}] : []), focus() { doc.activeElement = this; } });
const ctl = [el("close"), el("thanks"), el("all"), el("hidden", false)];
const box = { contains: (x) => ctl.includes(x), querySelectorAll: (q) => { asked = q; return ctl; } };
const overlay = { hidden: false, querySelector: (q) => (q === "[role=\"dialog\"]" ? box : null) };
new Function("addEventListener", "overlay", "document", s.slice(a, b + 6))((type, f) => { if (type === "keydown") handler = f; }, overlay, doc);
const press = (key, shift, at) => { doc.activeElement = at; let stop = false; handler({ key, shiftKey: shift, preventDefault() { stop = true; } }); return doc.activeElement.name + (stop ? " stopped" : ""); };
const out = { name: "body" };
const got = [press("Tab", false, ctl[2]), press("Tab", true, ctl[0]), press("Tab", false, out), press("Tab", true, out),
  press("Tab", false, ctl[0]), press("Tab", true, ctl[2]), press("Tab", false, ctl[1]), press("Tab", true, ctl[1]), press("Enter", false, ctl[2])];
overlay.hidden = true; got.push(press("Tab", false, ctl[2]));
const want = ["close stopped", "all stopped", "close stopped", "all stopped", "close", "all", "thanks", "thanks", "all", "all"];
console.log(JSON.stringify(got) === JSON.stringify(want) && asked === "a[href], button, video[controls]" ? "ok" : "wrong: " + JSON.stringify(got) + " " + asked);
' "$T/pl-app.js" 2>&1)
check "Tab and Shift+Tab stay inside every open post and chooser at every size (site/app.js, the handler run in node): from the last shown control to the first and back, from outside the dialog to its first or last, the browser's own move stopped then, and nothing anywhere else" "$WTAB" "ok"
# styles.css: the wide post's rules name only its own classes (.post-frame, .pv-*), have no media query, transition or
# animation, and no rule elsewhere names them, so none of them can reach a phone's post; the frame takes no clicks (its
# children do), so its empty parts pass them to the backdrop; the paper's ✕ and SEE THE SPOT ON SATELLITE reach 44 px
# through an ::after inside a positioned button (unpositioned, it would cover the whole paper), and only in the paper, so
# no hit area reaches over a link under it; the post's links under the photos are 44 px tall, on their own row or, on a
# stage from 860 px, at the end of the arrows' row; the count is as wide as 16 / 16, so the arrows stay put; the paper's
# bottom fades while more is below.
WCSS=$(python3 - "$SC" <<'PY'
import re, sys
css = sys.argv[1]
start = css.find("/* ===== the wide post (site/app.js WIDE, wideHtml, startStage)")
end = css.find("@media (prefers-reduced-motion: reduce)")
bad = []
if start < 0 or end < start:
    bad.append("the block, before the reduced motion block")
block, rest = css[start:end], css[:start] + css[end:]
plain = re.sub(r"(?s)/\*.*?\*/", "", block)
if re.search(r"@media|transition|animation", plain):
    bad.append("a media query, transition or animation")
sels = [" ".join(one.split()) for s, _ in re.findall(r"([^{}]+)\{([^{}]*)\}", re.sub(r"@supports[^{]*\{", "", plain)) for one in s.split(",") if one.strip()]
off = [s for s in sels if not re.search(r"\.post-frame(?![\w-])|\.pv-[a-z]", s)]
if off:
    bad.append("not the wide post's: " + " | ".join(off))
if re.search(r"\.post-frame(?![\w-])|\.pv-[a-z]", re.sub(r"(?s)/\*.*?\*/", "", rest)):
    bad.append("a rule outside the block")
for must in [".post-frame {\n  display: flex; align-items: flex-start; gap: 22px;\n  width: min(1760px, 100%); height: calc(100vh - 36px); height: calc(100dvh - 36px);\n  pointer-events: none;\n}",
             ".post-frame > * { pointer-events: auto; }", ".pv-slide[hidden] { display: none; }",
             ".post-frame .post-link { position: relative; }",
             '.post-frame .post-close::after { content: ""; position: absolute; inset: -7px; }',
             '.post-frame .post-paper .post-link::after { content: ""; position: absolute; inset: -7px 0; }',
             "  width: 56px; height: 44px; padding: 0; cursor: pointer;",
             "  order: -1; position: relative; flex: 1 1 0; min-width: 0; align-self: stretch; container-type: inline-size;",
             ".pv-count { min-width: calc(7ch + 16px); ",
             ".pv-acts {\n  grid-column: 1 / -1; justify-self: center;\n",
             "@container (min-width: 860px) {\n  .pv-bar { grid-template-columns: auto 1fr auto; }\n  .pv-nav { justify-self: center; }\n  .pv-acts { grid-column: 3; justify-self: end; justify-content: flex-end; }\n}",
             ".pv-acts .post-link { min-height: 44px; ",
             '.post-frame .post-paper.pv-more::after {\n  content: ""; position: sticky; bottom: -4px; display: block; height: 48px; margin-top: -48px; pointer-events: none;\n  background: linear-gradient(rgba(253, 250, 241, 0), var(--paper) 85%);\n}']:
    if must not in block:
        bad.append("missing " + must)
if ".post-frame .post-link::after" in plain:
    bad.append("a hit area on every yellow button, the bar's too")
print("ok" if not bad else "wrong: " + "; ".join(bad))
PY
)
check "styles.css: the wide post's rules name only its own classes, with no media query, transition or animation, and no other rule names them, so a phone's post meets none; the frame takes no clicks, so a click beside the paper reaches the backdrop; ✕ and SEE THE SPOT ON SATELLITE reach 44 px there, the post's links under the photos are 44 px tall, the arrows stay put from 9 / 12 to 10 / 12, and the paper fades at its bottom while more is below" "$WCSS" "ok"
# The crew page: the total above YOUR CLEANUPS and the note under it, its keys in EN and ID (node), and each published
# cleanup's count in its line.
MINE=$(echo "$UP" | sed -n '/<section class="panel" id="mine" hidden>/,/<\/section>/p')
[ "$(echo "$MINE" | grep -oE 'id="(thanksTotal|mineList|thanksNote)"' | tr '\n' ' ')" = 'id="thanksTotal" id="mineList" id="thanksNote" ' ] \
  && echo "$MINE" | grep -qF '<p class="hint cp-thanks" id="thanksTotal" aria-live="polite" hidden></p>' && echo "$MINE" | grep -qF '<p class="hint cp-tnote" id="thanksNote" hidden></p>' \
  && echo "$UJ" | grep -qF 'const keep = (text) => String(text).replace(/ /g, "\u00a0");' \
  && echo "$UJ" | grep -qF '? "\u00a0· " + keep(t(s.thanks === 1 ? "mine_thanked_1" : "mine_thanked", { n: countText(s.thanks) })) : "";' \
  && echo "$UJ" | grep -qF 'small.textContent = `${keep(fmtDay(s.cleanup_date, true) || s.cleanup_date)}\u00a0· ${keep(t("st_" + s.status))}${thanked}`;' \
  && grep -qF '.mine-list small { font-family: var(--font-mono); font-size: 11.5px; color: var(--dim); overflow-wrap: anywhere; }' site/forms.css \
  && echo "$UJ" | grep -qF 'if (published) setMsg(note, "ty_note", { btn: ["ID", "MY"].includes(partner.country) ? "SAY TERIMA KASIH" : "SAY THANK YOU" }); else setMsg(note);' \
  && grep -qF '.cp-thanks { color: #1a7a3a; font-weight: 700; margin: 0 0 6px; }' site/forms.css && grep -qF '.sub.p-thanks { margin: -10px 0 22px; }' site/forms.css \
  && ok "the crew page: the thanks total above YOUR CLEANUPS, the note on the button under it, and each published cleanup's count in its line" || bad "crew page thanks" "$MINE"
TYK=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  const T = {"), b = s.indexOf("\n  };", a);
const T = new Function("return (" + s.slice(a + "  const T = ".length, b + 4) + ");")();
const want = {
  en: { mine_thanked: "thanked {n} times", mine_thanked_1: "thanked once", ty_total: "Visitors on sapu.earth thanked your crew {n} times.", ty_total_1: "Visitors on sapu.earth thanked your crew once.",
    ty_note: "Anyone can tap {btn} under your receipts on sapu.earth. It is not money, only a sign that people value your crew\x27s work, and it counts taps, not people. Share your receipts so more people see them." },
  id: { mine_thanked: "{n} ucapan terima kasih", mine_thanked_1: "1 ucapan terima kasih", ty_total: "Pengunjung sapu.earth sudah {n} kali berterima kasih atas aksi bersih kru kamu.",
    ty_total_1: "Pengunjung sapu.earth sudah 1 kali berterima kasih atas aksi bersih kru kamu.",
    ty_note: "Siapa pun bisa menekan {btn} di laporan aksi bersih kamu di sapu.earth. Ini bukan uang, hanya tanda bahwa orang menghargai kerja kru kamu, dan yang dihitung adalah jumlah ketukan, bukan jumlah orang. Bagikan laporannya supaya lebih banyak orang melihatnya." } };
const bad = [];
for (const l of ["en", "id"]) for (const [k, v] of Object.entries(want[l])) if (T[l][k] !== v || /[\u2013\u2014]/.test(T[l][k])) bad.push(l + " " + k);
if (T.en.thanks !== "THANK YOU!" || T.id.thanks !== "TERIMA KASIH!") bad.push("the THANK YOU! after a send changed");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok");
' "$T/crew.js" 2>&1)
check "the crew page's thanks texts: mine_thanked, mine_thanked_1, ty_total, ty_total_1 and ty_note in EN and ID, as written, no dashes (\"It is not money\", \"Ini bukan uang\"), and THANK YOU! after a send as it was (node)" "$TYK" ok
# /admin/: THANKS BY DAY with its two undos and the line on each APPROVED card.
TYA=""
for t in '<h2 class="panel-title">THANKS BY DAY (UTC)</h2>' \
         'const nThanks = (n) => (n === 1 ? "1 thank you" : `${fmt(n)} thanks`);' \
         'if (d.closed) return `<li><span>${when}: undone, ${esc(nThanks(d.taken))} taken off.</span></li>`;' \
         'if (!(d.n > 0)) return `<li><span>${when}: ${esc(nThanks(d.taken))} taken off.</span></li>`;' \
         'return `<li><span>${when}: ${esc(nThanks(d.n))}${top ? `, the most on ${esc(top.place_name)} (${esc(fmt(top.n))})` : ""}.` +' \
         '`${d.full ? " The daily cap is reached." : ""}${d.taken > 0 ? ` ${esc(nThanks(d.taken))} already taken off.` : ""}</span>` +' \
         '<button type="button" class="b b-sm b-red" data-undo-receipt="${esc(top.id)}" data-day="${esc(d.day)}">UNDO ON THAT RECEIPT</button>' \
         '<button type="button" class="b b-sm b-red" data-undo-day="${esc(d.day)}">UNDO THE WHOLE DAY</button>' \
         'One tap under a receipt is one thank you. A receipt counts at most ${esc(fmt(caps.receipt))} a day and the whole site ${esc(fmt(caps.site))} (UTC days), and thanks taken off still count toward that day'"'"'s caps. UNDO ON THAT RECEIPT takes that receipt'"'"'s thanks of that day off for good, and that receipt takes no more thanks that day. UNDO THE WHOLE DAY takes all thanks of that day off the receipts for good, and nobody can thank on sapu.earth for the rest of that day. Use them only for a day that looks inflated, never to change a crew'"'"'s numbers otherwise. A day with ${esc(fmt(caps.busy_site))} or more thanks in all, or ${esc(fmt(caps.busy_receipt))} or more on one receipt, also comes up in the GitHub note.' \
         '? `Take the ${nThanks(d.top.n)} of ${when} off ${place}? This cannot be undone, and that receipt takes no more thanks that day (UTC).`' \
         ': `Take ${d.n === 1 ? "the 1 thank you" : `all ${fmt(d.n)} thanks`} of ${when} off the receipts? This cannot be undone, and nobody can thank on sapu.earth for the rest of that day (UTC).`)) return;' \
         'flash(id ? `The ${nThanks(r.taken)} of ${when} ${was} taken off ${place}.` : `The ${nThanks(r.taken)} of ${when} ${was} taken off the receipts.`);' \
         'const was = r.taken === 1 ? "was" : "were";' \
         'line.textContent = s.thanks > 0 ? `Thanked ${fmt(s.thanks)} ${s.thanks === 1 ? "time" : "times"}.` : "No thanks yet.";' \
         '($("[data-postbox]", el) || $(".dl-list", el)).after(line);' \
         'const daysBox = tab === "approved" && Array.isArray(days) && days.length && caps ? thanksDaysBox(days, caps) : null;'; do
  echo "$AJ" | grep -qF -- "$t" || TYA="$TYA [$t]"
done
[ -z "$TYA" ] && grep -qF '.am-tdays li { display: flex; flex-wrap: wrap; gap: 6px 10px; align-items: center;' admin/admin.css && grep -qF '.am-thanks { color: var(--ink); margin-top: 8px; }' admin/admin.css \
  && grep -qF '.am-tdays li > span { flex-basis: 100%; }' admin/admin.css \
  && ok "/admin/: THANKS BY DAY (UTC) above the APPROVED cards with each day's line, UNDO ON THAT RECEIPT and UNDO THE WHOLE DAY (each asks first and says what came off), the hint with the caps, and Thanked N times. or No thanks yet. after COMMENTS LINK" \
  || bad "admin.js thanks texts" "$TYA"
# The visitor notice: its Thanks line (after the satellite map, before Instagram and TikTok) and its What we keep sentence.
echo "$VN" | grep -qF "<li><b>Thanks:</b> if you tap SAY THANK YOU under a receipt (SAY TERIMA KASIH on a receipt from Indonesia or Malaysia), our code uses only which receipt it was, after checking that the tap came from a page of sapu.earth. As with any page, Cloudflare receives the request (Hosting, above). Our database adds one to that receipt's count and to the counts of that day (UTC), which keep the thanks within daily limits. It keeps nothing about you: no internet address, no time of day, no cookie, and nothing saved on your device. The page remembers your tap only while it is open, and the counts cannot show who thanked. The counts show on the receipt, the crew's page and the list of crews, and go when the receipt goes off sapu.earth. Legal basis: our legitimate interest in letting visitors thank the crews (GDPR Art. 6(1)(f)).</li>" \
  && echo "$VN" | grep -qF '<li><b>What we keep:</b> nothing about your visit. Thanking a crew under a receipt only adds one to a count and says nothing about you (Thanks, below). Our own code and database never store your internet address.' \
  && [ "$(echo "$VN" | grep -n '<b>Satellite map:</b>' | cut -d: -f1)" -lt "$(echo "$VN" | grep -n '<b>Thanks:</b>' | cut -d: -f1)" ] \
  && [ "$(echo "$VN" | grep -n '<b>Thanks:</b>' | cut -d: -f1)" -lt "$(echo "$VN" | grep -n '<b>Instagram and TikTok:</b>' | cut -d: -f1)" ] \
  && ! echo "$VN" | grep -qE "$DASHES" \
  && ok "/impressum/#privacy: Thanks after the satellite map (only which receipt, the origin check, Cloudflare, the day counts, nothing about the visitor or on the device, the legal basis), and What we keep says thanking says nothing about you" \
  || bad "/impressum/ visitor notice: thanks" ""

# What the notices promise, held by the code: no cookies, nothing loaded from another host, and only the
# application form reads the internet address (as a keyed hash).
CK=""
for p in / /upload/ /apply/ /impressum/ /no-such-page /api/events /api/missions /m/1 /r/aaaaaaaaaa /crews /missions; do
  curl -s -o /dev/null -D - "$B$p" | grep -qi '^set-cookie:' && CK="$CK $p"
done
curl -s -o /dev/null -D - -X POST $B/api/thanks -H "Origin: $B" -H 'content-type: application/json' -d '{"id":"aaaaaaaaaa"}' | grep -qi '^set-cookie:' && CK="$CK POST/api/thanks"
[ -z "$CK" ] && ok "no page or API sets a cookie, POST /api/thanks neither" || bad "cookies set by" "$CK"
EXT=""
for p in / /upload/ /apply/ /impressum/ /no-such-page /crews /missions; do
  curl -s "$B$p" | grep -oE '<(script|link|img|iframe|video|audio|source|embed|object)[^>]*(src|href|data)="(https?:)?//[^"]*"' \
    | grep -vqE '="https://sapu\.earth/' && EXT="$EXT $p"
done
curl -s $B/site/styles.css $B/site/forms.css $B/site/fonts.css | grep -qE "url\\([\"']?(https?:)?//" && EXT="$EXT css"
curl -s $B/site/app.js $B/upload/upload.js $B/upload/videoclean.js $B/apply/apply.js | grep -qE "(fetch|open)\\([\"'\`](https?:)?//" && EXT="$EXT js"
[ -z "$EXT" ] && ok "the public pages load nothing from another host by themselves (satellite tiles only when zoomed in far, checked above)" || bad "loads from another host" "$EXT"
IPR=$(grep -rliE 'cf-connecting-ip|x-forwarded-for|x-real-ip|request\.cf[^a-z]' functions | sort | tr '\n' ' ')
IPU=$(grep -rl 'ipHash(' functions | sort | tr '\n' ' ')
[ "$IPR" = "functions/_lib/util.js " ] && [ "$IPU" = "functions/_lib/util.js functions/api/apply.js " ] \
  && ok "only the application form reads the internet address, as a keyed hash" || bad "internet address use" "read in: $IPR, ipHash in: $IPU"

# ---------- Missions with several spots (docs/missions.md, Spots; migration 0008) ----------
# Marcus said 'Yes, build it' on 2026-11-17: one mission, one cleanup, one receipt and one payment at up to 4 spots,
# each with its own place, point and day. Spot 2 goes on the way docs/missions.md tells Marcus (the UPDATE for the D1
# console), so most of this part needs the local database (STATE): the crew page's data, the photos of each spot and
# their days on POST /api/upload and POST /api/submit, PENDING, APPROVE, the receipt, /m/<no>, /missions, LATE from
# the last day, no link from a plain cleanup to a mission with spots, and every page before migration 0008.
grep -qF 'ALTER TABLE missions ADD COLUMN spots TEXT;' migrations/0008_spots.sql \
  && grep -qF 'ALTER TABLE submissions ADD COLUMN spots TEXT;' migrations/0008_spots.sql \
  && grep -qF 'ALTER TABLE uploads ADD COLUMN spot INTEGER CHECK (spot BETWEEN 2 AND 4);' migrations/0008_spots.sql \
  && [ "$(grep -cE '^(ALTER|CREATE|INSERT|UPDATE|DELETE|DROP)' migrations/0008_spots.sql)" = 3 ] \
  && ok "migration 0008: three additive columns (missions.spots, submissions.spots, uploads.spot), nothing else" || bad "migration 0008" ""
SPRUN=$RANDOM$RANDOM
SPJ=$(newp "Spot Crew $SPRUN" ID "spots-$SPRUN"); SPT=$(echo "$SPJ" | jget "d['token']"); SPPID=$(echo "$SPJ" | jget "d['id']")
[ ${#SPT} -eq 43 ] && ok "a crew for the spots' checks" || bad "spots crew" "$SPJ"
# The upload's spot parameter is checked before anything is stored.
SPV=$(code -X POST "$B/api/upload?k=$SPT&kind=video&spot=2" -H 'content-type: video/mp4' --data-binary @$F/tiny.mp4)
SP5=$(code -X POST "$B/api/upload?k=$SPT&kind=before&spot=5" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)
SP1=$(code -X POST "$B/api/upload?k=$SPT&kind=before&spot=1" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)
SPX=$(code -X POST "$B/api/upload?k=$SPT&kind=after&spot=02" -H 'content-type: image/jpeg' --data-binary @$F/after.jpg)
check "a spot on a video, spot 5, spot 1 or spot 02 -> 400 400 400 400" "$SPV $SP5 $SP1 $SPX" "400 400 400 400"

if [ -n "$STATE" ]; then
  SP1P="Pantai Kuta $SPRUN"; SP2P="Pantai Losari $SPRUN"
  SPN=$(upk $SPT before)
  st=$(mpost $SPT "media=$SPN" "place_name=$SP1P" crew_size:=15 price_local:=3000000 crew_local:=1500000); SPM=$(mj "d.get('id')"); SPNO=$(mj "d.get('no')")
  st="$st $(act "${SPM:-none}" fund '"funded_eur":175,"advance_pct":100')"
  check "a crew posts a mission and Sapu Earth funds it (the spots' test mission)" "$st" "201 200"
  SPD2=$(dplus 4)
  # The UPDATE docs/missions.md gives Marcus (Adding a spot), with a point given to 7 decimals.
  SQL2="UPDATE missions SET spots = json_array(json_object('place_name', '$SP2P', 'lat', round(-0.8123456, 3), 'lng', round(100.3011111, 3), 'date', '$SPD2')) WHERE no = $SPNO AND status = 'funded' AND spots IS NULL;"
  check "the UPDATE of docs/missions.md gives the mission its second spot (1 row), a second run changes none" \
    "$(d1 "$SQL2 SELECT changes() AS n;" | jget "d[-1]['results'][0]['n']") $(d1 "$SQL2 SELECT changes() AS n;" | jget "d[-1]['results'][0]['n']")" "1 0"
  check "the stored spot: its place, the point at 3 decimals, its day" \
    "$(d1 "SELECT spots FROM missions WHERE id = '$SPM'" | jget "json.loads(d[0]['results'][0]['spots'])")" \
    "[{'place_name': '$SP2P', 'lat': -0.812, 'lng': 100.301, 'date': '$SPD2'}]"

  # GET /api/missions: every spot, spot 1 first (its own place, point and day), rounded; nothing else new.
  check "GET /api/missions: the mission's 2 spots, spot 1 its own place and day, spot 2 rounded, no other new key" \
    "$(curl -s $B/api/missions | pubm "$SPNO" "(len(m['spots']), m['spots'][0]['no'], m['spots'][0]['place_name']==m['place_name'], m['spots'][0]['date']==m['date'], (m['spots'][0]['lat'], m['spots'][0]['lng'])==(m['lat'], m['lng']), m['spots'][1], sorted(set(m) - {'no','status','date','place_name','country','lat','lng','crew_size','task','currency','price_local','crew_local','funded_eur','partner','now','now_video','url','spots'}))")" \
    "(2, 1, True, True, True, {'no': 2, 'place_name': '$SP2P', 'lat': -0.812, 'lng': 100.301, 'date': '$SPD2'}, [])"
  check "GET /api/partner: the crew page gets each spot's place and day, never a point" \
    "$(curl -s "$B/api/partner?k=$SPT" | mq "$SPM" "([sorted(s) for s in m['spots']], m['spots'][1]['place_name'], m['spots'][1]['date'], m['spots'][0]['date']==m['plan_date'])")" \
    "([['date', 'no', 'place_name'], ['date', 'no', 'place_name']], '$SP2P', '$SPD2', True)"
  SPL=$(mlist funded)
  check "/admin/ MISSIONS: the card's spots, spot 2 with its rounded point, not late" \
    "$(echo "$SPL" | mq "$SPM" "(len(m['spots']), m['spots'][1]['place_name'], m['spots'][1]['lat'], m['late'], m['overdue'], isinstance(m.get('spots'), list))")" "(2, '$SP2P', -0.812, False, False, True)"
  curl -s "$B/m/$SPNO" > "$T/spm.html"
  grep -qF "<title>Mission #$SPNO is funded: $SP1P and $SP2P · Sapu Earth</title>" "$T/spm.html" \
    && grep -qE "content=\"A crew of 15 cleans $SP1P on [0-9]+ [A-Za-z]+ 20[0-9]{2} and $SP2P on [0-9]+ [A-Za-z]+ 20[0-9]{2}\.\"" "$T/spm.html" \
    && ok "/m/<no>: the title names both places, the preview each place with its day" || bad "/m/<no> with spots" "$(grep -m2 -E '<title>|og:description' "$T/spm.html")"
  SPML=$(curl -s $B/missions | sed -n "/id=\"m-$SPNO\"/,/<\/li>/p")
  echo "$SPML" | grep -qF "<b>$SP1P and $SP2P</b>" && echo "$SPML" | grep -qE 'days [0-9]+( [A-Za-z]+)?( 20[0-9]{2})? and [0-9]+ [A-Za-z]+ 20[0-9]{2}' \
    && ok "/missions: the card names both places and says both days" || bad "/missions with spots" "$SPML"

  # The photos of each spot (POST /api/upload &spot=) and the cleanup (POST /api/submit with spot_dates).
  upks() { curl -s -X POST "$B/api/upload?k=$1&kind=$2&spot=$3" -H 'content-type: image/jpeg' --data-binary @$F/$2.jpg | jget "d['key']"; }
  # ssub <token> <mission id or -> <media> [spot_dates as JSON]: POST /api/submit. Status out, body in $T/m.json.
  ssub()  { local b; b=$(body $TODAY "$SP1P" "$3")
            b=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);m=sys.argv[2];s=sys.argv[3]
if m!='-': d['mission_id']=m
if s: d['spot_dates']=json.loads(s)
print(json.dumps(d))" "$b" "$2" "${4:-}")
            curl -s -o "$T/m.json" -w '%{http_code}' -X POST "$B/api/submit?k=$1" -H 'content-type: application/json' -d "$b"; }
  SB1=$(upk $SPT before); SA1=$(upk $SPT after); SB2=$(upks $SPT before 2); SA2=$(upks $SPT after 2); SB3=$(upks $SPT before 3)
  check "photos of spots 2 and 3 go up, stored with their spot (spot 1 without one)" \
    "$(d1 "SELECT key, spot FROM uploads WHERE key IN ('$SB1', '$SB2', '$SA2', '$SB3')" | jget "sorted((r['spot'] or 1) for r in d[0]['results'])")" "[1, 2, 2, 3]"
  TD="[\"$TODAY\"]"
  st=$(ssub $SPT "$SPM" "$SB1,$SA1" "$TD"); st="$st $(ssub $SPT "$SPM" "$SB1,$SA1,$SB2" "$TD")"
  st="$st $(ssub $SPT "$SPM" "$SB1,$SA1,$SB2,$SA2")/$(mj "d.get('code')")"
  st="$st $(ssub $SPT "$SPM" "$SB1,$SA1,$SB2,$SA2" '["2099-01-01"]') $(ssub $SPT "$SPM" "$SB1,$SA1,$SB2,$SA2,$SB3" "$TD")"
  st="$st $(ssub $SPT - "$SB1,$SA1,$SB2")"
  check "POST /api/submit refuses: no photos for spot 2, no after photo for spot 2, no spot_dates, a day in the future, a photo of spot 3 (the mission has 2), a spot photo without a mission" \
    "$st" "400 400 400/spot_dates 400 400 400"
  # Its videos are the whole mission's, never a spot's (up to 30 before and 30 after, as for any cleanup): 3 before, 2 after.
  SPVS="$(upv $SPT before),$(upv $SPT before),$(upv $SPT before),$(upv $SPT after),$(upv $SPT after)"
  st=$(ssub $SPT "$SPM" "$SB1,$SA1,$SB2,$SA2,$SPVS" "$TD"); SPS=$(mj "d.get('id')")
  check "the cleanup of a mission with 2 spots: the before and after of each, the day of spot 2, 3 videos before and 2 after -> 200" "$st" 200
  check "its videos stay the mission's: 3 before then 2 after in PENDING, and no video row with a spot" \
    "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[[v['stage'] for v in s['media']['videos']] for s in d['submissions'] if s['id']=='${SPS:-none}']") $(d1 "SELECT COUNT(*) AS n FROM uploads WHERE submission_id = '${SPS:-none}' AND kind = 'video' AND spot IS NOT NULL" | jget "d[0]['results'][0]['n']")" \
    "[['before', 'before', 'before', 'after', 'after']] 0"
  check "the cleanup keeps the mission's spot 2 with the day it was cleaned" \
    "$(d1 "SELECT spots FROM submissions WHERE id = '${SPS:-none}'" | jget "json.loads(d[0]['results'][0]['spots'])")" \
    "[{'place_name': '$SP2P', 'lat': -0.812, 'lng': 100.301, 'date': '$TODAY'}]"
  check "PENDING: the cleanup's 2 spots with their days, each photo's spot, the mission's 2 spots" \
    "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[(len(s['spots']), s['spots'][1]['place_name'], s['spots'][1]['date'], [p['spot'] for p in s['media']['before']], [p['spot'] for p in s['media']['after']], len(s['mission']['spots'])) for s in d['submissions'] if s['id']=='${SPS:-none}']")" \
    "[(2, '$SP2P', '$TODAY', [1, 2], [1, 2], 2)]"
  check "approve the cleanup of the mission with 2 spots" "$(sdec "{\"id\":\"${SPS:-none}\",\"action\":\"approve\",\"paid_eur\":175}")" approved
  check "the mission is done, with one receipt" "$(mlist done | mq "$SPM" "(m['status'], m['submission_id']=='${SPS:-none}')")" "('done', True)"
  check "GET /api/events: one receipt with both spots (place, rounded point, day), the photos spot by spot, location still spot 1" \
    "$(curl -s $B/api/events | jget "[(len(e['spots']), e['spots'][0]['name']==e['location']['name'], e['spots'][0]['date']==e['date'], e['spots'][1], e['media']['before_spots'], e['media']['after_spots'], e['mission']['no']) for e in d if e['id']=='${SPS:-none}']")" \
    "[(2, True, True, {'no': 2, 'name': '$SP2P', 'lat': -0.812, 'lng': 100.301, 'date': '$TODAY'}, [1, 2], [1, 2], $SPNO)]"
  check "every other receipt has one spot: no spots, no photo spots" \
    "$(curl -s $B/api/events | jget "[e['id'] for e in d if e['id']!='${SPS:-none}' and ('spots' in e or 'before_spots' in e['media'] or 'after_spots' in e['media'])]")" "[]"
  grep -qF "<title>Mission #$SPNO done: $SP1P and $SP2P · Sapu Earth</title>" <(curl -s "$B/m/$SPNO") \
    && ok "/m/<no> once done: the title names both places" || bad "/m/<no> done with spots" ""
  SPMC=$(curl -s "$B/missions?status=cleaned" | sed -n "/id=\"m-$SPNO\"/,/<\/li>/p")
  echo "$SPMC" | grep -qF "<b>$SP1P and $SP2P</b>" && echo "$SPMC" | grep -qE 'cleaned [0-9]+ [A-Za-z]+ 20[0-9]{2}' \
    && ok "/missions: the cleaned mission names both places and its day" || bad "/missions cleaned with spots" "$SPMC"

  # LATE counts from the last spot's day: 4 days past spot 1's day but spot 2 is today is not late; without the spot it is.
  SPLID=$(newid); SPLD=$(dplus 0)
  hk >/dev/null; SPH0=$(hkj "d['waiting']['late']")
  if d1 "$(mrow "$SPPID" $SPLID funded $(dplus -4) $(ago 12) $(ago 11) $(ago 10) 10 3)" >/dev/null; then
    hk >/dev/null; SPH1=$(hkj "d['waiting']['late']")
    d1 "UPDATE missions SET spots = json_array(json_object('place_name', 'Second spot', 'lat', NULL, 'lng', NULL, 'date', '$SPLD')) WHERE id = '$SPLID'" >/dev/null
    hk >/dev/null; SPH2=$(hkj "d['waiting']['late']")
    SPLL=$(mlist funded | mq "$SPLID" "(m['late'], len(m['spots']))")
    d1 "UPDATE missions SET spots = NULL WHERE id = '$SPLID'" >/dev/null
    SPLN=$(mlist funded | mq "$SPLID" "(m['late'], m['spots'])")
    check "LATE from the last spot's day: 4 days past its first day is late alone, not with a spot today (housekeeping and /admin/)" \
      "$(add "$SPH1" "-$SPH0") $(add "$SPH2" "-$SPH0") $SPLL $SPLN" "1 0 (False, 2) (True, [])"
  else
    bad "write a late mission into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # A cleanup sent without a mission cannot be linked to a mission with spots on APPROVE: it has no photos for them.
  SPKID=$(newid)
  if d1 "$(mrow "$SPPID" $SPKID funded $(dplus 2) $(ago 3) $(ago 2) $(ago 1) 10 3)" >/dev/null \
     && d1 "UPDATE missions SET spots = json_array(json_object('place_name', 'Other spot', 'lat', NULL, 'lng', NULL, 'date', '$(dplus 3)')) WHERE id = '$SPKID'" >/dev/null; then
    PB=$(upk $SPT before); PA=$(upk $SPT after)
    st=$(ssub $SPT - "$PB,$PA"); SPP=$(mj "d.get('id')")
    SPPM=$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[('$SPKID' in [m['id'] for m in s['partner_missions']], '$SPLID' in [m['id'] for m in s['partner_missions']]) for s in d['submissions'] if s['id']=='${SPP:-none}']")
    st="$st $(sdst "{\"id\":\"${SPP:-none}\",\"action\":\"approve\",\"mission_id\":\"$SPKID\",\"paid_eur\":10}")/$(mj "d.get('code')")"
    check "a plain cleanup: Link to mission lists the crew's funded mission with one spot, not the one with spots, and APPROVE refuses to link that one (400 mission)" \
      "$st $SPPM" "200 400/mission [(False, True)]"
    check "reject that plain cleanup again" "$(sdec "{\"id\":\"${SPP:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
  else
    bad "write a funded mission with spots into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # The biggest cleanup there is (MEDIA_MAX in functions/api/submit.js): a mission with 4 spots (SPOTS.max), 4 before
  # and 4 after photos of each, and as many videos as the limits take (LIMITS.stageVideos before and after, and the rest
  # of LIMITS.cleanupVideos without a stage; today 30, 30 and none: 92 files). Attaching them is one UPDATE with 3 more
  # bound values than files, and the local D1 refuses more than 100 in one statement as Cloudflare's does, so limits
  # that let MEDIA_MAX pass 97 fail here. The resend gets the same id; APPROVE puts it all on the receipt, and UNPUBLISH
  # deletes every file and the mission.
  SV=$(sed -n 's/^ *stageVideos: *\([0-9][0-9]*\),.*/\1/p' functions/_lib/util.js); CV=$(sed -n 's/^ *cleanupVideos: *\([0-9][0-9]*\),.*/\1/p' functions/_lib/util.js)
  NV=$((CV - 2 * SV)); NF=$((32 + CV))
  check "the limits of the biggest cleanup: 4 spots, $SV videos before and after, $CV in all" \
    "$(grep -cxF 'export const SPOTS = { max: 4 };' functions/_lib/spots.js) $SV $CV $NF" "1 30 60 92"
  SPFID=$(newid)
  if d1 "$(mrow "$SPPID" $SPFID funded $(dplus 1) $(ago 3) $(ago 2) $(ago 1) 10 3)" >/dev/null \
     && d1 "UPDATE missions SET spots = json_array(json_object('place_name', 'Spot two', 'lat', NULL, 'lng', NULL, 'date', '$(dplus 1)'), json_object('place_name', 'Spot three', 'lat', NULL, 'lng', NULL, 'date', '$(dplus 2)'), json_object('place_name', 'Spot four', 'lat', NULL, 'lng', NULL, 'date', '$(dplus 3)')) WHERE id = '$SPFID'" >/dev/null; then
    FULL=""
    for k in 1 2 3 4; do for i in 1 2 3 4; do
      if [ $k = 1 ]; then FULL="$FULL,$(upk $SPT before),$(upk $SPT after)"; else FULL="$FULL,$(upks $SPT before $k),$(upks $SPT after $k)"; fi
    done; done
    for ((i = 0; i < SV; i++)); do FULL="$FULL,$(upv $SPT before),$(upv $SPT after)"; done
    for ((i = 0; i < NV; i++)); do FULL="$FULL,$(upv $SPT)"; done  # not seq: on macOS seq 1 0 counts 1 and 0
    FULL=${FULL#,}; TD3="[\"$TODAY\", \"$TODAY\", \"$TODAY\"]"
    VST="['before'] * $SV + ['after'] * $SV + [None] * $NV"
    [ "$(echo "$FULL" | tr ',' '\n' | grep -cE '^[0-9a-f]{32}$')" = $NF ] && ok "a crew uploads 32 photos (4 before and 4 after at each of 4 spots) and $CV videos ($SV before, $SV after)" \
      || bad "the $NF uploads of the biggest cleanup" "$(echo "$FULL" | tr ',' '\n' | grep -cE '^[0-9a-f]{32}$') keys"
    st=$(ssub $SPT "$SPFID" "$FULL" "$TD3"); SPF=$(mj "d.get('id')")
    st="$st $(ssub $SPT "$SPFID" "$FULL" "$TD3")/$(mj "(d.get('id') == '${SPF:-none}', d.get('repeated'))")"
    check "the cleanup of a mission with 4 spots with all $NF files -> 200, and its resend -> 200 with the same id" "$st" "200 200/(True, True)"
    check "all $NF files are its own now" "$(d1 "SELECT COUNT(*) AS n FROM uploads WHERE submission_id = '${SPF:-none}'" | jget "d[0]['results'][0]['n']")" $NF
    check "PENDING: 16 before and 16 after photos at spots 1 to 4, the $SV videos before then the $SV after, its 4 spots" \
      "$(curl -s "$B/api/admin/submissions?status=pending" -H "$A" | jget "[(len(s['media']['before']), len(s['media']['after']), sorted(set(p['spot'] for p in s['media']['before'] + s['media']['after'])), [v['stage'] for v in s['media']['videos']] == $VST, len(s['spots'])) for s in d['submissions'] if s['id']=='${SPF:-none}']")" \
      "[(16, 16, [1, 2, 3, 4], True, 4)]"
    check "approve the biggest cleanup" "$(sdec "{\"id\":\"${SPF:-none}\",\"action\":\"approve\",\"paid_eur\":175}")" approved
    check "GET /api/events: its receipt with 4 spots, 16 and 16 photos at spots 1 to 4, and $CV videos, $SV before then $SV after" \
      "$(curl -s $B/api/events | jget "[(len(e['spots']), len(e['media']['before']), len(e['media']['after']), sorted(set(e['media']['before_spots'] + e['media']['after_spots'])), len(e['media']['videos']), e['media']['video_stages'] == $VST) for e in d if e['id']=='${SPF:-none}']")" \
      "[(4, 16, 16, [1, 2, 3, 4], $CV, True)]"
    check "UNPUBLISH it: all $NF files deleted, the mission removed, the receipt gone" \
      "$(curl -s -X POST $B/api/admin/decide -H "$A" -H 'content-type: application/json' -d "{\"id\":\"${SPF:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}" | jget "(d['status'], d['deleted_media'], d.get('mission', {}).get('status'))") $(curl -s $B/api/events | grep -c "${SPF:-none}") $(code $B/media/${FULL##*,})" \
      "('rejected', $NF, 'removed') 0 404"
  else
    bad "write a funded mission with 4 spots into the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi

  # Deploy order: before migration 0008 every page and API works, and every mission has one spot. The three columns
  # are renamed for a moment (finish() renames them back if the script stops in between).
  PSRENAMED=1
  if d1 "ALTER TABLE missions RENAME COLUMN spots TO spots_e2e_off; ALTER TABLE submissions RENAME COLUMN spots TO spots_e2e_off; ALTER TABLE uploads RENAME COLUMN spot TO spot_e2e_off" >/dev/null; then
    W1=$(curl -s -o "$T/spo.json" -w '%{http_code}' $B/api/missions)
    W1S=$(jget "[m['no'] for m in d if 'spots' in m]" < "$T/spo.json")
    W2=$(curl -s -o "$T/spo.json" -w '%{http_code}' "$B/api/partner?k=$SPT"); W2S=$(jget "[m['no'] for m in d['missions'] if 'spots' in m]" < "$T/spo.json")
    W3=$(curl -s -o "$T/spo.json" -w '%{http_code}' $B/api/events); W3S=$(jget "[e['id'] for e in d if 'spots' in e]" < "$T/spo.json")
    W4="$(code "$B/api/admin/missions?status=funded" -H "$A") $(code "$B/api/admin/missions?status=done" -H "$A") $(code "$B/api/admin/submissions?status=approved" -H "$A")"
    W5="$(code "$B/m/$SPNO") $(code $B/missions) $(hk)"
    W6=$(code -X POST "$B/api/upload?k=$SPT&kind=before&spot=2" -H 'content-type: image/jpeg' --data-binary @$F/before.jpg)
    W7B=$(upk $SPT before); W7A=$(upk $SPT after); W7=$(ssub $SPT "$SPKID" "$W7B,$W7A")
    d1 "ALTER TABLE missions RENAME COLUMN spots_e2e_off TO spots; ALTER TABLE submissions RENAME COLUMN spots_e2e_off TO spots; ALTER TABLE uploads RENAME COLUMN spot_e2e_off TO spot" >/dev/null && PSRENAMED=
    check "without migration 0008: /api/missions, /api/partner and /api/events -> 200 with no spots anywhere" "$W1 $W1S $W2 $W2S $W3 $W3S" "200 [] 200 [] 200 []"
    check "without migration 0008: /admin/ MISSIONS, PENDING and APPROVED, /m/<no>, /missions and the housekeeping -> 200" "$W4 $W5" "200 200 200 200 200 200"
    check "without migration 0008: a photo for spot 2 is refused (400), a mission's cleanup goes in with one spot (200)" "$W6 $W7" "400 200"
    SPW=$(mj "d.get('id')")
    check "reject that cleanup, so nothing waits in PENDING" "$(sdec "{\"id\":\"${SPW:-none}\",\"action\":\"reject\",\"review_note\":\"e2e\"}")" rejected
  else
    PSRENAMED=
    bad "rename the spots columns in the local D1 in $STATE" "$(tail -3 "$T/d1.err")"
  fi
fi

# The homepage's spots in node with site/app.js's own code: the list taken only when whole (2 to 4, numbered in order, a
# place and a day each, a point of two numbers or none), each photo's spot, the SPOT rows, the phone post's first before
# and after of each spot, and one SEE SPOT ON SATELLITE button per spot with a point, carrying it.
curl -s $B/site/app.js > "$T/sp-app.js"
SPJS=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const cut = (from, to) => { const a = s.indexOf(from), b = s.indexOf(to, a); if (a < 0 || b < a) throw new Error("no " + from.trim()); return s.slice(a, b); };
const one = (re) => { const m = s.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const block = (name) => cut("  const " + name + " = ", "\n  };\n") + "\n  };\n";
const code = [/^  const ESC = .*$/m, /^  const escapeHTML = .*$/m].map(one).join("\n") + "\n" + cut("  const safeSrc = (u) =>", "\n  const ") + "\n"
  + block("phOr") + block("dateStr") + one(/^  const upper = .*$/m) + "\n"
  + cut("  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------", "  // ---------- end of the spots ----------")
  + one(/^  const spotRows = .*$/m) + "\n" + block("spotPairs") + block("satRow");
const X = new Function("Globe", code + "\nreturn { spotList, spotsE, spotsM, photoSpots, spotRows, spotPairs, satRow };")(function () {});
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const sp = (no, extra) => Object.assign({ no, name: "Spot " + no, lat: -0.8 - no / 100, lng: 100.3, date: "2026-11-2" + (4 + no) }, extra);
const M = (k) => "/media/" + k.repeat(32).slice(0, 32);
eq("whole lists", [X.spotsE({ spots: [sp(1), sp(2)] }).length, X.spotsE({ spots: [sp(1), sp(2), sp(3), sp(4)] }).length,
  X.spotsM({ spots: [{ no: 1, place_name: "A", lat: 1, lng: 2, date: "2026-11-25" }, { no: 2, place_name: "B", lat: null, lng: null, date: "2026-11-26" }] })], [2, 4,
  [{ no: 1, name: "A", date: "2026-11-25", lat: 1, lng: 2 }, { no: 2, name: "B", date: "2026-11-26", lat: null, lng: null }]]);
eq("broken lists are none", [X.spotsE({}), X.spotsE({ spots: [sp(1)] }), X.spotsE({ spots: [sp(1), sp(2), sp(3), sp(4), sp(5)] }), X.spotsE({ spots: [sp(1), sp(3)] }),
  X.spotsE({ spots: [sp(1), sp(2, { name: " " })] }), X.spotsE({ spots: [sp(1), sp(2, { date: "26 Nov" })] }), X.spotsE({ spots: "[1,2]" }), X.spotsE({ spots: [sp(2), sp(1)] })].map((x) => x.length), [0, 0, 0, 0, 0, 0, 0, 0]);
eq("a point of two numbers or none", X.spotsE({ spots: [sp(1, { lat: "1" }), sp(2, { lng: Infinity })] }).map((x) => [x.lat, x.lng]), [[null, null], [null, null]]);
eq("photo spots", [X.photoSpots({ media: { before: [1, 2, 3, 4], before_spots: [1, 2, 9, "2"] } }, "before", 2), X.photoSpots({ media: { after: [1, 2] } }, "after", 2)], [[1, 2, 1, 1], [1, 1]]);
const e = { spots: [sp(1), sp(2, { lat: null, lng: null })], media: { before: [M("a"), M("b"), M("c")], after: [M("d")], before_spots: [1, 1, 2], after_spots: [1] } };
const rows = X.spotRows(X.spotsE(e), "ID");
eq("SPOT rows, the day on a line of its own", rows, "<div><dt>SPOT 1</dt><dd>SPOT 1 · ID<br>2026-11-25</dd></div><div><dt>SPOT 2</dt><dd>SPOT 2 · ID<br>2026-11-26</dd></div>");
eq("no rows for one spot", [X.spotRows([], "ID"), X.spotPairs({ media: { before: [M("a")], after: [M("d")] } })], ["", ""]);
const pairs = X.spotPairs(e);
eq("the phone post: the first before and after of each spot, PHOTO SOON for one missing", [(pairs.match(/<img /g) || []).length, pairs.indexOf(M("a")) >= 0, pairs.indexOf(M("b")) < 0, pairs.indexOf(M("c")) >= 0,
  (pairs.match(/<span class="tag">[^<]*<\/span>/g) || []).map((t) => t.replace(/<[^>]+>/g, "")), pairs.includes("PHOTO SOON")],
  [3, true, true, true, ["BEFORE · SPOT 1", "AFTER · SPOT 1", "BEFORE · SPOT 2", "AFTER · SPOT 2"], true]);
eq("SEE THE SPOT for one point, SEE SPOT n for each spot with one, each carrying its point", [X.satRow(-0.5, 100.25),
  X.satRow(-0.811, 100.301, X.spotsE({ spots: [sp(1), sp(2), sp(3, { lat: null })] })), X.satRow(null, null), X.satRow(1, 2, X.spotsE({ spots: [sp(1, { lat: null }), sp(2, { lat: null })] }))],
  ["<div class=\"post-sat\"><button type=\"button\" class=\"post-link post-map\" data-lat=\"-0.5\" data-lng=\"100.25\">SEE THE SPOT ON SATELLITE</button></div>",
   "<div class=\"post-sat\"><button type=\"button\" class=\"post-link post-map\" data-lat=\"-0.81\" data-lng=\"100.3\">SEE SPOT 1 ON SATELLITE</button><button type=\"button\" class=\"post-link post-map\" data-lat=\"-0.8200000000000001\" data-lng=\"100.3\">SEE SPOT 2 ON SATELLITE</button></div>", "", ""]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 9");
' "$T/sp-app.js" 2>&1)
check "the homepage's spots (site/app.js, node): whole lists only, each photo's spot, SPOT rows, the first before and after of each spot, one satellite button per spot with a point" "$SPJS" "ok 9"
SJS=$(cat "$T/sp-app.js")
echo "$SJS" | grep -qF '${spotRows(spotsM(m), mcc(m)) || `<div><dt>LOC</dt>' && echo "$SJS" | grep -qF '${spotRows(spotsE(e), cc(e)) || `<div><dt>LOC</dt>' \
  && [ "$(echo "$SJS" | grep -cF '${spotRows(spotsE(e), cc(e)) ||')" = 2 ] && echo "$SJS" | grep -qF '${satRow(m.lat, m.lng, spotsM(m))}' \
  && [ "$(echo "$SJS" | grep -cF '    satButtons();')" = 2 ] && ! echo "$SJS" | grep -qF 'querySelector(".post-map")' \
  && echo "$SJS" | grep -qF 'const geo = events.flatMap((e) => (spotsE(e).length ? spotsE(e).map((s) => ({ of: e, location: s })) : [{ of: e, location: e.location }]))' \
  && echo "$SJS" | grep -qF '? spotsM(m).map((s) => ({ ...m, place_name: s.name, date: s.date, lat: s.lat, lng: s.lng, spot: s.no, base: m })) : [m]))' \
  && echo "$SJS" | grep -qF 'const groupLabel = (ms) => { const u = missionsOf(ms); return u.length <= 3' \
  && echo "$SJS" | grep -qF 'const list = missions.filter((x) => [...gs].some((y) => y.ms.some((z) => baseOf(z) === x)));' \
  && echo "$SJS" | grep -qF 'return near.sort((a, b) => a.d - b.d).filter((x) => !seen.has(x.e) && !!seen.add(x.e));' \
  && echo "$SJS" | grep -qF 'nextUpAt.get(baseOf(lead(a))) - nextUpAt.get(baseOf(lead(b)))' \
  && echo "$SJS" | grep -qF 'const rank = (m) => (last(m) < today ? 2 : m.status === "funded" ? 0 : 1);' \
  && [ "$(echo "$SJS" | grep -nF '  // ---------- spots (pure; tests/e2e.sh runs this block in node) ----------' | cut -d: -f1)" -lt "$(echo "$SJS" | grep -nF '  // ---------- missions: open (waiting for funding)' | cut -d: -f1)" ] \
  && ok "the homepage with spots: SPOT rows on the cards and posts, a dot and a pin at each spot, one tag per mission (#2 once), a tap on it opens the mission, a finger near two dots of one receipt opens it once, NEXT UP counts a mission as passed by its last spot's day" \
  || bad "the homepage's code for spots" ""

# The crew page with spots (upload/upload.js): the list from GET /api/partner taken only when whole (spotsOf, node), the
# fields of spots 2 to 4 made from spot 1's, each spot's photos and day asked and checked, the photos sent with &spot=,
# spot_dates sent, Use my location now hidden, every new text in both languages.
curl -s $B/upload/upload.js > "$T/sp-up.js"
SPU=$(node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const a = s.indexOf("  // ---------- crew page model (pure; tests/e2e.sh runs this block in node) ----------"), b = s.indexOf("  // ---------- end of crew page model ----------");
const M = new Function(s.slice(a, b) + "\nreturn { spotsOf, SPOT_MAX };")();
const bad = [], eq = (n, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(n + ": " + JSON.stringify(got)); };
const sp = (no, extra) => Object.assign({ no, place_name: "P" + no, date: "2026-11-2" + (4 + no) }, extra);
eq("spotsOf", [M.SPOT_MAX, M.spotsOf({ spots: [sp(1), sp(2)] }).length, M.spotsOf({ spots: [sp(1), sp(2), sp(3), sp(4)] }).length, M.spotsOf({}).length, M.spotsOf(null).length,
  M.spotsOf({ spots: [sp(1)] }).length, M.spotsOf({ spots: [sp(1), sp(3)] }).length, M.spotsOf({ spots: [sp(1), sp(2, { place_name: "" })] }).length,
  M.spotsOf({ spots: [sp(1), sp(2, { date: "2026-11" })] }).length, M.spotsOf({ spots: [sp(1), sp(2), sp(3), sp(4), sp(5)] }).length], [4, 2, 4, 0, 0, 0, 0, 0, 0, 0]);
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 1");
' "$T/sp-up.js" 2>&1)
check "the crew page takes a mission's spots only when the list is whole (upload.js crew page model, node)" "$SPU" "ok 1"
SUJ=$(cat "$T/sp-up.js")
KEYS="paper_hint_spots before_hint_spots after_hint_spots spot_field spot_day spot_before_aria spot_after_aria sum_planned_spots sum_planned_spots_1 card_spot e_before_spot e_after_spot e_spot_day funded_todo_spots"
n=0; for k in $KEYS; do [ "$(echo "$SUJ" | grep -cE "^ +$k: \"|, $k: \"")" = 2 ] && n=$((n+1)); done
echo "$SUJ" | grep -qF 'for (let k = 2; k <= SPOT_MAX; k++) SPOT_KINDS.push(`before_${k}`, `after_${k}`);' \
  && echo "$SUJ" | grep -qF '${spot > 1 ? `&spot=${spot}` : ""}' && echo "$SUJ" | grep -qF 'if (n > 1) data.spot_dates = spotDates;' \
  && echo "$SUJ" | grep -qF 'bad("f-" + kind + sfx, n > 1 ? `e_${kind}_spot` : "e_" + kind, n > 1 ? { n: k } : undefined);' \
  && echo "$SUJ" | grep -qF 'bad("f-date_" + (i + 2), "e_spot_day", { n: i + 2 });' && echo "$SUJ" | grep -qF '$("#f-geo").hidden = n > 1;' \
  && echo "$SUJ" | grep -qF 'lat: geo.cleanup && n === 1 ? Math.round(geo.cleanup.lat * 1e6) / 1e6 : null,' \
  && echo "$SUJ" | grep -qF 'const sendItems = () => allItems().filter((it) => kindSpot(it.kind)[1] <= spotCount());' \
  && echo "$SUJ" | grep -qF 'const itemsOf = (g) => (g === "mission" ? [...files.now, ...files.now_video] : sendItems());' \
  && echo "$SUJ" | grep -qF 'for (const s of spotsOf(m).slice(1)) if (s.date <= localToday()) fill(E["spot_date_" + s.no], s.date);' \
  && echo "$SUJ" | grep -qF 'card_spot: "Spot {n}: {place} ({day})",' && echo "$SUJ" | grep -qF 'card_spot: "Titik {n}: {place} ({day})",' \
  && ! echo "$SUJ" | grep -E "spot_|_spots" | grep -qE '—|–' && [ "$n" = 14 ] \
  && ok "the crew page with spots: fields for spots 2 to 4, each spot's photos and day asked, photos sent with their spot, only the mission's spots sent, no location button, its days prefilled once they came, 14 new texts in both languages" \
  || bad "the crew page's code for spots" "$n of 14 texts"

# /admin/ with spots: the cards, and the funded message in node (each spot with its day, the paper and the photos at each).
SPAD=$(node -e '
const src = require("fs").readFileSync(process.argv[1], "utf8");
const line = (re) => { const m = src.match(re); if (!m) throw new Error("missing " + re); return m[0]; };
const fn = (name) => { const a = src.indexOf("  function " + name + "("), b = src.indexOf("\n  }\n", a); if (a < 0 || b < 0) throw new Error("missing " + name); return src.slice(a, b + 4); };
eval([/^  const n = .*$/m, /^  const isNum = .*$/m, /^  const cents = .*$/m, /^  const missionNo = .*$/m, /^  const spotsOf = .*$/m, /^  const lastDay = .*$/m, /^  const ADVANCE_PCT = .*$/m].map(line).join("\n") + "\n" + fn("missionFundedText") + "\nObject.assign(globalThis, { missionFundedText, spotsOf, lastDay });");
const day = (k) => { const d = new Date(Date.now() + k * 86400000); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
const m = (spots, k = 5) => ({ no: 2, place_name: "Pantai Kuta", plan_date: day(k), funded_eur: 120, advance_eur: 36, partner_name: "Kru Uji", spots });
const two = (k = 5) => [{ no: 1, place_name: "Pantai Kuta", date: day(k) }, { no: 2, place_name: "Pantai Losari", date: day(k + 1) }];
const bad = [];
const en = missionFundedText("en", m(two())), id = missionFundedText("id", m(two())), en1 = missionFundedText("en", m(undefined)), past = missionFundedText("en", m(two(-3), -3));
if (!/This mission has 2 spots: Pantai Kuta on \d+ \w+ \d{4}, then Pantai Losari on \d+ \w+ \d{4}\. At each spot:\n/.test(en)) bad.push("en spots");
if (!en.includes("After the last spot, open your crew page (the private link we sent you), tap SEND A CLEANUP FOR #2, add the photos and the day of each spot and the number of sacks, and tap SEND CLEANUP.")) bad.push("en end");
if (!/Misi ini punya 2 titik: Pantai Kuta pada \d+ \w+ \d{4}, lalu Pantai Losari pada \d+ \w+ \d{4}\. Di setiap titik:\n/.test(id)) bad.push("id spots");
if (!id.includes("Setelah titik terakhir selesai, buka halaman kru kalian (link pribadi yang kami kirim), tekan LAPOR AKSI BERSIH #2, tambahkan foto dan tanggal setiap titik serta jumlah karungnya, lalu tekan KIRIM LAPORAN.")) bad.push("id end");
if (en1.includes("each spot") || !/On the day \(\d+ \w+ \d{4}\):\n/.test(en1)) bad.push("one spot as before");
if (!/Your planned day \(\d+ \w+ \d{4}\) has passed/.test(past) || !past.includes(new Date(Date.parse(day(-2) + "T12:00:00")).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }))) bad.push("past: the last day");
if ([en, id].some((t) => /[—–]/.test(t))) bad.push("a dash");
if (lastDay(m(two())) !== day(6) || lastDay(m(undefined)) !== day(5) || spotsOf({ spots: [{ no: 1 }] }).length !== 0) bad.push("lastDay, spotsOf");
console.log(bad.length ? "wrong: " + bad.join("; ") : "ok 8");
' "$T/admin-texts.js" 2>&1)
check "/admin/ funded message with spots (node): each spot with its day, at each spot, the photos and day of each spot, the last day once passed, one spot as before (EN and ID)" "$SPAD" "ok 8"
SAJ=$(cat "$T/admin-texts.js")
echo "$SAJ" | grep -qF 'const late = st === "funded" ? ageDays(lastDay(m)) : null;' && [ "$(echo "$SAJ" | grep -cF 'the planned day was ${esc(lastDay(m))}')" = 2 ] \
  && echo "$SAJ" | grep -qF '${spotsOf(m).length ? spotKv(m) : `<dt>Map</dt><dd>${osm(m)}</dd>`}' \
  && echo "$SAJ" | grep -qF '<h4>BEFORE, SPOT ${esc(sp.no)} (${b.length})</h4>' && echo "$SAJ" | grep -qF '<h4>AFTER, SPOT ${esc(sp.no)} (${a.length})</h4>' \
  && echo "$SAJ" | grep -qF '${spotsOf(s).length ? spotKv(s) : `<dt>Map</dt><dd>${osm(s)}</dd>' \
  && ok "/admin/ with spots: the mission card's Spot rows and LATE from the last day, PENDING's photos by spot and its Spot rows" || bad "/admin/ code for spots" ""

# robots.txt and sitemap.xml, for search engines (Marcus, 18 Nov 2026: Google Search Console). scripts/build-site.sh
# writes the sitemap: the public pages, and every story with an English and an Indonesian page, each naming the other.
RBT=$(curl -s "$B/robots.txt")
echo "$RBT" | grep -qxF 'Sitemap: https://sapu.earth/sitemap.xml' && echo "$RBT" | grep -qxF 'User-agent: *' \
  && echo "$RBT" | grep -qxF 'Disallow: /admin/' && echo "$RBT" | grep -qxF 'Disallow: /upload/' && echo "$RBT" | grep -qxF 'Disallow: /api/' \
  && ! echo "$RBT" | grep -qE '^Disallow: /$|^Disallow: /(stories|apply|crews|missions|m|r|p)' \
  && ok "robots.txt names the sitemap, keeps /admin/, /upload/ and /api/ out, and lets every public page be crawled" || bad "robots.txt" "$RBT"
SMH=$(curl -s -o "$T/sitemap.xml" -w '%{http_code} %{content_type}' "$B/sitemap.xml")
SMX=$(python3 - "$T/sitemap.xml" "$B" <<'PYEOF' 2>&1
import glob, os, sys, urllib.request, xml.etree.ElementTree as ET
ns = {'s': 'http://www.sitemaps.org/schemas/sitemap/0.9', 'x': 'http://www.w3.org/1999/xhtml'}
root, base, site = ET.parse(sys.argv[1]).getroot(), sys.argv[2], 'https://sapu.earth'
urls = {u.find('s:loc', ns).text: {a.get('hreflang'): a.get('href') for a in u.findall('x:link', ns)} for u in root.findall('s:url', ns)}
bad = []
pages = ['/', '/stories/', '/crews', '/missions', '/apply/', '/impressum/']
stories = sorted(p.split('/')[1] for p in glob.glob('stories/*/id/index.html') if os.path.exists('stories/%s/index.html' % p.split('/')[1]))
want = [site + p for p in pages] + [site + '/stories/%s/%s' % (s, l) for s in stories for l in ('', 'id/')]
if sorted(urls) != sorted(want): bad.append('urls %s' % sorted(set(urls) ^ set(want)))
for s in stories:
    pair = {'en': site + '/stories/%s/' % s, 'id': site + '/stories/%s/id/' % s}
    for loc in pair.values():
        if urls.get(loc) != pair: bad.append('alternates of ' + loc)
if any(x in u for u in urls for x in ('/admin', '/upload', '/api', '?')): bad.append('a private or query url')
for u in urls:
    try: st = urllib.request.urlopen(base + u[len(site):], timeout=20).status
    except Exception as e: st = getattr(e, 'code', str(e))
    if st != 200: bad.append('%s answers %s' % (u, st))
print('wrong: ' + '; '.join(bad) if bad else 'ok %d urls, %d stories' % (len(urls), len(stories)))
PYEOF
)
case "$SMH $SMX" in "200 "*xml*" ok "*) ok "sitemap.xml lists the public pages and every story in English and Indonesian with its translation, and every page in it answers 200 ($SMX)" ;; *) bad "sitemap.xml" "$SMH $SMX" ;; esac

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

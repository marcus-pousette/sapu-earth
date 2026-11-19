#!/bin/sh
# Cloudflare Pages build step. Copies ONLY the public site into dist/ (an allowlist),
# so internal folders (ops, docs, migrations, functions, .claude) are never deployed.
# Pages settings: build command "sh scripts/build-site.sh", build output directory "dist".
# Pages Functions are still read from functions/ at the repo root.
set -eu
cd "$(dirname "$0")/.."
rm -rf dist
mkdir -p dist/data
# 404.html: Pages answers every path that is no file and no Function with it, status 404. Without a top-level
# 404.html, Pages takes the site for a single-page app and answers 200 with the homepage instead, also for
# /.env or /wrangler.toml, which scanners report.
cp index.html 404.html _routes.json dist/
for d in site upload admin apply impressum stories; do
  if [ -d "$d" ]; then cp -R "$d" dist/; fi
done
cp -R data/events dist/data/events
for f in _headers _redirects robots.txt favicon.ico; do
  if [ -f "$f" ]; then cp "$f" dist/; fi
done
find dist -name '.DS_Store' -delete

# sitemap.xml for search engines (robots.txt names it): the public pages, then every story that has an English and
# an Indonesian page, each naming the other as its translation. A new story folder is listed by itself. The crews'
# and missions' pages are Functions and say noindex while they list nothing.
SITE=https://sapu.earth
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
  for p in / /stories/ /crews /missions /apply/ /impressum/; do printf '  <url><loc>%s%s</loc></url>\n' "$SITE" "$p"; done
  for d in stories/*/; do
    s=$(basename "$d")
    [ -f "stories/$s/index.html" ] && [ -f "stories/$s/id/index.html" ] || continue
    for loc in "$SITE/stories/$s/" "$SITE/stories/$s/id/"; do
      printf '  <url><loc>%s</loc><xhtml:link rel="alternate" hreflang="en" href="%s/stories/%s/"/><xhtml:link rel="alternate" hreflang="id" href="%s/stories/%s/id/"/></url>\n' "$loc" "$SITE" "$s" "$SITE" "$s"
    done
  done
  printf '</urlset>\n'
} > dist/sitemap.xml

# Every page needs the self-hosted fonts, and there is no fallback to Google. A file that site/fonts.css
# names but the build lacks (say, one never added to git) would answer 404 with the not found page, and
# every page would quietly show other fonts, so stop the build instead. A failed build leaves the live
# site as it is.
[ -f dist/site/fonts.css ] || { echo "Missing site/fonts.css" >&2; exit 1; }
for f in $(grep -oE 'fonts/[A-Za-z0-9._-]+\.(woff2|txt)' dist/site/fonts.css); do
  [ -f "dist/site/$f" ] || { echo "Missing site/$f (named in site/fonts.css)" >&2; exit 1; }
done

# Pages tells browsers to keep .js and .css for 4 hours but re-checks HTML every time. Tag every
# local script and stylesheet link with the commit, so a fresh page never runs yesterday's code.
V=$(printf '%s' "${CF_PAGES_COMMIT_SHA:-}" | cut -c1-8)
[ -n "$V" ] || V="dev$(date +%s)"
case "$V" in *[!A-Za-z0-9]*) echo "Bad asset version: $V" >&2; exit 1 ;; esac
# Pages compiles functions/ after this build command, so a page that a Function renders (/p/<slug>)
# can link the same ?v= as the static pages. The file is gitignored. scripts/dev.sh and
# scripts/test.sh run this script before wrangler pages dev, so it exists locally too.
printf '// Written by scripts/build-site.sh on every build. Do not edit or commit.\nexport const ASSET_V = "%s";\n' "$V" > functions/_lib/asset-version.js
if command -v perl >/dev/null 2>&1; then
  # The story pages (stories/, docs/stories.md) are static too, one folder per story and language.
  for f in dist/index.html dist/404.html dist/upload/index.html dist/admin/index.html dist/apply/index.html dist/impressum/index.html $(find dist/stories -name '*.html' 2>/dev/null); do
    [ -f "$f" ] && V="$V" perl -pi -e 's#((?:src|href)="/?(?!site/vendor/)(?:site|upload|admin|apply)/[^"?]+\.(?:js|css))"#$1?v=$ENV{V}"#g' "$f"
  done
else
  echo "perl not found: asset links are not versioned." >&2
fi
echo "Built dist/ with $(find dist -type f | wc -l | tr -d ' ') files."

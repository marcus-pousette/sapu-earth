# Sapu Earth

The code behind [sapu.earth](https://sapu.earth). Local cleanup crews post a cleanup they want to do and what it costs, Sapu Earth funds it, and every cleanup comes back as a public receipt: the photos before and after, the place, the crew, and the money paid.

The code is open so anyone can check how that works: what a crew sends, what is checked before anything goes public, what the site shows, and what it keeps and for how long. The money for each cleanup is on its receipt on the site.

## What is in here

- `index.html`, `site/`: the homepage, with the globe, the missions and the receipts.
- `upload/`: the crew page. A crew opens it with its own private link, posts missions and sends cleanups with photos and video.
- `apply/`: the form for crews who want to join.
- `admin/`: the review page, where every mission and cleanup is checked before it goes public.
- `functions/`: the server code (Cloudflare Pages Functions), with a D1 database (SQLite) and an R2 bucket for photos and videos.
- `migrations/`: the database tables.
- `stories/`: the stories, plain pages.
- `docs/upload-flow.md`: how all of it works, in detail, including the privacy rules. `docs/missions.md`: missions.
- `tests/e2e.sh`: the tests, run against a local copy.

## Run it on your computer

You need Node.js, Python 3, curl and openssl.

    sh scripts/dev.sh     # a local copy at http://127.0.0.1:8790, with its own local database
    sh scripts/test.sh    # the tests, against a fresh local copy

Nothing local touches the real site. The first run writes `.dev.vars` with a random token for the local admin page.

## License

The code is under the GNU Affero General Public License v3.0 (`LICENSE`). You may use it and change it. If you run a changed version for other people, you must publish your changes under the same license.

The name Sapu Earth, the Sapu character, the broom logo, the pictures and the stories are not under that license, see `NOTICE.md`.

## About this repository

It is a copy of the code that runs sapu.earth, updated when the site is. Found a security problem? See `SECURITY.md`. Anything else: hello@sapu.earth.

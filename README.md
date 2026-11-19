<p align="center"><img src="site/social/sapu-earth-mark.png" width="120" alt="Sapu Earth's broom"></p>

<h1 align="center">Sapu Earth</h1>

<p align="center"><b>We pay local crews to clean up trash. Every cleanup gets a public receipt.</b><br>
Photos before and after, the place, the crew and the money: <a href="https://sapu.earth">sapu.earth</a></p>

## Why

We are building an open, AI-accelerated way to give: the most real impact per euro, with the least room for fraud.

- **One cleanup at a time.** A crew posts a dirty spot and what cleaning it costs. Funded, it happens.
- **Proof for every cleanup.** Photos from the spot, before and after, checked before anything goes public.
- **In the open.** Every receipt is public, and so is this code.

## The code

This is the code that runs sapu.earth, copied here whenever the site changes. It runs on Cloudflare (Pages, D1, R2). To try it, you need Node.js, Python 3, curl and openssl:

    sh scripts/dev.sh     # a local copy at http://127.0.0.1:8790
    sh scripts/test.sh    # the tests

How it works: [docs/upload-flow.md](docs/upload-flow.md). The code is under AGPL-3.0; the name, Sapu, the pictures and the stories are not ([NOTICE.md](NOTICE.md)). Security: [SECURITY.md](SECURITY.md). Anything else: hello@sapu.earth

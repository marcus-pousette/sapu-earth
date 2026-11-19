# Event data

One JSON file per cleanup event: `events/YYYY-MM-DD-<slug>.json`. The globe site renders these directly: adding a file **and listing it in `events/index.json`** (the manifest the site fetches) = publishing an event.

Events with `"demo": true` render with a SAMPLE stamp and SAMPLE DATA on the first screen, and the homepage hides them by itself as soon as one real cleanup is published. Since 2026-11-16 `events/index.json` lists none (Marcus said 'Yes, build all 9'): with mission #2 funded and no cleanup approved yet, the samples made the first screen say 3 cleanups, about 515 kg and about €231 that never happened, and SAMPLE DATA made the real mission look like a sample too. The three files stay: listed again, they show again, under SAMPLE DATA. A sample event can carry `"days_ago": 4` instead of a fixed day: the page then dates it 4 days before the visitor's today, so it never sits in the future or grows old (its `date` is only a fallback). Their before and after pictures are playful illustrations in `site/samples/` (SVG, flat, in the site's colours), so nobody takes them for real photos.

Sample missions live next to them in `site/samples/missions.json`: two open and one funded, in the shape `/api/missions` answers, with `"in_days"` instead of a date and a `now` picture in `site/samples/`. The homepage shows them only next to the sample receipts: `/api/missions` answered with no missions, and the receipts are all samples. With no receipt at all, as since 2026-11-16, none show. They are stamped SAMPLE, their tags say SAMPLE MISSION, and they have no share buttons (`/m/<no>` only knows real missions). The first real mission or cleanup hides them; a failed `/api/missions` never shows them.

## Schema

```json
{
  "id": "2026-12-05-canggu-river",
  "date": "2026-12-05",
  "location": {
    "name": "Canggu river mouth",
    "city": "Canggu",
    "country": "ID",
    "lat": -8.6594,
    "lng": 115.1300
  },
  "crew": { "size": 5, "coordinator": "W." },
  "result": {
    "sacks": 23,
    "kg_estimate": 180,
    "disposal": "TPS3R Canggu (waste bank)"
  },
  "cost_eur": 78.5,
  "media": {
    "before": ["media/2026-12-05/before-1.jpg"],
    "after": ["media/2026-12-05/after-1.jpg"],
    "clips": ["https://..."]
  },
  "notes": "First trial event."
}
```

### Partner cleanups (funded through an existing organization)

Add two optional blocks. With `money` present, the receipt shows the split instead of a single total:

```json
"provider": { "name": "Sungai Watch", "url": "https://sungai.watch" },
"money": { "paid_eur": 920, "crew_eur": 310, "ops_eur": 610 }
```

Leave out `crew_eur` if the partner doesn't disclose it; the receipt then says "CREW SHARE: NOT DISCLOSED".

Rules:
- `kg_estimate` is honest guesswork until we have a scale. Never inflate, the whole project runs on credibility
- No full names or faces in committed media without consent (see event checklist)
- Large video files live on a host (YouTube unlisted / Cloudflare Stream), only URLs here

See [events/2026-00-00-example.json](events/2026-00-00-example.json).

## Partner uploads (API events)

Besides these static files, the site also loads approved partner uploads from `GET /api/events` (see [docs/upload-flow.md](../docs/upload-flow.md)). They use the same schema plus:

```json
"provider": {
  "name": "Sungai Watch", "url": "https://sungai.watch", "slug": "sungai-watch",
  "page": "https://sapu.earth/p/sungai-watch", "logo": "/media/<key>"
},
"hours": 4,
"local_money": { "currency": "IDR", "total": 1500000, "crew": 900000 },
"social": { "site": "instagram", "url": "https://www.instagram.com/p/<code>/", "by": "sapu" },
"thanks": 47,
"media": {
  "before": ["/media/<key>"], "after": ["/media/<key>"],
  "videos": ["/media/<key>", "/media/<key>", "/media/<key>"], "video_stages": ["before", "before", "after"]
}
```

`local_money` is the cleanup's own costs in local money, when the crew filled in COSTS: `total` is what the cleanup cost in all and `crew` the whole crew's pay inside it (the crew page adds both up from what each person got × the crew size, plus the other costs). A receipt that closed a mission (one with the `mission` block below) shows them as SPENT, CREW PAY and OTHER COSTS (the total less the crew's pay), never as a pay for each person: APPROVE can change the crew size, not the money. A receipt without a mission does not show its local money (`localRows` in `site/app.js`). `total` and `crew` are `null` when the crew sent no costs; a mission receipt then shows the mission block's price instead.

`provider.page` is the crew's page and `provider.logo` its live logo (`/media/<key>`, a square JPEG, docs/upload-flow.md, Crew logos), both only while the crew is active, like `provider.url` (its website) and `provider.slug`: a deactivated crew has `null` for all four, and its receipts keep the name alone. `logo` is `null` too for a crew without an approved logo, and before migration 0006. The receipt post on the homepage shows the logo (20 px) and links the name to the page; the receipt cards do not. The site takes a logo only as `/media/` and 32 hex characters, nothing else.

`social` is the one post on Instagram or TikTok where people comment on this cleanup (docs/upload-flow.md, Post links and thanks): Sapu Earth's own post (`"by": "sapu"`) when there is one, else the crew's own (`"by": "crew"`) while the crew is active; `null` without one, and before migration 0007. `site` is `"instagram"` or `"tiktok"`, and `url` is always one of the four stored forms: `https://www.instagram.com/p/<code>/`, `https://www.instagram.com/reel/<code>/`, `https://www.tiktok.com/@<account>/video/<digits>` or `.../photo/<digits>`. The receipt post shows it as COMMENTS ON INSTAGRAM or COMMENTS ON TIKTOK, a plain link, never on the cards; the site takes it only in those forms.

`thanks` is the number of standing thanks on this receipt from SAY TERIMA KASIH (SAY THANK YOU) in its post (docs/upload-flow.md, Thanks), a whole number of taps, not people. It is absent before migration 0007, and the homepage then shows no button and no count. A receipt of a deactivated crew keeps its count but takes no new thanks (`POST /api/thanks` answers 409 code `inactive` for it). The post shows the count under the button, and a card shows THANKED only above 0.

`media.videos` play inline in the receipt. `media.video_stages` goes with them, in the same order, one for each video: `"before"` (the crew's video before the cleanup), `"after"` (after it), or `null` for one sent before the upload page had those two fields, or before migration 0005. A cleanup has up to 30 videos before and 30 after, 60 in all (a video without a label counts toward the 60; until 2026-11-19 it was one of each). The videos before come first, then those after, then any without a label, each in upload order, and the receipt tags them BEFORE · VIDEO, AFTER · VIDEO or VIDEO, numbered like the photos when there is more than one (BEFORE · VIDEO 1/3 to BEFORE · VIDEO 3/3). The site only accepts media URLs that start with `/media/`, `data/`, `site/` or `https://`, and escapes every text value, because partner data is untrusted.

### Mission block

A cleanup that a crew sent for a funded mission (see [docs/missions.md](../docs/missions.md)) also carries the mission:

```json
"mission": {
  "no": 12,
  "url": "https://sapu.earth/m/12",
  "now": ["/media/<key>"],
  "now_video": "/media/<key>",
  "funded_eur": 120,
  "currency": "IDR",
  "price_local": 2000000,
  "crew_local": 1200000,
  "crew_size": 5
}
```

- `no`: the short public mission number (`#12`), never reused.
- `url`: the mission's share link. Once the mission is done, `/m/12` shows the receipt's preview and opens `/#ev-<id>`.
- `now`: the photos of the place before the mission, as the crew posted them. Same URL rules as `media` (`/media/<key>` or the public bucket address).
- `now_video`: the crew's short video of the place before the mission, the same way, or `null` when it sent none.
- `funded_eur`: what Sapu Earth agreed to pay for the mission. The money actually paid is in `money` as for every receipt.
- `currency`, `price_local`, `crew_local`, `crew_size`: what the crew asked when it posted the mission, in local money: `price_local` the whole price, `crew_local` the pay of all crew members together, inside `price_local`, and `crew_size` the crew it was added up for. The pay for each person is `crew_local / crew_size` and the other costs `price_local - crew_local`. The receipt shows them as ASKED, CREW PAY (15 × IDR 100,000, or with its head count when it does not split evenly) and OTHER COSTS when the cleanup itself has no costs of its own (`local_money`).

Only the receipt of the cleanup that completed the mission (the mission is done) has the block, also when the cleanup was linked to the mission in `/admin/` (the crew sent it with "No mission"). Never in it: the mission id, the advance, the notes, the exact point. Receipts without a mission have no `mission` key. Before migration 0004 there is never one.

### Spots

The receipt of a mission with several spots (docs/missions.md, Spots) also lists them, spot 1 first, and says which spot each photo shows:

```json
"spots": [
  { "no": 1, "name": "Pantai Kuta", "lat": -8.718, "lng": 115.168, "date": "2027-01-05" },
  { "no": 2, "name": "Pantai Legian", "lat": -8.705, "lng": 115.166, "date": "2027-01-06" }
],
"media": { "before": ["/media/<key>", "/media/<key>"], "after": ["/media/<key>", "/media/<key>"],
           "before_spots": [1, 2], "after_spots": [1, 2], "videos": [], "video_stages": [] }
```

- `spots`: 2 to 4, numbered 1, 2, ... in order. Spot 1 is the receipt's own `location` and `date`; `date` is the day the crew cleaned that spot. Points rounded like `location`'s, or `null`.
- `media.before_spots` and `media.after_spots`: one spot number for each photo of `media.before` and `media.after`, which come spot by spot. The videos (up to 30 before and 30 after) stay for the whole mission, without a spot.
- The homepage shows SPOT 1, SPOT 2 rows (place, country, day) instead of LOC and DATE, a green dot at each spot, every one opening the receipt, and the photos named by their spot (BEFORE · SPOT 2). It takes the list only when it is whole (`spotList` in `site/app.js`); otherwise the receipt shows its one location.
- A receipt with one spot has none of these keys.

## Missions (`GET /api/missions`)

Open and funded missions of active partners for the globe and the NEXT UP strip, newest published first, at most 200 (the homepage sorts NEXT UP itself: funded from today on, then open, then past days). The homepage shows them as `#12` tags on the globe and as NEXT UP cards, and never counts them in the stats: a mission only adds kg, cleanups and euros once its cleanup is approved and it is a receipt. A plain JSON array, cached for 60 seconds. It is `[]` when there are none, and also before migration 0004 has been applied.

```json
[
  {
    "no": 12,
    "status": "funded",
    "date": "2026-11-14",
    "place_name": "Canggu river mouth",
    "country": "ID",
    "lat": -8.659,
    "lng": 115.13,
    "crew_size": 5,
    "task": "Clear the river mouth.\nSort the plastic for the waste bank.",
    "currency": "IDR",
    "price_local": 2000000,
    "crew_local": 1200000,
    "funded_eur": 120,
    "partner": { "name": "Kali Bersih Crew", "slug": "kali-bersih", "logo": "/media/<key>" },
    "now": ["/media/<key>"],
    "now_video": "/media/<key>",
    "url": "https://sapu.earth/m/12"
  }
]
```

- `status`: `open` (shown, not funded yet, the "NEXT UP" ones) or `funded` (the money is agreed and the advance sent, the cleanup is coming). Done missions are receipts in `/api/events` instead.
- `date`: the planned day (YYYY-MM-DD), not a cleanup date.
- `lat` and `lng` are rounded to 3 decimals (about 100 m) or `null`. The exact point stays in `/admin/`.
- `task` is multiline text from the crew.
- `price_local` is what the crew asks in total, `crew_local` the pay of all crew members together, inside `price_local`, both in `currency`. The pay for each person is `crew_local / crew_size` and the other costs `price_local - crew_local`. The homepage shows them as ASKING (ASKED once funded), CREW PAY and OTHER COSTS.
- `funded_eur` is only there when `status` is `funded`.
- `now`: 1 to 4 photos of the place as it looks now. These files are public while the mission is open, funded or done, and deleted when it is removed (declined, cancelled, withdrawn, expired, unpublished, or its crew deactivated).
- `now_video`: the crew's short video of the place as it looks now (`/media/<key>`), or `null`. Public and deleted exactly like `now`.
- `partner.logo`: the crew's live logo (`/media/<key>`), or `null` without one (and before migration 0006). Always `/media/` and 32 hex characters, never the public bucket, so a removed logo answers 404 at once. The mission post shows it next to the crew's name; the NEXT UP card does not.
- `spots`: only for a mission with several spots (docs/missions.md, Spots), every spot, spot 1 first (spot 1 is `place_name`, `lat`, `lng` and `date`): `[{ "no": 1, "place_name": "...", "lat": -8.659, "lng": 115.13, "date": "2027-01-05" }, { "no": 2, ... }]`, 2 to 4 of them, points rounded like `lat` and `lng` or `null`. The homepage puts a pin at each spot (spots a few km apart share the mission's tag) and shows SPOT 1, SPOT 2 rows instead of LOC and DAY. None before migration 0008.

Never in this list: the mission id, the crew's private note, the internal review note, the advance, exact coordinates. Treat every text value as untrusted, the same as receipts.

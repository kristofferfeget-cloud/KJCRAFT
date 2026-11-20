# WoW Forever – profession routes 1–300

**Live:** <https://web-production-949755cb.up.railway.app>

A website that shows the cheapest way from 1 to 300 in every profession in **WoW: Forever** (Normal Alliance EU), calculated from **live AH prices**.

- Step-by-step routes for Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid – "Best route" and "Trainer only".
- Enter your skill to see what to craft now, how many crafts are left, a shopping list to 300 and gold tips.
- Separate pages for Herbalism, Mining, Skinning and Fishing.
- Filters for realistic gold costs: ignore AH items that sell fewer than X per day or have fewer than Y listed, choose a 5% (faction) or 15% (neutral) AH cut. Sales always use the better of AH price (after the cut) and vendor price.

## WoW addon (CraftPath)

`addon/CraftPath` is an in-game addon that shows the same routes: it reads your skill, shows the next recipe, mats left (counting bags and bank), gold tips and a mini tracker for all eight professions.

WoW addons cannot make web requests, so the addon reads `Data.lua`, which the server generates from the live routes:

- `/addon/CraftPath.zip` – the whole addon with fresh data
- `/addon/Data.lua` – just the data file
- `/addon/update.ps1` (Windows) and `/addon/update.sh` (macOS/Linux) – an updater that downloads a fresh `Data.lua` every 30 minutes. In game, `/reload` loads it.

All of them take the same filter parameters as `/api/data`. The website's **WoW addon** page has the download and copy-paste commands. In game, `/cpath web` gives a link back to the route on the website with your skill filled in (`/#tailoring/152`).

## How it works

`server.js` is a small Node server with no dependencies:

1. Fetches recipes from [seemeta](https://seemeta.com) (once a day) and merges them with learn levels and sources from Warcraft Wiki (`data/overrides.json`).
2. Fetches AH prices from [AHledger](https://ahledger.com) every 30 minutes (median price and daily sales, max 100 items per request).
3. Recalculates the routes (`src/model.js`) and serves the result at `/api/data`.
4. The page (`public/index.html`) picks up new numbers by itself every 2 minutes and shows when the last AH scan happened.

If AHledger does not respond, the last successful numbers are shown – or `public/snapshot.json` on first start.

## Run locally

```bash
npm start              # fetches live data (needs internet)
npm run offline        # snapshot only, no network calls
npm test
```

Open <http://localhost:3000>.

## Settings (environment variables)

| Variable | Default | What |
|---|---|---|
| `PORT` | `3000` | Port |
| `MARKET` | `forever.normal.alliance.eu` | AHledger market |
| `REFRESH_MINUTES` | `30` | How often prices are fetched (min. 10) |
| `RECIPES_REFRESH_HOURS` | `24` | How often recipes are fetched |
| `CACHE_DIR` | `.cache` | Where the latest data is kept between restarts |

## Hosting

Runs on Railway (project `kjcraft`, service `web`, region EU West). Every push to `main` deploys automatically.

## Endpoints

- `/` – the website
- `/api/data` – routes and prices as JSON. Optional filters: `?minSold=3&minListed=5&cut=5` (cut is 5 or 15). Non-default filters are computed on demand and cached until the next price refresh.
- `/api/status` – when prices were last fetched, and any errors
- `/health` – health check
- `/addon/CraftPath.zip`, `/addon/Data.lua`, `/addon/update.ps1`, `/addon/update.sh` – the addon and its updater

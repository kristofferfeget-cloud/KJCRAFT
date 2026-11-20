# WoW Forever – yrkesruter 1–300

**Live:** <https://web-production-949755cb.up.railway.app>

Nettside som viser billigste vei fra 1 til 300 i alle yrker i **WoW: Forever** (Normal Alliance EU), regnet ut fra **live AH-priser**.

- Ruter trinn for trinn for Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking og First Aid – «Beste rute» og «Kun trainer».
- Skriv inn skillen din, så ser du hva du skal lage nå, hvor mange crafts som gjenstår, handleliste til 300 og gulltips.
- Egne sider for Herbalism, Mining, Skinning og Fishing.

## Slik fungerer det

`server.js` er en liten Node-server uten avhengigheter:

1. Henter oppskrifter fra [seemeta](https://seemeta.com) (én gang i døgnet) og slår dem sammen med lærenivå og kilde fra Warcraft Wiki (`data/overrides.json`).
2. Henter AH-priser fra [AHledger](https://ahledger.com) hvert 30. minutt (median-pris og omsetning per dag, maks 100 varer per kall).
3. Regner ut rutene på nytt (`src/model.js`) og serverer resultatet på `/api/data`.
4. Siden (`public/index.html`) henter nye tall av seg selv hvert 2. minutt og viser når siste AH-skann var.

Hvis AHledger ikke svarer, vises siste vellykkede tall, eller `public/snapshot.json` ved første oppstart.

## Kjøre lokalt

```bash
npm start              # henter live data (krever internett)
npm run offline        # bare snapshot, ingen nettverkskall
npm test
```

Åpne <http://localhost:3000>.

## Innstillinger (miljøvariabler)

| Variabel | Standard | Hva |
|---|---|---|
| `PORT` | `3000` | Port |
| `MARKET` | `forever.normal.alliance.eu` | AHledger-marked |
| `REFRESH_MINUTES` | `30` | Hvor ofte prisene hentes (min. 10) |
| `RECIPES_REFRESH_HOURS` | `24` | Hvor ofte oppskriftene hentes |
| `CACHE_DIR` | `.cache` | Hvor siste data lagres mellom omstarter |

## Drift

Kjører på Railway (prosjekt `kjcraft`, tjeneste `web`, region EU West). Hver push til `main` deployes automatisk.

## Endepunkter

- `/` – nettsiden
- `/api/data` – rutene og prisene som JSON
- `/api/status` – når prisene sist ble hentet, og eventuelle feil
- `/health` – helsesjekk

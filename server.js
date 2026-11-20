// WoW Forever yrkesruter – small server that keeps AH prices fresh and serves the site.
import http from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SLUGS, EXTRA_IDS, buildRecipes, neededIds, compute } from './src/model.js';
import { fetchSeemeta, fetchPrices } from './src/sources.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PORT = +process.env.PORT || 3000;
const MARKET = process.env.MARKET || 'forever.normal.alliance.eu';
const REFRESH_MINUTES = Math.max(10, +process.env.REFRESH_MINUTES || 30);
const RECIPES_REFRESH_HOURS = Math.max(1, +process.env.RECIPES_REFRESH_HOURS || 24);
const CACHE_DIR = process.env.CACHE_DIR || path.join(ROOT, '.cache');
const OFFLINE = process.env.OFFLINE === '1'; // serve the bundled snapshot only (for local testing)

const overrides = JSON.parse(await readFile(path.join(ROOT, 'data', 'overrides.json'), 'utf8'));

const log = (...a) => console.log(new Date().toISOString(), ...a);
const fmtDate = (iso) => new Intl.DateTimeFormat('nb-NO', { timeZone: 'Europe/Oslo', day: '2-digit', month: '2-digit', year: 'numeric' }).format(new Date(iso));

const state = {
  payload: null, body: null, gz: null, etag: null,
  recipes: null, recipesAt: 0, recipesMeta: null,
  lastOk: null, lastError: null, lastAttempt: null, lastDurationMs: null, running: false, nextAt: null
};

function setPayload(p) {
  const json = JSON.stringify(p);
  state.payload = p;
  state.body = Buffer.from(json);
  state.gz = gzipSync(state.body);
  state.etag = '"' + createHash('sha1').update(json).digest('hex').slice(0, 20) + '"';
}

async function readJSON(file) { try { return JSON.parse(await readFile(file, 'utf8')); } catch { return null; } }
async function writeJSON(file, data) { try { await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, JSON.stringify(data)); } catch (e) { log('cache write failed:', e.message); } }

async function boot() {
  const cached = await readJSON(path.join(CACHE_DIR, 'latest.json'));
  if (cached && cached.profs) { setPayload({ ...cached, source: 'cache' }); log('loaded cached data from', cached.generatedAt); }
  else {
    const snap = await readJSON(path.join(ROOT, 'public', 'snapshot.json'));
    if (snap) { setPayload({ ...snap, source: 'snapshot', refreshMinutes: REFRESH_MINUTES }); log('serving bundled snapshot until the first live refresh'); }
  }
  const rc = await readJSON(path.join(CACHE_DIR, 'recipes.json'));
  if (rc && rc.recipes) { state.recipes = rc.recipes; state.recipesAt = rc.at || 0; state.recipesMeta = rc.meta || null; }
}

async function refresh() {
  if (state.running || OFFLINE) return;
  state.running = true;
  const t0 = Date.now();
  state.lastAttempt = new Date().toISOString();
  try {
    if (!state.recipes || Date.now() - state.recipesAt > RECIPES_REFRESH_HOURS * 3600e3) {
      try {
        const { profs, meta } = await fetchSeemeta(SLUGS);
        state.recipes = buildRecipes(profs, overrides);
        state.recipesAt = Date.now();
        state.recipesMeta = meta;
        await writeJSON(path.join(CACHE_DIR, 'recipes.json'), { at: state.recipesAt, meta, recipes: state.recipes });
        log('recipes updated:', Object.values(state.recipes).reduce((a, r) => a + r.length, 0), 'recipes, build', meta && meta.build);
      } catch (e) {
        if (!state.recipes) throw e;
        log('recipe refresh failed, keeping old recipes:', e.message);
      }
    }
    const ids = neededIds(state.recipes);
    const { P, BP, names, label, scannedAt, requests } = await fetchPrices(MARKET, ids);
    const priced = Object.keys(P).length;
    if (priced < Math.max(50, ids.length * 0.2)) throw new Error(`For få priser fra AHledger (${priced} av ${ids.length})`);
    const out = compute(state.recipes, P, BP);
    for (const id of EXTRA_IDS) if (!out.items[id] && names[id]) out.items[id] = names[id];
    const now = new Date().toISOString();
    const gaps = Object.keys(out.gaps);
    delete out.gaps;
    setPayload({
      source: 'live',
      market: label || 'Normal Alliance EU',
      marketSlug: MARKET,
      generatedAt: now,
      scannedAt: scannedAt || now,
      asOf: fmtDate(scannedAt || now),
      refreshMinutes: REFRESH_MINUTES,
      recipesBuild: state.recipesMeta ? state.recipesMeta.build : null,
      ...out
    });
    state.lastOk = now;
    state.lastError = null;
    await writeJSON(path.join(CACHE_DIR, 'latest.json'), state.payload);
    log(`refresh ok: ${priced}/${ids.length} priced in ${requests} requests, scan ${scannedAt}${gaps.length ? ', gaps in ' + gaps.join(',') : ''}`);
  } catch (e) {
    state.lastError = String((e && e.message) || e);
    log('refresh failed:', state.lastError);
  } finally {
    state.running = false;
    state.lastDurationMs = Date.now() - t0;
  }
}

// ---------- static files ----------
const TYPES = { '.html': 'text/html; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.txt': 'text/plain; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };
const STATIC = new Map();
async function loadStatic() {
  for (const [route, file] of [['/', 'index.html'], ['/index.html', 'index.html'], ['/snapshot.json', 'snapshot.json'], ['/favicon.svg', 'favicon.svg'], ['/robots.txt', 'robots.txt']]) {
    try {
      const body = await readFile(path.join(ROOT, 'public', file));
      STATIC.set(route, { body, gz: gzipSync(body), type: TYPES[path.extname(file)] || 'application/octet-stream', etag: '"' + createHash('sha1').update(body).digest('hex').slice(0, 20) + '"' });
    } catch { /* optional file */ }
  }
}

function send(req, res, status, { body, gz, type, etag, cache = 'no-cache', extra = {} }) {
  const headers = { 'content-type': type, 'cache-control': cache, 'x-content-type-options': 'nosniff', vary: 'accept-encoding', ...extra };
  if (etag) headers.etag = etag;
  if (etag && req.headers['if-none-match'] === etag) { res.writeHead(304, headers); return res.end(); }
  const useGz = gz && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
  if (useGz) headers['content-encoding'] = 'gzip';
  res.writeHead(status, headers);
  res.end(req.method === 'HEAD' ? undefined : (useGz ? gz : body));
}
const sendJSON = (req, res, status, obj) => { const body = Buffer.from(JSON.stringify(obj)); send(req, res, status, { body, type: TYPES['.json'], extra: { 'access-control-allow-origin': '*' } }); };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { allow: 'GET, HEAD' }); return res.end(); }
  if (url.pathname === '/api/data') {
    if (!state.body) return sendJSON(req, res, 503, { error: 'Data er ikke klare ennå' });
    return send(req, res, 200, { body: state.body, gz: state.gz, type: TYPES['.json'], etag: state.etag, extra: { 'access-control-allow-origin': '*' } });
  }
  if (url.pathname === '/api/status') {
    const p = state.payload || {};
    return sendJSON(req, res, 200, {
      source: p.source || null, market: p.market || null, generatedAt: p.generatedAt || null, scannedAt: p.scannedAt || null,
      lastOk: state.lastOk, lastAttempt: state.lastAttempt, lastError: state.lastError, lastDurationMs: state.lastDurationMs,
      refreshing: state.running, nextAt: state.nextAt, refreshMinutes: REFRESH_MINUTES,
      recipesBuild: state.recipesMeta && state.recipesMeta.build, recipesFetchedAt: state.recipesAt ? new Date(state.recipesAt).toISOString() : null
    });
  }
  if (url.pathname === '/health') return sendJSON(req, res, 200, { ok: true });
  const f = STATIC.get(url.pathname);
  if (f) return send(req, res, 200, f);
  res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('Ikke funnet');
});

await loadStatic();
await boot();
server.listen(PORT, () => log(`listening on :${PORT} (market ${MARKET}, refresh every ${REFRESH_MINUTES} min${OFFLINE ? ', OFFLINE' : ''})`));

const schedule = () => { state.nextAt = new Date(Date.now() + REFRESH_MINUTES * 60e3).toISOString(); };
refresh().finally(schedule);
setInterval(() => { refresh().finally(schedule); }, REFRESH_MINUTES * 60e3).unref?.();

const shutdown = () => { log('shutting down'); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 3000).unref(); };
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

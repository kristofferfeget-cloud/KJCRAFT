// WoW Forever profession routes – small server that keeps AH prices fresh and serves the site.
import http from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SLUGS, EXTRA_IDS, buildRecipes, neededIds, compute, normSrc } from './src/model.js';
import { fetchSeemeta, fetchPrices, fetchPriceTable, fetchCatalog, hasKey } from './src/sources.js';
import { buildDataLua, buildZip } from './src/addon.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PORT = +process.env.PORT || 3000;
const MARKET = process.env.MARKET || 'forever.normal.alliance.eu';
const REFRESH_MINUTES = Math.max(10, +process.env.REFRESH_MINUTES || 30);
const RECIPES_REFRESH_HOURS = Math.max(1, +process.env.RECIPES_REFRESH_HOURS || 24);
const CACHE_DIR = process.env.CACHE_DIR || path.join(ROOT, '.cache');
const OFFLINE = process.env.OFFLINE === '1'; // serve the bundled snapshot only (for local testing)
const DEFAULT_FILTERS = { minSold: 3, minListed: 5, cut: 5, src: 'TVDQ', pat: 6, ex: '' }; // cut in percent, pat = max pattern price in gold

const overrides = JSON.parse(await readFile(path.join(ROOT, 'data', 'overrides.json'), 'utf8'));

const log = (...a) => console.log(new Date().toISOString(), ...a);
const fmtDate = (iso) => new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Oslo', day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(iso));

const state = {
  payload: null, body: null, gz: null, etag: null,
  raw: null, variants: new Map(),
  recipes: null, recipesAt: 0, recipesMeta: null,
  lastOk: null, lastError: null, lastAttempt: null, lastDurationMs: null, running: false, nextAt: null,
  table: null, catalog: {}, catalogRunning: false, market: null
};

function pack(p) {
  const json = JSON.stringify(p);
  const body = Buffer.from(json);
  return { body, gz: gzipSync(body), etag: '"' + createHash('sha1').update(json).digest('hex').slice(0, 20) + '"', payload: p };
}
function setPayload(p) {
  const pk = pack(p);
  state.payload = p;
  state.body = pk.body;
  state.gz = pk.gz;
  state.etag = pk.etag;
  state.variants.clear();
  addonCache.clear();
}

// Read filter settings from the query string, clamped to sane ranges.
function readFilters(url) {
  const num = (k, lo, hi) => { const v = url.searchParams.get(k); if (v == null || v === '') return DEFAULT_FILTERS[k]; const n = +v; return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : DEFAULT_FILTERS[k]; };
  const cut = num('cut', 0, 50);
  const src = url.searchParams.has('src') ? normSrc(url.searchParams.get('src')) : DEFAULT_FILTERS.src;
  return { minSold: Math.round(num('minSold', 0, 100000) * 10) / 10, minListed: Math.round(num('minListed', 0, 100000)), cut: cut === 15 ? 15 : 5,
    src, pat: Math.round(num('pat', 0, 10000) * 100) / 100, ex: normEx(url.searchParams.get('ex')) };
}
// recipes the player can't make: spell ids, sorted, at most 60
function normEx(s) {
  const ids = [...new Set(String(s || '').split(/[^0-9]+/).filter(Boolean).map(Number).filter((n) => n > 0 && n < 1e7))].sort((a, b) => a - b);
  return ids.slice(0, 60).join(',');
}
const sameFilters = (a, b) => a.minSold === b.minSold && a.minListed === b.minListed && a.cut === b.cut && a.src === b.src && a.pat === b.pat && a.ex === b.ex;
const filterKey = (f) => `${f.minSold}|${f.minListed}|${f.cut}|${f.src}|${f.pat}|${f.ex}`;

// Build the full payload for a set of filters from the last fetched prices.
function buildPayload(filters) {
  const r = state.raw;
  const out = compute(state.recipes, r.P, r.BP, { minSold: filters.minSold, minListed: filters.minListed, cut: filters.cut / 100, src: filters.src, maxPattern: Math.round(filters.pat * 10000), exclude: filters.ex ? filters.ex.split(',').map(Number) : [] });
  for (const id of EXTRA_IDS) if (!out.items[id] && r.names[id]) out.items[id] = r.names[id];
  const gaps = Object.keys(out.gaps);
  delete out.gaps;
  return {
    payload: {
      source: 'live',
      market: r.label || 'Normal Alliance EU',
      marketSlug: MARKET,
      generatedAt: r.generatedAt,
      scannedAt: r.scannedAt,
      asOf: fmtDate(r.scannedAt),
      refreshMinutes: REFRESH_MINUTES,
      recipesBuild: state.recipesMeta ? state.recipesMeta.build : null,
      filters,
      ...out
    },
    gaps
  };
}

// Payload for non-default filters, computed on demand and cached until the next price refresh.
function variantFor(filters) {
  const key = filterKey(filters);
  let v = state.variants.get(key);
  if (!v) {
    v = pack(buildPayload(filters).payload);
    state.variants.set(key, v);
    if (state.variants.size > 40) state.variants.delete(state.variants.keys().next().value);
  }
  return v;
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
  const pt = await readJSON(path.join(CACHE_DIR, 'pricetable.json'));
  if (pt && Array.isArray(pt.rows)) state.table = pt;
  const cat = await readJSON(path.join(CACHE_DIR, 'catalog.json'));
  if (cat && cat.items) state.catalog = cat.items;
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
    if (priced < Math.max(50, ids.length * 0.2)) throw new Error(`Too few prices from AHledger (${priced} of ${ids.length})`);
    const now = new Date().toISOString();
    state.raw = { P, BP, names, label, scannedAt: scannedAt || now, generatedAt: now };
    const { payload, gaps } = buildPayload(DEFAULT_FILTERS);
    setPayload(payload);
    state.lastOk = now;
    state.lastError = null;
    await writeJSON(path.join(CACHE_DIR, 'latest.json'), state.payload);
    // every priced item on the market, for the addon's tooltips (not needed for the routes, so never fatal)
    try {
      const t = await fetchPriceTable(MARKET, state.table && state.table.etag);
      if (!t.notModified) { state.table = t; await writeJSON(path.join(CACHE_DIR, 'pricetable.json'), t); }
    } catch (e) { log('price table failed:', e.message); }
    fillCatalog(names);
    log(`refresh ok: ${priced}/${ids.length} priced in ${requests} requests, scan ${scannedAt}${gaps.length ? ', gaps in ' + gaps.join(',') : ''}`);
  } catch (e) {
    state.lastError = String((e && e.message) || e);
    log('refresh failed:', state.lastError);
  } finally {
    state.running = false;
    state.lastDurationMs = Date.now() - t0;
  }
}

// ---------- market overview ----------
const CATALOG_MAX_AGE = 14 * 24 * 3600e3;
const ICON_BASE = 'https://render.worldofwarcraft.com/classic1x-us/icons/56/';
// names, quality, class and icon for every item on the market: filled in the background, a few batches at a time
async function fillCatalog(known) {
  if (state.catalogRunning || !state.table) return;
  state.catalogRunning = true;
  try {
    const now = Date.now();
    const ids = state.table.rows.map((r) => r[0]).filter((id) => { const c = state.catalog[id]; return !c || now - (c[5] || 0) > CATALOG_MAX_AGE; });
    if (!ids.length) return;
    let saved = 0;
    const got = await fetchCatalog(MARKET, ids, {
      delayMs: hasKey() ? 400 : 2200, maxBatches: 80,
      onBatch: async (part) => {
        Object.assign(state.catalog, part);
        state.marketCache = null;
        if (++saved % 10 === 0) await writeJSON(path.join(CACHE_DIR, 'catalog.json'), { items: state.catalog });
      }
    });
    Object.assign(state.catalog, got);
    state.marketCache = null;
    await writeJSON(path.join(CACHE_DIR, 'catalog.json'), { items: state.catalog });
    log(`catalog: ${Object.keys(got).length} items updated, ${Object.keys(state.catalog).length} known`);
  } catch (e) {
    log('catalog failed:', e.message);
  } finally {
    state.catalogRunning = false;
  }
}

// every item on the market with its prices: [id, name, quality, class, icon, level, median, min, listed, med7, med30, low30, high30, soldPerDay]
function marketBody() {
  const t = state.table;
  if (!t) return null;
  if (state.marketCache && state.marketCache.ts === t.ts) return state.marketCache;
  const classes = [], clsIdx = new Map();
  const items = t.rows.map(([id, median, sold10, qty, min, m7, m30, lo, hi]) => {
    const c = state.catalog[id] || [];
    let ci = -1;
    if (c[2]) { if (!clsIdx.has(c[2])) { clsIdx.set(c[2], classes.length); classes.push(c[2]); } ci = clsIdx.get(c[2]); }
    const icon = c[3] ? (c[3].startsWith(ICON_BASE) ? c[3].slice(ICON_BASE.length).replace(/\.jpg$/, '') : c[3]) : null;
    return [id, c[0] || null, c[1] ?? 1, ci, icon, c[4] ?? null, median, min, qty, m7, m30, lo, hi, sold10 == null ? null : sold10 / 10];
  });
  const named = items.filter((x) => x[1]).length;
  const obj = { market: (state.payload && state.payload.market) || 'Normal Alliance EU', marketId: MARKET, scannedAt: new Date(t.ts * 1000).toISOString(),
    generatedAt: new Date().toISOString(), iconBase: ICON_BASE, ahApi: process.env.AHLEDGER_BASE || 'https://api.ahledger.com', classes, named, total: items.length, catalogFilling: state.catalogRunning, items };
  const body = Buffer.from(JSON.stringify(obj));
  state.marketCache = { ts: t.ts, body, gz: gzipSync(body), etag: '"m-' + t.ts + '-' + named + '"' };
  return state.marketCache;
}

// ---------- addon downloads ----------
const ADDON_FILES = ['CraftPath.toc', 'Core.lua', 'UI.lua', 'Tooltip.lua', 'AHScan.lua', 'README.txt'];
const addonSrc = {};
const scripts = {};
const addonCache = new Map();
async function loadAddon() {
  for (const f of ADDON_FILES) addonSrc[f] = await readFile(path.join(ROOT, 'addon', 'CraftPath', f));
  for (const f of ['update.ps1', 'update.sh']) scripts[f] = await readFile(path.join(ROOT, 'addon', f), 'utf8');
}
function baseUrl(req) {
  if (process.env.PUBLIC_URL) return process.env.PUBLIC_URL.replace(/\/$/, '');
  const proto = (req.headers['x-forwarded-proto'] || 'http').split(',')[0].trim();
  return `${proto}://${req.headers['x-forwarded-host'] || req.headers.host}`;
}
function filterQuery(f) {
  return sameFilters(f, DEFAULT_FILTERS) ? '' : `?minSold=${f.minSold}&minListed=${f.minListed}&cut=${f.cut}&src=${f.src}&pat=${f.pat}${f.ex ? '&ex=' + f.ex : ''}`;
}
// The route payload for a request's filters (default payload when filters can't be applied yet).
function payloadFor(filters) {
  if (state.raw && state.recipes && !sameFilters(filters, DEFAULT_FILTERS)) {
    try { return variantFor(filters); } catch (e) { log('filter compute failed:', e.message); }
  }
  return { body: state.body, gz: state.gz, etag: state.etag, payload: state.payload };
}
function addonBuild(kind, v, base) {
  const key = `${kind}|${v.etag}|${base}|${state.table ? state.table.ts : 0}`;
  let hit = addonCache.get(key);
  if (!hit) {
    const lua = buildDataLua(v.payload, base, state.table);
    const body = kind === 'zip'
      ? buildZip([...ADDON_FILES.map((f) => ({ name: `CraftPath/${f}`, data: addonSrc[f] })), { name: 'CraftPath/Data.lua', data: lua }])
      : Buffer.from(lua);
    hit = { body, gz: kind === 'zip' ? null : gzipSync(body), etag: '"' + kind + '-' + v.etag.replace(/"/g, '') + '-' + (state.table ? state.table.ts : 0) + '"' };
    addonCache.set(key, hit);
    if (addonCache.size > 30) addonCache.delete(addonCache.keys().next().value);
  }
  return hit;
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
    if (!state.body) return sendJSON(req, res, 503, { error: 'Data is not ready yet' });
    const filters = readFilters(url);
    let v = { body: state.body, gz: state.gz, etag: state.etag };
    if (state.raw && state.recipes && !sameFilters(filters, DEFAULT_FILTERS)) {
      try { v = variantFor(filters); } catch (e) { log('filter compute failed:', e.message); }
    }
    return send(req, res, 200, { body: v.body, gz: v.gz, type: TYPES['.json'], etag: v.etag, extra: { 'access-control-allow-origin': '*' } });
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
  if (url.pathname === '/api/market') {
    const m = marketBody();
    if (!m) return sendJSON(req, res, 503, { error: 'Market data is not ready yet' });
    return send(req, res, 200, { body: m.body, gz: m.gz, etag: m.etag, type: TYPES['.json'], extra: { 'access-control-allow-origin': '*' } });
  }
  if (url.pathname === '/addon/Data.lua' || url.pathname === '/addon/CraftPath.zip') {
    if (!state.payload) return sendJSON(req, res, 503, { error: 'Data is not ready yet' });
    const zip = url.pathname.endsWith('.zip');
    const v = payloadFor(readFilters(url));
    const hit = addonBuild(zip ? 'zip' : 'lua', v, baseUrl(req));
    return send(req, res, 200, {
      body: hit.body, gz: hit.gz, etag: hit.etag,
      type: zip ? 'application/zip' : 'text/plain; charset=utf-8',
      extra: { 'content-disposition': `attachment; filename="${zip ? 'CraftPath.zip' : 'Data.lua'}"`, 'access-control-allow-origin': '*' }
    });
  }
  if (url.pathname === '/addon/update.ps1' || url.pathname === '/addon/update.sh') {
    const name = url.pathname.slice(7);
    const text = scripts[name].replaceAll('__BASE__', baseUrl(req)).replaceAll('__QUERY__', filterQuery(readFilters(url)));
    return send(req, res, 200, { body: Buffer.from(text), type: 'text/plain; charset=utf-8', extra: { 'content-disposition': `inline; filename="${name}"` } });
  }
  const f = STATIC.get(url.pathname);
  if (f) return send(req, res, 200, f);
  res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('Not found');
});

await loadStatic();
await loadAddon();
await boot();
server.listen(PORT, () => log(`listening on :${PORT} (market ${MARKET}, refresh every ${REFRESH_MINUTES} min${OFFLINE ? ', OFFLINE' : ''})`));

const schedule = () => { state.nextAt = new Date(Date.now() + REFRESH_MINUTES * 60e3).toISOString(); };
refresh().finally(schedule);
setInterval(() => { refresh().finally(schedule); }, REFRESH_MINUTES * 60e3).unref?.();

const shutdown = () => { log('shutting down'); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 3000).unref(); };
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

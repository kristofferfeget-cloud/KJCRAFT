// Data sources: seemeta (recipes) and AHledger (auction house prices).

const UA = 'wow-forever-yrkesruter/1.0 (+https://github.com/kristofferfeget-cloud/KJCRAFT)';
const AH_BASE = process.env.AHLEDGER_BASE || 'https://api.ahledger.com';
const SEEMETA_BASE = process.env.SEEMETA_BASE || 'https://seemeta.com';
const QUALITY = { POOR: 0, COMMON: 1, UNCOMMON: 2, RARE: 3, EPIC: 4, LEGENDARY: 5, ARTIFACT: 6, HEIRLOOM: 7 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// optional free AHledger key (raises the rate limit; needed for 30-day history from 10 Dec 2026)
const KEY = process.env.AHLEDGER_KEY || '';
const authFor = (url) => (KEY && url.startsWith(AH_BASE) ? { authorization: `Bearer ${KEY}` } : {});
export const hasKey = () => !!KEY;

async function getJSON(url, { timeoutMs = 25000, tries = 3 } = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'user-agent': UA, accept: 'application/json', ...authFor(url) }, signal: AbortSignal.timeout(timeoutMs) });
      if (res.status === 429) {
        const wait = Math.min(60, +(res.headers.get('retry-after') || 10)) * 1000;
        lastErr = new Error(`429 from ${new URL(url).host}`);
        await sleep(wait);
        continue;
      }
      if (!res.ok) throw new Error(`${res.status} from ${new URL(url).host}${new URL(url).pathname}`);
      const text = await res.text();
      try { return JSON.parse(text); } catch { throw new Error(`Invalid JSON from ${new URL(url).host} (${text.slice(0, 80).replace(/\s+/g, ' ')})`); }
    } catch (e) {
      lastErr = e;
      if (attempt < tries) await sleep(1000 * attempt * attempt);
    }
  }
  throw lastErr;
}

/** Fetch recipe data for each profession from seemeta. */
export async function fetchSeemeta(slugs) {
  const profs = {};
  let meta = null;
  for (const slug of slugs) {
    const j = await getJSON(`${SEEMETA_BASE}/data/wow-forever-professions.en.profession-${slug}.json`, { timeoutMs: 60000 });
    const p = (j.professions || []).find((x) => x.slug === slug);
    if (!p || !Array.isArray(p.recipes) || !p.recipes.length) throw new Error(`seemeta: no recipes found for ${slug}`);
    profs[slug] = { recipes: p.recipes };
    meta = { build: j.build || null, version: j.version || null, updatedAt: j.updatedAt || null };
  }
  return { profs, meta };
}

/**
 * Fetch AH prices for a list of item ids from AHledger's tooltip endpoint (max 100 ids per request).
 * Returns P (median price + sales/day), BP (pattern prices), item names and the latest scan time.
 */
export async function fetchPrices(market, ids, { batch = 100, delayMs = 350 } = {}) {
  const P = {}, BP = {}, names = {};
  let label = null, scannedAt = null, requests = 0;
  for (let i = 0; i < ids.length; i += batch) {
    const chunk = ids.slice(i, i + batch);
    const j = await getJSON(`${AH_BASE}/v1/tooltip/${market}?items=${chunk.join(',')}`);
    requests++;
    if (j.market && j.market.label) label = j.market.label;
    for (const it of j.items || []) {
      if (it.median != null) P[it.id] = { price: it.median, sales: it.salesPerDay ?? null, listed: it.quantity ?? null };
      BP[it.id] = { med: it.median ?? null, min: it.minBuyout ?? null, qty: it.quantity || 0 };
      if (it.name) names[it.id] = [it.name, QUALITY[it.quality] ?? 1];
      if (it.observedAt && (!scannedAt || it.observedAt > scannedAt)) scannedAt = it.observedAt;
    }
    if (i + batch < ids.length) await sleep(delayMs);
  }
  return { P, BP, names, label, scannedAt, requests };
}

/**
 * Every priced item on a market from AHledger's price table (one request, plain text, ETag).
 * Returns { ts, rows: [[id, median, soldPerDayTimes10|null, listed|null, minBuyout, median7d, median30d, low30d, high30d], ...], etag }
 * or { notModified: true }.
 * Format: header "AHL1|market|unixTime|rows", then id:median:minBuyout:quantity:median7d:median30d:low30d:high30d:soldPerDay*10
 */
export async function fetchPriceTable(market, etag) {
  const headers = { 'user-agent': UA, accept: 'text/plain', ...authFor(AH_BASE) };
  if (etag) headers['if-none-match'] = etag;
  const res = await fetch(`${AH_BASE}/v1/pricetable/${market}`, { headers, signal: AbortSignal.timeout(45000) });
  if (res.status === 304) return { notModified: true };
  if (!res.ok) throw new Error(`${res.status} from AHledger price table`);
  const lines = (await res.text()).split(/\r?\n/);
  const head = (lines[0] || '').split('|');
  if (head[0] !== 'AHL1') throw new Error('AHledger price table: unknown format ' + String(head[0]).slice(0, 20));
  const num = (s) => (s === undefined || s === '' ? null : Number(s));
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const f = lines[i].split(':');
    const id = num(f[0]), median = num(f[1]);
    if (!Number.isInteger(id) || id <= 0 || median == null || !Number.isFinite(median)) continue;
    rows.push([id, Math.round(median), num(f[8]), num(f[3]), num(f[2]), num(f[4]), num(f[5]), num(f[6]), num(f[7])]);
  }
  return { ts: num(head[2]) || Math.floor(Date.now() / 1000), rows, etag: res.headers.get('etag') };
}

/**
 * Item names, quality, class, icon and level for many ids (AHledger tooltip endpoint, 100 per request).
 * Paced so it never crowds the rate limit; calls onBatch after each request so progress is kept.
 */
export async function fetchCatalog(market, ids, { delayMs = 2200, maxBatches = 80, onBatch } = {}) {
  const out = {};
  let n = 0;
  for (let i = 0; i < ids.length && n < maxBatches; i += 100, n++) {
    const chunk = ids.slice(i, i + 100);
    const j = await getJSON(`${AH_BASE}/v1/tooltip/${market}?items=${chunk.join(',')}`);
    const now = Date.now();
    for (const it of j.items || []) {
      if (!it || !it.id) continue;
      out[it.id] = [it.name || null, QUALITY[it.quality] ?? 1, it.itemClass || null, it.icon || null, it.level ?? null, now];
    }
    // ids the market does not know still get an entry, so they are not asked for again and again
    for (const id of chunk) if (!out[id]) out[id] = [null, 1, null, null, null, now];
    if (onBatch) await onBatch(out);
    if (i + 100 < ids.length && n + 1 < maxBatches) await sleep(delayMs);
  }
  return out;
}

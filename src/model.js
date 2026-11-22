// Route model: turns recipe data + AH prices into the cheapest 1-300 routes.
// Pure functions, no I/O, so the same code can run on the server and in a test harness.

export const SLUGS = ['alchemy', 'blacksmithing', 'enchanting', 'engineering', 'leatherworking', 'tailoring', 'cooking', 'first-aid'];

// Vendor buy prices (copper) for common reagents sold by trade-supply vendors.
export const VBUY = { 2320: 10, 2321: 100, 2324: 25, 2325: 1000, 2604: 50, 2605: 100, 2678: 10, 2692: 40, 2880: 100, 3371: 4, 3372: 40, 3466: 2000, 3713: 160, 3857: 500, 4289: 50, 4291: 500, 4340: 350, 4341: 500, 4342: 2500, 4399: 200, 4400: 2000, 4470: 38, 6260: 50, 6261: 1000, 8343: 2000, 8925: 500, 10290: 2500, 14341: 5000, 18256: 6000 };

// Items bought from general vendors, priced at 4x their vendor sell price (water, vials of honeymead, etc.).
export const VSET = new Set([159, 1179, 6217, 10647, 10648, 2593, 2594, 2596, 1708, 8766, 2894, 4536, 5051, 17194, 17196, 3857]);

// Engineering items that need Gnomish/Goblin specialization (besides names starting with Gnomish/Goblin).
const SPEC = ['The Big One', 'Dimensional Ripper - Everlook', 'Ultrasafe Transporter - Gadgetzan', 'World Enlarger', 'Goblin Jumper Cables XL'];

// Item ids shown on the gathering pages, so they always get a price.
export const EXTRA_IDS = [
  2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,
  2840, 3576, 2841, 2842, 3575, 3577, 3859, 3860, 6037, 11371, 12359,
  774, 818, 1210, 1206, 1705, 1529, 3864, 7909, 7910, 12363, 12800,
  2318, 2319, 4234, 4304, 8170, 4232, 4235, 8171, 7286, 8165, 8167, 15408, 15412, 15416, 15419, 15423, 249428, 248824,
  13893, 13759, 4655, 5504, 5503, 5500, 7971
];

// minSold / minListed: items that sell less than minSold per day or have fewer than minListed on the AH are ignored on the AH
// (not bought there, and not counted on to sell there). cut: the AH's cut of a sale.
export const DEFAULT_OPTS = { minP: 0.2, pen: 2000, sticky: 700, risk: 0.12, src: 'TVDQ', maxPattern: 60000, goldTop: 15, goldMinNet: 100, goldMinSold: 5, minSold: 3, minListed: 5, cut: 0.05 };

// Capital-penalty levels for the budget family: from "most gold" (the default route) to "least gold tied up".
// The site and the addon pick the best of these routes that fits the player's gold.
export const RISK_LEVELS = [0.12, 0.25, 0.5, 1, 2, 4, 8, 16, 40];

const round1 = (x) => Math.round(x * 10) / 10;

/**
 * Normalise seemeta profession JSON into recipe objects.
 * @param {Record<string, any>} seemeta  slug -> profession object ({recipes:[...]})
 * @param {{src:Record<string,number[]>, learn:Record<string,number[]>}} overrides  learn level / source per spell (from Warcraft Wiki)
 */
export function buildRecipes(seemeta, overrides) {
  const srcOf = new Map();
  for (const [k, arr] of Object.entries(overrides.src || {})) for (const s of arr) srcOf.set(s, k);
  const learnOf = new Map();
  for (const [k, arr] of Object.entries(overrides.learn || {})) for (const s of arr) learnOf.set(s, +k);
  const out = {};
  for (const slug of SLUGS) {
    const prof = seemeta[slug];
    if (!prof || !Array.isArray(prof.recipes)) continue;
    out[slug] = prof.recipes.filter((r) => r && r.spellId && r.skill).map((r) => {
      const sk = r.skill;
      const books = (r.source && r.source.books) || [];
      const method = r.source && r.source.method;
      const repBook = books.find((b) => b && b.reputation);
      let src = srcOf.get(r.spellId);
      if (!src) src = method === 'automatic' ? 'T' : method === 'unknown' ? 'U' : repBook ? 'R' : 'P';
      let learn = learnOf.get(r.spellId);
      if (learn == null) learn = sk.trainerRequired ?? sk.required ?? sk.yellow ?? 1;
      const y = Math.max(sk.yellow ?? learn, learn);
      const g = Math.max(sk.green ?? y, y);
      const gr = Math.max(sk.grey ?? g, g);
      const ci = r.createdItem;
      return {
        prof: slug, name: r.name, spell: r.spellId, learn, y, g, gr, src,
        rep: repBook ? (repBook.reputation.name || null) : null,
        bookId: books[0] ? books[0].id : null,
        res: ci && ci.id ? { id: ci.id, n: ci.count || 1, vs: ci.vendorSellPrice || 0, q: ci.quality ?? 1, name: ci.name } : null,
        reag: (r.reagents || []).map((x) => ({ id: x.id, n: x.count || 1, q: x.quality ?? 1, name: x.name, vs: x.vendorSellPrice || 0 }))
      };
    });
  }
  return out;
}

/** All item ids whose AH price the model needs. */
export function neededIds(recipes) {
  const ids = new Set(EXTRA_IDS);
  for (const recs of Object.values(recipes)) for (const r of recs) {
    for (const g of r.reag) ids.add(g.id);
    if (r.res) ids.add(r.res.id);
    if (r.bookId) ids.add(r.bookId);
  }
  return [...ids].sort((a, b) => a - b);
}

const isCD = (r) => (/^Transmute:/.test(r.name) && r.name !== 'Transmute: Elemental Fire') || r.name === 'Mooncloth' || /^Refined Salt/.test(r.name);
const isSpec = (r) => r.prof === 'engineering' && (/^Gnomish /.test(r.name) || /^Goblin /.test(r.name) || SPEC.includes(r.name));
// Recipe-source groups for the "recipe sources" filter: AH patterns and unknown sources count as drops.
const SRC_GROUP = { T: 'T', V: 'V', D: 'D', P: 'D', U: 'D', Q: 'Q', R: 'R' };
export const SRC_LETTERS = 'TVDQR';
/** Normalise a sources string ("vdq" -> "TVDQ"); the trainer is always allowed. */
export function normSrc(s) {
  const set = new Set(String(s ?? '').toUpperCase().split(''));
  return [...SRC_LETTERS].filter((c) => c === 'T' || set.has(c)).join('');
}
const patCost = (r) => (['P', 'D', 'Q'].includes(r.src) && r.book && r.book.price != null && r.book.qty >= 1) ? r.book.price : null;

/** Chance of a skill-up at skill s. */
export function pp(r, s) {
  if (s < r.learn || s >= r.gr) return 0;
  if (s < r.y) return 1;
  return (r.gr - s) / (r.gr - r.y);
}
function crafts(r, a, b) {
  let n = 0;
  for (let s = a; s < b; s++) { const p = pp(r, s); if (p > 0) n += 1 / p; }
  return n;
}

/**
 * Greedy route: at each skill level pick the recipe with the lowest cost per point.
 * filters: list of predicates tried in order (first one that yields a candidate wins).
 */
function route(recs, filters, opt) {
  const { minP, pen, sticky, risk } = opt;
  // patterns are capital too: weigh them up when the capital penalty is raised (no change at the default level)
  const patFactor = 1 + Math.max(0, risk - (opt.baseRisk ?? risk));
  const used = {}, learned = {}, segs = [];
  let prevK = null;
  for (let s = 1; s < 300; s++) {
    let best = null;
    for (const fn of filters) {
      for (const r of recs) {
        if (!fn(r)) continue;
        const p = pp(r, s);
        if (p < minP) continue;
        const k = r.spell, n = 1 / p;
        const yld = (r.res && r.res.n) || 1;
        const vend = ((r.res && r.res.vs) || 0) * yld;
        const cap = r.how === 'AH' ? Math.max(2, r.sold || 0) : 0;
        const u = used[k] || 0;
        const ahN = Math.max(0, Math.min(n, cap - u));
        const val = ahN * r.sale + (n - ahN) * (r.how === 'AH' ? vend : r.sale);
        const cost = n * r.mats - val;
        const pc = (!learned[k] && patCost(r)) ? patCost(r) * patFactor : 0;
        const score = cost + pc + n * pen + n * r.mats * risk + (k === prevK ? 0 : sticky);
        if (!best || score < best.score) best = { r, score, k, n };
      }
      if (best) break;
    }
    if (!best) { segs.push({ gap: s }); prevK = null; continue; }
    used[best.k] = (used[best.k] || 0) + best.n;
    learned[best.k] = 1;
    prevK = best.k;
    const last = segs[segs.length - 1];
    if (last && last.k === best.k) last.to = s + 1;
    else segs.push({ k: best.k, r: best.r, from: s, to: s + 1 });
  }
  const sg = segs.filter((x) => !x.gap);
  const gaps = segs.filter((x) => x.gap).map((x) => x.gap);
  const works = (r, a, b) => { for (let s = a; s < b; s++) if (pp(r, s) < minP) return false; return true; };
  let ch = true;
  while (ch) {
    ch = false;
    for (let i = 0; i < sg.length; i++) {
      const g = sg[i];
      if (g.to - g.from >= 3) continue;
      const pv = sg[i - 1], nx = sg[i + 1];
      if (pv && pv.to === g.from && works(pv.r, g.from, g.to)) { pv.to = g.to; sg.splice(i, 1); ch = true; break; }
      if (nx && nx.from === g.to && works(nx.r, g.from, g.to)) { nx.from = g.from; sg.splice(i, 1); ch = true; break; }
    }
    for (let i = 1; i < sg.length; i++) {
      if (sg[i].k === sg[i - 1].k && sg[i - 1].to === sg[i].from) { sg[i - 1].to = sg[i].to; sg.splice(i, 1); ch = true; break; }
    }
  }
  return { segs: sg, gaps };
}

/**
 * Compute everything the site shows.
 * @param recipes  output of buildRecipes
 * @param P   item id -> {price (median copper), sales (per day), listed}
 * @param BP  item id -> {med, min, qty}  (pattern prices, same source)
 */
export function compute(recipes, P, BP, options = {}) {
  const opt = { ...DEFAULT_OPTS, riskLevels: RISK_LEVELS, ...options };
  const exclude = new Set((opt.exclude || []).map(Number));
  const out = { profs: {}, items: {}, prices: {}, crafts: {}, gaps: {}, ignored: 0, riskLevels: opt.riskLevels };
  // An item counts on the AH only if it trades and is listed in enough volume.
  const liquid = (id) => { const p = P[id]; return !!p && p.price != null && (p.sales ?? 0) >= opt.minSold && (p.listed ?? 0) >= opt.minListed; };
  for (const id of Object.keys(P)) if (P[id].price != null && !liquid(id)) out.ignored++;
  const itemInfo = new Map();
  const VS = {};
  for (const recs of Object.values(recipes)) for (const r of recs) {
    for (const g of r.reag) { if (!itemInfo.has(g.id)) itemInfo.set(g.id, [g.name, g.q]); if (g.vs) VS[g.id] = g.vs; }
    if (r.res && !itemInfo.has(r.res.id)) itemInfo.set(r.res.id, [r.res.name, r.res.q]);
  }
  const useItem = (id) => { const i = itemInfo.get(id); if (i) out.items[id] = i; };

  for (const slug of SLUGS) {
    const src = recipes[slug];
    if (!src) continue;
    const recs = src.map((r) => ({ ...r }));
    const prodBy = new Map();
    for (const r of recs) if (r.res) { const a = prodBy.get(r.res.id) || []; a.push(r); prodBy.set(r.res.id, a); }
    // strict: thin AH items are ignored (the filters). Non-strict prices are only a last resort so a route never has holes.
    const memo = new Map();
    const unitOf = (strict) => function unit(id, d = 0) {
      const key = id + '|' + d + '|' + strict;
      if (memo.has(key)) return memo.get(key);
      let best = null, how = null, via = null;
      const ah = (strict ? liquid(id) : (P[id] && P[id].price != null)) ? P[id].price : null;
      if (ah != null) { best = ah; how = 'AH'; }
      const vb = VBUY[id] != null ? VBUY[id] : (VSET.has(id) && VS[id] ? VS[id] * 4 : null);
      if (vb != null && (best == null || vb <= best)) { best = vb; how = 'V'; }
      if (d < 2) {
        for (const p of prodBy.get(id) || []) {
          if (isCD(p)) continue;
          let c = 0, ok = true;
          for (const g of p.reag) { const u = unit(g.id, d + 1); if (!u) { ok = false; break; } c += u.c * g.n; }
          if (ok) { c /= (p.res.n || 1); if (best == null || c < best) { best = c; how = 'craft'; via = p; } }
        }
      }
      const res = best == null ? null : { c: best, how, via: how === 'craft' ? via : null };
      memo.set(key, res);
      return res;
    };
    const unit = unitOf(true), unitRaw = unitOf(false);
    for (const r of recs) {
      let c = 0;
      for (const g of r.reag) { const u = unit(g.id); if (!u) { c = null; break; } c += u.c * g.n; }
      r.mats = c;
      r.thin = false;
      if (c == null) {
        let c2 = 0;
        for (const g of r.reag) { const u = unitRaw(g.id); if (!u) { c2 = null; break; } c2 += u.c * g.n; }
        if (c2 != null) { r.mats = c2; r.thin = true; }
      }
      if (!r.res) { r.sale = 0; r.how = 'none'; }
      else {
        const p = P[r.res.id];
        const vend = (r.res.vs || 0) * r.res.n;
        r.ahVal = p && p.price != null ? p.price * (1 - opt.cut) * r.res.n : null;
        r.liquid = liquid(r.res.id);
        if (r.liquid) {
          const a = r.ahVal;
          if (a > vend) { r.sale = a; r.how = 'AH'; } else { r.sale = vend; r.how = 'vendor'; }
        } else { r.sale = vend; r.how = vend > 0 ? 'vendor' : 'none'; }
      }
      r.sold = r.res && P[r.res.id] ? (P[r.res.id].sales || 0) : 0;
      r.book = r.bookId ? { id: r.bookId, price: BP[r.bookId] ? BP[r.bookId].med : null, qty: BP[r.bookId] ? (BP[r.bookId].qty || 0) : 0 } : null;
    }
    // recipe sources the player wants to use (trainer always); others only fill a hole nothing else covers
    const okSrc = new Set(normSrc(opt.src));
    const srcOK = (r) => okSrc.has(SRC_GROUP[r.src] || 'D');
    // recipes the player said they can't make: never used, not even to fill a hole
    const allowLast = (r) => !exclude.has(r.spell) && !isCD(r) && !isSpec(r) && r.mats != null;
    const allowLastOK = (r) => allowLast(r) && srcOK(r);
    const allowAny = (r) => allowLastOK(r) && !r.thin;
    const allowBest = (r) => allowAny(r) && (r.src === 'T' || r.src === 'V' || r.src === 'R' || (patCost(r) != null && patCost(r) <= opt.maxPattern));
    const allowTrainer = (r) => allowAny(r) && r.src === 'T';

    const usePrice = (id, d = 0) => {
      const u = unit(id) || unitRaw(id);
      if (u) {
        const prev = out.prices[id]; const c = Math.round(u.c);
        if (!prev || c < prev[0]) {
          out.prices[id] = [c, u.how, P[id] ? (P[id].listed ?? null) : null, P[id] ? (P[id].sales ?? null) : null];
          // mats that are cheaper to make yourself: what they are made of, so the site can say what to buy
          if (u.how === 'craft' && u.via) {
            out.crafts[id] = [u.via.res.n || 1, u.via.reag.map((g) => [g.id, g.n]), u.via.name];
            if (d < 2) u.via.reag.forEach((g) => usePrice(g.id, d + 1));
          } else delete out.crafts[id];
        }
      }
      useItem(id);
    };
    // other recipes for the same skill range, best first (same costs as the route: mats, sales, patterns)
    const altsFor = (seg, filters) => {
      const span = seg.to - seg.from, rows = [];
      for (const r of recs) {
        if (r.spell === seg.r.spell) continue;
        const tier = filters.findIndex((fn) => fn(r));
        if (tier < 0 || pp(r, seg.from) < opt.minP) continue;
        let n = 0, val = 0, to = seg.from;
        const yld = (r.res && r.res.n) || 1, vend = ((r.res && r.res.vs) || 0) * yld;
        for (let s = seg.from; s < seg.to; s++) {
          const p = pp(r, s);
          if (p < opt.minP) break;
          n += 1 / p; to = s + 1;
        }
        const cap = r.how === 'AH' ? Math.max(2, r.sold || 0) : 0, ahN = Math.min(n, cap);
        val = ahN * r.sale + (n - ahN) * (r.how === 'AH' ? vend : r.sale);
        const pc = patCost(r) || 0, pts = to - seg.from;
        const net = val - n * r.mats - pc;
        // rank: allowed sources first, then cost per point (with the same capital penalty as the route)
        const score = (n * r.mats - val + pc + n * opt.pen + n * r.mats * opt.risk) / pts + (pts < span ? opt.pen : 0);
        rows.push({ r, tier, score, n, to, net });
      }
      rows.sort((a, b) => a.tier - b.tier || a.score - b.score);
      const seen = new Set();
      return rows.filter((x) => (seen.has(x.r.name) ? false : (seen.add(x.r.name), true))).slice(0, 3).map(({ r, n, to, net }) => {
        r.reag.forEach((g) => usePrice(g.id));
        if (r.res) useItem(r.res.id);
        return [r.spell, r.name, r.res ? r.res.id : 0, r.src, r.learn, r.y, r.g, r.gr, Math.round(r.mats), Math.round(r.sale), r.how,
          patCost(r) || 0, round1(n), to, Math.round(net), r.reag.map((g) => [g.id, g.n]), r.rep || ''];
      });
    };
    const stepOf = (seg, filters) => {
      const r = seg.r;
      r.reag.forEach((g) => usePrice(g.id));
      if (r.res) useItem(r.res.id);
      return [seg.from, seg.to, r.name, r.res ? r.res.id : 0, r.res ? r.res.n : 1, r.learn, r.y, r.g, r.gr, r.src,
        patCost(r) || 0, round1(crafts(r, seg.from, seg.to)), Math.round(r.mats), Math.round(r.sale), r.how,
        r.res ? round1(r.sold) : null, r.res ? (r.res.vs || 0) * r.res.n : 0, r.reag.map((g) => [g.id, g.n]), r.thin ? 1 : 0,
        r.res && r.ahVal != null ? Math.round(r.ahVal) : null, r.res && P[r.res.id] ? (P[r.res.id].listed ?? null) : null, r.res ? (r.liquid ? 1 : 0) : 0,
        r.spell, filters ? altsFor(seg, filters) : null];
    };
    const FILTERS = { best: [allowBest, allowAny, allowLastOK, allowLast], trainer: [allowTrainer, allowBest, allowAny, allowLastOK, allowLast] };
    const best = route(recs, FILTERS.best, opt);
    const trainer = route(recs, FILTERS.trainer, opt);
    const seenRes = new Set();
    const gold = recs
      .filter((r) => srcOK(r) && !exclude.has(r.spell) && r.how === 'AH' && r.mats != null && !r.thin && r.learn <= 300 && r.sale - r.mats >= opt.goldMinNet && r.sold >= Math.max(opt.goldMinSold, opt.minSold))
      .map((r) => ({ r, score: (r.sale - r.mats) * Math.min(r.sold * 0.25, 20) }))
      .sort((a, b) => b.score - a.score)
      .filter(({ r }) => (seenRes.has(r.res.id) ? false : (seenRes.add(r.res.id), true)))
      .slice(0, opt.goldTop)
      .map(({ r }) => {
        r.reag.forEach((g) => usePrice(g.id));
        useItem(r.res.id);
        return [r.name, r.res.id, r.res.n, r.learn, r.src, Math.round(r.mats), Math.round(r.sale), round1(r.sold),
          isCD(r) ? 'cd' : isSpec(r) ? 'spec' : '', r.rep || '', patCost(r) || 0, r.reag.map((g) => [g.id, g.n])];
      });
    // budget family: the same greedy with a growing penalty on gold tied up in mats and patterns
    const keyOf = (segs) => segs.map((s) => s.k + ':' + s.from + ':' + s.to).join('|');
    const defaults = { best, trainer };
    const alts = [], altIdx = new Map(), fam = { best: [], trainer: [] };
    for (const v of ['best', 'trainer']) {
      const defKey = keyOf(defaults[v].segs);
      for (const risk of opt.riskLevels) {
        const r = risk === opt.risk ? defaults[v] : route(recs, FILTERS[v], { ...opt, risk, baseRisk: opt.risk });
        const k = keyOf(r.segs);
        if (k === defKey) { fam[v].push(0); continue; }
        if (!altIdx.has(k)) { alts.push(r.segs.map((s) => stepOf(s))); altIdx.set(k, alts.length); }
        fam[v].push(altIdx.get(k));
      }
    }
    out.profs[slug] = { best: best.segs.map((s) => stepOf(s, FILTERS.best)), trainer: trainer.segs.map((s) => stepOf(s, FILTERS.trainer)), gold, alts, fam };
    if (best.gaps.length || trainer.gaps.length) out.gaps[slug] = { best: best.gaps, trainer: trainer.gaps };
  }
  // prices + names for the gathering pages
  for (const id of EXTRA_IDS) {
    if (P[id] && P[id].price != null && !out.prices[id]) out.prices[id] = [Math.round(P[id].price), 'AH', P[id].listed ?? null, P[id].sales ?? null];
    if (itemInfo.has(id)) out.items[id] = itemInfo.get(id);
  }
  return out;
}

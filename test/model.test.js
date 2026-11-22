import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRecipes, compute, neededIds, pp } from '../src/model.js';

const reag = (id, count, name, vendorSellPrice = 1) => ({ id, count, name, quality: 1, vendorSellPrice });
// Two tiny tailoring recipes covering 1-300 so the route has no gaps.
const seemeta = {
  tailoring: {
    recipes: [
      { name: 'Low Shirt', spellId: 1, skill: { required: 1, trainerRequired: 1, yellow: 100, green: 150, grey: 200 }, source: { method: 'automatic', books: [] },
        reagents: [reag(2589, 2, 'Linen Cloth')], createdItem: { id: 900, name: 'Low Shirt', count: 1, quality: 1, vendorSellPrice: 5 } },
      { name: 'High Robe', spellId: 2, skill: { required: 150, trainerRequired: 150, yellow: 280, green: 300, grey: 320 }, source: { method: 'book', books: [{ id: 950, reputation: null }] },
        reagents: [reag(4306, 3, 'Silk Cloth')], createdItem: { id: 901, name: 'High Robe', count: 1, quality: 2, vendorSellPrice: 50 } }
    ]
  }
};

test('pp follows orange/yellow/green/grey', () => {
  const r = { learn: 10, y: 20, gr: 40 };
  assert.equal(pp(r, 5), 0);
  assert.equal(pp(r, 15), 1);
  assert.equal(pp(r, 30), 0.5);
  assert.equal(pp(r, 40), 0);
});

test('builds recipes, prices and a gap-free route', () => {
  const recipes = buildRecipes(seemeta, { src: { V: [2] }, learn: {} });
  assert.equal(recipes.tailoring.length, 2);
  assert.equal(recipes.tailoring[1].src, 'V');
  assert.deepEqual(neededIds(recipes).filter((i) => i >= 900 && i < 1000), [900, 901, 950]);
  const P = { 2589: { price: 40, sales: 1000 }, 4306: { price: 200, sales: 1000 }, 900: { price: 150, sales: 50 }, 901: { price: 900, sales: 2 } };
  const out = compute(recipes, P, {}, { minListed: 0 });
  const best = out.profs.tailoring.best;
  assert.equal(best[0][0], 1);
  assert.equal(best[best.length - 1][1], 300);
  for (let i = 1; i < best.length; i++) assert.equal(best[i][0], best[i - 1][1]);
  assert.deepEqual(out.prices[2589].slice(0, 2), [40, 'AH']);
  assert.equal(out.items[901][0], 'High Robe');
  // High Robe sells < 3/day, so it is valued at vendor price
  const robe = best.find((s) => s[2] === 'High Robe');
  assert.equal(robe[14], 'vendor');
});

test('filters ignore thin AH items and pick the better of AH and vendor', () => {
  const recipes = buildRecipes(seemeta, { src: { V: [2] }, learn: {} });
  const P = {
    2589: { price: 40, sales: 1000, listed: 500 },
    4306: { price: 200, sales: 1000, listed: 2 },   // thin: only 2 listed
    900: { price: 150, sales: 50, listed: 40 },
    901: { price: 9000, sales: 50, listed: 30 }
  };
  const out = compute(recipes, P, {}, { minSold: 3, minListed: 5, cut: 0.05 });
  const robe = out.profs.tailoring.best.find((s) => s[2] === 'High Robe');
  assert.equal(robe[18], 1, 'High Robe only works with thin Silk Cloth, so it is flagged');
  assert.equal(robe[13], Math.round(9000 * 0.95), 'AH sale after 5% cut');
  const out15 = compute(recipes, P, {}, { minSold: 3, minListed: 0, cut: 0.15 });
  const robe15 = out15.profs.tailoring.best.find((s) => s[2] === 'High Robe');
  assert.equal(robe15[18], 0);
  assert.equal(robe15[13], Math.round(9000 * 0.85), 'neutral AH cut');
  // vendor pays more than a cheap AH price
  const cheap = compute(recipes, { ...P, 900: { price: 4, sales: 50, listed: 40 } }, {}, {});
  const shirt = cheap.profs.tailoring.best.find((s) => s[2] === 'Low Shirt');
  assert.equal(shirt[14], 'vendor');
  assert.equal(shirt[13], 5);
  assert.ok(out.ignored >= 1);
});

test('recipe-source filter keeps disallowed sources out unless nothing else covers a level', () => {
  // a cheap vendor recipe competes with the trainer recipe at 150+
  const sm = JSON.parse(JSON.stringify(seemeta));
  sm.tailoring.recipes.push({ name: 'Cheap Drop Cloak', spellId: 3, skill: { required: 150, trainerRequired: 150, yellow: 290, green: 300, grey: 320 },
    source: { method: 'book', books: [{ id: 951, reputation: null }] },
    reagents: [reag(2589, 1, 'Linen Cloth')], createdItem: { id: 902, name: 'Cheap Drop Cloak', count: 1, quality: 2, vendorSellPrice: 200 } });
  const recipes = buildRecipes(sm, { src: { V: [2], D: [3] }, learn: {} });
  const P = { 2589: { price: 40, sales: 1000, listed: 500 }, 4306: { price: 200, sales: 1000, listed: 500 } };
  const BP = { 951: { med: 1000, qty: 3 } };
  const names = (o) => new Set(o.profs.tailoring.best.map((s) => s[2]));
  assert.ok(names(compute(recipes, P, BP, {})).has('Cheap Drop Cloak'), 'drops allowed by default');
  const noDrops = compute(recipes, P, BP, { src: 'TV' });
  assert.ok(!names(noDrops).has('Cheap Drop Cloak'), 'drops filtered out');
  assert.ok(names(noDrops).has('High Robe'), 'vendor recipe still used');
  // with neither vendor nor drops, 200-300 has only those two recipes: the route still has no holes
  const trainerOnly = compute(recipes, P, BP, { src: 'T' });
  const best = trainerOnly.profs.tailoring.best;
  assert.equal(best[best.length - 1][1], 300);
  // the pattern price cap applies to drops
  assert.ok(!names(compute(recipes, P, BP, { maxPattern: 500 })).has('Cheap Drop Cloak'), 'pattern above the cap');
});

test('mats that are cheaper to craft carry their recipe', () => {
  const sm = JSON.parse(JSON.stringify(seemeta));
  // Bolt (id 950x) made from 4 Linen; High Robe needs bolts instead of silk
  sm.tailoring.recipes.push({ name: 'Bolt', spellId: 4, skill: { required: 1, trainerRequired: 1, yellow: 25, green: 37, grey: 50 }, source: { method: 'automatic', books: [] },
    reagents: [reag(2589, 4, 'Linen Cloth')], createdItem: { id: 2996, name: 'Bolt', count: 1, quality: 1, vendorSellPrice: 10 } });
  sm.tailoring.recipes[1].reagents = [reag(2996, 3, 'Bolt')];
  const recipes = buildRecipes(sm, { src: { V: [2] }, learn: {} });
  const P = { 2589: { price: 40, sales: 1000, listed: 500 }, 2996: { price: 500, sales: 1000, listed: 500 } };
  const out = compute(recipes, P, {}, {});
  assert.deepEqual(out.prices[2996].slice(0, 2), [160, 'craft']);
  assert.deepEqual(out.crafts[2996].slice(0, 2), [1, [[2589, 4]]]);
  assert.ok(out.prices[2589]);
});

test('steps list alternative recipes, and excluded recipes are never used', () => {
  const recipes = buildRecipes(seemeta, { src: { V: [2] }, learn: {} });
  const P = { 2589: { price: 40, sales: 1000, listed: 500 }, 4306: { price: 200, sales: 1000, listed: 500 } };
  const out = compute(recipes, P, {}, {});
  const best = out.profs.tailoring.best;
  const robe = best.find((s) => s[2] === 'High Robe');
  assert.ok(robe, 'High Robe in the route');
  assert.equal(typeof robe[22], 'number', 'spell id on the step');
  assert.ok(Array.isArray(robe[23]), 'alternatives on the step');
  // skip the robe: it is gone from the route and the gold tips
  const ex = compute(recipes, P, {}, { exclude: [robe[22]] });
  assert.ok(!ex.profs.tailoring.best.some((s) => s[2] === 'High Robe'));
  assert.ok(!ex.profs.tailoring.gold.some((g) => g[0] === 'High Robe'));
});

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

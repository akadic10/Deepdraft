// SUPERSEDED 2026-10-21: the game's blueberry now comes from tools/voxel_assets/plants.py
// (_square_shrub, notched clumps shared by every bush). Kept for reference only.
// Hearthblock plant pilot (2026-10-20, doc 256): the blueberry bush in every state.
// Square leaf clumps stepped over three flared stems, using the bush's own season
// colours (leaf0 dark .. leaf2 light). Berries are a separate layer (picking
// removes only them) and every cell connects through faces down to the ground.
// Mature stays under 26 cells, young under 16; both within 1.5 blocks of centre.
import * as P from './proposal.mjs';

const { Vox } = P;
const parts = {};
const define = (name, fn) => { parts[name] = fn; };
const SEASONS = ['spring', 'summer', 'autumn', 'winter'];

function stems(v, young) {
  const h = young ? 4 : 7;
  v.box(-1, 1, 0, h, -1, 1, 'bark');
  v.box(-4, -2, 0, h - 2, 1, 3, 'bark'); v.box(-2, -1, h - 3, h - 2, 1, 2, 'bark');
  v.box(2, 4, 0, h - 1, -3, -1, 'bark'); v.box(1, 2, h - 2, h - 1, -2, -1, 'bark');
}

// A leaning limb that stays face-connected: each step moves one cell out and one up
// with a two-cell cross-section, so consecutive steps share faces.
function stair(v, x, y, z, dx, dz, n, w = 2) {
  for (let i = 0; i < n; i++) v.box(x + dx * i, x + dx * i + w, y + i, y + i + w, z + dz * i, z + dz * i + w, 'bark');
  return [x + dx * (n - 1), y + n - 1, z + dz * (n - 1)];
}

function bareTwigs(v, young) {             // winter: three leaning limbs with small forked twiglets
  const k = (n) => Math.max(2, Math.round(n * (young ? 0.6 : 1)));
  v.box(-1, 1, 0, k(5), -1, 1, 'bark');
  for (const [x, y, z, dx, dz, n] of [[-1, k(3), -1, -1, 0, k(8)], [0, k(4), -1, 1, 1, k(7)], [-1, k(5), 0, 0, -1, k(9)], [0, k(3), 0, 1, -1, k(5)]]) {
    const [ex, ey, ez] = stair(v, x, y, z, dx, dz, n);
    v.box(ex, ex + 1, ey + 2, ey + 4, ez, ez + 1, 'bark');                       // upturned tip
    v.box(ex + (dx || 1), ex + (dx || 1) + 1, ey + 1, ey + 2, ez + 1, ez + 2, 'bark');   // and a side twig
  }
}

function clumps(v, young) {
  if (young) {
    v.cut(-6, 1, 1, 9, -5, 3, 2, 'leaf0');
    v.cut(-1, 6, 2, 10, -3, 5, 2, 'leaf1');
    v.cut(-4, 4, 8, 13, -4, 4, 2, 'leaf1');
    v.cut(-2, 3, 12, 15, -2, 3, 1, 'leaf2');
    v.paint(-4, 4, 12, 13, -4, 4, 'leaf2');
    return;
  }
  v.cut(-11, 1, 2, 13, -8, 4, 3, 'leaf0');           // low clumps hide the stems
  v.cut(-2, 11, 3, 14, -5, 8, 3, 'leaf1');
  v.cut(-12, -5, 6, 15, 2, 9, 2, 'leaf0');
  v.cut(4, 12, 7, 15, -9, -2, 2, 'leaf2');
  v.cut(-7, 7, 11, 19, -7, 7, 3, 'leaf1');
  v.cut(-4, 5, 18, 23, -4, 5, 2, 'leaf2');
  v.paint(-7, 7, 18, 19, -7, 7, 'leaf2'); v.paint(-11, 1, 12, 13, -8, 4, 'leaf1');
  v.paint(-2, 11, 13, 14, -5, 8, 'leaf2');
}

const top = (v, x, z) => { for (let y = 40; y >= 0; y--) if (v.has(x, y, z)) return y; return -1; };

function blossoms(v) {                     // spring: cream flowers sitting on the top faces
  for (const [x, z] of [[-6, -3], [2, 0], [9, 4], [-9, -5], [8, -6], [-10, 6], [-2, 5]]) {
    const y = top(v, x, z) + 1;
    v.box(x, x + 2, y, y + 1, z, z + 2, 'blossom'); v.box(x, x + 1, y, y + 1, z, z + 1, 'blossom_centre');
  }
}

for (const season of SEASONS) {
  for (const young of [false, true]) {
    define(`blueberry/${young ? 'young' : 'mature'}/${season}`, v => {
      if (season === 'winter') { bareTwigs(v, young); return; }
      stems(v, young); clumps(v, young);
      if (season === 'spring' && !young) blossoms(v);
    });
  }
}

// Ripe berries (mature summer only): chunky clusters against real clump faces,
// one lighter cell on top; a separate layer so picking removes only the berries.
define('blueberry/fruit', v => {
  const base = new Vox(); stems(base, false); clumps(base, false);
  for (const [y, lane, axis, sign, c] of [[8, -2, 'x', -1, 'fruit0'], [10, 2, 'x', 1, 'fruit1'], [9, -4, 'z', -1, 'fruit2'],
    [11, 3, 'z', 1, 'fruit0'], [13, -6, 'x', 1, 'fruit1'], [12, 5, 'x', -1, 'fruit2'], [15, 0, 'z', -1, 'fruit0']]) {
    let edge = null;
    for (let a = -30; a <= 30; a++) {
      const hit = axis === 'x' ? base.has(a, y, lane) : base.has(lane, y, a);
      if (hit && (edge === null || (sign < 0 ? a < edge : a > edge))) edge = a;
    }
    if (edge === null) continue;
    const a0 = sign < 0 ? edge - 2 : edge + 1;
    if (axis === 'x') { v.box(a0, a0 + 2, y, y + 2, lane, lane + 2, c); v.box(a0, a0 + 1, y + 2, y + 3, lane, lane + 1, 'fruit1'); }
    else { v.box(lane, lane + 2, y, y + 2, a0, a0 + 2, c); v.box(lane, lane + 1, y + 2, y + 3, a0, a0 + 1, 'fruit1'); }
  }
});

export function build(name) { const v = new Vox(); parts[name](v); return v; }
export const NAMES = Object.keys(parts);

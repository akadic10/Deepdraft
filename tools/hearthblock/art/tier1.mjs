// Hearthblock Tier 1 · Axe-Hewn furniture for the game (2026-10-20, doc 256).
// Same vocabulary as proposal.mjs: 1:16 cells, [x0,x1) ranges, ground at Y0,
// X right, Z toward the front. Each model keeps the existing in-game frame and
// the contact bounds written above it. Split, chopped and notched with an axe:
// bark stays on, ends step back like axe cuts, joints are notches and lashings.
// The fence's posts, rails and gate are peeled, as built logs are (doc 278).
import { Vox, endRings, notchedLogBed } from './proposal.mjs';

export { notchedLogBed };

// ── Log bench: 32 x 16 x 16, seat at Y16, two-cell footprint (the sitting log) ────────────
// The owner's pick of three concepts (2026-11-11): one whole log lying on the ground, wedged at
// both ends so it cannot roll, a seat hewn flat along its top. Mostly bark, in ridges painted
// flush, with a lopped branch on its front shoulder; the hewn strip shows the heart down its
// middle, and both ends show their rings. The seat is level at Y16 over the middle, where the
// one dwarf sits (`test_hearthblock` keeps that, and the log solid from the ground to the seat).
const ROUND = [[0, 3], [1, 5], [2, 6], [3, 7], [4, 7], [5, 8], [6, 8], [7, 8], [8, 8], [9, 8], [10, 8], [11, 7], [12, 7], [13, 6], [14, 5], [15, 4]];   // a lying log's section: [layer, half width]
// Bark ridges along a lying log, painted flush: [x0, x1, y, z].
const ridges = (v, lines, role = 'bark_light') => { for (const [x0, x1, y, z] of lines) v.paint(x0, x1, y, y + 1, z, z + 1, role); };
export function logBench() {
  const v = new Vox();
  for (const [y, a] of ROUND) v.box(-16, 16, y, y + 1, -a, a, y < 2 ? 'bark_dark' : 'bark');     // the log
  for (const x of [-16, 15]) {                                   // both ends: the cut face, its rings, a bark rim
    v.paint(x, x + 1, 1, 15, -8, 8, 'wood_top');
    endRings(v, 'x', x, 8, -1, [2, 5]);
    for (const [y, a] of ROUND) { v.paint(x, x + 1, y, y + 1, -a, -a + 1, 'bark'); v.paint(x, x + 1, y, y + 1, a - 1, a, 'bark'); }
    v.paint(x, x + 1, 1, 2, -5, -3, 'bark'); v.paint(x, x + 1, 1, 2, 3, 5, 'bark');
  }
  // wedges driven under each flank at both ends, thick end out
  const GAP = [[0, 3], [1, 5], [2, 6], [3, 7]];
  for (const s of [1, -1]) for (const [y, a] of GAP) for (const [za, zb] of [[a, 8], [-8, -a]]) {
    const thick = s * 14, thin = s * (6 + 2 * y);
    v.box(Math.min(thick, thin), Math.max(thick, thin), y, y + 1, za, zb, 'riven');
    v.paint(s > 0 ? 13 : -14, s > 0 ? 14 : -13, y, y + 1, za, zb, 'wood_top');
  }
  v.paint(-12, -9, 1, 2, 7, 8, 'riven_dark'); v.paint(9, 11, 2, 3, 7, 8, 'riven_dark'); v.paint(8, 12, 1, 2, -8, -7, 'riven_dark');
  // the seat: hewn flat along the top, the heart showing down its middle
  v.paint(-14, 16, 15, 16, -4, 4, 'riven');
  v.paint(-14, 16, 15, 16, -4, -3, 'wood_top'); v.paint(-14, 16, 15, 16, 3, 4, 'wood_top');
  v.paint(-11, 12, 15, 16, -1, 1, 'grain'); v.paint(-6, 2, 15, 16, -2, -1, 'grain'); v.paint(3, 10, 15, 16, 1, 2, 'grain');
  v.paint(-10, -4, 15, 16, 0, 1, 'riven_dark'); v.paint(-2, 0, 15, 16, -1, 0, 'riven_dark'); v.paint(2, 9, 15, 16, 0, 1, 'riven_dark');
  v.paint(-8, 5, 14, 15, 4, 5, 'riven'); v.paint(-3, 11, 14, 15, -5, -4, 'riven');   // where the axe bit a step deeper
  bites(v, 15, [[-12, -3], [-11, -2], [-12, 2], [6, -3], [7, -2], [12, 2], [13, 3]]);
  v.box(9, 16, 15, 16, -1, 0, null); v.box(15, 16, 8, 15, -1, 0, null);              // the drying split, out of one end
  // a lopped branch on the front shoulder, cut level a cell below the seat
  v.box(8, 11, 11, 15, 5, 8, 'bark'); v.paint(8, 11, 14, 15, 5, 8, 'riven_dark'); v.paint(9, 10, 14, 15, 6, 7, 'pith');
  ridges(v, [[-15, -11, 13, 5], [-3, 6, 13, 5], [-5, 4, 12, 6], [12, 15, 12, 6], [-14, -9, 11, 6],
    [-4, 7, 9, 7], [1, 13, 7, 7], [-12, -1, 6, 7], [4, 11, 5, 7]]);
  ridges(v, [[-14, -6, 14, -5], [6, 13, 13, -6], [-14, -4, 12, -7], [-6, 8, 10, -8], [2, 12, 7, -8], [-12, -4, 5, -8]]);
  ridges(v, [[-2, 6, 10, 7], [-13, -6, 8, 7], [6, 14, 9, -8], [-10, -2, 8, -8]], 'bark_dark');
  return v;
}

// ── Log stool: 14 x 14 x 14, seat at Y14 (doc 301: the proposal's stool, its bark in ridges) ──
// The proposal's stool (proposal.mjs `stool`, which stored logs still replay) wore raised plates
// of lighter bark, which read as panels stuck on. Bark splits into upright ridges, so here they
// are painted flush, uneven in length, with a few dark furrows. Seat, rim, ring and split as before.
export function logStool() {
  const v = new Vox();
  v.cut(-7, 7, 0, 2, -7, 7, 3, 'bark_dark');      // root flare
  v.cut(-6, 6, 2, 12, -6, 6, 2, 'bark');
  for (const [x, y0, y1] of [[-3, 3, 11], [0, 2, 9], [2, 4, 12]]) { v.paint(x, x + 1, y0, y1, 5, 6, 'bark_light'); v.paint(x + 1, x + 2, y0, y1, -6, -5, 'bark_light'); }
  for (const [z, y0, y1] of [[-3, 2, 10], [0, 4, 12], [3, 3, 9]]) { v.paint(-6, -5, y0, y1, z, z + 1, 'bark_light'); v.paint(5, 6, y0, y1, z - 1, z, 'bark_light'); }
  v.paint(-1, 0, 2, 7, 5, 6, 'bark_dark'); v.paint(5, 6, 2, 8, 1, 2, 'bark_dark'); v.paint(-6, -5, 2, 6, -1, 0, 'bark_dark'); v.paint(1, 2, 2, 7, -6, -5, 'bark_dark');
  v.cut(-6, 6, 12, 14, -6, 6, 2, 'bark');         // bark rim around the seat
  v.cut(-5, 5, 13, 14, -5, 5, 2, 'wood_top');
  v.ring(-3, 2, 13, -3, 2, 'grain');              // one square growth ring, off centre
  v.box(-1, 0, 13, 14, -1, 0, 'pith');
  v.box(1, 5, 13, 14, 0, 1, null);                // drying split, carved
  v.box(5, 6, 10, 14, 0, 1, null);
  return v;
}

// ── Split logs and stumps (doc 301) ─────────────────────────────────────────────
// A half or a pole split from a log, lying along X, riven face up at `top`. `steps` are [layers,
// side inset, end chop] from the top down: its section is a D with the bark underneath, and each
// lower step is chopped shorter, as an axe leaves an end. The riven face keeps a rim of bark
// `wane` cells wide on each long edge; the end faces show end grain, with ring arcs round the pith.
function rivenX(v, x0, x1, z0, z1, top, steps, wane = 2) {
  let y = top;
  const zc = Math.floor((z0 + z1) / 2);
  for (const [h, inset, chop] of steps) {
    v.box(x0 + chop, x1 - chop, y - h, y, z0 + inset, z1 - inset, 'bark');
    for (const x of [x0 + chop, x1 - chop - 1]) {
      v.paint(x, x + 1, y - h, y, z0 + inset, z1 - inset, 'wood_top');
      for (const r of [3, 6]) {
        const ya = Math.max(top - 1 - r, y - h), yb = Math.min(top, y);
        if (ya < yb) { v.paint(x, x + 1, ya, yb, zc - r, zc - r + 1, 'grain'); v.paint(x, x + 1, ya, yb, zc + r, zc + r + 1, 'grain'); }
        if (top - 1 - r >= y - h && top - 1 - r < y) v.paint(x, x + 1, top - 1 - r, top - r, zc - r, zc + r + 1, 'grain');
      }
      if (top - 1 >= y - h) v.paint(x, x + 1, top - 1, top, zc, zc + 1, 'pith');
    }
    y -= h;
  }
  v.paint(x0, x1, top - 1, top, z0 + wane, z1 - wane, 'riven');
  return zc;
}
const HALF = [[2, 0, 0], [2, 1, 1], [2, 3, 2], [2, 6, 4]];      // half a log, 8 cells thick
const POLE = [[2, 0, 0], [2, 1, 1], [2, 3, 2]];                 // a split pole, 6 cells thick

// What a log split through its heart shows on its riven face, on layer y: pale sapwood inside the
// bark on both edges, a darker band of heartwood down the middle, and the pith as a broken line.
// A top drawn this way is never one flat colour (doc 64).
function heartX(v, y, x0, x1, z0, z1, wane = 2, sap = 2, band = 2) {
  const zc = Math.floor((z0 + z1) / 2);
  v.paint(x0, x1, y, y + 1, z0 + wane, z0 + wane + sap, 'wood_top');
  v.paint(x0, x1, y, y + 1, z1 - wane - sap, z1 - wane, 'wood_top');
  v.paint(x0 + 3, x1 - 4, y, y + 1, zc - band, zc + band, 'grain');
  v.paint(x0 + 9, x1 - 14, y, y + 1, zc - band - 1, zc - band, 'grain');       // the band swells and thins
  v.paint(x0 + 16, x1 - 7, y, y + 1, zc + band, zc + band + 1, 'grain');
  const long = x1 - x0;                                                           // the pith, broken unevenly
  for (const [a, b, dz] of [[0.10, 0.31, 0], [0.37, 0.45, band > 1 ? 1 : 0], [0.53, 0.79, 0], [0.85, 0.91, band > 1 ? -1 : 0]]) {
    v.paint(x0 + Math.round(a * long), x0 + Math.round(b * long), y, y + 1, zc + dz, zc + dz + 1, 'riven_dark');
  }
  return zc;
}
// Marks on a riven face at layer y: a knot trimmed flush, and the bites of an axe that ran on.
function knot(v, y, x, z) { v.paint(x - 1, x + 2, y, y + 1, z - 1, z + 2, 'riven_dark'); v.paint(x, x + 1, y, y + 1, z, z + 1, 'pith'); }
function bites(v, y, cells) { for (const [x, z] of cells) v.paint(x, x + 1, y, y + 1, z, z + 1, 'chop'); }

// A bark stump with its corners cut square (n) and its bark in upright ridges, painted flush.
// `flare` widens the root by that many cells.
function stump(v, x0, x1, z0, z1, top, n = 2, flare = 1) {
  v.box(x0 + n, x1 - n, 0, 2, z0 - flare, z1 + flare, 'bark_dark'); v.box(x0 - flare, x1 + flare, 0, 2, z0 + n, z1 - n, 'bark_dark');
  v.box(x0 + n, x1 - n, 2, top, z0, z1, 'bark'); v.box(x0, x1, 2, top, z0 + n, z1 - n, 'bark');
  const xm = Math.floor((x0 + x1) / 2), zm = Math.floor((z0 + z1) / 2);
  for (const [x, y0, y1, z] of [[xm - 1, 3, top - 1, z1 - 1], [xm + 1, 2, top - 2, z1 - 1], [xm, 3, top - 1, z0], [xm + 2, 2, top - 2, z0]]) v.paint(x, x + 1, y0, y1, z, z + 1, 'bark_light');
  v.paint(x0, x0 + 1, 3, top - 1, zm - 1, zm, 'bark_light'); v.paint(x1 - 1, x1, 2, top - 2, zm + 1, zm + 2, 'bark_light');
}
// The cut top of such a stump at layer y: a bark rim, the pale face, square growth rings, the pith.
function stumpTop(v, x0, x1, z0, z1, y, n, rings) {
  v.box(x0 + n, x1 - n, y, y + 1, z0, z1, 'bark'); v.box(x0, x1, y, y + 1, z0 + n, z1 - n, 'bark');
  v.paint(x0 + n, x1 - n, y, y + 1, z0 + 1, z1 - 1, 'wood_top'); v.paint(x0 + 1, x1 - 1, y, y + 1, z0 + n, z1 - n, 'wood_top');
  const xm = Math.floor((x0 + x1) / 2) - 1, zm = Math.floor((z0 + z1) / 2);
  for (const r of rings) v.ring(xm - r, xm + r + 1, y, zm - r, zm + r + 1, 'grain');
  v.paint(xm, xm + 1, y, y + 1, zm, zm + 1, 'pith');
  return [xm, zm];
}
// A bark log lying along Z or X, its ends showing their rings.
function logZ(v, x0, x1, y0, y1, z0, z1, role = 'bark') {
  v.cutZ(x0, x1, y0, y1, z0, z1, 1, role);
  for (const z of [z0, z1 - 1]) { v.paint(x0, x1, y0, y1, z, z + 1, 'wood_top'); endRings(v, 'z', z, Math.floor((x0 + x1) / 2), Math.floor((y0 + y1) / 2), [1]); }
}
function logX(v, x0, x1, y0, y1, z0, z1, role = 'bark') {
  v.cutX(x0, x1, y0, y1, z0, z1, 1, role);
  for (const x of [x0, x1 - 1]) { v.paint(x, x + 1, y0, y1, z0, z1, 'wood_top'); endRings(v, 'x', x, Math.floor((y0 + y1) / 2), Math.floor((z0 + z1) / 2), [1]); }
}

// ── Dining table: 46 x 24 x 46, top at Y24 (doc 301, B, four stumps) ──────────────
// The owner's pick of three concepts (2026-11-10): legs you can see. A short stump at each corner,
// a bearer log across each pair, and three split poles laid over the bearers, riven face up. The
// four stools sit mid-side, between the legs. The table's collision and seated-leg boxes follow
// the stumps, the bearers and the top (data/furniture/dining_table.json).
function tableLegs(v) {
  for (const x0 of [-23, 15]) for (const z0 of [-23, 15]) stump(v, x0, x0 + 8, z0, z0 + 8, 12, 2, 0);
  for (const x0 of [-22, 16]) logZ(v, x0, x0 + 6, 12, 18, -23, 23);
}
export function splitSlabTable() {
  const v = new Vox();
  tableLegs(v);
  for (const [z0, z1, x0, x1] of [[-23, -9, -23, 23], [-7, 7, -22, 21], [9, 23, -23, 22]]) {
    rivenX(v, x0, x1, z0, z1, 24, POLE, 2);
    heartX(v, 23, x0, x1, z0, z1, 2, 1, 1);
  }
  knot(v, 23, 12, -13); knot(v, 23, -10, 18); knot(v, 23, -3, 3);
  bites(v, 23, [[-20, -19], [-19, -18], [-18, -17], [17, 3], [18, 4], [19, 5]]);
  v.box(10, 23, 23, 24, 14, 15, null); v.box(19, 23, 19, 24, 14, 15, null);    // a drying split from one end
  return v;
}

// ── Board-game table: the dining table's stumps and bearers under two riven halves ──
// 46 x 25 x 46. Three poles leave no room for a board, so the game table keeps a top of two wide
// halves. The board is scraped clean and scratched into it in knot-dark lines; six 4 x 4 counters
// rest on solid wood.
export function gameTable() {
  const v = new Vox();
  tableLegs(v);
  rivenX(v, -23, 23, -23, -1, 24, HALF, 1); heartX(v, 23, -23, 23, -23, -1, 1);
  rivenX(v, -22, 22, 1, 23, 24, HALF, 1); heartX(v, 23, -22, 22, 1, 23, 1);
  v.paint(-11, 11, 23, 24, -11, 11, 'riven');                                  // the board, scraped clean
  for (const g of [-11, -4, 3, 10]) {
    v.paint(-11, 11, 23, 24, g, g + 1, 'pith');
    v.paint(g, g + 1, 23, 24, -11, 11, 'pith');
  }
  for (const [x, z, c] of [[-9, -9, 'red'], [-2, -9, 'teal'], [5, -9, 'red'], [-9, 5, 'teal'], [-2, 5, 'red'], [5, 5, 'teal']]) {
    v.box(x, x + 4, 24, 25, z, z + 4, c);
  }
  return v;
}

// ── Crude workbench: 46 x 16 x 46, top at Y16 (doc 301, A, the rooted stump) ─────────
// The owner's pick of three concepts (2026-11-10). Still one great stump, as its recipe has it
// ("Every hall began as a stump and a dwarf with an axe"), but the stump of a felled tree:
// buttress roots running out over its ground, bark in upright ridges, the felling cut and its
// splintered hinge along one side, rings off centre, a drying crack. Goods lie on its top within
// `crafting_surface_radius` of its middle, so that much stays flat.
// A square growth ring painted on a cut face (never set: it must not add cells past an outline).
function ringOn(v, y, cx, cz, r, role = 'grain') {
  v.paint(cx - r, cx + r + 1, y, y + 1, cz - r, cz - r + 1, role); v.paint(cx - r, cx + r + 1, y, y + 1, cz + r, cz + r + 1, role);
  v.paint(cx - r, cx - r + 1, y, y + 1, cz - r, cz + r + 1, role); v.paint(cx + r, cx + r + 1, y, y + 1, cz - r, cz + r + 1, role);
}
export function workbench() {
  const v = new Vox();
  const root = (boxes) => { for (const [x0, x1, h, z0, z1] of boxes) { v.box(x0, x1, 0, h, z0, z1, 'bark'); v.paint(x0, x1, 0, 2, z0, z1, 'bark_dark'); } };
  root([[15, 20, 9, -5, 2], [20, 22, 5, -4, 1], [22, 23, 3, -3, 0]]);                 // toward +X
  root([[-20, -15, 8, 2, 8], [-22, -20, 5, 3, 7], [-23, -22, 2, 4, 6]]);              // -X
  root([[-8, -2, 9, 15, 20], [-7, -3, 5, 20, 22], [-6, -4, 3, 22, 23]]);              // +Z
  root([[3, 10, 8, -20, -15], [4, 9, 5, -22, -20], [5, 8, 2, -23, -22]]);             // -Z
  root([[12, 18, 6, -18, -12], [16, 21, 3, -21, -16]]);                               // between, two smaller
  root([[-18, -12, 6, 12, 18], [-21, -16, 3, 16, 21]]);
  for (const [x0, x1, z0, z1] of [[-12, 12, -17, 17], [-17, 17, -12, 12], [-15, 15, -15, 15]]) {   // the trunk, its corners in two steps
    v.box(x0, x1, 0, 15, z0, z1, 'bark'); v.paint(x0, x1, 0, 2, z0, z1, 'bark_dark');
  }
  for (const [a, y0, y1, w] of [[-10, 4, 12, 1], [-7, 2, 8, 1], [-3, 5, 13, 2], [2, 2, 9, 1], [6, 3, 12, 1], [9, 6, 13, 1]]) {   // bark ridges
    v.paint(a, a + w, y0, y1, 16, 17, 'bark_light'); v.paint(-a - w, -a, y0, y1, -17, -16, 'bark_light');
    v.paint(-17, -16, y0, y1, -a - w, -a, 'bark_light'); v.paint(16, 17, y0, y1, a, a + w, 'bark_light');
  }
  for (const [x0, x1, z0, z1] of [[-12, 12, -17, 17], [-17, 17, -12, 12], [-15, 15, -15, 15]]) v.box(x0, x1, 15, 16, z0, z1, 'bark');   // the cut top, in a bark rim
  for (const [x0, x1, z0, z1] of [[-11, 11, -16, 16], [-16, 16, -11, 11], [-14, 14, -14, 14]]) v.paint(x0, x1, 15, 16, z0, z1, 'wood_top');
  for (const r of [3, 7, 11, 15]) ringOn(v, 15, -3, -2, r);
  v.paint(-3, -2, 15, 16, -2, -1, 'pith');
  v.box(-11, 9, 12, 16, 13, 17, null); v.paint(-11, 9, 11, 12, 13, 17, 'chop');       // the felling cut, along one side
  v.paint(-11, 9, 12, 16, 12, 13, 'riven');                                           // its back, torn wood
  for (const x of [-9, -6, -5, -1, 3, 4, 7]) v.box(x, x + 1, 15, 16, 12, 13, null);   // the hinge, splintered
  for (const x of [-10, -3, 1, 6]) v.box(x, x + 1, 12, 14, 13, 14, 'riven');          // splinters left standing in the cut
  v.box(-2, 17, 15, 16, -2, -1, null); v.box(16, 17, 8, 16, -2, -1, null);            // the drying crack
  bites(v, 15, [[-12, -9], [-11, -8], [-10, -7], [8, -11], [9, -10], [10, 5], [11, 6], [-9, 6], [-8, 7]]);
  for (const [x, z, long = 1] of [[-13, 19, 2], [-10, 21], [10, 18, 2], [12, 20], [14, 17], [1, 21, 2]]) v.box(x, x + long, 0, 1, z, z + 1, 'wood_top');   // chips
  return v;
}

// ── Log doors: leaf_left spans x0..x1 at Y0..62, Z -7..7; hinge on -X ─────────
// Vertical split slabs, riven on both faces with bark edges, pinned to two
// battens per face with dark pegs; rope lashings on the hinge, a pull loop opposite.
export function doorLeaf(x0, x1, hinge = -1) {
  const v = new Vox();
  const tops = [62, 60, 61, 59, 62, 60, 61, 59];
  for (let i = 0, x = x0; x < x1; i++, x += 8) {
    const top = tops[i % tops.length];
    v.cut(x, x + 8, 0, top - 2, -4, 4, 2, 'bark');
    v.cut(x + 1, x + 7, top - 2, top, -3, 3, 2, 'bark');                 // chopped top, stepped in
    v.paint(x, x + 8, top - 3, top - 2, -4, 4, 'wood_top'); v.paint(x + 1, x + 7, top - 1, top, -3, 3, 'wood_top');
    v.paint(x + 2, x + 6, top - 1, top, -1, 1, 'pith');
    v.paint(x + 1, x + 7, 0, top - 3, 3, 4, 'riven'); v.paint(x + 1, x + 7, 0, top - 3, -4, -3, 'riven');
    v.paint(x + 3, x + 4, 6 + (i * 7) % 11, 30 + (i * 5) % 9, 3, 4, 'riven_dark');
    v.paint(x + 5, x + 6, 34 - (i * 3) % 7, 52, -4, -3, 'riven_dark');
  }
  for (const y of [10, 46]) {
    for (const [z0, z1] of [[4, 7], [-7, -4]]) {
      v.cutX(x0, x1, y, y + 4, z0, z1, 1, 'wood_dark');
      for (let x = x0 + 3; x < x1; x += 8) v.box(x, x + 2, y + 1, y + 3, z1 > 0 ? z1 - 1 : z0, z1 > 0 ? z1 : z0 + 1, 'bark_dark');
    }
    const hx = hinge < 0 ? x0 : x1 - 3;                                    // rope lashed round the hinge end
    v.box(hx, hx + 3, y - 1, y + 5, -7, 7, 'rope'); v.paint(hx, hx + 3, y + 1, y + 2, -7, 7, 'rope_dark'); v.paint(hx, hx + 3, y + 3, y + 4, -7, 7, 'rope_dark');
  }
  const px = hinge < 0 ? x1 - 6 : x0 + 3;                                  // pull loop, both faces
  for (const [z0, z1] of [[4, 7], [-7, -4]]) {
    v.box(px, px + 3, 26, 27, z0, z1, 'rope'); v.box(px, px + 3, 33, 34, z0, z1, 'rope');
    v.box(px, px + 1, 27, 33, z1 > 0 ? 6 : -7, z1 > 0 ? 7 : -6, 'rope'); v.box(px + 2, px + 3, 27, 33, z1 > 0 ? 6 : -7, z1 > 0 ? 7 : -6, 'rope_dark');
  }
  return v;
}

// ── Fence post: inside -3..3 x 0..20 x -3..3, centred in its tile ────────────
// A peeled 6 x 6 pole, drawn to be seen from the play camera (the owner's pick of three,
// 2026-11-11): its top chopped in two steps, its foot dark three cells up where it stands in the
// earth, a knot three cells across on two faces and a drying check that runs out of the top. Its
// faces stand 3 cells out up to Y17, so the rails and the gate's hinge meet it where they did.
// The foot of a pole standing in the ground, darkened by the earth.
function foot(v, x0, x1, z0, z1, high = 3) {
  v.paint(x0, x1, 0, high, z0, z1, 'bark'); v.paint(x0, x1, 0, 1, z0, z1, 'bark_dark');
}
// A knot trimmed flush on a peeled face: three cells across, uneven, with a dark eye (a square read
// as a plaque and a plus as a sign).
function knotX(v, x, y, z) {
  v.paint(x, x + 1, y + 1, y + 2, z, z + 3, 'pith'); v.paint(x, x + 1, y, y + 1, z + 1, z + 2, 'pith'); v.paint(x, x + 1, y + 2, y + 3, z + 1, z + 3, 'pith');
  v.paint(x, x + 1, y + 1, y + 2, z + 1, z + 2, 'bark');
}
function knotZ(v, x, y, z) {
  v.paint(x, x + 3, y + 1, y + 2, z, z + 1, 'pith'); v.paint(x + 1, x + 2, y, y + 1, z, z + 1, 'pith'); v.paint(x + 1, x + 3, y + 2, y + 3, z, z + 1, 'pith');
  v.paint(x + 1, x + 2, y + 1, y + 2, z, z + 1, 'bark');
}
export function fencePost() {
  const v = new Vox();
  v.cut(-3, 3, 0, 17, -3, 3, 1, 'riven_dark');
  foot(v, -3, 3, -3, 3); v.paint(-3, 0, 3, 4, -3, 3, 'bark');
  v.paint(-3, 3, 16, 17, -3, 3, 'wood_top');                             // the shoulder the axe left
  v.box(-2, 2, 17, 20, -2, 2, 'riven');                                  // the top, chopped in two levels
  v.box(-2, 2, 19, 20, 0, 2, null);
  v.paint(-2, 2, 19, 20, -2, 0, 'wood_top'); v.paint(-2, 2, 18, 19, 0, 2, 'wood_top');
  v.paint(-1, 1, 19, 20, -1, 0, 'grain'); v.paint(-1, 1, 18, 19, 0, 1, 'grain'); v.paint(-1, 0, 19, 20, -1, 0, 'pith');
  knotX(v, 2, 9, -2); knotZ(v, -1, 5, -3);
  v.box(0, 1, 8, 17, 1, 3, null); v.box(-1, 0, 4, 9, 2, 3, null);        // the check, down the front
  v.box(-3, -2, 8, 15, -1, 0, null);                                     // and a shorter one behind
  return v;
}

// ── Fence rails: inside -8..8 x 4..17 x -2..2, rows at Y4 and Y13 ─────────────
// Two peeled poles split in two, riven face up, each lashed to its posts with two turns of rope.
// A peeled pole split in two, 4 x 4, its riven face up: pale wood with the heart line down it,
// dark and broken. (A darker band between the lashings read as a slot cut in the rail.)
function splitRail(v, x0, x1, y0, pith = []) {
  v.box(x0, x1, y0 + 1, y0 + 4, -2, 2, 'riven_dark');
  v.box(x0, x1, y0, y0 + 1, -1, 1, 'riven_dark');
  v.paint(x0, x1, y0 + 3, y0 + 4, -2, 2, 'wood_top');
  for (const [xa, xb, z] of pith) v.paint(xa, xb, y0 + 3, y0 + 4, z, z + 1, 'pith');
}
export function fenceRails() {
  const v = new Vox();
  for (const [y0, pith] of [[4, [[-3, 1, -1], [1, 3, 0]]], [13, [[-3, -1, 0], [-1, 3, -1]]]]) {
    splitRail(v, -8, 8, y0, pith);
    for (const [light, dark] of [[-5, -4], [4, 3]]) {                    // lashed where it meets each post: two turns of rope
      v.box(light, light + 1, y0, y0 + 4, -2, 2, 'rope');
      v.box(dark, dark + 1, y0, y0 + 4, -2, 2, 'rope_dark');
    }
  }
  return v;
}

// ── Gate leaf: inside -13..12 x 3..18 x -2..3; hinge stile on -X at the post's face ──
// Peeled stiles with chopped tops stepped in, the hinge stile the taller; two split rails at the
// fence's heights; one brace, a split pole with its riven face out, from the hinge's foot to the
// latch's head, pegged at both ends. Rope lashes the hinge stile and loops the latch, and a
// cell's gap at the latch shows the leaf swings free.
export function gateLeaf() {
  const v = new Vox();
  for (const [x0, top] of [[-13, 18], [9, 17]]) {                        // stiles; the hinge stile stands taller
    v.box(x0, x0 + 3, 3, top - 2, -2, 2, 'riven_dark');
    v.box(x0, x0 + 3, top - 2, top, -1, 1, 'riven');                     // chopped tops, stepped in
    v.paint(x0, x0 + 3, top - 3, top - 2, -2, 2, 'wood_top'); v.paint(x0, x0 + 3, top - 1, top, -1, 1, 'wood_top');
  }
  splitRail(v, -10, 9, 4, [[-7, -3, 0], [0, 2, -1], [4, 7, 0]]);
  splitRail(v, -10, 9, 13, [[-8, -6, -1], [-3, 2, 0], [5, 8, -1]]);
  for (let i = 0; i < 19; i++) {                                         // the brace: a split pole, riven face out
    const y = 5 + Math.floor(i * 10 / 18);
    v.box(-10 + i, -9 + i, y, y + 3, 2, 3, 'riven');
    v.paint(-10 + i, -9 + i, y + 1, y + 2, 2, 3, 'grain');
  }
  v.paint(-9, -8, 6, 7, 2, 3, 'bark_dark'); v.paint(7, 8, 15, 16, 2, 3, 'bark_dark');   // pegged at both ends
  for (const y0 of [4, 13]) {                                            // rope at the hinge
    v.paint(-13, -10, y0, y0 + 4, -2, 2, 'rope');
    v.paint(-13, -10, y0 + 1, y0 + 2, -2, 2, 'rope_dark'); v.paint(-13, -10, y0 + 3, y0 + 4, -2, 2, 'rope_dark');
  }
  v.paint(9, 12, 9, 12, -2, 2, 'rope'); v.paint(9, 12, 10, 11, -2, 2, 'rope_dark');   // the latch loop
  v.box(9, 12, 9, 12, 2, 3, 'rope'); v.paint(9, 12, 10, 11, 2, 3, 'rope_dark');
  return v;
}

// ── Drying rack: inside -16..16 x 0..31 x -5..5, centred on its 2 x 1 footprint (doc 289) ──
// Two forked bark posts on root flares hold a peeled pole in their forks, lashed there with
// rope. The rack stands empty: its fish are a part of their own (dryingRackFish), shown only
// while a batch dries, laid over the rack at the same origin.
export function dryingRack() {
  const v = new Vox();
  for (const x0 of [-16, 12]) {
    const out = x0 < 0 ? x0 : x0 + 3;                             // the post's outer column
    v.cut(x0 < 0 ? x0 : x0 - 1, x0 < 0 ? x0 + 5 : x0 + 4, 0, 2, -3, 3, 1, 'bark_dark');   // the root flare
    v.cut(x0, x0 + 4, 2, 22, -2, 2, 1, 'bark');                   // the post
    v.cut(x0, x0 + 4, 22, 24, -3, 3, 1, 'bark');                  // the crotch, widening into the fork
    for (const z0 of [-4, 2]) v.box(x0, x0 + 4, 24, 31, z0, z0 + 2, 'bark');   // the prongs, either side of the pole
    v.paint(x0, x0 + 4, 30, 31, -4, 4, 'wood_top');               // chopped ends
    v.paint(x0 + 1, x0 + 2, 6, 15, 1, 2, 'bark_light'); v.paint(x0 + 2, x0 + 3, 11, 19, -2, -1, 'bark_light');   // bark ridges
    v.paint(out, out + 1, 4, 9, -1, 0, 'bark_light');
  }
  v.cutX(-16, 16, 24, 28, -2, 2, 1, 'riven_dark');                // the peeled pole, lying in the forks
  v.paint(-16, 16, 27, 28, -2, 2, 'riven');
  for (const x of [-16, 15]) v.paint(x, x + 1, 24, 28, -2, 2, 'wood_top');   // its chopped ends
  for (const x0 of [-16, 12]) {                                   // rope lashed round each fork
    v.box(x0, x0 + 4, 25, 27, -5, 5, 'rope'); v.paint(x0, x0 + 4, 25, 26, -5, 5, 'rope_dark');
  }
  return v;
}

// ── Drying rack's fish (parts/drying_rack_fish), in the rack's own coordinates ──────────
// Two dried fish hang head down from cords looped round the pole, as many as one batch dries
// (the dried fish recipe hangs two; `test_hearthblock` keeps the model and the recipe in step):
// the chunky fish (big head, bead eye, deep body, fan tail) in coppery browns, redder than any
// wood, the belly split to show the dried flesh. Each loop rings the pole (y 24..28, z -2..2) one
// cell clear of it, so the part never shares a cell with the rack it is laid over.
export function dryingRackFish() {
  const v = new Vox();
  for (const [x0, cord] of [[-8, 1], [2, 3]]) {
    const b = 12 - cord;                                          // the mouth's row; the fan's top row is b + 11
    for (const [l0, l1, d0, d1] of [[0, 2, 2, 4], [2, 4, 1, 5], [4, 7, 0, 6], [7, 9, 1, 5], [9, 10, 2, 4], [10, 11, 1, 5], [11, 12, 0, 6]]) {
      v.box(x0 + d0, x0 + d1, b + l0, b + l1, -1, 1, l0 >= 10 ? 'dry_tail' : 'dry_skin');   // head down, body, fan tail
    }
    v.paint(x0 + 4, x0 + 6, b + 2, b + 9, -1, 1, 'dry_back');     // the dark back
    v.paint(x0, x0 + 2, b + 2, b + 9, -1, 1, 'dry_flesh');        // split along the belly: the dried flesh
    v.paint(x0 + 1, x0 + 5, b + 4, b + 5, -1, 1, 'dry_back');     // the gill's edge
    v.paint(x0 + 3, x0 + 4, b + 2, b + 3, -1, 1, 'dry_eye');      // the bead eye
    v.paint(x0 + 2, x0 + 4, b + 9, b + 10, -1, 1, 'rope');        // tied at the wrist
    v.box(x0 + 3, x0 + 4, b + 12, 24, 0, 1, 'rope');              // the cord up to the pole,
    v.box(x0 + 3, x0 + 4, 23, 24, -2, 2, 'rope'); v.box(x0 + 3, x0 + 4, 28, 29, -2, 2, 'rope');   // looped round it
    v.box(x0 + 3, x0 + 4, 24, 28, -3, -2, 'rope'); v.box(x0 + 3, x0 + 4, 24, 28, 2, 3, 'rope');
  }
  return v;
}

// ── Carpenter's bench: 3 x 1, inside -24..24 x 0..18 x -8..8, top level at Y18 (doc 293; doc 301, B) ──
// The chopping block, the owner's pick of three concepts (2026-11-10). Half of a great log, round
// side down and hewn flat on top, peeled as built logs and fences are (doc 278). One end is let
// into a stump with its bark on, level with the slab: the block the Carpenter chops on, with the
// scars to show it. The other end stands on two round legs with a rail between them, and one
// stretcher runs back to the block. The slab's top is a split log's own face; the legs darken
// toward the ground; chips lie where the work is done. The top stays level along its length.
function peeledLeg(v, x0, z0, w, top) {
  v.cut(x0, x0 + w, 0, top, z0, z0 + w, 1, 'riven_dark');
  v.paint(x0, x0 + w, 0, 4, z0, z0 + w, 'pith'); v.paint(x0, x0 + w, 0, 2, z0, z0 + w, 'bark_light'); v.paint(x0, x0 + w, 0, 1, z0, z0 + w, 'bark');
}
function peeledSlab(v, x0, x1, top) {
  v.box(x0, x1, top - 3, top, -8, 8, 'riven_dark');                      // the slab, round side down
  v.box(x0, x1, top - 5, top - 3, -7, 7, 'riven_dark');
  v.box(x0, x1, top - 6, top - 5, -5, 5, 'riven_dark');
  v.paint(x0, x1, top - 1, top, -8, 8, 'riven');                          // hewn flat on top
  for (const x of [x0, x1 - 1]) {                                          // the end grain
    v.paint(x, x + 1, top - 6, top, -8, 8, 'wood_top');
    v.paint(x, x + 1, top - 4, top - 3, -4, 4, 'grain'); v.paint(x, x + 1, top - 2, top - 1, -6, 6, 'grain');
    v.paint(x, x + 1, top - 5, top - 4, -1, 1, 'pith');
  }
}
export function carpenterBench() {
  const v = new Vox();
  stump(v, -24, -8, -8, 8, 17, 3, 0);                                      // the chopping block
  const [xm, zm] = stumpTop(v, -24, -8, -8, 8, 17, 3, [2, 5]);
  for (const z0 of [-8, 3]) peeledLeg(v, 16, z0, 5, 12);                   // two round legs at the other end
  v.paint(20, 21, 6, 9, -6, -5, 'pith'); v.box(17, 18, 5, 11, 7, 8, null); // a knot, a drying check
  v.box(17, 20, 3, 6, -3, 3, 'riven_dark');                                // the end rail
  v.box(-8, 17, 5, 8, -1, 2, 'riven_dark'); v.paint(3, 4, 6, 8, 1, 2, 'pith');   // one stretcher back to the block
  peeledSlab(v, -11, 24, 18);
  v.paint(-12, -11, 12, 18, -8, 8, 'chop');                                // the notch it sits in
  heartX(v, 17, -10, 24, -8, 8, 0, 2, 2);
  knot(v, 17, 9, -5); knot(v, 17, 19, 4);
  bites(v, 17, [[-6, -4], [-5, -3], [-4, -2], [-3, 3], [-2, 4]]);
  bites(v, 17, [[xm - 4, zm - 4], [xm - 3, zm - 3], [xm - 2, zm - 2], [xm + 3, zm + 3], [xm + 4, zm + 4], [xm - 5, zm + 3], [xm - 4, zm + 4]]);   // axe scars on the block
  v.box(xm - 1, xm + 4, 17, 18, zm - 5, zm - 4, null); v.paint(xm - 1, xm + 4, 16, 17, zm - 5, zm - 4, 'chop');   // one cut deep
  v.box(xm + 1, -8, 17, 18, zm, zm + 1, null); v.box(-9, -8, 12, 18, zm, zm + 1, null);   // the block's drying split
  for (const [x, z, long = 1, role = 'wood_top'] of [[-7, 6, 2], [-4, 7], [-3, 5, 2], [0, 7, 2], [1, 4], [2, 6], [-1, 3, 2, 'riven'], [-6, 4, 1, 'riven'], [5, 7], [-5, -7, 2], [-2, -6]]) {
    v.box(x, x + long, 0, 1, z, z + 1, role);                              // chips on the ground
  }
  return v;
}

// ── Worked stone (the owner's pick, 2026-11-10, doc 301) ────────────────────────────
// Stone furniture is drawn as wood is. A log has bark outside and a pale cut face inside a bark
// rim; a stone has a weathered skin outside (stone_skin, its lit ledges stone_skin_top, its feet
// and undersides stone_skin_dark) and fresh stone (stone_fresh) where it was split or knocked,
// one cell inside a ledge of skin. Marks are cut in, never stuck on. Corners are cut square:
// the diamond that `cut` clips gives one-cell stairs, which read as ribbing on a stone.

// A stone box with its four upright corners cut away n x n.
function stoneBlock(v, x0, x1, y0, y1, z0, z1, n, role = 'stone_skin') {
  v.box(x0 + n, x1 - n, y0, y1, z0, z1, role);
  v.box(x0, x1, y0, y1, z0 + n, z1 - n, role);
}

// One stone with a worked face on top. With `under`, its lowest two layers are drawn in that
// many cells and the stone hangs over them, dark beneath; without, it stands on a dark foot.
// The top layer is fresh and drawn in one cell, so a lit ledge of skin rims the fresh face.
function workedStone(v, x0, x1, y0, y1, z0, z1, n, under = 0) {
  if (under > 0) {
    stoneBlock(v, x0 + under, x1 - under, y0, y0 + 1, z0 + under, z1 - under, n, 'stone_skin_dark');
    stoneBlock(v, x0 + under, x1 - under, y0 + 1, y0 + 2, z0 + under, z1 - under, n);
    stoneBlock(v, x0, x1, y0 + 2, y0 + 3, z0, z1, n, 'stone_skin_dark');
    stoneBlock(v, x0, x1, y0 + 3, y1 - 2, z0, z1, n);
  } else {
    stoneBlock(v, x0, x1, y0, y0 + 2, z0, z1, n, 'stone_skin_dark');
    stoneBlock(v, x0, x1, y0 + 2, y1 - 2, z0, z1, n);
  }
  stoneBlock(v, x0, x1, y1 - 2, y1 - 1, z0, z1, n, 'stone_skin_top');
  stoneBlock(v, x0 + 1, x1 - 1, y1 - 1, y1, z0 + 1, z1 - 1, n, 'stone_fresh');
}

// Knock a piece away: the scar it leaves, on every side of the hole, is fresh stone.
function knockOff(v, x0, x1, y0, y1, z0, z1) {
  v.box(x0, x1, y0, y1, z0, z1, null);
  v.paint(x0 - 1, x0, y0, y1, z0, z1, 'stone_fresh'); v.paint(x1, x1 + 1, y0, y1, z0, z1, 'stone_fresh');
  v.paint(x0, x1, y0 - 1, y0, z0, z1, 'stone_fresh'); v.paint(x0, x1, y1, y1 + 1, z0, z1, 'stone_fresh');
  v.paint(x0, x1, y0, y1, z0 - 1, z0, 'stone_fresh'); v.paint(x0, x1, y0, y1, z1, z1 + 1, 'stone_fresh');
}

// A short, stout bark stump with its root flare, 10 across, its bark in ridges.
function stoutStump(v, x0, top) {
  v.box(x0 + 2, x0 + 8, 0, 2, -6, 6, 'bark_dark'); v.box(x0 - 1, x0 + 11, 0, 2, -3, 3, 'bark_dark');
  v.box(x0 + 2, x0 + 8, 2, top, -5, 5, 'bark'); v.box(x0, x0 + 10, 2, top, -3, 3, 'bark');
  for (const [x, y0, y1, z] of [[x0 + 3, 3, top - 1, 4], [x0 + 6, 2, top - 2, 4], [x0 + 4, 3, top - 1, -5], [x0 + 7, 2, top - 2, -5]]) {
    v.paint(x, x + 1, y0, y1, z, z + 1, 'bark_light');
  }
  v.paint(x0, x0 + 1, 3, top - 1, -1, 0, 'bark_light'); v.paint(x0 + 9, x0 + 10, 2, top - 2, 1, 2, 'bark_light');
}

// ── Mason's bench: 3 x 1, inside -24..24 x 0..15 x -8..8, top at Y15 (doc 293; doc 301, A) ──
// The split slab on two log stumps, built as a stone: a slab eight cells thick, split from a
// bigger stone and never dressed, on two short stout stumps. Its two ends lie out of line with
// each other. The top is a fresh cleft inside a ledge of weathered skin, a cell lower along the
// back where the cleft stepped, with one end left unworked, one corner broken away in two steps,
// a crack in from the front, peck marks where the maul's point strikes, and the spalls swept to
// one foot. The top stays level enough for a Rough stone to lie anywhere along it.
export function masonBench() {
  const v = new Vox();
  stoutStump(v, -19, 7); stoutStump(v, 9, 7);
  workedStone(v, -24, 4, 7, 15, -8, 6, 3, 2);                           // the slab: its left end sits back,
  workedStone(v, -2, 24, 7, 15, -6, 8, 3, 2);                           // its right end forward
  knockOff(v, -19, -9, 14, 15, -7, -4); knockOff(v, -9, -3, 14, 15, -7, -5);   // the cleft's lower level, along the back
  v.box(20, 24, 14, 15, -6, 8, null); v.box(18, 20, 14, 15, 3, 8, null);       // one end left as it was, a cell lower
  knockOff(v, -24, -20, 12, 15, 1, 6); knockOff(v, -24, -22, 9, 12, 3, 6);     // a corner broken away, in two steps
  v.box(12, 13, 12, 15, 1, 8, null); v.box(11, 12, 12, 15, -4, 2, null);       // a crack in from the front edge,
  v.paint(12, 13, 11, 12, 1, 8, 'stone_cleft'); v.paint(11, 12, 11, 12, -4, 2, 'stone_cleft');   // its floor dark
  for (const [x, z] of [[-5, -1], [-3, 1], [-4, 3], [-1, 0], [0, 2]]) {        // peck marks
    v.box(x, x + 1, 14, 15, z, z + 1, null); v.paint(x, x + 1, 13, 14, z, z + 1, 'stone_fresh_dark');
  }
  for (const [x0, x1, h, z0, z1] of [[13, 16, 1, 6, 8], [15, 18, 2, 6, 7], [19, 21, 1, 6, 8], [22, 24, 1, 5, 7], [10, 11, 1, 7, 8],
    [-8, -6, 1, 6, 8], [-22, -20, 1, 6, 8]]) v.box(x0, x1, 0, h, z0, z1, 'stone_fresh');   // spalls
  return v;
}

// One weathered tier of a boulder: a dark foot if it stands on the ground, a lit top layer.
function stoneTier(v, x0, x1, y0, y1, z0, z1, n) {
  if (y0 === 0) { stoneBlock(v, x0, x1, 0, 2, z0, z1, n, 'stone_skin_dark'); stoneBlock(v, x0, x1, 2, y1 - 1, z0, z1, n); }
  else stoneBlock(v, x0, x1, y0, y1 - 1, z0, z1, n);
  stoneBlock(v, x0, x1, y1 - 1, y1, z0, z1, n, 'stone_skin_top');
}

// The hole knocked in a boulder's top, w x w at (x0, z0), from `floor` up to `top`, and the stone
// pot standing in it, its rim a cell above the crown. The hole's lip is fresh stone, its walls
// smoke-black, ash on its floor. The pot's corners are cut away, so four cells stay empty round
// its foot (the charge's coals glow there).
function potHole(v, x0, z0, w, floor, top) {
  const x1 = x0 + w, z1 = z0 + w;
  v.box(x0, x1, floor, top, z0, z1, null);
  v.paint(x0 - 1, x1 + 1, top - 1, top, z0 - 1, z1 + 1, 'stone_fresh');
  v.paint(x0 - 1, x0, floor, top - 1, z0, z1, 'soot'); v.paint(x1, x1 + 1, floor, top - 1, z0, z1, 'soot');
  v.paint(x0, x1, floor, top - 1, z0 - 1, z0, 'soot'); v.paint(x0, x1, floor, top - 1, z1, z1 + 1, 'soot');
  v.box(x0, x1, floor, floor + 1, z0, z1, 'ash');
  stoneBlock(v, x0, x1, floor + 1, top + 1, z0, z1, 1, 'stone_skin_dark');   // the pot
  v.paint(x0, x1, top, top + 1, z0, z1, 'stone_skin');                        // its rim
  v.box(x0 + 1, x1 - 1, top - 3, top + 1, z0 + 1, z1 - 1, null);
  v.paint(x0 + 1, x1 - 1, top - 4, top - 3, z0 + 1, z1 - 1, 'soot');
}

// The fire hole knocked in a boulder's foot at the front: x0..x1 wide, `high` cells high, from
// the foot's front face at `front` back to `back`. Its walls and the ledge over it are
// smoke-black, and a short uneven stain climbs the face above (`face` is the body's front row of
// cells, `ledge` the foot's top layer).
function fireHole(v, x0, x1, high, back, front, face, ledge) {
  v.box(x0, x1, 0, high, back, front, null);
  v.box(x0, x1, 0, 1, back, front, 'ash');
  v.paint(x0, x1, 1, high, back - 1, back, 'soot');
  v.paint(x0 - 1, x0, 0, high, back, front, 'soot'); v.paint(x1, x1 + 1, 0, high, back, front, 'soot');
  v.paint(x0 - 1, x1 + 1, high, ledge + 1, back, front, 'soot');
  v.paint(x0, x1, ledge + 1, ledge + 3, face, face + 1, 'soot');
  v.paint(x0 + 2, x1 - 1, ledge + 3, ledge + 5, face, face + 1, 'soot');
}

// ── Basic smelter: 3 x 1, inside -24..24 x 0..25 x -8..8 (doc 297; doc 300, the owner's pick E;
// doc 301, B) ──
// The Blacksmith's own workbench, built only from what the dwarves have (owner: "the dwarves have
// basic tools for now, keep it rudimentary"; no clay), in worked stone. Left two cells: one great
// stone, two cells broad and 24 cells high, with a low shoulder toward the casting stone and a
// lump at its front, knocked hollow with the maul: a stone pot stands in the hole in its crown
// (the charge is tipped into it, by hand), its lip fresh stone, and a fire hole is knocked in its
// foot at the front (+Z), both smoke-black. A flake is gone from its flank and a crack runs down
// its back. Right cell: the casting stone, a thick worked slab on two log rounds with their root
// flares, its top at bench height (Y15), with one bar mould pecked in its front and peck marks
// behind it where fittings are hammered. The charge (glowing coals, copper melting in the pot) and
// the cast bar are parts of their own (basicSmelterCharge, basicSmelterBar).
export function basicSmelter() {
  const v = new Vox();
  stoneTier(v, -24, 8, 0, 10, -8, 8, 4);                                // the boulder's broad foot, two cells
  stoneTier(v, -8, 0, 0, 14, 1, 8, 2);                                  // a lump at its front
  stoneTier(v, -24, -4, 10, 19, -8, 5, 3);                              // its body, set back above the fire
  stoneTier(v, -4, 7, 10, 14, -7, 4, 2);                                // a low shoulder toward the casting stone
  stoneTier(v, -22, -11, 19, 24, -6, 4, 2);                             // its crown, two cells of wall round the pot
  potHole(v, -19, -4, 5, 17, 24);
  fireHole(v, -20, -14, 7, 3, 8, 4, 9);
  knockOff(v, -24, -22, 5, 10, -4, 1);                                  // a flake off its left flank
  v.box(-9, -8, 10, 19, -8, -7, null); v.box(-10, -9, 12, 20, -8, -7, null);   // a crack down the back
  v.box(-24, -22, 0, 1, 6, 8, 'stone_fresh'); v.box(-23, -22, 0, 2, 5, 6, 'stone_fresh'); v.box(4, 7, 0, 1, 6, 8, 'stone_fresh');   // spalls
  for (const x0 of [9, 17]) {                                           // the casting stone's two log rounds
    v.box(x0 + 1, x0 + 5, 0, 2, -5, 5, 'bark_dark'); v.box(x0 - 1, x0 + 7, 0, 2, -3, 3, 'bark_dark');   // root flare
    v.box(x0 + 1, x0 + 5, 2, 9, -4, 4, 'bark'); v.box(x0, x0 + 6, 2, 9, -3, 3, 'bark');
    v.paint(x0 + 2, x0 + 3, 3, 8, 3, 4, 'bark_light'); v.paint(x0 + 3, x0 + 4, 2, 7, -4, -3, 'bark_light');
  }
  workedStone(v, 9, 24, 9, 15, -7, 7, 2, 1);                            // the slab, never dressed
  v.box(12, 20, 14, 15, 1, 3, null); v.paint(12, 20, 13, 14, 1, 3, 'stone_fresh_dark');   // the bar mould
  for (const [x, z] of [[13, -4], [15, -3], [17, -4], [16, -2]]) {      // where fittings are hammered
    v.box(x, x + 1, 14, 15, z, z + 1, null); v.paint(x, x + 1, 13, 14, z, z + 1, 'stone_fresh_dark');
  }
  knockOff(v, 21, 24, 12, 15, -7, -4);                                  // a corner broken away
  v.box(22, 24, 0, 1, 6, 8, 'stone_fresh'); v.box(10, 11, 0, 1, 7, 8, 'stone_fresh');     // spalls
  return v;
}

// ── Basic smelter's charge (parts/basic_smelter_charge), in the smelter's own coordinates ──
// Copper melting in the stone pot, coals glowing round its foot and in the fire hole, each in a
// cell the smelter left empty. Shown from the moment the charge is in the pot until the copper
// has set (doc 300, step 2).
export function basicSmelterCharge() {
  const v = new Vox();
  v.box(-18, -15, 21, 23, -3, 0, 'molten'); v.paint(-17, -16, 22, 23, -2, -1, 'molten_light');   // in the pot
  for (const [x, z] of [[-19, -4], [-15, -4], [-19, 0], [-15, 0]]) v.box(x, x + 1, 18, 20, z, z + 1, 'ember');   // round its foot
  v.box(-20, -14, 1, 3, 4, 7, 'char'); v.paint(-19, -15, 2, 3, 4, 6, 'ember');   // the fire hole's coals
  v.box(-20, -14, 1, 4, 3, 4, 'ember');                                 // its glow
  return v;
}

// ── Basic smelter's cast bar (parts/basic_smelter_bar), in the smelter's own coordinates ──
// The copper bar set in the casting stone's mould: shown once the melt is done, in place of the
// charge, until a Blacksmith takes it off.
export function basicSmelterBar() {
  const v = new Vox();
  v.box(12, 20, 14, 15, 1, 3, 'copper');
  v.paint(12, 20, 14, 15, 1, 2, 'copper_light');
  v.paint(12, 13, 14, 15, 1, 3, 'copper_dark'); v.paint(19, 20, 14, 15, 1, 3, 'copper_dark');
  return v;
}

// Where the maul's blows have pitted a fresh face: each pit one cell, its floor a step darker.
function pecks(v, y, cells) { for (const [x, z] of cells) { v.box(x, x + 1, y, y + 1, z, z + 1, null); v.paint(x, x + 1, y - 1, y, z, z + 1, 'stone_fresh_dark'); } }
// Copper beaten into a face where the bars lie, painted flush.
function smear(v, y, cells, role = 'copper') { for (const [x, z] of cells) v.paint(x, x + 1, y, y + 1, z, z + 1, role); }

// ── Anvil stone: 2 x 1, inside -16..16 x 0..15 x -8..8, its face at Y15 (doc 310, the owner's
// pick B) ──
// Where a Blacksmith hammers a bar into a tool (the owner, 2026-11-14: "I think the smelter should
// not be that workstation"): one great stone, two cells broad, with its top split off level and
// nothing else done to it. No wood at all. A broad foot, a lump against its right flank, and the
// upper stone set back from the front and hanging over the back, in worked stone. The hammering
// face is fresh stone inside a ledge of weathered skin, at the casting stone's height (Y15), over
// the left cell and half the right; it stops where the split ran out, a cell lower. It is pitted
// where the maul falls, about the middle of the left cell, where the bar lies (the furniture's
// crafting_cell), with copper beaten into it. A corner is broken away toward the front, a crack
// runs in from the back, and spalls and a scrap of copper lie on the foot's ledge.
export function anvilStone() {
  const v = new Vox();
  stoneTier(v, -16, 12, 0, 8, -7, 8, 4);                               // its foot, broad
  stoneTier(v, 6, 16, 0, 11, -6, 6, 3);                                // a lump against its right flank
  stoneTier(v, -14, 8, 8, 14, -8, 4, 3);                               // the upper stone: set back from the front, hanging over the back
  stoneBlock(v, -13, 7, 14, 15, -7, 3, 3, 'stone_fresh');              // the hammering face, inside a ledge of skin
  v.box(4, 8, 14, 15, -1, 4, null);                                    // where the split ran out, a cell lower
  knockOff(v, -14, -11, 11, 15, 1, 4);                                 // a corner broken away, toward the front
  v.box(-1, 0, 11, 15, -8, -3, null); v.paint(-1, 0, 10, 11, -8, -3, 'stone_cleft');   // a crack in from the back
  pecks(v, 14, [[-8, -3], [-6, -2], [-7, 0], [-5, -4], [-4, -1], [-9, -1], [-5, 1]]);
  smear(v, 14, [[-3, 1], [-2, 1], [-8, 2]]); smear(v, 14, [[-2, 2], [-7, 2]], 'copper_dark');
  v.box(-4, -1, 8, 9, 5, 7, 'stone_fresh'); v.box(-6, -5, 8, 9, 6, 7, 'stone_fresh');  // spalls on the foot's ledge
  v.box(1, 3, 8, 9, 5, 6, 'copper'); v.paint(1, 2, 8, 9, 5, 6, 'copper_dark');         // a scrap of copper
  return v;
}

// ── Stone stool: X -8..8 (1 x 1), seat at Y14 like the log stool (doc 293, B; doc 301, A) ──
// The Stonemason's first piece: one Rough stone knocked square all the way down, built as a
// stone (see "Worked stone" above). Its seat is a fresh face inside a ledge of weathered skin.
// One top corner is knocked off, which breaks its outline and shows fresh stone; a crack runs
// from the seat down the back; a chip is gone from its foot, and two spalls lie beside it.
export function stoneStool() {
  const v = new Vox();
  workedStone(v, -7, 7, 0, 14, -7, 7, 2);
  knockOff(v, 3, 7, 9, 14, 3, 7);                                       // a corner knocked off
  knockOff(v, -7, -4, 0, 4, -7, -4);                                    // a chip gone from the foot
  v.box(-2, -1, 12, 14, -6, 0, null); v.paint(-2, -1, 11, 12, -6, 0, 'stone_cleft');   // a crack across the seat
  v.box(-2, -1, 6, 14, -7, -6, null); v.paint(-2, -1, 5, 6, -7, -6, 'stone_cleft');    // and down the back
  v.box(7, 8, 0, 1, 3, 6, 'stone_fresh'); v.box(5, 7, 0, 1, 7, 8, 'stone_fresh');      // spalls
  return v;
}

// ── Tool rack: X -24..24 (3 x 1), its back on a wall at Z-8, hooks at Y39 (doc 294, B) ──
// The Carpenter's first piece and the first storage furniture: half a split log pegged to the
// wall. Since 2026-11-11 (the owner's pick of three) it hangs bark side out: its flat split face
// to the wall and its round bark side to the room, dark bark in long ridges, both ends chopped
// pale, the rope pale across it at its two wall pegs, and three pale pegs driven through the
// bark. Tools hang from the pegs (the furniture's storage anchors) against the crown of the
// round, which stands where the split face did.
export function toolRack() {
  const v = new Vox();
  v.box(-24, 24, 33, 43, -8, -6, 'bark');                             // the round, in three steps out from the wall
  v.box(-24, 24, 34, 42, -6, -5, 'bark');
  v.box(-24, 24, 35, 41, -5, -4, 'bark');
  v.paint(-24, 24, 33, 35, -8, -4, 'bark_dark');                      // dark underneath
  for (const [a, b, y, z] of [[-20, -11, 40, -5], [1, 6, 40, -5], [11, 21, 39, -5], [-6, 5, 37, -5], [10, 20, 36, -5], [-21, -12, 36, -5],
    [-17, -10, 41, -6], [-5, 6, 41, -6], [12, 19, 41, -6], [-3, 6, 42, -7], [-20, -11, 42, -7], [11, 16, 42, -8]]) v.paint(a, b, y, y + 1, z, z + 1, 'bark_light');   // ridges along it
  for (const [a, b, y] of [[-22, -10, 38], [2, 13, 38], [14, 22, 40], [-6, 4, 35]]) v.paint(a, b, y, y + 1, -5, -4, 'bark_dark');   // furrows
  for (const s of [-1, 1]) {                                          // the ends, chopped back in steps, pale
    const a = s < 0 ? -24 : 22, e = s < 0 ? -24 : 23;
    v.box(a, a + 2, 35, 41, -5, -4, null); v.box(e, e + 1, 34, 42, -6, -5, null);
    v.paint(a, a + 2, 33, 43, -8, -4, 'wood_top');
    v.paint(e, e + 1, 37, 39, -8, -7, 'pith'); v.paint(e, e + 1, 35, 41, -7, -6, 'grain');
  }
  for (const x of [-9, 7]) {                                          // between the pegs:
    v.box(x, x + 2, 43, 46, -8, -5, 'riven_dark'); v.paint(x, x + 2, 43, 46, -6, -5, 'wood_top');   // a wall peg,
    v.paint(x, x + 2, 33, 44, -8, -4, 'rope');                        // and the rope round the log and the peg's foot, flush
    v.paint(x, x + 2, 37, 38, -8, -4, 'rope_dark'); v.paint(x, x + 2, 41, 42, -8, -4, 'rope_dark');
  }
  for (const hook of [-16, 0, 16]) {                                         // pale pegs driven through the bark
    const x = hook - 1;
    v.box(x + 2, x + 6, 37, 38, -5, -4, null); v.paint(x + 2, x + 6, 37, 38, -6, -5, 'riven');   // the bark split, pale wood under it
    v.box(x, x + 2, 36, 38, -4, -1, 'riven');
    v.box(x, x + 2, 37, 39, -1, 1, 'riven'); v.paint(x, x + 2, 37, 39, 0, 1, 'wood_top');
  }
  return v;
}

// ── Raw materials crate: X, Z -16..16 (2 x 2), its rim at Y13 (doc 294, A; doc 301, A) ──────────
// The log crib, built up (the owner's pick, 2026-11-10): three courses of stout notched logs
// crossing at the corners, open on top, so it stands as a bin when it is empty. Two sides stand a
// course lower than the other two. Each log's ends run a cell past the logs it crosses, within
// the footprint. Goods sit on the ground in its four quarters, at X and Z ±6 (the furniture's
// storage anchors).
export function rawMaterialsCrate() {
  const v = new Vox();
  for (const z of [-15, 10]) logX(v, -16, 16, 0, 5, z, z + 5, 'bark_dark');   // the first course, along X
  for (const x of [-15, 10]) logZ(v, x, x + 5, 4, 9, -16, 16);                // the second, along Z, in notches
  for (const z of [-15, 10]) logX(v, -16, 16, 8, 13, z, z + 5);               // the third
  for (const x of [-15, 10]) for (const z of [-15, 10]) { v.paint(x, x + 5, 4, 5, z, z + 5, 'chop'); v.paint(x, x + 5, 8, 9, z, z + 5, 'chop'); }
  for (const z of [-15, 14]) {                                                // bark ridges along the outer faces
    v.paint(-8, -2, 10, 11, z, z + 1, 'bark_light'); v.paint(3, 9, 10, 11, z, z + 1, 'bark_light'); v.paint(-6, 4, 2, 3, z, z + 1, 'bark_light');
  }
  for (const z of [-11, 10]) { v.paint(-9, -4, 12, 13, z, z + 1, 'bark_light'); v.paint(1, 8, 12, 13, z, z + 1, 'bark_light'); }
  v.paint(-15, -14, 6, 7, -7, 5, 'bark_light'); v.paint(14, 15, 6, 7, -3, 8, 'bark_light');
  return v;
}

// ── Finished goods pallet: X, Z -16..16 (2 x 2), its deck top at Y7 (doc 62, A, log skids) ──
// The owner's pick of three concepts (2026-11-02): timbers laid across two log runners and
// lashed to them. Since 2026-11-11 (the owner's pick of three ways to lay it) the deck is four
// broad split halves, let a cell into the runners, each wide enough to show what a split log
// shows (sapwood, a heart band, a knot), with dark gaps between them and the lashings in the
// gaps. Goods stand on the deck in its four quarters, at X and Z ±8 (the furniture's storage
// anchors), where its top is level at Y7.
// A half or a pole split from a log, lying along Z, riven face up at `top`: the Z twin of rivenX.
// `steps` are [layers, side inset, end chop] from the top down. Its end faces show end grain: a
// pith on the split face and, with `arc`, one growth ring round it.
function rivenZ(v, x0, x1, z0, z1, top, steps, arc = 0) {
  let y = top;
  const xc = Math.floor((x0 + x1) / 2);
  for (const [h, inset, chop] of steps) {
    v.box(x0 + inset, x1 - inset, y - h, y, z0 + chop, z1 - chop, 'bark');
    for (const z of [z0 + chop, z1 - chop - 1]) {
      v.paint(x0 + inset, x1 - inset, y - h, y, z, z + 1, 'wood_top');
      if (arc > 0) {
        const ya = Math.max(top - 1 - arc, y - h), yb = Math.min(top, y);
        if (ya < yb) { v.paint(xc - arc, xc - arc + 1, ya, yb, z, z + 1, 'grain'); v.paint(xc + arc, xc + arc + 1, ya, yb, z, z + 1, 'grain'); }
        if (top - 1 - arc >= y - h && top - 1 - arc < y) v.paint(xc - arc, xc + arc + 1, top - 1 - arc, top - arc, z, z + 1, 'grain');
      }
      if (top - 1 >= y - h) v.paint(xc, xc + 1, top - 1, top, z, z + 1, 'pith');
    }
    y -= h;
  }
  v.paint(x0, x1, top - 1, top, z0, z1, 'riven');
  return xc;
}
// What a half split through its heart shows on its face, on layer y, for a half lying along Z:
// pale sapwood on the edges (sapL, sapR cells), a darker heart band over cells bx0..bx1 that
// stops short of the ends and swells once on each side, and the pith at px as a broken line.
// `flip` runs it from the other end, so no two halves beside each other match.
function heartZ(v, y, x0, x1, z0, z1, bx0, bx1, px, sapL = 1, sapR = 1, flip = false) {
  const line = (xa, xb, a, b, role) => {
    const [za, zb] = flip ? [z0 + z1 - b, z0 + z1 - a] : [a, b];
    if (za < zb) v.paint(xa, xb, y, y + 1, za, zb, role);
  };
  if (sapL) v.paint(x0, x0 + sapL, y, y + 1, z0, z1, 'wood_top');
  if (sapR) v.paint(x1 - sapR, x1, y, y + 1, z0, z1, 'wood_top');
  line(bx0, bx1, z0 + 3, z1 - 4, 'grain');
  line(bx0 - 1, bx0, z0 + 9, z1 - 14, 'grain');
  line(bx1, bx1 + 1, z0 + 16, z1 - 7, 'grain');
  const long = z1 - z0;
  for (const [a, b] of [[0.10, 0.31], [0.37, 0.45], [0.53, 0.79], [0.85, 0.91]]) line(px, px + 1, z0 + Math.round(a * long), z0 + Math.round(b * long), 'riven_dark');
}
export function finishedGoodsPallet() {
  const v = new Vox();
  for (const z of [-12, 8]) {
    v.cutX(-16, 16, 0, 4, z, z + 4, 1, 'bark_dark');
    v.paint(-16, -15, 0, 4, z, z + 4, 'wood_top'); v.paint(15, 16, 0, 4, z, z + 4, 'wood_top');
  }
  const HALF4 = [[2, 0, 0], [1, 1, 1], [1, 3, 2]];
  rivenZ(v, -16, -8, -16, 15, 7, HALF4, 2);
  rivenZ(v, -7, 0, -15, 16, 7, HALF4, 2);
  rivenZ(v, 1, 8, -16, 16, 7, HALF4, 2);
  rivenZ(v, 9, 16, -14, 16, 7, HALF4, 2);
  const Y = 6;
  heartZ(v, Y, -16, -8, -16, 15, -13, -10, -12, 2, 1);
  v.paint(-16, -15, Y, Y + 1, -16, 9, 'bark');                                         // bark left on an edge here and there
  heartZ(v, Y, -7, 0, -15, 16, -5, -2, -4, 1, 1, true);
  heartZ(v, Y, 1, 8, -16, 16, 4, 6, 4, 1, 2);
  v.paint(7, 8, Y, Y + 1, -3, 16, 'bark');
  heartZ(v, Y, 9, 16, -14, 16, 11, 14, 12, 1, 2, true);
  v.paint(15, 16, Y, Y + 1, -14, 2, 'bark');
  knot(v, Y, -11, 9); knot(v, Y, -3, -9); knot(v, Y, 3, 4); knot(v, Y, 13, -6);
  bites(v, Y, [[-5, 13], [-4, 14], [-3, 15], [10, 12], [11, 13], [-14, -14], [-13, -13]]);
  v.box(5, 6, 6, 7, -16, -9, null); v.box(5, 6, 4, 7, -16, -14, null);                 // a drying split from one end
  for (const gx of [-8, 0, 8]) for (const z of [-12, 8]) {                             // lashed to the runners in the gaps
    v.box(gx, gx + 1, 3, 6, z - 1, z + 5, 'rope'); v.paint(gx, gx + 1, 5, 6, z + 1, z + 3, 'rope_dark');
  }
  for (const [x, z] of [[-16, -12], [14, -12], [-16, 8], [14, 8]]) v.box(x, x + 2, 3, 5, z - 1, z + 5, 'rope');   // and at the corners
  return v;
}

// ── Food shelf: X -24..24, Y 0..40, Z -8..8 (3 x 1), facing +Z (doc 299, A, the lean-to rack) ──
// The owner's pick of three concepts (2026-11-06). At each end a bark post with a pole leaned against
// it and lashed at the top; rails lashed across them at two heights; timbers laid along the rails.
// The lean makes the upper deck shallower than the lower, so both rows of crates show from above:
// crates stand at X 0 and ±15, the upper row on Y31 at Z-3, the lower on Y12 at Z3 (the furniture's
// storage anchors). Since 2026-11-11 (the owner's pick of three ways to lay the decks) the bark of
// the posts and the leaning poles is in upright ridges, and the decks are broad halves: two halves
// of a split log below, one half and a pole above, each face drawn as the table tops are.
// A pole along X on a deck, `w` cells across and three thick, its two long edges a cell lower
// (today's section). Each end may be chopped: the top layer that many cells shorter, the chopped
// wood pale.
function pole(v, x0, x1, y0, z0, w, chop0 = 0, chop1 = 0) {
  v.cutX(x0, x1, y0, y0 + 3, z0, z0 + w, 1, 'bark');
  if (chop0) v.box(x0, x0 + chop0, y0 + 2, y0 + 3, z0, z0 + w, null);
  if (chop1) v.box(x1 - chop1, x1, y0 + 2, y0 + 3, z0, z0 + w, null);
}
function poleEnds(v, x0, x1, y0, z0, w, chop0 = 0, chop1 = 0) {
  v.paint(x0, x0 + Math.max(chop0, 1), y0, y0 + 3, z0, z0 + w, 'wood_top');
  v.paint(x1 - Math.max(chop1, 1), x1, y0, y0 + 3, z0, z0 + w, 'wood_top');
}
function splitPole(v, x0, x1, y0, z0, w, chop0, chop1, face) {
  pole(v, x0, x1, y0, z0, w, chop0, chop1);
  v.paint(x0, x1, y0 + 2, y0 + 3, z0, z0 + w, face);
  poleEnds(v, x0, x1, y0, z0, w, chop0, chop1);
}
const dashes = (v, y, z, runs, role = 'riven_dark') => { for (const [a, b] of runs) v.paint(a, b, y, y + 1, z, z + 1, role); };
const SLAB = [[1, 0, 0], [1, 1, 0], [1, 2, 1]];                      // half a small log, 3 cells thick, its ends on the rails
export function foodShelf() {
  const v = new Vox();
  for (const x0 of [-24, 21]) {
    const out = x0 < 0 ? x0 : x0 + 2, inn = x0 < 0 ? x0 + 2 : x0;      // the post's outer and inner columns
    v.box(x0, x0 + 3, 0, 40, -8, -5, 'bark');                         // the back post
    v.paint(x0, x0 + 3, 0, 2, -8, -5, 'bark_dark');
    v.paint(x0, x0 + 3, 39, 40, -8, -5, 'wood_top');
    v.paint(x0, x0 + 1, 3, 21, -6, -5, 'bark_light'); v.paint(x0 + 2, x0 + 3, 12, 32, -6, -5, 'bark_light');   // ridges: its front,
    v.paint(out, out + 1, 4, 23, -7, -6, 'bark_light'); v.paint(out, out + 1, 17, 37, -8, -7, 'bark_light');   // its outer side,
    v.paint(inn, inn + 1, 10, 24, -7, -6, 'bark_light'); v.paint(inn, inn + 1, 29, 38, -6, -5, 'bark_light');  // its inner side,
    v.paint(x0 + 1, x0 + 2, 5, 20, -8, -7, 'bark_light'); v.paint(x0, x0 + 1, 22, 36, -8, -7, 'bark_light');   // its back
    for (let y = 0; y < 37; y++) {                                    // the pole leaned against it
      const z = 5 - Math.floor(y * 10 / 36);
      v.box(x0, x0 + 3, y, y + 1, z, z + 3, y < 2 ? 'bark_dark' : 'bark');
      if (y >= 3 && y < 19) v.paint(x0, x0 + 1, y, y + 1, z + 2, z + 3, 'bark_light');          // ridges along its front
      if (y >= 13 && y < 31) v.paint(x0 + 2, x0 + 3, y, y + 1, z + 2, z + 3, 'bark_light');
      if (y >= 9 && y < 24) v.paint(out, out + 1, y, y + 1, z + 1, z + 2, 'bark_light');        // and its outer side
      if (y >= 4 && y < 16) v.paint(x0 + 1, x0 + 2, y, y + 1, z, z + 1, 'bark_light');          // and its back
    }
    v.paint(x0, x0 + 3, 32, 38, -8, -1, 'rope');                      // lashed where they meet
    v.paint(x0, x0 + 3, 34, 35, -8, -1, 'rope_dark');
    for (const rail of [6, 25]) {                                     // lashed where the rails cross
      v.paint(x0, x0 + 3, rail, rail + 3, -8, 8, 'rope');
      v.paint(x0, x0 + 3, rail + 1, rail + 2, -8, 8, 'rope_dark');
    }
  }
  for (const [rail, front] of [[6, 8], [25, 2]]) {
    for (const x0 of [-21, 18]) {                                     // a rail across each end
      v.box(x0, x0 + 3, rail, rail + 3, -8, front, 'bark_dark');
      v.paint(x0 + 1, x0 + 2, rail + 2, rail + 3, -6, front - 2, 'bark');
      v.paint(x0, x0 + 3, rail, rail + 3, front - 1, front, 'riven_dark');
    }
  }
  rivenX(v, -21, 20, -8, -1, 12, SLAB, 1); heartX(v, 11, -21, 20, -8, -1, 1, 1, 1);          // the lower deck: two halves,
  rivenX(v, -20, 21, 0, 8, 12, SLAB, 1); heartX(v, 11, -20, 21, 0, 8, 1, 1, 1);              // a cell apart
  knot(v, 11, -11, 2); knot(v, 11, 9, -4);
  v.box(8, 21, 11, 12, 5, 6, null); v.box(18, 21, 9, 12, 5, 6, null);                        // a drying split from one end
  splitPole(v, -21, 20, 28, -8, 3, 0, 0, 'riven'); dashes(v, 30, -7, [[-14, -5], [2, 12]]);  // the upper deck: a pole at the back,
  rivenX(v, -21, 21, -5, 2, 31, SLAB, 1); heartX(v, 30, -21, 21, -5, 2, 1, 1, 1);            // and one half
  knot(v, 30, 12, -1);
  v.box(-21, -11, 30, 31, -3, -2, null); v.box(-21, -19, 28, 31, -3, -2, null);
  return v;
}

// ── Rough ladder: X -6..6, Y 0..16h, Z -5..-1; rungs every 8 cells from Y4 ────
export function ladder(blocks) {
  const v = new Vox();
  const H = blocks * 16;
  for (const [x0, x1] of [[-6, -3], [3, 6]]) {
    v.cut(x0, x1, 0, H - 2, -5, -1, 1, 'bark');
    v.box(x0 + 1, x1 - 1, H - 2, H, -4, -2, 'bark'); v.paint(x0 + 1, x1 - 1, H - 1, H, -4, -2, 'wood_top');
  }
  for (let y = 4; y + 2 <= H - 2; y += 8) {
    v.box(-3, 3, y, y + 2, -4, -2, 'wood_side');
    for (const x of [-4, 3]) { v.paint(x, x + 1, y - 1, y + 3, -5, -1, 'rope'); v.paint(x, x + 1, y + 1, y + 2, -5, -1, 'rope_dark'); }
  }
  for (let y = 9; y + 3 < H - 2; y += 21) v.paint(-6, -5, y, y + 3, -5, -1, 'bark_light');
  return v;
}

// ── Ladder kit: X -10..10, Y 0..9, Z -6..6. Three poles bound with rope ───────
export function ladderKit() {
  const v = new Vox();
  for (const [y0, z0] of [[0, -5], [0, 1], [4, -2]]) {
    v.cutX(-10, 10, y0, y0 + 4, z0, z0 + 4, 1, 'bark');
    for (const x of [-10, 9]) v.paint(x, x + 1, y0, y0 + 4, z0, z0 + 4, 'wood_top');
  }
  v.paint(-5, 3, 1, 3, -5, -4, 'bark_light');
  for (const x0 of [-6, 4]) { v.paint(x0, x0 + 2, 0, 9, -6, 6, 'rope'); v.box(x0, x0 + 2, 8, 9, -1, 1, 'rope_dark'); }
  return v;
}

// ── Packed furniture: 16 x 16 x 16 crate of split slats on bark corner posts ──
export function packedCrate() {
  const v = new Vox();
  for (const x0 of [-8, 5]) for (const z0 of [-8, 5]) v.box(x0, x0 + 3, 0, 16, z0, z0 + 3, 'bark');
  for (const y0 of [1, 6, 11]) {
    v.box(-5, 5, y0, y0 + 4, -8, -6, 'riven'); v.box(-5, 5, y0, y0 + 4, 6, 8, 'riven');
    v.box(-8, -6, y0, y0 + 4, -5, 5, 'riven'); v.box(6, 8, y0, y0 + 4, -5, 5, 'riven');
  }
  v.box(-6, 6, 0, 1, -6, 6, 'riven_dark'); v.box(-6, 6, 15, 16, -6, 6, 'riven');
  for (const x0 of [-5, -1, 3]) v.paint(x0, x0 + 1, 15, 16, -6, 6, 'riven_dark');
  for (const x0 of [-8, 5]) for (const z0 of [-8, 5]) v.paint(x0, x0 + 3, 15, 16, z0, z0 + 3, 'wood_top');
  v.paint(-8, 8, 7, 9, -8, -7, 'rope'); v.paint(-8, 8, 7, 9, 7, 8, 'rope'); v.paint(-8, -7, 7, 9, -8, 8, 'rope'); v.paint(7, 8, 7, 9, -8, 8, 'rope');
  return v;
}

// ── Hearth: a split boulder, body inside -16..16 x 0..27 x -16..16; the fire faces +Z ──
// The fire-back the owner picked on 2026-10-29 (doc 279), since 2026-11-11 one boulder in worked
// stone (the owner's pick of three): its foot fills the back, its body and crown out of line with
// it, a great lump against its left flank coming forward beside the fire and a low toe at its
// right. Its front was split away flat for the fire to burn against: fresh stone up to the break,
// smoke-black behind the flame, weathered skin above. The piece that came away lies before it as
// the hearthstone, weathered side up, scorched round the ash. No wood of its own: the night's log
// is the real good a worker sets on the ash, whose top stays at Y4. The animated flame (inside
// X -8..8, Y 8..22, Z -10..6) burns before the split face, so those cells stay empty.
// The ash bed, where today's is: dark ash, a charred middle where the log burns, grey ash raked
// to one side. Its top is Y4.
function hearthAsh(v) {
  v.cut(-8, 8, 3, 4, -9, 6, 3, 'ash');
  v.paint(-3, 4, 3, 4, -6, 0, 'char'); v.paint(-1, 5, 3, 4, -4, 2, 'char');
  v.paint(-7, -3, 3, 4, -4, 4, 'stone_dark'); v.paint(-6, -4, 3, 4, -6, -4, 'stone_dark'); v.paint(-3, -1, 3, 4, 2, 5, 'stone_dark');
}
// The hearth floor scorched black round the ash, so the fire's own light does not wash it out.
function scorch(v) {
  v.paint(-10, 10, 1, 3, -11, 8, 'soot'); v.paint(-11, 11, 1, 3, -9, 6, 'soot');
}
export function hearth() {
  const v = new Vox();
  stoneBlock(v, -11, 12, 0, 3, -11, 13, 4, 'stone_fresh');               // the piece split away: the hearthstone,
  stoneBlock(v, -10, 11, 0, 2, -10, 12, 4); stoneBlock(v, -10, 11, 2, 3, -10, 12, 4, 'stone_skin_top');   // its broken edge fresh
  scorch(v);
  stoneTier(v, -16, 16, 0, 10, -16, -10, 2);                             // the boulder: its foot fills the back,
  stoneTier(v, -15, 13, 10, 22, -16, -10, 2);                            // its body out of line with it,
  stoneTier(v, -12, 0, 22, 27, -16, -11, 1);                             // its crown left of the middle, set back,
  stoneTier(v, 0, 7, 22, 24, -16, -11, 1);                               // stepping down to the right
  stoneTier(v, -16, -8, 0, 13, -13, 2, 3);                               // a great lump against its left flank, coming forward
  stoneTier(v, -16, -10, 13, 17, -14, -5, 2);
  stoneTier(v, 10, 16, 0, 6, -11, -5, 2);                                // a low toe at its right
  v.paint(-8, 16, 3, 9, -11, -10, 'stone_fresh'); v.paint(-8, 13, 9, 16, -11, -10, 'stone_fresh');   // its front split away flat,
  v.paint(-8, -1, 16, 19, -11, -10, 'stone_fresh');                      // the break stepping up at the left
  knockOff(v, 13, 16, 3, 6, -8, -5);                                     // a flake off the toe
  v.box(9, 10, 21, 22, -16, -10, null); v.box(9, 10, 16, 21, -11, -10, null);             // a crack down from the top
  v.paint(9, 10, 20, 21, -16, -11, 'stone_cleft'); v.paint(9, 10, 16, 21, -12, -11, 'stone_cleft');
  for (const [x0, x1, h, z0, z1] of [[-15, -13, 1, 5, 7], [-14, -13, 2, 8, 9], [-16, -14, 1, 11, 13], [13, 15, 1, 0, 2], [14, 16, 1, 6, 8], [13, 14, 2, 11, 12]]) {
    v.box(x0, x1, 0, h, z0, z1, 'stone_fresh');                          // spalls where they fell
  }
  hearthAsh(v);
  v.paint(-8, 9, 3, 11, -11, -10, 'stone_fresh_dark'); v.paint(-5, 8, 11, 13, -11, -10, 'stone_fresh_dark');   // a smoke stain,
  v.paint(-2, 7, 13, 15, -11, -10, 'stone_fresh_dark');
  v.paint(-6, 7, 3, 10, -11, -10, 'soot'); v.paint(-3, 6, 10, 12, -11, -10, 'soot');      // and smoke-black behind the flame,
  v.paint(0, 5, 12, 14, -11, -10, 'soot');                               // drifting as smoke does
  v.paint(-9, -8, 3, 12, -10, 1, 'soot');                                // and on the lump's face toward it
  return v;
}

// ── Campfire: a 3 x 3 camp area, the ring inside -16..16 x 0..6 x -16..16 ────────
// Five great stones round the fire, in worked stone (the owner's pick of three, 2026-11-11):
// fewer and bigger than the proposal's eight (proposal.mjs keeps that ring), out of line with
// each other, the gaps between them showing the bed, one knocked flat on top. Seats stand round
// the camp area and dwarves hold grilling sticks over the ring, so no stone is higher than the
// low box of the fire's definition (6 cells). No wood of its own: the night's log is the real
// good a worker sets on the ash in the middle, whose top stays at Y1.
// The fire bed: ground burnt black out to the stones, grey ash in the middle of it, a charred
// heart. Its top is Y1. A dark bed sets the stones off at noon, when their skin is lifted to a
// middle grey.
function campAsh(v, r = 12) {
  v.cut(-r, r, 0, 1, -r, r, 6, 'ash');
  v.cut(-7, 7, 0, 1, -7, 7, 3, 'stone_dark'); v.paint(5, 8, 0, 1, -2, 3, 'stone_dark'); v.paint(-3, 2, 0, 1, 6, 8, 'stone_dark');
  v.cut(-3, 4, 0, 1, -4, 3, 1, 'char');
}
// A ring stone: a dark foot, skin, a lit top; `cap` adds a second, smaller tier [x0, x1, z0, z1, top].
function ringStone(v, x0, x1, z0, z1, h, n = 1, cap = null) {
  stoneBlock(v, x0, x1, 0, 1, z0, z1, n, 'stone_skin_dark');
  if (h > 2) stoneBlock(v, x0, x1, 1, h - 1, z0, z1, n);
  stoneBlock(v, x0, x1, h - 1, h, z0, z1, n, 'stone_skin_top');
  if (cap) {
    const [a, b, c, d, top] = cap;
    if (top - h > 1) stoneBlock(v, a, b, h, top - 1, c, d, 1);
    stoneBlock(v, a, b, top - 1, top, c, d, 1, 'stone_skin_top');
  }
}
export function campfire() {
  const v = new Vox();
  campAsh(v);
  ringStone(v, -10, 7, -16, -8, 4, 2, [-8, 3, -16, -10, 6]);             // north, the broadest
  ringStone(v, 8, 16, -6, 5, 5, 2, [10, 16, -4, 3, 6]);                  // east
  workedStone(v, 4, 15, 0, 5, 8, 16, 2);                                 // south-east, knocked flat on top
  ringStone(v, -15, -4, 9, 16, 4, 2, [-13, -7, 10, 15, 6]);              // south-west
  ringStone(v, -16, -8, -6, 6, 5, 2);                                    // west, long and plain
  v.box(15, 16, 0, 1, 5, 7, 'stone_fresh'); v.box(1, 3, 0, 1, 14, 16, 'stone_fresh'); v.box(2, 3, 0, 2, 12, 13, 'stone_fresh');   // spalls by the knocked one
  v.paint(-10, 7, 1, 6, -10, -8, 'soot'); v.paint(8, 10, 1, 6, -6, 5, 'soot');
  v.paint(4, 13, 1, 4, 8, 10, 'soot'); v.paint(-13, -4, 1, 6, 9, 11, 'soot'); v.paint(-10, -8, 1, 6, -6, 6, 'soot');
  return v;
}

// ── Settlement flag: inside -8..8 x 0..48 x -6..6 ─────────────────────────────
// A rough pole in a cairn of squared stones; the banner hangs from a crossbar
// lashed to the pole, with a stitched mark and a fringed foot.
export function settlementFlag() {
  const v = new Vox();
  v.pillow(-6, 6, 0, 5, -6, 6, 1, 'stone'); v.pillow(-7, -1, 0, 4, -2, 5, 1, 'stone_light');
  v.pillow(1, 7, 0, 3, -5, 1, 1, 'stone_light'); v.pillow(-4, 3, 5, 8, -3, 4, 1, 'stone');
  v.box(-2, 1, 0, 46, -1, 2, 'bark'); v.box(-1, 0, 46, 48, 0, 1, 'bark'); v.paint(-1, 0, 47, 48, 0, 1, 'wood_top');
  v.paint(-2, -1, 12, 20, -1, 2, 'bark_light'); v.paint(0, 1, 26, 33, -1, 2, 'bark_light');
  v.cutX(-3, 8, 42, 44, -1, 2, 0, 'wood_side'); v.paint(7, 8, 42, 44, -1, 2, 'wood_top');
  v.box(-3, 2, 41, 45, -2, 3, 'rope'); v.box(-2, 1, 41, 45, -1, 2, 'bark');
  v.box(1, 8, 22, 42, 0, 1, 'flag');
  v.paint(1, 8, 39, 41, 0, 1, 'flag_light');
  for (const x of [2, 4, 6]) v.box(x, x + 1, 20, 22, 0, 1, 'flag');
  v.paint(3, 6, 29, 35, 0, 1, 'flag_mark'); v.paint(4, 5, 28, 36, 0, 1, 'flag_mark'); v.paint(2, 7, 31, 33, 0, 1, 'flag_mark');
  return v;
}

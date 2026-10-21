// Hearthblock Tier 1 · Axe-Hewn furniture for the game (2026-10-20, doc 256).
// Same vocabulary as proposal.mjs: 1:16 cells, [x0,x1) ranges, ground at Y0,
// X right, Z toward the front. Each model keeps the existing in-game frame and
// the contact bounds written above it. Split, chopped and notched with an axe:
// bark stays on, ends step back like axe cuts, joints are notches and lashings.
import { Vox, endRings, splitHalf, notchedLogBed } from './proposal.mjs';

export { notchedLogBed };

// Long broken riven-grain lines along X on the top layer of a split face.
function rivenLinesX(v, y, lines) {
  for (const [x0, x1, z] of lines) v.paint(x0, x1, y, y + 1, z, z + 1, 'riven_dark');
}

// A split half-log along Z, riven face up at `top`: the Z twin of splitHalf.
function splitHalfZ(v, x0, x1, z0, z1, top) {
  const steps = [[2, 0, 0], [2, 1, 1], [2, 3, 2], [2, 6, 4]];
  let y = top;
  for (const [h, inset, chop] of steps) {
    v.box(x0 + inset, x1 - inset, y - h, y, z0 + chop, z1 - chop, 'bark');
    for (const z of [z0 + chop, z1 - chop - 1]) v.paint(x0 + inset, x1 - inset, y - h, y, z, z + 1, 'wood_top');
    y -= h;
  }
  v.paint(x0 + 1, x1 - 1, top - 1, top, z0 + 1, z1 - 1, 'riven');
}

// ── Log bench: 32 x 16 x 16, seat at Y16, two-cell footprint ───────────────────
// Half of a split log, riven face up, dropped into notches in two short logs.
export function logBench() {
  const v = new Vox();
  for (const x0 of [-13, 7]) {                       // feet centred on x = ±10
    v.cutZ(x0, x0 + 6, 0, 10, -8, 8, 2, 'bark');
    endRings(v, 'z', -8, x0 + 3, 4, [2]); endRings(v, 'z', 7, x0 + 3, 4, [2]);
  }
  const zc = splitHalf(v, -16, 16, -8, 8, 16);
  rivenLinesX(v, 15, [[-13, 1, zc - 3], [-5, 11, zc + 3], [4, 13, zc - 4]]);
  for (const [x, z] of [[-14, zc - 1], [-13, zc], [-12, zc - 1], [12, zc + 1], [13, zc + 2]]) v.paint(x, x + 1, 15, 16, z, z + 1, 'chop');
  v.paint(-9, 3, 10, 12, -5, -4, 'bark_light'); v.paint(-2, 9, 12, 14, 6, 7, 'bark_light');   // loose bark plates
  v.box(12, 16, 15, 16, zc, zc + 1, null); v.box(14, 16, 12, 15, zc, zc + 1, null);          // drying split runs out of one end
  return v;
}

// ── Dining table: the proposal's Split-Slab Bench, 46 x 24 x 46, top at Y24 ──
// In game, everything under the top must stay inside the centre block (the
// seated-leg obstacle), so the upper cross log is shortened from 24 to 16 cells.
export function splitSlabTable() {
  const v = new Vox();
  v.cutX(-8, 8, 0, 9, -4, 4, 2, 'bark');
  v.box(-6, 4, 3, 6, -5, -4, 'bark_light');
  endRings(v, 'x', -8, 4, -1, [2]); endRings(v, 'x', 7, 4, -1, [2]);
  v.cutZ(-4, 4, 7, 16, -8, 8, 2, 'bark');
  endRings(v, 'z', -8, -1, 11, [2]); endRings(v, 'z', 7, -1, 11, [2]);
  const za = splitHalf(v, -23, 23, -23, -1, 24);
  const zb = splitHalf(v, -22, 22, 1, 23, 24);
  v.paint(-18, -2, 23, 24, za - 4, za - 3, 'riven_dark'); v.paint(3, 19, 23, 24, za + 4, za + 5, 'riven_dark');
  v.paint(-20, -6, 23, 24, zb + 3, zb + 4, 'riven_dark'); v.paint(-3, 15, 23, 24, zb - 4, zb - 3, 'riven_dark');
  for (const [x, z] of [[-20, za - 1], [-19, za], [-18, za + 1], [-17, za - 1], [-16, za], [17, zb], [18, zb + 1], [19, zb + 2]]) v.paint(x, x + 1, 23, 24, z, z + 1, 'chop');
  v.paint(7, 10, 23, 24, zb + 2, zb + 4, 'riven_dark'); v.paint(8, 9, 23, 24, zb + 2, zb + 3, 'pith');
  v.box(11, 23, 23, 24, za, za + 1, null);
  v.box(19, 23, 18, 24, za, za + 1, null);
  return v;
}

// ── Board-game table: the dining table with a board scratched into its top ───
// 46 x 25 x 46. Knot-dark grid lines; six 4 x 4 counters rest on solid wood.
export function gameTable() {
  const v = splitSlabTable();
  for (const g of [-11, -4, 3, 10]) {
    v.paint(-11, 11, 23, 24, g, g + 1, 'pith');
    v.paint(g, g + 1, 23, 24, -11, 11, 'pith');
  }
  for (const [x, z, c] of [[-9, -9, 'red'], [-2, -9, 'teal'], [5, -9, 'red'], [-9, 5, 'teal'], [-2, 5, 'red'], [5, 5, 'teal']]) {
    v.box(x, x + 4, 24, 25, z, z + 4, c);
  }
  return v;
}

// ── Crude workbench: 46 x 16 x 46, the accepted solid stump form ──────────────
// One great squared stump: root flare, raised bark plates, a bark rim, square
// growth rings, a drying crack and a worn chopping notch at the working edge.
export function workbench() {
  const v = new Vox();
  v.cut(-23, 23, 0, 2, -23, 23, 6, 'bark_dark');
  v.cut(-22, 22, 2, 14, -22, 22, 5, 'bark');
  for (const [x0, x1, y0, y1, z0, z1] of [[-23, -22, 4, 12, -9, 3], [-23, -22, 3, 8, 8, 13], [22, 23, 3, 11, -3, 9],
    [-7, 6, 4, 11, 22, 23], [9, 15, 5, 12, 22, 23], [3, 14, 5, 12, -23, -22], [-15, -8, 3, 9, -23, -22]]) v.box(x0, x1, y0, y1, z0, z1, 'bark_light');
  v.cut(-22, 22, 14, 16, -22, 22, 5, 'bark');
  v.cut(-21, 21, 15, 16, -21, 21, 5, 'wood_top');
  for (const r of [4, 8, 12, 16]) v.ring(-3 - r, -3 + r + 1, 15, 2 - r, 2 + r + 1, 'grain');
  v.box(-3, -2, 15, 16, 2, 3, 'pith');
  v.box(-2, 19, 15, 16, 2, 3, null); v.box(19, 22, 9, 16, 2, 3, null);           // drying crack down one face
  v.box(-12, 1, 14, 16, 16, 22, null); v.paint(-12, 1, 13, 14, 16, 22, 'chop');  // chopping notch, worn dark
  for (const [x, z] of [[-17, -11], [-16, -10], [-15, -11], [9, -14], [10, -13], [14, 8]]) v.paint(x, x + 1, 15, 16, z, z + 1, 'chop');
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

// ── Fence post: inside -2..2 x 0..21 x -2..2 (the navigation post envelope) ───
// A squared pole with a chopped two-step point and rope bands where rails meet.
export function fencePost() {
  const v = new Vox();
  v.box(-2, 2, 0, 18, -2, 2, 'bark');
  v.box(-2, 2, 18, 19, -2, 2, 'wood_top');
  v.box(-1, 1, 19, 21, -1, 1, 'bark'); v.paint(-1, 1, 20, 21, -1, 1, 'wood_top');
  v.paint(-2, -1, 2, 6, -2, 2, 'bark_light'); v.paint(1, 2, 10, 14, -2, 2, 'bark_light');
  for (const y of [6, 15]) { v.paint(-2, 2, y, y + 3, -2, 2, 'rope'); v.paint(-2, 2, y + 1, y + 2, -2, 2, 'rope_dark'); }
  return v;
}

// ── Fence rails: inside -8..8 x 5..18 x -2..2, rows Y7 and Y16 at Z0 ──────────
// Two split poles, riven face up, ends hidden in the posts.
export function fenceRails() {
  const v = new Vox();
  for (const y0 of [6, 15]) {
    v.cutX(-8, 8, y0, y0 + 3, -2, 1, 1, 'bark');
    v.paint(-8, 8, y0 + 2, y0 + 3, -1, 0, 'riven');
    v.paint(-6, -1, y0 + 2, y0 + 3, -1, 0, 'riven_dark');
  }
  return v;
}

// ── Gate leaf: inside -15..15 x 4..18 x -2..2; hinge post on -X ──────────────
// Two split rails and a diagonal brace between chopped stiles, lashed at joints.
export function gateLeaf() {
  const v = new Vox();
  v.cutZ(-15, -12, 4, 18, -2, 2, 1, 'bark'); v.cutZ(12, 15, 4, 18, -2, 2, 1, 'bark');
  v.paint(-15, -12, 17, 18, -2, 2, 'wood_top'); v.paint(12, 15, 17, 18, -2, 2, 'wood_top');
  for (const y0 of [5, 14]) { v.cutX(-12, 12, y0, y0 + 3, -1, 2, 1, 'bark'); v.paint(-12, 12, y0 + 2, y0 + 3, 0, 1, 'riven'); }
  for (let i = 0; i < 6; i++) v.box(-11 + i * 4, -7 + i * 4, 7 + i, 10 + i, -2, 0, 'wood_side');   // brace, hinge-low to latch-high
  for (const [x0, y0] of [[-15, 5], [-15, 14], [12, 5], [12, 14]]) { v.paint(x0, x0 + 3, y0, y0 + 3, -2, 2, 'rope'); v.paint(x0, x0 + 3, y0 + 1, y0 + 2, -2, 2, 'rope_dark'); }
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

// ── Log bridge: X -8..24, deck top at Y0 (cells Y-1), Z -(16s+22)..6 ─────────
// Four split logs, riven face up; the deck ends short so both ends settle into
// the banks; rope lashings bind the logs near each bank.
export function bridge(span) {
  const v = new Vox();
  const zA = -(16 * span + 22), zB = 6;
  const layers = [[-1, 0, 3], [-3, 0, 1], [-5, 1, 0], [-7, 2, 0], [-9, 3, 0]];   // [layer bottom, x inset, z shorten]
  for (const x0 of [-8, 0, 8, 16]) {
    for (const [y0, inset, cut] of layers) {
      const y1 = y0 === -1 ? 0 : y0 + 2;
      v.box(x0 + inset, x0 + 8 - inset, y0, y1, zA + cut, zB - cut, 'bark');
      for (const z of [zA + cut, zB - cut - 1]) v.paint(x0 + inset, x0 + 8 - inset, y0, y1, z, z + 1, 'wood_top');
    }
    v.paint(x0 + 1, x0 + 7, -1, 0, zA + 3, zB - 3, 'riven');
    for (let z = zA + 6, k = (x0 + 8) / 8; z < zB - 8; z += 13, k++) v.paint(x0 + 2 + (k % 3), x0 + 3 + (k % 3), -1, 0, z, z + 7, 'riven_dark');
  }
  for (const z0 of [-7, -16 * span - 11]) {
    v.paint(-8, 24, -1, 0, z0, z0 + 2, 'rope');
    v.paint(-8, -7, -5, 0, z0, z0 + 2, 'rope'); v.paint(23, 24, -5, 0, z0, z0 + 2, 'rope');
  }
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

// ── Bridge kit: X -12..12, Y 0..9, Z -6..6. Three split logs bound with rope ──
export function bridgeKit() {
  const v = new Vox();
  for (const [y0, z0, z1] of [[0, -6, 0], [0, 0, 6], [4, -3, 3]]) {
    v.cutX(-12, 12, y0, y0 + 4, z0, z1, 1, 'bark');
    v.paint(-12, 12, y0 + 3, y0 + 4, z0 + 1, z1 - 1, 'riven');
    for (const x of [-12, 11]) v.paint(x, x + 1, y0, y0 + 4, z0, z1, 'wood_top');
  }
  for (const x0 of [-7, 5]) { v.paint(x0, x0 + 2, 0, 9, -6, 6, 'rope'); v.box(x0, x0 + 2, 8, 9, -1, 1, 'rope_dark'); }
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

// ── Hearth: body inside -16..16 x 0..27 x -16..16; fire opening faces +Z ──────
// Squared stones in uneven courses on a hearthstone, crossed logs on the fire
// bed, soot above. The animated flame (X -5..5, Y 7..16, Z -2..5) stays clear.
export function hearth() {
  const v = new Vox();
  v.cut(-16, 16, 0, 3, -16, 16, 3, 'stone_dark');
  v.cut(-15, 15, 2, 3, -15, 15, 3, 'stone');
  const course = (y0, h, x0, x1, z0, z1, widths, axis, shift) => {
    let a = (axis === 'x' ? x0 : z0) - shift, i = 0;
    const end = axis === 'x' ? x1 : z1;
    while (a < end) {
      const w = widths[i % widths.length], lo = Math.max(a, axis === 'x' ? x0 : z0), hi = Math.min(a + w, end);
      const c = ['stone', 'stone_light', 'stone', 'stone_dark'][(i + shift) % 4];
      if (hi - lo >= 2) {
        if (axis === 'x') v.pillow(lo, hi, y0, y0 + h, z0, z1, 1, c); else v.pillow(x0, x1, y0, y0 + h, lo, hi, 1, c);
      }
      a += w; i++;
    }
  };
  // Back wall, full height, three courses
  course(3, 8, -16, 16, -16, -9, [10, 8, 14], 'x', 0);
  course(11, 8, -16, 16, -16, -9, [8, 12, 12], 'x', 4);
  course(19, 8, -15, 15, -15, -9, [12, 10, 8], 'x', 2);
  // Side walls step down toward the front
  for (const [x0, x1] of [[-16, -8], [8, 16]]) {
    course(3, 8, x0, x1, -9, 13, [9, 7, 8], 'z', 1);
    course(11, 7, x0, x1, -9, 9, [8, 10], 'z', 3);
    course(18, 4, x0 + 1, x1 - 1, -9, 3, [6, 6], 'z', 0);
  }
  // Lintel stone across the top of the opening
  v.pillow(-9, 9, 18, 22, -9, -2, 1, 'stone_light');
  // Fire bed: ash, two crossed logs with cut ends, charred centre; soot above
  v.cut(-7, 7, 3, 4, -8, 8, 2, 'ash');
  v.cutX(-7, 7, 4, 7, -2, 1, 1, 'bark'); v.paint(-7, -6, 4, 7, -2, 1, 'wood_top'); v.paint(6, 7, 4, 7, -2, 1, 'wood_top');
  v.cutZ(-2, 1, 5, 8, -7, 7, 1, 'bark_light'); v.paint(-2, 1, 5, 8, -7, -6, 'wood_top'); v.paint(-2, 1, 5, 8, 6, 7, 'wood_top');
  v.paint(-4, 4, 4, 8, -4, 4, 'char');
  v.cut(-5, 5, 4, 5, -5, 5, 2, 'ember');
  v.paint(-8, 8, 8, 27, -10, -9, 'soot');
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

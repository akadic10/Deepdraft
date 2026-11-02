// Hearthblock Tier 1 · Axe-Hewn furniture for the game (2026-10-20, doc 256).
// Same vocabulary as proposal.mjs: 1:16 cells, [x0,x1) ranges, ground at Y0,
// X right, Z toward the front. Each model keeps the existing in-game frame and
// the contact bounds written above it. Split, chopped and notched with an axe:
// bark stays on, ends step back like axe cuts, joints are notches and lashings.
// The fence's posts, rails and gate are peeled, as built logs are (doc 278).
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

// ── Fence post: inside -3..3 x 0..20 x -3..3, centred in its tile ────────────
// A peeled pole with trimmed corners and an earth-dark foot; its flat top shows its
// rings. One knot and one drying check. The rails go straight into it.
export function fencePost() {
  const v = new Vox();
  v.cut(-3, 3, 0, 20, -3, 3, 1, 'riven_dark');
  v.paint(-3, 3, 0, 2, -3, 3, 'bark');                                                   // the foot, darkened by the earth
  v.cut(-3, 3, 19, 20, -3, 3, 1, 'wood_top');                                            // end grain: one ring and the pith
  v.ring(-2, 1, 19, -2, 1, 'grain'); v.box(-1, 0, 19, 20, -1, 0, 'pith');
  v.paint(-3, -2, 9, 12, -1, 2, 'bark_light'); v.paint(-3, -2, 10, 11, 0, 1, 'bark');   // a knot, trimmed flush
  v.box(1, 2, 4, 9, 2, 3, null); v.box(0, 1, 9, 12, 2, 3, null);                         // a drying check down the front
  return v;
}

// ── Fence rails: inside -8..8 x 5..17 x -2..2, rows at Y5 and Y14 ─────────────
// Two split poles, peeled, the split face up; their ends go into the posts.
export function fenceRails() {
  const v = new Vox();
  for (const y0 of [5, 14]) {
    v.cutX(-8, 8, y0, y0 + 3, -2, 2, 1, 'riven_dark');
    v.paint(-8, 8, y0 + 2, y0 + 3, -1, 1, 'riven');
  }
  return v;
}

// ── Gate leaf: inside -13..12 x 3..18 x -2..3; hinge stile on -X at the post's face ──
// Peeled stiles with chopped tops, two split rails at the fence's heights and one brace
// laid over the front from the hinge's foot to the latch's head. Rope lashes the hinge
// stile and loops the latch, two pegs pin the brace, and a cell's gap at the latch shows
// the leaf swings free.
export function gateLeaf() {
  const v = new Vox();
  for (const x0 of [-13, 9]) {
    v.cutZ(x0, x0 + 3, 3, 18, -2, 2, 1, 'riven_dark');
    v.paint(x0, x0 + 3, 17, 18, -2, 2, 'wood_top');
  }
  for (const y0 of [5, 14]) {
    v.cutX(-10, 9, y0, y0 + 3, -2, 2, 1, 'riven_dark');
    v.paint(-10, 9, y0 + 2, y0 + 3, -1, 1, 'riven');
  }
  for (let i = 0; i < 9; i++) v.box(-10 + 2 * i, -8 + 2 * i, 7 + i, 9 + i, 2, 3, 'riven_dark');   // the brace
  for (const y0 of [5, 14]) { v.paint(-13, -10, y0, y0 + 3, -2, 2, 'rope'); v.paint(-13, -10, y0 + 1, y0 + 2, -2, 2, 'rope_dark'); }
  v.paint(9, 12, 14, 17, -2, 2, 'rope'); v.paint(9, 12, 15, 16, -2, 2, 'rope_dark');           // the latch loop
  v.box(-9, -8, 7, 8, 2, 3, 'bark_dark'); v.box(7, 8, 15, 16, 2, 3, 'bark_dark');              // pegs
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
// Three dried fish hang head down from cords looped round the pole: the chunky fish (big
// head, bead eye, deep body, fan tail) in coppery browns, redder than any wood, the belly
// split to show the dried flesh. Each loop rings the pole (y 24..28, z -2..2) one cell clear
// of it, so the part never shares a cell with the rack it is laid over.
export function dryingRackFish() {
  const v = new Vox();
  for (const [x0, cord] of [[-11, 1], [-3, 3], [5, 2]]) {
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

// ── Carpenter's bench: 3 x 1, inside -24..24 x 0..18 x -8..8, top at Y18 (doc 293) ──
// After the owner's picture of a log workbench: half of a great log, its round side down, hewn
// flat on top, on four thick round legs braced low with log rails, rails across both ends and
// long rails a little higher along both sides. The slab runs past the legs at both ends. Peeled,
// as built logs and fences are (doc 278): knots trimmed flush, drying checks, end grain at every
// cut, the feet darkened by the ground.
export function carpenterBench() {
  const v = new Vox();
  for (const [x0, z0] of [[-20, -7], [-20, 2], [15, -7], [15, 2]]) {
    v.cut(x0, x0 + 5, 0, 14, z0, z0 + 5, 1, 'riven_dark');            // a thick round leg
    v.paint(x0, x0 + 5, 0, 1, z0, z0 + 5, 'bark');                     // its foot, darkened by the ground
  }
  v.paint(-20, -19, 5, 8, -5, -4, 'pith'); v.paint(19, 20, 8, 11, 3, 5, 'pith');   // knots, trimmed flush
  v.box(-16, -15, 2, 6, 2, 3, null); v.box(16, 17, 7, 11, -7, -6, null);          // drying checks
  for (const x0 of [-19, 16]) {                                         // the end rails, round, through the legs
    v.cutZ(x0, x0 + 4, 3, 7, -8, 8, 1, 'riven_dark');
    for (const z of [-8, 7]) v.paint(x0, x0 + 4, 3, 7, z, z + 1, 'wood_top');
  }
  for (const z0 of [-6, 2]) {                                           // the long rails, a little higher
    v.cutX(-21, 21, 7, 11, z0, z0 + 4, 1, 'riven_dark');
    for (const x of [-21, 20]) v.paint(x, x + 1, 7, 11, z0, z0 + 4, 'wood_top');
  }
  v.box(-24, 24, 15, 18, -8, 8, 'riven_dark');                         // the slab, round side down
  v.box(-24, 24, 13, 15, -7, 7, 'riven_dark');
  v.box(-24, 24, 12, 13, -5, 5, 'riven_dark');
  v.paint(-24, 24, 17, 18, -8, 8, 'riven');                             // hewn flat on top
  for (const [x0, x1, z] of [[-22, -4, -5], [-1, 21, -1], [-17, 9, 3], [6, 22, 5]]) v.paint(x0, x1, 17, 18, z, z + 1, 'riven_dark');
  for (const [x, z] of [[-13, -3], [-12, -2], [10, 2], [11, 1]]) v.paint(x, x + 1, 17, 18, z, z + 1, 'chop');   // two old axe bites
  for (const x of [-24, 23]) {                                          // the end grain
    v.paint(x, x + 1, 12, 18, -8, 8, 'wood_top');
    v.paint(x, x + 1, 14, 15, -4, 4, 'grain'); v.paint(x, x + 1, 16, 17, -6, 6, 'grain');
    v.paint(x, x + 1, 13, 14, -1, 1, 'pith');
  }
  v.box(-24, -20, 16, 18, 7, 8, null); v.paint(-24, -20, 15, 16, 7, 8, 'riven_dark');   // a split at one end
  return v;
}

// ── Mason's bench: 3 x 1, inside -24..24 x 0..15 x -8..8, top at Y15 (doc 293) ──────
// A slab split from a bigger stone, never dressed, laid across two log stumps with their root
// flares, set in from the ends: an uneven top, chipped corners, a crack, stone chips at its foot.
// The stone is the Rough Stone's own grey (rough_stone roles); the stumps keep their bark.
export function masonBench() {
  const v = new Vox();
  for (const x0 of [-20, 12]) {
    v.cut(x0 - 1, x0 + 9, 0, 2, -5, 5, 3, 'bark_dark');                  // a root flare
    v.cut(x0, x0 + 8, 2, 11, -4, 4, 2, 'bark');                          // the stump
    v.box(x0 - 1, x0, 3, 9, -2, 1, 'bark_light'); v.box(x0 + 8, x0 + 9, 4, 8, 0, 2, 'bark_light');
  }
  v.cut(-24, 24, 11, 14, -7, 7, 2, 'rough_stone');                       // the slab
  v.cut(-23, 22, 14, 15, -6, 7, 2, 'rough_stone_light');                 // its top, uneven
  v.box(-20, -9, 14, 15, -6, -3, 'rough_stone_accent'); v.box(6, 18, 14, 15, 2, 6, 'rough_stone_accent');
  v.box(-6, 2, 14, 15, 3, 6, 'rough_stone_accent');
  v.paint(-24, 24, 11, 12, -7, 7, 'rough_stone_shade');
  v.box(21, 24, 13, 15, -7, -3, null); v.box(-24, -21, 13, 15, 3, 7, null);   // chipped corners
  v.box(8, 9, 11, 15, 6, 7, null); v.paint(9, 10, 12, 15, 6, 7, 'rough_stone_cleft');   // a crack
  v.paint(7, 10, 14, 15, -3, 6, 'rough_stone_cleft');
  for (const [x, z] of [[-4, 6], [0, -6], [4, 5], [-24, -6], [22, 6], [-9, -7]]) v.box(x, x + 1, 0, 1, z, z + 1, 'rough_stone_light');
  return v;
}

// ── Stone stool: X -8..8 (1 x 1), seat at Y14 like the log stool (doc 293, B) ────
// The Stonemason's first piece: one Rough Stone knocked square all the way down with the maul,
// in the Rough Stone's own greys (never recoloured by a wood). Its top is a little uneven, one
// corner a cell lower, and lumps are left on its sides.
export function stoneStool() {
  const v = new Vox();
  v.cut(-7, 7, 0, 13, -7, 7, 2, 'rough_stone');
  v.paint(-7, 7, 0, 2, -7, 7, 'rough_stone_shade');
  v.cut(-6, 6, 13, 14, -6, 6, 1, 'rough_stone_light');                  // the seat, knocked flat
  v.box(1, 6, 13, 14, -6, -1, null); v.paint(1, 6, 12, 13, -6, -1, 'rough_stone_light');   // one corner a cell lower
  v.box(-8, -7, 4, 9, -3, 2, 'rough_stone_accent'); v.box(7, 8, 6, 10, 0, 4, 'rough_stone_accent');   // lumps
  v.box(-2, 3, 3, 7, 7, 8, 'rough_stone_accent');
  v.paint(-4, -3, 13, 14, 1, 4, 'rough_stone_accent');
  return v;
}

// ── Tool rack: X -24..24 (3 x 1), its back on a wall at Z-8, hooks at Y39 (doc 294, B) ──
// The Carpenter's first piece and the first storage furniture: half a split log, its round back
// to the wall and its split face out, lashed to two wall pegs above it, with three stout pegs
// driven in, angled up. Tools hang from the pegs (the furniture's storage anchors).
export function toolRack() {
  const v = new Vox();
  const Y = 32, Z = -8;                                             // raised to the mount, against the wall
  v.cutX(-24, 24, Y, Y + 12, Z, Z + 4, 2, 'bark');
  v.box(-23, 23, Y + 1, Y + 11, Z + 3, Z + 4, 'riven');                    // the split face
  v.paint(-23, 23, Y + 1, Y + 2, Z + 3, Z + 4, 'riven_dark'); v.paint(-23, 23, Y + 10, Y + 11, Z + 3, Z + 4, 'riven_dark');
  v.paint(-18, 4, Y + 6, Y + 7, Z + 3, Z + 4, 'grain'); v.paint(-2, 20, Y + 3, Y + 4, Z + 3, Z + 4, 'grain');
  v.paint(-14, -6, Y + 8, Y + 9, Z + 3, Z + 4, 'grain');
  v.paint(-24, -23, Y, Y + 12, Z, Z + 4, 'wood_top'); v.paint(23, 24, Y, Y + 12, Z, Z + 4, 'wood_top');
  for (const x of [-21, 19]) {
    v.box(x, x + 2, Y + 12, Y + 14, Z, Z + 4, 'riven_dark'); v.paint(x, x + 2, Y + 12, Y + 14, Z + 3, Z + 4, 'wood_top');   // a wall peg
    v.box(x, x + 2, Y + 8, Y + 13, Z, Z + 5, 'rope'); v.paint(x, x + 2, Y + 10, Y + 11, Z, Z + 5, 'rope_dark');               // lashed to it
  }
  for (const x of [-17, -1, 15]) {                                         // stout pegs, angled up
    v.box(x, x + 2, Y + 4, Y + 6, Z + 4, Z + 7, 'riven_dark');
    v.box(x, x + 2, Y + 5, Y + 7, Z + 7, Z + 9, 'riven_dark'); v.paint(x, x + 2, Y + 5, Y + 7, Z + 8, Z + 9, 'wood_top');
    v.paint(x - 1, x + 3, Y + 3, Y + 7, Z + 3, Z + 4, 'chop');             // split where it was driven in
  }
  return v;
}

// ── Raw materials crate: X, Z -16..16 (2 x 2), its rim at Y9 (doc 294, A) ──────────
// The log crib: two courses of notched logs crossing at the corners, open on top. Each log's ends
// run 2 cells past the logs it crosses, within the footprint. Goods sit on the ground in its four
// quarters, at X and Z ±6 (the furniture's storage anchors), and show over the rim.
export function rawMaterialsCrate() {
  const v = new Vox();
  for (const z of [-14, 10]) {                                      // the first course, along X
    v.cutX(-16, 16, 0, 5, z, z + 4, 1, 'bark');
    v.paint(-16, -15, 0, 5, z, z + 4, 'wood_top'); v.paint(15, 16, 0, 5, z, z + 4, 'wood_top');
    v.paint(-12, -6, 2, 3, z, z + 1, 'bark_light'); v.paint(4, 9, 3, 4, z + 3, z + 4, 'bark_light');
  }
  for (const x of [-14, 10]) {                                      // the second, along Z, in notches
    v.cutZ(x, x + 4, 4, 9, -16, 16, 1, 'bark_dark');
    v.paint(x, x + 4, 4, 9, -16, -15, 'wood_top'); v.paint(x, x + 4, 4, 9, 15, 16, 'wood_top');
    v.paint(x, x + 4, 8, 9, -9, -3, 'bark'); v.paint(x, x + 4, 8, 9, 5, 11, 'bark');
  }
  for (const x of [-14, 10]) for (const z of [-14, 10]) v.paint(x, x + 4, 4, 5, z, z + 4, 'chop');   // the notches
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

// ── Hearth: fire-back, body inside -16..16 x 0..29 x -16..16; the fire faces +Z ──
// The owner's pick of four rudimentary concepts (2026-10-29, doc 279): an open fire on
// four flagstones against one upright stack of slabs that shields the wall and throws
// the heat back into the room, with low wing stones cradling the fire. No wood of its
// own: the night's log is the real good a worker sets on the ash. The animated flame
// (inside X -8..8, Y 8..22, Z -10..6) burns in front of the fire-back, below its top.
export function hearth() {
  const v = new Vox();
  // Hearthstone: four flagstones on a dark bed, their seams showing between them
  v.cut(-16, 16, 0, 2, -16, 16, 2, 'stone_dark');
  v.cut(-15, -1, 2, 3, -15, -1, 1, 'stone'); v.cut(1, 15, 2, 3, -15, -1, 1, 'stone_light');
  v.cut(-15, -1, 2, 3, 1, 15, 1, 'stone_light'); v.cut(1, 15, 2, 3, 1, 15, 1, 'stone');
  // Fire-back: three slabs, each narrower than the one below
  v.pillow(-15, 15, 3, 13, -16, -10, 1, 'stone');
  v.pillow(-12, 12, 13, 22, -16, -11, 1, 'stone_light');
  v.pillow(-7, 7, 22, 29, -15, -11, 1, 'stone');
  // Wing stones at the back corners, stepping down toward the room
  v.pillow(-16, -10, 3, 11, -10, -3, 1, 'stone_light'); v.pillow(-15, -10, 3, 7, -3, 3, 1, 'stone');
  v.pillow(10, 16, 3, 11, -10, -3, 1, 'stone'); v.pillow(10, 15, 3, 7, -3, 3, 1, 'stone_light');
  // Scorched flagstones around the ash, so the fire's own light does not wash them out
  v.paint(-10, 10, 2, 3, -10, 8, 'stone_dark');
  v.cut(-8, 8, 3, 4, -9, 6, 3, 'ash');
  v.paint(-3, 3, 3, 4, -5, 1, 'char');
  // Soot black around the fire, fading as it drifts up the fire-back
  v.paint(-6, 6, 3, 12, -11, -9, 'soot');
  v.paint(-5, 5, 13, 16, -12, -10, 'stone_dark');
  v.paint(-4, 3, 16, 19, -12, -10, 'stone_dark');
  v.paint(-3, 2, 19, 22, -12, -10, 'stone_dark');
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

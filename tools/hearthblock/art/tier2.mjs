// Tier 2 · the Carpenter's plank pieces (Hearthblock, sawn but plain).
//
// The Carpenter starts with a copper pull saw (owner, 2026-11-13: "the carpenter starts with a saw,
// therefore I think the initial set of items the carpenter can make don't need to be rudimentary
// anymore"). It saws a log into two planks and builds from them. The look agreed for that work is
// sawn, but plain: thick boards, pegs and saw-cut ends, as plain and thick as the copper tools
// themselves. No carving, no turned legs, no iron (nails, hinges, bands), no cloth or wool and no
// paint; fine joinery, such as a butterfly key, waits for the iron saw. Everything a Worker makes
// at camp stays hewn (tier1.mjs).
//
// The owner picked the table and the bench from one sheet on 2026-11-13 ("Dining Table, B / Bench,
// A"; tmp/plank_look_20261113/plank_look_sheet.png), and the tool rack, the pallet, the
// board-game table, the raw materials crate and the food shelf from the sheets that followed the
// same day ("Tool rack, A / Pallet, A / Game Board, A", then "Crate, A / Food shelf, A";
// tmp/plank_pieces_20261113/). Each takes the place of a Tier 1 piece, whose design stays in
// tier1.mjs (`splitSlabTable`, `logBench`, `toolRack`, `finishedGoodsPallet`, `gameTable`,
// `rawMaterialsCrate`, `foodShelf`) and in the art data, uninstalled. The Tier 2 study's own table
// and bed (`diningTable`, `bed` in proposal.mjs) are untouched.
//
// A sawn face is drawn one way on every plank piece and on the plank good
// (tools/voxel_assets/hearthblock_goods.py, plank()):
// - as pale as a log's cut end (`wood_top`), a step darker on a board's sides (`riven`), dark
//   underneath (`grain`);
// - the saw's strokes run across the board (`riven_dark`, three steps darker than the face, since
//   the sky's midday lifts a line one step darker out of sight), where a split face's lines run
//   along it; a stroke stops two cells short of both edges, so the board stays one piece;
// - a saw-cut end is plain end grain, paler than the sides. The plank good's end shows the log's
//   square ring; a row of those along a table's edge read as a carved key pattern;
// - pegs are knot-dark (`pith`), two cells square, cut flush;
// - neighbouring boards differ by a step of tone. At midday every pale face comes out one cream,
//   and that step, the dark seams and the pegs are what still tell the boards apart.
// These are the hewn palette's wood roles, so every piece recolours for pine, oak, juniper and
// applewood through `hand_hewn_timber`, as the Tier 1 furniture does.
//
// Cells are 1/16 block; ranges are [x0, x1); ground is Y0; a piece's origin is the middle of its
// footprint. Only box, paint and air are used: the game's data stores operations, not cells.
import { Vox } from './proposal.mjs';

// One sawn board, its face up at y1.
export function board(v, x0, x1, y0, y1, z0, z1) {
  v.box(x0, x1, y0, y1, z0, z1, 'riven');
  v.paint(x0, x1, y0, y0 + 1, z0, z1, 'grain');
  v.paint(x0, x1, y1 - 1, y1, z0, z1, 'wood_top');
}

// The saw-cut end of a board, on layer x (a board along X) or layer z (a board along Z): end
// grain over the board's dark underside. y0..y1 are the rows under the board's face.
export function sawnEndX(v, x, y0, y1, z0, z1) { v.paint(x, x + 1, y0 + 1, y1, z0, z1, 'wood_top'); }
export function sawnEndZ(v, z, y0, y1, x0, x1) { v.paint(x0, x1, y0 + 1, y1, z, z + 1, 'wood_top'); }

// The saw's strokes on a face at layer y: across a board that lies along X (lines along Z), or
// across one that lies along Z (lines along X).
export function strokesX(v, y, xs, z0, z1) { for (const x of xs) v.paint(x, x + 1, y, y + 1, z0 + 2, z1 - 2, 'riven_dark'); }
export function strokesZ(v, y, zs, x0, x1) { for (const z of zs) v.paint(x0 + 2, x1 - 2, y, y + 1, z, z + 1, 'riven_dark'); }

// A peg driven in from above and cut flush: two cells square on layer y.
export function peg(v, y, x, z) { v.paint(x, x + 2, y, y + 1, z, z + 2, 'pith'); }

// ── The plank tables' frame: two plank ends and two aprons, 46 x 19 x 46 under a top at Y19..24 ──
// Each end is one broad board on edge with the middle sawn out of its foot, so it stands on two
// feet; a board on edge under each long side ties the ends together and is pegged to them. Every
// cell stands inside the boxes the log tables had (data/furniture/dining_table.json and
// board_game_table.json: a leg at each corner, a bearer down each side, the top), so a table's
// collision and the leg room of whoever sits at it are unchanged. The dining table and the
// board-game table both stand on it.
export function plankFrame(v) {
  for (const x0 of [-22, 16]) {
    v.box(x0, x0 + 6, 0, 19, -23, 23, 'riven');
    v.box(x0, x0 + 6, 0, 12, -15, 15, null);                                // sawn out between the feet
    v.paint(x0, x0 + 6, 0, 1, -23, 23, 'grain'); v.paint(x0, x0 + 6, 12, 13, -15, 15, 'grain');
    for (const z of [-23, 22]) v.paint(x0, x0 + 6, 1, 19, z, z + 1, 'wood_top');           // its cut ends
    const face = x0 < 0 ? x0 : x0 + 5;                                      // the saw's strokes on its outer face
    v.paint(face, face + 1, 13, 18, -9, -8, 'riven_dark'); v.paint(face, face + 1, 14, 18, 6, 7, 'riven_dark');
    v.paint(face, face + 1, 2, 9, -19, -18, 'riven_dark'); v.paint(face, face + 1, 4, 11, 18, 19, 'riven_dark');
  }
  for (const z0 of [-22, 19]) {                                             // a board on edge under each long side
    v.box(-23, 23, 16, 19, z0, z0 + 3, 'riven'); v.paint(-23, 23, 16, 17, z0, z0 + 3, 'grain');
    for (const x of [-23, 22]) v.paint(x, x + 1, 16, 19, z0, z0 + 3, 'wood_top');
    const face = z0 < 0 ? z0 : z0 + 2;
    for (const x of [-20, 18]) v.paint(x, x + 2, 17, 19, face, face + 1, 'pith');          // pegged to the ends
  }
}
// The four boards of a plank table's top, along X, with a one-cell gap between them.
const TABLE_BOARDS = [[-23, -12], [-11, 0], [1, 12], [13, 23]];

// ── Plank dining table: 46 x 24 x 46, top at Y24, 3 x 3 footprint, the same 5 x 5 stool layout ──
// Boards on two plank ends (the owner's pick, B): the frame above, and four boards laid across it
// with a gap between them, each pegged down onto both ends.
export function plankTable() {
  const v = new Vox();
  plankFrame(v);
  const boards = TABLE_BOARDS;
  for (const [z0, z1] of boards) {
    board(v, -23, 23, 19, 24, z0, z1);
    for (const x of [-23, 22]) sawnEndX(v, x, 19, 23, z0, z1);
  }
  for (const [z0, z1] of [boards[1], boards[3]]) v.paint(-23, 23, 23, 24, z0, z1, 'riven');   // every other board a step darker
  for (const [z0, z1] of boards) for (const x of [-20, 18]) peg(v, 23, x, Math.floor((z0 + z1) / 2) - 1);
  for (const z of [-13, -11, -1, 1, 11, 13]) v.paint(-23, 23, 19, 23, z, z + 1, 'riven_dark');   // the gaps, dark inside
  strokesX(v, 23, [-8], -23, -12); strokesX(v, 23, [5], -11, 0);
  strokesX(v, 23, [-3], 1, 12); strokesX(v, 23, [9], 13, 23);
  return v;
}

// ── Plank board-game table: 46 x 25 x 46, top at Y24, six one-cell counters on it, 3 x 3 footprint ──
// The dining table with the game marked on it (the owner's pick, A; drawn 2026-11-13 in
// tmp/plank_pieces_20261113/crate_pallet_game). The same four boards on the same frame; the two
// middle boards stay pale, with no stroke of the saw, and a board of four squares by four is
// scratched across them in knot-dark lines, five cells to a square. Three of its lines are the
// gaps between the boards. Six counters, three cells square and one high, three of each colour,
// each standing in a square on solid wood and inside the definition's own box for them.
const COUNTERS = [[-10, -10, 'red'], [2, -10, 'red'], [-4, -4, 'red'], [8, 8, 'teal'], [-4, 8, 'teal'], [2, 2, 'teal']];
export function plankGameTable() {
  const v = new Vox();
  plankFrame(v);
  for (const [z0, z1] of TABLE_BOARDS) {
    board(v, -23, 23, 19, 24, z0, z1);
    for (const x of [-23, 22]) sawnEndX(v, x, 19, 23, z0, z1);
  }
  for (const [z0, z1] of [TABLE_BOARDS[0], TABLE_BOARDS[3]]) v.paint(-23, 23, 23, 24, z0, z1, 'riven');     // the two outer boards a step darker
  for (const [z0, z1] of TABLE_BOARDS) for (const x of [-20, 18]) peg(v, 23, x, Math.floor((z0 + z1) / 2) - 1);
  for (const z of [-13, -11, -1, 1, 11, 13]) v.paint(-23, 23, 19, 23, z, z + 1, 'riven_dark');   // the gaps, dark inside
  strokesX(v, 23, [-8], -23, -12); strokesX(v, 23, [9], 13, 23);             // the saw's strokes stay on the outer boards
  for (const g of [-12, -6, 0, 6, 12]) v.paint(g, g + 1, 23, 24, -12, 13, 'pith');        // the board: lines across the boards
  for (const g of [-6, 6]) v.paint(-12, 13, 23, 24, g, g + 1, 'pith');                    // and along them, between the gaps
  for (const [x, z, c] of COUNTERS) v.box(x, x + 3, 24, 25, z, z + 3, c);
  return v;
}

// ── Plank bench: 32 x 16 x 16, one broad seat at Y16, 2 x 1 footprint ──
// A board seat on two plank ends (the owner's pick, A), built the way the table is. Each end is a
// board on edge with a notch sawn out of its foot; a stretcher runs through both ends and a peg
// holds it outside each; the seat is two boards side by side, each pegged down onto both ends.
// The seam between the two boards is painted, not cut: the seat stays whole and level from end
// to end, which is what a sitting dwarf needs of it.
export function plankBench() {
  const v = new Vox();
  for (const x0 of [-13, 9]) {
    v.box(x0, x0 + 4, 0, 12, -7, 7, 'riven');
    v.box(x0, x0 + 4, 0, 4, -3, 3, null);                                   // the notch: two feet
    v.paint(x0, x0 + 4, 0, 1, -7, 7, 'grain'); v.paint(x0, x0 + 4, 4, 5, -3, 3, 'grain');
    for (const z of [-7, 6]) v.paint(x0, x0 + 4, 1, 12, z, z + 1, 'wood_top');
  }
  v.box(-15, 15, 5, 9, -1, 1, 'riven');                                     // the stretcher, through both ends
  v.paint(-15, 15, 8, 9, -1, 1, 'wood_top'); v.paint(-15, 15, 5, 6, -1, 1, 'grain');
  for (const x of [-15, 14]) v.paint(x, x + 1, 5, 9, -1, 1, 'wood_top');
  v.box(-14, -13, 3, 11, -1, 1, 'pith'); v.box(13, 14, 3, 11, -1, 1, 'pith');             // and the peg that holds it
  board(v, -16, 16, 12, 16, -8, 8);                                         // the seat: two boards
  for (const x of [-16, 15]) sawnEndX(v, x, 12, 15, -8, 8);
  v.paint(-16, 16, 15, 16, 1, 8, 'riven');                                  // the second board a step darker
  v.paint(-16, 16, 13, 16, 0, 1, 'riven_dark');                             // the seam between them
  for (const x of [-12, 10]) for (const z of [-5, 4]) peg(v, 15, x, z);     // a peg through each board into each end
  strokesX(v, 15, [-5], -8, 0); strokesX(v, 15, [4], 1, 8);
  return v;
}

// ── Plank finished goods pallet: 32 x 7 x 32, a level deck at Y7, 2 x 2 footprint ──
// The plain pallet (the owner's pick, A; drawn 2026-11-13 in tmp/plank_pieces_20261113/
// crate_pallet_game). Three runners on edge; four deck boards across them with two-cell gaps that
// show the dark underneath; each board pegged to each runner. The gaps are what keeps the deck
// readable under pale goods: a plank covers a gap, and the gap carries on past it. The deck is
// level at seven cells, where the definition's four quarters stand their goods.
export function plankPallet() {
  const v = new Vox();
  for (const [z0, z1] of [[-14, -11], [-2, 2], [11, 14]]) {                  // three runners along X
    v.box(-16, 16, 0, 4, z0, z1, 'riven'); v.paint(-16, 16, 0, 1, z0, z1, 'grain');
    for (const x of [-16, 15]) v.paint(x, x + 1, 1, 4, z0, z1, 'wood_top');
  }
  const boards = [[-16, -9], [-7, -1], [1, 7], [9, 16]];
  const strokes = [[-7, 6], [-9, 4], [-5, 8], [-8, 5]];
  boards.forEach(([x0, x1], i) => {
    board(v, x0, x1, 4, 7, -16, 16);
    for (const z of [-16, 15]) sawnEndZ(v, z, 4, 6, x0, x1);
    if (i % 2) v.paint(x0, x1, 6, 7, -16, 16, 'riven');                      // every other board a step darker
    for (const z of [-13, -1, 11]) peg(v, 6, Math.floor((x0 + x1) / 2) - 1, z);
    for (const z of strokes[i]) v.paint(x0 + 1, x1 - 1, 6, 7, z, z + 1, 'riven_dark');   // a stroke one cell short of each edge (strokesZ stops two short, which leaves two cells on a six-cell board)
  });
  for (const x of [-10, -7, -2, 1, 6, 9]) v.paint(x, x + 1, 4, 6, -16, 16, 'riven_dark');   // the gaps, dark inside
  return v;
}

// ── Plank tool rack: 48 x 12 x 9, hung on a wall with its underside at Y33, 3 x 1 footprint ──
// The peg rail (the owner's pick, A; drawn 2026-11-13 in tmp/plank_pieces_20261113/rack_shelf).
// One broad sawn board flat on the wall, its back at Z-8, two pegs through it into the wall, and
// three stout pegs for the tools. It hangs where the pegged log hung (its underside at Y33).

// The saw's strokes on a board's upright face (layer z), each [x, y0, y1]: across a board that
// runs along X, so they stand upright.
export function faceStrokes(v, z, strokes) { for (const [x, y0, y1] of strokes) v.paint(x, x + 1, y0, y1, z, z + 1, 'riven_dark'); }

// The three hooks: a stout peg driven into the face at layer `face` under each of the furniture's
// storage anchors (X -16, 0, 16; its top at Y39, where a hung tool's top is), tilted up a cell
// toward its tip so a tool stays on. Knot-dark to its end: a paler tip made it one cream with the
// board at midday.
export function hookPegs(v, face) {
  for (const hook of [-16, 0, 16]) {
    v.box(hook - 1, hook + 1, 36, 38, face, -1, 'pith');
    v.box(hook - 1, hook + 1, 37, 39, -1, 1, 'pith');
  }
}

export function plankToolRack() {
  const v = new Vox();
  v.box(-24, 24, 33, 45, -8, -4, 'riven');
  v.paint(-24, 24, 33, 34, -8, -4, 'grain');                               // dark underneath
  v.paint(-24, 24, 44, 45, -8, -4, 'wood_top');                            // its top edge
  for (const x of [-24, 23]) v.paint(x, x + 1, 34, 45, -8, -4, 'wood_top');   // saw-cut ends
  faceStrokes(v, -5, [[-21, 35, 42], [-5, 37, 43], [11, 35, 41], [21, 36, 43]]);
  for (const x of [-9, 7]) v.paint(x, x + 2, 41, 43, -5, -4, 'pith');      // pegged to the wall
  hookPegs(v, -4);
  return v;
}

// ── Plank raw materials crate: 32 x 13 x 32, open on top and inside, 2 x 2 footprint ──
// The open bin (the owner's pick, A of the crate's second sheet; drawn 2026-11-13 in
// tmp/plank_pieces_20261113/crate_pallet_game). The owner on the first sheet: "I don't think it
// needs connecting pieces through the middle". So nothing crosses the inside: a sawn post at each
// corner, two boards a side with a gap between them, each pegged through the post. No floor: the
// four goods stand together on the ground at the definition's own four places, in a space 24
// cells square, and show from above and through the gaps.

// One side of the post-and-board bin: boards on edge between two corner posts, along X at Z `at`
// or along Z at X `at`, three cells thick. `rows` are the boards' [y0, y1] from the ground up and
// `marks` the places of the saw's strokes on each. The gap over a lower board is dark inside; the
// top board's edge is the rim, a step darker than the posts' ends.
const BIN_ROWS = [[0, 5], [7, 12]];
export function binSide(v, along, at, rows, marks) {
  rows.forEach(([y0, y1], i) => {
    const edge = i === rows.length - 1 ? 'riven' : 'riven_dark';
    if (along === 'x') {
      board(v, -12, 12, y0, y1, at, at + 3);
      v.paint(-12, 12, y1 - 1, y1, at, at + 3, edge);
      for (const x of marks[i]) v.paint(x, x + 1, y0 + 1, y1 - 1, at, at + 3, 'riven_dark');
    } else {
      board(v, at, at + 3, y0, y1, -12, 12);
      v.paint(at, at + 3, y1 - 1, y1, -12, 12, edge);
      for (const z of marks[i]) v.paint(at, at + 3, y0 + 1, y1 - 1, z, z + 1, 'riven_dark');
    }
  });
}
// A sawn corner post, 13 cells high and a cell proud of the boards, with a peg through it into the
// end of each board it holds: `pegsX` are the heights of the pegs for the boards along X (driven
// through the post's outer X face), `pegsZ` for the boards along Z.
export function binPost(v, x0, z0, pegsX, pegsZ) {
  v.box(x0, x0 + 4, 0, 13, z0, z0 + 4, 'riven');
  v.paint(x0, x0 + 4, 0, 1, z0, z0 + 4, 'grain'); v.paint(x0, x0 + 4, 12, 13, z0, z0 + 4, 'wood_top');
  const fx = x0 < 0 ? x0 : x0 + 3, fz = z0 < 0 ? z0 : z0 + 3;
  for (const y of pegsX) v.paint(fx, fx + 1, y, y + 2, z0 + 1, z0 + 3, 'pith');
  for (const y of pegsZ) v.paint(x0 + 1, x0 + 3, y, y + 2, fz, fz + 1, 'pith');
}

export function plankCrate() {
  const v = new Vox();
  for (const z0 of [-15, 12]) binSide(v, 'x', z0, BIN_ROWS, [[-7, 5], [-3, 8]]);
  for (const x0 of [-15, 12]) binSide(v, 'z', x0, BIN_ROWS, [[-6, 7], [-9, 3]]);
  for (const x0 of [-16, 12]) for (const z0 of [-16, 12]) binPost(v, x0, z0, [2, 9], [2, 9]);
  return v;
}

// ── Plank food shelf: 48 x 40 x 16, two decks at Y12 and Y31, 3 x 1 footprint ──
// Two shelves between two plank ends (the owner's pick, A; drawn 2026-11-13 in
// tmp/plank_pieces_20261113/rack_shelf). Each end is one broad board on edge, a notch sawn out of
// its foot and its front corner sawn out above the upper shelf, which is six cells shallower than
// the lower, so both rows of crates show from above. The lower shelf is two boards, the upper
// one; each is pegged through the ends, and a board on edge under the back of the upper shelf ties
// the ends together. Crates stand at the definition's own six places: the upper row on Y31 at
// Z-3, the lower on Y12 at Z3, a whole deck under each.
export function plankFoodShelf() {
  const v = new Vox();
  for (const x0 of [-24, 21]) {
    v.box(x0, x0 + 3, 0, 40, -8, 8, 'riven');
    v.box(x0, x0 + 3, 31, 40, 2, 8, null);                                  // the corner sawn out above the upper shelf
    v.box(x0, x0 + 3, 0, 4, -4, 4, null);                                   // the notch: two feet
    v.paint(x0, x0 + 3, 0, 1, -8, 8, 'grain'); v.paint(x0, x0 + 3, 4, 5, -4, 4, 'grain');
    v.paint(x0, x0 + 3, 39, 40, -8, 2, 'wood_top'); v.paint(x0, x0 + 3, 30, 31, 2, 8, 'wood_top');   // its saw-cut tops
    const face = x0 < 0 ? x0 : x0 + 2;                                      // its outer face:
    for (const [y, z] of [[9, -5], [9, 3], [28, -6], [28, -1]]) v.paint(face, face + 1, y, y + 2, z, z + 2, 'pith');   // the shelves' pegs
    v.paint(face, face + 1, 17, 18, -6, 5, 'riven_dark'); v.paint(face, face + 1, 35, 36, -6, 0, 'riven_dark');      // the saw's strokes across it
    v.paint(face, face + 1, 23, 24, -2, 6, 'riven_dark');
  }
  v.box(-21, 21, 22, 27, -8, -5, 'riven'); v.paint(-21, 21, 22, 23, -8, -5, 'grain');   // the tie under the upper shelf's back
  board(v, -21, 21, 8, 12, -8, 8);                                          // the lower shelf: two boards
  v.paint(-21, 21, 11, 12, 1, 8, 'riven');                                  // the front one a step darker
  v.paint(-21, 21, 9, 12, 0, 1, 'riven_dark');                              // the seam between them
  strokesX(v, 11, [-8], -8, 0); strokesX(v, 11, [7], 1, 8);
  board(v, -21, 21, 27, 31, -8, 2);                                         // the upper shelf: one board
  strokesX(v, 30, [-8, 7], -8, 2);
  return v;
}

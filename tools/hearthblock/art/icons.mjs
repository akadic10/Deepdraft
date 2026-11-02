// Hearthblock UI icons: the dock set for the icon proof (doc 259, step 3, 2026-10-23).
// Each icon is an ordinary model on the 1:16 grid. The renderer turns it into a picture;
// icons are never placed in the world. Where an icon shows something the game already
// has, it replays the real model (the dwarf head, the log stool, the packed crate).
// Everything else uses the same box and notched-box vocabulary. Icons fill roughly a
// 32 x 32 x 32 cell volume, so the set renders at one cell density.
import * as P from './proposal.mjs';
import * as T from './tier1.mjs';
import * as D from './dwarves.mjs';
import * as W from './wildlife.mjs';
import * as S from './sky.mjs';

const { Vox } = P;

// A mirrored group's operations reflected across X = 0 (cell x becomes -x - 1).
const reflected = ops => ops.map(([op, a, c]) => [op, [-a[1], -a[0], ...a.slice(2)], c]);

// Replay another model's operations into v, shifted by whole cells, optionally renaming
// colours (`recolor`). A mirrored group shifted off X = 0 is written out as both of its
// sides; that is exact for groups of boxes and cut boxes, such as the dwarf head parts.
function replayInto(v, ops, [dx, dy, dz] = [0, 0, 0], recolor = {}) {
  for (const [op, a, raw] of ops) {
    const c = raw == null ? raw : (recolor[raw] ?? raw);
    if (op === 'mirror_x') {
      if (a.some(([inner]) => inner === 'mirror_x')) throw new Error('nested mirrored groups are not supported');
      if (dx) { replayInto(v, a, [dx, dy, dz], recolor); replayInto(v, reflected(a), [dx, dy, dz], recolor); }
      else v.both(s => replayInto(s, a, [0, dy, dz], recolor));
      continue;
    }
    const s = op === 'ring'
      ? [a[0] + dx, a[1] + dx, a[2] + dy, a[3] + dz, a[4] + dz]
      : [a[0] + dx, a[1] + dx, a[2] + dy, a[3] + dy, a[4] + dz, a[5] + dz, ...a.slice(6)];
    if (op === 'box') v.box(...s, c); else if (op === 'air') v.box(...s, null);
    else if (op === 'cutbox') v.cut(...s, c); else if (op === 'cutbox_x') v.cutX(...s, c);
    else if (op === 'cutbox_z') v.cutZ(...s, c); else if (op === 'paint') v.paint(...s, c);
    else if (op === 'ring') v.ring(...s, c);
    else throw new Error('unknown op ' + op);
  }
}

// Each icon may turn toward the 3/4 camera (`yaw` in degrees about Y), so a subject
// with a face shows it; the renderer reads the turn from the art data.
const icons = {};
const settings = {};
const define = (name, fn, options = {}) => { icons['icon/' + name] = fn; settings['icon/' + name] = options; };

// Orders: a pickaxe driven into a rough rock.
define('orders', v => {
  v.cut(-12, 12, 0, 11, -10, 10, 4, 'stone');
  v.cut(-10, 10, 11, 13, -8, 8, 4, 'stone_light');            // lit top
  v.cut(-12, 12, 0, 2, -10, 10, 4, 'stone_dark');             // dark foot
  v.paint(2, 3, 3, 8, 9, 10, 'stone_dark'); v.paint(3, 4, 7, 11, 9, 10, 'stone_dark');   // one crack
  v.cut(13, 17, 0, 3, 3, 8, 1, 'stone');                      // a chip knocked loose
  v.box(-1, 1, 8, 30, -1, 1, 'wood'); v.paint(0, 1, 13, 30, -1, 1, 'grain');
  v.box(-1, 1, 15, 18, -1, 1, 'tool_leather');                // grip wrap
  v.cut(-3, 3, 27, 33, -2, 2, 1, 'iron_dark');                // square socket
  v.box(-11, -3, 29, 32, -2, 2, 'iron'); v.box(3, 11, 29, 32, -2, 2, 'iron');
  v.box(-14, -11, 27, 30, -1, 1, 'iron'); v.box(11, 14, 27, 30, -1, 1, 'iron');
  v.box(-16, -14, 25, 28, -1, 1, 'steel'); v.box(14, 16, 25, 28, -1, 1, 'steel');
  v.paint(-11, 11, 31, 32, -2, 2, 'steel');                   // lit top edge
});

// Zones: marked storage ground with a packed crate and a log on it.
define('zones', v => {
  v.box(-16, 16, 0, 1, -16, 16, 'burlap_dark');
  v.box(-16, 16, 1, 2, -16, 16, 'burlap');
  for (let i = -16; i < 16; i += 5) {                         // dashed edge, like the zone outline
    v.paint(i, i + 3, 1, 2, -16, -15, 'zone_line'); v.paint(i, i + 3, 1, 2, 15, 16, 'zone_line');
    v.paint(-16, -15, 1, 2, i, i + 3, 'zone_line'); v.paint(15, 16, 1, 2, i, i + 3, 'zone_line');
  }
  replayInto(v, T.packedCrate().log, [-3, 2, -3]);
  v.cutX(-12, 6, 2, 7, 8, 13, 1, 'bark');                     // a log beside it
  v.paint(5, 6, 2, 7, 8, 13, 'wood_top'); v.paint(5, 6, 4, 5, 10, 11, 'pith');
});

// Rooms: a cutaway corner of a dug room, lit by a torch.
define('rooms', v => {
  v.box(-15, 15, 0, 2, -15, 15, 'stone_dark');
  v.box(-11, 15, 2, 3, -11, 15, 'riven');                     // a plank floor inside
  for (const x0 of [-7, 1, 9]) v.paint(x0, x0 + 1, 2, 3, -11, 15, 'riven_dark');
  v.box(-15, 15, 2, 27, -15, -11, 'stone');                   // back wall
  v.box(-15, -11, 2, 27, -11, 15, 'stone');                   // side wall
  v.paint(-15, 15, 26, 27, -15, 15, 'stone_light');           // lit wall tops
  for (const y of [9, 17]) { v.paint(-11, 15, y, y + 1, -11, -10, 'stone_dark'); v.paint(-11, -10, y, y + 1, -11, 15, 'stone_dark'); }
  v.box(-1, 1, 10, 18, -11, -9, 'wood_side');                 // torch on the back wall
  v.box(-2, 2, 15, 17, -11, -8, 'rope');
  v.box(-2, 2, 18, 21, -11, -7, 'flame_out');
  v.box(-1, 1, 21, 24, -10, -8, 'flame_mid');
  v.box(0, 1, 24, 25, -9, -8, 'flame_core');
});

// Construction: three dressed stone blocks and a mallet.
define('construction', v => {
  const block = (x0, y0, z0) => {
    v.cut(x0, x0 + 12, y0, y0 + 11, z0, z0 + 12, 1, 'stone');
    v.paint(x0, x0 + 12, y0 + 10, y0 + 11, z0, z0 + 12, 'stone_light');
    v.paint(x0, x0 + 12, y0, y0 + 1, z0, z0 + 12, 'stone_dark');
  };
  block(-14, 0, -8); block(-1, 0, -8); block(-8, 11, -8);
  v.cut(4, 14, 0, 6, 6, 13, 1, 'riven');                      // mallet head on the ground
  v.paint(4, 14, 5, 6, 6, 13, 'wood_top');
  v.box(8, 10, 6, 22, 8, 10, 'wood'); v.paint(8, 9, 6, 22, 8, 10, 'grain');
});

// Place: the log stool with a chunky arrow showing where it goes.
define('place', v => {
  replayInto(v, P.stool().log);
  v.box(-3, 3, 27, 36, -3, 3, 'arrow');
  v.box(-8, 8, 23, 27, -3, 3, 'arrow');
  v.box(-6, 6, 21, 23, -3, 3, 'arrow');
  v.box(-4, 4, 19, 21, -3, 3, 'arrow');
  v.box(-2, 2, 17, 19, -3, 3, 'arrow');
  v.paint(-3, 3, 35, 36, -3, 3, 'arrow_light'); v.paint(-8, 8, 26, 27, -3, 3, 'arrow_light');
  v.paint(-8, 8, 23, 24, -3, 3, 'arrow_dark'); v.paint(-2, 2, 17, 18, -3, 3, 'arrow_dark');
});

// Craft: a big stone hammer resting on a low work stump, chips on the top.
define('craft', v => {
  v.cut(-11, 11, 0, 2, -11, 11, 4, 'bark_dark');
  v.cut(-10, 10, 2, 8, -10, 10, 3, 'bark');
  for (const [x0, x1, y0, y1, z0, z1] of [[-11, -10, 3, 7, -4, 3], [10, 11, 3, 6, -2, 5], [-3, 4, 3, 7, 10, 11]]) v.box(x0, x1, y0, y1, z0, z1, 'bark_light');
  v.cut(-9, 9, 7, 8, -9, 9, 3, 'wood_top');
  v.ring(-4, 4, 7, -4, 4, 'grain');
  v.box(-15, 8, 8, 11, -1, 2, 'grain');                       // a long pale haft across the stump
  v.paint(-15, 8, 8, 9, -1, 2, 'wood');
  v.box(4, 8, 8, 12, -2, 3, 'rope');                          // lashing behind the head
  v.cut(8, 17, 6, 16, -4, 6, 1, 'stone');                     // a big squared stone head
  v.paint(8, 17, 15, 16, -4, 6, 'stone_light'); v.paint(8, 17, 6, 7, -4, 6, 'stone_dark');
  v.paint(12, 13, 9, 13, 5, 6, 'stone_dark');                 // one chip out of the face
  for (const [x, z] of [[-7, 5], [-4, -6], [-9, -2]]) v.box(x, x + 2, 8, 9, z, z + 1, 'wood_top');   // shavings
}, { yaw: -20 });

// Colony: a dwarf's head, built from the real head, eyes, brows, hair and beard. The
// swept cut keeps the silhouette compact, so the face stays large at small sizes.
define('colony', v => {
  for (const part of ['body/head_adult', 'body/eyes', 'eyebrows/brows_m_bushy', 'hair/hair_m_short_back', 'beards/beard_short_trimmed'])
    replayInto(v, D.build(part).log);
}, { yaw: 32 });

// Inventory: colony supplies, a stack of logs, a sack and a stone.
define('stocks', v => {
  const log = (y0, z0) => {
    v.cutX(-13, 13, y0, y0 + 7, z0, z0 + 7, 2, 'bark');
    v.paint(12, 13, y0, y0 + 7, z0, z0 + 7, 'wood_top'); v.paint(-13, -12, y0, y0 + 7, z0, z0 + 7, 'wood_top');
    v.paint(12, 13, y0 + 3, y0 + 4, z0 + 3, z0 + 4, 'pith');
  };
  log(0, -10); log(0, -3); log(6, -7);
  v.cut(2, 14, 0, 9, 4, 16, 3, 'burlap');                     // a tied sack
  v.paint(2, 14, 0, 2, 4, 16, 'burlap_dark');
  v.cut(4, 12, 9, 10, 6, 14, 3, 'burlap');
  v.box(6, 10, 10, 12, 8, 12, 'rope'); v.box(7, 9, 12, 14, 9, 11, 'burlap');
  v.cut(-12, -4, 0, 5, 7, 14, 2, 'stone'); v.paint(-12, -4, 4, 5, 7, 14, 'stone_light');
});

// Menu: a brass cog standing on its rim.
define('system', v => {
  v.cutZ(-11, 11, 2, 24, -2, 2, 6, 'brass');
  v.box(-3, 3, 24, 28, -2, 2, 'brass'); v.box(-3, 3, -2, 2, -2, 2, 'brass');
  v.box(-15, -11, 10, 16, -2, 2, 'brass'); v.box(11, 15, 10, 16, -2, 2, 'brass');
  for (const [x0, y0] of [[-12, 19], [8, 19], [-12, 3], [8, 3]]) v.box(x0, x0 + 4, y0, y0 + 4, -2, 2, 'brass');
  v.cutZ(-4, 4, 9, 17, -3, 3, 2, null);                       // axle hole
  v.paint(-11, 11, 23, 24, -2, 2, 'brass_light'); v.paint(-3, 3, 27, 28, -2, 2, 'brass_light');
  v.paint(-11, 11, 2, 4, -2, 2, 'brass_dark'); v.paint(-3, 3, -2, 0, -2, 2, 'brass_dark');
}, { yaw: 40 });

// Development: a stoppered flask of amber liquid.
define('development', v => {
  v.cut(-8, 8, -2, 0, -8, 8, 5, 'potion_dark');
  v.cut(-9, 9, 0, 13, -9, 9, 5, 'potion');
  v.cut(-8, 8, 13, 15, -8, 8, 5, 'glass');                    // shoulder
  v.box(-3, 3, 15, 25, -3, 3, 'glass');                       // neck
  v.box(-4, 4, 25, 27, -4, 4, 'glass_light');                 // lip
  v.box(-2, 2, 27, 31, -2, 2, 'bark_light');                  // cork
  v.paint(-9, 9, 12, 13, -9, 9, 'potion_light');              // liquid line
  v.paint(-6, -4, 3, 11, 8, 9, 'glass_light');                // shine on the glass
  v.box(3, 5, 6, 8, 8, 9, 'potion_light'); v.box(5, 6, 9, 10, 8, 9, 'potion_light');   // bubbles
});

// ── Time and view strip (bottom right) ───────────────────────────────────────
// Time and slice-step glyphs are chunky brass solids facing the camera, with lit tops
// and dark feet. The view toggles are blocks of ground.
function bar(v, x0, x1, y0, y1) {
  v.box(x0, x1, y0, y1, -2, 2, 'brass');
  v.paint(x0, x1, y1 - 1, y1, -2, 2, 'brass_light');
  v.paint(x0, x1, y0, y0 + 1, -2, 2, 'brass_dark');
}
// A stepped triangle pointing +X: `steps` columns, three cells wide, shrinking by four.
function pointRight(v, x0, steps) {
  for (let i = 0; i < steps; i++) bar(v, x0 + i * 3, x0 + i * 3 + 3, 2 * (i - steps), 2 * (steps - i));
}
// A stepped triangle pointing up (dir 1) or down (dir -1), rows three cells tall.
function pointVertical(v, y0, steps, dir) {
  for (let i = 0; i < steps; i++) {
    const half = (steps - i) * 3, y = dir > 0 ? y0 + i * 3 : y0 - (i + 1) * 3;
    v.box(-half, half, y, y + 3, -2, 2, 'brass');
    v.paint(-half, half, y + 2, y + 3, -2, 2, 'brass_light');
  }
}
const FACE = { yaw: 40 };
define('pause', v => { bar(v, -7, -2, -9, 9); bar(v, 2, 7, -9, 9); }, FACE);
define('play', v => pointRight(v, -6, 4), FACE);
define('fast', v => { pointRight(v, -10, 3); pointRight(v, 0, 3); }, FACE);
define('up_one', v => pointVertical(v, 0, 3, 1), FACE);
define('up_four', v => { pointVertical(v, 0, 3, 1); pointVertical(v, 11, 3, 1); }, FACE);
define('down_one', v => pointVertical(v, 0, 3, -1), FACE);
define('down_four', v => { pointVertical(v, 0, 3, -1); pointVertical(v, -11, 3, -1); }, FACE);

// Slice: a block of ground cut through, its grassy top lifted off the bright cut face.
define('slice', v => {
  v.box(-9, 9, 0, 9, -9, 9, 'earth');
  v.paint(-9, 9, 0, 3, -9, 9, 'stone'); v.paint(-9, 9, 0, 1, -9, 9, 'stone_dark');
  v.paint(-4, -2, 3, 5, 8, 9, 'stone');                       // a stone poking into the earth
  v.box(-9, 9, 9, 10, -9, 9, 'zone_line');                    // the cut face
  v.box(-9, 9, 13, 16, -9, 9, 'earth');                       // the lifted top
  v.box(-9, 9, 16, 18, -9, 9, 'grass'); v.paint(-9, 9, 17, 18, -9, 9, 'grass_light');
  v.paint(-9, 9, 13, 14, -9, 9, 'earth_dark');
});

// X-ray: a block of mountain seen through, its edges in the x-ray cyan, a lit room inside.
define('xray', v => {
  for (const x of [-10, 8]) for (const z of [-10, 8]) v.box(x, x + 2, 0, 20, z, z + 2, 'xray');
  for (const y of [0, 18]) {
    for (const z of [-10, 8]) v.box(-10, 10, y, y + 2, z, z + 2, 'xray');
    for (const x of [-10, 8]) v.box(x, x + 2, y, y + 2, -10, 10, 'xray');
  }
  v.paint(-10, 10, 19, 20, -10, 10, 'xray_light');
  v.box(-8, 8, 0, 2, -8, 8, 'stone'); v.paint(-8, 8, 1, 2, -8, 8, 'stone_light');   // a dug floor
  v.box(-7, 1, 2, 4, -6, 0, 'riven'); v.paint(-7, 1, 3, 4, -6, 0, 'hay');           // a bed of hay
  v.box(3, 5, 2, 7, -6, -4, 'wood_side');                                            // a torch
  v.box(2, 6, 7, 9, -7, -3, 'flame_out'); v.box(3, 5, 9, 11, -6, -4, 'flame_mid');
});

// ── Orders shelf, also the world markers over ordered trees, plants and stones ─────
// One icon per order. The markers reuse them, so a marked tree shows the same picture
// as the tool that marked it. Uproot has no Orders tool; it is the object panel's action.

// Mine blocks: a cube of rock in four seams, its corner block struck out and a pick
// swinging down at the gap. The pick is drawn in steps, facing the camera.
define('mine', v => {
  v.box(-13, 3, 0, 16, -8, 8, 'stone');
  v.paint(-13, 3, 15, 16, -8, 8, 'stone_light');              // lit top
  v.paint(-13, 3, 0, 1, -8, 8, 'stone_dark');                 // dark foot
  v.paint(-5, -4, 0, 16, -8, 8, 'stone_dark');                // the block seams
  v.paint(-13, 3, 7, 8, -8, 8, 'stone_dark');
  v.paint(-13, 3, 0, 16, 0, 1, 'stone_dark');
  v.box(-4, 3, 8, 16, 1, 8, null);                            // the struck-out block
  v.paint(-4, 3, 7, 8, 1, 8, 'stone_light');                  // the floor it left
  v.cut(5, 12, 0, 7, 0, 7, 1, 'stone');                       // fallen beside it, with chips
  v.paint(5, 12, 6, 7, 0, 7, 'stone_light');
  v.box(13, 15, 0, 2, 4, 6, 'stone_light'); v.box(-16, -14, 0, 2, 3, 5, 'stone');
  for (const [x0, x1, y0, y1, c] of [[-13, -10, 18, 21, 'steel'], [-10, -6, 20, 23, 'iron_dark'], [-6, 0, 21, 25, 'iron_dark'],
    [0, 4, 19, 23, 'iron_dark'], [3, 6, 16, 20, 'iron_dark'], [4, 7, 13, 17, 'steel']]) v.box(x0, x1, y0, y1, 3, 6, c);   // the head
  v.paint(-10, 0, 24, 25, 3, 6, 'steel');                     // lit top edge
  for (let i = 0; i < 6; i++) v.box(-4 + 2 * i, -1 + 2 * i, 24 + 2 * i, 27 + 2 * i, 3, 6, i < 4 ? 'wood' : 'tool_leather');   // haft
}, { yaw: 40 });

// Chop trees: an oak with an axe bitten into its trunk, chips at the foot.
define('chop', v => {
  v.cut(-7, 7, 0, 2, -7, 7, 3, 'bark_dark');                  // root flare
  v.cut(-5, 5, 0, 17, -5, 5, 2, 'bark');
  for (const [x0, z0] of [[-5, -1], [-1, 4], [4, 0]]) v.paint(x0, x0 + 1, 2, 16, z0, z0 + 1, 'bark_light');
  v.cut(-11, 11, 14, 18, -11, 11, 4, 'leafy_dark');           // crown: dark skirt, body, lit cap
  v.cut(-10, 10, 18, 24, -10, 10, 4, 'leafy');
  v.cut(-6, 6, 24, 27, -6, 6, 3, 'leafy_light');
  v.box(3, 5, 3, 11, -2, 3, null);                            // the axe's bite, pale inside
  v.paint(2, 3, 3, 11, -2, 3, 'riven');
  v.box(2, 8, 3, 12, -1, 2, 'iron_dark');                     // a broad axe head, edge in the wood
  v.box(2, 4, 3, 12, -1, 2, 'steel');
  v.box(8, 21, 6, 9, -1, 2, 'wood'); v.paint(8, 21, 8, 9, -1, 2, 'grain');
  v.box(17, 21, 6, 9, -1, 2, 'tool_leather');
  for (const [x, z] of [[7, 5], [11, 2], [4, 9]]) v.box(x, x + 2, 0, 1, z, z + 2, 'riven');   // chips
});

// Clear stones: two boulders and a scatter of scree, a maul standing beside them.
define('clear_stones', v => {
  v.cut(-13, 3, 0, 9, -11, 5, 4, 'stone');                    // the big boulder, rounded in tiers
  v.cut(-12, 2, 9, 12, -10, 4, 4, 'stone');
  v.cut(-10, 0, 12, 14, -8, 2, 3, 'stone_light');
  v.paint(-13, 3, 0, 1, -11, 5, 'stone_dark');
  v.paint(-4, -3, 3, 9, 4, 5, 'stone_dark');                  // a crack in its face
  v.cut(1, 11, 0, 6, -6, 4, 3, 'stone');                      // a smaller one behind
  v.cut(2, 10, 6, 8, -5, 3, 3, 'stone_light');
  for (const [x, z, c] of [[-9, 8, 'stone'], [-5, 11, 'stone_light'], [-1, 8, 'stone'], [1, 12, 'stone_dark'], [-12, 11, 'stone_light']])
    v.box(x, x + 3, 0, 2, z, z + 3, c);                       // scree
  v.box(5, 13, 0, 6, 7, 13, 'iron_dark');                     // the maul, head down
  v.paint(5, 13, 5, 6, 7, 13, 'iron');
  v.box(8, 10, 6, 22, 9, 11, 'wood'); v.paint(8, 9, 6, 22, 9, 11, 'grain');
  v.box(8, 10, 18, 22, 9, 11, 'tool_leather');
});

// Harvest plants: a wicker basket heaped with blue and red berries, a leafy sprig.
define('harvest_plants', v => {
  v.cut(-11, 11, 0, 12, -9, 9, 3, 'rope');
  for (const y of [2, 5, 8]) v.paint(-11, 11, y, y + 1, -9, 9, 'rope_dark');   // weave
  for (let x = -9; x < 11; x += 4) v.paint(x, x + 1, 0, 12, -9, 9, 'rope_dark');
  v.cut(-12, 12, 11, 13, -10, 10, 4, 'bark_light');           // rim
  v.cut(-9, 9, 4, 13, -7, 7, 2, null);
  v.box(-8, 8, 4, 12, -6, 6, 'berry_blue_dark');              // the heap, rounded in tiers
  v.cut(-8, 8, 12, 14, -6, 6, 3, 'berry_blue');
  v.cut(-6, 6, 14, 16, -4, 4, 2, 'berry_blue');
  v.cut(-3, 3, 16, 18, -2, 2, 1, 'berry_blue_light');
  for (const [x, y, z] of [[-7, 12, 2], [3, 13, 3], [-2, 16, -1], [5, 12, -4], [-1, 14, 3], [-5, 14, -3]]) v.box(x, x + 2, y, y + 2, z, z + 2, 'berry_red');
  for (const [x, y, z] of [[-4, 15, 1], [2, 15, -2], [6, 12, 2]]) v.box(x, x + 2, y, y + 2, z, z + 2, 'berry_blue_light');
  v.box(-9, -4, 13, 21, -7, -3, 'bush');                      // a sprig behind the heap
  v.box(-8, -5, 21, 23, -6, -4, 'bush_light'); v.box(-11, -8, 16, 19, -5, -2, 'bush_light');
});

// Clear plants: a tuft of reed stalks, two of them cut, beside a sickle held blade up.
define('clear_plants', v => {
  v.cut(-14, 0, 0, 2, -7, 7, 3, 'earth');
  for (const [x, z, h] of [[-11, -3, 16], [-8, 1, 13], [-5, -4, 18], [-3, 2, 11], [-9, -6, 9]]) {
    v.box(x, x + 2, 2, 2 + h, z, z + 2, 'stalk'); v.paint(x, x + 2, h, 2 + h, z, z + 2, 'stalk_light');
  }
  for (const [x, z] of [[-12, 3], [-6, 4]]) v.box(x, x + 2, 2, 4, z, z + 2, 'stalk_dry');   // cut stubs
  v.box(-10, 0, 2, 4, 6, 8, 'stalk_dry');                     // a cut stalk lying down
  for (let i = 0; i < 4; i++) v.box(8 + 2 * i, 11 + 2 * i, 6 - 2 * i, 9 - 2 * i, -1, 1, i < 2 ? 'wood' : 'tool_leather');   // handle
  for (const [x0, x1, y0, y1] of [[4, 10, 8, 12], [2, 6, 11, 16], [1, 5, 15, 20], [3, 8, 19, 23], [7, 12, 21, 24], [11, 14, 19, 22]])
    v.box(x0, x1, y0, y1, -1, 1, 'steel');                    // the crescent blade, tip forward
  v.paint(1, 5, 15, 20, -1, 1, 'iron'); v.paint(2, 6, 11, 14, -1, 1, 'iron');   // its back, darker
}, { yaw: 40 });

// Cancel orders: an order scroll struck through with a red cross.
define('cancel', v => {
  v.box(-9, 9, 4, 24, -1, 1, 'linen');
  v.cutX(-10, 10, 22, 28, -3, 3, 2, 'linen_dark');            // top and bottom rolls
  v.cutX(-10, 10, 0, 6, -3, 3, 2, 'linen_dark');
  v.paint(-10, -9, 0, 28, -3, 3, 'parchment_edge'); v.paint(9, 10, 0, 28, -3, 3, 'parchment_edge');
  for (let i = -4; i <= 4; i++) {
    v.box(i * 2 - 1, i * 2 + 2, 13 + i * 2, 16 + i * 2, 1, 3, 'apple');
    v.box(i * 2 - 1, i * 2 + 2, 13 - i * 2, 16 - i * 2, 1, 3, 'apple');
  }
  v.paint(-9, 10, 4, 6, 2, 3, 'apple_dark');                  // shade the lower ends
}, { yaw: 40 });

// Uproot (world marker; the object panel's Uproot): a berry bush lifted out of its hole,
// root ball and all, beside a brass arrow pointing up.
define('uproot', v => {
  v.cut(-14, 8, 0, 2, -11, 11, 4, 'earth');
  v.paint(-8, 2, 1, 2, -5, 5, 'earth_dark');                  // the hole it left
  for (const [x, z] of [[-5, -2], [-2, 2], [0, -3], [-4, 2]]) v.box(x, x + 1, 3, 8, z, z + 1, 'bark_light');   // roots
  v.box(-6, -1, 4, 5, 1, 2, 'bark_light'); v.box(-1, 2, 5, 6, -3, -2, 'bark_light');
  v.cut(-7, 2, 7, 11, -4, 4, 2, 'earth');                     // root ball
  v.cut(-11, -1, 10, 17, -6, 3, 2, 'bush');                   // the bush: square clumps, as in the world
  v.cut(-4, 5, 10, 16, -2, 6, 2, 'bush');
  v.cut(-8, 2, 16, 21, -4, 4, 2, 'bush_light');
  v.paint(-11, 5, 10, 11, -6, 6, 'bush_dark');
  for (const [x, y, z] of [[-10, 14, 2], [3, 13, 5], [-2, 18, 3], [4, 11, 1], [-6, 17, 3], [-1, 12, 5]]) v.box(x, x + 2, y, y + 2, z, z + 1, 'berry_blue');
  v.box(10, 14, 6, 21, -2, 2, 'brass');                       // the arrow: a stem and a stepped head
  for (const [half, y] of [[8, 21], [6, 23], [4, 25], [2, 27]]) v.box(12 - half, 12 + half, y, y + 2, -2, 2, 'brass');
  v.paint(10, 14, 6, 7, -2, 2, 'brass_dark');
  for (const [half, y] of [[8, 22], [6, 24], [4, 26], [2, 28]]) v.paint(12 - half, 12 + half, y, y + 1, -2, 2, 'brass_light');
}, { yaw: 25 });

// ── Zones and Construction ─────────────────────────────────────────────────────
// The zone tools stand on marked ground with the zone's dashed edge, like the dock's
// Zones icon. The construction tools show what they build.

// Marked ground: a slab with a dashed edge, as the zone outline in the world.
function zoneGround(v, base, top) {
  v.box(-16, 16, 0, 1, -16, 16, base);
  v.box(-16, 16, 1, 2, -16, 16, top);
  for (let i = -16; i < 16; i += 5) {
    v.paint(i, i + 3, 1, 2, -16, -15, 'zone_line'); v.paint(i, i + 3, 1, 2, 15, 16, 'zone_line');
    v.paint(-16, -15, 1, 2, i, i + 3, 'zone_line'); v.paint(15, 16, 1, 2, i, i + 3, 'zone_line');
  }
}

// A log lying along X, `d` cells thick, its cut ends showing.
function logX(v, x0, x1, y0, z0, d = 6) {
  v.cutX(x0, x1, y0, y0 + d, z0, z0 + d, 2, 'bark');
  v.paint(x0, x0 + 1, y0, y0 + d, z0, z0 + d, 'wood_top'); v.paint(x1 - 1, x1, y0, y0 + d, z0, z0 + d, 'wood_top');
  v.paint(x1 - 1, x1, y0 + d / 2 - 1, y0 + d / 2 + 1, z0 + d / 2 - 1, z0 + d / 2 + 1, 'pith');
}

// Storage: a stockpile on marked ground, a pyramid of logs, rough stone and a tied sack.
define('storage_zone', v => {
  zoneGround(v, 'burlap_dark', 'burlap');
  logX(v, -14, 4, 2, -14, 8); logX(v, -14, 4, 2, -6, 8); logX(v, -14, 4, 10, -10, 8);
  v.cut(6, 15, 2, 10, -14, -5, 1, 'stone'); v.paint(6, 15, 9, 10, -14, -5, 'stone_light');
  v.cut(8, 13, 10, 14, -12, -7, 1, 'stone'); v.paint(8, 13, 13, 14, -12, -7, 'stone_light');
  v.cut(-1, 11, 2, 15, 3, 15, 3, 'linen'); v.paint(-1, 11, 2, 4, 3, 15, 'linen_dark');
  v.cut(1, 9, 15, 16, 5, 13, 2, 'linen');
  v.box(3, 7, 16, 18, 7, 11, 'rope'); v.box(2, 8, 18, 20, 6, 12, 'linen');
});

// Farming (planned): tilled ridges on marked ground, sprouts along them, a crop ripening.
define('farming_zone', v => {
  zoneGround(v, 'earth_dark', 'earth_dark');
  for (const x0 of [-11, -3, 5]) {
    v.cut(x0 - 2, x0 + 2, 2, 4, -14, 14, 1, 'earth'); v.paint(x0 - 2, x0 + 2, 3, 4, -14, 14, 'earth_light');
    for (const z of [-10, -3, 4, 11]) {
      v.box(x0 - 1, x0 + 1, 4, 7, z - 1, z + 1, 'stalk');
      v.box(x0 - 3, x0 + 3, 6, 8, z - 1, z + 1, 'stalk_light');
    }
  }
  v.cut(10, 15, 2, 4, -14, 14, 1, 'earth'); v.paint(10, 15, 3, 4, -14, 14, 'earth_light');
  for (const z of [-9, 1, 9]) {                              // the ripening crop
    v.box(12, 14, 4, 14, z, z + 2, 'stalk');
    v.cut(11, 15, 14, 20, z - 1, z + 3, 1, 'hay'); v.paint(11, 15, 19, 20, z - 1, z + 3, 'straw');
  }
});

// Animal pasture (planned): grass on marked ground, a corner of the game's log fence,
// and a pile of hay.
define('animal_pasture', v => {
  zoneGround(v, 'earth', 'grass');
  for (const [x, z] of [[-6, -6], [-2, 7], [8, -2], [-11, 10]]) v.paint(x, x + 4, 1, 2, z, z + 3, 'grass_light');
  replayInto(v, T.fencePost().log, [-13, 2, -13]);
  replayInto(v, T.fencePost().log, [3, 2, -13]);
  replayInto(v, T.fenceRails().log, [-5, 2, -13]);
  replayInto(v, T.fencePost().log, [-13, 2, 3]);
  for (const y0 of [7, 16]) {                                // rails along the left side
    v.cutZ(-15, -11, y0, y0 + 3, -10, 0, 1, 'riven_dark');
    v.paint(-14, -12, y0 + 2, y0 + 3, -10, 0, 'riven');
  }
  v.cut(1, 13, 2, 8, 1, 13, 4, 'hay');                       // a pile of hay
  v.cut(3, 11, 8, 11, 3, 11, 3, 'hay_light'); v.cut(5, 9, 11, 12, 5, 9, 1, 'straw');
  for (const [x, z] of [[0, 8], [13, 5], [6, 13]]) v.box(x, x + 2, 2, 3, z, z + 1, 'straw');
});

// Fishing (doc 289): a marked earth bank beside open water. The dwarves' peeled rod rests
// on a forked stick and reaches out over the water, and a perch hangs from its line, just
// caught.
// The caught perch lies along +X, hung by its mouth at X 0: swapping X for Y (and turning Y
// down) stands it on end, head up, so its edges along X now run along Y.
function hangInto(v, ops, [dx, dy, dz]) {
  for (const [op, a, c] of ops) {
    const s = [a[2] + dx, a[3] + dx, -a[1] + dy, -a[0] + dy, a[4] + dz, a[5] + dz, ...a.slice(6)];
    if (op === 'box') v.box(...s, c); else if (op === 'paint') v.paint(...s, c);
    else if (op === 'cutbox_x') v.cut(...s, c);
    else throw new Error('hangInto: unsupported op ' + op);
  }
}
define('fishing_zone', v => {
  v.box(-16, -1, 0, 2, -16, 16, 'earth_dark');                // the bank, a cell above the water
  v.box(-16, -1, 2, 3, -16, 16, 'earth');
  for (const [x, z] of [[-14, -12], [-9, 9], [-5, -8], [-13, 4]]) v.box(x, x + 3, 3, 4, z, z + 2, 'grass');
  for (let i = -16; i < 16; i += 5) {                         // its dashed zone edge
    v.paint(-16, -15, 2, 3, i, i + 3, 'zone_line'); v.paint(-2, -1, 2, 3, i, i + 3, 'zone_line');
  }
  for (let i = -16; i < -1; i += 5) {
    v.paint(i, Math.min(i + 3, -1), 2, 3, -16, -15, 'zone_line'); v.paint(i, Math.min(i + 3, -1), 2, 3, 15, 16, 'zone_line');
  }
  v.box(-1, 16, 0, 1, -16, 16, 'water_dark');                 // the open water
  v.box(-1, 16, 1, 2, -16, 16, 'water');
  for (const [x0, x1, z0, z1] of [[6, 14, -3, -2], [6, 14, 3, 4], [6, 7, -2, 3], [13, 14, -2, 3], [1, 4, 9, 10], [10, 14, -11, -10]]) {
    v.paint(x0, x1, 1, 2, z0, z1, 'water_light');              // rings where the fish left the water
  }
  v.box(-5, -3, 3, 11, -1, 1, 'rod_bark');                    // the forked stick
  v.box(-6, -5, 9, 13, -1, 1, 'rod_bark'); v.box(-3, -2, 9, 13, -1, 1, 'rod_bark');
  for (let i = 0; i <= 10; i++) {                             // the rod, rising over the water
    v.box(-12 + 2 * i, -10 + 2 * i, 3 + 2 * i, 5 + 2 * i, -1, 1, i < 2 ? 'rod_bark' : 'rod_wood');
  }
  v.paint(-4, -2, 11, 13, -1, 1, 'rope');                     // lashed where it rests
  v.box(9, 10, 18, 23, 0, 1, 'rod_line');                     // the line
  hangInto(v, D.build('tools/caught_perch').log, [5, 18, 0]);
});

// Build's materials (doc 273): one block of each across x0..x1, y0..y1, z0..z1, dressed as
// the terrain shader draws it. The camera sees the top and the +x and +z faces.

// Stone: two courses with staggered joints, its top lit.
function stoneCube(v, x0, x1, y0, y1, z0, z1) {
  const mid = Math.round((y0 + y1) / 2);
  v.cut(x0, x1, y0, y1, z0, z1, 1, 'stone');
  v.paint(x0, x1, y1 - 1, y1, z0, z1, 'stone_light');
  v.paint(x0, x1, y0, y0 + 1, z0, z1, 'stone_dark');
  v.paint(x0, x1, mid, mid + 1, z0, z1, 'stone_dark');                      // a course line
  const jx = Math.round(x0 + (x1 - x0) * 0.45), jz = Math.round(z0 + (z1 - z0) * 0.6);
  v.paint(jx, jx + 1, y0, mid, z1 - 1, z1, 'stone_dark');                    // staggered joints
  v.paint(x1 - 1, x1, mid, y1 - 1, jz, jz + 1, 'stone_dark');
}

// Earth with two-cell flecks; `grassy` gives it a grass top with a ragged lip.
function earthCube(v, x0, x1, y0, y1, z0, z1, grassy) {
  const w = x1 - x0, h = y1 - y0, d = z1 - z0, lip = Math.max(2, Math.round(h / 6));
  v.cut(x0, x1, y0, y1, z0, z1, 1, 'earth');
  v.paint(x0, x1, y0, y0 + 1, z0, z1, 'earth_dark');
  for (const [fx, fy] of [[0.2, 0.2], [0.6, 0.45], [0.35, 0.65]]) {
    const x = Math.round(x0 + w * fx), y = Math.round(y0 + (h - lip) * fy);
    v.paint(x, x + 2, y, y + 2, z1 - 1, z1, 'earth_dark');
  }
  for (const [fz, fy] of [[0.3, 0.35], [0.7, 0.15]]) {
    const z = Math.round(z0 + d * fz), y = Math.round(y0 + (h - lip) * fy);
    v.paint(x1 - 1, x1, y, y + 2, z, z + 2, 'earth_light');
  }
  if (!grassy) {
    v.paint(x0, x1, y1 - 1, y1, z0, z1, 'earth_light');
    return;
  }
  v.paint(x0, x1, y1 - lip, y1, z0, z1, 'grass');
  v.paint(x0, x1, y1 - 1, y1, z0, z1, 'grass_light');
  for (let x = x0 + 2; x < x1 - 2; x += 5) v.paint(x, x + 2, y1 - lip - 2, y1 - lip, z1 - 1, z1, 'grass');
  for (let z = z0 + 3; z < z1 - 2; z += 6) v.paint(x1 - 1, x1, y1 - lip - 2, y1 - lip, z, z + 2, 'grass');
  for (const [fx, fz] of [[0.25, 0.3], [0.65, 0.7]]) {
    const x = Math.round(x0 + w * fx), z = Math.round(z0 + d * fz);
    v.paint(x, x + 2, y1 - 1, y1, z, z + 2, 'grass');
  }
}

// Wood: a peeled log lying along the wall, as Build lays it (docs 275 and 278), clipped like
// the loose log. Its upper corner steps are lit and its lower ones shaded; a knot on the
// front, and its end grain (a ring, the pith and a drying split) faces the camera.
function logCube(v, x0, x1, y0, y1, z0, z1) {
  v.cutX(x0, x1, y0, y1, z0, z1, 2, 'riven_dark');
  for (const [y, z] of [[y1 - 1, z0 + 2], [y1 - 2, z0 + 1], [y1 - 3, z0], [y1 - 1, z1 - 3], [y1 - 2, z1 - 2], [y1 - 3, z1 - 1]]) v.paint(x0, x1, y, y + 1, z, z + 1, 'riven');
  for (const [y, z] of [[y0, z0 + 2], [y0 + 1, z0 + 1], [y0 + 2, z0], [y0, z1 - 3], [y0 + 1, z1 - 2], [y0 + 2, z1 - 1]]) v.paint(x0, x1, y, y + 1, z, z + 1, 'pith');
  v.paint(x1 - 1, x1, y0, y1, z0, z1, 'riven_dark');                       // the end: a peeled rim round the cut face
  v.paint(x1 - 1, x1, y0 + 1, y1 - 1, z0 + 2, z1 - 2, 'wood_top'); v.paint(x1 - 1, x1, y0 + 2, y1 - 2, z0 + 1, z1 - 1, 'wood_top');
  const py = y0 + 5, pz = z0 + 5;
  P.endRings(v, 'x', x1 - 1, py, pz, [2]);
  v.box(x1 - 1, x1, py + 1, py + 2, pz + 2, z1, null); v.box(x1 - 5, x1 - 1, py + 1, py + 2, z1 - 1, z1, null);   // the drying split
  v.paint(x0 + 2, x0 + 5, y0 + 3, y0 + 6, z1 - 1, z1, 'bark_light'); v.paint(x0 + 3, x0 + 4, y0 + 4, y0 + 5, z1 - 1, z1, 'bark');   // a knot
}

// Build: a wall going up in stone, a peeled log and grass-topped earth, its next block still
// the game's blue plan.
define('build', v => {
  stoneCube(v, -14, -2, 0, 11, -8, 4);
  logCube(v, -1, 11, 0, 11, -8, 4);
  earthCube(v, -8, 4, 11, 22, -8, 4, true);
  const [x0, x1, y0, y1, z0, z1] = [5, 16, 11, 22, -8, 3];
  for (const x of [x0, x1 - 2]) for (const z of [z0, z1 - 2]) v.box(x, x + 2, y0, y1, z, z + 2, 'plan');
  for (const y of [y0, y1 - 2]) {
    for (const z of [z0, z1 - 2]) v.box(x0, x1, y, y + 2, z, z + 2, 'plan');
    for (const x of [x0, x1 - 2]) v.box(x, x + 2, y, y + 2, z0, z1, 'plan');
  }
  v.paint(x0, x1, y1 - 1, y1, z0, z1, 'plan_light');
});

// Build's material pictures: one block each. Wood's are its logs, made by
// tools/voxel_assets/built_logs.py in each wood (doc 275).
define('block_stone', v => stoneCube(v, -11, 11, 0, 22, -11, 11));
define('block_dirt', v => earthCube(v, -11, 11, 0, 22, -11, 11, false));
define('block_grass', v => earthCube(v, -11, 11, 0, 22, -11, 11, true));

// Shapes (doc 273, Phase 2): small dressed stone blocks, `s` cells each, laid out as the game
// plans each shape; a 'plan' block is the game's blue outline.
function shapeBlock(v, x, y, z, s, role) {
  if (role === 'plan') {
    for (const dx of [0, s - 1]) for (const dz of [0, s - 1]) v.box(x + dx, x + dx + 1, y, y + s, z + dz, z + dz + 1, 'plan');
    for (const dy of [0, s - 1]) {
      for (const dz of [0, s - 1]) v.box(x, x + s, y + dy, y + dy + 1, z + dz, z + dz + 1, 'plan');
      for (const dx of [0, s - 1]) v.box(x + dx, x + dx + 1, y + dy, y + dy + 1, z, z + s, 'plan');
    }
    v.paint(x, x + s, y + s - 1, y + s, z, z + s, 'plan_light');
    return;
  }
  v.cut(x, x + s, y, y + s, z, z + s, 1, 'stone');
  v.paint(x, x + s, y + s - 1, y + s, z, z + s, 'stone_light');
  v.paint(x, x + s, y, y + 1, z, z + s, 'stone_dark');
}
const shapeBlocks = (v, cells, s, [ox, oy, oz], role = 'stone') => {
  for (const [bx, by, bz] of cells) shapeBlock(v, ox + bx * s, oy + by * s, oz + bz * s, s, role);
};

// A ring `radius` blocks out, as the game draws a hollow circle: the cells within radius + ½
// that have a side neighbour outside.
function ringCells(radius, height) {
  const inside = (dx, dz) => dx * dx + dz * dz <= (radius + 0.5) ** 2;
  const cells = [];
  for (let dx = -radius; dx <= radius; dx++) for (let dz = -radius; dz <= radius; dz++) {
    if (!inside(dx, dz) || (inside(dx + 1, dz) && inside(dx - 1, dz) && inside(dx, dz + 1) && inside(dx, dz - 1))) continue;
    for (let y = 0; y < height; y++) cells.push([dx + radius, y, dz + radius]);
  }
  return cells;
}

// A flight of `steps` rising toward -x, `width` blocks wide: each step a column under its tread.
function stairCells(steps, width) {
  const cells = [];
  for (let i = 0; i < steps; i++) for (let h = 0; h <= i; h++) for (let w = 0; w < width; w++) cells.push([steps - 1 - i, h, w]);
  return cells;
}

// Shapes: a ring of walls on the left, a flight of stairs on the right, its top step still the
// game's blue plan. Left and right of the picture run along -x+z and +x-z.
define('shapes', v => {
  shapeBlocks(v, ringCells(1, 2), 5, [-16, 0, 1]);
  const flight = stairCells(3, 2);
  shapeBlocks(v, flight.filter(([, y]) => y < 2), 5, [1, 0, -16]);
  shapeBlocks(v, flight.filter(([, y]) => y === 2), 5, [1, 0, -16], 'plan');
});

// Shapes' shape pictures: a hollow rectangle with a door gap, a ring, a flight of stairs.
define('shape_rectangle', v => {
  const cells = [];
  for (let y = 0; y < 2; y++) for (let x = 0; x < 5; x++) for (let z = 0; z < 4; z++) {
    const edge = x === 0 || x === 4 || z === 0 || z === 3;
    if (edge && !(z === 3 && x === 2)) cells.push([x, y, z]);
  }
  shapeBlocks(v, cells, 5, [-12, 0, -10]);
});
define('shape_circle', v => shapeBlocks(v, ringCells(2, 2), 5, [-12, 0, -12]));

// Copy (doc 273, Phase 3): a small stone hut inside the blue box Copy draws round it.
define('copy', v => {
  const hut = [];
  for (let y = 0; y < 2; y++) for (let x = 0; x < 3; x++) for (let z = 0; z < 3; z++) {
    if ((x === 1 && z === 1) || (x === 1 && z === 2 && y === 0)) continue;   // hollow, a door in front
    hut.push([x, y, z]);
  }
  shapeBlocks(v, hut, 6, [-9, 0, -9]);
  const [x0, x1, y0, y1, z0, z1] = [-14, 14, 0, 18, -14, 14];
  for (const x of [x0, x1 - 2]) for (const z of [z0, z1 - 2]) v.box(x, x + 2, y0, y1, z, z + 2, 'plan');
  for (const y of [y0, y1 - 2]) {
    for (const z of [z0, z1 - 2]) v.box(x0, x1, y, y + 2, z, z + 2, 'plan');
    for (const x of [x0, x1 - 2]) v.box(x, x + 2, y, y + 2, z0, z1, 'plan');
  }
  v.paint(x0, x1, y1 - 1, y1, z0, z1, 'plan_light');
});

// Blueprints: a blue sheet with a room drawn on it in pale lines, its far edge rolled.
define('blueprints', v => {
  v.box(-14, 14, 0, 2, -10, 14, 'plan');
  v.cutX(-14, 14, 0, 6, -15, -9, 2, 'plan');                    // the roll at the far edge
  v.paint(-14, 14, 5, 6, -15, -9, 'plan_light');
  for (const [a, b, c, d] of [[-9, 9, 4, 5], [-9, 9, 11, 12], [-9, -8, 4, 12], [8, 9, 4, 12]]) v.paint(a, b, 1, 2, c, d, 'plan_light');
  v.paint(-2, 2, 1, 2, 11, 12, 'plan');                          // the room's door gap
  v.paint(-2, 3, 1, 2, -4, -3, 'plan_light'); v.paint(-2, -1, 1, 2, -4, 1, 'plan_light');   // a stair mark
});
define('shape_stairs', v => shapeBlocks(v, stairCells(4, 2), 5, [-10, 0, -5]));

// ── Professions ────────────────────────────────────────────────────────────────
// One icon per profession, shared by the Crafters menu, the career map and the
// equipment view. Tools echo the game's own: the dwarves' felling axe and mining
// pickaxe, and the starter tools' stone heads lashed with rope.

// A stepped diagonal stroke in the XY plane, three cells thick, from (x0, y0) along
// (dx, dy) steps of two cells; facing the camera when the icon turns 40°.
function stroke(v, x0, y0, dx, dy, steps, c, z0 = -1, z1 = 2) {
  for (let i = 0; i < steps; i++) v.box(x0 + dx * 2 * i, x0 + dx * 2 * i + 3, y0 + dy * 2 * i, y0 + dy * 2 * i + 3, z0, z1, c);
}

// Worker: the dwarves' own felling axe and mining pickaxe, standing in a heap of earth,
// turned so both heads show broadside.
define('worker', v => {
  v.cut(-7, 7, 0, 4, -9, 9, 3, 'earth'); v.paint(-7, 7, 3, 4, -9, 9, 'earth_light');
  replayInto(v, D.build('tools/mining_pickaxe').log, [0, 4, -4]);
  replayInto(v, D.build('tools/felling_axe').log, [0, 4, 4]);
}, { yaw: -50 });

// Miner: a heap of ore-bearing rock, a pick leaning on it. The pick is drawn in steps,
// facing the camera.
define('miner', v => {
  v.cut(-15, 3, 0, 9, -8, 8, 3, 'stone'); v.cut(-13, 1, 9, 14, -6, 6, 3, 'stone'); v.paint(-13, 1, 13, 14, -6, 6, 'stone_light');
  for (const [x, y, z, c] of [[-10, 3, 7, 'ore_gold'], [-5, 6, 7, 'ore_copper'], [-1, 3, 7, 'ore_gold'], [-8, 10, 5, 'ore_copper'],
    [-3, 11, 5, 'ore_gold'], [-12, 7, 6, 'ore_copper'], [-6, 13, 1, 'ore_gold']]) v.box(x, x + 3, y, y + 3, z, z + 2, c);   // nuggets
  for (let i = 0; i < 8; i++) v.box(14 - 2 * i, 17 - 2 * i, 0 + 2 * i, 3 + 2 * i, -1, 2, i < 2 ? 'tool_leather' : 'wood');   // haft
  for (const [x0, x1, y0, y1, c] of [[-8, -4, 15, 18, 'steel'], [-5, -1, 16, 20, 'iron_dark'], [-1, 3, 17, 21, 'iron_dark'],
    [2, 6, 19, 23, 'iron_dark'], [5, 9, 21, 24, 'steel']]) v.box(x0, x1, y0, y1, -1, 2, c);   // the head across the haft's top
}, { yaw: 40 });

// Carpenter: a handsaw resting on a plank, its toothed blade facing the camera.
define('carpenter', v => {
  v.box(-15, 15, 0, 4, -6, 6, 'plank_riven'); v.paint(-15, 15, 3, 4, -6, 6, 'plank');
  v.paint(-15, 15, 0, 4, -6, -5, 'plank_seam');
  for (let x = -12; x < 8; x += 5) v.paint(x, x + 2, 3, 4, -3, 2, 'plank_grain');
  for (let i = 0; i < 6; i++) v.box(-12 + 3 * i, -9 + 3 * i, 4, 13 + i, -1, 1, 'steel');   // a tapering blade
  for (let x = -12; x < 6; x += 3) v.box(x, x + 2, 4, 5, -1, 1, 'iron');                    // its teeth
  v.paint(-12, 6, 12, 19, -1, 1, 'steel');
  v.box(6, 15, 5, 21, -2, 2, 'wood_side');                    // the handle, a loop for the hand
  v.box(8, 13, 9, 17, -2, 2, null);
  v.paint(6, 15, 20, 21, -2, 2, 'wood_top');
  for (const [x, z] of [[-14, 7], [-8, 8], [-11, -9]]) v.box(x, x + 2, 0, 1, z, z + 2, 'plank');   // sawdust
}, { yaw: 40 });

// Stonemason: a dressed block with a chisel driven into its top, a round mason's mallet
// at its foot, and chips.
define('stonemason', v => {
  v.cut(-12, 6, 0, 15, -9, 9, 1, 'stone');
  v.paint(-12, 6, 14, 15, -9, 9, 'stone_light'); v.paint(-12, 6, 0, 1, -9, 9, 'stone_dark');
  for (const y of [5, 10]) v.paint(-12, 6, y, y + 1, -9, 9, 'stone_dark');   // tooled courses
  for (let i = 0; i < 6; i++) v.box(-2 + 2 * i, 1 + 2 * i, 13 + 2 * i, 16 + 2 * i, -1, 2, i < 4 ? 'steel' : 'iron');   // the chisel
  v.box(10, 14, 23, 27, -2, 3, 'iron'); v.paint(10, 14, 26, 27, -2, 3, 'steel');
  v.cutX(7, 15, 0, 7, 4, 11, 2, 'wood_side');                 // the round mallet head
  v.paint(7, 8, 0, 7, 4, 11, 'wood_top'); v.paint(14, 15, 0, 7, 4, 11, 'wood_top');
  v.box(10, 12, 2, 4, 11, 19, 'wood'); v.box(10, 12, 2, 4, 16, 19, 'tool_leather');   // its handle
  for (const [x, z, c] of [[-15, 6, 'stone'], [-9, 11, 'stone_light'], [1, 12, 'stone']]) v.box(x, x + 3, 0, 2, z, z + 3, c);
}, { yaw: 20 });

// Blacksmith: an anvil with a glowing bar on its face and sparks above.
define('blacksmith', v => {
  v.cut(-7, 7, 0, 4, -6, 6, 2, 'iron_dark');                  // the foot
  v.box(-4, 4, 4, 9, -3, 3, 'iron_dark');                     // the waist
  v.box(-11, 10, 9, 15, -5, 5, 'iron');                       // the body and face
  v.box(10, 14, 10, 14, -3, 3, 'iron'); v.box(14, 17, 11, 13, -2, 2, 'iron');   // the horn
  v.box(-14, -11, 11, 15, -4, 4, 'iron');                     // the heel
  v.paint(-14, 14, 14, 15, -5, 5, 'steel');
  v.box(-7, 6, 15, 17, -1, 2, 'flame_out'); v.paint(-5, 4, 16, 17, -1, 2, 'flame_mid');
  v.paint(-2, 1, 16, 17, -1, 2, 'flame_core');
  for (const [x, y, z] of [[-3, 21, 0], [3, 24, 1], [0, 27, -1], [6, 20, 0]]) v.box(x, x + 1, y, y + 1, z, z + 1, 'flame_core');
}, { yaw: 20 });

// Farmer: the stone hoe over a heap of earth, turnips pulled beside it.
define('farmer', v => {
  v.cut(-14, 10, 0, 3, -7, 7, 3, 'earth'); v.paint(-14, 10, 2, 3, -7, 7, 'earth_light');
  for (const x of [-11, -3]) {                                // two turnips, leaves up
    v.cut(x, x + 6, 3, 8, -3, 3, 2, 'turnip'); v.paint(x, x + 6, 6, 8, -3, 3, 'turnip_top');
    v.box(x + 1, x + 3, 8, 14, -1, 1, 'stalk'); v.box(x + 3, x + 5, 8, 12, -1, 1, 'stalk_light');
    v.box(x, x + 2, 12, 15, -1, 1, 'stalk_light');
  }
  stroke(v, 16, 30, -1, -1, 7, 'wood');                       // the hoe's haft, down to the left
  v.box(0, 9, 13, 18, -2, 3, 'stone'); v.paint(0, 9, 17, 18, -2, 3, 'stone_light');   // its stone blade
  v.box(6, 9, 15, 19, -2, 3, 'rope');
}, { yaw: 40 });

// Ranger (doc 292, concept A): the Hunter's stone-pointed spear crossed over the dwarves' peeled
// rod, both planted in a turf; the rod's line hangs from its tip past the turf's edge, with the
// red-tipped float.
define('ranger', v => {
  v.cut(-11, 11, 0, 4, -7, 7, 3, 'earth');                    // the turf
  v.paint(-11, 11, 3, 4, -7, 7, 'grass'); v.paint(-11, 11, 0, 1, -7, 7, 'earth_dark');
  for (const [x, z] of [[-9, 4], [6, -5], [8, 3], [-3, 5]]) v.box(x, x + 2, 4, 7, z, z + 1, 'grass_light');
  for (let i = 0; i < 26; i++) v.box(10 - i, 12 - i, 2 + i, 4 + i, -3, -1, i < 4 ? 'rod_bark' : 'rod_wood');   // the rod, behind
  for (const i of [7, 14]) v.box(9 - i, 13 - i, 2 + i, 4 + i, -4, 0, 'rope');                                  // its lashings
  v.box(-14, -13, 12, 27, -2, -1, 'rod_line');                // the line from the tip
  v.box(-14, -13, 4, 6, -2, -1, 'float_wood');                // the float's keel, carved body and dyed tip
  v.cut(-15, -12, 6, 9, -3, 0, 1, 'float_wood');
  v.paint(-15, -12, 8, 9, -3, 0, 'float_red');
  v.box(-14, -13, 9, 12, -2, -1, 'float_red');
  v.paint(-14, -13, 11, 12, -2, -1, 'float_dark');
  stroke(v, -11, 2, 1, 1, 9, 'wood', 1, 4);                   // the spear, in front, rising right
  v.box(5, 9, 18, 22, 0, 5, 'rope');                          // the lashing
  stroke(v, 9, 21, 1, 1, 3, 'stone', 0, 5);                    // the stepped stone point
  v.box(14, 16, 27, 29, 1, 4, 'stone_light');
}, FACE);

// Brewer: a hooped brewing tub frothing with mash, a paddle in it, barley beside.
define('brewer', v => {
  v.cut(-11, 7, 0, 15, -9, 9, 4, 'wood_side');
  for (let x = -9; x < 7; x += 3) v.paint(x, x + 1, 0, 15, -9, 9, 'wood_dark');   // staves
  for (const y of [2, 11]) v.paint(-11, 7, y, y + 1, -9, 9, 'iron_dark');           // hoops
  v.cut(-9, 5, 12, 15, -7, 7, 3, null);
  v.cut(-9, 5, 12, 14, -7, 7, 3, 'linen');                    // the frothing mash
  for (const [x, z] of [[-6, -2], [0, 3], [-3, 4], [2, -4]]) v.box(x, x + 2, 14, 15, z, z + 2, 'straw');
  v.box(-1, 1, 13, 28, -1, 1, 'wood'); v.box(-2, 2, 26, 29, -2, 2, 'wood_top');   // the paddle
  for (const z of [-4, 0, 4]) {                               // a sheaf of barley
    v.box(9, 11, 0, 16, z, z + 2, 'hay_dark');
    v.cut(8, 12, 16, 22, z - 1, z + 3, 1, 'hay'); v.paint(8, 12, 21, 22, z - 1, z + 3, 'straw');
  }
  v.box(8, 12, 5, 7, -5, 7, 'rope');
});

// ── Colony ─────────────────────────────────────────────────────────────────────

// Dwarves: two of the colony's dwarves side by side, from the real head parts: a
// black-haired dwarf with a braided beard in front and a ginger dwarf with twin braids a
// step behind. The second tints (hair2, skin2) keep them apart.
const DARK_TAN = { hair: 'hair2', hair_mid: 'hair2_mid', hair_shade: 'hair2_shade', skin: 'skin2',
  skin_shade: 'skin_shade2', nose: 'nose2', blush: 'blush2', mouth: 'mouth2' };
define('dwarves', v => {
  for (const part of ['body/head_adult', 'body/eyes', 'eyebrows/brows_f_thin_arched', 'hair/hair_f_twin_braids'])
    replayInto(v, D.build(part).log, [12, 3, -6]);
  for (const part of ['body/head_adult', 'body/eyes', 'eyebrows/brows_m_thick_flat', 'hair/hair_m_braided_back', 'beards/beard_braided_long'])
    replayInto(v, D.build(part).log, [-12, 0, 4], DARK_TAN);
}, { yaw: 25 });

// Settlement flag: the game's banner on its pole and cairn, drawn shorter so the
// banner reads at icon size; the peak mark as on the real flag.
define('flag', v => {
  v.pillow(-7, 7, 0, 5, -6, 6, 1, 'stone'); v.pillow(-8, -2, 0, 4, -2, 5, 1, 'stone_light');
  v.pillow(2, 8, 0, 3, -5, 1, 1, 'stone_light'); v.pillow(-4, 3, 5, 8, -3, 4, 1, 'stone');
  v.box(-2, 1, 0, 32, -1, 2, 'bark'); v.box(-1, 0, 32, 34, 0, 1, 'bark'); v.paint(-1, 0, 33, 34, 0, 1, 'wood_top');
  v.paint(-2, -1, 10, 16, -1, 2, 'bark_light'); v.paint(0, 1, 20, 25, -1, 2, 'bark_light');
  v.cutX(-3, 15, 28, 30, -1, 2, 0, 'wood_side'); v.paint(14, 15, 28, 30, -1, 2, 'wood_top');
  v.box(-3, 2, 27, 31, -2, 3, 'rope'); v.box(-2, 1, 27, 31, -1, 2, 'bark');
  v.box(1, 14, 10, 28, 0, 1, 'flag');                         // the banner
  v.paint(1, 14, 25, 27, 0, 1, 'flag_light');
  v.box(6, 9, 10, 13, 0, 1, null);                            // a swallowtail
  for (const [x0, x1, y0] of [[7, 8, 21], [6, 9, 19], [5, 10, 17], [4, 11, 15]]) v.paint(x0, x1, y0, y0 + 2, 0, 1, 'flag_mark');   // the peak mark
}, { yaw: 40 });

// Labor: an open work ledger, its rows ticked or crossed, as the work permissions are.
define('labor', v => {
  v.box(-15, 15, 0, 2, -11, 11, 'belt'); v.paint(-15, 15, 1, 2, -11, 11, 'belt_dark');   // the leather cover
  v.box(-14, -1, 2, 4, -10, 10, 'linen'); v.box(1, 14, 2, 4, -10, 10, 'linen');            // the pages
  v.box(-1, 1, 1, 3, -10, 10, 'linen_dark');                  // the gutter
  v.paint(-14, -1, 3, 4, -10, -9, 'linen_dark'); v.paint(1, 14, 3, 4, -10, -9, 'linen_dark');
  for (const [x0, z0, mark] of [[-12, -7, 'tick'], [-12, -1, 'tick'], [-12, 5, 'cross'], [3, -7, 'tick'], [3, -1, 'cross'], [3, 5, 'tick']]) {
    v.ring(x0, x0 + 4, 4, z0, z0 + 4, 'char');                 // a box
    v.box(x0 + 5, x0 + 10, 4, 5, z0 + 1, z0 + 3, 'linen_dark'); // and its line
    if (mark === 'tick') { v.box(x0 + 1, x0 + 2, 4, 5, z0 + 2, z0 + 3, 'arrow'); v.box(x0 + 2, x0 + 3, 4, 5, z0 + 1, z0 + 2, 'arrow'); v.box(x0 + 3, x0 + 4, 4, 6, z0, z0 + 1, 'arrow'); }
    else { v.box(x0 + 1, x0 + 3, 4, 5, z0 + 1, z0 + 3, 'apple'); }
  }
  v.box(8, 10, 2, 5, 9, 14, 'brass'); v.box(8, 10, 5, 7, 13, 14, 'brass');   // a ribbon marker
});

// Trade (planned): a brass balance with gold coins on one pan and a crate of goods on
// the other.
define('trade', v => {
  v.cut(-6, 6, 0, 3, -4, 4, 2, 'brass_dark');                 // the foot
  v.box(-1, 1, 3, 27, -1, 1, 'brass'); v.box(-2, 2, 27, 30, -2, 2, 'brass_light');   // the post and its finial
  v.box(-15, 15, 24, 26, -1, 1, 'brass'); v.paint(-15, 15, 25, 26, -1, 1, 'brass_light');   // the beam
  for (const x of [-12, 11]) {
    v.box(x, x + 1, 14, 24, -1, 1, 'brass_dark');             // hangers
    v.cut(x - 5, x + 6, 12, 14, -4, 5, 2, 'brass');           // the pans
  }
  for (const [y, z] of [[14, -1], [16, 0], [18, -1]]) v.cut(-15, -10, y, y + 2, z - 1, z + 3, 1, 'ore_gold');   // a stack of coins
  v.box(7, 15, 14, 21, -3, 4, 'wood_side'); v.paint(7, 15, 20, 21, -3, 4, 'wood_top');   // a crate of goods
  v.paint(7, 15, 17, 18, -3, 4, 'rope');
  for (const [x, z] of [[-9, 6], [-5, 8], [5, 7]]) v.cut(x, x + 3, 0, 1, z, z + 3, 1, 'ore_gold');   // coins on the ground
}, { yaw: 40 });

// ── Compact panel actions (doc 260) ───────────────────────────────────────────
// The object panel's buttons: the same green arrows as Place, the real stool and packed
// crate, and the real dwarf head for ownership.

// A green arrow along X: a shaft from x0 to x1, then a stepped head from x1 pointing `dir`.
function arrowX(v, x0, x1, y0, dir) {
  v.box(Math.min(x0, x1), Math.max(x0, x1), y0, y0 + 4, -2, 2, 'arrow');
  v.paint(Math.min(x0, x1), Math.max(x0, x1), y0 + 3, y0 + 4, -2, 2, 'arrow_light');
  for (const [step, half] of [[0, 7], [1, 5], [2, 3], [3, 1]]) {   // 45 degree steps, as Place
    const a = x1 + dir * step * 2, b = a + dir * 2, mid = y0 + 2;
    v.box(Math.min(a, b), Math.max(a, b), mid - half, mid + half, -2, 2, 'arrow');
    v.paint(Math.min(a, b), Math.max(a, b), mid + half - 1, mid + half, -2, 2, 'arrow_light');
    v.paint(Math.min(a, b), Math.max(a, b), mid - half, mid - half + 1, -2, 2, 'arrow_dark');
  }
}

// Move: the log stool under a two-headed arrow.
define('move', v => {
  replayInto(v, P.stool().log);
  arrowX(v, -8, 8, 21, 1);
  arrowX(v, 8, -8, 21, -1);
}, { yaw: 38 });

// Pack up: the stool, an arrow and the packed crate it goes into.
define('pack_up', v => {
  replayInto(v, P.stool().log, [-10, 0, -2]);
  replayInto(v, T.packedCrate().log, [9, 0, 2]);
  arrowX(v, -12, 0, 21, 1);
}, { yaw: 30 });

// Assign owner: a dwarf's head with a brass key in front of it.
define('assign_owner', v => {
  for (const part of ['body/head_adult', 'body/eyes', 'eyebrows/brows_m_bushy', 'hair/hair_m_short_back', 'beards/beard_short_trimmed'])
    replayInto(v, D.build(part).log, [-6, 6, -4]);
  v.cutZ(-2, 12, 0, 14, 9, 13, 3, 'brass');                   // the key's bow, holed
  v.box(3, 7, 5, 9, 9, 13, null);
  v.box(12, 28, 5, 9, 9, 13, 'brass');                        // the shank
  v.box(19, 22, 0, 5, 9, 13, 'brass'); v.box(24, 28, 0, 5, 9, 13, 'brass');   // the teeth
  v.paint(-2, 28, 8, 9, 9, 13, 'brass_light'); v.paint(1, 9, 13, 14, 9, 13, 'brass_light');
  v.paint(19, 28, 0, 1, 9, 13, 'brass_dark'); v.paint(-1, 11, 0, 1, 9, 13, 'brass_dark');
}, { yaw: 32 });

// Allow/Disallow: a dwarf's mitten held up, palm out, struck through in red: hands off.
define('disallow', v => {
  v.cutZ(-9, 8, 2, 7, -4, 2, 2, 'tunic_dark'); v.paint(-9, 8, 6, 7, -4, 2, 'tunic');   // the cuff
  v.cutZ(-8, 7, 7, 27, -3, 2, 3, 'skin');                     // the mitten
  v.paint(-8, 7, 7, 10, -3, 2, 'skin_shade');                 // the heel of the hand
  for (const x of [-5, -1, 3]) {                              // four fingers
    v.paint(x, x + 1, 17, 27, 1, 2, 'skin_shade');
    v.box(x, x + 1, 25, 27, -3, 2, null);
  }
  v.box(7, 10, 10, 16, -2, 1, 'skin'); v.box(9, 12, 14, 19, -2, 1, 'skin');   // the thumb, out to the side
  for (let i = 0; i < 12; i++) v.box(-12 + 2 * i, -9 + 2 * i, 24 - 2 * i, 27 - 2 * i, 2, 5, 'apple');   // the red stroke
  v.paint(-12, 13, 2, 27, 2, 3, 'apple_dark');
}, FACE);

// Appeal (the panel's badge): a gold four-pointed sparkle.
define('appeal', v => {
  v.cutZ(-5, 5, 11, 21, -3, 3, 2, 'ore_gold');
  for (const [half, y0, y1] of [[3, 21, 25], [2, 25, 28], [1, 28, 31]]) {
    v.box(-half, half, y0, y1, -2, 2, 'ore_gold');            // up
    v.box(-half, half, 32 - y1, 32 - y0, -2, 2, 'ore_gold');  // down
  }
  for (const [half, x0, x1] of [[3, 5, 9], [2, 9, 12], [1, 12, 15]]) {
    v.box(x0, x1, 16 - half, 16 + half, -2, 2, 'ore_gold');   // right
    v.box(-x1, -x0, 16 - half, 16 + half, -2, 2, 'ore_gold'); // left
  }
  v.paint(-5, 0, 16, 21, -3, 3, 'brass_light'); v.paint(-3, 0, 21, 31, -2, 2, 'brass_light');   // the lit upper left
  v.paint(-15, -5, 16, 19, -2, 2, 'brass_light');
  v.paint(0, 5, 11, 16, -3, 3, 'brass'); v.paint(0, 3, 1, 11, -2, 2, 'brass'); v.paint(5, 15, 13, 16, -2, 2, 'brass');
}, FACE);

// ── Compact dwarf panel (doc 260 phase 3) ──────────────────────────────────────

// Follow: a watchful eye, outlined, with a teal iris and a glint.
define('follow', v => {
  v.cutZ(-15, 15, 5, 23, -2, 2, 7, 'char');                   // the outline
  v.cutZ(-13, 13, 7, 21, -3, 3, 6, 'linen');                  // the white
  v.cutZ(-6, 6, 8, 20, -4, 4, 3, 'teal');                     // the iris
  v.cutZ(-3, 3, 11, 17, -5, 5, 1, 'char');                    // the pupil
  v.box(1, 3, 14, 16, 5, 6, 'glint');
  for (const [x0, x1, y0] of [[-11, -9, 23], [-5, -3, 24], [3, 5, 24], [9, 11, 23]]) v.box(x0, x1, y0, y0 + 3, -1, 1, 'char');   // lashes
}, FACE);

// Locate: a red map pin standing in a patch of ground.
define('locate', v => {
  v.cut(-13, 13, 0, 3, -10, 10, 3, 'earth');
  v.paint(-13, 13, 2, 3, -10, 10, 'grass');
  v.paint(-3, 3, 2, 3, -3, 3, 'earth_dark');                  // where the needle went in
  v.box(-1, 1, 3, 15, -1, 1, 'steel');                        // the needle
  v.cut(-7, 7, 14, 28, -7, 7, 4, 'apple');                    // the round head
  v.paint(-7, 7, 14, 16, -7, 7, 'apple_dark');
  v.box(-4, -1, 23, 26, 4, 7, 'linen');                       // the shine
}, { yaw: 30 });

// Character sheet: a dwarf's head in front of a written sheet.
define('character_sheet', v => {
  v.box(0, 24, 2, 33, -8, -6, 'linen');                       // the sheet, behind
  v.cutX(-1, 25, 31, 35, -9, -5, 1, 'linen_dark');            // its rolled top
  v.cutX(-1, 25, 0, 4, -9, -5, 1, 'linen_dark');              // and bottom
  v.paint(0, 1, 2, 33, -8, -6, 'parchment_edge'); v.paint(23, 24, 2, 33, -8, -6, 'parchment_edge');
  for (const [y, x1] of [[26, 21], [22, 19], [18, 21], [14, 17], [10, 20], [6, 15]]) v.paint(9, x1, y, y + 2, -7, -6, 'char');   // lines of writing
  for (const part of ['body/head_adult', 'body/eyes', 'eyebrows/brows_m_bushy', 'hair/hair_m_short_back', 'beards/beard_short_trimmed'])
    replayInto(v, D.build(part).log, [-11, 0, 2]);
}, { yaw: 28 });

// ── Mood faces (doc 261 phase 3) ─────────────────────────────────────────────
// Five faces for the character sheet's mood banner and five-step scale: the dwarves'
// own square head and swept hair, without a beard so the mouth shows. The dark brows (left
// side, mirrored), eyes and mouth change from step to step, and the blush drains from the
// two unhappy ones; the brows stay under the fringe (y < 45) and the mouth sits on the
// jaw's front (z 8).
const BROW = {
  raised: b => { b.box(-10, -5, 43, 45, 10, 12, 'hair_shade'); b.box(-11, -10, 42, 44, 10, 12, 'hair_shade'); },
  arched: b => { b.box(-10, -5, 42, 44, 10, 12, 'hair_shade'); b.box(-9, -6, 44, 45, 10, 12, 'hair_shade'); },
  flat: b => b.box(-10, -5, 42, 44, 10, 12, 'hair_shade'),
  worried: b => { b.box(-11, -8, 41, 43, 10, 12, 'hair_shade'); b.box(-8, -5, 43, 45, 10, 12, 'hair_shade'); },
  knitted: b => { b.box(-12, -9, 40, 42, 10, 12, 'hair_shade'); b.box(-9, -6, 42, 44, 10, 12, 'hair_shade'); b.box(-6, -4, 44, 45, 10, 12, 'hair_shade'); },
};
const EYES = {
  open: v => P.eyes(v),
  closed: v => v.both(s => {                          // smiling arcs, ^ ^
    s.box(-10, -9, 38, 40, 10, 11, 'eye'); s.box(-9, -6, 40, 41, 10, 11, 'eye'); s.box(-6, -5, 38, 40, 10, 11, 'eye');
  }),
  down: v => v.both(s => s.box(-9, -6, 36, 39, 10, 11, 'eye')),   // lowered, no glint
};
const MOUTH = {
  grin: v => {
    v.paint(-5, 5, 30, 32, 8, 9, 'mouth'); v.paint(-4, 4, 31, 32, 8, 9, 'linen');   // open, the teeth on top
    v.paint(-6, -5, 31, 33, 8, 9, 'mouth'); v.paint(5, 6, 31, 33, 8, 9, 'mouth');
  },
  smile: v => { v.paint(-3, 3, 31, 32, 8, 9, 'mouth'); v.paint(-4, -3, 32, 33, 8, 9, 'mouth'); v.paint(3, 4, 32, 33, 8, 9, 'mouth'); },
  flat: v => v.paint(-3, 3, 31, 32, 8, 9, 'mouth'),
  frown: v => { v.paint(-3, 3, 32, 33, 8, 9, 'mouth'); v.paint(-4, -3, 31, 32, 8, 9, 'mouth'); v.paint(3, 4, 31, 32, 8, 9, 'mouth'); },
  sob: v => {
    v.paint(-3, 3, 32, 33, 8, 9, 'mouth'); v.paint(-4, -3, 31, 32, 8, 9, 'mouth'); v.paint(3, 4, 31, 32, 8, 9, 'mouth');
    v.paint(-5, -4, 30, 31, 8, 9, 'mouth'); v.paint(4, 5, 30, 31, 8, 9, 'mouth');
  },
};
function moodFace(v, brows, eyes, mouth, { tear = false, pale = false } = {}) {
  P.head(v, {});
  if (pale) v.both(s => s.paint(-10, -6, 35, 37, 10, 11, 'skin'));   // the blush drains
  replayInto(v, D.build('hair/hair_m_short_back').log);
  v.both(s => BROW[brows](s));
  EYES[eyes](v);
  MOUTH[mouth](v);
  if (tear) v.box(-8, -7, 33, 36, 10, 11, 'xray_light');   // down the cheek, over the blush
}
define('mood_miserable', v => moodFace(v, 'knitted', 'down', 'sob', { tear: true, pale: true }), FACE);
define('mood_unhappy', v => moodFace(v, 'worried', 'open', 'frown', { pale: true }), FACE);
define('mood_content', v => moodFace(v, 'flat', 'open', 'flat'), FACE);
define('mood_happy', v => moodFace(v, 'arched', 'open', 'smile'), FACE);
define('mood_joyful', v => moodFace(v, 'raised', 'closed', 'grin'), FACE);

// ── Dwarf concerns (doc 23) ──────────────────────────────────────────────────
// The badges over a hungry or exhausted dwarf's head, also beside the character sheet's
// Rest and Food. An unhappy dwarf shows the Unhappy face above.

// Food: a red apple from the colony's apple trees, with its stem, a leaf and a shine.
define('food', v => {
  for (const [half, y0, y1, n] of [[5, 0, 1, 3], [8, 1, 3, 5], [10, 3, 6, 6], [11, 6, 14, 7], [10, 14, 17, 6], [8, 17, 19, 5]])
    v.cut(-half, half, y0, y1, -half, half, n, 'apple');      // round, in tiers
  v.paint(-11, 11, 0, 4, -11, 11, 'apple_dark');              // the shaded underside
  v.paint(-11, 11, 16, 17, -11, 11, 'apple_light'); v.paint(-8, 8, 18, 19, -8, 8, 'apple_light');   // the lit shoulders
  v.box(-2, 2, 17, 19, -2, 2, null);                          // the dimple
  v.box(-1, 1, 16, 23, -1, 1, 'bark'); v.box(0, 2, 22, 24, -1, 1, 'bark');   // the stem
  v.box(1, 7, 20, 22, -2, 1, 'leaf'); v.box(4, 10, 22, 24, -2, 1, 'leaf');   // the leaf
  v.paint(4, 10, 23, 24, -2, 1, 'grass_light');
  v.paint(-4, -2, 11, 13, 10, 11, 'linen');                   // a shine
});

// Health (doc 41 "Health"): a red heart with a shine, beside Rest and Food, and over a badly hurt
// dwarf's head.
define('health', v => {
  const tiers = [[0, 2, 2], [2, 4, 4], [4, 6, 6], [6, 8, 8], [8, 10, 10], [10, 12, 12], [12, 18, 13]];
  for (const [y0, y1, half] of tiers) v.box(-half, half, y0, y1, -3, 3, 'apple');
  for (const [y0, y1, a, b] of [[18, 21, 1, 13], [21, 23, 2, 12], [23, 24, 4, 10]]) {   // the two lobes
    v.box(-b, -a, y0, y1, -3, 3, 'apple'); v.box(a, b, y0, y1, -3, 3, 'apple');
  }
  v.cutZ(-9, 9, 6, 19, -4, 4, 5, 'apple');                     // a fuller middle
  v.paint(-13, 13, 0, 7, -4, 4, 'apple_dark');                 // the shaded point
  v.paint(-12, -3, 18, 24, -3, 3, 'apple_light');              // the lit left lobe
  v.box(-9, -6, 16, 20, 3, 4, 'linen');                        // the shine
}, FACE);

// A brass Z facing the camera, `steps` two-cell steps tall, with a lit top and a dark foot.
function zGlyph(v, x0, y0, steps) {
  const w = 2 * steps + 3, h = 2 * steps + 4;
  v.box(x0, x0 + w, y0 + h - 3, y0 + h, -2, 2, 'brass');
  v.box(x0, x0 + w, y0, y0 + 3, -2, 2, 'brass');
  for (let i = 0; i < steps; i++) v.box(x0 + 1 + 2 * i, x0 + 4 + 2 * i, y0 + 2 + 2 * i, y0 + 5 + 2 * i, -2, 2, 'brass');
  v.paint(x0, x0 + w, y0 + h - 1, y0 + h, -2, 2, 'brass_light');
  v.paint(x0, x0 + w, y0, y0 + 1, -2, 2, 'brass_dark');
}

// Rest: a pale crescent moon with a big Z and a small one in its hollow.
define('rest', v => {
  v.cutZ(-16, 4, 0, 24, -2, 2, 6, 'linen');                   // the moon
  v.cutZ(-10, 10, 6, 28, -3, 3, 6, null);                     // bitten into a crescent
  v.paint(-16, 4, 0, 3, -2, 2, 'linen_dark');                 // its shaded lower edge
  v.paint(-14, -12, 8, 10, 1, 2, 'linen_dark'); v.paint(-11, -9, 3, 5, 1, 2, 'linen_dark');   // two craters
  zGlyph(v, -4, 6, 4);
  zGlyph(v, 7, 19, 3);
}, FACE);

// ── Room window (doc 261 phase 5) ────────────────────────────────────────────

// Thermometer, for the room's temperature row: a glass tube with a red column and a
// round red bulb, on a small wooden board marked in steps. It replaces the campfire
// stand-in of the concept.
define('thermometer', v => {
  v.box(-6, 6, 0, 32, -3, -1, 'wood'); v.paint(-6, 6, 30, 32, -3, -1, 'grain');      // the board, its lit top
  for (const y of [10, 14, 18, 22, 26]) v.box(3, 5, y, y + 1, -1, 0, 'char');           // the steps
  v.box(-2, 2, 7, 29, -1, 2, 'glass'); v.paint(-2, -1, 7, 29, 1, 2, 'glass_light');      // the tube, lit along one side
  v.paint(-1, 1, 7, 19, 1, 2, 'apple');                                                  // the red column, to about half
  v.cut(-4, 4, 0, 8, -2, 4, 2, 'apple'); v.paint(-3, -1, 5, 7, 3, 4, 'apple_dark');      // the bulb
  v.box(-2, -1, 5, 6, 3, 4, 'glint');                                                    // a shine on the bulb
  v.box(-2, 2, 29, 31, -1, 2, 'brass'); v.paint(-2, 2, 30, 31, -1, 2, 'brass_light');    // the cap
}, FACE);

// ── Crafting board (doc 23) ──────────────────────────────────────────────────

// Work time: a brass clock with a ring on top, its hands at three.
define('clock', v => {
  v.cutZ(-13, 13, 0, 26, -3, 2, 8, 'brass');                  // the round case
  v.cutZ(-11, 11, 2, 24, 1, 2, 7, null);                      // the face, set in its rim
  v.cutZ(-11, 11, 2, 24, 0, 1, 7, 'linen');
  for (const [x0, y0, w, h] of [[-1, 20, 2, 3], [-1, 3, 2, 3], [7, 12, 3, 2], [-10, 12, 3, 2]]) v.box(x0, x0 + w, y0, y0 + h, 0, 1, 'linen_dark');   // the hours
  v.box(-1, 1, 12, 21, 1, 2, 'char');                         // the minute hand, at twelve
  v.box(-1, 7, 12, 14, 1, 2, 'char');                         // the hour hand, at three
  v.box(-3, 3, 26, 28, -2, 1, 'brass');                       // the ring
  v.cutZ(-4, 4, 28, 32, -2, 1, 1, 'brass'); v.box(-2, 2, 29, 31, -2, 1, null);
  v.paint(-13, 13, 24, 26, -3, 2, 'brass_light'); v.paint(-4, 4, 31, 32, -2, 1, 'brass_light');
  v.paint(-13, 13, 0, 2, -3, 2, 'brass_dark');
}, FACE);

// ── Events (doc 23) ────────────────────────────────────────────────────────────
// The dock's Events entry and the pictures in its log: the species that arrived, a
// cavern, a warning. Promotions use the profession's icon, other colony news the
// Colony icon.

// Events: a brass bell hanging from a timber yoke: a flared lip, a straight body with two
// cast bands and a shine down its side, and a rounded dome.
define('events', v => {
  v.box(-15, 15, 28, 31, -2, 2, 'wood'); v.paint(-15, 15, 30, 31, -2, 2, 'grain');      // the yoke
  v.box(-1, 1, 24, 28, -1, 1, 'iron_dark');                                              // the hanger
  v.cut(-12, 12, 2, 5, -12, 12, 5, 'brass_dark');                                        // the flared lip
  v.cut(-9, 9, 5, 20, -9, 9, 4, 'brass');                                                // the body
  v.cut(-8, 8, 20, 23, -8, 8, 4, 'brass'); v.cut(-5, 5, 23, 25, -5, 5, 2, 'brass_light');   // the dome
  v.paint(-9, 9, 9, 10, -9, 9, 'brass_dark'); v.paint(-9, 9, 16, 17, -9, 9, 'brass_dark');  // two cast bands
  v.paint(-5, -3, 6, 20, 8, 9, 'brass_light');                                           // a shine down the side
}, { yaw: 30 });

// Arrivals: each species' real head in its own colours, which write_data.py names
// <species>_<role>. Shifted so the head sits on the origin; turned to face the camera.
const own = species => new Proxy({}, { get: (_, role) => species + '_' + role });
const head = (species, parts, shift) => v => { for (const part of parts) replayInto(v, W.build(part).log, shift, own(species)); };
define('rabbit', head('rabbit', ['rabbit/head', 'rabbit/ears'], [0, -6, 4]), { yaw: 212 });
define('deer', head('deer', ['deer/neck', 'deer/head', 'deer/ears', 'deer/antlers'], [0, -18, 9]), { yaw: 212 });
define('wolf', head('wolf', ['wolf/head', 'wolf/ears'], [0, -15, 20]), { yaw: 212 });
define('duck', head('duck', ['duck/male_head'], [0, -10, 6]), { yaw: 245 });

// Discovery: a cave mouth in a grassy hillside of rough rock, a torch standing on the
// ground outside it.
define('cavern', v => {
  v.cut(-16, 16, 0, 2, -12, 12, 4, 'earth'); v.paint(-16, 16, 1, 2, -12, 12, 'grass');  // the ground
  v.cut(-15, 13, 2, 17, -12, 1, 4, 'stone');                                             // the hillside, in uneven lumps
  v.cut(-13, 5, 17, 23, -11, -1, 3, 'stone'); v.cut(3, 12, 17, 20, -10, -1, 3, 'stone');
  v.paint(-13, 5, 22, 23, -11, -1, 'grass'); v.paint(3, 12, 19, 20, -10, -1, 'grass');   // grass on top
  v.paint(-15, -13, 16, 17, -12, 1, 'grass_light'); v.paint(5, 13, 16, 17, -12, 1, 'grass');
  v.box(-9, 5, 2, 12, -8, 1, null); v.box(-7, 3, 12, 15, -8, 1, null); v.box(-5, 1, 15, 17, -8, 1, null);   // the mouth
  v.box(-9, 5, 2, 12, -9, -8, 'char'); v.box(-7, 3, 12, 15, -9, -8, 'char'); v.box(-5, 1, 15, 17, -9, -8, 'char');   // dark inside
  v.box(-9, 5, 1, 2, -8, 1, 'char');                                                     // its floor, in shadow
  for (const [x0, x1, y0, y1] of [[-14, -11, 7, 8], [7, 10, 11, 12], [-12, -10, 19, 20]]) v.paint(x0, x1, y0, y1, 0, 1, 'stone_dark');   // cracks
  for (const [x, z, c] of [[-11, 4, 'stone'], [6, 6, 'stone_light'], [-4, 7, 'stone']]) v.box(x, x + 3, 2, 4, z, z + 3, c);   // loose stones
  v.box(10, 12, 2, 12, 6, 8, 'wood_side');                                               // a torch on a stake
  v.box(9, 13, 12, 14, 5, 9, 'flame_out'); v.box(10, 12, 14, 17, 6, 8, 'flame_mid'); v.box(10, 11, 17, 18, 6, 7, 'flame_core');
}, { yaw: 25 });

// Warning: a triangular sign on a post, rimmed in red, a dark "!" on its pale face.
define('warning', v => {
  v.box(-1, 1, 0, 9, -3, -1, 'wood'); v.paint(-1, 0, 0, 9, -3, -1, 'grain');             // the post
  for (let i = 0; i < 13; i++) {                                                         // rows two cells tall
    const half = Math.round(15 - i * 1.15), y = 8 + 2 * i;
    v.box(-half, half, y, y + 2, -1, 1, 'red');
    if (i >= 1 && i <= 10) v.paint(-(half - 2), half - 2, y, y + 2, 0, 1, 'hay_light');
  }
  v.paint(-2, 2, 18, 28, 0, 1, 'char'); v.paint(-2, 2, 13, 16, 0, 1, 'char');            // the "!"
  v.paint(-15, 15, 8, 9, -1, 1, 'flag');                                                 // a darker foot
}, FACE);

// ── Development (doc 23, DEV only) ───────────────────────────────────────────
// The Development menu's tools, on the DEV tile. Where the game has the subject, the
// picture replays the real model: Build's stone block, an elder from the dwarf head
// parts, the deer's head as Events shows its arrival, and the Sky Dial's storm cloud.
// Water, snow, pine and the cloud keep their world and Sky Dial colours (write_data.py).

// A square pine as the world grows them: a short trunk under three stepped tiers.
function pine(v, x, y, z) {
  v.box(x - 1, x + 1, y, y + 3, z - 1, z + 1, 'bark');
  v.cut(x - 4, x + 4, y + 3, y + 6, z - 4, z + 4, 2, 'pine_dark');
  v.cut(x - 3, x + 3, y + 6, y + 9, z - 3, z + 3, 2, 'pine');
  v.cut(x - 2, x + 2, y + 9, y + 12, z - 2, z + 2, 1, 'pine_light');
}

// A brass cog facing +z round (cx, cy), 22 cells across: Menu's cog, smaller, its hub dark.
function cog(v, cx, cy, z0, z1) {
  v.cutZ(cx - 8, cx + 8, cy - 8, cy + 8, z0, z1, 4, 'brass');
  for (const [x0, x1, y0, y1] of [[-2, 2, 8, 11], [-2, 2, -11, -8], [8, 11, -2, 2], [-11, -8, -2, 2]])
    v.box(cx + x0, cx + x1, cy + y0, cy + y1, z0, z1, 'brass');
  for (const [x0, y0] of [[5, 5], [-9, 5], [5, -9], [-9, -9]]) v.box(cx + x0, cx + x0 + 4, cy + y0, cy + y0 + 4, z0, z1, 'brass');
  v.paint(cx - 11, cx + 11, cy + 8, cy + 11, z0, z1, 'brass_light');
  v.paint(cx - 11, cx + 11, cy - 11, cy - 8, z0, z1, 'brass_dark');
  v.cutZ(cx - 3, cx + 3, cy - 3, cy + 3, z0, z1, 2, 'ash');
}

// Another model's operations mirrored front to back (cell z becomes -z - 1), so a head
// built facing -z faces +z.
const flipZ = ops => ops.map(([op, a, c]) => op === 'mirror_x' ? [op, flipZ(a)]
  : op === 'ring' ? [op, [a[0], a[1], a[2], -a[4], -a[3]], c] : [op, [a[0], a[1], a[2], a[3], -a[5], -a[4], ...a.slice(6)], c]);

// Block inspector: a dressed stone block with ore in its face, a brass glass held up to its
// corner, the ore it finds swollen in the lens.
define('dev_block_inspector', v => {
  stoneCube(v, -16, 4, 0, 20, -15, 5);
  v.paint(-9, -7, 13, 15, 4, 5, 'ore_gold'); v.paint(-13, -11, 5, 7, 4, 5, 'ore_copper');
  v.paint(3, 4, 14, 16, -11, -9, 'ore_gold'); v.paint(-12, -10, 19, 20, -12, -10, 'ore_gold');
  v.cutZ(-4, 12, 5, 21, 7, 10, 4, 'brass');                   // the rim
  v.cutZ(-1, 9, 8, 18, 9, 10, 3, 'stone_light');              // the lens, the stone behind it swollen
  for (const [x0, x1, y0, y1] of [[1, 5, 11, 14], [3, 7, 13, 16], [5, 7, 10, 12]]) v.box(x0, x1, y0, y1, 9, 10, 'ore_gold');
  v.paint(3, 5, 14, 16, 9, 10, 'brass_light');
  v.paint(0, 1, 13, 17, 9, 10, 'glass_light'); v.paint(1, 2, 16, 18, 9, 10, 'glass_light');   // a shine
  v.paint(-4, 12, 19, 21, 7, 9, 'brass_light'); v.paint(-4, 12, 5, 7, 7, 9, 'brass_dark');
  for (let i = 0; i < 5; i++) v.box(8 + 2 * i, 11 + 2 * i, 6 - 2 * i, 9 - 2 * i, 7, 10, i < 1 ? 'brass_dark' : 'wood');   // the handle
  v.paint(13, 19, -4, 3, 7, 10, 'tool_leather');
}, { yaw: 25 });

// World Build: a cut of the generated world, its strata on the sides, a mountain with a
// snowy peak and a lower shoulder, pines on the grass and a stream running off the edge.
define('dev_world_build', v => {
  v.box(-15, 15, 0, 12, -15, 15, 'stone');
  v.paint(-15, 15, 0, 3, -15, 15, 'ash');                     // the deep rock
  v.paint(-15, 15, 8, 11, -15, 15, 'earth');
  v.paint(-15, 15, 11, 12, -15, 15, 'grass');
  for (const [x0, x1] of [[-12, -8], [1, 5], [9, 13]]) v.paint(x0, x1, 7, 8, 14, 15, 'earth');   // ragged seams
  for (const [z0, z1] of [[-11, -7], [0, 4]]) v.paint(14, 15, 7, 8, z0, z1, 'earth');
  for (const [x0, x1] of [[-14, -10], [-3, 1], [6, 9]]) v.paint(x0, x1, 3, 4, 14, 15, 'ash');
  v.paint(-7, -5, 4, 6, 14, 15, 'ore_gold'); v.paint(14, 15, 4, 6, 7, 9, 'ore_copper');   // ore in the rock
  for (const [x, z] of [[-2, 6], [8, -12], [-13, 11], [10, 10]]) v.paint(x, x + 4, 11, 12, z, z + 3, 'grass_light');
  v.cut(-15, 6, 12, 15, -15, 3, 3, 'stone');                  // the mountain, in uneven tiers
  v.cut(-14, 0, 15, 18, -13, 0, 3, 'stone'); v.cut(-2, 5, 15, 19, -9, -1, 2, 'stone');   // and its shoulder
  v.cut(-12, -2, 18, 22, -12, -3, 2, 'stone');
  for (const [x0, x1, y, z0, z1] of [[-15, 6, 14, -15, 3], [-14, 0, 17, -13, 0], [-12, -2, 21, -12, -3]])
    v.paint(x0, x1, y, y + 1, z0, z1, 'stone_light');
  v.cut(-1, 4, 19, 20, -8, -2, 1, 'snow');
  v.paint(-15, 4, 12, 13, -15, 2, 'stone_dark');
  v.cut(-11, -4, 22, 25, -11, -5, 2, 'snow');                 // its snowy peak
  v.cut(-10, -6, 25, 27, -10, -7, 1, 'snow');
  v.paint(-11, -4, 22, 23, -11, -5, 'snow_shade'); v.paint(-12, -2, 21, 22, -12, -3, 'snow_shade');
  v.box(4, 9, 9, 12, -1, 15, null);                           // the stream, cut into the grass
  v.box(4, 9, 9, 11, -1, 15, 'water'); v.paint(4, 9, 10, 11, -1, 15, 'water_light');
  v.box(4, 9, 9, 12, -3, -1, 'stone_dark');                   // its spring at the mountain's foot
  pine(v, 11, 12, -8); pine(v, -10, 12, 9);
});

// Cave explorer: a lump of buried rock with a cave in it, opened on its face, the
// explorer's highlight round the mouth and a lantern hanging inside.
define('dev_cave_explorer', v => {
  v.cut(-15, 15, 0, 20, -13, 13, 3, 'stone');                 // the rock, in uneven lumps
  v.cut(-13, 6, 20, 25, -11, 8, 3, 'stone'); v.cut(3, 13, 20, 23, -10, 6, 2, 'stone');
  v.paint(-15, 15, 19, 20, -13, 13, 'stone_light'); v.paint(-13, 6, 24, 25, -11, 8, 'stone_light');
  v.paint(3, 13, 22, 23, -10, 6, 'stone_light');
  v.paint(-15, 15, 0, 1, -13, 13, 'stone_dark');
  v.paint(-15, 15, 5, 6, -13, 13, 'stone_dark'); v.paint(-13, 6, 20, 21, -11, 8, 'stone_dark');   // its courses
  v.paint(10, 12, 9, 11, 12, 13, 'ore_gold'); v.paint(14, 15, 13, 15, 2, 4, 'ore_copper');
  const mouth = [[-11, 7, 2, 5], [-12, 8, 5, 9], [-11, 7, 9, 12], [-10, 5, 12, 15], [-8, 3, 15, 17], [-6, 0, 17, 18]];   // a ragged mouth
  v.paint(-13, 9, 1, 19, -1, 12, 'stone_dark');               // its walls in shadow
  for (const [x0, x1, y0, y1] of mouth) v.box(x0, x1, y0, y1, 0, 13, null);
  for (const [x0, x1, y0, y1] of mouth) v.box(x0, x1, y0, y1, -1, 0, 'char');   // the dark far end
  v.paint(-8, 2, 1, 2, 3, 11, 'hay_dark');                    // lamplight on the floor
  v.paint(-8, 2, 5, 14, -1, 0, 'bark_dark');                  // and on the far wall
  v.box(-10, -9, 13, 15, 8, 12, 'stone_dark'); v.box(3, 4, 13, 15, 8, 12, 'stone_dark');   // drips from the roof
  v.box(-6, -5, 16, 17, 8, 12, 'stone_dark');
  const holes = new Set();
  for (const [x0, x1, y0, y1] of mouth) for (let x = x0; x < x1; x++) for (let y = y0; y < y1; y++) holes.add(x + ',' + y);
  for (let x = -14; x < 10; x++) for (let y = 1; y < 20; y++) {   // the highlight round the mouth
    if (holes.has(x + ',' + y)) continue;
    if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => holes.has((x + dx) + ',' + (y + dy)))) v.paint(x, x + 1, y, y + 1, 12, 13, 'cave_line');
  }
  v.box(-4, -2, 13, 17, 6, 8, 'iron_dark');                   // the chain
  v.box(-5, -1, 7, 13, 5, 9, 'brass');                        // the lantern
  v.paint(-5, -1, 8, 12, 8, 9, 'flame_mid'); v.paint(-2, -1, 8, 12, 5, 9, 'flame_mid');
  v.paint(-4, -2, 9, 11, 8, 9, 'flame_core'); v.paint(-2, -1, 9, 11, 6, 8, 'flame_core');
  v.box(-6, 0, 13, 14, 4, 10, 'brass_dark'); v.box(-6, 0, 6, 7, 4, 10, 'brass_dark');
}, { yaw: 25 });

// Dwarf tools: an elder dwarf's head from the real parts, bald and white-bearded so it is
// not Colony's ginger one (the third tints, hair3 and skin2), with a brass cog at its beard.
const ELDER = { hair: 'hair3', hair_mid: 'hair3_mid', hair_shade: 'hair3_shade', skin: 'skin2',
  skin_shade: 'skin_shade2', nose: 'nose2', blush: 'blush2', mouth: 'mouth2' };
define('dev_dwarf_tools', v => {
  for (const part of ['body/head_elder', 'body/eyes', 'eyebrows/brows_m_bushy', 'hair/hair_m_shaved', 'beards/beard_forked'])
    replayInto(v, D.build(part).log, [-5, 0, -2], ELDER);
  cog(v, 10, 31, 11, 15);
}, { yaw: 32 });

// Water: a stone channel with a plank gate across it, the water spilling over the step into
// a pool, foaming where it lands.
define('dev_water', v => {
  v.box(-15, 15, 0, 3, -15, 15, 'stone_dark');                // the bed
  v.cut(-15, 15, 3, 18, -15, -1, 2, 'stone');                 // the upper step
  v.paint(-15, 15, 17, 18, -15, -1, 'stone_light');
  v.paint(-15, 15, 10, 11, -15, -1, 'stone_dark'); v.paint(-15, 15, 3, 4, -15, -1, 'stone_dark');
  for (const [x, y0, y1] of [[-11, 4, 10], [9, 11, 17], [-9, 11, 17]]) v.paint(x, x + 1, y0, y1, -2, -1, 'stone_dark');
  v.box(-7, 7, 12, 18, -15, -1, null);                        // the channel through it
  v.box(-7, 7, 12, 16, -15, -1, 'water'); v.paint(-7, 7, 15, 16, -15, -1, 'water_light');
  v.box(-9, -7, 12, 25, -11, -8, 'bark'); v.box(7, 9, 12, 25, -11, -8, 'bark');   // the gate's posts
  v.paint(-9, -7, 24, 25, -11, -8, 'wood_top'); v.paint(7, 9, 24, 25, -11, -8, 'wood_top');
  v.box(-7, 7, 14, 23, -10, -9, 'riven');                     // the gate, lifted off the bed
  for (const x of [-3, 1, 4]) v.paint(x, x + 1, 14, 23, -10, -9, 'riven_dark');
  v.box(-8, 8, 22, 24, -11, -8, 'bark_light');
  v.box(-7, 7, 4, 16, -1, 1, 'water');                        // the fall
  for (const x of [-6, -2, 3]) v.paint(x, x + 1, 5, 16, 0, 1, 'water_light');
  v.box(-15, 15, 3, 6, -1, 15, 'stone');                      // the pool's rim
  v.paint(-15, 15, 5, 6, -1, 15, 'stone_light');
  v.box(-12, 12, 4, 6, -1, 12, null);
  v.box(-12, 12, 4, 5, -1, 12, 'water_dark');                 // the pool
  v.paint(-12, 12, 4, 5, 5, 12, 'water');
  v.box(-9, 9, 4, 6, 1, 4, 'foam'); v.box(-7, 7, 5, 7, 1, 3, 'foam');   // foam where it lands
  for (const [x, z] of [[-10, 7], [8, 8], [1, 9]]) v.box(x, x + 3, 4, 5, z, z + 1, 'water_light');   // ripples
}, { yaw: 20 });

// Arrival status: the deer's real head, as Events shows a deer's arrival, beside a board
// tallying what came: four strokes struck through and a fifth group begun.
define('dev_arrival_status', v => {
  for (const part of ['deer/neck', 'deer/head', 'deer/ears', 'deer/antlers'])
    replayInto(v, flipZ(W.build(part).log), [-6, -18, -4], own('deer'));
  v.box(10, 12, -3, 4, 4, 6, 'bark');                         // the board's post
  v.cut(2, 20, 3, 13, 5, 7, 1, 'riven');                      // the board
  v.paint(2, 20, 12, 13, 5, 7, 'wood_top'); v.paint(2, 20, 3, 4, 5, 7, 'riven_dark');
  for (const x of [4, 6, 8, 10]) v.paint(x, x + 1, 5, 11, 6, 7, 'char');
  v.paint(3, 12, 7, 8, 6, 7, 'char'); v.paint(3, 4, 8, 9, 6, 7, 'char'); v.paint(11, 12, 6, 7, 6, 7, 'char');
  for (const x of [14, 16]) v.paint(x, x + 1, 5, 11, 6, 7, 'char');
}, { yaw: 32 });

// Item stamper: a hewn stamp with a red knob, lifted off a flagged floor where it has just
// set down a log and a rough stone; its shadow on the flags below.
define('dev_item_stamper', v => {
  v.box(-15, 15, 0, 2, -15, 15, 'stone'); v.paint(-15, 15, 1, 2, -15, 15, 'stone_light');
  for (const c of [-5, 5]) { v.paint(c, c + 1, 1, 2, -15, 15, 'stone_dark'); v.paint(-15, 15, 1, 2, c, c + 1, 'stone_dark'); }
  v.paint(-14, 1, 1, 2, -13, 2, 'stone_dark');                // its shadow
  logX(v, -1, 14, 2, 6, 6);                                   // what it set down
  v.cut(5, 13, 2, 9, -5, 3, 2, 'stone'); v.paint(5, 13, 8, 9, -5, 3, 'stone_light');
  v.cut(-15, 2, 9, 16, -14, 3, 1, 'wood_side');               // the stamp's block
  v.paint(-15, 2, 15, 16, -14, 3, 'wood_top');
  v.paint(-15, 2, 9, 11, -14, 3, 'wood_dark');                // its pad
  v.box(-9, -4, 16, 21, -8, -3, 'wood');                      // the neck
  v.cut(-12, -1, 21, 29, -11, 0, 3, 'apple');                 // the knob
  v.paint(-12, -1, 28, 29, -11, 0, 'apple_light'); v.paint(-12, -1, 21, 22, -11, 0, 'apple_dark');
}, { yaw: -15 });

// Remove objects: a patch of grass where the tool's red outline rings a pine that is going,
// its crown coming apart into loose cubes that drift off; a boulder and a low blueberry bush
// wait beside it.
define('dev_remove_objects', v => {
  v.box(-15, 15, 0, 4, -15, 15, 'earth');                     // the ground
  v.paint(-15, 15, 3, 4, -15, 15, 'grass'); v.paint(-15, 15, 0, 1, -15, 15, 'earth_dark');
  for (const [x, z] of [[-13, 9], [7, -13], [-2, 12]]) v.paint(x, x + 4, 3, 4, z, z + 3, 'grass_light');
  for (const [x0, x1, z0, z1] of [[-15, 1, -15, -13], [-15, 1, -1, 1], [-15, -13, -15, 1], [-1, 1, -15, 1]])
    v.box(x0, x1, 4, 5, z0, z1, 'apple');                     // the red outline, lying on the grass
  v.box(-9, -5, 4, 12, -9, -5, 'bark'); v.paint(-9, -8, 4, 12, -6, -5, 'bark_light');   // the trunk
  v.cut(-13, -1, 11, 15, -13, -1, 3, 'pine_dark');            // the lowest tier, still whole
  v.paint(-13, -1, 14, 15, -13, -1, 'pine');
  v.cut(-11, -3, 15, 18, -11, -3, 2, 'pine');                 // the next, breaking up
  for (const [x0, x1, z0, z1] of [[-5, -3, -11, -8], [-11, -8, -5, -3], [-6, -3, -6, -3]]) v.box(x0, x1, 15, 18, z0, z1, null);
  for (const [x, y, z, s, c] of [[-10, 19, -9, 3, 'pine'], [-6, 20, -10, 3, 'pine_light'], [-8, 22, -6, 3, 'pine'],
    [-3, 23, -8, 2, 'pine_light'], [-11, 25, -5, 2, 'pine'], [-5, 26, -3, 2, 'pine_light'], [-1, 28, -7, 2, 'pine'],
    [-8, 29, -10, 1, 'pine_light'], [1, 30, -4, 1, 'pine_light']])
    v.box(x, x + s, y, y + s, z, z + s, c);                   // its crown, drifting off in cubes
  v.cut(3, 13, 4, 10, 3, 13, 3, 'stone');                     // a boulder
  v.cut(4, 12, 10, 13, 4, 12, 3, 'stone_light'); v.paint(3, 13, 4, 5, 3, 13, 'stone_dark');
  v.paint(8, 9, 6, 10, 12, 13, 'stone_dark');                 // a crack in its face
  v.cut(-14, -6, 4, 9, 5, 13, 3, 'bush_dark');                // a low blueberry bush
  v.cut(-13, -7, 9, 11, 6, 12, 2, 'bush'); v.paint(-12, -8, 10, 11, 7, 11, 'bush_light');
  for (const [x, y, z] of [[-11, 5, 11], [-8, 7, 10], [-7, 5, 7], [-11, 9, 9], [-9, 10, 6]])
    v.paint(x, x + 2, y, y + 2, z, z + 2, 'berry_blue');      // its berries
}, { yaw: 25 });

// Time & weather: an hourglass half run through, beside the Sky Dial's rain cloud.
define('dev_time_weather', v => {
  v.cut(-13, 5, 0, 3, -6, 6, 1, 'riven'); v.paint(-13, 5, 2, 3, -6, 6, 'wood_top');
  v.cut(-13, 5, 27, 30, -6, 6, 1, 'riven'); v.paint(-13, 5, 29, 30, -6, 6, 'wood_top');
  for (const x of [-12, 2]) for (const z of [-5, 3]) v.box(x, x + 2, 3, 27, z, z + 2, 'wood_side');
  v.cutZ(-10, 2, 3, 13, -3, 3, 3, 'glass');                   // the lower bulb
  v.cutZ(-6, -2, 12, 18, -2, 2, 1, 'glass');                  // the neck
  v.cutZ(-10, 2, 17, 27, -3, 3, 3, 'glass');                  // the upper bulb
  v.paint(-10, 2, 3, 8, -3, 3, 'hay'); v.paint(-7, -1, 8, 10, -3, 3, 'hay');   // sand run through
  v.paint(-5, -3, 10, 18, -3, 3, 'straw');                    // the stream
  v.paint(-10, 2, 17, 21, -3, 3, 'hay');                      // sand still to run
  v.paint(-9, -8, 21, 25, 2, 3, 'glass_light'); v.paint(-9, -8, 6, 11, 2, 3, 'glass_light');
  replayInto(v, S.build('sky/storm_small').log, [9, 19, 6]);
  for (const [x, y] of [[4, 13], [8, 11], [12, 14], [15, 11]]) { v.box(x, x + 1, y, y + 3, 7, 8, 'rain'); v.box(x - 1, x, y - 2, y, 7, 8, 'rain'); }
}, FACE);

// ── Dwarf stats (doc 41 "Stats") ────────────────────────────────────────────────────
// The six stats on the character sheet's Traits tab and the career map. Wits is
// dividers, not a cog: the System menu's picture is already a cog.

// Strength: a clenched mitten fist raised from its sleeve, the curled fingers and the
// thumb across them facing the camera, the knuckles on top.
define('stat_strength', v => {
  v.cut(-8, 8, 0, 7, -6, 5, 2, 'tunic_dark');                 // the sleeve
  v.paint(-8, 8, 6, 7, -6, 5, 'tunic');
  v.cut(-10, 10, 7, 22, -6, 3, 2, 'skin2');                    // the back of the fist
  for (let i = 0; i < 4; i++) {                                // four curled fingers, grooved apart
    const x0 = -10 + 5 * i;
    v.cut(x0, x0 + 4, 13, 25, -2, 6, 1, 'skin2');
    v.paint(x0, x0 + 4, 24, 25, -2, 6, 'skin');                // the knuckle, lit
    v.paint(x0, x0 + 4, 18, 19, 5, 6, 'skin_shade2');          // the middle joint
    v.paint(x0, x0 + 4, 13, 14, -2, 6, 'skin_shade2');         // tucked under
  }
  v.cut(-11, 3, 9, 14, 5, 10, 1, 'skin2');                     // the thumb across them
  v.paint(-11, 3, 13, 14, 5, 10, 'skin'); v.paint(-11, 3, 9, 10, 5, 10, 'skin_shade2');
  v.cut(1, 5, 9, 14, 4, 9, 1, 'skin2'); v.paint(1, 5, 13, 14, 4, 9, 'skin');
}, { yaw: 30 });

// Agility: a dwarf's square boot, doubled, with a white wing at its ankle.
define('stat_agility', v => {
  v.cut(-16, 7, 0, 3, -6, 6, 2, 'sole');                       // the sole, the toe to the left
  v.cut(-16, -1, 3, 10, -6, 6, 2, 'boot');                     // the round-square toe
  v.paint(-16, -1, 9, 10, -6, 6, 'boot_light');                // its cap, lit
  v.cut(-3, 7, 3, 22, -6, 6, 2, 'boot');                       // the shaft
  v.cut(-4, 8, 22, 26, -7, 7, 2, 'boot_dark');                 // the folded cuff
  v.paint(-4, 8, 25, 26, -7, 7, 'boot_light'); v.box(-2, 6, 25, 26, -5, 5, 'boot_dark');
  for (const [z0, z1] of [[6, 8], [-8, -6]]) {                 // a wing each side: three feathers fanned back
    v.box(6, 15, 14, 17, z0, z1, 'snow'); v.box(15, 17, 14, 16, z0, z1, 'snow_shade');
    v.box(6, 16, 18, 21, z0, z1, 'snow'); v.box(16, 18, 19, 21, z0, z1, 'snow_shade');
    v.box(6, 11, 22, 25, z0, z1, 'snow'); v.box(9, 14, 24, 27, z0, z1, 'snow'); v.box(12, 16, 26, 29, z0, z1, 'snow');
    v.box(14, 16, 29, 31, z0, z1, 'snow_shade');
    for (const y of [14, 18, 22]) v.paint(6, 18, y, y + 1, z0, z1, 'snow_shade');   // each feather's shaded underside
    v.cut(3, 9, 13, 26, z0, z1 + (z0 > 0 ? 1 : 0), 1, 'linen');   // the root at the ankle
  }
}, FACE);

// Toughness: a round shield, oak planks in an iron rim, a steel boss and brass rivets.
define('stat_toughness', v => {
  v.cutZ(-14, 14, 0, 28, -2, 2, 8, 'iron');                    // the rim
  v.cutZ(-12, 12, 2, 26, 2, 3, 7, 'wood_side');                // the planks, proud of it
  for (const x of [-6, 0, 6]) v.paint(x, x + 1, 2, 26, 2, 3, 'wood_dark');
  v.paint(-12, 12, 24, 26, 2, 3, 'wood_top');
  v.cutZ(-5, 5, 9, 19, 3, 6, 3, 'steel'); v.paint(-5, 5, 9, 11, 3, 6, 'iron');              // the boss
  v.box(-3, -1, 15, 17, 6, 7, 'glint');
  for (const [x, y] of [[-1, 26], [-1, 0], [-14, 13], [12, 13]]) v.box(x, x + 2, y, y + 2, 2, 3, 'brass');   // rivets
}, FACE);

// Wits: brass dividers stood open, steel points down: the clever hand's instrument.
define('stat_wits', v => {
  for (let i = 0; i < 11; i++) {                               // the legs, spreading from the hinge
    const dx = Math.round(i * 0.9);
    v.box(-3 - dx, -dx, 22 - 2 * i, 25 - 2 * i, -1, 2, i < 9 ? 'brass' : 'steel');
    v.box(dx, 3 + dx, 22 - 2 * i, 25 - 2 * i, -1, 2, i < 9 ? 'brass' : 'steel');
  }
  v.cutZ(-4, 4, 23, 30, -2, 3, 2, 'brass');                    // the hinge
  v.paint(-4, 4, 29, 30, -2, 3, 'brass_light'); v.box(-1, 1, 25, 27, 3, 4, 'brass_dark');   // its pin
  v.box(-1, 1, 30, 34, -1, 2, 'brass_dark');                   // the handle
  v.box(-7, 7, 13, 15, -1, 1, 'brass_dark');                   // the arc that sets the spread
}, FACE);

// Wisdom: a brown owl on a branch, its round cream face and gold eyes on the camera.
define('stat_wisdom', v => {
  v.box(-15, 15, 0, 3, -2, 2, 'bark'); v.paint(-15, 15, 2, 3, -2, 2, 'bark_light');   // the branch
  for (const x of [-5, 2]) v.box(x, x + 3, 3, 5, 0, 3, 'brass_dark');                // talons
  v.cut(-9, 9, 4, 20, -5, 5, 3, 'bark_light');                 // the body
  v.paint(-9, -6, 5, 18, -5, 5, 'bark'); v.paint(6, 9, 5, 18, -5, 5, 'bark');        // folded wings
  v.paint(-5, 5, 6, 16, 2, 5, 'deer_cream');                   // the breast
  for (const [x, y] of [[-3, 13], [1, 12], [-1, 9], [2, 8], [-4, 7]]) v.paint(x, x + 1, y, y + 1, 4, 5, 'bark');   // its specks
  v.cut(-10, 10, 19, 30, -5, 5, 3, 'bark_light');              // the head
  v.box(-10, -6, 30, 33, -2, 2, 'bark_dark'); v.box(6, 10, 30, 33, -2, 2, 'bark_dark');   // ear tufts
  v.cutZ(-9, 0, 20, 29, 4, 6, 2, 'deer_cream'); v.cutZ(0, 9, 20, 29, 4, 6, 2, 'deer_cream');   // the face
  v.cutZ(-7, -2, 22, 27, 6, 7, 1, 'ore_gold'); v.cutZ(2, 7, 22, 27, 6, 7, 1, 'ore_gold');      // the eyes
  v.box(-5, -3, 23, 26, 7, 8, 'char'); v.box(3, 5, 23, 26, 7, 8, 'char');
  v.box(-5, -4, 25, 26, 8, 9, 'glint'); v.box(3, 4, 25, 26, 8, 9, 'glint');
  v.box(-8, -2, 28, 29, 6, 7, 'bark_dark'); v.box(2, 8, 28, 29, 6, 7, 'bark_dark');   // the brows
  v.box(-1, 1, 18, 22, 6, 8, 'hay_dark');                      // the beak
}, FACE);

// Charisma: two dwarves' mittens clasped in greeting, rising from a teal sleeve and a rust one.
define('stat_charisma', v => {
  for (let i = 0; i < 5; i++) {                                // the two sleeves, rising to meet
    v.box(-16 + 2 * i, -9 + 2 * i, 2 * i, 7 + 2 * i, -4, 3, 'tunic');
    v.box(9 - 2 * i, 16 - 2 * i, 2 * i, 7 + 2 * i, -3, 4, 'rust');
  }
  v.paint(-8, -6, 8, 15, -4, 3, 'tunic_light'); v.paint(6, 8, 8, 15, -3, 4, 'rust_light');   // the cuffs' lit rims
  v.cut(-8, 5, 13, 22, -4, 3, 2, 'skin'); v.paint(-8, 5, 13, 15, -4, 3, 'skin_shade');       // the left hand
  v.cut(-4, 8, 14, 23, 0, 6, 2, 'skin2'); v.paint(-4, 8, 14, 16, 0, 6, 'skin_shade2');      // the right hand, in front
  for (let i = 0; i < 3; i++) {                                // its fingers wrapped over the left hand
    v.box(-8, -3, 15 + 2 * i, 17 + 2 * i, 3, 6, 'skin2');
    v.paint(-8, -3, 15 + 2 * i, 16 + 2 * i, 5, 6, 'skin_shade2');
  }
  v.cut(-3, 5, 22, 26, 1, 5, 1, 'skin2'); v.paint(-3, 5, 25, 26, 1, 5, 'skin');             // the right thumb on top
  v.box(1, 7, 21, 24, -3, 1, 'skin');                          // the left thumb behind it
}, FACE);

export function build(name) { const v = new Vox(); icons[name](v); return v; }
export function options(name) { return settings[name]; }
export const NAMES = Object.keys(icons);

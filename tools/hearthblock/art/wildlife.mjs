// Hearthblock wildlife (doc 256): square chibi blocks. Every animal faces -Z. Rigs
// follow the art (owner rule, 2026-10-21): each species' joints live in its
// data/entities/animals/*.json visual_pose. Parts are authored in standing world
// cells; legs, wings and feet in their own frames.
import * as P from './proposal.mjs';

const { Vox } = P;
const parts = {};
const define = (name, fn) => { parts[name] = fn; };

// ── Rabbit (chibi): a big square head with front bead eyes and chubby cheeks on a
// small loaf, big hind feet, one tall ear and one that flops. Still one block
// front to back and side to side (its navigation footprint). Joints in
// rabbit.json visual_pose: head (0, 8, -2), ears (0, 16, -4) cells.
define('rabbit/body', v => {
  v.cut(-5, 5, 1, 9, -3, 6, 2, 'fur');                  // a small loaf
  v.cut(-4, 4, 9, 10, -2, 5, 2, 'fur');                 // rounded back
  v.paint(-5, 5, 1, 3, -3, 6, 'shade');                 // darker flanks low down
  v.paint(-3, 3, 1, 2, -2, 5, 'cream');                 // pale belly
  v.cut(-3, 3, 2, 7, -5, -3, 1, 'cream');               // chest under the chin
  v.both(s => {
    s.cut(-6, -3, 1, 7, 0, 6, 1, 'fur');                // chunky haunches
    s.box(-6, -2, 0, 2, 0, 8, 'fur'); s.paint(-6, -2, 0, 1, 0, 8, 'cream');   // big hind feet
    s.box(-4, -2, 0, 3, -6, -3, 'cream');               // front paws
  });
  v.cut(-2, 2, 4, 8, 6, 8, 0, 'cream');                 // cotton tail
});

define('rabbit/head', v => {
  v.cut(-6, 6, 6, 16, -8, 0, 2, 'fur');                 // the big square head
  v.cut(-7, 7, 7, 12, -7, -2, 2, 'fur');                // chubby cheeks
  v.paint(-3, 3, 6, 10, -8, -7, 'cream');               // muzzle
  v.paint(-1, 1, 9, 10, -8, -7, 'nose');                // button nose
  v.paint(-4, -2, 11, 14, -8, -7, 'eye'); v.paint(-4, -3, 13, 14, -8, -7, 'glint');   // big bead eyes on the face
  v.paint(2, 4, 11, 14, -8, -7, 'eye'); v.paint(2, 3, 13, 14, -8, -7, 'glint');
  v.paint(-6, 6, 6, 7, -7, 0, 'cream');                 // pale chin
});

define('rabbit/ears', v => {
  v.box(-5, -2, 16, 24, -5, -2, 'fur'); v.paint(-4, -3, 17, 23, -5, -4, 'ear');   // one tall ear
  v.box(2, 5, 16, 20, -5, -2, 'fur'); v.paint(3, 4, 17, 19, -5, -4, 'ear');       // and one that flops
  v.box(4, 8, 18, 21, -5, -2, 'fur'); v.paint(5, 7, 19, 20, -5, -4, 'ear');
});

// ── Deer (chibi rig, owner-approved 2026-10-21): short chunky legs, a big head,
// stubby neck and compact antlers. Pivots live in deer.json visual_pose: neck
// (0, 19, -6), head (0, 28, -8), ears (0, 35, -6) cells; hips (±5, 10, ±6) with
// the knee 5 cells below and the hoof sole at -10 in the hip frame.
define('deer/body', v => {
  v.cut(-7, 7, 9, 23, -9, 10, 3, 'coat');               // a short, deep barrel
  v.cut(-6, 6, 23, 24, -8, 9, 3, 'back');
  v.paint(-7, 7, 9, 13, -9, 10, 'shade'); v.paint(-5, 5, 9, 10, -7, 8, 'cream');
  v.box(-3, 3, 14, 21, 10, 12, 'cream');                // white rump
  v.box(-2, 2, 19, 22, 11, 12, 'coat');                 // stub tail
});
define('deer/neck', v => {
  v.box(-3, 3, 18, 26, -9, -4, 'coat');                 // a stubby neck
  v.paint(-2, 2, 18, 26, -9, -8, 'cream');
});
define('deer/head', v => {
  v.cut(-6, 6, 24, 36, -12, -1, 3, 'coat');             // big square head (not quite body-wide)
  v.paint(-5, 5, 35, 36, -11, -2, 'back');              // lighter crown
  v.box(-3, 3, 24, 30, -18, -12, 'coat');               // a longer snout keeps it a deer
  v.paint(-3, 3, 24, 27, -18, -12, 'cream'); v.paint(-2, 2, 28, 30, -18, -17, 'nose');
  v.box(-6, -4, 30, 33, -13, -12, 'pupil'); v.box(-6, -5, 32, 33, -13, -12, 'eye');   // big bead eyes
  v.box(4, 6, 30, 33, -13, -12, 'pupil'); v.box(4, 5, 32, 33, -13, -12, 'eye');
});
define('deer/ears', v => v.both(s => {
  s.box(-12, -6, 32, 36, -6, -3, 'coat'); s.paint(-11, -7, 33, 35, -6, -5, 'ear');   // big ears, out to the sides
  s.box(-13, -12, 33, 37, -6, -3, 'coat');
}));
define('deer/antlers', v => v.both(s => {
  s.box(-4, -2, 36, 42, -7, -5, 'antler');              // short beam
  s.box(-7, -4, 40, 42, -7, -5, 'antler'); s.box(-7, -5, 42, 45, -7, -5, 'antler');
  s.box(-4, -2, 42, 46, -6, -4, 'antler'); s.box(-3, -1, 43, 46, -4, -2, 'antler');   // tines, one leaning back
  s.box(-5, -3, 39, 41, -10, -7, 'antler');              // brow tine
}));
define('deer/leg', v => {
  v.cut(-2, 2, -5, 2, -2, 2, 1, 'coat');                // short thigh (Upper, down to the knee)
  v.box(-2, 2, -8, -5, -2, 2, 'coat'); v.paint(-2, 2, -8, -7, -2, 2, 'shade');   // shin (Lower)
  v.box(-2, 2, -9, -8, -2, 2, 'hoof'); v.box(-2, 2, -10, -9, -1, 1, 'hoof');     // hoof, sole narrowing
});

// ── Wolf (chibi rig, doc 256): half-length chunky legs, a big head with amber eyes
// over a squared snout, tall stepped ears and a bushy tail that curls up. Pivots live
// in wolf.json visual_pose: head (0, 18, -11), tail (0, 16, 12) cells; hips
// (±6, 8, ±8) with the knee 4 cells below and the paw sole at -8 in the hip frame.
define('wolf/body', v => {
  v.cut(-8, 8, 7, 20, -12, 12, 3, 'fur');               // a short, deep barrel
  v.cut(-7, 7, 20, 22, -10, 10, 3, 'shade');            // darker saddle
  v.paint(-6, 6, 7, 9, -10, 10, 'cream');               // pale belly
  v.cut(-7, 7, 8, 19, -14, -11, 2, 'light');            // chest ruff
  v.paint(-4, 4, 8, 15, -14, -13, 'cream');
});
define('wolf/head', v => {
  v.cut(-8, 8, 15, 29, -24, -10, 3, 'fur');             // big square head
  v.paint(-6, 6, 28, 29, -22, -12, 'light');            // lighter brow
  v.box(-4, 4, 15, 21, -30, -24, 'fur');                // squared snout
  v.paint(-4, 4, 20, 21, -30, -24, 'light'); v.paint(-4, 4, 15, 17, -30, -24, 'cream');
  v.box(-2, 2, 19, 21, -31, -29, 'nose');
  v.box(-9, -8, 15, 23, -20, -12, 'light'); v.box(8, 9, 15, 23, -20, -12, 'light');     // cheek ruff
  v.box(-6, -3, 22, 25, -25, -24, 'eye'); v.box(-6, -5, 24, 25, -25, -24, 'glint');    // amber bead eyes
  v.box(3, 6, 22, 25, -25, -24, 'eye'); v.box(3, 4, 24, 25, -25, -24, 'glint');
});
define('wolf/ears', v => v.both(s => {                  // tall stepped triangles
  s.box(-8, -3, 29, 33, -17, -13, 'fur'); s.box(-7, -4, 33, 36, -16, -14, 'fur'); s.box(-6, -5, 36, 38, -16, -15, 'shade');
  s.paint(-7, -4, 30, 34, -17, -16, 'ear');
}));
define('wolf/tail', v => {                              // bushy, curling up behind
  v.box(-3, 3, 15, 21, 12, 17, 'fur');
  v.box(-3, 3, 17, 23, 17, 21, 'fur');
  v.box(-2, 2, 20, 24, 20, 24, 'shade');
  v.box(-2, 2, 23, 26, 22, 25, 'cream');                // pale tip
});
define('wolf/leg', v => {
  v.cut(-3, 3, -4, 2, -3, 3, 1, 'fur');                 // short thigh (Upper, down to the knee)
  v.box(-3, 3, -6, -4, -3, 3, 'shade');                 // shin (Lower)
  v.box(-3, 3, -7, -6, -4, 3, 'shade'); v.paint(-3, 3, -7, -6, -4, -3, 'cream');        // big paw, pale toes
  v.box(-3, 3, -8, -7, -2, 2, 'shade');                 // a narrower sole, so a striding paw stays above ground
});

// ── Ducks (chibi): a big square head with a wide flat bill on a round little hull,
// a stub tail and big paddles. Male and female share every cell and differ only in
// colour. Joints in duck.json visual_pose: head (0, 10, -3) cells; open wings along
// +X from (±4, 10, 0); feet in their own frame at (±2.7, 0, 0.3). The folded
// wings are their own mesh on the flanks, shown whenever the duck is not flying.
for (const sex of ['male', 'female']) {
  const c = (role) => sex + '_' + role;                  // sex-specific swatches
  define(`duck/${sex}_body`, v => {
    v.cut(-5, 5, 3, 10, -5, 7, 2, c('coat'));            // a round little hull
    v.cut(-4, 4, 10, 11, -3, 6, 2, c('coat'));           // rounded back
    v.cut(-4, 4, 4, 9, -6, -4, 1, c('breast'));          // chest
    v.box(-3, 3, 7, 10, 7, 9, 'dark'); v.box(-2, 2, 10, 12, 8, 10, 'dark');   // stub tail with an up-curl
    v.paint(-4, 4, 3, 4, -4, 6, sex === 'male' ? 'ring' : c('breast'));      // pale underside
  });
  define(`duck/${sex}_head`, v => {
    v.cut(-5, 5, 10, 19, -8, 0, 2, c('crown'));          // the big square head
    v.box(-3, 3, 12, 14, -12, -8, c('bill'));            // a wide flat bill
    v.box(-2, 2, 14, 15, -11, -8, c('bill'));            // with a ridge
    v.paint(-5, 5, 10, 11, -8, 0, sex === 'male' ? 'ring' : c('breast'));   // the drake's white ring
    v.box(-6, -5, 14, 17, -6, -3, 'eye'); v.box(-6, -5, 16, 17, -6, -5, 'ring');   // bead eyes with a glint
    v.box(5, 6, 14, 17, -6, -3, 'eye'); v.box(5, 6, 16, 17, -6, -5, 'ring');
  });
  define(`duck/${sex}_wing`, v => {                      // open, along +X from the shoulder
    v.box(0, 9, 0, 3, -3, 4, c('coat'));                 // inner wing
    v.box(9, 13, 0, 2, -3, 3, 'dark');                   // primaries
    v.paint(3, 8, 2, 3, 0, 4, 'speculum');               // the blue patch reads on top
    v.paint(0, 9, 0, 1, -3, 4, 'dark');
  });
  define(`duck/${sex}_wing_folded`, v => v.both(s => {   // tucked along both flanks
    s.cut(-7, -4, 5, 10, -3, 7, 1, c('coat'));
    s.box(-6, -4, 10, 11, -1, 6, c('coat'));             // the wing's top edge
    s.paint(-7, -6, 6, 8, 2, 6, 'speculum');             // the blue patch along the folded edge
    s.box(-6, -3, 8, 10, 7, 11, 'dark');                 // primaries cross over the tail
  }));
}
define('duck/foot', v => {
  v.box(-1, 1, 1, 4, -1, 1, 'foot');                    // short leg
  v.box(-2, 2, 0, 1, -4, 1, 'foot');                    // a big webbed paddle
  v.box(-2, -1, 0, 1, -5, -4, 'foot'); v.box(1, 2, 0, 1, -5, -4, 'foot');   // toes
});

export function build(name) { const v = new Vox(); parts[name](v); return v; }
export const NAMES = Object.keys(parts);

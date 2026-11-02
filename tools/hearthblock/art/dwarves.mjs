// Hearthblock dwarf parts for every appearance (2026-10-20, doc 256).
// The square head, body, mitten hands, boots and bead eyes come from the approved
// proposal (Brann/Sigrun/Thrain); every hairstyle, beard and brow keeps its game
// ID and is redrawn for the square head in the same vocabulary. The art no longer
// fits inside the old rig shapes (owner rule, 2026-10-21); what still binds it is
// gameplay: at a table the seated head sits 6 cells up and 3 back, so anything on
// the head below y 18 stays within z 11 (test_log_table checks every cell against
// the tabletop); beards end at y >= 12 so striding boots pass beneath them; nothing
// rises above y 54. A lying head rests on its lowest cell (DwarfRestBehavior), so
// a back bun is fine.
// Head: x -13..12, y 29..49 (jaw from 29), z -9..9 (face plane z = 10), ears at
// x ±13..15. Layout rules that keep any combination free of overlaps:
//   fringes start at y 45; brows stay in y 40..44 on the face (z 10..12);
//   male hair in front of the ear (z >= 2, |x| >= 11) starts at y 43, beard
//   sideburns stop at y 42. Overlaps with the body are clipped by dwarves.py,
//   so a beard that hangs over the belly keeps two cells in front of the buckle.
import * as P from './proposal.mjs';

const { Vox } = P;
const parts = {};
const define = (name, fn) => { parts[name] = fn; };

// ── Shared pieces ────────────────────────────────────────────────────────────
function domeTiers(v, a = 'hair', b = 'hair') {
  v.cut(-14, 14, 48, 51, -10, 11, 4, a);
  v.cut(-12, 12, 51, 53, -8, 9, 4, b);
}
function backMass(v, y0, c = 'hair_shade') { v.cut(-14, 14, y0, 49, -11, -4, 2, c); }
function sides(v, { low = 38, front = 43, frontZ = 4, c = 'hair_mid' } = {}) {
  v.both(s => { s.box(-15, -12, low, 49, -9, -2, c); s.box(-15, -12, front, 49, -2, frontZ, c); });
}
// A plait hanging along Y: three-cell lobes pinched by a darker cell, then a tie
// and a flared tuft. Cross-section x0..x1 by z0..z1.
function braid(v, x0, x1, z0, z1, top, bottom) {
  let y = top, i = 0;
  while (y - 7 >= bottom) {
    v.cut(x0, x1, y - 3, y, z0, z1, 1, i % 2 ? 'hair_mid' : 'hair');
    v.box(x0 + 1, x1 - 1, y - 4, y - 3, z0 + 1, z1 - 1, 'hair_shade');
    y -= 4; i++;
  }
  v.box(x0 + 1, x1 - 1, y - 1, y, z0 + 1, z1 - 1, 'hair_shade');           // tie
  v.cut(x0, x1, y - 4, y - 1, z0, z1, 1, 'hair');                           // tuft
  v.paint(x0, x1, y - 4, y - 3, z0, z1, 'hair_mid');
}

// ── Heads: four ages on the proposal's square head ───────────────────────────
define('body/head_adult', v => { P.head(v, {}); P.smile(v); });
define('body/head_young', v => { P.head(v, {}); P.smile(v); v.box(-2, 2, 38, 39, 10, 12, null); });   // smaller button nose
define('body/head_middle', v => {
  P.head(v, {}); P.smile(v);
  v.paint(-5, 5, 46, 47, 9, 10, 'skin_shade');                                // one forehead line
  v.paint(-6, -5, 32, 34, 8, 9, 'skin_shade'); v.paint(5, 6, 32, 34, 8, 9, 'skin_shade');   // smile lines
});
define('body/head_elder', v => {
  P.head(v, { dome: true, wrinkles: true }); P.smile(v);
  v.paint(-13, -10, 39, 41, 6, 10, 'skin_shade'); v.paint(10, 13, 39, 41, 6, 10, 'skin_shade'); // crow's feet
  v.paint(-6, -5, 32, 34, 8, 9, 'skin_shade'); v.paint(5, 6, 32, 34, 8, 9, 'skin_shade');
});
define('body/eyes', v => P.eyes(v));
define('body/body_base', v => P.body(v, ['tunic', 'tunic_dark', 'tunic_light']));
// The proposal's mitten with its tunic cuff, and its cuffed boot. The mitten is
// centred on the palm (17, 20, 3), the grip every work pose uses; the relaxed
// stance hangs it under the sleeve as on the proposal page (proportions.json).
// The cuff is a separate untinted mesh in hand.glb, so the skin tint never
// colours it. The boot is the proposal's, shifted so its 4-cell gap to the
// other boot survives the relaxed stance; its sole stays on the ground.
define('body/hand', v => {
  v.cut(14, 20, 17, 23, 0, 6, 1, 'skin');            // 6-cell mitten
  v.paint(14, 20, 17, 19, 0, 6, 'skin_shade');       // shaded underside
  v.box(15, 18, 19, 21, 6, 8, 'skin');               // thumb, forward as in the proposal
});
define('body/hand_cuff', v => v.cut(14, 20, 23, 25, 0, 6, 1, 'tunic_dark'));
define('body/foot', v => {
  v.cut(3, 12, 0, 2, -5, 10, 1, 'sole');
  v.cut(3, 12, 2, 9, -5, 3, 1, 'boot');              // shaft
  v.cut(3, 12, 2, 6, 3, 10, 1, 'boot');              // round-square toe
  v.paint(3, 12, 5, 6, 3, 10, 'boot_light');         // toe cap reads from above
  v.cut(2, 13, 9, 11, -6, 4, 1, 'boot_dark');        // folded cuff, one cell proud all round
  v.paint(2, 13, 10, 11, -6, 4, 'boot_light'); v.paint(3, 12, 10, 11, -5, 3, 'boot_dark');   // lit rim round the opening
});

// ── Men's hair ───────────────────────────────────────────────────────────────
define('hair/hair_m_short_back', v => {           // the proposal's swept cut (Brann)
  v.cut(-14, 14, 34, 49, -11, -4, 2, 'hair_shade');
  v.box(-15, -12, 38, 49, -9, -2, 'hair_mid'); v.box(-15, -12, 43, 49, -2, 4, 'hair_mid');
  v.box(12, 15, 39, 49, -9, -2, 'hair_mid'); v.box(12, 15, 44, 49, -2, 4, 'hair_mid');
  v.box(-15, -13, 35, 38, -7, -2, 'hair_shade');
  v.box(-17, -15, 45, 49, -6, 1, 'hair');
  domeTiers(v);
  v.paint(-6, -5, 51, 53, -8, 11, 'hair_shade');
  v.cut(-13, -6, 45, 49, 9, 12, 1, 'hair'); v.cut(-6, 2, 45, 49, 9, 12, 1, 'hair_mid'); v.cut(2, 12, 46, 49, 9, 11, 1, 'hair');
  v.box(-4, 4, 53, 54, -4, 3, 'hair');
});
define('hair/hair_m_shaved', v => {               // a close crop: one cell over the scalp
  v.cut(-14, 14, 46, 51, -10, 11, 4, 'hair_shade');
  v.box(-13, 13, 38, 46, -10, -9, 'hair_shade');
  v.both(s => s.box(-14, -13, 43, 46, -8, 3, 'hair_shade'));
  v.paint(-9, 9, 50, 51, -6, 7, 'hair_mid');
});
define('hair/hair_m_wild_loose', v => {
  domeTiers(v); v.cut(-15, 15, 34, 49, -12, -4, 2, 'hair_shade');
  v.both(s => { s.box(-16, -12, 38, 49, -9, -2, 'hair_mid'); s.box(-16, -12, 43, 49, -2, 4, 'hair_mid'); });
  v.box(-18, -15, 45, 49, -7, 0, 'hair'); v.box(15, 18, 44, 48, -5, 1, 'hair_mid');
  v.box(-5, 0, 53, 54, -5, 2, 'hair'); v.box(2, 7, 52, 54, -8, -2, 'hair_mid');
  v.box(-14, -10, 32, 38, -11, -7, 'hair'); v.box(10, 14, 33, 37, -12, -8, 'hair_mid');
  v.cut(-13, -8, 45, 49, 9, 13, 1, 'hair'); v.cut(-8, -2, 46, 49, 9, 12, 1, 'hair_mid'); v.cut(-2, 4, 45, 48, 9, 13, 1, 'hair');
  v.cut(4, 9, 46, 49, 9, 12, 1, 'hair_mid'); v.cut(9, 13, 45, 49, 9, 13, 1, 'hair');
});
define('hair/hair_m_braided_back', v => {         // swept top, a warrior's plait down the back
  domeTiers(v); backMass(v, 36); sides(v);
  v.paint(-6, -5, 51, 53, -8, 11, 'hair_shade');
  v.cut(-13, -6, 45, 49, 9, 12, 1, 'hair'); v.cut(-6, 3, 45, 49, 9, 12, 1, 'hair_mid'); v.cut(3, 12, 46, 49, 9, 11, 1, 'hair');
  v.cut(-4, 4, 30, 37, -12, -7, 1, 'hair_mid');
  braid(v, -3, 3, -10, -6, 30, 20);
});

// ── Women's hair ─────────────────────────────────────────────────────────────
define('hair/hair_f_twin_braids', v => P.HAIR_STYLES.braids(v));   // the proposal's braids (Sigrun)
define('hair/hair_f_bun', v => {                 // pulled back into a big knot at the back of the head
  domeTiers(v); backMass(v, 36); sides(v);
  v.cut(-13, -2, 45, 49, 9, 12, 1, 'hair'); v.cut(-2, 13, 46, 49, 9, 12, 1, 'hair_mid');
  v.cut(-6, 6, 38, 50, -17, -10, 2, 'hair');           // the bun, six cells proud of the nape
  v.paint(-6, 6, 43, 45, -17, -10, 'hair_shade');       // wrapped band
  v.cut(-4, 4, 50, 52, -15, -11, 1, 'hair_mid');        // rounded top
  v.box(-1, 1, 46, 48, -18, -17, 'hair_shade');         // a pin through the knot
});
define('hair/hair_f_braid_side', v => {
  domeTiers(v); backMass(v, 36); sides(v);
  v.paint(3, 4, 50, 53, -8, 12, 'hair_shade');
  v.cut(-13, 3, 45, 49, 9, 12, 1, 'hair'); v.cut(3, 13, 46, 49, 9, 11, 1, 'hair_mid');
  v.box(11, 14, 36, 46, 4, 10, 'hair');
  v.cut(-16, -11, 37, 44, 1, 8, 1, 'hair_mid');
  braid(v, -16, -11, 2, 8, 37, 20);
});
define('hair/hair_f_braid_long', v => {
  domeTiers(v); backMass(v, 34); sides(v);
  v.paint(-1, 1, 50, 53, -8, 12, 'hair_shade');
  v.cut(-13, -1, 45, 49, 9, 12, 1, 'hair'); v.cut(1, 13, 45, 49, 9, 12, 1, 'hair_mid');
  v.cut(-4, 4, 30, 36, -12, -7, 1, 'hair_mid');
  braid(v, -3, 3, -10, -6, 30, 20);
});
define('hair/hair_f_short_practical', v => {      // a chin-length bob that curls forward
  domeTiers(v); backMass(v, 37);
  v.both(s => { s.box(-15, -12, 34, 49, -9, 4, 'hair_mid'); s.box(-14, -12, 34, 36, 4, 7, 'hair_shade'); });
  v.cut(-13, 13, 46, 49, 9, 12, 1, 'hair'); v.paint(-13, 13, 46, 47, 9, 12, 'hair_mid');
});
define('hair/hair_f_half_up', v => {
  domeTiers(v); sides(v);
  v.cut(-14, 14, 26, 49, -11, -4, 2, 'hair_shade'); v.cut(-13, 13, 26, 33, -12, -9, 1, 'hair');
  v.box(-3, 3, 50, 54, -10, -4, 'hair_mid'); v.paint(-3, 3, 51, 52, -10, -4, 'hair_shade'); v.box(-2, 2, 50, 54, -12, -10, 'hair');
  v.cut(-13, -4, 45, 49, 9, 12, 1, 'hair'); v.cut(-4, 13, 46, 49, 9, 12, 1, 'hair_mid');
});
define('hair/hair_f_loose_long', v => {
  domeTiers(v); backMass(v, 22);
  v.both(s => { s.box(-16, -12, 29, 49, -2, 6, 'hair'); s.box(-15, -12, 38, 49, -9, -2, 'hair_mid'); s.box(-16, -13, 29, 31, -2, 6, 'hair_mid'); });
  v.cut(-12, 12, 22, 27, -12, -9, 1, 'hair');
  v.paint(-1, 1, 50, 53, -8, 12, 'hair_shade');
  v.cut(-13, -1, 45, 49, 9, 12, 1, 'hair_mid'); v.cut(1, 13, 45, 49, 9, 12, 1, 'hair');
});
define('hair/hair_f_shaved_sides', v => {         // a crest from brow to nape over shorn sides
  v.cut(-5, 5, 49, 53, -10, 11, 2, 'hair'); v.cut(-4, 4, 53, 54, -8, 9, 2, 'hair_mid');
  v.both(s => s.box(-14, -13, 44, 49, -8, 6, 'hair_shade'));
  v.box(-13, 13, 40, 49, -10, -9, 'hair_shade');
  v.cut(-3, 3, 38, 48, -12, -10, 1, 'hair');
});
define('hair/hair_f_cropped', v => {
  v.cut(-14, 14, 47, 51, -10, 11, 4, 'hair'); v.cut(-11, 11, 51, 52, -7, 8, 3, 'hair_mid');
  v.both(s => s.box(-15, -12, 42, 49, -9, 3, 'hair_mid'));
  v.cut(-14, 14, 39, 49, -11, -4, 2, 'hair_shade');
  v.cut(-12, -7, 46, 49, 9, 12, 1, 'hair'); v.cut(-7, -1, 47, 49, 9, 12, 1, 'hair_mid');
  v.cut(-1, 6, 46, 49, 9, 12, 1, 'hair'); v.cut(6, 12, 47, 49, 9, 11, 1, 'hair_mid');
});
define('hair/hair_f_wild', v => {
  v.cut(-16, 16, 47, 51, -12, 12, 4, 'hair'); v.cut(-13, 13, 51, 53, -9, 9, 4, 'hair_mid');
  v.cut(-15, 15, 30, 49, -12, -4, 2, 'hair_shade');
  v.both(s => { s.box(-17, -12, 34, 49, -9, 5, 'hair_mid'); s.box(-19, -16, 42, 47, -6, 2, 'hair'); s.box(-18, -15, 36, 40, -8, -2, 'hair'); });
  v.box(-6, -1, 53, 54, -5, 2, 'hair'); v.box(3, 9, 52, 54, -8, -2, 'hair_mid');
  v.cut(-13, -7, 45, 49, 9, 13, 1, 'hair'); v.cut(-7, -2, 46, 49, 9, 12, 1, 'hair_mid'); v.cut(-2, 4, 45, 48, 9, 13, 1, 'hair');
  v.cut(4, 9, 46, 49, 9, 12, 1, 'hair_mid'); v.cut(9, 13, 45, 49, 9, 13, 1, 'hair');
});

// ── Beards ───────────────────────────────────────────────────────────────────
const sideburns = (v) => { v.box(-14, -11, 31, 43, 2, 9, 'hair_mid'); v.box(11, 14, 31, 43, 2, 9, 'hair_mid'); };
const moustache = (v, top = 35, depth = 13) => {
  v.cut(-9, -1, 31, top, 10, depth, 1, 'hair'); v.cut(1, 9, 31, top, 10, depth, 1, 'hair');
  v.paint(-9, 9, 31, 32, 10, depth, 'hair_shade');
};
define('beards/beard_full_long', v => {           // the proposal's stepped spade (Brann), down to the belt
  sideburns(v);
  v.cut(-12, 12, 27, 34, 3, 11, 2, 'hair_mid');
  v.cut(-10, 10, 23, 27, 4, 11, 2, 'hair_mid');
  v.cut(-7, 7, 19, 23, 5, 11, 2, 'hair_shade');
  v.cut(-4, 4, 15, 19, 6, 11, 1, 'hair_shade');
  v.paint(-12, 12, 23, 34, 10, 11, 'hair');           // lit front plane
  v.paint(-5, -4, 19, 31, 9, 11, 'hair_mid'); v.paint(4, 5, 19, 31, 9, 11, 'hair_mid');   // two grooves split it into locks
  moustache(v);
  v.box(-11, -8, 27, 31, 10, 12, 'hair'); v.box(8, 11, 27, 31, 10, 12, 'hair');
});
define('beards/beard_forked', v => {              // the proposal's fork (Thrain), prongs to the belt
  v.cut(-10, 10, 31, 35, 10, 13, 1, 'hair');
  v.box(-11, -8, 28, 31, 10, 12, 'hair'); v.box(8, 11, 28, 31, 10, 12, 'hair');
  v.cut(-12, 12, 24, 33, 3, 12, 2, 'hair_mid');
  v.cut(-10, -1, 17, 24, 4, 11, 1, 'hair_shade'); v.cut(1, 10, 17, 24, 4, 11, 1, 'hair_shade');
  v.cut(-8, -3, 12, 17, 6, 11, 1, 'hair'); v.cut(3, 8, 12, 17, 6, 11, 1, 'hair');
  sideburns(v);
});
define('beards/beard_full_braided', v => {        // a full beard with two plaits to the belt
  sideburns(v);
  v.cut(-12, 12, 26, 34, 3, 11, 2, 'hair_mid'); v.paint(-12, 12, 26, 34, 10, 11, 'hair');
  v.cut(-9, 9, 23, 26, 4, 11, 2, 'hair_shade');
  moustache(v);
  v.box(-11, -8, 27, 31, 10, 12, 'hair'); v.box(8, 11, 27, 31, 10, 12, 'hair');
  braid(v, -7, -2, 7, 11, 25, 12); braid(v, 2, 7, 7, 11, 25, 12);
});
define('beards/beard_short_trimmed', v => {
  sideburns(v);
  v.cut(-12, 12, 28, 34, 3, 11, 2, 'hair_mid'); v.cut(-9, 9, 25, 28, 4, 10, 2, 'hair_shade');
  v.paint(-12, 12, 28, 34, 10, 11, 'hair');
  moustache(v, 35, 12);
});
define('beards/beard_mutton_chops', v => {
  v.both(s => { s.box(-14, -10, 31, 43, 2, 10, 'hair_mid'); s.cut(-13, -9, 28, 31, 3, 10, 1, 'hair_shade'); s.paint(-14, -10, 31, 43, 9, 10, 'hair'); });
  moustache(v, 34, 12);
  v.both(s => s.box(-10, -8, 31, 34, 9, 11, 'hair_mid'));
});
define('beards/beard_goatee', v => {
  moustache(v, 34, 12);
  v.box(-10, -7, 28, 32, 10, 12, 'hair_mid'); v.box(7, 10, 28, 32, 10, 12, 'hair_mid');
  v.cut(-4, 4, 23, 31, 6, 11, 1, 'hair_mid'); v.cut(-2, 2, 20, 23, 7, 10, 1, 'hair_shade');
});
define('beards/beard_braided_long', v => {
  moustache(v);
  sideburns(v);
  v.cut(-10, 10, 26, 33, 3, 11, 2, 'hair_mid'); v.paint(-10, 10, 26, 33, 10, 11, 'hair');
  braid(v, -3, 3, 7, 11, 28, 12);                    // one long plait to the belt
});

// ── Brows: on the face, y 40..44 ─────────────────────────────────────────────
const brow = (name, fn) => define('eyebrows/' + name, v => v.both(fn));
brow('brows_m_arched', b => P.BROWS.arched(b));
brow('brows_f_thin_arched', b => P.BROWS.fine(b));
brow('brows_m_bushy', b => P.BROWS.bushy(b));
brow('brows_f_bushy', b => { b.box(-10, -5, 42, 45, 10, 12, 'hair'); b.box(-11, -9, 41, 43, 10, 12, 'hair_mid'); });
brow('brows_m_thick_flat', b => { b.box(-11, -4, 42, 44, 10, 12, 'hair'); b.paint(-11, -4, 43, 44, 10, 12, 'hair_mid'); });
brow('brows_f_thick_flat', b => { b.box(-10, -5, 42, 44, 10, 12, 'hair'); b.paint(-10, -5, 43, 44, 10, 12, 'hair_mid'); });
brow('brows_f_sharp_angled', b => { b.box(-11, -9, 43, 45, 10, 12, 'hair'); b.box(-9, -7, 42, 44, 10, 12, 'hair'); b.box(-7, -5, 42, 43, 10, 12, 'hair_mid'); });
define('eyebrows/brows_m_unibrow', v => {
  v.box(-11, 11, 42, 44, 10, 12, 'hair'); v.paint(-11, 11, 43, 44, 10, 12, 'hair_mid'); v.box(-2, 2, 43, 44, 10, 12, null);
});

// ── Work tools: square iron heads on a square haft ──────────────────────────
// The hand grips the haft at (0, 0, 0); the support hand sits 10 cells up the haft;
// the axe strikes at (0, 17, 11) and the pickaxe at (0, 22, 15) (felling/mining poses).
define('tools/felling_axe', v => {
  v.box(-1, 1, -4, 20, -1, 1, 'wood'); v.paint(0, 1, -4, 20, -1, 1, 'grain');   // haft, a lit grain face
  v.box(-1, 1, -3, 2, -1, 1, 'tool_leather'); v.box(-1, 1, 8, 10, -1, 1, 'tool_leather');   // grip wraps
  v.cut(-2, 2, 13, 21, -3, 3, 1, 'iron_dark');                // square socket collar
  v.box(-2, 2, 12, 22, 3, 6, 'iron');                          // the heavy cheek
  v.box(-1, 1, 11, 23, 6, 10, 'iron');                         // a flared bit
  v.box(-1, 1, 11, 23, 10, 11, 'steel');                       // bright edge
  v.paint(-2, 2, 21, 22, 3, 6, 'steel');                       // lit top of the cheek
});
define('tools/mining_pickaxe', v => {
  v.box(-1, 1, -4, 26, -1, 1, 'wood'); v.paint(0, 1, -4, 26, -1, 1, 'grain');
  v.box(-1, 1, -3, 2, -1, 1, 'tool_leather'); v.box(-1, 1, 8, 10, -1, 1, 'tool_leather');
  v.cut(-2, 2, 24, 30, -3, 3, 1, 'iron_dark');                // square socket block
  v.box(-2, 2, 25, 29, -10, -3, 'iron'); v.box(-2, 2, 25, 29, 3, 10, 'iron');   // two square arms
  v.box(-1, 1, 23, 27, -13, -10, 'iron'); v.box(-1, 1, 23, 27, 10, 13, 'iron');  // stepping down to
  v.box(-1, 1, 22, 24, -15, -13, 'steel'); v.box(-1, 1, 22, 24, 13, 15, 'steel'); // the points
  v.paint(-2, 2, 28, 29, -10, 10, 'steel');                    // lit top edge
});

// ── Crafting tools (doc 293): stone heads lashed to wooden hafts, no iron ─────
// Held in the Worker's crafting swing in place of the axe, so each strikes where the axe's
// edge does, at (0, 17, 11). Rope binds them: there is no leather yet.
// The Carpenter's stone adze: a wide stone blade lashed across the haft's top, its edge level.
define('tools/stone_adze', v => {
  v.box(-1, 1, -4, 20, -1, 1, 'wood'); v.paint(0, 1, -4, 20, -1, 1, 'grain');
  v.box(-1, 1, -3, 1, -1, 1, 'rope'); v.box(-1, 1, 8, 10, -1, 1, 'rope');          // grip bindings
  v.box(-3, 3, 16, 20, 1, 9, 'tool_stone'); v.box(-3, 3, 16, 18, 9, 11, 'tool_stone');
  v.paint(-3, 3, 19, 20, 1, 9, 'tool_stone_light'); v.paint(-3, 3, 16, 18, 10, 11, 'tool_stone_light');   // the edge
  v.paint(-3, 3, 16, 17, 1, 9, 'tool_stone_dark');
  v.box(-2, 2, 15, 21, -2, 2, 'rope'); v.paint(-2, 2, 17, 18, -2, 2, 'rope_dark');  // the lashing
});
// The Stonemason's maul: a squat hammerstone lashed to a short haft, its face forward.
define('tools/stone_maul', v => {
  v.box(-1, 1, -4, 18, -1, 1, 'wood'); v.paint(0, 1, -4, 18, -1, 1, 'grain');
  v.box(-1, 1, -3, 1, -1, 1, 'rope'); v.box(-1, 1, 8, 10, -1, 1, 'rope');
  v.cut(-4, 4, 13, 21, 2, 11, 2, 'tool_stone');
  v.paint(-4, 4, 20, 21, 2, 11, 'tool_stone_light'); v.paint(-4, 4, 13, 14, 2, 11, 'tool_stone_dark');
  v.paint(-3, 3, 14, 20, 10, 11, 'tool_stone_light');                                // the worn face
  v.box(-2, 2, 14, 20, -2, 3, 'rope'); v.paint(-2, 2, 16, 17, -2, 3, 'rope_dark');  // the lashing
});

// ── Fishing (doc 289): a peeled sapling rod, Tier 1 with no iron ─────────────
// Gripped at (0, 0, 0) and running straight up +Y, 42 cells, the line wound on a peg by the
// hand and knotted at the tip. The float rides the water with its water line at y 3; the
// caught perch (the chunky look) hangs by its mouth at (0, 0, 0), its body along +X.
define('tools/fishing_rod', v => {
  v.box(-1, 1, -6, 2, -1, 1, 'rod_bark');                       // the bark butt
  for (const y of [-5, -2, 1]) v.paint(-1, 1, y, y + 1, -1, 1, 'rod_bark_light');
  v.box(-1, 1, 2, 18, -1, 1, 'rod_wood');                       // the thick, peeled lower rod
  v.paint(-1, 1, 9, 10, -1, 1, 'rod_knot');                     // a node
  v.box(0, 1, 18, 41, -1, 0, 'rod_wood');                       // the slim upper rod
  v.paint(0, 1, 25, 26, -1, 0, 'rod_knot'); v.paint(0, 1, 33, 34, -1, 0, 'rod_knot');
  for (const y of [3, 12]) v.box(-2, 2, y, y + 1, -2, 2, 'rope');   // rope lashings
  v.box(-1, 2, 21, 22, -2, 1, 'rope');
  v.box(1, 3, 4, 8, -1, 1, 'rod_line');                         // the line wound on a peg
  v.box(1, 2, 3, 9, -1, 1, 'rod_wood');
  v.box(0, 1, 41, 42, -1, 0, 'rope');                           // the knot at the tip
});
define('tools/fishing_float', v => {
  v.box(0, 1, 0, 2, 0, 1, 'float_wood');                        // the keel
  v.cut(-1, 2, 2, 5, -1, 2, 1, 'float_wood');                   // the carved body
  v.paint(-1, 2, 4, 5, -1, 2, 'float_red');
  v.box(0, 1, 5, 8, 0, 1, 'float_red');                         // the dyed tip
  v.paint(0, 1, 7, 8, 0, 1, 'float_dark');
});
const PERCH = {side: 'perch_side', back: 'perch_back', belly: 'perch_belly', bar: 'perch_bar', tail: 'perch_dorsal', fin: 'perch_fin', eye: 'fish_eye'};
function perchBody(v, c) {
  for (const [x0, x1, y0, y1, h, n] of [[0, 2, 3, 6, 1, 0], [2, 4, 2, 7, 2, 1], [4, 8, 1, 8, 2, 1], [8, 10, 2, 7, 2, 1], [10, 11, 3, 6, 1, 0]]) {
    v.cutX(x0, x1, y0, y1, -h, h, n, c.side);                  // the deep body, round along X
  }
  v.paint(0, 12, 6, 9, -3, 3, c.back); v.paint(0, 12, 0, 3, -3, 3, c.belly);
  for (const x of [5, 8]) v.paint(x, x + 1, 4, 9, -3, 3, c.bar);
  v.box(11, 12, 2, 7, -1, 1, c.tail); v.box(12, 13, 1, 8, -1, 1, c.tail);   // the fan tail
  v.box(5, 7, 8, 10, -1, 1, c.tail); v.box(7, 8, 8, 9, -1, 1, c.tail);      // the dorsal
  v.box(5, 6, 0, 1, -1, 1, c.fin); v.box(8, 9, 0, 2, -1, 1, c.fin);         // the orange fins
  v.paint(2, 3, 5, 6, 1, 2, c.eye); v.paint(2, 3, 5, 6, -2, -1, c.eye);     // an eye on each flank
}
define('tools/caught_perch', v => perchBody(v, PERCH));
// The other catches (doc 289, step 2) share the perch's chunky body and hang the same way; their
// colours and marks set them apart. `spots` are [x, y, role] cells painted on both flanks.
function caught(v, c, spots) {
  for (const [x0, x1, y0, y1, h, n] of [[0, 2, 3, 6, 1, 0], [2, 4, 2, 7, 2, 1], [4, 8, 1, 8, 2, 1], [8, 10, 2, 7, 2, 1], [10, 11, 3, 6, 1, 0]]) {
    v.cutX(x0, x1, y0, y1, -h, h, n, c.side);
  }
  v.paint(0, 12, 6, 9, -3, 3, c.back); v.paint(0, 12, 0, 3, -3, 3, c.belly);
  for (const [x, y, role] of spots) { v.paint(x, x + 1, y, y + 1, 1, 2, role); v.paint(x, x + 1, y, y + 1, -2, -1, role); }
  v.box(11, 12, 2, 7, -1, 1, c.tail); v.box(12, 13, 1, 8, -1, 1, c.tail);   // the fan tail
  v.box(5, 7, 8, 10, -1, 1, c.dorsal); v.box(7, 8, 8, 9, -1, 1, c.dorsal);  // the dorsal
  v.box(5, 6, 0, 1, -1, 1, c.fin); v.box(8, 9, 0, 2, -1, 1, c.fin);         // the lower fins
  if (c.eye) { v.paint(2, 3, 5, 6, 1, 2, c.eye); v.paint(2, 3, 5, 6, -2, -1, c.eye); }
}
// Grilling (doc 290) browns every species alike: ROAST stands in for a catch's colours, and its
// marks darken to grill_bar. A roasted cave fish keeps no eye, as it has none.
const ROAST = {side: 'grill_side', back: 'grill_back', belly: 'grill_belly', bar: 'grill_bar', tail: 'grill_fin', dorsal: 'grill_fin', fin: 'grill_fin', eye: 'grill_eye'};
const marks = (spots, roast) => spots.map(([x, y, role]) => [x, y, roast ? 'grill_bar' : role]);
// The river's trout: olive-brown, dark spots above and red ones along the side, a silver belly.
function trout(v, roast) {
  caught(v, roast ? ROAST : {side: 'trout_side', back: 'trout_back', belly: 'trout_belly', tail: 'trout_fin', dorsal: 'trout_fin', fin: 'trout_fin_light', eye: 'fish_eye'},
    marks([[4, 7, 'trout_spot'], [6, 6, 'trout_spot'], [8, 7, 'trout_spot'], [9, 6, 'trout_spot'], [5, 4, 'trout_red'], [7, 4, 'trout_red'], [9, 4, 'trout_red']], roast));
  v.box(10, 11, 7, 8, -1, 1, roast ? 'grill_fin' : 'trout_fin');              // the adipose fin
}
define('tools/caught_trout', v => trout(v, false));
// The tarn's char: a dark green back with pale spots, an orange belly, white-edged fins.
function char(v, roast) {
  caught(v, roast ? ROAST : {side: 'char_side', back: 'char_back', belly: 'char_belly', tail: 'char_dorsal', dorsal: 'char_dorsal', fin: 'char_fin', eye: 'fish_eye'},
    marks([[4, 6, 'char_spot'], [6, 5, 'char_spot'], [8, 6, 'char_spot'], [5, 4, 'char_spot'], [7, 3, 'char_spot'], [9, 4, 'char_spot']], roast));
  if (!roast) { v.paint(5, 6, 0, 1, -1, 1, 'char_edge'); v.paint(8, 9, 0, 1, -1, 1, 'char_edge'); }   // the fins' white edges
}
define('tools/caught_char', v => char(v, false));
// The spring cave's fish: pinkish white, no eyes, a pink gill and a paler line down each side.
function caveFish(v, roast) {
  caught(v, roast ? {...ROAST, eye: null} : {side: 'cavefish_body', back: 'cavefish_shade', belly: 'cavefish_belly', tail: 'cavefish_fin', dorsal: 'cavefish_fin', fin: 'cavefish_fin', eye: 'cavefish_socket'},
    marks([[3, 3, 'cavefish_gill'], [3, 4, 'cavefish_gill'], [3, 5, 'cavefish_gill'], [3, 6, 'cavefish_gill'],
     [5, 5, 'cavefish_line'], [6, 5, 'cavefish_line'], [7, 5, 'cavefish_line'], [8, 5, 'cavefish_line'], [9, 5, 'cavefish_line']], roast));
}
define('tools/caught_cave_fish', v => caveFish(v, false));
// The big catch (doc 292, concept B): a Ranger's big fish on the line, its own heavier model a
// size up from the caught fish (19 cells long against 13), with a bigger eye and a heavier jaw.
// It hangs by its mouth at (0, 0, 0) along +X as they do. `marks` are [x, y0, y1, role] stripes
// and spots painted through both flanks.
function bigFish(v, c) {
  for (const [x0, x1, y0, y1, h, n] of [[0, 3, 4, 9, 2, 0], [3, 6, 2, 11, 3, 1], [6, 12, 1, 13, 3, 1], [12, 15, 2, 11, 3, 1], [15, 16, 4, 9, 2, 0]]) {
    v.cutX(x0, x1, y0, y1, -h, h, n, c.side);                  // the deep body, round along X
  }
  v.paint(0, 19, 9, 13, -4, 4, c.back); v.paint(0, 19, 0, 4, -4, 4, c.belly);
  for (const [x, y0, y1, role] of c.marks) v.paint(x, x + 1, y0, y1, -4, 4, role);
  v.box(16, 17, 3, 10, -1, 1, c.tail); v.box(17, 19, 1, 12, -1, 1, c.tail);       // the fan tail
  v.box(6, 10, 12, 15, -1, 1, c.dorsal); v.box(10, 12, 12, 14, -1, 1, c.dorsal);  // the dorsal
  if (c.adipose) v.box(14, 15, 11, 13, -1, 1, c.dorsal);                          // the trout's adipose fin
  v.box(7, 9, 0, 1, -1, 1, c.fin); v.box(12, 13, 0, 2, -1, 1, c.fin);             // the lower fins
  if (c.edge) { v.paint(7, 9, 0, 1, -1, 1, c.edge); v.paint(12, 13, 0, 1, -1, 1, c.edge); }
  v.paint(1, 3, 6, 8, 1, 2, c.eye); v.paint(1, 3, 6, 8, -2, -1, c.eye);           // a bigger eye
  v.box(0, 1, 3, 5, -1, 1, c.belly);                                                // the heavy jaw
}
const spot = (cells, role) => cells.map(([x, y]) => [x, y, y + 1, role]);
define('tools/big_perch', v => bigFish(v, {...PERCH, dorsal: PERCH.tail,
  marks: [[6, 5, 13, 'perch_bar'], [9, 5, 13, 'perch_bar'], [12, 5, 13, 'perch_bar']]}));
define('tools/big_trout', v => bigFish(v, {side: 'trout_side', back: 'trout_back', belly: 'trout_belly', tail: 'trout_fin', dorsal: 'trout_fin',
  fin: 'trout_fin_light', eye: 'fish_eye', adipose: true,
  marks: [...spot([[5, 10], [8, 11], [11, 10], [13, 9], [7, 9]], 'trout_spot'), ...spot([[6, 6], [9, 5], [12, 6], [10, 7]], 'trout_red')]}));
define('tools/big_char', v => bigFish(v, {side: 'char_side', back: 'char_back', belly: 'char_belly', tail: 'char_dorsal', dorsal: 'char_dorsal',
  fin: 'char_fin', eye: 'fish_eye', edge: 'char_edge',
  marks: spot([[6, 9], [9, 8], [12, 9], [7, 6], [10, 5], [13, 6], [15, 8]], 'char_spot')}));
define('tools/big_cave_fish', v => bigFish(v, {side: 'cavefish_body', back: 'cavefish_shade', belly: 'cavefish_belly', tail: 'cavefish_fin',
  dorsal: 'cavefish_fin', fin: 'cavefish_fin', eye: 'cavefish_socket',
  marks: [[4, 4, 10, 'cavefish_gill'], ...[6, 7, 8, 9, 10, 11, 12, 13, 14].map(x => [x, 7, 8, 'cavefish_line'])]}));

// ── Grilling (doc 290): a fresh fish pushed onto a peeled green stick from the mouth, held out
// over the campfire, then eaten off the stick (concept A, tmp/grill_concepts_20261031). Gripped at
// (0, 0, 0) like the rod, the stick runs up +Y: a bark butt in the hand, peeled above, slim from
// y 10 to its tip at y 29. The fish lies along it, snout up at y 26 and tail down at y 14, its
// height across X and its flanks facing ±Z, so the stick runs through it from mouth to tail.
// Grilled, the fish browns (ROAST), scorched along the belly where the flames reach and glossy
// along the shoulder, and the stick's tip blackens.
function grillStick(v, grilled) {
  v.box(-1, 1, -3, 3, -1, 1, 'stick_bark');                     // the bark butt
  v.paint(-1, 1, -1, 0, -1, 1, 'stick_bark_light'); v.paint(-1, 1, 1, 2, -1, 1, 'stick_bark_light');
  v.box(-1, 1, 3, 10, -1, 1, 'stick_wood');                     // peeled
  v.paint(-1, 1, 6, 7, -1, 1, 'stick_knot');
  v.box(0, 1, 10, 29, -1, 0, 'stick_wood');                     // the slim upper stick
  if (grilled) v.box(0, 1, 27, 29, -1, 0, 'stick_char');        // blackened where the flames reach
}
// A caught fish's ops, in its own cells (x from the snout, y up), laid on the stick's cells.
function onStick(v) {
  const across = (y0, y1) => [y0 - 5, y1 - 5];
  const along = (x0, x1) => [27 - x1, 27 - x0];
  return {
    box: (x0, x1, y0, y1, z0, z1, c) => v.box(...across(y0, y1), ...along(x0, x1), z0, z1, c),
    paint: (x0, x1, y0, y1, z0, z1, c) => v.paint(...across(y0, y1), ...along(x0, x1), z0, z1, c),
    cutX: (x0, x1, y0, y1, z0, z1, n, c) => v.cut(...across(y0, y1), ...along(x0, x1), z0, z1, n, c),
  };
}
const CATCHES = {perch: (v, roast) => perchBody(v, roast ? ROAST : PERCH), trout, char, cave_fish: caveFish};
const SCORCH = [[3, 3], [4, 2], [6, 1], [7, 2], [9, 2], [10, 4], [2, 6], [6, 6], [9, 6]];
for (const [fish, body] of Object.entries(CATCHES)) {
  for (const grilled of [false, true]) {
    define(`tools/grill_stick_${fish}${grilled ? '_grilled' : ''}`, v => {
      grillStick(v, grilled);
      const s = onStick(v);
      body(s, grilled);
      if (!grilled) return;
      s.paint(4, 8, 5, 6, -3, 3, 'grill_side_light');          // the gloss along the shoulder
      for (const [x, y] of SCORCH) s.paint(x, x + 1, y, y + 1, -3, 3, 'grill_char');
    });
  }
}

// ── Portrait-only scars, drawn on the face; dwarves.py lifts them clear ──────
define('scars/scar_cheek_slash', v => { v.box(7, 8, 32, 35, 9, 10, 'scar'); v.box(8, 9, 31, 33, 9, 10, 'scar'); });
define('scars/scar_brow_notch', v => v.box(-8, -7, 45, 48, 9, 10, 'scar'));
define('scars/scar_nose_bridge', v => v.box(-2, 2, 37, 38, 11, 12, 'scar'));
define('scars/scar_chin_split', v => v.box(0, 1, 30, 33, 8, 9, 'scar'));


export function build(name) { const v = new Vox(); parts[name](v); return v; }
export const NAMES = Object.keys(parts);

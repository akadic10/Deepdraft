// Hearthblock proposal models, verbatim from the approved proposal page
// ("Deepdraft Hearthblock Style", 2026-10-20), with helpers exported for tier1.mjs.

// Hearthblock proposal models for Deepdraft.
// Every model is authored on the native 1:16 grid (one cell = 1/16 world block)
// with the same primitives as data/art/voxel_*.json: box and cutbox use
// [x0,x1) x [y0,y1) x [z0,z1) in cells, cutbox clips vertical edges by `n`
// cells (the same diamond rule as micro_voxel_study/generate.py). cutX/cutZ
// clip edges along X/Z, pillow steps the top layer in by one cell, paint
// recolours existing cells, and a null colour carves air.
// Axes: X right, Y up, Z toward the dwarf's front. Ground is Y0.

export class Vox {
  // `log` records every authoring operation so a model can be saved as
  // readable layout data (see layoutOps below); `cells` is the result.
  constructor() { this.cells = new Map(); this.log = []; }
  static key(x, y, z) { return ((x + 512) * 1024 + (y + 512)) * 1024 + (z + 512); }
  static unkey(k) {
    const z = (k % 1024) - 512; k = Math.floor(k / 1024);
    const y = (k % 1024) - 512; const x = Math.floor(k / 1024) - 512;
    return [x, y, z];
  }
  set(x, y, z, c) { const k = Vox.key(x, y, z); if (c == null) this.cells.delete(k); else this.cells.set(k, c); }
  has(x, y, z) { return this.cells.has(Vox.key(x, y, z)); }
  box(x0, x1, y0, y1, z0, z1, c) {
    this.log.push(c == null ? ['air', [x0, x1, y0, y1, z0, z1]] : ['box', [x0, x1, y0, y1, z0, z1], c]);
    for (let x = x0; x < x1; x++) for (let y = y0; y < y1; y++) for (let z = z0; z < z1; z++) this.set(x, y, z, c);
    return this;
  }
  cut(x0, x1, y0, y1, z0, z1, n, c) {
    this.log.push(['cutbox', [x0, x1, y0, y1, z0, z1, n], c]);
    for (let x = x0; x < x1; x++) for (let z = z0; z < z1; z++) {
      if (Math.min(x - x0, x1 - 1 - x) + Math.min(z - z0, z1 - 1 - z) < n) continue;
      for (let y = y0; y < y1; y++) this.set(x, y, z, c);
    }
    return this;
  }
  cutX(x0, x1, y0, y1, z0, z1, n, c) {
    this.log.push(['cutbox_x', [x0, x1, y0, y1, z0, z1, n], c]);
    for (let y = y0; y < y1; y++) for (let z = z0; z < z1; z++) {
      if (Math.min(y - y0, y1 - 1 - y) + Math.min(z - z0, z1 - 1 - z) < n) continue;
      for (let x = x0; x < x1; x++) this.set(x, y, z, c);
    }
    return this;
  }
  cutZ(x0, x1, y0, y1, z0, z1, n, c) {
    this.log.push(['cutbox_z', [x0, x1, y0, y1, z0, z1, n], c]);
    for (let x = x0; x < x1; x++) for (let y = y0; y < y1; y++) {
      if (Math.min(x - x0, x1 - 1 - x) + Math.min(y - y0, y1 - 1 - y) < n) continue;
      for (let z = z0; z < z1; z++) this.set(x, y, z, c);
    }
    return this;
  }
  pillow(x0, x1, y0, y1, z0, z1, n, c, top = c) {
    this.cut(x0, x1, y0, y1 - 1, z0, z1, n, c);
    this.cut(x0 + 1, x1 - 1, y1 - 1, y1, z0 + 1, z1 - 1, n, top);
    return this;
  }
  paint(x0, x1, y0, y1, z0, z1, c) {
    this.log.push(['paint', [x0, x1, y0, y1, z0, z1], c]);
    for (let x = x0; x < x1; x++) for (let y = y0; y < y1; y++) for (let z = z0; z < z1; z++) {
      const k = Vox.key(x, y, z); if (this.cells.has(k)) this.cells.set(k, c);
    }
    return this;
  }
  ring(x0, x1, y, z0, z1, c) {
    this.log.push(['ring', [x0, x1, y, z0, z1], c]);
    for (let x = x0; x < x1; x++) { this.set(x, y, z0, c); this.set(x, y, z1 - 1, c); }
    for (let z = z0; z < z1; z++) { this.set(x0, y, z, c); this.set(x1 - 1, y, z, c); }
    return this;
  }
  mirrorX() {
    const v = new Vox();
    for (const [k, c] of this.cells) { const [x, y, z] = Vox.unkey(k); v.set(-x - 1, y, z, c); }
    return v;
  }
  merge(o) { for (const [k, c] of o.cells) this.cells.set(k, c); return this; }
  // Build one side in a fresh model, then add it and its mirror across X = 0.
  both(fn) { const s = new Vox(); fn(s); this.log.push(['mirror_x', s.log]); return this.merge(s).merge(s.mirrorX()); }
  get count() { return this.cells.size; }
}

// sRGB authoring colours. Tinted roles are authored near white and
// multiplied by the dwarf's skin or hair tint, as DwarfAgent does today.
export const PALETTE = {
  // Hewn oak: three values for each surface, plus marks
  wood_top: '#DCA35C', wood_top_alt: '#CB8E4D', wood_side: '#A96F3B', wood_dark: '#6C4326',
  grain: '#BE8344', pith: '#8D5731',
  // Tier 1 riven (split, unplaned) faces and axe bites
  riven: '#C08A4E', riven_dark: '#9A6A38', chop: '#7A512E',
  bark: '#5C3B26', bark_light: '#7B5336', bark_dark: '#3E2819',
  // Stone props, metal, fibre
  stone_light: '#A9A49C', stone: '#8F8A83', stone_dark: '#6C6863', ash: '#3F3B38',
  iron: '#6E6F72', iron_dark: '#47494C', brass: '#E3B04B', brass_dark: '#A9782A',
  rope: '#CFAB69', rope_dark: '#9F7E45', char: '#2C2320',
  // Soft goods
  hay: '#E3C56B', hay_mid: '#C99A3E', hay_light: '#E2BE5E', hay_dark: '#9A7631', straw: '#EED47C', leaf_dry: '#A0662C',
  linen: '#F0E6CC', linen_dark: '#D0C2A1',
  blanket: '#3D7E77', blanket_light: '#5C9C92', blanket_stripe: '#EAD7AE',
  apple: '#C9412F', apple_dark: '#94291F', leaf: '#5F8B35',
  // Clothing (baked into body/feet, as today)
  tunic: '#3F7C76', tunic_dark: '#2D5D59', tunic_light: '#5C9B91',
  moss: '#6F8C3E', moss_dark: '#536A2E', moss_light: '#8CA851',
  rust: '#A9563B', rust_dark: '#84412C', rust_light: '#C47050',
  trousers: '#4B4542', belt: '#6A4227', belt_dark: '#4B2D1A',
  boot: '#7A4C2C', boot_light: '#9C6A40', boot_dark: '#4E301D', sole: '#2E2521',
  // Tinted roles
  skin: '#F6EAE2', skin_shade: '#DCC6BA', nose: '#EFC9BC', blush: '#F7B3A3', mouth: '#A8655D',
  hair: '#FFFFFF', hair_mid: '#E7DCD2', hair_shade: '#C6B5A7',
  // Eyes stay untinted: dark bead plus one glint cell
  eye: '#2A1F1B', glint: '#FFFFFF',
  // Emissive
  flame_out: '#F27A2B', flame_mid: '#FFB443', flame_core: '#FFEBA8', ember: '#D24B1E',
};

export const TINTED = { skin: 'skin', skin_shade: 'skin', nose: 'skin', blush: 'skin', mouth: 'skin',
  hair: 'hair', hair_mid: 'hair', hair_shade: 'hair' };
export const EMISSIVE = new Set(['flame_out', 'flame_mid', 'flame_core', 'ember']);

// Proposed runtime tints (sRGB). Skin tones are today's DwarfAssets values;
// hair tints are slightly warmer and less saturated than today's.
export const SKIN = { pale: '#F5D6C4', medium: '#D9A680', tan: '#B58059', dark: '#6B472E' };
export const HAIR = { ginger: '#CC6A36', auburn: '#8E3B22', chestnut: '#6B3C23', black: '#2B2524',
  blond: '#D7B35F', grey: '#A39B93', white: '#E9E3D9' };

// ── Dwarf parts ──────────────────────────────────────────────────────────────
export function boots(v) {
  v.both(b => {
    b.cut(2, 11, 0, 2, -5, 10, 1, 'sole');
    b.cut(2, 11, 2, 9, -5, 3, 1, 'boot');        // shaft
    b.cut(2, 11, 2, 6, 3, 10, 1, 'boot');        // round-square toe
    b.paint(2, 11, 5, 6, 3, 10, 'boot_light');   // toe cap reads from above
    b.cut(1, 12, 9, 11, -6, 4, 1, 'boot_dark');  // folded cuff
  });
}

export function body(v, cloth) {
  const [t, td, tl] = cloth;
  v.box(-8, 8, 10, 13, -4, 3, 'trousers');
  v.cut(-11, 11, 11, 15, -7, 8, 2, td);          // flared hem: bottom heavy
  v.cut(-11, 11, 15, 18, -7, 8, 2, 'belt');
  v.box(-3, 3, 14, 19, 7, 9, 'brass');           // buckle, proud by one cell
  v.box(-1, 1, 15, 18, 8, 9, 'belt_dark');
  v.cut(-10, 10, 18, 28, -6, 7, 2, t);           // torso
  v.paint(-2, 2, 19, 27, 6, 7, tl);              // placket
  v.cut(-14, -9, 20, 28, -4, 4, 1, t);           // sleeves
  v.cut(9, 14, 20, 28, -4, 4, 1, t);
  v.cut(-8, 8, 27, 30, -5, 6, 2, 'linen');       // collar
}

export function hands(v, cuff) {
  v.both(h => {
    h.cut(11, 17, 18, 20, -3, 3, 1, cuff);       // cuff
    h.cut(11, 17, 12, 18, -3, 3, 1, 'skin');     // 6-cell mitten
    h.paint(11, 17, 12, 14, -3, 3, 'skin_shade');
    h.box(12, 15, 14, 16, 3, 5, 'skin');         // thumb
  });
}

export function head(v, { dome = false, wrinkles = false } = {}) {
  v.cut(-10, 10, 29, 34, -6, 9, 2, 'skin');      // jaw
  v.cut(-13, 13, 33, 50, -9, 10, 3, 'skin');     // the square head: 26 x 17 x 19
  if (dome) v.cut(-12, 12, 50, 52, -8, 9, 4, 'skin');
  v.box(-15, -13, 37, 43, -2, 2, 'skin_shade');  // ears
  v.box(13, 15, 37, 43, -2, 2, 'skin_shade');
  v.box(-2, 2, 35, 39, 10, 12, 'nose');         // potato nose, proud by two
  v.box(-3, 3, 35, 37, 10, 11, 'nose');          // wider at the base
  v.box(-10, -6, 35, 37, 10, 11, 'blush');       // rosy cheeks
  v.box(6, 10, 35, 37, 10, 11, 'blush');
  if (wrinkles) { v.paint(-6, 6, 46, 47, 9, 10, 'skin_shade'); v.paint(-4, 4, 48, 49, 9, 10, 'skin_shade'); }
}

export function eyes(v) {
  v.box(-9, -6, 37, 41, 10, 11, 'eye'); v.box(-9, -8, 40, 41, 10, 11, 'glint');
  v.box(6, 9, 37, 41, 10, 11, 'eye');   v.box(6, 7, 40, 41, 10, 11, 'glint');
}

export function smile(v) {
  v.paint(-2, 2, 31, 32, 8, 9, 'mouth');
  v.paint(-3, -2, 32, 33, 8, 9, 'mouth');
  v.paint(2, 3, 32, 33, 8, 9, 'mouth');
}

export const BROWS = {
  arched(b) { b.box(-10, -5, 42, 44, 10, 12, 'hair_mid'); b.box(-9, -6, 44, 45, 10, 12, 'hair_mid'); },
  fine(b) { b.box(-10, -5, 42, 43, 10, 12, 'hair_mid'); b.box(-9, -6, 43, 44, 10, 12, 'hair_mid'); },
  bushy(b) { b.box(-11, -4, 42, 45, 10, 13, 'hair'); b.box(-12, -10, 40, 43, 10, 12, 'hair'); },
};

export const BEARDS = {
  block(v) {                                        // a stepped spade, narrowing in three steps
    v.box(-14, -11, 31, 44, 2, 9, 'hair_mid'); v.box(11, 14, 31, 44, 2, 9, 'hair_mid'); // sideburns
    v.cut(-12, 12, 27, 34, 3, 11, 2, 'hair_mid');
    v.cut(-10, 10, 23, 27, 4, 11, 2, 'hair_mid');
    v.cut(-7, 7, 19, 23, 5, 10, 2, 'hair_shade');
    v.cut(-4, 4, 16, 19, 5, 9, 1, 'hair_shade');
    v.paint(-12, 12, 23, 34, 10, 11, 'hair');         // lit front plane
    v.paint(-5, -4, 21, 31, 9, 11, 'hair_mid');       // two grooves split it into locks
    v.paint(4, 5, 21, 31, 9, 11, 'hair_mid');
    v.cut(-9, -1, 31, 35, 10, 13, 1, 'hair');         // parted moustache
    v.cut(1, 9, 31, 35, 10, 13, 1, 'hair');
    v.paint(-9, 9, 31, 32, 10, 13, 'hair_shade');     // shaded underside
    v.box(-11, -8, 27, 31, 10, 12, 'hair'); v.box(8, 11, 27, 31, 10, 12, 'hair'); // drooping ends
  },
  forked(v) {
    v.cut(-10, 10, 31, 35, 10, 13, 1, 'hair');
    v.box(-11, -8, 28, 31, 10, 12, 'hair'); v.box(8, 11, 28, 31, 10, 12, 'hair');
    v.cut(-12, 12, 24, 33, 3, 12, 2, 'hair_mid');
    v.cut(-10, -1, 17, 24, 4, 11, 1, 'hair_shade'); v.cut(1, 10, 17, 24, 4, 11, 1, 'hair_shade');
    v.cut(-8, -3, 13, 17, 5, 10, 1, 'hair'); v.cut(3, 8, 13, 17, 5, 10, 1, 'hair');
    v.box(-14, -11, 31, 44, 2, 9, 'hair_mid'); v.box(11, 14, 31, 44, 2, 9, 'hair_mid');
  },
};

export const HAIR_STYLES = {
  swept(v) {
    v.cut(-14, 14, 34, 49, -11, -4, 2, 'hair_shade');   // back
    v.box(-15, -12, 38, 49, -9, -2, 'hair_mid');        // sides: long behind the ear,
    v.box(-15, -12, 43, 49, -2, 4, 'hair_mid');         // short in front of it
    v.box(12, 15, 39, 49, -9, -2, 'hair_mid');
    v.box(12, 15, 44, 49, -2, 4, 'hair_mid');
    v.box(-15, -13, 35, 38, -7, -2, 'hair_shade');      // one lock falls lower
    v.box(-17, -15, 45, 49, -6, 1, 'hair');             // and one sticks out
    v.cut(-14, 14, 48, 51, -10, 11, 4, 'hair');         // dome, tier one
    v.cut(-12, 12, 51, 53, -8, 9, 4, 'hair');           // dome, tier two
    v.paint(-6, -5, 51, 53, -8, 11, 'hair_shade');      // parting, read from above
    v.cut(-13, -6, 44, 49, 9, 12, 1, 'hair');           // three fringe locks
    v.cut(-6, 2, 45, 49, 9, 12, 1, 'hair_mid');
    v.cut(2, 12, 46, 49, 9, 11, 1, 'hair');
    v.box(-4, 4, 53, 54, -4, 3, 'hair');                // crown tuft
  },
  braids(v) {
    v.cut(-14, 14, 34, 49, -11, -4, 2, 'hair_shade');
    v.box(-15, -12, 38, 49, -9, 4, 'hair_mid');
    v.box(12, 15, 38, 49, -9, 4, 'hair_mid');
    v.box(-14, -11, 35, 46, 4, 10, 'hair');             // locks framing the face
    v.box(11, 14, 35, 46, 4, 10, 'hair');
    v.cut(-14, 14, 48, 51, -10, 11, 4, 'hair');
    v.cut(-12, 12, 51, 53, -8, 9, 4, 'hair');
    v.paint(-1, 1, 50, 53, -8, 12, 'hair_shade');       // centre parting
    v.cut(-13, -1, 45, 49, 9, 12, 1, 'hair');           // bangs, parted
    v.cut(1, 13, 46, 49, 9, 12, 1, 'hair_mid');
    v.both(b => {                                       // twin braids over the shoulders
      b.cut(-16, -11, 36, 43, 2, 8, 1, 'hair_mid');
      b.cut(-16, -11, 34, 36, 2, 8, 1, 'hair_shade');
      b.cut(-16, -11, 28, 34, 2, 8, 1, 'hair');
      b.cut(-16, -11, 26, 28, 2, 8, 1, 'hair_shade');
      b.cut(-15, -12, 22, 26, 3, 7, 1, 'hair_mid');
    });
  },
  elder(v) {
    v.cut(-13, 13, 36, 47, -11, -5, 2, 'hair_shade');
    v.box(-15, -12, 38, 47, -8, 3, 'hair_mid'); v.box(12, 15, 38, 47, -8, 3, 'hair_mid');
    v.box(-17, -14, 43, 47, -5, 2, 'hair'); v.box(14, 17, 43, 47, -5, 2, 'hair');
  },
};

export function dwarf({ hair = 'swept', beard = 'block', brows = 'arched', cloth = 'tunic',
  dome = false, wrinkles = false, mouth = false } = {}) {
  const v = new Vox();
  boots(v);
  body(v, [cloth, cloth + '_dark', cloth + '_light']);
  hands(v, cloth + '_dark');
  head(v, { dome, wrinkles });
  if (mouth) smile(v);
  eyes(v);
  v.both(BROWS[brows]);
  if (beard) BEARDS[beard](v);
  HAIR_STYLES[hair](v);
  return v;
}

// ── Furniture and goods ──────────────────────────────────────────────────────
export function stool() {           // 14 x 14 x 14, seat at Y14 (0.875 block)
  const v = new Vox();
  v.cut(-7, 7, 0, 2, -7, 7, 3, 'bark_dark');      // root flare
  v.cut(-6, 6, 2, 12, -6, 6, 2, 'bark');
  v.box(-7, -6, 3, 11, -3, 2, 'bark_light');      // bark plates proud by one cell
  v.box(6, 7, 2, 9, -1, 4, 'bark_light');
  v.box(-2, 3, 3, 10, 6, 7, 'bark_light');
  v.box(-4, 0, 4, 11, -7, -6, 'bark_light');
  v.cut(-6, 6, 12, 14, -6, 6, 2, 'bark');         // bark rim around the seat
  v.cut(-5, 5, 13, 14, -5, 5, 2, 'wood_top');
  v.ring(-3, 2, 13, -3, 2, 'grain');              // one square growth ring, off centre
  v.box(-1, 0, 13, 14, -1, 0, 'pith');
  v.box(1, 5, 13, 14, 0, 1, null);                // drying split, carved
  v.box(5, 6, 10, 14, 0, 1, null);
  return v;
}

export function diningTable() {    // 46 x 24 x 46: 3x3 blocks, top at Y24
  const v = new Vox();
  v.cut(-17, 17, 0, 3, -3, 3, 1, 'wood_dark');    // cross foot
  v.cut(-3, 3, 0, 3, -17, 17, 1, 'wood_dark');
  v.box(-17, -14, 0, 4, -3, 3, 'wood_dark'); v.box(14, 17, 0, 4, -3, 3, 'wood_dark');
  v.box(-3, 3, 0, 4, -17, -14, 'wood_dark'); v.box(-3, 3, 0, 4, 14, 17, 'wood_dark');
  v.cut(-7, 7, 3, 16, -7, 7, 2, 'bark');          // square post
  v.box(-8, -7, 4, 14, -3, 2, 'bark_light'); v.box(7, 8, 5, 15, -1, 4, 'bark_light');
  v.box(-3, 2, 4, 15, 7, 8, 'bark_light'); v.box(-2, 3, 5, 13, -8, -7, 'bark_light');
  v.box(-21, 21, 14, 16, -18, -14, 'wood_dark');  // battens
  v.box(-21, 21, 14, 16, 14, 18, 'wood_dark');
  v.box(-22, 22, 16, 18, -21, 21, 'wood_dark');   // inset lip: shadow line under the slab
  // Three hewn planks with staggered ends and one-cell seams
  v.cut(-23, -9, 18, 24, -22, 22, 2, 'wood_side'); v.paint(-23, -9, 23, 24, -22, 22, 'wood_top');
  v.cut(-8, 8, 18, 24, -23, 23, 2, 'wood_side');   v.paint(-8, 8, 23, 24, -23, 23, 'wood_top_alt');
  v.cut(9, 23, 18, 24, -22, 21, 2, 'wood_side');   v.paint(9, 23, 23, 24, -22, 21, 'wood_top');
  for (const px of [-17, -1, 15]) for (const pz of [-19, 16]) v.paint(px, px + 2, 23, 24, pz, pz + 2, 'wood_dark');
  v.box(-11, -7, 23, 24, 4, 5, 'wood_dark');      // butterfly key across the seam
  v.box(-10, -8, 22, 24, 5, 8, 'wood_dark');
  v.box(-11, -7, 23, 24, 8, 9, 'wood_dark');
  v.paint(11, 16, 23, 24, -10, -5, 'grain'); v.paint(12, 15, 23, 24, -9, -6, 'wood_top');
  v.paint(13, 14, 23, 24, -8, -7, 'pith');        // one knot
  return v;
}

export function wallTorch() {      // wall plane at Z0, faces +Z; 8 x 24 x 11
  const v = new Vox();
  v.cut(-3, 3, 6, 14, 0, 2, 1, 'wood_dark');      // wall plate
  v.box(-2, -1, 12, 13, 2, 3, 'iron'); v.box(1, 2, 7, 8, 2, 3, 'iron');
  v.box(-1, 1, 9, 11, 2, 6, 'iron');              // arm
  v.box(-3, 3, 9, 11, 5, 11, 'iron'); v.box(-2, 2, 9, 11, 6, 10, null);
  v.box(-2, 2, 3, 13, 6, 10, 'wood_side');        // squared torch stick
  v.box(-3, 3, 11, 14, 5, 11, 'rope'); v.paint(-3, 3, 12, 13, 5, 11, 'rope_dark');
  v.box(-2, 2, 14, 15, 6, 10, 'char');
  v.box(-3, 3, 15, 18, 5, 11, 'flame_out');       // stepped square flame
  v.box(-2, 2, 18, 21, 6, 10, 'flame_mid');
  v.box(-1, 1, 21, 23, 7, 9, 'flame_core');
  v.box(0, 1, 23, 24, 7, 8, 'flame_core');
  return v;
}

export function campfire() {       // stone ring in a 3x3 area
  const v = new Vox();
  v.cut(-10, 10, 0, 1, -10, 10, 4, 'ash');
  v.cut(-6, 6, 1, 2, -6, 6, 2, 'ember');
  const stones = [[12, 0, 5, 'stone'], [9, 9, 4, 'stone_light'], [0, 12, 6, 'stone'], [-9, 9, 4, 'stone_light'],
    [-12, 0, 5, 'stone'], [-9, -9, 6, 'stone_light'], [0, -12, 4, 'stone'], [9, -9, 5, 'stone_light']];
  for (const [cx, cz, h, c] of stones) {
    const wide = cx === 0, deep = cz === 0;
    v.pillow(cx - (deep ? 3 : 4), cx + (deep ? 3 : 4), 0, h, cz - (wide ? 3 : 4), cz + (wide ? 3 : 4), 1, c);
  }
  v.cutX(-9, 9, 1, 5, -2, 2, 1, 'bark');
  v.paint(-9, -8, 1, 5, -2, 2, 'wood_top'); v.paint(8, 9, 1, 5, -2, 2, 'wood_top');
  v.cutZ(-2, 2, 4, 8, -9, 9, 1, 'bark_light');
  v.paint(-2, 2, 4, 8, -9, -8, 'wood_top'); v.paint(-2, 2, 4, 8, 8, 9, 'wood_top');
  v.paint(-4, 4, 1, 8, -4, 4, 'char');
  v.box(-5, 5, 6, 10, -5, 5, 'flame_out');
  v.box(4, 7, 6, 12, -4, -1, 'flame_out'); v.box(-7, -4, 6, 10, 1, 4, 'flame_out');
  v.box(-4, 3, 10, 14, -3, 4, 'flame_mid');
  v.box(-2, 2, 14, 18, -2, 2, 'flame_core');
  v.box(-1, 1, 18, 21, 0, 2, 'flame_core');
  return v;
}

export function bed() {            // 4 x 3 blocks, head toward -X, sleep surface near Y13
  const v = new Vox();
  v.cutX(-30, 30, 0, 8, -24, -18, 1, 'bark'); v.cutX(-30, 30, 0, 8, 18, 24, 1, 'bark');
  v.pillow(-32, -25, 0, 20, -24, -17, 1, 'bark_dark', 'wood_top');
  v.pillow(-32, -25, 0, 20, 17, 24, 1, 'bark_dark', 'wood_top');
  v.pillow(25, 32, 0, 13, -24, -17, 1, 'bark_dark', 'wood_top');
  v.pillow(25, 32, 0, 13, 17, 24, 1, 'bark_dark', 'wood_top');
  v.box(-31, -27, 6, 18, -17, 17, 'wood_side');   // headboard
  for (const z of [-6, 5]) v.box(-27, -26, 8, 18, z, z + 1, 'wood_dark');
  v.box(27, 31, 5, 11, -17, 17, 'wood_side');     // footboard
  v.cut(-27, 27, 5, 11, -18, 18, 2, 'linen_dark'); // straw-stuffed tick
  v.paint(-27, 27, 10, 11, -18, 18, 'linen');
  v.box(-26, -24, 6, 7, -19, -17, 'hay'); v.box(20, 23, 7, 8, 17, 19, 'hay');
  v.box(-8, 27, 10, 13, -19, 19, 'blanket');      // wool blanket, draped
  v.box(-8, 27, 7, 10, -19, -18, 'blanket'); v.box(-8, 27, 7, 10, 18, 19, 'blanket');
  for (const x of [3, 15]) v.paint(x, x + 3, 7, 13, -19, 19, 'blanket_stripe');
  v.box(-11, -7, 11, 14, -19, 19, 'blanket_light'); // folded edge
  v.pillow(-26, -13, 11, 15, -12, 12, 2, 'linen');
  v.paint(-22, -17, 14, 15, -6, 6, 'linen_dark');
  return v;
}

export function appleCrate() {     // 12 x 12 x 10
  const v = new Vox();
  v.box(-6, 6, 0, 8, -5, 5, 'wood_dark');
  v.box(-6, 6, 1, 4, -5, 5, 'wood_side'); v.box(-6, 6, 5, 8, -5, 5, 'wood_side');
  for (const x of [-6, 4]) for (const z of [-5, 3]) v.box(x, x + 2, 0, 9, z, z + 2, 'wood_dark');
  v.box(-5, 5, 5, 9, -4, 4, null);
  const apple = (x, y, z, leaf = true) => {
    v.cut(x, x + 4, y, y + 4, z, z + 4, 1, 'apple'); v.paint(x, x + 4, y, y + 1, z, z + 4, 'apple_dark');
    if (leaf) v.box(x + 1, x + 2, y + 4, y + 5, z + 2, z + 3, 'leaf');
  };
  apple(-5, 5, -4); apple(-1, 6, -4, false); apple(1, 5, 0); apple(-4, 6, 0, false); apple(-2, 8, -2);
  return v;
}

export function beam() {           // squared timber: 14 x 10 x 10, bark wane on two edges
  const v = new Vox();
  v.cutX(-7, 7, 0, 10, -5, 5, 2, 'wood_side');
  v.paint(-7, 7, 9, 10, -5, 5, 'wood_top');
  v.paint(-7, 3, 7, 10, -5, -3, 'bark'); v.paint(-5, 7, 0, 4, 3, 5, 'bark');
  for (const x of [-7, 6]) {
    v.paint(x, x + 1, 0, 10, -5, 5, 'wood_top');
    v.paint(x, x + 1, 2, 8, -3, 3, 'grain'); v.paint(x, x + 1, 3, 7, -2, 2, 'wood_top');
    v.paint(x, x + 1, 4, 6, -1, 1, 'pith');
  }
  v.paint(-3, -2, 9, 10, -4, 5, 'wood_side'); v.paint(2, 3, 9, 10, -4, 5, 'wood_side');
  return v;
}

// ── Furniture tiers ──────────────────────────────────────────────────────────
// Tier 1 · Axe-Hewn Era: split, chopped and notched with an axe alone. Bark
// stays on, ends are chopped in steps, joints are notches, bedding is loose hay.
// Tier 2 · Carpenter Era: the dressed plank table and blanket bed above.

// Paint square growth rings on a log end. axis 'x' paints the plane x = at in
// (y, z); axis 'z' paints z = at in (x, y). Rings are outlines at each radius.
export function endRings(v, axis, at, cu, cv, radii) {
  const face = (u0, u1, w0, w1, c) => axis === 'x'
    ? v.paint(at, at + 1, u0, u1, w0, w1, c)
    : v.paint(u0, u1, w0, w1, at, at + 1, c);
  for (const r of radii) {
    face(cu - r, cu + r + 1, cv - r, cv - r + 1, 'grain');
    face(cu - r, cu + r + 1, cv + r, cv + r + 1, 'grain');
    face(cu - r, cu - r + 1, cv - r, cv + r + 1, 'grain');
    face(cu + r, cu + r + 1, cv - r, cv + r + 1, 'grain');
  }
  face(cu, cu + 1, cv, cv + 1, 'pith');
}

// One half of a split log, riven face up, lying along X. The section steps in
// like a D (bark underneath) and each lower step is chopped shorter, so the
// ends read as axe cuts rather than saw cuts.
export function splitHalf(v, x0, x1, z0, z1, top) {
  const steps = [[2, 0, 0], [2, 1, 1], [2, 3, 2], [2, 6, 4]]; // [layers, side inset, end chop]
  const layers = [];
  let y = top;
  for (const [h, inset, chop] of steps) {
    v.box(x0 + chop, x1 - chop, y - h, y, z0 + inset, z1 - inset, 'bark');
    layers.push({ y0: y - h, y1: y, inset, chop });
    y -= h;
  }
  v.paint(x0, x1, top - 1, top, z0 + 1, z1 - 1, 'riven');                           // split face, bark rim on both edges
  const zc = Math.floor((z0 + z1) / 2);
  // Chopped end faces show end grain: half rings around a pith on the split face.
  // Each step has its own end plane, so each gets its own share of the rings.
  for (const { y0, y1, inset, chop } of layers) for (const x of [x0 + chop, x1 - chop - 1]) {
    v.paint(x, x + 1, y0, y1, z0 + inset, z1 - inset, 'wood_top');
    for (const r of [3, 6]) {
      const ya = Math.max(top - 1 - r, y0), yb = Math.min(top, y1);
      if (ya < yb) { v.paint(x, x + 1, ya, yb, zc - r, zc - r + 1, 'grain'); v.paint(x, x + 1, ya, yb, zc + r, zc + r + 1, 'grain'); }
      if (top - 1 - r >= y0 && top - 1 - r < y1) v.paint(x, x + 1, top - 1 - r, top - r, zc - r, zc + r + 1, 'grain');
    }
    if (top - 1 >= y0) v.paint(x, x + 1, top - 1, top, zc, zc + 1, 'pith');
  }
  return zc;
}

export function splitSlabBench() {  // Tier 1 table: 46 x 24 x 46, top at Y24, 3x3 footprint, same 5x5 stool layout
  const v = new Vox();
  // Support kept inside the centre block, where the table's seating obstacle already is,
  // so seated legs stay clear: two short logs crossed in a lap notch.
  v.cutX(-8, 8, 0, 9, -4, 4, 2, 'bark');
  v.box(-6, 4, 3, 6, -5, -4, 'bark_light');                // one loose bark plate
  endRings(v, 'x', -8, 4, -1, [2]); endRings(v, 'x', 7, 4, -1, [2]);
  v.cutZ(-4, 4, 7, 16, -12, 12, 2, 'bark');                // upper log drops two cells into the lower one
  endRings(v, 'z', -12, -1, 11, [2]); endRings(v, 'z', 11, -1, 11, [2]);
  // Two halves of one split log, laid riven face up with a gap between them.
  const za = splitHalf(v, -23, 23, -23, -1, 24);           // north half, full length
  const zb = splitHalf(v, -22, 22, 1, 23, 24);             // south half, a cell shorter at each end
  // Riven grain: long broken lines, not noise
  v.paint(-18, -2, 23, 24, za - 4, za - 3, 'riven_dark'); v.paint(3, 19, 23, 24, za + 4, za + 5, 'riven_dark');
  v.paint(-20, -6, 23, 24, zb + 3, zb + 4, 'riven_dark'); v.paint(-3, 15, 23, 24, zb - 4, zb - 3, 'riven_dark');
  // Axe bites near the ends
  for (const [x, z] of [[-20, za - 1], [-19, za], [-18, za + 1], [-17, za - 1], [-16, za], [17, zb], [18, zb + 1], [19, zb + 2]]) v.paint(x, x + 1, 23, 24, z, z + 1, 'chop');
  // A knot on the south half and a drying split running out of the north half's east end
  v.paint(7, 10, 23, 24, zb + 2, zb + 4, 'riven_dark'); v.paint(8, 9, 23, 24, zb + 2, zb + 3, 'pith');
  v.box(11, 23, 23, 24, za, za + 1, null);                // the split runs down the stepped end
  v.box(19, 23, 18, 24, za, za + 1, null);
  return v;
}

export function notchedLogBed() {  // Tier 1 bed: 64 x 15 x 48, 4x3 footprint, head toward -X, sleep surface Y12
  const v = new Vox();
  // Side logs lie on the floor; their ends run past the corners.
  for (const [z0, z1, x0] of [[-20, -12, -32], [12, 20, -31]]) {
    v.cutX(x0, 32, 0, 8, z0, z1, 2, 'bark');
    v.box(x0, x0 + 2, 6, 8, z0, z1, null); v.box(30, 32, 6, 8, z0, z1, null);    // chopped, stepped ends
    endRings(v, 'x', x0, 3, z0 + 3, [2]); endRings(v, 'x', 31, 3, z0 + 3, [2]);
    v.paint(x0 + 2, x0 + 3, 6, 8, z0, z1, 'wood_top'); v.paint(29, 30, 6, 8, z0, z1, 'wood_top');
  }
  v.box(-18, -6, 2, 6, -21, -20, 'bark_light'); v.box(4, 16, 2, 6, 20, 21, 'bark_light'); // loose bark plates
  // Saddle notches: the end logs drop three cells into the side logs at each corner.
  for (const [x0, x1] of [[-29, -21], [21, 29]]) for (const [z0, z1] of [[-20, -12], [12, 20]]) v.box(x0, x1, 5, 8, z0, z1, null);
  // End logs cross on top. The head log is thicker and stands as a low headboard.
  for (const [x0, x1, top] of [[-29, -21, 15], [21, 29, 13]]) {
    v.cutZ(x0, x1, 5, top, -24, 24, 2, 'bark');
    v.box(x0, x1, top - 2, top, -24, -23, null); v.box(x0, x1, top - 2, top, 23, 24, null);
    endRings(v, 'z', -24, x0 + 3, 5 + Math.floor((top - 5) / 2) - 1, [2]); endRings(v, 'z', 23, x0 + 3, 5 + Math.floor((top - 5) / 2) - 1, [2]);
    v.paint(x0, x1, top - 2, top, -23, -22, 'wood_top'); v.paint(x0, x1, top - 2, top, 22, 23, 'wood_top');
  }
  // Loose hay heaped inside the frame, above the side logs. The heap is built from
  // overlapping tufts, one straw colour each, so its texture comes from shape.
  v.box(-21, 21, 0, 9, -12, 12, 'hay_dark');
  v.cut(-21, 21, 9, 11, -12, 12, 2, 'hay_mid');
  v.cut(-19, 20, 11, 12, -11, 11, 3, 'hay_mid');          // continuous sleeping surface at Y12
  v.cut(-21, -9, 11, 13, -10, 10, 3, 'hay_mid');           // a heap under the head
  let seed = 11;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const tones = ['hay_light', 'hay_light', 'hay_mid', 'straw', 'hay_mid', 'hay_dark'];
  for (let i = 0; i < 34; i++) {
    const w = 3 + Math.floor(rnd() * 5), d = 3 + Math.floor(rnd() * 4);
    const x0 = -21 + Math.floor(rnd() * (42 - w)), z0 = -12 + Math.floor(rnd() * (24 - d));
    const head = x0 + w <= -8, body = x0 > -9 && z0 > -8 && z0 + d < 8;
    const base = head ? 13 : 12, h = body ? 1 : 1 + Math.floor(rnd() * 2);
    v.cut(x0, x0 + w, base, base + h, z0, z0 + d, 1, tones[Math.floor(rnd() * tones.length)]);
  }
  v.box(-12, -5, 8, 10, -14, -12, 'hay_mid'); v.box(2, 10, 8, 10, 12, 15, 'hay_light'); v.box(14, 18, 8, 9, -15, -12, 'hay_mid'); // spill over the logs
  v.box(-20, -15, 8, 10, 12, 14, 'hay_dark'); v.box(-3, 1, 8, 9, -15, -12, 'hay_light');
  v.box(19, 23, 12, 14, -5, 3, 'hay_mid');                 // and over the foot log
  v.box(-15, -14, 11, 12, 10, 15, 'straw'); v.box(6, 11, 12, 13, -3, -2, 'straw'); v.box(20, 21, 11, 12, -9, -4, 'straw');
  v.box(-26, -22, 14, 15, 3, 4, 'straw');
  for (const [x, y, z] of [[-4, 12, 6], [12, 12, -7], [-16, 15, 1], [3, 12, -9]]) v.box(x, x + 1, y, y + 1, z, z + 1, 'leaf_dry');
  return v;
}

export const TIERS = [
  { id: 'tier1_axe_hewn', label: 'Tier 1 · Axe-Hewn Era',
    note: 'Split, chopped and notched with an axe alone. Bark stays on, ends are chopped in steps, joints are notches, bedding is loose hay.',
    models: [
      { id: 'split_slab_bench', name: 'Split-Slab Bench', role: 'table', build: splitSlabBench,
        contacts: 'Top at Y24 (1.5 blocks) across the 3×3 footprint; support only inside the centre block (the existing seating obstacle); four stools keep the 5×5 layout.' },
      { id: 'notched_log_bed', name: 'Notched Log Bed', role: 'bed', build: notchedLogBed,
        contacts: '4×3 footprint, head toward −X, hay sleeping surface at Y12 (0.75 block), nothing above Y15, inside the existing 1-block collision.' },
    ] },
  { id: 'tier2_carpenter', label: 'Tier 2 · Carpenter Era',
    note: 'Dressed planks, pegs and a butterfly key; a wool blanket and linen pillow. Kept unchanged from the first Hearthblock proposal.',
    models: [
      { id: 'plank_dining_table', name: 'Plank Dining Table', role: 'table', build: () => diningTable(),
        contacts: 'Top at Y24 across the 3×3 footprint; square post on a cross foot; four stools keep the 5×5 layout.' },
      { id: 'blanket_bed', name: 'Blanket Bed', role: 'bed', build: () => bed(),
        contacts: '4×3 footprint, head toward −X, blanket surface near Y13, posts to Y20.' },
    ] },
];

export const ROSTER = [
  { id: 'brann', name: 'Brann', opts: { hair: 'swept', beard: 'block', brows: 'arched', cloth: 'tunic' }, skin: 'medium', hair: 'ginger' },
  { id: 'sigrun', name: 'Sigrun', opts: { hair: 'braids', beard: null, brows: 'fine', cloth: 'moss', mouth: true }, skin: 'pale', hair: 'chestnut' },
  { id: 'thrain', name: 'Thrain', opts: { hair: 'elder', beard: 'forked', brows: 'bushy', cloth: 'rust', dome: true, wrinkles: true }, skin: 'dark', hair: 'white' },
];

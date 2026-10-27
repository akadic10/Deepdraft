// Hearthblock Sky Dial (doc 23, "The Sky Dial"; chosen by the owner, 2026-10-26): a stone
// window under a hewn-oak lintel, looking at the sky. Each piece is an ordinary model on the
// 1:16 grid, seen from the front: x right, y up, z toward the viewer. The `sky` family in
// build.py is staged only; tools/GenerateUiIcons.gd renders each piece to a picture in
// assets/ui/sky_dial/ with the framing in data/ui/sky_dial.json, and SkyDial.gd stacks them:
// the sky for the part of the day, the stars, the sun or moon on its arc, the clouds, the rain
// or snow, the season's hills, then the frame.
// Options: `framing` 'picture' renders a piece where it sits in the window; 'sprite' renders
// it alone round its origin, for the dial to move. `unshaded` pieces give light (the sun, the
// stars). `outline` draws the icons' dark outline round the piece (the frame, the dial's edge).
import * as P from './proposal.mjs';

const { Vox } = P;

// Roles the proposal palette lacks: the sky's four bands for each part of the day (0 at the
// top), the sun and moon, clouds and weather, and each season's grass, far hills and leaves.
export const PALETTE = {
  sky_day_0: '#5B90CA', sky_day_1: '#74A6D9', sky_day_2: '#91BDE5', sky_day_3: '#B0D2EE',
  sky_dawn_0: '#5E6FAE', sky_dawn_1: '#9A86B6', sky_dawn_2: '#E2A09A', sky_dawn_3: '#F4C88C',
  sky_dusk_0: '#363F7A', sky_dusk_1: '#77508A', sky_dusk_2: '#C7646C', sky_dusk_3: '#EE985A',
  sky_night_0: '#10172F', sky_night_1: '#162045', sky_night_2: '#1D2B57', sky_night_3: '#283B69',
  sky_grey_0: '#77828F', sky_grey_1: '#8994A0', sky_grey_2: '#9CA6B0', sky_grey_3: '#AEB6BE',
  sun: '#F6C24C', sun_light: '#FFE49A', sun_dark: '#E39A2D',
  moon: '#ECE6D6', moon_dark: '#C2BBAA', star: '#FFF4CF',
  cloud: '#F4F6F8', cloud_shade: '#CDD6DF', storm: '#8D97A3', storm_shade: '#6B7581',
  rain: '#A9C3D6', snow: '#FFFFFF', snow_shade: '#DCE5EE',
  grass: '#6F9A4C', grass_light: '#8FB862',
  spring_grass: '#84AD54', spring_light: '#A2C866',
  autumn_grass: '#8E8B47', autumn_light: '#ABA052',
  earth: '#8B6243', earth_dark: '#6A4831',
  far_summer: '#5F8A6E', far_spring: '#76A07A', far_autumn: '#8E8565', far_winter: '#C3CDD6',
  far_summer_top: '#6E9A7A', far_spring_top: '#88B087', far_autumn_top: '#A09572', far_winter_top: '#E4EAF0',
  pine: '#3F6B4A', pine_light: '#55835C', pine_dark: '#2F533A',
  oak_leaf: '#5F8B35', oak_leaf_light: '#7AA548', oak_leaf_dark: '#476B28',
  blossom: '#F1BFCD', blossom_light: '#FBE2EA', blossom_dark: '#D898AC',
  autumn_a: '#CB6530', autumn_b: '#E39C3B', autumn_c: '#A8432C',
  flower_white: '#F7F2E6', flower_pink: '#E996AE', flower_gold: '#F3CF5A',
};

// The opening: x -26..26, y 6..41, between the jambs, over the sill and under the lintel.
const OPEN = { x0: -26, x1: 26, y0: 6, y1: 42 };

// A stone window: jambs in courses of light and plain blocks with dark joints, a sill that
// stands out, a hewn oak lintel with its grain and two pegs, and a brass lip round the opening.
function frame() {
  const v = new Vox();
  for (const side of [-1, 1]) {
    const x0 = side < 0 ? -32 : 26, x1 = side < 0 ? -26 : 32;
    let y = 4, i = side < 0 ? 0 : 1;
    for (const tall of [9, 8, 10, 10]) {
      v.cutZ(x0, x1, y, y + tall, 0, 6, 1, i % 2 ? 'stone_light' : 'stone');
      v.paint(x0, x1, y, y + 1, 0, 6, 'stone_dark');
      y += tall; i++;
    }
  }
  v.cutZ(-35, 35, 0, 5, 0, 9, 1, 'stone_light');
  v.paint(-35, 35, 0, 1, 0, 9, 'stone_dark'); v.paint(-35, 35, 4, 5, 7, 9, 'stone');
  v.cutZ(-34, 34, 41, 47, -1, 8, 1, 'wood_side');
  v.paint(-34, 34, 46, 47, -1, 8, 'wood_top'); v.paint(-34, 34, 41, 42, -1, 8, 'wood_dark');
  for (const [x0, x1, y] of [[-28, -11, 43], [-5, 13, 44], [17, 29, 43]]) v.paint(x0, x1, y, y + 1, 7, 8, 'grain');
  for (const x of [-31, 29]) { v.box(x, x + 2, 43, 45, 8, 9, 'wood_dark'); v.box(x, x + 1, 44, 45, 8, 9, 'pith'); }
  v.box(-27, 27, 5, 6, 5, 7, 'brass_dark');
  v.box(-27, -26, 5, 41, 5, 7, 'brass'); v.box(26, 27, 5, 41, 5, 7, 'brass');
  return v;
}

// The sky behind the opening for one part of the day, in four bands, lightest at the horizon.
function sky(time) {
  const v = new Vox();
  const rows = OPEN.y1 - OPEN.y0;
  for (let y = OPEN.y0; y < OPEN.y1; y++)
    v.box(OPEN.x0, OPEN.x1, y, y + 1, -2, -1, `sky_${time}_${Math.min(3, Math.floor((OPEN.y1 - 1 - y) * 4 / rows))}`);
  return v;
}

// Stars at fixed spots, a few of them crosses.
function stars() {
  const v = new Vox();
  for (let i = 0; i < 18; i++) {
    const x = -25 + ((i * 29 + 7) % 50), y = 20 + ((i * 17 + 3) % 21);
    v.box(x, x + 1, y, y + 1, 0, 1, 'star');
    if (i % 5 === 0) {
      v.box(x - 1, x, y, y + 1, 0, 1, 'star'); v.box(x + 1, x + 2, y, y + 1, 0, 1, 'star');
      v.box(x, x + 1, y - 1, y, 0, 1, 'star'); v.box(x, x + 1, y + 1, y + 2, 0, 1, 'star');
    }
  }
  return v;
}

// The sun: a notched block with a lit core and eight stubby rays, round its origin.
function sun() {
  const v = new Vox();
  const r = 5;
  v.cutZ(-r, r, -r, r, 0, 2, 3, 'sun');
  v.paint(-r + 2, 1, 0, r - 2, 1, 2, 'sun_light');
  v.paint(-r, r, -r, -r + 2, 0, 2, 'sun_dark');
  for (const [x0, x1, y0, y1] of [[-1, 1, 7, 9], [-1, 1, -9, -7], [7, 9, -1, 1], [-9, -7, -1, 1]]) v.box(x0, x1, y0, y1, 0, 1, 'sun');
  for (const [x, y] of [[5, 5], [-7, 5], [5, -7], [-7, -7]]) v.box(x, x + 2, y, y + 2, 0, 1, 'sun_dark');
  return v;
}

// The moon: a pale notched block bitten into a crescent, with two craters, round its origin.
function moon() {
  const v = new Vox();
  v.cutZ(-5, 5, -5, 5, 0, 2, 3, 'moon');
  v.cutZ(0, 10, -4, 7, 0, 2, 3, null);
  v.paint(-4, -2, -1, 1, 1, 2, 'moon_dark');
  v.paint(-2, -1, -3, -2, 1, 2, 'moon_dark');
  return v;
}

// A cloud: overlapping notched blocks with a shaded underside; storm clouds are darker.
function cloud(w, role, shade) {
  const v = new Vox();
  v.cutZ(-w, w, 0, 5, 0, 3, 2, role);
  v.cutZ(-Math.round(w * 0.6), Math.round(w * 0.3), 3, 9, 0, 3, 2, role);
  v.cutZ(-Math.round(w * 0.1), Math.round(w * 0.7), 2, 7, 0, 3, 2, role);
  v.paint(-w, w, 0, 1, 0, 3, shade);
  return v;
}

// Rain (short slanted streaks) or snow (single flakes) across the opening, at fixed spots. The
// dial scrolls it down through the opening, so the field repeats from its top to its foot.
function fall(kind) {
  const v = new Vox();
  for (let i = 0; i < 64; i++) {
    const x = OPEN.x0 + ((i * 37 + 11) % 52), y = OPEN.y0 + 2 + ((i * 23 + 5) % 34);
    if (kind === 'rain' && i % 2 === 0) { v.box(x, x + 1, y, y + 2, 0, 1, 'rain'); v.box(x - 1, x, y - 2, y, 0, 1, 'rain'); }
    if (kind === 'snow' && i % 3 === 0) v.box(x, x + 1, y, y + 1, 0, 1, i % 2 ? 'snow' : 'snow_shade');
  }
  return v;
}

// A rolling hill line, stepped to whole cells: the same every time.
const line = (x, base, amp, phase, freq) =>
  base + Math.round(amp * (0.62 * Math.sin(x * freq + phase) + 0.38 * Math.sin(x * freq * 2.3 + phase * 1.7)));

const SEASONS = {
  spring: { grass: 'spring_grass', light: 'spring_light', far: 'far_spring', far_top: 'far_spring_top' },
  summer: { grass: 'grass', light: 'grass_light', far: 'far_summer', far_top: 'far_summer_top' },
  autumn: { grass: 'autumn_grass', light: 'autumn_light', far: 'far_autumn', far_top: 'far_autumn_top' },
  winter: { grass: 'snow_shade', light: 'snow', far: 'far_winter', far_top: 'far_winter_top' },
};

// A pine: a trunk under stepped tiers, snow on each tier's top in winter. `s` scales it.
function pine(v, x, y, z, s, season) {
  v.box(x - s, x + s, y, y + 2 * s, z, z + 2, 'bark');
  let yy = y + 2 * s;
  for (const [half, tall] of [[4, 3], [3, 3], [2, 2], [1, 2]]) {
    v.cutZ(x - half * s, x + half * s, yy, yy + tall * s, z - 1, z + 3, 1, 'pine');
    v.paint(x - half * s, x - half * s + s, yy, yy + tall * s, z - 1, z + 3, 'pine_dark');
    v.paint(x + half * s - s, x + half * s, yy, yy + s, z - 1, z + 3, 'pine_light');
    if (season === 'winter') v.paint(x - half * s, x + half * s, yy + tall * s - 1, yy + tall * s, z - 1, z + 3, 'snow');
    yy += tall * s;
  }
}

// An oak: a notched crown in the season's leaves (blossom, green, orange), bare with snow in winter.
function oak(v, x, y, z, s, season) {
  v.box(x - s, x + s, y, y + 4 * s, z, z + 2, 'bark');
  v.paint(x - s, x, y, y + 4 * s, z, z + 2, 'bark_dark');
  const top = y + 4 * s;
  if (season === 'winter') {
    v.box(x - 3 * s, x - s, top + s, top + 2 * s, z, z + 2, 'bark');
    v.box(x - 4 * s, x - 3 * s, top + 2 * s, top + 3 * s, z, z + 2, 'bark');
    v.box(x + s, x + 3 * s, top + 2 * s, top + 3 * s, z, z + 2, 'bark');
    v.box(x - s, x + s, top, top + 4 * s, z, z + 2, 'bark');
    v.box(x - 4 * s, x - 3 * s, top + 3 * s, top + 3 * s + 1, z, z + 2, 'snow');
    v.box(x + s, x + 3 * s, top + 3 * s, top + 3 * s + 1, z, z + 2, 'snow');
    v.box(x - s, x + s, top + 4 * s, top + 4 * s + 1, z, z + 2, 'snow');
    return;
  }
  const leaf = { spring: ['blossom', 'blossom_light', 'blossom_dark'], summer: ['oak_leaf', 'oak_leaf_light', 'oak_leaf_dark'],
    autumn: ['autumn_b', 'sun', 'autumn_a'] }[season];
  v.cutZ(x - 5 * s, x + 5 * s, top - s, top + 6 * s, z - 2, z + 4, 2 * s, leaf[0]);
  v.paint(x - 5 * s, x + 5 * s, top - s, top + s, z - 2, z + 4, leaf[2]);
  v.paint(x - 3 * s, x + s, top + 4 * s, top + 6 * s, z - 2, z + 4, leaf[1]);
  if (season === 'autumn') {
    v.paint(x + 2 * s, x + 4 * s, top + s, top + 3 * s, z - 2, z + 4, 'autumn_c');
    v.paint(x - 5 * s, x - 3 * s, top + 2 * s, top + 3 * s, z - 2, z + 4, 'autumn_a');
  }
  if (season === 'spring') v.paint(x + s, x + 3 * s, top + 2 * s, top + 3 * s, z - 2, z + 4, 'flower_white');
}

// The season's land across the opening: far hills in the distance's colour with a small pine
// and oak, then near hills of grass over a cut bank of earth with a bigger pine and oak. Spring
// scatters flowers, summer a few gold ones, autumn fallen leaves; winter is snow.
function hills(season) {
  const v = new Vox();
  const S = SEASONS[season];
  for (let x = OPEN.x0; x < OPEN.x1; x += 2) {
    const f = line(x, 15, 3, 0.6, 0.11);
    v.box(x, x + 2, OPEN.y0, f, 0, 2, S.far);
    v.paint(x, x + 2, f - 1, f, 0, 2, S.far_top);
  }
  pine(v, -18, 15, 1, 1, season); oak(v, 17, 15, 1, 1, season);
  for (let x = OPEN.x0; x < OPEN.x1; x += 2) {
    const n = line(x, 11, 2.5, 2.1, 0.15);
    v.box(x, x + 2, OPEN.y0, OPEN.y0 + 2, 4, 7, (x >> 1) % 3 === 0 ? 'earth_dark' : 'earth');
    v.box(x, x + 2, OPEN.y0 + 2, n, 4, 7, S.grass);
    v.paint(x, x + 2, n - 1, n, 4, 7, S.light);
    const mark = ((x * 7 + 3) >> 1) % 5;
    if (season === 'spring' && mark < 2) v.box(x + (mark & 1), x + (mark & 1) + 1, n, n + 1, 6, 7, mark ? 'flower_pink' : 'flower_white');
    if (season === 'summer' && mark === 0) v.box(x + 1, x + 2, n, n + 1, 6, 7, 'flower_gold');
    if (season === 'autumn' && mark < 2) v.paint(x + mark, x + mark + 1, n - 1, n, 6, 7, mark ? 'autumn_a' : 'autumn_b');
  }
  pine(v, -21, 11, 5, 2, season); oak(v, 18, 11, 5, 1, season);
  return v;
}

const PIECES = {
  frame: [frame, { framing: 'picture', outline: true }],
  ...Object.fromEntries(['day', 'dawn', 'dusk', 'night', 'grey'].map(t => ['sky_' + t, [() => sky(t), { framing: 'picture' }]])),
  stars: [stars, { framing: 'picture', unshaded: true }],
  sun: [sun, { framing: 'sprite', unshaded: true }],
  moon: [moon, { framing: 'sprite' }],
  cloud_big: [() => cloud(10, 'cloud', 'cloud_shade'), { framing: 'sprite' }],
  cloud_small: [() => cloud(6, 'cloud', 'cloud_shade'), { framing: 'sprite' }],
  storm_big: [() => cloud(11, 'storm', 'storm_shade'), { framing: 'sprite' }],
  storm_small: [() => cloud(7, 'storm', 'storm_shade'), { framing: 'sprite' }],
  rain: [() => fall('rain'), { framing: 'picture' }],
  snow: [() => fall('snow'), { framing: 'picture' }],
  ...Object.fromEntries(Object.keys(SEASONS).map(s => ['hills_' + s, [() => hills(s), { framing: 'picture' }]])),
};

export const NAMES = Object.keys(PIECES).map(n => 'sky/' + n);
export const build = (name) => PIECES[name.slice(4)][0]();
export const options = (name) => PIECES[name.slice(4)][1];

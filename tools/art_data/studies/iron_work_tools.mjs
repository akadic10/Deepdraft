// Study (doc 301, 2026-11-10): the iron felling axe and the iron mining pickaxe, drawn and waiting
// for the Blacksmith's tool upgrade (data/professions/professions.json, "Iron pickaxe", planned).
// Nothing builds or installs this file. The game's default tools are stone bound with rope
// (tools/hearthblock/art/dwarves.mjs); these are the owner's second option from the hand tools
// sheet, kept so the upgrade has its art when its feature arrives.
//
// Same contracts as the stone tools: the hand grips the haft at (0, 0, 0), the support hand 10
// cells up; the axe's edge is at (0, 17, 11) and the pickaxe's point at (0, 22, 15). Colours are
// in tools/art_data/voxel_dwarves.json: wood, grain, tool_leather, iron, iron_dark, steel.
// Each takes a Vox from tools/hearthblock/art/proposal.mjs.
function haft(v, y0, y1) {
  v.box(-1, 1, y0, y1, -1, 1, 'wood'); v.paint(0, 1, y0, y1, -1, 1, 'grain');
  v.box(-1, 1, -3, 2, -1, 1, 'tool_leather'); v.box(-1, 1, 8, 10, -1, 1, 'tool_leather');   // leather grip wraps
}

// A dark head that flares to its edge in steps; the edge is the head's own iron, ground bright.
export function ironFellingAxe(v) {
  haft(v, -4, 20);
  v.cut(-2, 2, 14, 21, -3, 3, 1, 'iron_dark');                 // the eye, round the haft
  v.box(-1, 1, 15, 20, 3, 5, 'iron_dark');                      // the neck
  v.box(-1, 1, 14, 21, 5, 7, 'iron_dark');                      // the blade flares
  v.box(-1, 1, 12, 22, 7, 9, 'iron_dark');
  v.box(-1, 1, 11, 23, 9, 10, 'iron'); v.box(-1, 1, 11, 23, 10, 11, 'steel');   // the bevel and the edge
  v.paint(-2, 2, 20, 21, -3, 3, 'iron'); v.paint(-1, 1, 20, 21, 5, 7, 'iron'); v.paint(-1, 1, 21, 22, 7, 9, 'iron');   // lit top
  return v;
}

// Dark, lit only along its top, the arms thinning as they drop to the points.
export function ironPickaxe(v) {
  haft(v, -4, 26);
  v.cut(-2, 2, 24, 30, -3, 3, 1, 'iron_dark'); v.paint(-2, 2, 29, 30, -3, 3, 'iron');
  for (const s of [1, -1]) {
    const span = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
    let [a, b] = span(3, 7); v.box(-2, 2, 25, 29, a, b, 'iron_dark'); v.paint(-2, 2, 28, 29, a, b, 'iron');
    [a, b] = span(7, 11); v.box(-1, 1, 24, 28, a, b, 'iron_dark'); v.paint(-1, 1, 27, 28, a, b, 'iron');
    [a, b] = span(11, 14); v.box(-1, 1, 23, 26, a, b, 'iron_dark'); v.paint(-1, 1, 25, 26, a, b, 'iron');
    [a, b] = span(14, 15); v.box(-1, 1, 22, 24, a, b, 'steel');
  }
  return v;
}

// Export Hearthblock authoring logs (operations + reference cells) as JSON.
// Usage: node export.mjs <out.json>   (write_data.py runs this for you)
import { writeFileSync } from 'node:fs';
import * as P from './proposal.mjs';
import * as T from './tier1.mjs';
import * as D from './dwarves.mjs';
import * as W from './wildlife.mjs';
import * as I from './icons.mjs';
import * as S from './sky.mjs';

const cellsOf = (v) => [...v.cells].map(([k, c]) => [...P.Vox.unkey(k), c]).sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
const fromModel = (v) => ({ ops: v.log, cells: cellsOf(v) });
const log = (fn) => { const v = new P.Vox(); fn(v); return fromModel(v); };

// One side of a mirrored pair: the sub-log inside the single mirror_x entry.
function side(fn) {
  const v = new P.Vox(); fn(v);
  if (v.log.length !== 1 || v.log[0][0] !== 'mirror_x') throw new Error('expected one mirrored group');
  const one = new P.Vox(); replay(one, v.log[0][1]);
  return { ops: v.log[0][1], cells: cellsOf(one) };
}
function replay(v, ops) {
  for (const [op, a, c] of ops) {
    if (op === 'box') v.box(...a, c); else if (op === 'air') v.box(...a, null);
    else if (op === 'cutbox') v.cut(...a, c); else if (op === 'cutbox_x') v.cutX(...a, c);
    else if (op === 'cutbox_z') v.cutZ(...a, c); else if (op === 'paint') v.paint(...a, c);
    else if (op === 'ring') v.ring(...a, c);
    else if (op === 'mirror_x') { const s = new P.Vox(); replay(s, a); v.merge(s).merge(s.mirrorX()); }
    else throw new Error('unknown op ' + op);
  }
}

const out = {
  furniture: {
    stool: fromModel(P.stool()),
    split_slab_table: fromModel(T.splitSlabTable()),
    wall_torch: fromModel(P.wallTorch()),
    campfire: fromModel(P.campfire()),
    notched_log_bed: fromModel(P.notchedLogBed()),
    log_bench: fromModel(T.logBench()),
    game_table: fromModel(T.gameTable()),
    workbench: fromModel(T.workbench()),
    door_2: fromModel(T.doorLeaf(-16, 16, -1)),
    door_3: fromModel(T.doorLeaf(-24, 24, -1)),
    door_4_left: fromModel(T.doorLeaf(-32, 0, -1)),
    door_4_right: fromModel(T.doorLeaf(0, 32, 1)),
    fence_post: fromModel(T.fencePost()),
    fence_rails: fromModel(T.fenceRails()),
    gate_leaf: fromModel(T.gateLeaf()),
    ladder_kit: fromModel(T.ladderKit()),
    bridge_kit: fromModel(T.bridgeKit()),
    packed_crate: fromModel(T.packedCrate()),
    hearth: fromModel(T.hearth()),
    settlement_flag: fromModel(T.settlementFlag()),
  },
  dwarf: Object.fromEntries(D.NAMES.map(n => [n, fromModel(D.build(n))])),
  wildlife: Object.fromEntries(W.NAMES.map(n => [n, fromModel(W.build(n))])),
  icon: Object.fromEntries(I.NAMES.map(n => [n, { ...fromModel(I.build(n)), ...I.options(n) }])),
  sky: Object.fromEntries(S.NAMES.map(n => [n, { ...fromModel(S.build(n)), ...S.options(n) }])),
  sky_palette: S.PALETTE,
  palette: P.PALETTE,
  tints: { skin: P.SKIN, hair: P.HAIR },
};
for (let h = 1; h <= 4; h++) out.furniture['ladder_' + h] = fromModel(T.ladder(h));
for (let s = 1; s <= 5; s++) out.furniture['bridge_' + s] = fromModel(T.bridge(s));
writeFileSync(process.argv[2], JSON.stringify(out));

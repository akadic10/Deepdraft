"""Rebuild data/art/voxel_hearthblock.json from the Hearthblock authoring modules.

    py -3 tools/hearthblock/art/write_data.py      (needs node on PATH)

proposal.mjs holds the approved proposal models verbatim; tier1.mjs adds the
Tier 1 · Axe-Hewn pieces. export.mjs records each model's operations, and this
script adds the in-game palettes and pilot edits (dropped flame cells, offsets,
clips between dwarf layers, extra operations). tools/voxel_assets/hearthblock.py
replays the result. See docs/00_dev_roadmap/256_hearthblock_art_pilot.md.
"""
import json
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'data/art/voxel_hearthblock.json'

# Wood roles reuse the game's existing source palettes so every wood recolors.
HEWN = {'bark_dark': '463022', 'bark': '65442C', 'bark_light': '825B36', 'chop': '825B36',
        'wood_top': 'D4A264', 'riven': 'CA975A', 'riven_dark': 'A27643', 'grain': 'B88A50', 'pith': '966835'}
OAK = {'wood_dark': '6C4528', 'wood_side': '91633B', 'iron': '5A381F', 'bark': '5A381F', 'bark_light': '7A5230',
       'wood_top': 'DABE84', 'bark_dark': '412A1C', 'chop': '6C4528', 'riven': 'B58A5A', 'riven_dark': 'A67C52',
       'grain': 'AE8C54', 'pith': '91633B'}
FIXED_FROM_PROPOSAL = ['stone', 'stone_light', 'stone_dark', 'ash', 'ember', 'char', 'rope', 'rope_dark',
                       'hay', 'hay_mid', 'hay_light', 'hay_dark', 'straw', 'leaf_dry']
FIXED = {'soot': '38302C', 'red': 'B65F38', 'teal': '477F7C',          # game-table counters as before
         'flag': '7F3E36', 'flag_light': '9B5144', 'flag_mark': 'D3B980'}  # settlement banner as before
DWARF_ROLES = ['scar', 'skin', 'skin_shade', 'nose', 'blush', 'mouth', 'hair', 'hair_mid', 'hair_shade', 'eye', 'glint',
               'tunic', 'tunic_dark', 'tunic_light', 'trousers', 'belt', 'belt_dark', 'brass', 'linen',
               'boot', 'boot_light', 'boot_dark', 'sole']
FLAMES = ['flame_out', 'flame_mid', 'flame_core']
GROUND = {'ground': 0}


def models(dwarf_parts, wildlife_parts, plant_parts):
    rows = [
        ('stool', 'furniture', 'hewn', dict(piece='log_chair', occlusion=GROUND)),
        ('split_slab_table', 'furniture', 'hewn', dict(piece='log_table', occlusion=GROUND)),
        # The flame stays the game's animated voxel flame; the bracket is a wooden peg,
        # and the stick runs down to the model base like the previous torch.
        ('wall_torch', 'furniture', 'oak', dict(piece='wooden_torch', part='torch_body', drop=FLAMES, offset=[0, 1, 0], occlusion={'wall': 0},
                                                extra=[['box', [-2, 2, 0, 3, 6, 10], 'wood_side'], ['box', [-1, 1, -1, 0, 7, 9], 'wood_side']])),
        ('campfire', 'furniture', 'oak', dict(piece='campfire', part='campfire_body', drop=FLAMES, occlusion=GROUND)),
        # Hay inside the sleeper's torso area stays flat and the bed stays 15 cells
        # high (test_furniture contact rules): one dry leaf drops onto the hay.
        ('notched_log_bed', 'furniture', 'oak', dict(piece='log_bed', occlusion=GROUND, extra=[
            ['air', [-8, 12, 12, 15, -8, 8]], ['air', [-16, -15, 15, 16, 1, 2]], ['paint', [-16, -15, 14, 15, 1, 2], 'leaf_dry']])),
        ('log_bench', 'furniture', 'hewn', dict(piece='bench', occlusion=GROUND)),
        ('game_table', 'furniture', 'hewn', dict(piece='board_game_table', occlusion=GROUND)),
        ('workbench', 'furniture', 'hewn', dict(piece='crude_workbench', occlusion=GROUND)),
        ('door_2', 'furniture', 'oak', dict(piece='door', part='leaf_left', occlusion=GROUND)),
        ('door_3', 'furniture', 'oak', dict(piece='log_door_3', part='leaf_left', occlusion=GROUND)),
        ('door_4_left', 'furniture', 'oak', dict(piece='log_door_4', part='leaf_left', occlusion=GROUND)),
        ('door_4_right', 'furniture', 'oak', dict(piece='log_door_4', part='leaf_right', occlusion=GROUND)),
        ('fence_post', 'furniture', 'oak', dict(piece='log_fence', part='post', occlusion=GROUND)),
        ('gate_post_left', 'furniture', 'oak', dict(piece='log_gate', part='post_left', source='fence_post', offset=[-16, 0, 0], occlusion=GROUND)),
        ('gate_post_right', 'furniture', 'oak', dict(piece='log_gate', part='post_right', source='fence_post', offset=[16, 0, 0], occlusion=GROUND)),
        ('gate_leaf', 'furniture', 'oak', dict(piece='log_gate', part='leaf_left')),
        ('fence_rails', 'furniture', 'oak', dict(piece='parts/log_fence_rails', part='rails')),
    ]
    rows += [(f'ladder_{h}', 'furniture', 'oak', dict(piece=f'crude_ladder_{h}', occlusion=GROUND)) for h in range(1, 5)]
    rows += [(f'bridge_{s}', 'furniture', 'oak', dict(piece=f'log_bridge_{s}')) for s in range(1, 6)]
    rows += [
        ('ladder_kit', 'furniture', 'oak', dict(piece='ladder_kit', occlusion=GROUND)),
        ('bridge_kit', 'furniture', 'oak', dict(piece='bridge_kit', occlusion=GROUND)),
        ('packed_crate', 'furniture', 'oak', dict(piece='packed_furniture', occlusion=GROUND)),
        ('hearth', 'furniture', 'oak', dict(piece='hearth', part='hearth_body', occlusion=GROUND)),
        ('settlement_flag', 'furniture', 'oak', dict(piece='settlement_flag', occlusion=GROUND)),
    ]
    # Every dwarf part keeps its production name (body/, hair/, beards/, eyebrows/, scars/).
    rows += [(name, 'dwarf', 'dwarf', dict(occlusion=GROUND) if name == 'body/foot' else {}) for name in dwarf_parts]
    # The floor sits where each part meets the ground: soles in their leg/foot frames.
    floor = {'rabbit/body': 0, 'deer/leg': -10, 'wolf/leg': -8, 'duck/foot': 0}
    rows += [(name, 'wildlife', name.split('/')[0], dict(occlusion={'ground': floor[name]}) if name in floor else {}) for name in wildlife_parts]
    # Plants: one palette per species and season ('blueberry/mature/spring' -> 'blueberry:spring').
    rows += [(name, 'plants', name.split('/')[0] + ':' + ('summer' if name.endswith('/fruit') else name.split('/')[-1]), dict(occlusion=GROUND)) for name in plant_parts]
    return rows


def main():
    with tempfile.TemporaryDirectory() as temp:
        reference = Path(temp) / 'reference.json'
        subprocess.run(['node', str(HERE / 'export.mjs'), str(reference)], check=True, cwd=HERE)
        ref = json.loads(reference.read_text())
    proposal = ref['palette']
    fixed = {k: proposal[k].lstrip('#') for k in FIXED_FROM_PROPOSAL} | FIXED
    dwarf_scar = json.loads((ROOT / 'data/art/voxel_dwarves.json').read_text(encoding='utf-8-sig'))['palette']['scar']
    wildlife = json.loads((ROOT / 'data/art/voxel_wildlife.json').read_text(encoding='utf-8-sig'))['palette']
    species = {name.split('/')[0] for name in ref['wildlife']}
    palettes = {f: {k.split(':', 1)[1]: v.lstrip('#') for k, v in wildlife.items() if k.startswith(f + ':')} for f in species}
    flora = json.loads((ROOT / 'data/art/voxel_plants.json').read_text(encoding='utf-8-sig'))
    for name in {n.split('/')[0] for n in ref['plants']}:
        p = flora[name]
        for season in ('spring', 'summer', 'autumn', 'winter'):
            leaves = p.get(season, p['summer'])
            palettes[f'{name}:{season}'] = {'bark': p['bark'], 'leaf0': leaves[0], 'leaf1': leaves[1], 'leaf2': leaves[2],
                                            'blossom': p['blossom'], 'blossom_centre': 'CEAC62',
                                            'fruit0': p['fruit'][0], 'fruit1': p['fruit'][1], 'fruit2': p['fruit'][2]}
    # Work tools keep the existing tool materials (iron, steel, haft wood, leather wraps).
    dwarf_palette = json.loads((ROOT / 'data/art/voxel_dwarves.json').read_text(encoding='utf-8-sig'))['palette']
    tools = {k: dwarf_palette[k].lstrip('#') for k in ('wood', 'grain', 'tool_leather', 'iron', 'iron_dark', 'steel')}
    palettes |= {'hewn': HEWN | fixed, 'oak': OAK | fixed,
                'dwarf': {k: proposal[k].lstrip('#') for k in DWARF_ROLES if k != 'scar'} | {'scar': dwarf_scar.lstrip('#')} | tools}
    out = {}
    for name, group, palette, extra in models(list(ref['dwarf']), list(ref['wildlife']), list(ref['plants'])):
        source = extra.pop('source', name)
        out[name] = dict(group=group, palette=palette, **extra, ops=ref[group][source]['ops'])
        used = {op[2] for op in _flat(out[name]['ops'] + out[name].get('extra', [])) if len(op) > 2 and op[2] is not None}
        missing = sorted(used - set(palettes[palette]) - set(out[name].get('drop', [])))
        if missing: raise SystemExit(f'{name}: no {palette} color for {missing}')
    description = ('Hearthblock art (doc 256): cozy square chibi solids. proposal.mjs holds the approved proposal models; '
                   'tier1.mjs the Tier 1 Axe-Hewn furniture (tools/hearthblock/art; regenerate with write_data.py). '
                   'Cells use [x0,x1) ranges on the native 1:16 grid. cutbox clips XZ edges, cutbox_x clips YZ, cutbox_z '
                   'clips XY, paint recolors existing cells, air carves, mirror_x adds a sub-log and its mirror across X=0. '
                   'Wood roles map to the existing hand_hewn_timber / oak_log source palettes so every wood variant recolors.')
    lines = ['{', '  "description": ' + json.dumps(description) + ',', '  "palettes": ' + json.dumps(palettes) + ',', '  "models": {']
    for i, (name, model) in enumerate(out.items()):
        head = {k: v for k, v in model.items() if k != 'ops'}
        lines.append('    ' + json.dumps(name) + ': {' + json.dumps(head)[1:-1] + ', "ops": [')
        lines.append(',\n'.join('      ' + json.dumps(op, separators=(',', ':')) for op in model['ops']))
        lines.append('    ]}' + (',' if i < len(out) - 1 else ''))
    lines += ['  }', '}']
    OUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    json.loads(OUT.read_text(encoding='utf-8'))
    print('wrote', OUT.relative_to(ROOT), len(out), 'models')


def _flat(ops):
    for op in ops:
        if op[0] == 'mirror_x': yield from _flat(op[1])
        else: yield op


if __name__ == '__main__':
    main()

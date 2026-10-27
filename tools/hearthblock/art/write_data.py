"""Rebuild tools/art_data/voxel_hearthblock.json from the Hearthblock authoring modules.

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
OUT = ROOT / 'tools/art_data/voxel_hearthblock.json'

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
# UI icons (icons.mjs, doc 259) bake one skin and one hair tint; the game tints dwarves at runtime.
ICON_TINTS = {'skin': 'pale', 'hair': 'ginger'}
SKIN_ROLES = ['skin', 'skin_shade', 'nose', 'blush', 'mouth']
HAIR_ROLES = ['hair', 'hair_mid', 'hair_shade']
# The Events arrival icons (doc 23) replay each species' head in its own colours, as <species>_<role>.
ICON_SPECIES = {'rabbit': ['fur', 'cream', 'nose', 'eye', 'glint', 'ear'],
                'deer': ['coat', 'back', 'cream', 'nose', 'pupil', 'eye', 'ear', 'antler'],
                'wolf': ['fur', 'light', 'cream', 'nose', 'eye', 'glint', 'shade', 'ear'],
                'duck': ['male_crown', 'male_bill', 'ring', 'eye']}
ICON_EXTRA = {'arrow': '5E9B47', 'arrow_light': '86BF63', 'arrow_dark': '3F6E31',      # placement green
              'burlap': 'B0905F', 'burlap_dark': '8A6D45', 'zone_line': 'F0E2BE',     # storage ground
              'brass_light': 'F2CF7A',
              'glass': 'BCD3CF', 'glass_light': 'E4F1EC',
              'potion': 'DD963F', 'potion_light': 'F2C46B', 'potion_dark': 'A6632A',
              'earth': '8B6243', 'earth_dark': '6A4831', 'grass': '6F9A4C', 'grass_light': '8FB862',
              'xray': '6FCBDB', 'xray_light': 'B4EBF2',                                # x-ray cyan, as the in-game guide
              # Orders and world markers: the in-game oak, blueberry bush and reed colours
              'leafy_dark': '475E36', 'leafy': '596D3D', 'leafy_light': '7C8B50',
              'bush_dark': '4D704A', 'bush': '5A7B50', 'bush_light': '6C8957',
              'berry_blue': '536B8E', 'berry_blue_light': '6A81A3', 'berry_blue_dark': '435C7F', 'berry_red': 'AD4B40',
              'stalk': '617D4A', 'stalk_light': '789052', 'stalk_dry': 'B09B64',
              'parchment_edge': 'B8A47E',
              # Zones and Construction: tilled ridges, the cyan construction plan, and planks
              'earth_light': 'A07452', 'plan': '4FBFEA', 'plan_light': '9ADDF5',
              'plank': 'C8955A', 'plank_riven': 'B58A5A', 'plank_grain': 'A67C52', 'plank_seam': '5C3F27',
              # Professions: ore glints and turnips
              'ore_copper': 'C0703A', 'ore_gold': 'E0B84C', 'turnip': 'E9E1CF', 'turnip_top': '9B5A8C',
              # Dwarf concerns: the food badge's lit apple
              'apple_light': 'E2634B'}


def models(dwarf_parts, wildlife_parts, icons, sky):
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
    # Icons keep their render turn (icons.mjs options) for the icon renderer.
    rows += [(name, 'icon', 'icon', {k: v for k, v in icon.items() if k == 'yaw'}) for name, icon in icons.items()]
    # The Sky Dial's pieces (sky.mjs) keep their framing, light and outline for the renderer.
    rows += [(name, 'sky', 'sky', {k: v for k, v in piece.items() if k in ('framing', 'unshaded', 'outline')}) for name, piece in sky.items()]
    return rows


def _tint(value, tint):
    """Multiply an authored colour by a runtime tint, as the game does for dwarves."""
    a, b = value.lstrip('#'), tint.lstrip('#')
    return ''.join(f'{round(int(a[i:i+2], 16) * int(b[i:i+2], 16) / 255):02X}' for i in (0, 2, 4))


def main():
    with tempfile.TemporaryDirectory() as temp:
        reference = Path(temp) / 'reference.json'
        subprocess.run(['node', str(HERE / 'export.mjs'), str(reference)], check=True, cwd=HERE)
        ref = json.loads(reference.read_text())
    proposal = ref['palette']
    fixed = {k: proposal[k].lstrip('#') for k in FIXED_FROM_PROPOSAL} | FIXED
    dwarf_scar = json.loads((ROOT / 'tools/art_data/voxel_dwarves.json').read_text(encoding='utf-8-sig'))['palette']['scar']
    wildlife = json.loads((ROOT / 'tools/art_data/voxel_wildlife.json').read_text(encoding='utf-8-sig'))['palette']
    species = sorted({name.split('/')[0] for name in ref['wildlife']})
    palettes = {f: {k.split(':', 1)[1]: v.lstrip('#') for k, v in wildlife.items() if k.startswith(f + ':')} for f in species}
    # Work tools keep the existing tool materials (iron, steel, haft wood, leather wraps).
    dwarf_palette = json.loads((ROOT / 'tools/art_data/voxel_dwarves.json').read_text(encoding='utf-8-sig'))['palette']
    tools = {k: dwarf_palette[k].lstrip('#') for k in ('wood', 'grain', 'tool_leather', 'iron', 'iron_dark', 'steel')}
    palettes |= {'hewn': HEWN | fixed, 'oak': OAK | fixed,
                'dwarf': {k: proposal[k].lstrip('#') for k in DWARF_ROLES if k != 'scar'} | {'scar': dwarf_scar.lstrip('#')} | tools}
    skin, hair = ref['tints']['skin'][ICON_TINTS['skin']], ref['tints']['hair'][ICON_TINTS['hair']]
    palettes['icon'] = ({k: v.lstrip('#') for k, v in proposal.items()} | tools | HEWN | fixed
                        | {r: _tint(proposal[r], skin) for r in SKIN_ROLES}
                        | {r: _tint(proposal[r], hair) for r in HAIR_ROLES} | ICON_EXTRA
                        # a second dwarf for the Dwarves icon: black hair, medium skin
                        | {r.replace('hair', 'hair2', 1): _tint(proposal[r], ref['tints']['hair']['black']) for r in HAIR_ROLES}
                        | {r + '2': _tint(proposal[r], ref['tints']['skin']['medium']) for r in SKIN_ROLES}
                        | {f'{s}_{r}': wildlife[f'{s}:{r}'].lstrip('#') for s, roles in ICON_SPECIES.items() for r in roles})
    palettes['sky'] = {k: v.lstrip('#') for k, v in proposal.items()} | {k: v.lstrip('#') for k, v in ref['sky_palette'].items()}
    out = {}
    for name, group, palette, extra in models(list(ref['dwarf']), list(ref['wildlife']), ref['icon'], ref['sky']):
        source = extra.pop('source', name)
        out[name] = dict(group=group, palette=palette, **extra, ops=ref[group][source]['ops'])
        used = {op[2] for op in _flat(out[name]['ops'] + out[name].get('extra', [])) if len(op) > 2 and op[2] is not None}
        missing = sorted(used - set(palettes[palette]) - set(out[name].get('drop', [])))
        if missing: raise SystemExit(f'{name}: no {palette} color for {missing}')
    description = ('Hearthblock art (doc 256): cozy square chibi solids. proposal.mjs holds the approved proposal models; '
                   'tier1.mjs the Tier 1 Axe-Hewn furniture; icons.mjs the UI icon models (doc 259); sky.mjs the Sky Dial (doc 23) '
                   '(tools/hearthblock/art; regenerate with write_data.py). '
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
    OUT.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    json.loads(OUT.read_text(encoding='utf-8'))
    print('wrote', OUT.relative_to(ROOT), len(out), 'models')


def _flat(ops):
    for op in ops:
        if op[0] == 'mirror_x': yield from _flat(op[1])
        else: yield op


if __name__ == '__main__':
    main()

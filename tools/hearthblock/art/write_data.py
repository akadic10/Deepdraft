"""Rebuild tools/art_data/voxel_hearthblock.json from the Hearthblock authoring modules.

    python3 tools/hearthblock/art/write_data.py      (needs node on PATH)

proposal.mjs holds the approved proposal models verbatim; tier1.mjs adds the
Tier 1 · Axe-Hewn pieces and tier2.mjs the Carpenter's plank pieces. export.mjs records each model's operations, and this
script adds the in-game palettes and pilot edits (dropped flame cells, offsets,
clips between dwarf layers, extra operations). tools/voxel_assets/hearthblock.py
replays the result. See docs/60_asset_creation/61_voxel_art_guide.md and 64_hearthblock_art_direction.md.
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
# The Development icons (doc 23) keep the Sky Dial's storm cloud, rain, snow and pine colours.
ICON_SKY = ['storm', 'storm_shade', 'rain', 'snow', 'snow_shade', 'pine', 'pine_light', 'pine_dark']
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
              # Zones and Construction: tilled ridges and the cyan construction plan
              'earth_light': 'A07452', 'plan': '4FBFEA', 'plan_light': '9ADDF5',
              # Professions: ore glints and turnips
              'ore_copper': 'C0703A', 'ore_gold': 'E0B84C', 'turnip': 'E9E1CF', 'turnip_top': '9B5A8C',
              # Dwarf concerns: the food badge's lit apple
              'apple_light': 'E2634B',
              # Development: the world's water (data/world_gen/water.json), lit and deepened as
              # WaterMeshBuilder shades it, and the cave explorer's highlight, a little softer
              'water': '58AFC4', 'water_light': '8ACFDD', 'water_dark': '3F8799', 'foam': 'C6EDF0',
              'cave_line': '45DCD2'}
# Fishing (doc 289): the peeled rod, its line and float, and the chunky perch, for the dwarf
# tools and the icons that show them.
FISHING = {'rod_wood': 'D7BC8C', 'rod_knot': '9E7C50', 'rod_bark': '5E3F29', 'rod_bark_light': '7E5838',
           'rod_line': 'E9DFC6', 'float_wood': 'E2CA97', 'float_red': 'B6452E', 'float_dark': '7B2E20',
           'fish_eye': '1E1814', 'perch_back': '55632A', 'perch_side': 'A7A646', 'perch_belly': 'EFE8C6',
           'perch_bar': '343D1D', 'perch_fin': 'D9572E', 'perch_dorsal': '7B8444',
           # step 2: the river's trout, the tarn's char and the spring cave's fish
           'trout_back': '6C5C37', 'trout_side': 'BFA261', 'trout_belly': 'F0EBDA', 'trout_spot': '2B241E',
           'trout_red': 'D1432C', 'trout_fin': '98865C', 'trout_fin_light': 'C9B78A',
           'char_back': '2C463B', 'char_side': '6E8669', 'char_belly': 'E2642B', 'char_spot': 'F1E2C3',
           'char_fin': 'DF7036', 'char_edge': 'F8F4EA', 'char_dorsal': '3C5649',
           'cavefish_body': 'F1DED7', 'cavefish_shade': 'DCC1B8', 'cavefish_belly': 'F8ECE7',
           'cavefish_gill': 'E29997', 'cavefish_fin': 'E4D0CA', 'cavefish_socket': 'E3C6BE', 'cavefish_line': 'E7CFC7'}
# The drying rack's dried fish (doc 289, step 3): coppery, redder than any wood swatch, so they
# never recolour with the rack's wood.
DRYING = {'dry_skin': '8A4A2A', 'dry_back': '5A321F', 'dry_flesh': 'C27448', 'dry_tail': '6E3E24', 'dry_eye': '24170F'}
# Worked stone (doc 301, the owner's pick, 2026-11-10): stone furniture has a dark weathered skin
# and pale fresh stone where it was split or knocked, as a log has bark and a cut face. Greys,
# cooler than any wood swatch, so they never recolour with a wood. The mason's bench, the stone
# stool and the basic smelter use them, and so do the stone heads of the dwarves' hand tools
# (the starter tools on the ground carry the same colours in hearthblock_goods.STONE).
WORKED_STONE = {'stone_skin': '5D6166', 'stone_skin_top': '6C7075', 'stone_skin_dark': '45494D',
                'stone_fresh': '9EA3A6', 'stone_fresh_dark': '85898C', 'stone_cleft': '2D3033'}
# The basic smelter's charge (doc 297): the copper, glowing in the pot and cast in the mould.
SMELTER = {'molten': 'F08A2E', 'molten_light': 'FFC861', 'copper': 'C0703A', 'copper_light': 'E09A5C', 'copper_dark': '8A4A26'}
# Trade hats (doc 304): felt in four of the tunics' own dyes (DwarfAssets.CLOTHING), the Miner's
# tallow candle and its wick, the Ranger's pheasant feather and the Blacksmith's scorch. The
# Stonemason's cap takes the worked stone above, and the candle's flame the proposal's flame.
HATS = {'ochre': 'B08B3A', 'ochre_dark': '86692B', 'ochre_light': 'C9A655',
        'moss': '6F8C3E', 'moss_dark': '536A2E', 'moss_light': '8CA851',
        'plum': '7B4F72', 'plum_dark': '5C3A55', 'plum_light': '98698E',
        'rust': 'A9563B', 'rust_dark': '84412C', 'rust_light': 'C47050',
        'tallow': 'E4D2A2', 'tallow_shade': 'BFA876', 'wick': '2A1F1B',
        'feather': 'B4532E', 'feather_dark': '6E2F1C', 'feather_tip': 'EFE3C2', 'quill': 'E9DFC6', 'soot': '38302C',
        # the Farmer's straw hat (doc 309): straw a step deeper than the bed's hay, which the midday sun
        # lifts to cream, and a band in the tunics' slate
        'straw': 'D9B452', 'straw_light': 'E3C366', 'straw_dark': 'A8842F', 'straw_weave': 'BC9638', 'band': '4E6B8F', 'band_dark': '3A516D'}
# The Farmer's copper hoe (doc 309) takes the copper bar's own colours, as the copper tool goods do.
HOE = {'copper': 'C0703A', 'copper_light': 'E09A5C', 'copper_dark': '8A4A26'}
# Grilling (doc 290): the peeled green stick and the roasted fish on it, for the dwarf tools.
GRILLING = {'stick_bark': '5E6238', 'stick_bark_light': '777A49', 'stick_wood': 'DDD3A3', 'stick_knot': 'A69E70',
            'stick_char': '3A2A20', 'grill_back': '5C3A22', 'grill_side': 'A9672F', 'grill_side_light': 'C6843F',
            'grill_belly': 'DAA65D', 'grill_bar': '6F4626', 'grill_fin': '4B2D1B', 'grill_char': '2E211A', 'grill_eye': 'E9E2CD'}


def models(dwarf_parts, wildlife_parts, icons, sky):
    rows = [
        # The proposal's stool: stored logs replay it on its side (hearthblock_goods.log_roles).
        ('stool', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # The log stool in the game: the same stool with its bark in ridges (doc 301).
        ('log_stool', 'furniture', 'hewn', dict(piece='log_stool', occlusion=GROUND)),
        # The Tier 1 log dining table: kept, uninstalled since the Carpenter's plank table took its place
        # (2026-11-13).
        ('split_slab_table', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # Tier 2, the Carpenter's plank pieces (tier2.mjs; the owner's picks, 2026-11-13): boards on two
        # plank ends, and a board seat on two plank ends. They keep the furniture keys and model paths of
        # the pieces they replace, so a colony's own table and benches change look.
        ('plank_table', 'furniture', 'hewn', dict(piece='dining_table', occlusion=GROUND)),
        ('plank_bench', 'furniture', 'hewn', dict(piece='bench', occlusion=GROUND)),
        # Three more the same day ("Tool rack, A / Pallet, A / Game Board, A"): the dining table with the
        # game marked on it, the plain pallet, and the peg rail, hung on a wall with its back at Z-8.
        ('plank_game_table', 'furniture', 'hewn', dict(piece='board_game_table', occlusion=GROUND)),
        ('plank_pallet', 'furniture', 'hewn', dict(piece='finished_goods_pallet', occlusion=GROUND)),
        ('plank_tool_rack', 'furniture', 'hewn', dict(piece='tool_rack', occlusion={'wall': -8})),
        # And two more ("Crate, A / Food shelf, A"): the open post-and-board bin with nothing through
        # its middle, and two shelves between two plank ends.
        ('plank_crate', 'furniture', 'hewn', dict(piece='raw_materials_crate', occlusion=GROUND)),
        ('plank_food_shelf', 'furniture', 'hewn', dict(piece='food_shelf', occlusion=GROUND)),
        # The flame stays the game's animated voxel flame; the bracket is a wooden peg,
        # and the stick runs down to the model base like the previous torch.
        ('wall_torch', 'furniture', 'oak', dict(piece='torch', part='torch_body', drop=FLAMES, offset=[0, 1, 0], occlusion={'wall': 0},
                                                extra=[['box', [-2, 2, 0, 3, 6, 10], 'wood_side'], ['box', [-1, 1, -1, 0, 7, 9], 'wood_side']])),
        # Nightly fires (doc 279): the ring holds no wood; the night's log is the real good a
        # worker sets on the ash. The ring is tier1.mjs's five great stones in worked stone (the
        # owner's pick, 2026-11-11), so it takes the hewn palette, which holds those colours;
        # nothing recolours a campfire. proposal.mjs keeps the proposal's eight-stone ring.
        ('campfire', 'furniture', 'hewn', dict(piece='campfire', part='campfire_body', occlusion=GROUND)),
        # Hay inside the sleeper's torso area stays flat and the bed stays 15 cells
        # high (test_furniture contact rules): one dry leaf drops onto the hay.
        ('notched_log_bed', 'furniture', 'oak', dict(piece='log_bed', occlusion=GROUND, extra=[
            ['air', [-8, 12, 12, 15, -8, 8]], ['air', [-16, -15, 15, 16, 1, 2]], ['paint', [-16, -15, 14, 15, 1, 2], 'leaf_dry']])),
        # The Tier 1 sitting log: kept, uninstalled since the plank bench took its place (2026-11-13).
        ('log_bench', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # The Tier 1 board-game table (the log table's stumps under two riven halves): kept, uninstalled
        # since the plank game table took its place (2026-11-13).
        ('game_table', 'furniture', 'hewn', dict(occlusion=GROUND)),
        ('workbench', 'furniture', 'hewn', dict(piece='crude_workbench', occlusion=GROUND)),
        ('drying_rack', 'furniture', 'hewn', dict(piece='drying_rack', occlusion=GROUND)),
        # Its fish, shown only while a batch dries (doc 289): a part over the rack, as the fence rails.
        ('drying_rack_fish', 'furniture', 'hewn', dict(piece='parts/drying_rack_fish', part='fish')),
        # The careers' own workbenches (doc 293): the Carpenter's peeled log bench, the
        # Stonemason's split slab on two stumps.
        ('carpenter_bench', 'furniture', 'hewn', dict(piece='carpenter_bench', occlusion=GROUND)),
        ('mason_bench', 'furniture', 'hewn', dict(piece='mason_bench', occlusion=GROUND)),
        # The Stonemason's stone stool (doc 293, B): a Rough stone knocked square. Both are worked stone (doc 301).
        ('stone_stool', 'furniture', 'hewn', dict(piece='stone_stool', occlusion=GROUND)),
        # The Tier 1 tool rack (doc 294, B: a pegged log hung on a wall, its back at Z-8): kept,
        # uninstalled since the peg rail took its place (2026-11-13).
        ('tool_rack', 'furniture', 'hewn', dict(occlusion={'wall': -8})),
        # The Tier 1 raw materials crate (doc 294, A: a log crib on the floor, open on top): kept,
        # uninstalled since the open plank bin took its place (2026-11-13).
        ('raw_materials_crate', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # The Tier 1 finished goods pallet (doc 62, A: split halves across two log runners): kept,
        # uninstalled since the plain plank pallet took its place (2026-11-13).
        ('finished_goods_pallet', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # The Tier 1 food shelf (doc 299, A: a lean-to rack of bark posts, lashed rails and split
        # halves): kept, uninstalled since the plank shelf took its place (2026-11-13).
        ('food_shelf', 'furniture', 'hewn', dict(occlusion=GROUND)),
        # The Blacksmith's basic smelter (doc 297), its charge shown while copper melts and the bar
        # shown once it has set (doc 300).
        ('basic_smelter', 'furniture', 'hewn', dict(piece='basic_smelter', occlusion=GROUND)),
        ('basic_smelter_charge', 'furniture', 'hewn', dict(piece='parts/basic_smelter_charge', part='charge')),
        ('basic_smelter_bar', 'furniture', 'hewn', dict(piece='parts/basic_smelter_bar', part='bar')),
        # The Blacksmith's anvil stone (doc 310, the owner's pick B): one great stone, where copper tools are hammered.
        ('anvil_stone', 'furniture', 'hewn', dict(piece='anvil_stone', occlusion=GROUND)),
        ('door_2', 'furniture', 'oak', dict(piece='door_2', part='leaf_left', occlusion=GROUND)),
        ('door_3', 'furniture', 'oak', dict(piece='door_3', part='leaf_left', occlusion=GROUND)),
        ('door_4_left', 'furniture', 'oak', dict(piece='door_4', part='leaf_left', occlusion=GROUND)),
        ('door_4_right', 'furniture', 'oak', dict(piece='door_4', part='leaf_right', occlusion=GROUND)),
        # Peeled like built logs (doc 278), so they share the built logs' hand-hewn palette.
        ('fence_post', 'furniture', 'hewn', dict(piece='log_fence', part='post', occlusion=GROUND)),
        ('gate_post_left', 'furniture', 'hewn', dict(piece='log_gate', part='post_left', source='fence_post', offset=[-16, 0, 0], occlusion=GROUND)),
        ('gate_post_right', 'furniture', 'hewn', dict(piece='log_gate', part='post_right', source='fence_post', offset=[16, 0, 0], occlusion=GROUND)),
        ('gate_leaf', 'furniture', 'hewn', dict(piece='log_gate', part='leaf_left')),
        ('fence_rails', 'furniture', 'hewn', dict(piece='parts/log_fence_rails', part='rails')),
    ]
    rows += [(f'ladder_{h}', 'furniture', 'oak', dict(piece=f'crude_ladder_{h}', occlusion=GROUND)) for h in range(1, 5)]
    rows += [
        ('ladder_kit', 'furniture', 'oak', dict(piece='ladder_kit', occlusion=GROUND)),
        ('packed_crate', 'furniture', 'oak', dict(piece='packed_furniture', occlusion=GROUND)),
        # The hearth is worked stone since 2026-11-11 (a split boulder), so it takes the hewn palette too.
        ('hearth', 'furniture', 'hewn', dict(piece='hearth', part='hearth_body', occlusion=GROUND)),
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
    # The hand tools (doc 301) are stone bound with rope on wooden hafts: the haft's wood from the
    # dwarves' palette, the benches' worked stone for the heads. The tool icons draw the same stone
    # since 2026-11-11; other icons still draw iron and steel (a barrel's hoops, a needle, a shield),
    # so the icon palette keeps them, and leather.
    dwarf_palette = json.loads((ROOT / 'tools/art_data/voxel_dwarves.json').read_text(encoding='utf-8-sig'))['palette']
    haft = {k: dwarf_palette[k].lstrip('#') for k in ('wood', 'grain')}
    icon_iron = {k: dwarf_palette[k].lstrip('#') for k in ('tool_leather', 'iron', 'iron_dark', 'steel')}
    tool_stone = {k: v for k, v in WORKED_STONE.items() if k != 'stone_cleft'}
    palettes |= {'hewn': HEWN | fixed | DRYING | WORKED_STONE | SMELTER, 'oak': OAK | fixed,
                'dwarf': {k: proposal[k].lstrip('#') for k in DWARF_ROLES if k != 'scar'} | {'scar': dwarf_scar.lstrip('#')} | haft
                         | {'rope': fixed['rope'], 'rope_dark': fixed['rope_dark']} | FISHING | GRILLING | tool_stone
                         | HATS | HOE | {k: proposal[k].lstrip('#') for k in FLAMES}}
    skin, hair = ref['tints']['skin'][ICON_TINTS['skin']], ref['tints']['hair'][ICON_TINTS['hair']]
    palettes['icon'] = ({k: v.lstrip('#') for k, v in proposal.items()} | haft | icon_iron | tool_stone | HEWN | fixed
                        | {r: _tint(proposal[r], skin) for r in SKIN_ROLES}
                        | {r: _tint(proposal[r], hair) for r in HAIR_ROLES} | ICON_EXTRA
                        # a second dwarf for the Dwarves icon: black hair, medium skin
                        | {r.replace('hair', 'hair2', 1): _tint(proposal[r], ref['tints']['hair']['black']) for r in HAIR_ROLES}
                        | {r + '2': _tint(proposal[r], ref['tints']['skin']['medium']) for r in SKIN_ROLES}
                        # an elder for Development's Dwarf tools: white hair, the medium skin above
                        | {r.replace('hair', 'hair3', 1): _tint(proposal[r], ref['tints']['hair']['white']) for r in HAIR_ROLES}
                        | {f'{s}_{r}': wildlife[f'{s}:{r}'].lstrip('#') for s, roles in ICON_SPECIES.items() for r in roles}
                        | {r: ref['sky_palette'][r].lstrip('#') for r in ICON_SKY} | FISHING)
    palettes['sky'] = {k: v.lstrip('#') for k, v in proposal.items()} | {k: v.lstrip('#') for k, v in ref['sky_palette'].items()}
    out = {}
    for name, group, palette, extra in models(list(ref['dwarf']), list(ref['wildlife']), ref['icon'], ref['sky']):
        source = extra.pop('source', name)
        out[name] = dict(group=group, palette=palette, **extra, ops=ref[group][source]['ops'])
        used = {op[2] for op in _flat(out[name]['ops'] + out[name].get('extra', [])) if len(op) > 2 and op[2] is not None}
        missing = sorted(used - set(palettes[palette]) - set(out[name].get('drop', [])))
        if missing: raise SystemExit(f'{name}: no {palette} color for {missing}')
    description = ('Hearthblock art (doc 256): cozy square chibi solids. proposal.mjs holds the approved proposal models; '
                   'tier1.mjs the Tier 1 Axe-Hewn furniture; tier2.mjs the Carpenter\'s plank furniture; icons.mjs the UI icon models (doc 259); sky.mjs the Sky Dial (doc 23) '
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

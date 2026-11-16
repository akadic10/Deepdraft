"""Hearthblock art (doc 256): production routes, wood swatches, occlusion and contacts."""
import unittest
from common import read_json
from furniture import assets as furniture_assets
import hearthblock

WOOD_ROLES = {'bark_dark', 'bark', 'bark_light', 'chop', 'wood_top', 'riven', 'riven_dark', 'grain', 'pith',
              'wood_dark', 'wood_side', 'iron'}


class HearthblockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = read_json(hearthblock.DATA)
        cls.furniture = {path: parts for path, parts, _ in furniture_assets()}

    def cells(self, piece, part='main'):
        return self.furniture['assets/models/furniture/' + piece + '.glb'][part].voxels.cells

    def test_every_furniture_model_is_installed_with_occlusion(self):
        replayed_only = []
        for name, model in self.data['models'].items():
            if model['group'] != 'furniture': continue
            if 'piece' not in model:
                replayed_only.append(name)
                continue
            part = self.furniture['assets/models/furniture/' + model['piece'] + '.glb'][model.get('part', 'main')]
            self.assertEqual(part.voxels.cells, hearthblock.model(name).cells, name)
            self.assertTrue(part.occlusion and len(part.occlusion['curve']) == 4, name)
        # The proposal's stool builds no piece of its own: stored logs replay it (hearthblock_goods.log_roles),
        # and the game's log stool is `log_stool`, the same stool with its bark in ridges (doc 301).
        # The Tier 1 log dining table, sitting log, board-game table, tool rack, raw materials crate,
        # finished goods pallet and food shelf are kept designs, uninstalled since the Carpenter's
        # plank pieces took their places (tier2.mjs, 2026-11-13).
        self.assertEqual(replayed_only, ['stool', 'split_slab_table', 'log_bench', 'game_table', 'tool_rack', 'raw_materials_crate',
                                         'finished_goods_pallet', 'food_shelf'])

    def test_wood_roles_are_existing_source_swatches(self):
        sources = read_json('data/materials/craft_materials.json')['source_palettes']
        for palette, source in (('hewn', 'hand_hewn_timber'), ('oak', 'oak_log')):
            swatches = {h.upper() for h in sources[source]['colors'].values()}
            for role, color in self.data['palettes'][palette].items():
                if role in WOOD_ROLES: self.assertIn(color.upper(), swatches, palette + ':' + role)
                else: self.assertNotIn(color.upper(), swatches, palette + ':' + role + ' must stay fixed')

    def test_shaded_wood_recolors_exactly(self):
        """Mirror CraftMaterials._recolor on 8-bit colors and half-float UV2 shades."""
        import math, struct
        from common import linear
        from voxel_glb import greedy_mesh_from_voxels
        sources = read_json('data/materials/craft_materials.json')['source_palettes']
        half = lambda v: struct.unpack('<e', struct.pack('<e', v))[0]
        for name, model in self.data['models'].items():
            if model['group'] != 'furniture': continue
            source = sources[{'hewn': 'hand_hewn_timber', 'oak': 'oak_log'}[model['palette']]]['colors']
            swatches = {role: linear(h) for role, h in source.items()}
            used = {h.upper(): linear(h) for h in self.data['palettes'][model['palette']].values()}
            mesh = greedy_mesh_from_voxels(hearthblock.model(name), (), hearthblock.occlusion(name))
            for color, shade in zip(mesh[2], mesh[4]):
                base = tuple(c / shade for c in color[:3])
                authored = min(used, key=lambda h: max(abs(a - b) for a, b in zip(used[h], base)))
                want = next((r for r, h in source.items() if h.upper() == authored), None)
                stored = tuple(math.floor(c * 255) / 255 for c in color[:3]); s = half(shade)
                got = None
                if s < .999:
                    best = 1.5 / 255
                    for role, swatch in swatches.items():
                        error = max(abs(a - b * s) for a, b in zip(stored, swatch))
                        if error < best: best, got = error, role
                else:
                    for role, swatch in swatches.items():
                        packed = tuple(math.floor(v * 255) / 255 for v in swatch)
                        if max(abs(a - b) for a, b in zip(stored, swatch)) < 1e-4 or max(abs(a - b) for a, b in zip(stored, packed)) < 1e-4:
                            got = role; break
                self.assertEqual(got, want, f'{name}: {authored} at shade {shade}')

    def test_drying_rack_hangs_the_batch_it_dries(self):
        # The hanging fish are one model, shown whole while a batch dries. It drew three fish for a
        # batch of two (owner, 2026-11-10), so it must draw as many as the recipe hangs and gives.
        recipe = next(r for r in read_json('data/recipes/recipes.json')['recipes'] if r['id'] == 'base:recipe:dried_fish')
        left = set(self.cells('parts/drying_rack_fish', 'fish'))
        fish = 0
        while left:
            stack = [left.pop()]
            fish += 1
            while stack:                                  # each fish, its cord and its loop touch at least by a corner
                x, y, z = stack.pop()
                for q in [(x + i, y + j, z + k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1)]:
                    if q in left:
                        left.remove(q)
                        stack.append(q)
        self.assertEqual(fish, recipe['ingredient_count'], 'the rack shows as many fish as a Ranger hangs')
        self.assertEqual(recipe['output_count'], recipe['ingredient_count'], 'and as many come down dried')

    def test_tables_keep_seated_legs_clear(self):
        for piece in ('dining_table', 'board_game_table'):
            boxes = read_json('data/furniture/' + piece + '.json')['seating_obstacles']
            for x, y, z in self.cells(piece):
                lo = ((x + 24) / 16, y / 16, (z + 24) / 16); hi = tuple(v + 1 / 16 for v in lo)
                self.assertTrue(any(all(b['min'][i] <= lo[i] and hi[i] <= b['max'][i] for i in range(3)) for b in boxes),
                                piece + str((x, y, z)))

    def test_bench_seat_contacts(self):
        cells = self.cells('bench')
        self.assertEqual(tuple(max(p[i] for p in cells) + 1 - min(p[i] for p in cells) for i in range(3)), (32, 16, 16))
        self.assertEqual(min(p[1] for p in cells), 0)
        self.assertTrue(all((x, 15, z) in cells for x in range(-6, 6) for z in range(-3, 3)), 'flat torso support at one block')
        # What a sitting dwarf needs of the plank bench (the owner's pick, 2026-11-13): the seat is
        # whole and level from end to end and edge to edge, so the torso and both resting hands lie
        # on wood wherever the pose puts them, and it stands on the ground under both halves of
        # the seat, so it bears a dwarf sat off centre. (The sitting log it replaced was pinned
        # here as solid from the ground to the seat; that described a log, not a seat.)
        self.assertTrue(all((x, 15, z) in cells for x in range(-16, 16) for z in range(-8, 8)), 'the seat is whole and level')
        self.assertFalse(any(p[1] > 15 for p in cells), 'nothing stands proud of the seat')
        feet = {x for x, y, z in cells if y == 0}
        self.assertTrue(any(x < -8 for x in feet) and any(x >= 8 for x in feet), 'feet on the ground under both ends')

    def test_tool_rack_hangs_tools_from_its_hooks(self):
        # What the rack's use rests on (data/furniture/tool_rack.json): it hangs flat on its wall, its
        # underside 33 cells up (FurnitureArtTest), inside its 3 x 1 footprint and three blocks of
        # height; under each storage anchor stands a peg whose top is the hook, and in front of the
        # face a hung tool rests against there is nothing but those pegs, so no tool hangs in wood.
        definition = read_json('data/furniture/tool_rack.json')
        cells = self.cells('tool_rack')
        self.assertEqual(min(p[1] for p in cells), 33)
        self.assertEqual(min(p[2] for p in cells), -8, 'its back is on the wall')
        self.assertTrue(all(-24 <= x < 24 and y < 48 and -8 <= z < 8 for x, y, z in cells))
        hooks = [(round(a[0] * 16) - 24, round(a[1] * 16), round(a[2] * 16) - 8) for a in definition['storage']['anchors']]
        self.assertEqual(hooks, [(-16, 39, -4), (0, 39, -4), (16, 39, -4)])
        for x, y, z in hooks:
            peg = {p for p in cells if x - 1 <= p[0] < x + 1 and p[2] >= z}
            self.assertEqual(max(p[1] for p in peg) + 1, y, 'a peg under the hook, its top at the hook')
        self.assertEqual({p for p in cells if p[2] >= -4}, {p for p in cells if p[2] >= -4 and any(x - 1 <= p[0] < x + 1 for x, _, _ in hooks)},
                         'only the three pegs stand in front of the face tools hang against')

    def test_pallet_deck_is_level_under_its_four_quarters(self):
        # What the pallet's use rests on (data/furniture/finished_goods_pallet.json): a deck level at
        # seven cells, the height of its storage anchors and of its collision box, with wood under
        # the middle of each of its four quarters, where a stored good is stood, and nothing above.
        definition = read_json('data/furniture/finished_goods_pallet.json')
        cells = self.cells('finished_goods_pallet')
        self.assertEqual([(min(p[i] for p in cells), max(p[i] for p in cells) + 1) for i in range(3)], [(-16, 16), (0, 7), (-16, 16)])
        self.assertEqual(definition['collision_regions'][0]['max'][1] * 16, 7)
        anchors = [(round(a[0] * 16) - 16, round(a[1] * 16), round(a[2] * 16) - 16) for a in definition['storage']['anchors']]
        self.assertEqual(sorted(anchors), [(-8, 7, -8), (-8, 7, 8), (8, 7, -8), (8, 7, 8)])
        for x, y, z in anchors:
            # A quarter's middle lies over the two-cell gap between two deck boards, so a good stood
            # there rests on both: wood on either side of the gap, and four fifths of the ten cells
            # square under it.
            under = [(x + i, y - 1, z + k) in cells for i in range(-5, 5) for k in range(-5, 5)]
            self.assertGreaterEqual(sum(under), 80, (x, z))
            self.assertTrue(all((x + i, y - 1, z + k) in cells for i in (-3, 2) for k in range(-5, 5)), 'a deck board on each side of the gap')

    def test_crate_keeps_its_four_goods_in_the_open(self):
        # What the crate's use rests on (data/furniture/raw_materials_crate.json): it stands inside
        # its 2 x 2 footprint and its collision box's height; its four quarters' goods stand on the
        # ground at the storage anchors, two mined goods (12 cells square) side by side each way, so
        # nothing of the crate stands in the 24 cells square they share: no floor, no lid and nothing
        # through the middle (the owner, 2026-11-13). And a good shows: from above, and from the
        # side through the gap each wall keeps between its two boards.
        definition = read_json('data/furniture/raw_materials_crate.json')
        cells = self.cells('raw_materials_crate')
        high = round(definition['collision_regions'][0]['max'][1] * 16)
        self.assertEqual([(min(p[i] for p in cells), max(p[i] for p in cells) + 1) for i in range(3)], [(-16, 16), (0, high), (-16, 16)])
        anchors = sorted((round(a[0] * 16) - 16, round(a[1] * 16), round(a[2] * 16) - 16) for a in definition['storage']['anchors'])
        self.assertEqual(anchors, [(-6, 0, -6), (-6, 0, 6), (6, 0, -6), (6, 0, 6)])
        self.assertFalse(any(-12 <= x < 12 and -12 <= z < 12 for x, y, z in cells), 'the goods\' space is empty from the ground up')
        for wall in ((0, 13), (0, -14), (13, 0), (-14, 0)):                      # the middle of each side
            column = {y for x, y, z in cells if (x, z) == wall}
            self.assertEqual(column, set(range(0, 5)) | set(range(7, 12)), 'two boards with a gap between them')

    def test_food_shelf_decks_carry_six_crates_in_two_rows(self):
        # What the shelf's use rests on (data/furniture/food_shelf.json): it stands inside its 3 x 1
        # footprint and collision box; a crate (12 cells wide, 10 deep, 10 high) stands at each of
        # its six storage anchors on a whole deck, with nothing of the shelf in it; the upper deck
        # is set back, so the lower row shows in front of it from above; and the lower row has room
        # over it up to the upper deck's underside.
        definition = read_json('data/furniture/food_shelf.json')
        cells = self.cells('food_shelf')
        high = round(definition['collision_regions'][0]['max'][1] * 16)
        self.assertTrue(all(-24 <= x < 24 and 0 <= y < high and -8 <= z < 8 for x, y, z in cells))
        places = [(round(a[0] * 16) - 24, round(a[1] * 16), round(a[2] * 16) - 8) for a in definition['storage']['anchors']]
        self.assertEqual(places, [(-15, 31, -3), (0, 31, -3), (15, 31, -3), (-15, 12, 3), (0, 12, 3), (15, 12, 3)])
        for x, y, z in places:
            self.assertTrue(all((x + i, y - 1, z + k) in cells for i in range(-6, 6) for k in range(-5, 5)), 'a whole deck under the crate')
            self.assertFalse(any((x + i, y + j, z + k) in cells for i in range(-6, 6) for j in range(10) for k in range(-5, 5)), 'nothing in the crate\'s place')
        upper_front = max(p[2] for p in cells if p[1] == 30 and abs(p[0]) < 21) + 1   # between the plank ends
        lower_front = max(p[2] for p in cells if p[1] == 11 and abs(p[0]) < 21) + 1
        self.assertEqual((upper_front, lower_front), (2, 8), 'the upper deck is set back six cells: the lower row shows in front of it')
        over = [min((p[1] for p in cells if p[0] == x and p[2] == z and p[1] >= 12), default=high) for x in (-15, 0, 15) for z in range(-2, 8)]
        self.assertGreaterEqual(min(over), 27, 'room over the lower row up to the upper deck\'s underside')

    def test_dwarf_rig_anchors(self):
        hand = hearthblock.roles('body/hand')
        mitten = [p for p in hand if p[0] >= 14 and p[1] < 23 and p[2] < 6]   # palm block, without thumb and wrist
        self.assertEqual([(min(p[i] for p in mitten) + max(p[i] for p in mitten) + 1) / 2 for i in range(3)], [17, 20, 3],
                         'mitten centred on the DwarfWorkToolPose palm')
        self.assertEqual(min(p[1] for p in hearthblock.roles('body/foot')), 0)
        head = hearthblock.roles('body/head_adult')
        self.assertTrue(all((x, y, z - 1) in head and (x, y, z) not in head for x, y, z in hearthblock.roles('body/eyes')),
                        'eyes sit directly on the face, not inside it')


if __name__ == '__main__': unittest.main()

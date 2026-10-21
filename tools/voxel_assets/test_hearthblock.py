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
        for name, model in self.data['models'].items():
            if model['group'] != 'furniture': continue
            part = self.furniture['assets/models/furniture/' + model['piece'] + '.glb'][model.get('part', 'main')]
            self.assertEqual(part.voxels.cells, hearthblock.model(name).cells, name)
            self.assertTrue(part.occlusion and len(part.occlusion['curve']) == 4, name)

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

    def test_tables_keep_seated_legs_clear(self):
        for piece in ('log_table', 'board_game_table'):
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
        for x in (-10, 10):
            self.assertTrue(all((x, y, 0) in cells for y in range(16)), 'both feet connect ground to seat')
        self.assertFalse(any((0, y, 0) in cells for y in range(7)), 'air gap between the feet')

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

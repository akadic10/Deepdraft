"""Bench scale, seated contacts, connected solids, production palette and VOX."""
from pathlib import Path
import tempfile
import unittest
import log_bench
import hearthblock
from common import linear, read_json
from furniture import assets
from hand_hewn_timber import connected
from vox_source import read_models, grounded_cells


class LogBenchTests(unittest.TestCase):
    def test_two_floor_cells_and_supported_seat(self):
        cells = log_bench.roles()
        self.assertEqual(tuple(max(p[i] for p in cells)+1-min(p[i] for p in cells) for i in range(3)),(32,16,16))
        self.assertEqual(min(p[1] for p in cells),0)
        self.assertTrue(connected(cells))
        self.assertTrue(all((x,15,z) in cells for x in range(-6,6) for z in range(-3,3)),
                        'flat intact torso support at the original one-block seat height')
        for x in (-10,10):
            self.assertTrue(all((x,y,0) in cells for y in range(16)), 'both feet connect ground to seat')
        self.assertFalse(any((0,y,0) in cells for y in range(7)), 'air gap between chunky supports')
        self.assertNotIn((-13,15,3),cells,'drying split removes real surface geometry')
        self.assertEqual(cells[-13,12,3],'crack','split has a solid dark floor')

    def test_production_and_all_material_variants(self):
        definition = read_json('data/furniture/bench.json')
        self.assertEqual(definition['footprint'],{'width':2,'depth':1})
        self.assertEqual(definition['material_palette'],'hand_hewn_timber')
        _,parts,metadata = next(assets(only='/bench.glb'))
        # Hearthblock Tier 1 bench (doc 256); its seat contracts are in test_hearthblock.
        self.assertEqual(parts['main'].voxels.cells,hearthblock.model('log_bench').cells)
        self.assertEqual(metadata['source'],'data/art/voxel_hearthblock.json')
        source = read_json('data/materials/craft_materials.json')['source_palettes']['hand_hewn_timber']['colors']
        for wood,palette in log_bench.TIMBER['palettes'].items():
            expected = {p:linear(palette[role]) for p,role in log_bench.roles().items()}
            self.assertEqual(log_bench.model('base:material:'+wood).cells,expected)
        self.assertTrue(all('hewn_'+role in source for role in set(log_bench.roles().values())))

    def test_editable_models_retain_every_cell_and_color(self):
        with tempfile.TemporaryDirectory() as directory:
            log_bench.export_editable(directory)
            for wood,colors in log_bench.TIMBER['palettes'].items():
                models,palette = read_models(Path(directory)/('log_bench_'+wood+'.vox'))
                cells = grounded_cells(models[0])
                self.assertEqual(set(cells),set(log_bench.roles()))
                for p,index in cells.items():
                    self.assertEqual(palette[index-1],tuple(bytes.fromhex(colors[log_bench.roles()[p]]))+(255,))


if __name__=='__main__': unittest.main()

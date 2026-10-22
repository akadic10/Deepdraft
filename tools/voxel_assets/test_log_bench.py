"""Log bench: footprint, wood palette and the Hearthblock Tier 1 model (doc 256)."""
import unittest
import hearthblock
from common import read_json
from furniture import assets


class LogBenchTests(unittest.TestCase):
    def test_production_model_and_definition(self):
        definition = read_json('data/furniture/bench.json')
        self.assertEqual(definition['footprint'],{'width':2,'depth':1})
        self.assertEqual(definition['material_palette'],'hand_hewn_timber')
        _,parts,metadata = next(assets(only='/bench.glb'))
        # The seat contracts are checked in test_hearthblock.
        self.assertEqual(parts['main'].voxels.cells,hearthblock.model('log_bench').cells)
        self.assertEqual(metadata['source'],'data/art/voxel_hearthblock.json')


if __name__=='__main__': unittest.main()

"""The bench: footprint, wood palette and its Hearthblock model, the Carpenter's plank bench (tier2.mjs)."""
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
        self.assertEqual(parts['main'].voxels.cells,hearthblock.model('plank_bench').cells)
        # The Tier 1 sitting log is a kept design: still in the art data, built into no piece.
        self.assertNotIn('piece',read_json(hearthblock.DATA)['models']['log_bench'])
        self.assertEqual(metadata['source'],'tools/art_data/voxel_hearthblock.json')


if __name__=='__main__': unittest.main()

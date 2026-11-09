"""Production models match their manifests; furniture definitions have their assets and recipes."""
import hashlib
import json
import unittest
from common import ROOT, read_json
from coverage import expected_paths


class CoverageTests(unittest.TestCase):
    def test_all_production_models_have_exact_manifest_coverage(self):
        owned = set()
        for path in (ROOT/'tools/art_data/voxel_manifests').glob('*.json'):
            ledger = json.loads(path.read_text())
            paths = {r['path'] for r in ledger['assets']}
            self.assertEqual(paths, expected_paths(ledger['family']))
            self.assertFalse(owned & paths)
            owned |= paths
            for row in ledger['assets']:
                self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(), row['sha256'], row['path'])
        actual = {p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models').rglob('*.glb') if '/studies/' not in p.as_posix()}
        self.assertEqual(actual, owned)
        self.assertEqual(len(actual), 424)   # + the duck's two folded-wing meshes (doc 256); + fishing's crates, serving, rod, float and catches (doc 289, steps 1 and 2); + the drying rack and dried fish crates (step 3); + the grill sticks, raw and grilled (doc 290); + the drying rack's fish part; + the four big fish on the line (doc 292); + the carpenter's and mason's benches, the masonry kit, the stone adze and maul, and the stone stool (doc 293); + the tool rack and the raw materials crate (doc 294); + the finished goods pallet; + the basic smelter, its charge, the copper bar and the copper fitting (doc 297); + the food shelf (doc 299)

    def test_remaining_definitions_have_all_assets_and_packed_items(self):
        items = read_json('data/entities/items/resources.json')
        definitions = [json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'data/furniture').glob('*.json')]
        self.assertEqual(len(definitions), 27)   # + the two benches and the stone stool (doc 293); + the tool rack and the raw materials crate (doc 294); + the finished goods pallet; + the basic smelter (doc 297); + the food shelf (doc 299)
        for definition in definitions:
            self.assertTrue((ROOT/definition['model'].removeprefix('res://')).is_file())
            self.assertIn(definition['item_key'], items)
            if 'light_source' in definition:
                self.assertTrue((ROOT/definition['light_source']['flame_animation']['model'].removeprefix('res://')).is_file())
        for name in ['settlement_flag', 'wet_stone', 'dry_stone']:
            self.assertTrue((ROOT/'data/furniture'/f'{name}.json').is_file())

    def test_every_remaining_furniture_design_is_craftable_or_explicitly_kept(self):
        recipes=read_json('data/workshops/worker_crafting.json')['recipes']
        items=read_json('data/entities/items/resources.json')
        definitions={json.loads(p.read_text(encoding='utf-8'))['furniture_key'] for p in (ROOT/'data/furniture').glob('*.json')}
        craftable={r['furniture'] for r in recipes if r.get('furniture')}
        self.assertEqual(len(recipes),32)     # + the two benches, the masonry kit and the stone stool (doc 293); + the tool rack and the crate (doc 294); + the finished goods pallet; + the basic smelter, copper bars and fittings (doc 297); + the food shelf (doc 299)
        self.assertEqual(len(craftable),24)   # the same, without the kit
        self.assertEqual(definitions,craftable|{'base:furniture:settlement_flag','base:water:wet_stone','base:water:dry_stone'})
        for recipe in recipes: self.assertIn(recipe['output'],items)


if __name__ == '__main__': unittest.main()

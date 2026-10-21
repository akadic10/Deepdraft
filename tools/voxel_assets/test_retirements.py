"""No retired production paths/identities; retained art and recipes stay usable."""
import hashlib
import json
import unittest
from common import ROOT, read_json
from coverage import expected_paths
from asset_ownership import guard_legacy_write


class RetirementTests(unittest.TestCase):
    def test_retired_assets_are_absent_and_legacy_writes_blocked(self):
        policy = read_json('data/content_retirements.json')
        self.assertEqual(len(policy['furniture']), 15)
        for path in policy['assets']:
            self.assertFalse((ROOT/path).exists(), path)
            with self.assertRaises(RuntimeError): guard_legacy_write(ROOT/path)
        items = read_json('data/entities/items/resources.json')
        self.assertEqual(len(policy['items']), 4)
        self.assertEqual([k for k in items if k.startswith('base:resources:stone:')],
                         ['base:resources:stone:rough_stone'])
        for key in policy['items']:
            self.assertNotIn(key, items)
            thumbnail = ROOT/'assets/ui/items'/(key.replace(':', '_')+'.png')
            self.assertFalse(thumbnail.exists())
            name = key.rsplit(':', 1)[1]+'_block'
            for folder in ('chunky_resources', 'stone_ore_dirt'):
                self.assertFalse((ROOT/'VoxelFeed/colored'/folder/(name+'.vox')).exists())
        self.assertEqual(read_json('data/art/voxel_items.json')['stone'], ['rough_stone'])
        place = read_json('data/ui/place_catalog.json')
        for key in policy['furniture']:
            name = key.rsplit(':', 1)[1]
            self.assertFalse((ROOT/'data/furniture'/f'{name}.json').exists())
            self.assertFalse((ROOT/'assets/ui/furniture'/f'{name}.png').exists())
            self.assertNotIn(key.replace('base:furniture:', 'base:resources:furniture:'), items)
            self.assertNotIn(key, {r['key'] for r in place['items']})

    def test_all_production_models_have_exact_manifest_coverage(self):
        owned = set()
        for path in (ROOT/'data/art/voxel_manifests').glob('*.json'):
            ledger = json.loads(path.read_text())
            paths = {r['path'] for r in ledger['assets']}
            self.assertEqual(paths, expected_paths(ledger['family']))
            self.assertFalse(owned & paths)
            owned |= paths
            for row in ledger['assets']:
                self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(), row['sha256'], row['path'])
        actual = {p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models').rglob('*.glb') if '/studies/' not in p.as_posix()}
        self.assertEqual(actual, owned)
        self.assertEqual(len(actual), 382)

    def test_remaining_definitions_have_all_assets_and_packed_items(self):
        items = read_json('data/entities/items/resources.json')
        definitions = [json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'data/furniture').glob('*.json')]
        self.assertEqual(len(definitions), 19)
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
        self.assertEqual(len(recipes),20)
        self.assertEqual(len(craftable),16)
        self.assertEqual(definitions,craftable|{'base:furniture:settlement_flag','base:water:wet_stone','base:water:dry_stone'})
        for recipe in recipes: self.assertIn(recipe['output'],items)


if __name__ == '__main__': unittest.main()

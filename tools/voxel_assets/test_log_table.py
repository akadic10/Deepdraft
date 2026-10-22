"""Log dining table: footprint, seating obstacles, recipe and seated head clearance."""
import unittest
from common import read_json
import hearthblock


class LogTableTests(unittest.TestCase):
    def test_definition_and_craft_registration(self):
        definition=read_json('data/furniture/log_table.json')
        self.assertEqual(definition['footprint'],{'width':3,'depth':3})
        self.assertEqual(definition['dining_surface_height'],24/16)
        self.assertEqual(definition['material_palette'],'hand_hewn_timber')
        self.assertEqual(len(definition['seating']['slots']),4)
        # The Tier 1 split-slab table (doc 256) stays inside the seating obstacles.
        for x,y,z in hearthblock.model('split_slab_table').cells:
            lo=((x+24)/16,y/16,(z+24)/16);hi=tuple(v+1/16 for v in lo)
            self.assertTrue(any(all(b['min'][i]<=lo[i] and hi[i]<=b['max'][i] for i in range(3)) for b in definition['seating_obstacles']))
        recipe=next(r for r in read_json('data/workshops/worker_crafting.json')['recipes'] if r['id']=='base:recipe:worker:log_table')
        self.assertEqual(recipe['furniture'],definition['furniture_key'])
        self.assertEqual(recipe['output'],definition['item_key'])
        self.assertEqual(recipe['ingredient_count'],2)
        self.assertIn(definition['item_key'],read_json('data/entities/items/resources.json'))

    def test_compact_four_seat_profile_keeps_every_head_off_the_tabletop(self):
        definition=read_json('data/furniture/log_table.json')
        seating=definition['seating']
        self.assertEqual(seating['max_chairs'],4)
        positions=[s['chair_origin'] for s in seating['slots']]
        self.assertEqual([(min(p[i] for p in positions),max(p[i] for p in positions)+1) for i in range(2)],[(-1,4),(-1,4)])
        self.assertEqual(positions,[[1,-1],[3,1],[1,3],[-1,1]])
        for now,before in zip(positions,[[1,-2],[4,1],[1,4],[-2,1]]):
            self.assertEqual(sum(abs(a-b) for a,b in zip(now,before)),1)
        profile=seating['chair_profile']
        self.assertFalse(profile['face_nearby_fire'])
        # Long beards may hang below the tabletop (owner rule, 2026-10-21), but no
        # cell of any head part may enter the slab. North seat: chair cell (1, -1),
        # facing +Z, so chair-local = table-local - (1, 0, -1).
        head=profile['rest_pose'].get('head',profile['rest_pose']['body'])
        slab=next(b for b in definition['seating_obstacles'] if b['min'][1]>=1)
        lo=[slab['min'][0]-1,slab['min'][1],slab['min'][2]+1]; hi=[slab['max'][0]-1,slab['max'][1],slab['max'][2]+1]
        box=profile['clearance_regions'][0]
        from dwarves import assets
        for path,parts,_ in assets():
            if not any(s in path for s in ['/head_','/hair/','/beards/','/eyebrows/','/scars/','/eyes.']):continue
            for part in parts.values():
                for x,y,z in part.voxels.cells:
                    a=[x/16+.5+head[0],y/16+head[1],z/16+.5+head[2]]
                    self.assertFalse(all(a[i]<hi[i] and a[i]+1/16>lo[i] for i in range(3)),f'{path} cell {(x,y,z)} enters the tabletop')
                    for i in (0,2): self.assertTrue(box['min'][i]<=a[i] and a[i]+1/16<=box['max'][i],path)
                    self.assertLessEqual(a[1]+1/16,box['max'][1],path)


if __name__=='__main__':unittest.main()

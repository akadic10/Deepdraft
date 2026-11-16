"""Complete defined crop stages, ground contacts and separated scree contracts; the field crops'
tile, ridge, height and stage contracts (doc 309)."""
import unittest
from collections import deque
from common import linear,read_json
from coverage import expected_paths
from rocks import assets as rocks
from crops import assets as crops,field_tile,FIELD


def components(cells):
    remaining=set(cells); result=[]
    while remaining:
        first=remaining.pop(); pending=deque([first]); part={first}
        while pending:
            p=pending.popleft()
            for axis in range(3):
                for sign in (-1,1):
                    n=list(p); n[axis]+=sign; n=tuple(n)
                    if n in remaining:
                        remaining.remove(n); part.add(n); pending.append(n)
        result.append(part)
    return result


class GroundCropTests(unittest.TestCase):
    def test_complete_grounded_rocks_and_separated_scree(self):
        rows=list(rocks())
        self.assertEqual({r[0] for r in rows},expected_paths('rocks'))
        for path,parts,meta in rows:
            cells=parts['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0,path)
            pieces=components(cells)
            self.assertTrue(all(min(p[1] for p in piece)==0 for piece in pieces),path)
            if meta['kind']=='scree': self.assertGreaterEqual(len(pieces),3,path)
            else: self.assertEqual(len(pieces),1,path)

    def test_all_crop_references_and_growth(self):
        rows=list(crops()); by_species={}
        self.assertEqual(len(rows),37)   # the 14 placeholders; + the bare tilled tile and the seven field crops' 22 stages (doc 309)
        self.assertEqual({r[0] for r in rows},expected_paths('crops'))
        for path,parts,meta in rows:
            cells=parts['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0,path)
            self.assertIn(meta['integration'],('art_and_data_only','field_crop'),path)
            if meta['integration']=='art_and_data_only':   # the brewing and weaving placeholders
                by_species.setdefault(meta['species'],[]).append((meta,max(p[1] for p in cells),len(cells)))
        self.assertEqual(len(by_species),4)
        for species,forms in by_species.items():
            young=[r for r in forms if r[0]['stage'] in ('cutting','seedling','sprouting')]
            older=[r for r in forms if r not in young]
            self.assertEqual(len(young),1,species)
            self.assertTrue(all(r[1]>young[0][1] for r in older),species)
            self.assertTrue(all(r[2]>young[0][2] for r in older),species)

    def test_every_field_tile_carries_the_ridges_and_stays_inside_its_tile(self):
        rows={(meta['species'],meta['stage']):(path,parts['main']) for path,parts,meta in crops() if meta['integration']=='field_crop'}
        self.assertEqual(len(rows),23)
        self.assertEqual({key[0] for key in rows},set(FIELD)|{'field'})
        bare=rows['field','bare'][1].voxels.cells
        # The ridges alone: one cell high, the same from one end of the tile to the other, so
        # tiles join along X; the troughs between and beside them are empty.
        self.assertEqual({p[1] for p in bare},{0})
        for (x,y,z),color in bare.items():
            self.assertTrue(all(bare.get((other,y,z))==color for other in range(-8,8)),(x,y,z))
        self.assertEqual({p[2] for p in bare},set(range(-7,-1))|set(range(1,7)))
        for (name,stage),(path,part) in rows.items():
            cells=part.voxels.cells
            self.assertTrue(part.shadow and part.occlusion and part.occlusion.get('ground')==0,path)
            self.assertTrue(set(bare)<=set(cells),path)
            self.assertTrue(all(-8<=p[0]<8 and -8<=p[2]<8 and p[1]>=0 for p in cells),path)
            self.assertTrue(all(min(p[1] for p in piece)==0 for piece in components(cells)),path)
            if name not in ('field','cabbage','pumpkin'):   # a row crop leaves the soil as the bare tile has it
                self.assertEqual({p:c for p,c in cells.items() if p[1]==0},bare,path)

    def test_field_crops_grow_taller_and_show_the_vegetable_only_when_ripe(self):
        profile=read_json('tools/art_data/voxel_crops.json')['field']
        ripe_height={}
        for name in FIELD:
            own={linear(value) for value in profile[name]['crop'].values()}
            high={}
            for stage in ('sprout','growing','ripe'):
                cells=field_tile(profile,name,stage).cells
                high[stage]=max(p[1] for p in cells)+1
                self.assertEqual(any(color in own for color in cells.values()),stage=='ripe',(name,stage))
            self.assertIn(high['sprout'],(2,3),name)
            self.assertLess(high['sprout'],high['growing'],name)
            self.assertLess(high['growing'],high['ripe'],name)
            self.assertLessEqual(high['ripe'],profile[name]['height'],name)
            ripe_height[name]=high['ripe']
        self.assertEqual(max(ripe_height,key=ripe_height.get),'kale')
        # A picking takes the kale's leaves and nothing else: the stalk and its young top stay.
        ripe=field_tile(profile,'kale','ripe').cells; picked=field_tile(profile,'kale','picked').cells
        self.assertTrue(set(picked)<set(ripe))
        for point,color in picked.items(): self.assertEqual(ripe[point],color,point)
        self.assertNotIn(linear(profile['kale']['crop']['frill']),picked.values())


if __name__=='__main__': unittest.main()

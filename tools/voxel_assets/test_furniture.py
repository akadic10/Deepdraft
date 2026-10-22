"""Complete state paths, contact planes, accepted anchors and fixed fire roots."""
import unittest
from common import read_json,linear,Voxels
from furniture import assets
from coverage import expected_paths
from solid_shapes import solid


class FurnitureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.parts={p:parts for p,parts,_ in assets()}

    def test_complete_family_and_casting(self):
        self.assertEqual(set(self.parts),expected_paths('furniture'))
        for path,parts in self.parts.items():
            for name,part in parts.items():
                self.assertTrue(part.voxels.cells,path+name)
                self.assertEqual(part.shadow,'flame' not in name,path+name)

    def test_retired_designs_cannot_regenerate(self):
        retired=read_json('data/content_retirements.json')
        self.assertFalse(set(retired['assets']) & set(self.parts))
        for name in ['settlement_flag','wet_stone','dry_stone','log_table','log_chair','board_game_table']:
            self.assertIn('assets/models/furniture/'+name+'.glb',self.parts)

    def test_access_contacts_and_buried_bridge_tails(self):
        for h in range(1,5):
            cells=self.parts['assets/models/furniture/crude_ladder_'+str(h)+'.glb']['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0)
            self.assertEqual(max(p[1]+1 for p in cells),h*16)
        for span in range(1,6):
            cells=self.parts['assets/models/furniture/log_bridge_'+str(span)+'.glb']['main'].voxels.cells
            self.assertEqual(max(p[1]+1 for p in cells),0)
            self.assertGreaterEqual(min(p[1] for p in cells),-10)
            self.assertTrue(all(y<-1 for x,y,z in cells if z>=4 or z<=-span*16-20))
        for name,count in [('door',1),('log_door_3',1),('log_door_4',2),('log_gate',1)]:
            parts=self.parts['assets/models/furniture/'+name+'.glb']
            self.assertEqual(len([key for key in parts if key.startswith('leaf_')]),count)

    def test_refined_bed_and_bridge_contact_surfaces(self):
        bed=self.parts['assets/models/furniture/log_bed.glb']['main'].voxels.cells
        self.assertEqual(tuple(max(p[i] for p in bed)+1-min(p[i] for p in bed) for i in range(3)),(64,15,48))
        for x in range(-8,12):
            for z in range(-8,8):
                self.assertTrue((x,11,z) in bed,f'continuous twelve-cell sleeping surface at {(x,z)}')
                self.assertFalse(any((x,y,z) in bed for y in range(12,15)),'no new lump beneath the torso')
        for span in range(1,6):
            cells=self.parts[f'assets/models/furniture/log_bridge_{span}.glb']['main'].voxels.cells
            for x in [-4,4,12,20]:
                # Only the gap is flush; landing tails deliberately settle into the banks.
                for z in range(-span*16-8,-8):
                    self.assertTrue((x,-1,z) in cells,f'bridge {span}: flush trunk support at {(x,z)}')

    def test_gate_and_derived_fence_share_exact_posts(self):
        post=self.parts['assets/models/furniture/log_fence.glb']['post'].voxels.cells
        gate=self.parts['assets/models/furniture/log_gate.glb']
        for offset,name in [(-16,'post_left'),(16,'post_right')]:
            self.assertEqual({(x+offset,y,z):c for (x,y,z),c in post.items()},gate[name].voxels.cells)
        self.assertTrue(all(-2<=x<2 and -2<=z<2 and 0<=y<21 for x,y,z in post),
                        'same quantized navigation post envelope')
        rails=self.parts['assets/models/furniture/parts/log_fence_rails.glb']['rails'].voxels.cells
        self.assertTrue(all(-8<=x<8 and -2<=z<2 for x,y,z in rails),'derived span and barrier depth')
        self.assertTrue(all((x,y,0) in rails for x in range(-8,8) for y in (7,16)),
                        'both rails still connect to adjacent corner posts')

    def test_shared_flame_states_and_fixed_roots(self):
        total=0
        for name in ['campfire','hearth','wooden_torch']:
            light=read_json('data/furniture/'+name+'.json')['light_source']
            frames=self.parts[light['flame_animation']['model'].removeprefix('res://')]
            self.assertEqual(list(frames),light['flame_animation']['frames'])
            shapes=[part.voxels.cells for part in frames.values()]
            self.assertEqual(len({frozenset(v) for v in shapes}),len(shapes))
            roots=[{p for p in v if p[1]==min(c[1] for c in v)} for v in shapes]
            self.assertTrue(all(r==roots[0] for r in roots))
            self.assertEqual(shapes[0],self.parts['assets/models/furniture/'+name+'.glb'][light['emissive_mesh']].voxels.cells)
            total+=len(frames)
        self.assertEqual(total,26)


if __name__=='__main__': unittest.main()

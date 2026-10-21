"""Appearance differentiation, fixed rig contacts and modular coverage."""
import unittest
from common import read_json,linear,Voxels
from dwarves import assets,separate_overlay,surface_keys
from coverage import expected_paths
from micro_voxel_study.generate import solid


def _merged(parts):
    vox=Voxels()
    for part in parts.values(): vox.cells.update(part.voxels.cells)
    return vox


class DwarfTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.parts={p:(_merged(parts),meta) for p,parts,meta in assets()}

    def test_coverage_and_identity(self):
        self.assertEqual(set(self.parts),expected_paths('dwarves'))
        for folder,expected in [('hair/',14),('beards/',7),('body/head_',4)]:
            cells=[frozenset(v.cells.items()) for path,(v,_) in self.parts.items() if folder in path]
            self.assertEqual(len(cells),expected)
            self.assertEqual(len(set(cells)),expected,'variants must remain distinct: '+folder)

    def test_fixed_rig_contacts(self):
        # Gameplay contacts, not the old shapes (owner rule, 2026-10-21): every work
        # pose grips the palm at (17, 20, 3), the sole stands on the ground, the boots
        # keep a gap at the relaxed stance and the closed lids cover the bead eyes.
        hand=self.parts['assets/models/characters/dwarves/body/hand.glb'][0].cells
        self.assertTrue(all((x,y,z) in hand for x in range(15,19) for y in range(18,22) for z in range(1,5)),'the mitten surrounds the palm grip')
        foot=self.parts['assets/models/characters/dwarves/body/foot.glb'][0].cells
        self.assertEqual(min(p[1] for p in foot),0,'the sole stands on the ground')
        inset=read_json('data/entities/dwarves/proportions.json')['relaxed_foot_inset']*16
        self.assertGreaterEqual(min(p[0] for p in foot)-inset,1,'the boots keep a gap at the relaxed stance')
        authored=self.parts['assets/models/characters/dwarves/body/eyes.glb'][0].cells
        lids=Voxels()
        for shape in read_json('data/art/voxel_presentation.json')['parts']['eyelids']: solid(lids,shape,{'neutral':(1,1,1),'crease':(.5,.5,.5)})
        self.assertTrue({(x,y) for x,y,z in authored}<={(x,y) for x,y,z in lids.cells},'eyelids cover the eyes')
        self.assertTrue(all((x,y,z) in lids.cells for x,y,z in authored),'closed lids sit exactly over the open eyes')
        # Eyes must remain visible on every head, including bald dwarves.
        eyes=self.parts['assets/models/characters/dwarves/body/eyes.glb'][0].cells
        eye_front={}
        for x,y,z in eyes: eye_front[x,y]=max(z,eye_front.get((x,y),z))
        for path,(head,_) in self.parts.items():
            if '/body/head_' not in path: continue
            for (x,y),z in eye_front.items():
                self.assertFalse(any((x,y,k) in head.cells for k in range(z,16)),path+' eye occlusion')

    def test_no_coincident_skin_overlay_surface(self):
        head=set().union(*(surface_keys(v.cells) for path,(v,_) in self.parts.items() if '/body/head_' in path))
        for path,(vox,_) in self.parts.items():
            if not any(folder in path for folder in ('/hair/','/beards/','/eyebrows/','/scars/')): continue
            before=dict(vox.cells)
            separate_overlay(vox,head)
            self.assertEqual(before,vox.cells,path+' must have no remaining shared skin/overlay exterior face')

    def test_appearance_bounds_and_work_contacts(self):
        for path,(vox,_) in self.parts.items():
            if '/tools/' not in path:
                self.assertGreaterEqual(min(p[1] for p in vox.cells),0,path)
                self.assertLessEqual(max(p[1]+1 for p in vox.cells),54,path)
        for name,point in [('felling_axe',(0,17,11)),('mining_pickaxe',(0,22,15))]:
            cells=self.parts['assets/models/characters/dwarves/tools/'+name+'.glb'][0].cells
            self.assertTrue(any(all(c[i]<=point[i]<=c[i]+1 for i in range(3)) for c in cells),name+' impact touches solid')
            self.assertIn((0,0,0),cells,name+' lower grip')


if __name__=='__main__': unittest.main()

"""Appearance differentiation, fixed rig contacts and modular coverage."""
import unittest
from common import read_json,linear,Voxels
from dwarves import assets,separate_overlay,surface_keys
from coverage import expected_paths
from micro_voxel_study.generate import solid


class DwarfTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.parts={p:(parts['main'].voxels,meta) for p,parts,meta in assets()}

    def test_coverage_and_identity(self):
        self.assertEqual(set(self.parts),expected_paths('dwarves'))
        for folder,expected in [('hair/',14),('beards/',7),('body/head_',4)]:
            cells=[frozenset(v.cells.items()) for path,(v,_) in self.parts.items() if folder in path]
            self.assertEqual(len(cells),expected)
            self.assertEqual(len(set(cells)),expected,'variants must remain distinct: '+folder)

    def test_fixed_rig_contacts(self):
        # The new sculpt may change faces/clothes/hair. Preserve the actual rig
        # interfaces instead of requiring the old pilot's entire silhouette.
        pilot=read_json('data/art/micro_voxel_study.json')
        colors={k:linear(v) for k,v in pilot['palette'].items()}
        for name in ('hand','foot','eyes'):
            vox=Voxels()
            for shape in pilot['parts']['dwarf/'+name]: solid(vox,shape,colors)
            authored=self.parts['assets/models/characters/dwarves/body/'+name+'.glb'][0].cells
            if name=='eyes':
                self.assertEqual(vox.cells,authored,'eye/eyelid assembly stays fixed')
            else:
                self.assertLessEqual(set(vox.cells),set(authored),name+' keeps the original contact solids')
                for axis in range(3):
                    self.assertEqual(min(p[axis] for p in vox.cells),min(p[axis] for p in authored),name+' lower envelope')
                    self.assertEqual(max(p[axis] for p in vox.cells),max(p[axis] for p in authored),name+' upper envelope')
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

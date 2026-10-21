"""Complete species/sex parts, rigid segment contacts and accepted deer anchors."""
import unittest
from common import read_json,linear,Voxels
from wildlife import assets
from coverage import expected_paths
from micro_voxel_study.generate import solid
import hearthblock


class WildlifeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.parts={p:parts for p,parts,_ in assets()}

    def test_coverage_and_opaque_solids(self):
        self.assertEqual(set(self.parts),expected_paths('wildlife'))
        for path,parts in self.parts.items():
            for part in parts.values():
                self.assertTrue(part.voxels.cells,path)
                self.assertTrue(part.shadow,path)

    def test_deer_solids_and_knee_join(self):
        # The Hearthblock deer (doc 256) replaced the 2026-10-09 deer pilot with the
        # owner's approval; production must equal its authored cells.
        for name in ('body','head','neck','ears','antlers','leg'):
            actual={p:c for part in self.parts['assets/models/animals/deer/'+name+'.glb'].values() for p,c in part.voxels.cells.items()}
            self.assertEqual(actual,hearthblock.model('deer/'+name).cells,name)
        for species in ('deer','wolf'):
            knee=round(read_json(f'data/entities/animals/{species}.json')['visual_pose']['knee_y']*16)
            parts=self.parts['assets/models/animals/'+species+'/leg.glb']
            upper=parts['Upper'].voxels.cells; lower=parts['Lower'].voxels.cells
            self.assertFalse(set(upper)&set(lower))
            self.assertTrue(any((x,knee-1,z) in lower for x,y,z in upper if y==knee))

    def test_sex_variants_and_ground_contact(self):
        for name in ('body','head','wing','wing_folded'):
            male=self.parts['assets/models/animals/duck/male_'+name+'.glb']['main'].voxels.cells
            female=self.parts['assets/models/animals/duck/female_'+name+'.glb']['main'].voxels.cells
            self.assertEqual(set(male),set(female))
            self.assertNotEqual(male,female)
        for name in ('rabbit/body','duck/foot'):
            cells=self.parts['assets/models/animals/'+name+'.glb']['main'].voxels.cells
            self.assertEqual(min(p[1] for p in cells),0)
        self.assertEqual(read_json('data/entities/animals/wolf.json')['visual_scale'],[1,1,1])


if __name__=='__main__': unittest.main()

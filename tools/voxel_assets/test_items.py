import unittest
from items import assets,PROFILE,shell
from construction import assets as construction_assets
from coverage import expected_paths
import hand_hewn_timber


class GoodsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.models={p:parts['main'].voxels.cells for p,parts,_ in assets()}

    def test_complete_grounded_and_bounded(self):
        self.assertEqual(set(self.models),expected_paths('items'))
        for path,cells in self.models.items():
            self.assertEqual(min(p[1] for p in cells),0,path)
            if '/crates/' in path or path.endswith('/oak_stave.glb'):
                self.assertTrue(all(max((x+dx)**2+(z+dz)**2 for dx in (0,1) for dz in (0,1))<=64 for x,y,z in cells),path)

    def test_timber_is_exact_colored_stool_turned_sideways(self):
        for name,material in PROFILE['timber'].items():
            cells=self.models[f'assets/models/items/wood/{name}.glb']
            self.assertEqual(len(cells),len(hand_hewn_timber.model('log_stool').cells))
            self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in range(3)],[(-7,7),(0,14),(-7,7)])
            upright={(x,6-z,y-7):color for (x,y,z),color in cells.items()}
            self.assertEqual(upright,hand_hewn_timber.model('log_stool',material).cells,name)

    def test_crate_states_and_contents(self):
        for name in PROFILE['crate_contents']:
            states=[self.models[f'assets/models/items/crates/{name}_{stage}.glb'] for stage in ('low','half','full')]
            self.assertTrue(len(states[0])<len(states[1])<len(states[2]),name)
            self.assertLess(max(p[1] for p in states[0]),max(p[1] for p in states[2]),name)
            self.assertNotEqual(states[0],states[1]); self.assertNotEqual(states[1],states[2])
            for cells in states:
                self.assertTrue(all(cells[p]==c for p,c in shell().cells.items()),name)

    def test_premium_drinks_distinct(self):
        for base,aged in [('stout_barrel','aged_stout_barrel'),('wine_barrel','vintage_wine_barrel'),('gin_cask','reserve_gin_cask')]:
            self.assertNotEqual(self.models[f'assets/models/items/drink/{base}.glb'],self.models[f'assets/models/items/drink/{aged}.glb'])

    def test_structural_tiles_fill_exact_unit(self):
        models={p:parts['main'].voxels.cells for p,parts,_ in construction_assets()}
        self.assertEqual(set(models),expected_paths('construction'))
        for path,cells in models.items():
            if 'floor' in path:
                self.assertEqual(set(cells),{(x,y,z) for x in range(16) for y in range(16) for z in range(16)})
        self.assertNotEqual(models['assets/models/construction/plank_floor.glb'],models['assets/models/construction/plank_floor_alternate.glb'])


if __name__=='__main__': unittest.main()

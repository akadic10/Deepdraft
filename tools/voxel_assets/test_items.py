import unittest
from common import linear
from items import assets,PROFILE,shell,NOT_IN_GAME
from coverage import expected_paths
import hearthblock
import hearthblock_goods as goods

STEPS=((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))


class GoodsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.models={p:parts['main'].voxels.cells for p,parts,_ in assets()}

    def test_complete_grounded_and_bounded(self):
        self.assertEqual(set(self.models),expected_paths('items'))
        for path,cells in self.models.items():
            self.assertEqual(min(p[1] for p in cells),0,path)
            if '/crates/' in path or path.endswith('/oak_stave.glb'):
                self.assertTrue(all(max((x+dx)**2+(z+dz)**2 for dx in (0,1) for dz in (0,1))<=64 for x,y,z in cells),path)

    def test_timber_is_the_hearthblock_stool_on_its_side_in_each_wood(self):
        # Stored logs match the Tier 1 stool and the square trees (doc 256); the size
        # and lying orientation the carry and stockpile code expect are unchanged.
        colors=[]
        for name,material in PROFILE['timber'].items():
            cells=self.models[f'assets/models/items/wood/{name}.glb']
            self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in range(3)],[(-7,7),(0,14),(-7,7)])
            self.assertEqual({(x,z+7,y-7) for x,y,z in cells},set(goods.log_roles()),name)
            colors.append(frozenset(cells.values()))
        self.assertEqual(len(set(colors)),4,'every wood keeps its own colours')

    def test_crate_states_and_contents(self):
        for name in PROFILE['crate_contents']:
            states=[self.models[f'assets/models/items/crates/{name}_{stage}.glb'] for stage in ('low','half','full')]
            self.assertTrue(len(states[0])<len(states[1])<len(states[2]),name)
            self.assertLess(max(p[1] for p in states[0]),max(p[1] for p in states[2]),name)
            self.assertNotEqual(states[0],states[1]); self.assertNotEqual(states[1],states[2])
            joinery=(shell() if name in NOT_IN_GAME else goods.shell()).cells
            for cells in states:
                self.assertTrue(all(cells[p]==c for p,c in joinery.items()),name)

    def test_mined_goods_are_connected_fragments_of_the_carry_size(self):
        appearances=set()
        for kind in ('stone','soil','ore'):
            for name in PROFILE[kind]:
                cells=self.models[f'assets/models/items/{kind}/{name}.glb']
                self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in (0,2)],[(-6,6),(-6,6)] if kind=='soil' else [(-6,6),(-5,6)],name)
                self.assertLessEqual(max(p[1] for p in cells)+1,12,name)
                remaining=set(cells); stack=[remaining.pop()]
                while stack:
                    p=stack.pop()
                    for d in STEPS:
                        q=(p[0]+d[0],p[1]+d[1],p[2]+d[2])
                        if q in remaining: remaining.remove(q); stack.append(q)
                self.assertFalse(remaining,name+' is one solid piece')
                appearances.add(frozenset(cells.items()))
                style=PROFILE['mined_styles'][name]['palette']
                if 'mineral' in style:
                    exposed=[p for p in cells if any((p[0]+d[0],p[1]+d[1],p[2]+d[2]) not in cells for d in STEPS)]
                    mineral={linear(style['mineral']),linear(style['mineral_light'])}
                    fraction=sum(cells[p] in mineral for p in exposed)/len(exposed)
                    self.assertTrue(.12<fraction<.5,(name,fraction))
        self.assertEqual(len(appearances),sum(len(PROFILE[k]) for k in ('stone','soil','ore')),'every mined good reads as its own material')

    def test_premium_drinks_distinct(self):
        for base,aged in [('stout_barrel','aged_stout_barrel'),('wine_barrel','vintage_wine_barrel'),('gin_cask','reserve_gin_cask')]:
            self.assertNotEqual(self.models[f'assets/models/items/drink/{base}.glb'],self.models[f'assets/models/items/drink/{aged}.glb'])


if __name__=='__main__': unittest.main()

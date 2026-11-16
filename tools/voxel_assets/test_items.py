import unittest
from common import linear,read_json
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

    def test_planks_are_one_sawn_board_in_each_wood(self):
        # A plank lies along Z as a log does, inside a stockpile tile and no longer than its log, and
        # is flat enough to be a board from above. It is one solid box, every face sawn: the same
        # shape in every wood, in that wood's own colours, with no bark on it.
        self.assertEqual(set(PROFILE['planks'].values()),set(PROFILE['timber'].values()))
        shapes=set(); colors=[]
        for name,material in PROFILE['planks'].items():
            cells=self.models[f'assets/models/items/wood/{name}.glb']
            box=[(min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in range(3)]
            self.assertEqual(box,[(-5,5),(0,4),(-7,7)],name)
            self.assertEqual(len(cells),10*4*14,name+' is one solid board')
            wood=goods.wood_roles(material)
            self.assertFalse({wood[r] for r in ('bark','bark_dark','bark_light')}&set(cells.values()),name)
            self.assertEqual({cells[x,3,z] for x in range(-5,5) for z in range(-7,7)},{wood['wood_top'],wood['riven_dark']},name)
            shapes.add(frozenset(cells)); colors.append(frozenset(cells.values()))
        self.assertEqual(len(shapes),1)
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

    def test_vegetable_crates_are_told_apart_from_above(self):
        # A stockpile is read from above (doc 309). Looking straight down into a vegetable's crate, at
        # every fill, the cells in view are that vegetable's own colours, more than one of them, and
        # no two vegetables show the same set: none is told from another by one colour alone.
        self.assertEqual(len(PROFILE['vegetable_styles']),7)
        joinery=goods.shell().cells
        for stage in ('low','half','full'):
            shown={}
            for name,style in PROFILE['vegetable_styles'].items():
                kind,dark,light=PROFILE['crate_contents'][name]
                own={linear(h) for h in style.values()}|{linear(dark),linear(light)}
                top={}
                for (x,y,z),color in self.models[f'assets/models/items/crates/{name}_{stage}.glb'].items():
                    if (x,y,z) not in joinery and y>=top.get((x,z),(0,))[0]: top[x,z]=(y,color)
                seen={color for _,color in top.values()}
                self.assertTrue(seen<=own,name+' '+stage)
                self.assertGreaterEqual(len(seen),2,name+' '+stage)
                shown[name]=frozenset(seen)
            self.assertEqual(len(set(shown.values())),7,stage)

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

    def test_tool_goods_hang_from_a_rack_and_copper_tools_are_one_bar_on_a_haft(self):
        # A tool good lies along Z with its head toward +Z, and a tool rack hangs it by that end, so it
        # is no longer than the hook is high. A copper tool is one copper bar and one log (doc 306):
        # its metal is the bar's own colours in no more cells than the bar, and its haft takes the
        # log's wood. No fixed colour may pass for a wood swatch at any baked shade, or the wood
        # recolour (CraftMaterials._shaded) would change it with the haft.
        hook=round(read_json('data/furniture/tool_rack.json')['storage']['anchors'][0][1]*16)
        bar=self.models['assets/models/items/metal/copper_bar.glb']
        copper,wood=set(goods.COPPER.values()),set(goods.TOOL.values())
        tools={path:cells for path,cells in self.models.items() if '/tools/' in path}
        self.assertEqual(len(tools),6)
        for path,cells in tools.items():
            self.assertLessEqual(max(p[2] for p in cells)+1-min(p[2] for p in cells),hook,path)
            self.assertTrue(wood&set(cells.values()),path)
            for color in set(cells.values())-wood:
                for shade in hearthblock.occlusion()['curve']:
                    stored=[int(v*shade*255)/255 for v in color]
                    self.assertFalse(any(max(abs(a-b*shade) for a,b in zip(stored,swatch))<1.5/255 for swatch in wood),path)
            metal=sum(color in copper for color in cells.values())
            if '/copper_' in path: self.assertTrue(0<metal<=len(bar),(path,metal))
            else: self.assertEqual(metal,0,path)

    def test_premium_drinks_distinct(self):
        for base,aged in [('stout_barrel','aged_stout_barrel'),('wine_barrel','vintage_wine_barrel'),('gin_cask','reserve_gin_cask')]:
            self.assertNotEqual(self.models[f'assets/models/items/drink/{base}.glb'],self.models[f'assets/models/items/drink/{aged}.glb'])


if __name__=='__main__': unittest.main()

"""Exact shared log size, supported game pieces and truthful seated clearance."""
import unittest
from common import read_json,linear
from furniture import assets
import hearthblock


def model(name):
    # The game table shares the Tier 1 dining table body (doc 256).
    return hearthblock.model({'dining_table':'split_slab_table'}[name])


class GameTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _,parts,_=next(assets(only='board_game_table.glb'))
        cls.cells=parts['main'].voxels.cells
        cls.palette=read_json('tools/art_data/voxel_hearthblock.json')['palettes']['hewn']
        cls.definition=read_json('data/furniture/board_game_table.json')

    def test_same_native_log_outline_and_height(self):
        base=model('dining_table').cells
        self.assertEqual({p for p in self.cells if p[1]<24},set(base))
        self.assertEqual({p:c for p,c in self.cells.items() if p[1]<23},
                         {p:c for p,c in base.items() if p[1]<23})
        self.assertTrue(all(self.cells[p] in (c,linear(self.palette['pith'])) for p,c in base.items()))
        self.assertEqual([(min(p[i] for p in self.cells),max(p[i] for p in self.cells)+1)
                          for i in range(3)],[(-23,23),(0,25),(-23,23)])
        self.assertEqual(self.definition['game_surface_height'],1.5)
        self.assertEqual(self.definition['footprint'],{'width':3,'depth':3})
        self.assertEqual(self.definition['material_palette'],'hand_hewn_timber')

    def test_six_separate_supported_stone_counters_and_board(self):
        pieces={p for p in self.cells if p[1]>=24};groups=[]
        while pieces:
            stack=[pieces.pop()];group=set(stack)
            while stack:
                x,y,z=stack.pop()
                for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
                    q=(x+dx,y,z+dz)
                    if q in pieces:pieces.remove(q);group.add(q);stack.append(q)
            groups.append(group)
        self.assertEqual(len(groups),6)
        colors=[linear(self.palette[key]) for key in ['red','teal']]
        for color in colors:
            self.assertEqual(sum(all(self.cells[p]==color for p in group) for group in groups),3)
        for group in groups:
            self.assertEqual(len(group),16)
            for x,y,z in group:
                self.assertEqual(y,24)
                self.assertTrue((x,y-1,z) in self.cells,'counter must rest directly on solid wood')
        base=model('dining_table').cells
        marks={p for p,c in self.cells.items() if p in base and c!=base[p]}
        self.assertTrue(marks)
        self.assertEqual({p[1] for p in marks},{23})

    def test_seating_obstacles_enclose_all_geometry_without_raising_outer_rim(self):
        boxes=self.definition['seating_obstacles']
        for x,y,z in self.cells:
            lo=((x+24)/16,y/16,(z+24)/16);hi=tuple(v+1/16 for v in lo)
            self.assertTrue(any(all(b['min'][i]<=lo[i] and hi[i]<=b['max'][i] for i in range(3)) for b in boxes),str((x,y,z)))
        dining=read_json('data/furniture/log_table.json')
        self.assertEqual(boxes[:-1],dining['seating_obstacles'])
        self.assertEqual(self.definition['collision_regions'],dining['collision_regions'])
        self.assertEqual(self.definition['seating']['chair_profile'],dining['seating']['chair_profile'])


if __name__=='__main__':unittest.main()

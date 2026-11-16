"""The board-game table: the plank dining table's frame under its own top, supported game pieces and truthful seated clearance."""
import unittest
from common import read_json,linear
from furniture import assets
import hearthblock


class GameTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _,parts,_=next(assets(only='board_game_table.glb'))
        cls.cells=parts['main'].voxels.cells
        cls.palette=read_json('tools/art_data/voxel_hearthblock.json')['palettes']['hewn']
        cls.definition=read_json('data/furniture/board_game_table.json')

    def test_dining_table_legs_under_its_own_top(self):
        # The game table is the plank dining table with the game marked on it (tier2.mjs, the owner's
        # pick, 2026-11-13): the same frame of two plank ends and two aprons under the same four
        # boards, so the two tables share their collision and seat boxes. (Until then it stood on the
        # Tier 1 log table's stumps and bearers; both log tables are kept designs in the art data.)
        dining=hearthblock.model('plank_table').cells
        self.assertEqual({p:c for p,c in self.cells.items() if p[1]<19},{p:c for p,c in dining.items() if p[1]<19})
        self.assertEqual({p for p in self.cells if 19<=p[1]<24},{p for p in dining if p[1]>=19},'the same four boards, laid the same way')
        self.assertEqual(max(p[1] for p in dining)+1,24)
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
        # The board is four squares by four, five cells to a square, scratched into the top layer
        # alone. Its lines across the boards are knot-dark; along them, two are knot-dark and three
        # are the gaps between the table's boards. (The log game table's board had six-cell squares
        # and four-cell counters; a counter here is three cells square, one cell inside its square.)
        line=linear(self.palette['pith'])
        marks=(-12,-6,0,6,12); gaps=(-12,0,12)
        for g in marks:
            for a in range(-12,13):
                if a not in gaps: self.assertEqual(self.cells[g,23,a],line,'board line across the boards')
        for g in (-6,6):
            for a in range(-12,13): self.assertEqual(self.cells[a,23,g],line,'board line along the boards')
        for g in gaps: self.assertFalse(any((a,23,g) in self.cells for a in range(-23,23)),'a gap between two boards is the board\'s line')
        self.assertFalse(any(c==line for p,c in self.cells.items() if p[1]==22 and abs(p[0])<=12 and abs(p[2])<=12))
        squares=set()
        for group in groups:
            self.assertEqual(len(group),9)
            for x,y,z in group:
                self.assertEqual(y,24)
                self.assertTrue((x,y-1,z) in self.cells,'counter must rest directly on solid wood')
                self.assertNotEqual(self.cells[x,y-1,z],line,'a counter stands inside a square, off the lines')
            squares.add((min(p[0] for p in group)//6,min(p[2] for p in group)//6))
        self.assertEqual(len(squares),6,'one counter to a square')

    def test_seating_obstacles_enclose_all_geometry_without_raising_outer_rim(self):
        boxes=self.definition['seating_obstacles']
        for x,y,z in self.cells:
            lo=((x+24)/16,y/16,(z+24)/16);hi=tuple(v+1/16 for v in lo)
            self.assertTrue(any(all(b['min'][i]<=lo[i] and hi[i]<=b['max'][i] for i in range(3)) for b in boxes),str((x,y,z)))
        dining=read_json('data/furniture/dining_table.json')
        self.assertEqual(boxes[:-1],dining['seating_obstacles'])
        self.assertEqual(self.definition['collision_regions'],dining['collision_regions'])
        self.assertEqual(self.definition['seating']['chair_profile'],dining['seating']['chair_profile'])


if __name__=='__main__':unittest.main()

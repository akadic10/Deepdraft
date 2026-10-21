import tempfile
import unittest
from pathlib import Path
from log_chair import source_model, model, roles, export_editable, MATERIALS
from vox_source import read_models


class LogChairTests(unittest.TestCase):
    def test_bounded_organic_player_shape_and_native_scale(self):
        original=source_model();cells=model().cells
        self.assertEqual(original['size'],(16,16,16))
        self.assertGreater(len(cells),2072*.85)
        self.assertLess({(x+8,7-z,y+1) for x,y,z in cells},set(original['cells']))
        self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)) for i in range(3)],[(-7,6),(0,13),(-7,6)])

    def test_exterior_bark_and_interior_cut_rings(self):
        assigned=roles();top_roles=set();bark=0;exterior=0
        for (x,y,z),role in assigned.items():
            exposed_side=any((x+dx,y,z+dz) not in assigned for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)])
            if exposed_side:
                exterior+=1
                bark+=role in ('bark','bark_dark')
            if y==13: top_roles.add(role)
        self.assertEqual(top_roles,{'bark','bark_dark','wood','grain','cut'})
        self.assertGreater(bark/exterior,.75,'bark surrounds small exposed knots and drying checks')

    def test_editable_species_preserve_shape_and_semantic_colors(self):
        original=source_model();appearances=[]
        with tempfile.TemporaryDirectory() as directory:
            export_editable(Path(directory))
            for wood in ['pine','oak','juniper','applewood']:
                models,palette=read_models(Path(directory)/(wood+'.vox'))
                self.assertEqual(len(models),1)
                self.assertEqual(models[0]['size'],original['size'])
                self.assertEqual(set(models[0]['cells']),{(x+8,7-z,y+1) for x,y,z in model().cells})
                colors=MATERIALS['materials']['base:material:'+wood]['colors']
                expected=[tuple(bytes.fromhex(colors[role]))+(255,) for role in ['bark_dark','bark','wood','grain','cut']]
                self.assertEqual(palette[:5],expected)
                appearances.append(tuple(expected))
            self.assertEqual(len(set(appearances)),4)


if __name__=='__main__': unittest.main()

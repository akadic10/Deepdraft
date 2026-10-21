import unittest
import tempfile
from pathlib import Path
from workbench import model,role_cells,PROFILE,source_model,export_editable
from common import read_json,linear
from vox_source import grounded_cells,read_models
from log_chair import MATERIALS


class WorkbenchTests(unittest.TestCase):
    def test_organic_example_outline_extruded_without_scaling(self):
        source=grounded_cells(source_model());outline={(x,z) for x,_,z in source}
        self.assertEqual(len(outline),1616)
        cells=role_cells(False)
        self.assertLess(len(cells),1616*16)
        self.assertGreater(len(cells),1616*16*.85)
        for y in range(16):
            self.assertLessEqual({(x,z) for x,h,z in cells if h==y},outline)

    def test_grounded_native_dimensions_and_definition(self):
        cells=model().cells;definition=read_json('data/furniture/crude_workbench.json')
        self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in range(3)],[(-23,23),(0,16),(-23,23)])
        self.assertEqual(definition['footprint'],{'width':3,'depth':3})
        self.assertEqual(definition['crafting_surface_height'],1.0)
        self.assertEqual(definition['collision_regions'][0]['max'],[3,1.0,3])
        self.assertEqual(definition['material_palette'],'hand_hewn_timber')

    def test_real_bounded_wear_and_supported_contacts(self):
        intact=role_cells(False);worn=role_cells();removed=set(intact)-set(worn)
        self.assertTrue(removed)
        self.assertTrue(all(y>=13 for x,y,z in removed))
        self.assertEqual({p:c for p,c in worn.items() if p[1]<12},{p:c for p,c in intact.items() if p[1]<12})
        self.assertLess(len(removed),len(intact)*.02)
        for x,z in [(10,0),(-10,0),(0,10),(0,-10)]:
            self.assertTrue((x,15,z) in worn,'material contact must have an intact top cell')
        self.assertEqual(set(worn.values()),{'bark','bark_dark','cut','wood','grain'})

    def test_four_editable_woods_keep_exact_occupancy_and_colors(self):
        roles=role_cells()
        with tempfile.TemporaryDirectory() as directory:
            export_editable(directory)
            for wood in ['pine','oak','juniper','applewood']:
                material='base:material:'+wood
                sources,palette=read_models(Path(directory)/(wood+'.vox'))
                self.assertEqual(sources[0]['size'],(48,48,16))
                cells=grounded_cells(sources[0])
                self.assertEqual(set(cells),set(roles))
                for point,color in cells.items():
                    expected=tuple(bytes.fromhex(MATERIALS['materials'][material]['colors'][roles[point]]))+(255,)
                    self.assertEqual(palette[color-1],expected)
                self.assertEqual(model(material).cells,{p:linear(MATERIALS['materials'][material]['colors'][role]) for p,role in roles.items()})


if __name__=='__main__':unittest.main()

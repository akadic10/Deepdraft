import tempfile
import unittest
from pathlib import Path
from common import ROOT, linear
from mined_resources import PROFILE, SHAPES, source_model, shape_cells, model, export_editable
from vox_source import read_models, grounded_cells


class MinedResourceTests(unittest.TestCase):
    def test_original_is_preserved_but_all_variants_use_approved_new_shapes(self):
        original=source_model()
        self.assertEqual(original['size'],(16,16,16))
        self.assertEqual(len(original['cells']),1088)
        names={name for kind in ('stone','ore','soil') for name in PROFILE[kind]}
        self.assertEqual(names,set(PROFILE['mined_styles']))
        for name in names:
            cells=model(name).cells
            self.assertNotEqual(set(cells),set(grounded_cells(original)),name)
            self.assertEqual(set(cells),shape_cells(PROFILE['mined_styles'][name]['shape']),name)
            self.assertEqual([(min(p[i] for p in cells),max(p[i] for p in cells)+1)
                              for i in range(3)],[(-6,6),(0,12),(-6,6)],name)
        self.assertEqual(len({shape_cells(kind) for kind in SHAPES['shapes']}),3)

    def test_every_shape_is_connected_supported_and_has_a_deep_open_cleft(self):
        for kind in SHAPES['shapes']:
            cells=shape_cells(kind)
            queue=[next(iter(cells))];seen=set(queue)
            for x,y,z in queue:
                for dx,dy,dz in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
                    p=x+dx,y+dy,z+dz
                    if p in cells and p not in seen:seen.add(p);queue.append(p)
            self.assertEqual(seen,cells,kind)
            self.assertGreater(sum(y==0 for x,y,z in cells),60,kind)
            self.assertTrue(all((0,y,3) not in cells for y in range(5,12)),kind)
            self.assertIn((0,0,3),cells,kind)
            self.assertNotEqual(cells,{(-1-x,y,z) for x,y,z in cells},kind)

    def test_ore_seams_are_visible_and_materials_distinct(self):
        appearances=[]
        for name in PROFILE['mined_styles']:
            cells=model(name).cells
            appearances.append(tuple(sorted(cells.items())))
            if name not in PROFILE['ore'] or name=='coal': continue
            exposed={p for p in cells if any(tuple(p[i]+d[i] for i in range(3)) not in cells
                for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)))}
            palette=PROFILE['mined_styles'][name]['palette']
            mineral={linear(palette[key]) for key in ('mineral','mineral_light')}
            fraction=sum(cells[p] in mineral for p in exposed)/len(exposed)
            self.assertGreater(fraction,.15,name)
            self.assertLess(fraction,.5,name)
        self.assertEqual(len(set(appearances)),10)

    def test_editable_vox_roundtrips_every_active_cell_and_color(self):
        with tempfile.TemporaryDirectory() as directory:
            export_editable(Path(directory))
            for name,style in PROFILE['mined_styles'].items():
                models,palette=read_models(Path(directory)/(name+'.vox'))
                self.assertEqual(len(models),1)
                self.assertEqual(models[0]['size'],(16,16,16))
                actual=grounded_cells(models[0]);expected=model(name).cells
                self.assertEqual(set(actual),set(expected),name)
                for p,index in actual.items():
                    self.assertEqual(linear(''.join(f'{v:02x}' for v in palette[index-1][:3])),expected[p],(name,p))
                self.assertEqual(palette[:len(style['palette'])],[tuple(bytes.fromhex(c))+(255,) for c in style['palette'].values()])

    def test_truncated_file_is_rejected(self):
        raw=(ROOT/PROFILE['mined_original_source']['source']).read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'truncated.vox';path.write_bytes(raw[:-1])
            with self.assertRaises(ValueError): read_models(path)


if __name__=='__main__': unittest.main()

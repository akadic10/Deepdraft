"""Accepted geometry, materials and production routing, including all wood variants."""
import tempfile
import unittest
from pathlib import Path
import hand_hewn_timber as hewn
from common import read_json,linear
from furniture import assets
from vox_source import read_models,grounded_cells


class HandHewnTests(unittest.TestCase):
    def test_drying_split_and_chipped_rim_preserve_support(self):
        table=hewn.roles()['dining_table']
        # The broad edge split is actual missing geometry with a dark floor;
        # its fine tip leaves most of the eight-cell slab intact.
        for x,z,depth in [(15,16,5),(12,11,3),(8,6,2)]:
            for y in range(24-depth,24): self.assertNotIn((x,y,z),table)
            self.assertEqual(table[x,23-depth,z],'crack')
        for kind,outline,top in [('dining_table','large_outline',23),('log_stool','stool_outline',13)]:
            cells=hewn.roles()[kind]
            rim=[p for p,d in hewn.depths(hewn.footprint(hewn.PROFILE[outline])).items() if d==0]
            heights={max(y for xx,y,zz in cells if (xx,zz)==(x,z)) for x,z in rim}
            self.assertIn(top,heights)
            self.assertTrue(any(y<top for y in heights),'rim has real chipped shoulders')
            self.assertTrue(hewn.connected(cells),'sculpting must not detach bark plates')
        # Every counter retains its entire supporting face after all damage.
        game=hewn.roles()['game_table']
        for x,y,z in game:
            if y==24: self.assertIn((x,y-1,z),table)

    def test_native_dimensions_contacts_and_shared_body(self):
        hewn.validate(hewn.roles())
        for kind,top in [('dining_table',23),('log_stool',13)]:
            cells=hewn.roles()[kind]
            self.assertTrue(all((x,top,z) in cells for x in range(-2,2) for z in range(-2,2)),kind)
        self.assertIn((1,15,1),hewn.roles()['workbench'],'central picking sample')
        for x,z in [(10,0),(-10,0),(0,10),(0,-10)]:
            self.assertIn((x,15,z),hewn.roles()['workbench'])
        table=hewn.roles()['dining_table']
        self.assertEqual(max(y for x,y,z in table)+1,24)
        self.assertEqual({y for x,y,z in table if x==16 and z==0},set(range(16,24)),
                         'eight real slab cells above the unchanged 16-cell pedestal')
        for name,field in [('log_table','dining_surface_height'),('board_game_table','game_surface_height')]:
            self.assertEqual(read_json('data/furniture/'+name+'.json')[field],24/16)

    def test_production_routes_and_palette_contract(self):
        materials=read_json('data/materials/craft_materials.json')
        profile=materials['source_palettes']['hand_hewn_timber']['colors']
        self.assertEqual(profile,{'hewn_'+role:color for role,color in hewn.PROFILE['palettes']['oak'].items() if role not in ('red','teal')})
        for wood,colors in hewn.PROFILE['palettes'].items():
            target=materials['materials']['base:material:'+wood]['colors']
            for role,color in colors.items():
                if role not in ('red','teal'): self.assertEqual(target['hewn_'+role],color)
        for name,kind in [('log_chair','log_stool'),('log_table','dining_table'),('board_game_table','game_table'),('crude_workbench','workbench')]:
            _,parts,_=next(assets(only='/'+name+'.glb'))
            self.assertEqual(parts['main'].voxels.cells,hewn.model(kind).cells)
            self.assertEqual(read_json('data/furniture/'+name+'.json')['material_palette'],'hand_hewn_timber')

    def test_editable_wood_variants_roundtrip(self):
        with tempfile.TemporaryDirectory() as directory:
            hewn.export_editable(directory)
            for wood,colors in hewn.PROFILE['palettes'].items():
                for kind,roles in hewn.roles().items():
                    models,palette=read_models(Path(directory)/(kind+'_'+wood+'.vox'))
                    cells=grounded_cells(models[0])
                    self.assertEqual(set(cells),set(roles))
                    for p,index in cells.items():
                        self.assertEqual(palette[index-1],tuple(bytes.fromhex(colors[roles[p]]))+(255,))


if __name__=='__main__': unittest.main()

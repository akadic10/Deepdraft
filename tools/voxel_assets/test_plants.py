"""Crop removal, packed identity, growth and seasonal model contracts."""
import math
import unittest
from common import read_json,linear
from plants import assets,shrub,shrub_layers,flowers,reeds,pack,RIPE,SEASONS
from coverage import expected_paths


class PlantTests(unittest.TestCase):
    def test_all_76_paths_and_grounded_bounded_forms(self):
        rows=list(assets())
        self.assertEqual({r[0] for r in rows},expected_paths('plants'))
        self.assertEqual(len(rows),76)
        for path,parts,_ in rows:
            vox=parts['main'].voxels
            self.assertEqual(min(p[1] for p in vox.cells),0,path)
            self.assertLessEqual(max(abs(v+.5) for p in vox.cells for v in (p[0],p[2])),24,path)

    def test_picking_removes_only_fruit_and_young_never_has_fruit(self):
        profile=read_json('tools/art_data/voxel_plants.json')
        for species,seasons in RIPE.items():
            for season in seasons:
                ripe=shrub(profile,species,season)
                picked=shrub(profile,species,season,picked=True)
                self.assertTrue(set(picked.cells)<=set(ripe.cells),(species,season))
                for point,color in picked.cells.items(): self.assertEqual(ripe.cells[point],color)
                self.assertNotEqual(ripe.cells,picked.cells,(species,season))
                self.assertEqual(shrub(profile,species,season,young=True).cells,
                                 shrub(profile,species,season,young=True,picked=True).cells)

    def test_packing_retains_exact_grid_shifted_plant(self):
        profile=read_json('tools/art_data/voxel_plants.json')
        for species in RIPE:
            for season in SEASONS:
                plant=shrub(profile,species,season)
                packed=pack(profile,plant,True)
                for (x,y,z),color in plant.cells.items(): self.assertEqual(packed.cells[x,y+5,z],color)
                young=shrub(profile,species,season,young=True)
                self.assertLess(len(young.cells),len(plant.cells),(species,season))

    def test_every_solid_component_touches_ground(self):
        # Exposed crop, bloom and fine winter stems must not float as detached
        # diagonal-only cells, even when a packed root raises the whole plant.
        steps=((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))
        for path,parts,_ in assets():
            remaining=set(parts['main'].voxels.cells)
            while remaining:
                first=remaining.pop(); stack=[first]; lowest=first[1]
                while stack:
                    point=stack.pop(); lowest=min(lowest,point[1])
                    for delta in steps:
                        neighbor=tuple(point[i]+delta[i] for i in range(3))
                        if neighbor in remaining: remaining.remove(neighbor); stack.append(neighbor)
                self.assertEqual(lowest,0,path)

    def test_height_grid_and_repeatability_for_every_defined_variant(self):
        profile=read_json('tools/art_data/voxel_plants.json')
        a=list(assets()); b=list(assets())
        for (path,parts,meta),(other,copy,_) in zip(a,b):
            self.assertEqual(path,other)
            vox=parts['main'].voxels
            self.assertEqual(vox.cells,copy['main'].voxels.cells,path)
            self.assertTrue(all(all(isinstance(v,int) for v in p) for p in vox.cells),path)
            species=meta['species']
            if species=='reeds': height=math.ceil(profile[species]['heights'][meta['variant']]*16)
            else: height=16 if meta.get('young') else math.floor(profile[species]['height']*16)
            if meta.get('packed'): height+=3 if species=='flowers' else 5
            self.assertLess(max(p[1] for p in vox.cells),height,path)

    def test_crop_attachment_and_seasonal_availability(self):
        profile=read_json('tools/art_data/voxel_plants.json')
        for species in RIPE:
            for season in SEASONS:
                base,fruit=shrub_layers(profile,species,season)
                self.assertEqual(bool(fruit.cells),season in RIPE[species],(species,season))
                self.assertFalse(set(base.cells)&set(fruit.cells))
                self.assertFalse(shrub_layers(profile,species,season,True)[1].cells)

    def test_flower_packs_and_dormancy_retain_variant_contracts(self):
        profile=read_json('tools/art_data/voxel_plants.json')
        for variant in range(3):
            for season in SEASONS:
                plant=flowers(profile,variant,season); packed=pack(profile,plant,False)
                for (x,y,z),color in plant.cells.items(): self.assertEqual(packed.cells[x,y+3,z],color)
            self.assertLess(len(flowers(profile,variant,'winter').cells),len(flowers(profile,variant,'summer').cells))
        for variant in range(2):
            self.assertLess(len(reeds(profile,variant,'winter').cells),len(reeds(profile,variant,'summer').cells))

    def test_young_shrub_canopies_have_depth_below_the_clearance_limit(self):
        # A mature crown merely clipped at the one-block limit can leave a
        # one-cell lid on bare stems. Young forms need their own complete crown.
        profile=read_json('tools/art_data/voxel_plants.json')
        for species in ('blueberry','elderberry'):
            for season in ('spring','summer','autumn'):
                plant=shrub(profile,species,season,young=True)
                colors={linear(c) for c in profile[species][season]}
                levels={p[1] for p,c in plant.cells.items() if c in colors}
                self.assertGreaterEqual(len(levels),4,(species,season))


if __name__=='__main__': unittest.main()

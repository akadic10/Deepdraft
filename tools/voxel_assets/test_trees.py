"""Source contracts for species/growth/season and visible harvest states."""
import unittest
from common import read_json
from trees import tree_layers,tree

SPECIES=('pine','oak','apple','juniper')
NEIGHBORS=((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))


class TreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile=read_json('tools/art_data/voxel_trees.json')
        cls.definitions={s:read_json(f'data/entities/flora/{s}_tree.json')[f'base:flora:{s}_tree'] for s in SPECIES}

    def layers(self,s,stage='mature',season='summer',picked=False,variant=0):
        return tree_layers(self.profile,s,stage,variant,season,picked,
                           self.definitions[s]['placement']['footprint'][stage])

    def test_all_growth_forms_keep_ground_height_clearance_and_canopy_envelope(self):
        for species in SPECIES:
            previous_height=0
            for stage in ('sapling','mature','ancient'):
                with self.subTest(species=species,stage=stage):
                    layers=self.layers(species,stage)
                    heights=[]
                    limit=self.definitions[species]['placement']['footprint'][stage]*8
                    for layer in layers:
                        for x,y,z in layer.cells:
                            self.assertTrue(all(isinstance(v,int) for v in (x,y,z)))
                            self.assertTrue(-256<x<256 and -256<z<256)
                            self.assertLess(y,self.profile[species][stage]['height']*16)
                            if stage!='sapling' and y<64:
                                self.assertTrue(-limit<=x<limit and -limit<=z<limit)
                        if layer.cells: heights.append(max(p[1] for p in layer.cells)+1)
                    self.assertEqual(min(p[1] for p in layers[0].cells),0)
                    height=max(heights)
                    self.assertGreater(height,previous_height)
                    previous_height=height

    def test_seasons_preserve_wood_and_bare_deciduous_trees(self):
        for species in SPECIES:
            summer=self.layers(species,stage='sapling')
            for season in ('spring','autumn','winter'):
                with self.subTest(species=species,season=season):
                    other=self.layers(species,stage='sapling',season=season)
                    self.assertEqual(summer[0].cells,other[0].cells)
                    self.assertFalse(other[2].cells,'saplings must not fruit or blossom')
                    if season=='winter' and species in ('oak','apple'):
                        self.assertFalse(other[1].cells)
                    else:
                        self.assertEqual(summer[1].cells.keys(),other[1].cells.keys())

    def assert_attached_visible_accents(self,layers):
        wood,leaves,accents=layers
        self.assertTrue(accents.cells)
        # Every separate fruit/blossom cluster touches the canopy; each also
        # exposes a face after compositing, rather than hiding inside a lobe.
        remaining=set(accents.cells)
        occupied=wood.cells.keys()|leaves.cells.keys()|accents.cells.keys()
        while remaining:
            pending=[remaining.pop()]; touches=False; exposed=False
            while pending:
                p=pending.pop()
                for d in NEIGHBORS:
                    q=tuple(p[i]+d[i] for i in range(3))
                    touches |= q in leaves.cells
                    exposed |= q not in occupied
                    if q in remaining: remaining.remove(q); pending.append(q)
            self.assertTrue(touches,'floating accent cluster')
            self.assertTrue(exposed,'fully buried accent cluster')

    def test_apple_blossom_and_fruit_are_visible_attached_seasonal_accents(self):
        for stage in ('mature','ancient'):
            for season in ('spring','autumn_fruiting'):
                count=len(self.definitions['apple']['stages'][stage]['models'][season])
                for variant in range(count):
                    with self.subTest(stage=stage,season=season,variant=variant):
                        self.assert_attached_visible_accents(self.layers('apple',stage,season,variant=variant))
        for season in ('summer','autumn','winter'):
            self.assertFalse(self.layers('apple',season=season)[2].cells)

    def test_juniper_picking_only_removes_berries_in_both_seasons(self):
        for stage in ('mature','ancient'):
            for season in ('summer','winter'):
                count=len(self.definitions['juniper']['stages'][stage]['models'][season])
                for variant in range(count):
                    with self.subTest(stage=stage,season=season,variant=variant):
                        fruit=self.layers('juniper',stage,season,variant=variant)
                        picked=self.layers('juniper',stage,season,picked=True,variant=variant)
                        self.assertEqual(fruit[0].cells,picked[0].cells)
                        self.assertEqual(fruit[1].cells,picked[1].cells)
                        self.assertFalse(picked[2].cells)
                        self.assert_attached_visible_accents(fruit)

    def test_bare_branches_remain_connected_to_the_grounded_trunk(self):
        for species in ('oak','apple'):
            wood=self.layers(species,season='winter')[0]
            start=min(wood.cells,key=lambda p:p[1])
            remaining=set(wood.cells); remaining.remove(start); pending=[start]
            while pending:
                x,y,z=pending.pop()
                for dx,dy,dz in NEIGHBORS:
                    q=(x+dx,y+dy,z+dz)
                    if q in remaining: remaining.remove(q); pending.append(q)
            self.assertFalse(remaining,'detached bare twig geometry')

    def test_variant_identity_is_repeatable_and_changes_the_shape(self):
        for species in SPECIES:
            footprint=self.definitions[species]['placement']['footprint']['sapling']
            def make(variant): return tree(self.profile,species,'sapling',variant,'summer',False,footprint).cells
            first=make(0)
            self.assertEqual(first,make(0))
            self.assertNotEqual(first.keys(),make(1).keys())


if __name__=='__main__': unittest.main()

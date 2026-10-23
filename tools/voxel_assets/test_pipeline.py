"""Production export contracts independent of the imported renderer."""
from pathlib import Path
import sys
import tempfile
import struct
import unittest
from common import TOOLS,Voxels,Part,box,branch,ellipsoid,export_asset,read_json
from test_shadows import load_glb,payloads
from trees import pine,tree_layers


class PipelineTests(unittest.TestCase):
    def test_authored_solids_and_tapered_branch_have_integer_cells(self):
        vox=Voxels()
        box(vox,(0,.5,0),(1,1,1),(1,0,0),cut=.125)
        ellipsoid(vox,(1,.5,0),(.4,.5,.3),(0,1,0),power=3)
        branch(vox,(-1,0,-1),(1,2,1),.2,.05,(0,0,1))
        self.assertTrue(vox.cells)
        self.assertTrue(all(all(isinstance(v,int) for v in p) for p in vox.cells))
        self.assertTrue(any(abs(p[0]/16-1)<.15 and abs(p[1]/16-2)<.15 for p in vox.cells))

    def test_named_rigid_parts_keep_local_identity(self):
        vox=Voxels(); box(vox,(0,.5,0),(1,1,1),(1,0,0))
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'door.glb'
            report=export_asset(path,{'leaf_left':Part(vox),'leaf_right':Part(vox),'flame':Part(vox,False)})
            doc,blob=load_glb(path)
            roots=[doc['nodes'][i] for i in doc['nodes'][0]['children']]
            self.assertEqual([r['name'] for r in roots],['leaf_left','leaf_right','flame'])
            for parent in roots[:2]:
                children=[doc['nodes'][i] for i in parent['children']]
                self.assertEqual([c['name'] for c in children],
                                 ['VoxelVisual__'+parent['name'],'VoxelShadowProxy__'+parent['name']])
                self.assertTrue(all(set(c)=={'name','mesh'} for c in children))
                visual=payloads(doc,blob,children[0]['mesh'])[0]
                proxy=payloads(doc,blob,children[1]['mesh'])[0]
                for attribute in ('POSITION','NORMAL','indices'):
                    self.assertEqual(visual[attribute],proxy[attribute])
            self.assertIn('mesh',roots[2])
            self.assertIsNone(report['parts'][2]['shadow'])

    def test_pine_export_retains_native_grid_ground_and_proxy_pair(self):
        profile=read_json('tools/art_data/voxel_trees.json')
        # The Hearthblock pine keeps the grid, root, ground and rendering contracts.
        vox=pine(profile,'sapling',0,'summer')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'pine.glb'
            report=export_asset(path,{'main':Part(vox)})
            doc,blob=load_glb(path)
            self.assertEqual(report['parts'][0]['min'][1],0)
            self.assertIsNotNone(report['parts'][0]['shadow'])
            root=doc['nodes'][0]
            self.assertNotIn('scale',root)
            self.assertEqual([doc['nodes'][i]['name'] for i in root['children']],
                             ['VoxelVisual','VoxelShadowProxy'])
            positions=payloads(doc,blob,0)[0]['POSITION'][2]
            for (value,) in struct.iter_unpack('<f',positions):
                self.assertEqual(value*16,round(value*16))

    def test_winter_retains_pine_shape_and_bark(self):
        profile=read_json('tools/art_data/voxel_trees.json')
        summer=pine(profile,'sapling',0,'summer')
        winter=pine(profile,'sapling',0,'winter')
        self.assertEqual(set(summer.cells),set(winter.cells))
        self.assertNotEqual(summer.cells,winter.cells)
        # Compare the actual authored wood layer, not an obsolete bark swatch.
        a=tree_layers(profile,'pine','sapling',0,'summer',False,1)[0]
        b=tree_layers(profile,'pine','sapling',0,'winter',False,1)[0]
        self.assertTrue(a.cells)
        self.assertEqual(a.cells,b.cells)


if __name__=='__main__': unittest.main()

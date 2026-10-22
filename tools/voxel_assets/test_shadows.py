"""Proxy occupancy, thin silhouette retention, and dual-mesh GLB contracts."""
import json
from pathlib import Path
import struct
import tempfile
import unittest

import common  # puts tools/ on the import path
from voxel_glb import Voxels, greedy_mesh_from_voxels, write_glb, write_glb_meshes
from voxel_shadow import downsample, shadow_mesh


def load_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert (magic, version, length) == (0x46546C67, 2, len(raw))
    size, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(raw[20:20 + size])
    binary_size, kind = struct.unpack_from('<II', raw, 20 + size)
    blob = raw[28 + size:]
    assert kind == 0x004E4942 and binary_size == len(blob) == doc['buffers'][0]['byteLength']
    return doc, blob


def payloads(doc, blob, mesh_index):
    """Extract actual accessor data, not metadata or full-file byte ordering."""
    result = []
    for primitive in doc['meshes'][mesh_index]['primitives']:
        refs = dict(primitive['attributes'], indices=primitive['indices'])
        fields = {}
        for name, index in refs.items():
            accessor = doc['accessors'][index]
            view = doc['bufferViews'][accessor['bufferView']]
            width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[accessor['type']] * 4
            stride = view.get('byteStride', width)
            offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            data = b''.join(blob[offset + i*stride:offset + i*stride + width] for i in range(accessor['count']))
            assert len(data) == width * accessor['count']
            fields[name] = (accessor['componentType'], accessor['type'], data)
        result.append(fields)
    return result


def occupied_centers(mesh):
    """Ray-parity voxelization of output quads; independent of binning code."""
    positions, normals, _, _ = mesh
    if not positions:
        return set()
    ranges = [range(min(p[i] for p in positions), max(p[i] for p in positions)) for i in range(3)]
    x_faces = []
    for start in range(0, len(positions), 4):
        if not normals[start][0]:
            continue
        quad = positions[start:start + 4]
        x_faces.append((quad[0][0], min(p[1] for p in quad), max(p[1] for p in quad),
                        min(p[2] for p in quad), max(p[2] for p in quad)))
    return {(x,y,z) for x in ranges[0] for y in ranges[1] for z in ranges[2]
            if sum(plane > x+.5 and y0 < y+.5 < y1 and z0 < z+.5 < z1
                   for plane,y0,y1,z0,z1 in x_faces) % 2}


class ShadowTests(unittest.TestCase):
    def test_clipped_negative_boundaries_preserve_full_solid(self):
        vox = Voxels()
        vox.box(-7, 5, -3, 10, -5, 6, (1,0,0), shade=False)
        mesh, coverage = downsample(vox, 4)
        self.assertEqual(occupied_centers(mesh), set(vox.cells))
        self.assertEqual(coverage, 1)
        self.assertEqual(len(mesh[3]) // 3, 12)

    def test_holes_never_filled_or_proxy_inflated(self):
        vox = Voxels()
        vox.box(-8, 8, -4, 8, -4, 4, (1,0,0), shade=False)
        for y in range(-4,8):
            del vox.cells[-1,y,0]
        for stride in [1,2,4]:
            mesh, coverage = downsample(vox, stride)
            occupied = occupied_centers(mesh)
            self.assertTrue(occupied)
            self.assertLessEqual(occupied, set(vox.cells))
            self.assertAlmostEqual(coverage, len(occupied)/len(vox.cells))

    def test_thin_shin_retained_despite_high_upper_leg_volume(self):
        vox = Voxels()
        vox.box(0, 8, 4, 12, 0, 8, (1,0,0), shade=False)
        vox.box(1, 2, 0, 4, 1, 2, (1,0,0), shade=False)
        mesh, info = shadow_mesh(vox)
        self.assertEqual(info['stride'], 1)
        self.assertEqual(min(p[1] for p in mesh[0]), 0)
        self.assertEqual(occupied_centers(mesh), set(vox.cells))

    def test_palette_removed_and_cell_order_irrelevant(self):
        vox = Voxels()
        for x in range(8):
            for y in range(8):
                for z in range(8):
                    vox.cells[x,y,z] = (1,0,0) if (x+y+z)%2 else (0,1,0)
        mesh, info = shadow_mesh(vox)
        self.assertEqual(len(mesh[3]) // 3, 12)
        self.assertLess(len(mesh[3]), len(greedy_mesh_from_voxels(vox)[3]))
        reverse = Voxels()
        reverse.cells = dict(reversed(list(vox.cells.items())))
        self.assertEqual((mesh,info), shadow_mesh(reverse))

    def test_invalid_or_empty_inputs(self):
        vox = Voxels()
        vox.cells[0,0,0] = (1,1,1)
        for stride in [0,-1,3,1.5]:
            with self.assertRaises(ValueError): shadow_mesh(vox,stride)
        for coverage in [0,-.1,1.1]:
            with self.assertRaises(ValueError): shadow_mesh(vox,minimum_coverage=coverage)
        with self.assertRaises(ValueError): shadow_mesh(Voxels())

    def test_glb_siblings_share_pivot_and_preserve_visual_payload(self):
        vox = Voxels()
        vox.box(-8,8,0,16,-4,4,(.2,.3,.4),shade=False)
        visual = greedy_mesh_from_voxels(vox)
        proxy, _ = shadow_mesh(vox)
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory)/'old.glb', Path(directory)/'new.glb'
            write_glb(old,'old',visual,1/16)
            write_glb_meshes(new,'asset',{'VoxelVisual':visual,'VoxelShadowProxy':proxy},1/16)
            doc, blob = load_glb(new)
            old_doc, old_blob = load_glb(old)
            self.assertEqual(doc['scenes'], [{'nodes':[0]}])
            self.assertEqual(doc['nodes'][0], {'name':'asset','children':[1,2]})
            self.assertEqual(doc['nodes'][1:], [{'name':'VoxelVisual','mesh':0},{'name':'VoxelShadowProxy','mesh':1}])
            self.assertEqual(payloads(doc,blob,0),payloads(old_doc,old_blob,0))
            write_glb(old,'proxy',proxy,1/16)
            old_doc,old_blob = load_glb(old)
            self.assertEqual(payloads(doc,blob,1),payloads(old_doc,old_blob,0))
            self.assertTrue(all(view['byteOffset']%4==0 for view in doc['bufferViews']))


if __name__ == '__main__': unittest.main()

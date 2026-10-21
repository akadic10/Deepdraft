"""Surface equivalence, winding, palette boundaries and determinism contracts."""
from collections import Counter
from pathlib import Path
import random
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voxel_glb import Voxels, greedy_mesh_from_voxels, mesh_from_voxels
from generate import linear


def unit_faces(mesh):
    positions, normals, colors, indices = mesh
    result = Counter()
    for base in range(0, len(positions), 4):
        quad = positions[base:base + 4]
        normal = normals[base]
        axis = next(i for i, n in enumerate(normal) if n)
        u, v = [i for i in range(3) if i != axis]
        plane = quad[0][axis]
        assert all(p[axis] == plane for p in quad)
        for a in range(min(p[u] for p in quad), max(p[u] for p in quad)):
            for b in range(min(p[v] for p in quad), max(p[v] for p in quad)):
                result[(normal, plane, a, b, colors[base])] += 1
    # Every triangle has a nonzero area and outward glTF winding.
    for start in range(0, len(indices), 3):
        a, b, c = [positions[i] for i in indices[start:start + 3]]
        ab, ac = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        cross = (ab[1]*ac[2]-ab[2]*ac[1], ab[2]*ac[0]-ab[0]*ac[2], ab[0]*ac[1]-ab[1]*ac[0])
        assert sum(cross[i] * normals[indices[start]][i] for i in range(3)) > 0
    return result


class MesherTests(unittest.TestCase):
    def compare(self, vox):
        merged = greedy_mesh_from_voxels(vox)
        actual = unit_faces(merged)
        self.assertEqual(actual, unit_faces(mesh_from_voxels(vox)))
        self.assertTrue(all(count == 1 for count in actual.values()))
        shuffled = Voxels()
        shuffled.cells = dict(reversed(list(vox.cells.items())))
        self.assertEqual(merged, greedy_mesh_from_voxels(shuffled))

    def test_solid_six_rectangles(self):
        vox = Voxels()
        vox.box(-8, 8, 0, 16, -8, 8, (.1, .2, .3), shade=False)
        mesh = greedy_mesh_from_voxels(vox)
        self.assertEqual(len(mesh[3]) // 3, 12)
        self.compare(vox)

    def test_hollow_box_and_palette_boundaries(self):
        vox = Voxels()
        for x in range(-3, 4):
            for y in range(-3, 4):
                for z in range(-3, 4):
                    if max(abs(x), abs(y), abs(z)) == 3:
                        vox.cells[x,y,z] = (1, 0, 0) if x < 0 else (0, 1, 0)
        del vox.cells[0,3,0]  # Open hole with both interior and exterior faces.
        self.compare(vox)

    def test_random_multicolor_sparse_grids(self):
        for seed in range(20):
            rng = random.Random(seed)
            vox = Voxels()
            for x in range(-4, 5):
                for y in range(-3, 4):
                    for z in range(-2, 3):
                        if rng.random() < .7:
                            vox.cells[x,y,z] = rng.choice([(1,0,0), (0,.5,0), (.2,.3,.4)])
            self.compare(vox)

    def test_empty(self):
        self.assertEqual(greedy_mesh_from_voxels(Voxels()), ([],[],[],[]))

    def test_rigid_part_occlusion(self):
        left, right, combined = Voxels(), Voxels(), Voxels()
        left.cells[0,0,0] = (1,0,0)
        right.cells[1,0,0] = (0,1,0)
        combined.update(left); combined.update(right)
        separate = unit_faces(greedy_mesh_from_voxels(left, right.cells))
        separate.update(unit_faces(greedy_mesh_from_voxels(right, left.cells)))
        self.assertEqual(separate, unit_faces(mesh_from_voxels(combined)))

    def test_srgb_to_linear_once(self):
        self.assertAlmostEqual(linear('808080')[0], .2158605001)
        self.assertEqual(linear('FFFFFF'), (1,1,1))
        self.assertEqual(linear('000000'), (0,0,0))


if __name__ == '__main__': unittest.main()

"""Inscribed, palette-free coarse voxel meshes for shadow-only rendering.

Only fully occupied bins are retained. Their boundary bins are clipped to the
source AABB, so proxies never inflate over the visible surface. Thin objects
automatically use a finer grid if the requested density loses too much volume.
"""
from collections import Counter
import math
from voxel_glb import Voxels, greedy_mesh_from_voxels


def downsample(vox, stride):
    if not isinstance(stride, int) or stride < 1:
        raise ValueError('shadow stride must be a positive integer')
    if not vox.cells:
        raise ValueError('cannot proxy an empty asset')
    lo = [min(p[i] for p in vox.cells) for i in range(3)]
    hi = [max(p[i] for p in vox.cells) + 1 for i in range(3)]
    counts = Counter(tuple(v // stride for v in cell) for cell in vox.cells)
    coarse = Voxels()
    retained = 0
    for cell, count in counts.items():
        volume = math.prod(min((cell[i] + 1) * stride, hi[i]) - max(cell[i] * stride, lo[i]) for i in range(3))
        if count == volume:
            coarse.cells[cell] = (1.0, 1.0, 1.0)
            retained += count
    mesh = greedy_mesh_from_voxels(coarse)
    # Greedy rectangles in the coarse grid map to source-cell coordinates.
    # Clipping affects only the first/last bin on an axis and stays monotonic.
    mesh[0][:] = [tuple(max(lo[i], min(hi[i], p[i] * stride)) for i in range(3)) for p in mesh[0]]
    return mesh, retained / len(vox.cells)


def shadow_mesh(vox, stride=4, minimum_coverage=.6):
    if not isinstance(stride, int) or stride < 1 or stride & (stride - 1):
        raise ValueError('shadow stride must be a positive power of two')
    if not 0 < minimum_coverage <= 1:
        raise ValueError('shadow coverage must be in (0, 1]')
    while True:
        mesh, coverage = downsample(vox, stride)
        # Volume alone can retain a chunky upper leg while losing its thin shin.
        # Keep at least 80% of the occupied span along every axis as well.
        span_ok = bool(mesh[0]) and all(
            max(p[i] for p in mesh[0]) - min(p[i] for p in mesh[0]) >= .8 *
            (max(p[i] for p in vox.cells) + 1 - min(p[i] for p in vox.cells))
            for i in range(3))
        if mesh[0] and coverage >= minimum_coverage and span_ok:
            return mesh, {'stride': stride, 'retained_volume': coverage, 'triangles': len(mesh[3]) // 3}
        stride = max(1, stride // 2)

"""Boulder pilot: baked 1/8-block voxels, ground origin, 2x2x2 envelope.

Run from any directory. These are dedicated world props, not scaled item art.
Only writes the three owned GLBs; Godot owns their import metadata.
"""
from pathlib import Path
import math
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/models/details/boulders'


def boulder(variant):
    vox = Voxels()
    # Overlapping broad lobes and a slanted broken shoulder avoid a cube or
    # perfect sphere. Coarse planes keep the silhouette legible at RTS zoom.
    lobes = [
        [(-1, 4, 0, 7.8, 8.4, 7.4), (3, 3, -3, 4.8, 5.5, 4.8)],
        [(0, 3, 0, 7.7, 6.5, 7.6), (-3, 4, 2, 5.0, 7.5, 5.2)],
        [(1, 4, -1, 7.1, 9.7, 6.8), (-4, 2, 2, 4.0, 5.0, 5.4)],
    ][variant]
    palette = [(0.48, 0.52, 0.55), (0.52, 0.54, 0.54), (0.46, 0.50, 0.54)][variant]
    for x in range(-8, 8):
        for z in range(-8, 8):
            for y in range(16):
                inside = any(((x+.5-cx)/rx)**2 + ((y+.5-cy)/ry)**2 + ((z+.5-cz)/rz)**2 < 1
                             for cx, cy, cz, rx, ry, rz in lobes)
                # A broad chipped face, not noisy per-voxel speckles.
                if not inside or (x-z > 9 and y > 5) or (x+z < -9 and y > 7):
                    continue
                band = math.sin((x//3)*1.3+(z//3)*.8+variant)*.025
                shade = .9 + y*.017 + band
                if 5 <= y <= 6 and x > 1 and z < 1:
                    shade -= .065
                # The existing flora/world material consumes linear COLOR_0.
                # Exporting display RGB directly washes these stones out.
                rgb = tuple(min(.85, c*shade) for c in palette)
                linear = tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb)
                vox.set(x, y, z, linear)
    return vox


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        vox = boulder(i)
        write_glb(OUT / f'boulder_{i+1}.glb', f'boulder_{i+1}', mesh_from_voxels(vox), .125)
        print(f'boulder_{i+1}: {len(vox)} voxels, scale baked 0.125')

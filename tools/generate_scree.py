"""Three walkable loose-stone clumps; baked 1/8-block voxels and linear colors.

Each stone touches Y0. Open gaps expose the supporting ground inside a 3x3
footprint. Only writes owned GLBs; Godot creates import metadata.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/models/details/scree'
GROUPS = [
    [(-6, -5, 4, 3, 4), (3, -4, 3, 2, 3), (-1, 4, 4, 3, 3), (7, 6, 2, 2, 2), (-8, 7, 2, 1, 2)],
    [(-5, 0, 4, 4, 3), (5, -6, 3, 2, 3), (4, 4, 4, 2, 3), (-5, 8, 2, 1, 2), (-9, -8, 2, 2, 2)],
    [(-6, -6, 3, 2, 3), (3, -2, 4, 3, 4), (-5, 4, 3, 2, 3), (5, 7, 3, 2, 2), (9, -8, 2, 1, 2), (-9, 9, 1, 1, 1)],
]


def scree(variant):
    vox = Voxels()
    for index, (cx, cz, rx, height, rz) in enumerate(GROUPS[variant]):
        for x in range(cx-rx, cx+rx):
            for z in range(cz-rz, cz+rz):
                for y in range(height):
                    if ((x+.5-cx)/rx)**2 + ((z+.5-cz)/rz)**2 + (y/(height+.2))**2 > 1:
                        continue
                    shade = .88 + .065*y + (index % 3)*.025
                    rgb = [c*shade for c in (.47, .50, .53)]
                    linear = tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb)
                    vox.set(x, y, z, linear)
    return vox


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        vox = scree(i)
        write_glb(OUT / f'scree_{i+1}.glb', f'scree_{i+1}', mesh_from_voxels(vox), .125)
        print(f'scree_{i+1}: {len(vox)} voxels, scale baked 0.125')

"""Build the rabbit's three articulated voxel parts. Run from any directory.

Eight voxels per block, baked scale 0.125, root scale 1. Parts share a feet
origin; the actor supplies head/ear pivots. Colours are linear vertex colours.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/animals/rabbit'
FUR = (0.55, 0.41, 0.27)
CREAM = (0.86, 0.79, 0.64)
PINK = (0.65, 0.40, 0.35)
DARK = (0.13, 0.10, 0.08)


def parts():
    body, head, ears = Voxels(), Voxels(), Voxels()
    # Facing -Z. Rounded, stepped haunches and oversized rear paws.
    body.box(-2, 2, 1, 4, -2, 3, FUR)
    body.box(-2, 2, 2, 5, 0, 3, FUR)
    body.box(-1, 1, 1, 3, -3, -2, CREAM)
    for x in (-2, 1):
        body.box(x, x + 1, 0, 2, -3, -1, CREAM)
        body.box(x, x + 1, 0, 2, 0, 3, FUR)
    body.box(-1, 1, 2, 4, 3, 4, CREAM)
    head.box(-2, 2, 4, 7, -3, 0, FUR)
    head.box(-1, 1, 4, 6, -4, -3, CREAM)
    head.box(-1, 1, 5, 6, -4, -3, PINK, False)
    for x in (-2, 1):
        head.set(x, 6, -3, DARK)
    # Different ear tips give the idle silhouette a little asymmetry.
    ears.box(-2, -1, 7, 12, -2, -1, FUR)
    ears.box(1, 2, 7, 11, -2, -1, FUR)
    for x, top in ((-2, 11), (1, 10)):
        for y in range(8, top):
            ears.set(x, y, -2, PINK)
    return {'body': body, 'head': head, 'ears': ears}


def linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


if __name__ == '__main__':
    for name, vox in parts().items():
        positions, normals, colours, indices = mesh_from_voxels(vox)
        assert all(-4 <= p[0] <= 4 and 0 <= p[1] <= 12 and -4 <= p[2] <= 4 for p in positions)
        colours = [tuple(linear(c) for c in colour[:3]) + (1.0,) for colour in colours]
        size = write_glb(OUT / f'{name}.glb', name, (positions, normals, colours, indices), 0.125)
        print(f'{name}: {len(vox)} voxels, {size} bytes; baked scale 0.125')

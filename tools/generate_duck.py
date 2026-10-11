"""Articulated male/female ducks on the project's eight-voxel block grid."""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_rabbit import linear

OUT = Path(__file__).resolve().parents[1] / 'assets/animals/duck'


def parts(female):
    coat = (.49, .37, .23) if female else (.57, .59, .54)
    breast = (.62, .47, .28) if female else (.38, .23, .16)
    crown = (.49, .36, .22) if female else (.17, .38, .27)
    bill = (.69, .48, .22) if female else (.84, .67, .23)
    body, head, wing = Voxels(), Voxels(), Voxels()
    body.box(-2, 2, 2, 6, -2, 3, coat)
    body.box(-3, 3, 3, 5, -1, 2, coat)
    body.box(-2, 2, 3, 6, -3, -1, breast)
    body.box(-1, 1, 3, 5, 3, 4, (.25, .26, .23))
    body.box(-1, 1, 5, 6, 2, 4, coat)
    head.box(-1, 1, 5, 8, -3, -1, crown)
    head.box(-2, 2, 7, 9, -3, -1, crown)
    head.box(-1, 1, 7, 8, -4, -3, bill, False)
    for x in (-2, 1):
        head.set(x, 8, -3, (.07, .075, .065))
    if not female:
        head.box(-1, 1, 5, 6, -3, -1, (.84, .82, .67), False)
    else:
        for x in (-2, 1):
            head.set(x, 7, -2, (.67, .53, .32))
        for x in (-2, 1):
            for z in (-1, 1): body.set(x, 5, z, (.36, .28, .19))
    # Wing origin is the shoulder. Fold by rotating around local Z; when open
    # its horizontal span is one block with stepped outer primary feathers.
    wing.box(0, 5, 0, 1, -2, 2, coat)
    wing.box(4, 7, 0, 1, -1, 2, (.29, .31, .29))
    wing.box(6, 8, 0, 1, 0, 2, (.24, .25, .23))
    wing.box(1, 5, 0, 1, 1, 2, (.29, .34, .52), False)
    wing.box(1, 5, 0, 1, 2, 3, (.79, .78, .66), False)
    return {'body': body, 'head': head, 'wing': wing}


if __name__ == '__main__':
    all_parts = {}
    for sex in ('male', 'female'):
        for part, voxels in parts(sex == 'female').items(): all_parts[f'{sex}_{part}'] = voxels
    foot = Voxels()
    foot.box(0, 1, 0, 2, 0, 1, (.78, .40, .13))
    foot.box(-1, 2, 0, 1, -1, 1, (.87, .48, .17))
    all_parts['foot'] = foot
    for name, voxels in all_parts.items():
        pos, normals, colors, indices = mesh_from_voxels(voxels)
        colors = [tuple(linear(c) for c in color[:3]) + (1.0,) for color in colors]
        size = write_glb(OUT / f'{name}.glb', name, (pos, normals, colors, indices), .125)
        print(f'{name}: {len(voxels)} voxels, {size} bytes')

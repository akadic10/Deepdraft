"""Original, seamless 8-voxels/block structural floor art. No textures/colliders.

Each solid 8x8x8 model fills [0,1]^3 in engine coordinates; its authored top is
flush with the block above. Runtime batches only exposed faces of these models.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]


def rgb(hex_color):
    return tuple(int(hex_color[i:i+2], 16)/255 for i in (0, 2, 4))


def plank(phase=0):
    v = Voxels()
    colors = list(map(rgb, ('926941', 'A67C52', 'B58A5A', 'AD8052', '976D44', 'B08759')))
    for x in range(8):
        for z in range(8):
            board = x // 4
            end = (z + phase*8 + board*8) % 16 == 0
            for y in range(8):
                # Broad straight boards, staggered ends and quiet grain strokes.
                index = 1+board if y == 7 else (4 if y < 6 else 1)
                if y == 7:
                    if x % 4 == 0 or end: index = 0
                    elif x % 4 == 1 and z in (2, 3, 4): index = 3
                    elif x % 4 == 3 and z in (5, 6): index = 5
                elif y == 6 and (x % 4 == 0 or end): index = 0
                v.set(x, y, z, colors[index])
    return v


def stone():
    v = Voxels()
    colors = list(map(rgb, ('757D84', '989FA5', '8E969D', 'A1A7AC', '878F96', '92999F')))
    for x in range(8):
        for z in range(8):
            row = z // 4
            joint = z % 4 == 0 or (x + row*4) % 8 == 0
            for y in range(8):
                index = 4 if y < 6 else 5
                if y == 7:
                    index = 0 if joint else 1+row
                    if not joint and z % 4 == 1: index = 3
                elif y == 6 and joint: index = 0
                v.set(x, y, z, colors[index])
    return v


def main():
    out = ROOT/'assets/models/construction'
    out.mkdir(parents=True, exist_ok=True)
    for name, author in (('plank_floor', plank), ('plank_floor_alternate', lambda: plank(1)), ('stone_floor', stone)):
        vox = author()
        assert len(vox.cells) == 512
        positions, normals, colors, indices = mesh_from_voxels(vox)
        def linear(c):
            return c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4
        colors = [tuple(linear(c) for c in color[:3])+(1.,) for color in colors]
        write_glb(out/(name+'.glb'), name, (positions, normals, colors, indices), .125)
        print(f'{name}: 8x8x8 solid voxels, {len(indices)//3} surface triangles')


if __name__ == '__main__':
    main()

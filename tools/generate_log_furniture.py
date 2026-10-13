"""Starter log doors, split-log bench and primitive torch; native 8 voxels/block.

Original voxel geometry with linear vertex colors. Frameless door leaves are
separate meshes so installed furniture can swing without changing room sealing.
"""
from pathlib import Path
from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, box, export_mesh, rgb
from generate_wall_torch import torch, write_parts

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tmp/log_furniture_20261011/art"
CUT, RING, HEART = map(rgb, ("DABE84", "AE8C54", "CCAA6D"))


def door_parts(width=2):
    assert width in (2, 3, 4)
    low, high = -width * 4, width * 4
    # Starter doors are only pegged log leaves. Jambs and a top beam belong
    # to future better doors; the surrounding terrain is the opening's frame.
    parts = []
    ranges = [(low, high)] if width < 4 else [(low, 0), (0, high)]
    for index, (left, right) in enumerate(ranges):
        leaf = Voxels()
        # Closely set rough split logs: continuous core, faceted bark faces.
        box(leaf, left, right, 0, 30, -1, 1, OAK[1])
        for log_index, x in enumerate(range(left, right, 4)):
            end = min(x+4, right)
            height = 31 if (log_index+index)%3 == 1 else 30
            box(leaf, x, end, 0, height, -1, 1, OAK[2+log_index%2])
            if end-x > 2:
                box(leaf, x+1, end-1, 0, height, -2, 2, OAK[3+log_index%2])
                box(leaf, x+1, end-1, height-1, height, -2, 2, CUT)
            box(leaf, x, end, height-1, height, -1, 1, RING)
        # Raw cross battens and broad wooden pegs, on both faces.
        for z in (-3, 2):
            for y in (5, 23):
                box(leaf, left, right, y, y+2, z, z+1, OAK[4])
                for x in (left+1, right-2):
                    leaf.cells[x,y,z] = CUT
            # Small wooden pull near the meeting edge, no metal hardware.
            x = right-3 if index == 0 else left+2
            box(leaf, x, x+1, 12, 16, z, z+1, OAK[5])
        parts.append(("leaf_left" if index == 0 else "leaf_right", leaf))
    return parts


def door(width=2):
    combined = Voxels()
    for _, part in door_parts(width):
        combined.cells.update(part.cells)
    return combined


def write_door(path, width=2, out=OUT):
    (out / "parts").mkdir(parents=True, exist_ok=True)
    return write_parts(path, door_parts(width), out, path.stem)


def bench():
    vox = Voxels()
    # Two short transverse log trestles with exposed end grain.
    for cx in (-5, 4):
        for x in range(cx-1, cx+2):
            for y in range(4):
                if y in (0,3) and x != cx: continue
                for z in range(-4,4):
                    vox.cells[x,y,z] = (HEART if x==cx and y in (1,2) else RING) if z in (-4,3) else OAK[2+(x-cx+1)%2]
    # A half trunk: axe-hewn flat top, rounded bark underneath and cut ends.
    for x in range(-8,8):
        for y in range(3,8):
            radius = (2,3,4,4,4)[y-3]
            for z in range(-radius,radius):
                color = OAK[2+(abs(z)+y)%3]
                if x in (-8,7): color = RING if abs(z) >= radius-1 else HEART
                if y==7: color = CUT if z in (-3,-2,1,2) else HEART
                vox.cells[x,y,z] = color
    # One short natural split at each end; no regular plank seams.
    for x in (-8,-7,6,7): vox.cells[x,7,0] = RING
    return vox


def log_torch():
    body = Voxels()
    # One low wooden peg holds a thick charred branch. No fork or backplate.
    box(body, -1,1, 2,4, 0,4, OAK[2])
    box(body, -1,1, 0,8, 3,5, OAK[2])
    box(body, -1,0, 0,6, 4,5, OAK[4])
    box(body, -2,2, 5,7, 3,5, rgb("9C8456")) # rough fibre binding
    box(body, -1,1, 6,8, 3,5, rgb("302019"))
    _, flame = torch()
    for cell in flame.cells: body.cells.pop(cell,None)
    return body, flame


def generate():
    (OUT / "parts").mkdir(parents=True, exist_ok=True)
    model_dir = ROOT / "assets/models/furniture"
    for width in (2,3,4):
        name = "door" if width==2 else f"log_door_{width}"
        vox = door(width)
        assert all(-width*4<=x<width*4 and 0<=y<31 and -3<=z<3 for x,y,z in vox.cells)
        write_door(model_dir / f"{name}.glb", width)
        print(f"{name}: {len(vox.cells)} voxels; {width}x1 footprint; {'single' if width<4 else 'double'} leaf")
    vox = bench()
    assert all(-8<=x<8 and 0<=y<8 and -4<=z<4 for x,y,z in vox.cells)
    write_glb(model_dir / "bench.glb", "log_bench", export_mesh(vox), export_scale=.125)
    body, flame = log_torch()
    write_parts(model_dir / "wooden_torch.glb", [("torch_body",body),("torch_flame",flame)], OUT, "log_torch")
    print("Log bench and log torch exported at native scale.")


if __name__ == "__main__": generate()

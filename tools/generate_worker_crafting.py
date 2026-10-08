"""Rough crafting stump and iron-free wall torch, eight voxels per block."""
import argparse
import math
from pathlib import Path
from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import box, export_mesh, OAK, rgb
from generate_wall_torch import torch, write_parts

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tmp/worker_crafting_review/art"

def bench():
    vox = Voxels()
    # One rough trunk section, with bark ridges and a flared, irregular base.
    # Pine end-grain tones match the existing raw-timber palette. No joinery.
    cut, ring, heart = map(rgb, ("DABE84", "AE8C54", "CCAA6D"))
    for x in range(-4,4):
        for z in range(-4,4):
            radius = math.hypot(x+.5,z+.5)
            sector = int((math.atan2(z+.5,x+.5)+math.pi)*4/math.pi)
            top = 7
            # Uneven rim left by the axe; keep the middle level for working.
            if (x,z) in [(-3,2),(-2,3),(3,-1)]: top = 6
            if (x,z) == (-3,-2): top = 8
            for y in range(top):
                limit = 4.2 if y < 2 else 3.85 if y < 4 else 3.65
                if radius > limit: continue
                color = OAK[[1,3,2,4,2,3,1,3,2][sector]]
                if y == 0: color = OAK[1]
                if y == top-1 and radius < 3.35:
                    color = ring if 1.6 < radius < 2.7 else cut
                    if radius < 1.5: color = heart
                vox.cells[x,y,z] = color
    # Short split and cross-grain axe scars, not neat plank seams.
    for x,z in [(0,2),(0,1),(-2,-1),(-1,-1)]:
        vox.cells[x,6,z] = OAK[2] if x == 0 else ring
    vox.cells.pop((0,6,3),None)
    return vox

def wooden_torch():
    body = Voxels()
    # A wooden rear peg and fork, with no iron plates, rivets or bands.
    box(body,-1,1,0,7,0,1,OAK[1])
    box(body,-1,1,2,4,1,4,OAK[2])
    box(body,-1,1,2,8,3,5,OAK[2])
    box(body,-1,0,3,6,4,5,OAK[4])
    for x in (-2,1): box(body,x,x+1,3,5,3,5,OAK[1])
    box(body,-1,1,6,8,3,5,rgb("302019"))
    _, flame = torch()
    # Keep the existing flame envelope/animation; only the mounting differs.
    for cell in flame.cells: body.cells.pop(cell,None)
    return body, flame

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=("all","bench","torch"), default="all")
    args = parser.parse_args()
    (OUT / "parts").mkdir(parents=True,exist_ok=True)
    model_dir = ROOT / "assets/models/furniture"
    if args.only in ("all","bench"):
        stump = bench()
        assert all(-4<=x<4 and 0<=y<8 and -4<=z<4 for x,y,z in stump.cells)
        write_glb(model_dir / "crude_workbench.glb", "crude_workbench", export_mesh(stump), export_scale=.125)
        print(f"Crafting stump: {len(stump.cells)} voxels, 1x1 footprint, .875 working surface, 1.0 splinter height.")
    if args.only in ("all","torch"):
        body, flame = wooden_torch()
        write_parts(model_dir / "wooden_torch.glb", [("torch_body",body),("torch_flame",flame)], OUT, "wooden_torch")
        print("Wooden torch exported at native scale.")

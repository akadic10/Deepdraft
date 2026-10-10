"""Rudimentary camp furniture: eight voxels/block, baked scale, linear colours.

Grounded stone-ring fire with animated flame meshes and a small stump stool.
No metal fittings or processed planks. Packed goods use the existing carry crate.
"""
from pathlib import Path
import math
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb
from generate_wall_torch import write_parts

ROOT = Path(__file__).resolve().parents[1]
BARK, DARK, WOOD, GRAIN, CUT = map(linear_rgb, (
    "684827", "4A3018", "94643F", "AD8250", "C5A46A"))
STONE, ROCK, EDGE = map(linear_rgb, ("737B7C", "50595C", "959C96"))
FIRE = list(map(linear_rgb, ("C94717", "ED7120", "FFAB32", "FFDA69", "FFF1AF")))


def chair():
    v = Voxels()
    # One tile wide and .75 blocks tall: a sawn trunk, without arms or a back.
    for x in range(-4, 4):
        for z in range(-4, 4):
            if abs(x+.5)+abs(z+.5) > 5.5: continue
            for y in range(6):
                # Vertical bark furrows, with slightly lighter upper edges.
                color = BARK if (x*3+z*7)%5 else DARK
                if y==4 and (x+z)%3==0: color = WOOD
                if y==5:
                    edge = max(abs(x+.5),abs(z+.5)) >= 3.5 or abs(x+.5)+abs(z+.5)>4.5
                    ring = int(math.hypot(x+.5,z+.5))
                    color = BARK if edge else GRAIN if ring==2 else CUT
                v.set(x,y,z,color)
    # A short drying split in the flat cut face, not an upholstered seat hollow.
    v.set(0,5,0,WOOD)
    v.set(0,5,1,WOOD)
    return v


def fire_body():
    v = Voxels()
    # Separate irregular stones leave visible gaps in a low octagonal ring.
    for x,z,sx,sz in ((-6,-6,4,3),(-1,-7,4,3),(4,-5,3,4),
                       (5,0,3,4),(2,5,4,3),(-3,5,4,3),(-7,1,3,4),(-8,-4,3,4)):
        for y in range(3):
            for dx in range(sx):
                for dz in range(sz):
                    if y==2 and dx==sx-1 and dz==sz-1: continue
                    v.set(x+dx,y,z+dz,EDGE if y==2 else STONE if (dx+dz)%3 else ROCK)
    # Crossed charred logs remain readable below the flame.
    v.box(-5,5,0,2,-2,1,DARK,shade=False)
    v.box(-2,1,1,3,-5,5,BARK,shade=False)
    v.box(-5,-4,0,2,-2,1,GRAIN,shade=False)
    v.box(-2,1,1,3,4,5,WOOD,shade=False)
    return v


def flame(frame):
    v = Voxels()
    # Anchored amber body with three connected, changing tongues.
    for x in range(-3,3):
        for z in range(-3,3):
            if abs(x+.5)+abs(z+.5)>4: continue
            for y in range(3,6):
                v.set(x,y,z,FIRE[4 if abs(x+.5)<1 and y==3 else 3 if y<5 else 2])
    for n,(x,z) in enumerate(((-2,-1),(0,0),(1,1))):
        top = ((8,10,9),(9,8,10),(10,9,8),(9,11,8),(11,8,9),(8,9,11),(10,8,11),(8,11,10))[frame][n]
        for y in range(5,top):
            shift = (1 if frame in (0,1,4,7) else -1) if y>7 else 0
            start = x+max(0,shift) if y==top-1 else x+shift
            v.box(start,start+2 if y<top-1 else start+1,y,y+1,z,z+2,
                  FIRE[2 if y<7 else 1],shade=False)
    return v


if __name__ == "__main__":
    out = ROOT / "assets/models/furniture"
    review = ROOT / "tmp/profession_crafting_review"
    (out / "animations").mkdir(parents=True,exist_ok=True)
    (review / "parts").mkdir(parents=True,exist_ok=True)
    seat = chair()
    assert all(-4<=x<4 and 0<=y<6 and -4<=z<4 for x,y,z in seat.cells)
    write_glb(out / "log_chair.glb","log_chair",mesh_from_voxels(seat),export_scale=.125)
    body = fire_body()
    frames = [(f"flame_{i:02d}",flame(i)) for i in range(8)]
    for _,f in frames:
        assert not set(body.cells)&set(f.cells)
        assert all(-8<=x<8 and 0<=y<12 and -8<=z<8 for x,y,z in f.cells)
        seen, pending = set(), {next(iter(f.cells))}
        while pending:
            cell = pending.pop()
            seen.add(cell)
            for offset in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
                neighbor = tuple(cell[i]+offset[i] for i in range(3))
                if neighbor in f.cells and neighbor not in seen: pending.add(neighbor)
        assert len(seen)==len(f.cells), 'Detached fire voxel'
    assert len({tuple(sorted(f.cells)) for _,f in frames})==8
    write_parts(out / "campfire.glb",[("campfire_body",body),("campfire_flame",frames[0][1])],review,"campfire")
    write_parts(out / "animations/campfire_flame.glb",frames,review,"campfire_flames")
    print("CAMP_FURNITURE_OK: one-tile stump stool, stone-ring fire and eight flame frames")

"""Rudimentary 4 x 3 log bed: rough bark frame and loose hay/leaf bedding."""

# Retained only as historical source / flame-building helpers.
if __name__ == "__main__":
    from retired_voxel_art import stop
    stop()

from pathlib import Path
from random import Random
from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, box, export_mesh, rgb
from generate_log_furniture import CUT, RING, HEART

ROOT = Path(__file__).resolve().parents[1]
HAY = [rgb(h) for h in ('756339','988047','B49B58','CBB575','DECB91')]
LEAVES = [rgb(h) for h in ('73704B','898456','A19A65')]

def log_bed():
    v = Voxels()
    rng = Random(121)
    # Two whole bark rails, with faceted sides and rough cut ends.
    for cz in (-10,9):
        for x in range(-16,16):
            for y in range(2,6):
                for z in range(cz-1,cz+2):
                    if y in (2,5) and z!=cz: continue
                    bark = OAK[1 if y==2 else 2+(z==cz)]
                    if x in (-16,15): bark = RING if y in (2,5) else HEART
                    v.cells[x,y,z] = bark
        # Small axe scars interrupt the bark, without planed boards or trim.
        for x in (-12,3,11): v.cells[x,5,cz] = CUT
        for start,length,y in [(-12,5,3),(-3,4,4),(6,6,3)]:
            for x in range(start,start+length):
                for z in (cz-1,cz+1): v.cells[x,y,z] = OAK[1 if y==3 else 3]
    # Two short transverse trunks sit directly on the ground: four logs total.
    for cx in (-12,11):
        for x in range(cx-1,cx+2):
            for y in range(3):
                if y==0 and x!=cx: continue
                for z in range(-12,12):
                    v.cells[x,y,z] = (HEART if x==cx else RING) if z in (-12,11) else OAK[1+(y>0)]
    # Rough branches under the bedding, visible through the low open frame.
    for x in (-10,-4,2,8): box(v,x,x+1,3,4,-9,9,OAK[3])
    # Dense loose hay with a ragged outline. The central sleeping surface stays
    # at six voxels (.75 blocks); exposed stalks replace stitched ticking.
    for x in range(-14,14):
        low = -9+rng.randrange(2)
        high = 9-rng.randrange(2)
        if x in (-14,13): low,high = -6,6
        for z in range(low,high):
            v.cells[x,4,z] = HAY[0 if (x+z)%4==0 else 1]
            v.cells[x,5,z] = HAY[2]
    for z in range(-8,9):
        x = -13+rng.randrange(3)
        while x<13:
            length = rng.randrange(2,6)
            shade = HAY[rng.choice((1,2,3,3,4))]
            for sx in range(x,min(x+length,14)):
                if (sx,5,z) in v.cells: v.cells[sx,5,z] = shade
            x += length+rng.randrange(1,3)
    # A few broad dried leaves mixed into the hay, not a tailored cover.
    for x,z in [(-7,-3),(-2,5),(4,-5),(9,2)]:
        for dx,dz in [(0,-1),(-1,0),(0,0),(1,0),(2,0),(1,1)]:
            v.cells[x+dx,5,z+dz] = LEAVES[1 if dz==0 else 0]
        v.cells[x+1,5,z] = LEAVES[2]
    # An irregular mound of extra hay supports the head; no sewn pillow.
    for x in range(-13,-7):
        for z in range(-6,7):
            if (x in (-13,-8) and abs(z)>3) or rng.random()<.14: continue
            v.cells[x,6,z] = HAY[rng.choice((2,3,3,4))]
            if x in (-11,-10) and -3<=z<=3: v.cells[x,7,z] = HAY[3]
    # Loose stalks spill across the rails and beyond the mat's short ends.
    for x,z,dx,dz in [(-9,-8,0,-1),(-2,-8,1,-1),(6,-8,0,-1),
                       (-6,7,0,1),(3,7,1,1),(10,7,0,1),
                       (12,-4,1,0),(12,4,1,0),(-13,3,-1,0)]:
        for step in range(3):
            v.cells[x+dx*step,5,z+dz*step] = HAY[3 if step<2 else 4]
    # A few uncompressed tufts at the edges break up the flat mat silhouette.
    for x,z,length in [(-5,-7,4),(2,-6,3),(8,-7,3),(-5,6,3),(3,7,4),(10,5,3)]:
        for step in range(length):
            v.cells[x+step,6,z] = HAY[3 if step<length-1 else 4]
    assert all(-16<=x<16 and 0<=y<8 and -12<=z<12 for x,y,z in v.cells)
    return v

if __name__ == '__main__':
    path = ROOT/'assets/models/furniture/log_bed.glb'
    write_glb(path,'log_bed',export_mesh(log_bed()),export_scale=.125)
    print(path)

"""Voxel woodland deer: baked eight voxels/block, shared body origin, root scale 1.

Four runtime legs share a mesh authored below its hip pivot. All other parts
share feet Y0. The standing model fits a 2x2 footprint and four-cell clearance.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_rabbit import linear

OUT = Path(__file__).resolve().parents[1] / 'assets/animals/deer'
COAT = (.63, .40, .22)
LIGHT = (.73, .52, .31)
CREAM = (.88, .81, .66)
HOOF = (.19, .15, .12)
EYE = (.08, .065, .05)
ANTLER = (.58, .49, .35)


def parts():
    body, neck, head, ears, antlers, leg = [Voxels() for _ in range(6)]
    body.box(-3,3,10,16,-5,6,COAT)
    body.box(-2,2,15,17,-4,5,LIGHT)
    body.box(-2,2,10,12,-4,5,CREAM)
    body.box(-2,2,12,15,5,7,CREAM)
    body.box(-1,1,14,17,6,8,LIGHT)
    # Sloping upright neck, fine muzzle, white throat and wide alert ears.
    neck.box(-2,2,13,18,-5,-2,COAT)
    neck.box(-2,2,17,22,-6,-3,LIGHT)
    head.box(-2,2,21,24,-6,-2,COAT)
    head.box(-1,1,20,23,-8,-5,LIGHT)
    head.box(-1,1,20,21,-8,-4,CREAM)
    head.box(-1,1,21,22,-8,-7,HOOF,False)
    neck.box(-1,1,14,19,-6,-5,CREAM)
    for x in [-2,1]: head.set(x,22,-6,EYE)
    for side in [-1,1]:
        for x,y in [(2,23),(3,24),(4,24)]:
            xx = x if side > 0 else -x-1
            ears.box(xx,xx+1,y,y+2,-5,-3,LIGHT)
            ears.set(xx,y,-5,CREAM)
        # Small forked antlers rather than a wide, oversized rack.
        for x,y in [(1,24),(1,25),(2,26),(2,27),(3,28),(3,29),(4,29)]:
            xx = x if side > 0 else -x-1
            antlers.box(xx,xx+1,y,y+1,-4,-2,ANTLER)
        xx = 3 if side > 0 else -4
        antlers.box(xx,xx+1,26,28,-3,-2,ANTLER)
    # Local hip pivot Y0; ten voxels down to the ground, squared cloven hoof.
    leg.box(-1,1,-9,0,-1,1,COAT)
    leg.box(-1,1,-10,-8,-1,1,HOOF)
    return dict(body=body,neck=neck,head=head,ears=ears,antlers=antlers,leg=leg)


if __name__ == '__main__':
    for name, vox in parts().items():
        positions,normals,colours,indices = mesh_from_voxels(vox)
        if name != 'leg':
            assert all(-8 <= p[0] <= 8 and 0 <= p[1] <= 31 and -8 <= p[2] <= 8 for p in positions)
        colours = [tuple(linear(c) for c in colour[:3]) + (1.,) for colour in colours]
        print(name, write_glb(OUT/f'{name}.glb',name,(positions,normals,colours,indices),.125))

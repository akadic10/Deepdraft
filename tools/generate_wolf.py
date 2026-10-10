"""Original woodland wolf: eight voxels/block, baked .125, rooted at its paws.

Grey stone-range fur with a cream muzzle/belly keeps the existing muted palette.
Separate head, pointed ears, brush tail and four legs support runtime animation.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_rabbit import linear

OUT = Path(__file__).resolve().parents[1] / 'assets/animals/wolf'
FUR = (.46, .48, .48)
LIGHT = (.60, .62, .60)
DARK = (.30, .32, .33)
CREAM = (.78, .76, .67)
NOSE = (.12, .13, .14)
EYE = (.22, .17, .09)


def parts():
    body, head, ears, tail, leg = [Voxels() for _ in range(5)]
    body.box(-3,3,5,10,-4,5,FUR)
    body.box(-2,2,9,11,-3,4,DARK)
    body.box(-2,2,5,7,-3,4,CREAM)
    body.box(-3,3,8,12,-5,-2,LIGHT)  # shoulder ruff
    head.box(-2,2,9,13,-6,-3,FUR)
    head.box(-2,2,9,11,-8,-5,LIGHT)
    head.box(-1,1,9,10,-8,-5,CREAM)
    head.box(-1,1,10,11,-8,-7,NOSE,False)
    for x in [-2,1]: head.set(x,11,-6,EYE)
    for a,b,tip,inner in [(-3,-1,-3,-2),(1,3,2,1)]:
        ears.box(a,b,12,14,-5,-3,DARK)
        ears.box(tip,tip+1,14,15,-5,-4,DARK)
        ears.set(inner,13,-5,CREAM)
    tail.box(-1,1,6,9,4,7,FUR)
    tail.box(-1,1,4,7,6,8,DARK)
    leg.box(-1,1,-5,0,-1,1,FUR)
    leg.box(-1,1,-6,-4,-1,1,DARK)
    return dict(body=body,head=head,ears=ears,tail=tail,leg=leg)


if __name__ == '__main__':
    for name,vox in parts().items():
        positions,normals,colours,indices = mesh_from_voxels(vox)
        colours = [tuple(linear(c) for c in colour[:3])+(1.,) for colour in colours]
        print(name,write_glb(OUT/f'{name}.glb',name,(positions,normals,colours,indices),.125))

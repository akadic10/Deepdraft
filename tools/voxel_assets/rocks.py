"""Grounded voxel boulders and separated walkable scree from authored dimensions.

Hearthblock (doc 256): boulders are broken square rocks (stacked notched blocks, a
crack, chipped corners, lit tops, a few square moss patches); scree is a clutch of
small notched stones. Boulders keep their 2 x 2 block footprint and 2-block height,
scree its 3 x 3 footprint and walkable height.
"""
from common import Voxels,Part,linear,read_json

MOSS=(linear('6F8C3E'),linear('8CA851'))
# Per boulder: notched blocks (lo, hi, notch), a crack and broken corners, in cells.
BOULDERS=[
    dict(blocks=[((-15,0,-14),(14,10,15),4),((-12,10,-12),(9,20,11),3),((-8,20,-7),(4,24,6),2),((6,0,1),(15,14,15),2)],
         crack=((-2,12,4),(0,24,11)),chips=[((5,16,-12),(9,20,-8)),((-15,6,10),(-11,10,15))]),
    dict(blocks=[((-15,0,-14),(15,8,14),4),((-13,8,-10),(11,16,12),3),((-6,16,-6),(7,20,7),2),((-15,0,-14),(-6,12,-4),2)],
         crack=((3,10,6),(5,20,12)),chips=[((9,12,-10),(11,16,-6))]),
    dict(blocks=[((-14,0,-14),(13,12,14),4),((-11,12,-11),(10,22,10),3),((-7,22,-6),(5,28,5),2),((4,0,-14),(14,18,-2),2)],
         crack=((-4,14,5),(-2,28,10)),chips=[((-11,18,6),(-7,22,10)),((8,6,10),(13,12,14))]),
]


def _scale(color,factor): return tuple(min(1,c*factor) for c in color)


def _notched(vox,lo,hi,color,n):
    for x in range(lo[0],hi[0]):
        for z in range(lo[2],hi[2]):
            if (x-lo[0]<n or hi[0]-1-x<n) and (z-lo[2]<n or hi[2]-1-z<n): continue
            for y in range(lo[1],hi[1]): vox.cells[x,y,z]=color


def _carve(vox,lo,hi):
    for p in [p for p in vox.cells if all(lo[i]<=p[i]<hi[i] for i in range(3))]: del vox.cells[p]


def _shade(vox,body,moss_every=0,crack=None):
    """Lit tops, a dark foot, dark crack walls and square moss patches on the tops."""
    for p in list(vox.cells):
        x,y,z=p
        if (x,y+1,z) not in vox.cells:
            vox.cells[p]=_scale(body,1.25)
            if moss_every and ((x//4)+(z//4)*3)%moss_every==0 and y>=8: vox.cells[p]=MOSS[(x//4+z//4)%2]
        elif y<2: vox.cells[p]=_scale(body,.78)
        elif crack and crack[0][1]<=y<crack[1][1] and crack[0][2]<=z<crack[1][2] and x in (crack[0][0]-1,crack[1][0]):
            vox.cells[p]=_scale(body,.58)


def boulder(variant,body):
    spec=BOULDERS[variant]; vox=Voxels()
    for lo,hi,n in spec['blocks']: _notched(vox,lo,hi,body,n)
    _carve(vox,*spec['crack'])
    for lo,hi in spec['chips']: _carve(vox,lo,hi)
    _shade(vox,body,7,spec['crack'])
    return vox


def scree(clump,palette,i):
    vox=Voxels()
    for j,(x,z,width,height,depth,_) in enumerate(clump):
        w,h,d=max(3,round(width*16)),max(2,round(height*16)),max(3,round(depth*16))
        cx,cz=round(x*16),round(z*16)
        body=palette[(i+j)%3]
        _notched(vox,(cx-w//2,0,cz-d//2),(cx-w//2+w,h,cz-d//2+d),body,2 if min(w,d)>=8 else 1)
        if min(w,d)>=10 and h<=6:    # a smaller stone resting on the larger ones, still walkable
            _notched(vox,(cx-w//4,h,cz-d//4),(cx+w//6,h+2,cz+d//6),palette[(i+j+1)%3],1)
    for p in list(vox.cells):
        x,y,z=p; body=vox.cells[p]
        if (x,y+1,z) not in vox.cells: vox.cells[p]=_scale(body,1.22)
        elif y==0: vox.cells[p]=_scale(body,.8)
    return vox


def assets(only=None):
    profile=read_json('data/art/voxel_rocks.json')
    palette=[linear(c) for c in profile['palette']]
    for i,p in enumerate(profile['boulders']):
        path=f'assets/models/rocks/boulders/boulder_{i+1}.glb'
        if only and only not in path: continue
        yield path,{'main':Part(boulder(i,palette[i]))},dict(kind='boulder',variant=i,blocking=True)
    for i,clump in enumerate(profile['scree']):
        path=f'assets/models/rocks/scree/scree_{i+1}.glb'
        if only and only not in path: continue
        yield path,{'main':Part(scree(clump,palette,i))},dict(kind='scree',variant=i,blocking=False,stones=len(clump))

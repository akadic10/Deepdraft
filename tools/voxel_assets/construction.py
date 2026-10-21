"""Seamless structural tiles remain solid [0,1]^3; packaging shares item joinery."""
from common import Voxels,Part,linear,read_json
from items import shell


def floor(name):
    v=Voxels(); stone=name=='stone_floor'; phase=int(name.endswith('alternate'))
    colors=list(map(linear,read_json('data/art/voxel_construction.json')['stone' if stone else 'plank']))
    for x in range(16):
        for z in range(16):
            board=x//8; row=z//8
            joint=(z%8==0 or (x+row*8)%16==0) if stone else (x%8==0 or (z+phase*16+board*16)%32==0)
            for y in range(16):
                index=4 if y<14 else 5 if stone else 1
                if y==15:
                    index=0 if joint else 1+(row if stone else board)
                    if not joint:
                        if stone and z%8==1: index=3
                        if not stone and x%8==2 and z in (4,5,6,7,8): index=3
                        if not stone and x%8==6 and z in (10,11,12): index=5
                elif y==14 and joint: index=0
                v.cells[x,y,z]=colors[index]
    return v


def assets(only=None):
    for name in ['plank_floor','plank_floor_alternate','stone_floor','materials_crate']:
        path='assets/models/construction/'+name+'.glb'
        if not only or only in path:
            yield path,{'main':Part(shell() if name=='materials_crate' else floor(name))},dict(structural=name!='materials_crate')

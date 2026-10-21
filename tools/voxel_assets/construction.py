"""Seamless structural tiles remain solid [0,1]^3; packaging shares item joinery.

Hearthblock (doc 256): the plank floor is Tier 1 split planks: two eight-cell boards
per tile over a dark joist layer, with dark seams, staggered plank ends, pegs, grain,
a knot and an axe chop. The materials crate is the stockpile crate. The stone floor
needs a Stonemason, who is not in the game yet, so it keeps its earlier tile.
"""
from common import Voxels,Part,linear,read_json
from hearthblock_goods import shell

PLANK={k:linear(v) for k,v in dict(light='C8955A',riven='B58A5A',grain='A67C52',dark='976D44',
                                   seam='5C3F27',joist='7A5536',peg='3E2819',knot='8D5731').items()}


def plank_floor(alternate):
    v=Voxels(); c=PLANK
    for x in range(16):
        for z in range(16):
            board=x//8
            end=8 if (board+alternate)%2 else 0          # plank ends stagger board to board
            seam=x%8==0 or z==end
            for y in range(16):
                if y<12: color=c['joist']
                elif seam: color=c['seam'] if y>=13 else c['dark']
                elif y==15: color=c['grain'] if x%8==4 and (z//3)%2==0 else c['light']
                elif y==12: color=c['dark']
                else: color=c['riven']
                v.cells[x,y,z]=color
    for board in (0,1):
        end=8 if (board+alternate)%2 else 0
        for dz in (1,15) if end==0 else (7,9):           # two pegs beside each plank end
            for px in (board*8+2,board*8+6): v.cells[px,15,dz%16]=c['peg']
    kx,kz=(11,4) if not alternate else (3,12)            # one knot per tile
    for dx in (0,1):
        for dz in (0,1): v.cells[kx+dx,15,kz+dz]=c['knot']
    v.cells[kx,15,kz]=c['peg']
    for dz in (0,1): v.cells[(5 if not alternate else 13),15,(10 if not alternate else 3)+dz]=c['dark']   # an axe chop
    return v


def stone_floor():
    v=Voxels()
    colors=list(map(linear,read_json('data/art/voxel_construction.json')['stone']))
    for x in range(16):
        for z in range(16):
            row=z//8
            joint=z%8==0 or (x+row*8)%16==0
            for y in range(16):
                index=4 if y<14 else 5
                if y==15:
                    index=0 if joint else 1+row
                    if not joint and z%8==1: index=3
                elif y==14 and joint: index=0
                v.cells[x,y,z]=colors[index]
    return v


def assets(only=None):
    makers={'plank_floor':lambda:plank_floor(0),'plank_floor_alternate':lambda:plank_floor(1),
            'stone_floor':stone_floor,'materials_crate':shell}
    for name,fn in makers.items():
        path='assets/models/construction/'+name+'.glb'
        if not only or only in path:
            yield path,{'main':Part(fn())},dict(structural=name!='materials_crate')

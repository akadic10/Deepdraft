"""Native-grid loose goods: readable silhouettes and complete quantity states.

Dimensions below are integer cells; all geometry is unioned before greedy baking.
The saved art profile owns palettes and each named inventory presentation.
"""
import math
from common import ROOT, Voxels, Part, linear, read_json, ellipsoid, translate
from solid_shapes import apply
import hearthblock
import hearthblock_goods as goods

# Crate goods the game cannot produce yet (their plants are not in the world).
NOT_IN_GAME = {'grape_cutting','hops_cutting','pig_tail_seed'}

PROFILE = read_json('data/art/voxel_items.json')
P = {k:linear(v) for k,v in PROFILE['palette'].items()}
P.update({'tool:'+k:linear(v) for k,v in read_json('data/materials/craft_materials.json')['source_palettes']['starter_tool']['colors'].items()})


def block(v, lo, hi, color, cut=0):
    for x in range(lo[0],hi[0]):
        for y in range(lo[1],hi[1]):
            for z in range(lo[2],hi[2]):
                if min(x-lo[0],hi[0]-1-x)+min(z-lo[2],hi[2]-1-z)>=cut:
                    v.cells[x,y,z]=P.get(color,color)


def bulb(v, center, radius, color, power=2.5):
    ellipsoid(v,[c/16 for c in center],[r/16 for r in radius],P.get(color,color),power)


def profile(v, rings, color, inner=0, colors=None):
    palette={'base':P.get(color,color)}
    palette.update({str(i):P.get(c,c) for i,c in enumerate(colors or [])})
    apply(v,dict(op='profile',rings=[[q/16 for q in r] for r in rings],color='base',inner=inner,
                 colors=[str(i) for i in range(len(colors))] if colors else ['base']),palette)


def grounded(v):
    return translate(v,(0,-min(p[1] for p in v.cells)/16,0))


def shell():
    v=Voxels()
    block(v,(-6,0,-5),(6,1,5),'crate_shadow')
    for y in (1,3):
        for z in (-5,4): block(v,(-6,y,z),(6,y+2,z+1),'crate_board')
        for x in (-6,5): block(v,(x,y,-4),(x+1,y+2,4),'crate_board')
    for x in (-6,5):
        for z in (-5,4): block(v,(x,1,z),(x+1,7,z+1),'crate_edge')
    for z in (-5,4): block(v,(-6,6,z),(6,7,z+1),'crate_edge')
    for x in (-6,5): block(v,(x,6,-4),(x+1,7,4),'crate_edge')
    return v


def crate(name, level):
    v=shell(); kind,dark,light=PROFILE['crate_contents'][name]; dark,light=linear(dark),linear(light)
    joinery=v.cells.copy()
    y=[2,4,6][level]
    if level: block(v,(-5,1,-4),(5,y,4),dark)
    sites=[(-3,-3),(0,0),(3,3),(-3,3),(3,-3),(0,-3),(-3,0),(3,0),(0,3)]
    for i,(x,z) in enumerate(sites[:[3,6,9][level]]):
        c=dark if i%3 else light
        if kind=='cutting':
            block(v,(x,y,z),(x+1,y+4,z+1),'stem')
            block(v,(x-1,y+1,z),(x,y+2,z+2),dark)
            block(v,(x+1,y+2,z),(x+2,y+3,z+2),light)
        elif kind=='cone':
            for dy,r in [(0,1),(1,1),(2,1),(3,1)]: block(v,(x-r,y+dy,z-r),(x+r,y+dy+1,z+r),dark if dy%2 else light)
        elif kind=='acorn':
            bulb(v,(x,y+1.5,z),(1.3,1.5,1.3),light)
            block(v,(x-1,y+2,z-1),(x+1,y+3,z+1),dark)
        elif kind=='seed':
            block(v,(x-1,y,z-1),(x+1,y+1,z+1),c)
            block(v,(x,y+1,z),(x+1,y+2,z+1),light)
        else:
            bulb(v,(x+.5,y+1.5,z+.5),(1.4,1.4,1.4),c,2)
            if kind in ('fruit','strawberry'):
                block(v,(x,y+3,z),(x+1,y+4,z+1),'stem' if kind=='fruit' else 'leaf')
    v.cells.update(joinery)
    return v


def starter(name):
    v=Voxels(); stone=linear('7C8587')
    if name=='hunting_spear':
        block(v,(-1,0,-18),(1,2,12),'tool:wood')
        for z in range(10,19):
            r=2 if z<14 else 1
            block(v,(-r,0,z),(r,3 if z<14 else 2,z+1),stone)
        block(v,(-1,0,9),(1,3,12),'tool:bark')
        block(v,(-1,3,10),(1,4,11),'tool:grain')
    elif name=='carpentry_kit':
        for x in (-5,5): block(v,(x-1,0,-10),(x+1,2,9),'tool:wood')
        block(v,(-9,0,4),(-1,6,9),'tool:grain',1)
        block(v,(2,0,4),(8,4,10),stone,1)
        block(v,(4,4,5),(6,5,7),'tool:bark')
    elif name=='stone_hammer':
        block(v,(-1,1,-9),(1,3,6),'tool:wood')
        block(v,(-6,0,1),(6,8,7),stone,1)
        block(v,(-1,0,1),(1,8,7),'tool:bark')
        block(v,(-1,8,3),(1,9,5),'tool:grain')
    else:
        block(v,(-1,0,-14),(1,2,11),'tool:wood')
        block(v,(-6,0,7),(6,3,13),stone,1)
        block(v,(-1,3,8),(1,5,11),'tool:bark')
        block(v,(-1,5,9),(2,6,10),'tool:grain')
    return v


def drink(name):
    v=Voxels(); h=11 if 'gin' in name else 13; r=5
    profile(v,[(0,4,4,0,0),(2,r,r,0,0),(h-2,r,r,0,0),(h,4,4,0,0)],'crate_board',colors=['crate_board','crate_shadow','crate_board','crate_edge'])
    for y in (2,h-3): profile(v,[(y,r,r,0,0),(y+1,r,r,0,0)],'iron_dark',inner=.72)
    profile(v,[(h-1,3,3,0,0),(h,3,3,0,0)],'crate_edge')
    block(v,(-2,4,4),(2,8,5),linear(PROFILE['drink_marks'][name]))
    if 'wine' in name:
        for x,y in [(-1,6),(1,6),(0,5)]: block(v,(x,y,5),(x+1,y+1,6),'linen')
    elif 'gin' in name: block(v,(0,5,5),(1,8,6),'linen')
    else: block(v,(-1,6,5),(2,7,6),'linen')
    if name.startswith(('aged_','vintage_','reserve_')):
        block(v,(-2,4,5),(2,5,6),'gold')
        profile(v,[(h-2,5,5,0,0),(h-1,5,5,0,0)],'gold_dark',inner=.75)
    return v


def misc(name):
    v=Voxels()
    if name=='cloth_bolt':
        for y,w,d,c in [(0,11,8,'linen'),(4,10,7,'linen_shadow'),(5,9,6,'linen')]:
            block(v,(-w//2,y,-d//2),((w+1)//2,y+4 if y==0 else y+1,(d+1)//2),c,1)
        for x in (-4,3): block(v,(x,6,-3),(x+1,7,3),'crate_shadow')
    elif name=='water_bucket':
        profile(v,[(0,3,3,0,0),(7,5,5,0,0)],'crate_board',colors=['crate_board','crate_shadow'])
        profile(v,[(7,5,5,0,0),(8,5,5,0,0)],'crate_edge',inner=.75)
        profile(v,[(6,4,4,0,0),(7,4,4,0,0)],'water')
        for x in (-5,4): block(v,(x,5,-1),(x+1,11,1),'iron_dark')
        block(v,(-5,11,-1),(5,12,1),'crate_edge')
        profile(v,[(1,4,4,0,0),(2,4,4,0,0)],'iron_dark',inner=.7)
    elif name=='honey_jar':
        profile(v,[(0,3,3,0,0),(2,4.5,4.5,0,0),(6,4.5,4.5,0,0),(8,3,3,0,0)],'clay')
        profile(v,[(8,3.5,3.5,0,0),(9,3.5,3.5,0,0)],'honey')
        block(v,(-2,3,4),(2,6,5),'linen')
        block(v,(-1,4,5),(1,5,6),'honey')
    else:
        bulb(v,(0,1,0),(6,1.5,5),linear('8D8B7F'),3)
        for x,z,r in [(-2,-1,1.5),(0,0,2),(3,1,1.5)]: bulb(v,(x,2,z),(r,1.2,r),'linen')
    return grounded(v)


def flora(name):
    v=Voxels()
    if name=='plump_helmet':
        block(v,(-2,0,-2),(2,5,2),linear('B7AD8F'),1)
        bulb(v,(0,5,0),(6,3,5.5),linear('96778E'),2.5)
        profile(v,[(4,5,5,0,0),(5,5,5,0,0)],linear('7F657E'))
    elif name=='pig_tail':
        for z in (-2,0,2):
            block(v,(-5,0,z),(4,1,z+1),'stem')
            bulb(v,(1,2,z),(3,2,1.5),linear('B6A3AA'),3)
        block(v,(-3,0,-3),(-2,3,4),'crate_shadow')
    else:
        c=linear('8E9E58' if name=='hops' else '74587C')
        for x,y,z in [(-2,2,-2),(2,2,-2),(0,2,2),(0,5,0)]: bulb(v,(x,y,z),(2,2.5,2),c,2.8)
        block(v,(0,6,0),(1,9,1),'stem')
        block(v,(1,7,0),(3,8,1),'leaf')
    return grounded(v)


def assets(only=None):
    makers={}; square=set()
    def add(category,name,fn): makers['assets/models/items/'+category+'/'+name+'.glb']=fn
    def hearthblock_add(category,name,fn): add(category,name,fn); square.add('assets/models/items/'+category+'/'+name+'.glb')
    # The goods the game has today are Hearthblock (doc 256); the rest keep their earlier art.
    for category in ('stone','soil','ore'):
        for name in PROFILE[category]: hearthblock_add(category,name,lambda n=name:goods.mined(n))
    for name,colors in PROFILE['gems'].items(): hearthblock_add('gem',name,lambda c=colors:goods.gem(c))
    for name,material in PROFILE['timber'].items(): hearthblock_add('wood',name,lambda m=material:goods.log(m))
    def stave():
        v=Voxels(); block(v,(-2,0,-7),(2,2,7),'crate_board'); return v
    add('wood','oak_stave',stave)
    for name in PROFILE['crate_contents']:
        for i,stage in enumerate(['low','half','full']):
            if name in NOT_IN_GAME: add('crates',name+'_'+stage,lambda n=name,i=i:crate(n,i))
            else: hearthblock_add('crates',name+'_'+stage,lambda n=name,i=i:goods.crate(n,i))
    for name in ['stone_hoe','stone_hammer','hunting_spear','carpentry_kit']: hearthblock_add('tools',name,lambda n=name:goods.starter(n))
    for name in PROFILE['drink_marks']: add('drink',name,lambda n=name:drink(n))
    for name in ['cloth_bolt','water_bucket','honey_jar','fossil_fragment']: add('misc',name,lambda n=name:misc(n))
    for name in ['plump_helmet','pig_tail','hops','grape']: add('flora',name,lambda n=name:flora(n))
    def coin():
        v=Voxels(); profile(v,[(0,4,4,0,0),(1,4,4,0,0)],'gold')
        block(v,(0,1,-2),(1,2,2),'gold_dark'); block(v,(-1,1,-1),(2,2,0),'gold_dark'); return v
    add('currency','gold_coin',coin)
    for path,fn in makers.items():
        if not only or only in path:
            metadata=dict(item=path.rsplit('/',1)[-1][:-4])
            if path in square: metadata['source']='tools/voxel_assets/hearthblock_goods.py'
            if metadata['item'] in PROFILE['timber']:
                metadata.update(material=PROFILE['timber'][metadata['item']],orientation='horizontal_z')
            occlusion=hearthblock.occlusion()|{'ground':0} if path in square else None
            yield path,{'main':Part(fn(),occlusion=occlusion)},metadata

"""Crop art. Two kinds live here:
- the Farmer's field vegetables (doc 309), in Hearthblock: seven crops at their stages and the
  bare tilled tile, at the paths data/flora/field_crops.json and task_config.json name;
- placeholders for the brewing and weaving crops (grape vine, hops, pig tail, plump helmet), whose
  features are not built. They are not Hearthblock yet and must stay as they are until then."""
import math
from common import Voxels,Part,box,ellipsoid,linear,read_json
from plants import branch,leaf,block,notched
import hearthblock


def crop(profile,species,stage,season):
    p=profile[species]; colors={k:linear(v) for k,v in p['palette'].items()}
    vox=Voxels(); height=p['heights'][stage]
    if species=='plump_helmet':
        for i,(x,z) in enumerate(p['clump']):
            h=height*(1-i*.18)
            radius=h*.32
            box(vox,(x,h*.35,z),(.1875,h*.70,.1875),colors['stem'])
            ellipsoid(vox,(x,h*.77,z),(radius,h*.23,radius),colors['cap'],power=3)
            box(vox,(x+radius*.25,h*.94,z-radius*.25),(.125,.0625,.125),colors['speck'])
    elif species=='pig_tail_plant':
        for i,(x,z) in enumerate(p['clump']):
            tip=(x,height*(1-.12*i),z)
            branch(vox,(x,0,z),tip,.05,.05,colors['autumn' if season=='autumn' else 'stem'])
            for j in range(3):
                at=(x,height*(.25+.17*j),z)
                angle=i*2.1+j*2.4
                leaf(vox,at,(x+math.cos(angle)*.30,at[1]+.12,z+math.sin(angle)*.30),.16,colors['autumn' if season=='autumn' else 'leaf'])
            if stage=='mature':
                last=tip
                for j in range(1,7):
                    angle=j*math.pi/4
                    current=(x+.14*math.sin(angle),tip[1]+.14*(1-math.cos(angle)),z)
                    branch(vox,last,current,.06,.05,colors['fiber']); last=current
    else:
        mature=stage not in ('seedling','cutting')
        # A single authored support is part of the existing crop visual only.
        box(vox,(0,height/2,0),(.125,height,.125),colors['wood'])
        last=(0,0,0)
        turns=10 if mature else 3
        for i in range(turns):
            y=height*(i+1)/(turns+1)
            angle=i*1.8
            at=(math.cos(angle)*.14,y,math.sin(angle)*.14)
            branch(vox,last,at,.05,.05,colors['stem']); last=at
            if season=='winter': continue
            end=(at[0]+math.cos(angle)*.32,y+.10,at[2]+math.sin(angle)*.32)
            leaf(vox,at,end,.25,colors['autumn' if season=='autumn' else 'leaf'])
            if mature and i>=2 and i%2==0 and (species=='hops_plant' and stage=='mature' or species=='grape_vine' and season in ('summer','autumn')):
                for j in range(3):
                    spot=(end[0],end[1]-.10-j*.10,end[2]+.0625*(j%2))
                    ellipsoid(vox,spot,(.10,.13,.10),colors['fruit'],power=3)
            if mature and species=='grape_vine' and season=='spring' and i%2:
                box(vox,(end[0],end[1]+.04,end[2]),(.125,.0625,.125),colors['bud'])
    vox.cells={p:c for p,c in vox.cells.items() if p[1]>=0}
    return vox


# ── Field crops (doc 309) ────────────────────────────────────────────────────────────────
# Hearthblock, in whole 1:16 cells. A tile is one block of tilled soil: cells x and z in
# [-8, 8), the block's top at y 0. The game draws one model a tile and never turns it, so every
# model carries the tile's two soil ridges, which run its whole length along X under the planted
# rows and meet the next tile's. Plants stand on the ridges; a crop of one plant a tile (cabbage,
# pumpkin) stands on a planting hill that joins them at the middle.
# The owner looks down on a field, so a vegetable shows on top: a root's shoulders stand out of
# the soil with their leaves kept small or to the sides, never spread over them.
FIELD_CROPS='data/flora/field_crops.json'
FARMING='data/tasks/task_config.json'
ROWS=(-4,4)      # the two rows' centre lines: a ridge at z covers cells z-3 .. z+2
PAIR=(-4,4)      # two plants to a row: their centre lines along X
# Three plants to a row, one of them a cell broader so the gaps come out even: (first cell, width).
TRIO={-4:((-8,4),(-3,5),(3,4)),4:((-8,5),(-2,4),(3,4))}
CORNERS=((-2,-2),(1,-2),(-2,1),(1,1))


def _occlusion():
    return hearthblock.occlusion() | {'ground':0}


def put(vox,color,*points):
    for point in points: vox.cells[point]=color


def carve(vox,lo,size):
    for x in range(lo[0],lo[0]+size[0]):
        for y in range(lo[1],lo[1]+size[1]):
            for z in range(lo[2],lo[2]+size[2]): vox.cells.pop((x,y,z),None)


def ridges(vox,c):
    """The tile's soil, shared by every field model: two ridges one cell high, the tile's whole
    length, a lit top four cells wide between darker sides. The troughs stay empty: the block shows."""
    for row in ROWS:
        block(vox,(-8,0,row-3),(16,1,6),c['soil_side'])
        block(vox,(-8,0,row-2),(16,1,4),c['soil'])


def hill(vox,c):
    """A planting hill across the middle trough, for a tile that holds one plant."""
    block(vox,(-3,0,-2),(6,1,4),c['soil_side'])
    block(vox,(-2,0,-2),(4,1,4),c['soil'])


def tuft(vox,x,y,row,c):
    """A sprig of small leaves, two cells square."""
    block(vox,(x,y,row-1),(2,1,2),c['leaf'])
    put(vox,c['leaf_light'],(x,y+1,row-1),(x+1,y+1,row))


def radish(vox,stage,c):
    """Round red shoulders under a sprig of leaves, three to a row."""
    for row in ROWS:
        for x0,wide in TRIO[row]:
            x=x0+1
            if stage=='growing':                     # a low rosette, longer across the ridge
                block(vox,(x,1,row-1),(2,1,2),c['leaf_dark'])
                block(vox,(x,2,row-3),(2,1,6),c['leaf']); block(vox,(x-1,2,row-1),(4,1,2),c['leaf'])
                block(vox,(x,3,row-1),(2,1,2),c['leaf_light'])
                continue
            if stage=='ripe':
                notched(vox,(x0,1,row-2),(wide,1,4),c['root_dark'],1)
                notched(vox,(x0,2,row-2),(wide,1,4),c['root'],1)
            tuft(vox,x,3 if stage=='ripe' else 1,row,c)


def carrot(vox,stage,c):
    """Broad orange shoulders, each under one thin feathery top; four to a row."""
    for row in ROWS:
        for x in range(-8,8,4):                      # three cells of carrot, then one of soil
            if stage=='sprout':                      # a blade bent across the ridge, its two tips up
                block(vox,(x+1,1,row-2),(1,1,4),c['leaf_dark'])
                put(vox,c['leaf_light'],(x+1,2,row-2),(x+1,2,row+1))
                continue
            if stage=='ripe':
                block(vox,(x,1,row-2),(3,1,4),c['root'])
                notched(vox,(x,2,row-2),(3,1,4),c['root_light'],1)
                foot,top=3,6
            else:
                block(vox,(x,1,row-1),(3,1,2),c['leaf_dark'])
                foot,top=2,4
            # The top: a thin stalk with a leaflet to each side, one higher than the other, and a tip.
            block(vox,(x+1,foot,row-1),(1,top-foot+1,2),c['leaf'])
            block(vox,(x+1,foot,row-1),(1,1,2),c['leaf_dark'])
            block(vox,(x,top-1,row-1),(1,1,2),c['leaf_light']); block(vox,(x+2,top,row-1),(1,1,2),c['leaf_light'])
            put(vox,c['leaf_light'],(x+1,top,row),(x+1,top+1 if stage=='ripe' else top,row-1))


def turnip(vox,stage,c):
    """A white root with purple shoulders and a broad leaf rising to each side; two to a row."""
    for row in ROWS:
        for x in PAIR:
            if stage=='sprout':                      # two seed leaves
                block(vox,(x-2,1,row-1),(4,1,2),c['leaf_dark'])
                for end in (x-2,x+1): block(vox,(end,2,row-1),(1,1,2),c['leaf_light'])
                continue
            if stage=='ripe':                        # the white root shows as a step either side of the shoulders
                notched(vox,(x-2,1,row-3),(4,1,6),c['root_dark'],1)
                notched(vox,(x-2,2,row-3),(4,1,6),c['root'],1)
                block(vox,(x-2,3,row-2),(4,1,4),c['shoulder_dark'])
                block(vox,(x-2,4,row-2),(4,1,4),c['shoulder'])
                low=5
            else:
                block(vox,(x-1,1,row-1),(2,2,2),c['leaf_dark'])
                low=2
            for side in (-1,1):                      # a stalk at the shoulders' edge, a broad blade, a tip
                first=x-2 if side<0 else x+1
                block(vox,(first,low,row-1),(1,1,2),c['leaf_dark']); block(vox,(first,low+1,row-1),(1,1,2),c['leaf'])
                block(vox,(first+side,low,row-2),(1,1,4),c['leaf_dark']); block(vox,(first+side,low+1,row-2),(1,1,4),c['leaf'])
                block(vox,(first+2*side,low+1,row-1),(1,1,2),c['leaf']); block(vox,(first+2*side,low+2,row-1),(1,1,2),c['leaf_light'])


def onion(vox,stage,c):
    """Golden bulbs out of the soil, each top fallen over one side or the other; three to a row."""
    for row in ROWS:
        for index,(x0,wide) in enumerate(TRIO[row]):
            x=x0+1
            if stage=='sprout':                      # a blade and a shorter one
                block(vox,(x,1,row-1),(1,2,1),c['leaf']); put(vox,c['leaf_light'],(x,2,row-1))
                put(vox,c['leaf'],(x+1,1,row-1))
                continue
            if stage=='growing':                     # four thin upright blades, the middle two taller
                for dx,dz,high in ((-1,0,2),(0,-1,3),(1,0,3),(2,-1,2)):
                    block(vox,(x+dx,1,row+dz),(1,high,1),c['leaf'])
                    put(vox,c['leaf_dark'],(x+dx,1,row+dz)); put(vox,c['leaf_light'],(x+dx,high,row+dz))
                continue
            notched(vox,(x0,1,row-2),(wide,1,4),c['bulb_dark'],1)
            block(vox,(x0,2,row-2),(wide,1,4),c['bulb'])
            notched(vox,(x0,3,row-2),(wide,1,4),c['bulb_light'],1)
            away=-1 if (index+(row>0))%2==0 else 1   # the side this top fell to
            edge=row-2 if away<0 else row+1          # the bulb's last row on that side
            block(vox,(x,4,min(edge,edge-away)),(2,1,2),c['leaf'])
            block(vox,(x,4,edge+away),(2,1,1),c['leaf_light'])
            block(vox,(x,3,edge+2*away),(2,2,1),c['tip'])    # its yellowed end hangs past the bulb


def ribs(vox,y,inner,reach,color):
    """A light midrib on each of a rosette's four outer leaves."""
    for k in range(inner,reach): put(vox,color,(-1,y,-k-1),(0,y,k),(k,y,-1),(-k-1,y,0))


def cabbage(vox,stage,c):
    """One big rosette a tile: dark outer leaves and, when ripe, a pale head inside them."""
    hill(vox,c)
    if stage=='sprout':
        block(vox,(-1,1,-1),(2,2,2),c['leaf_dark'])
        block(vox,(-2,2,-1),(1,1,2),c['leaf_light']); block(vox,(1,2,-1),(1,1,2),c['leaf_light'])
        block(vox,(-1,2,-2),(2,1,1),c['leaf_light']); block(vox,(-1,2,1),(2,1,1),c['leaf_light'])
        return
    if stage=='growing':                             # an open rosette: a cup of leaves about a small heart
        notched(vox,(-5,1,-5),(10,1,10),c['leaf_dark'],3)
        notched(vox,(-6,2,-6),(12,1,12),c['leaf'],3)
        ribs(vox,2,4,6,c['leaf_light'])
        notched(vox,(-4,3,-4),(8,1,8),c['leaf'],2)
        notched(vox,(-4,4,-4),(8,1,8),c['leaf_light'],2)
        carve(vox,(-2,4,-2),(4,1,4))
        block(vox,(-2,3,-2),(4,1,4),c['leaf_dark'])
        block(vox,(-1,4,-1),(2,2,2),c['wrap'])
        return
    notched(vox,(-6,1,-6),(12,1,12),c['leaf_dark'],3)
    notched(vox,(-7,2,-7),(14,1,14),c['leaf'],4)
    ribs(vox,2,5,7,c['leaf_light'])
    notched(vox,(-5,3,-5),(10,1,10),c['leaf'],2)
    notched(vox,(-5,4,-5),(10,1,10),c['wrap'],2)
    notched(vox,(-4,5,-4),(8,1,8),c['head_dark'],2)
    notched(vox,(-4,6,-4),(8,2,8),c['head'],2)
    notched(vox,(-3,8,-3),(6,1,6),c['head_light'],1)
    block(vox,(-3,8,-1),(3,1,1),c['head']); block(vox,(0,8,-1),(1,1,3),c['head'])   # the edge of the head's top leaf


def pad(vox,x,z,size,top,c,light=False):
    """A broad leaf on its stalk: a square with its corners off, its top at `top`."""
    half=size//2
    low=1 if (x,0,z) in vox.cells else 0
    block(vox,(x,low,z),(1,top-1-low,1),c['vine'])
    notched(vox,(x-half,top-1,z-half),(size,1,size),c['leaf_dark'],1)
    notched(vox,(x-half,top,z-half),(size,1,size),c['leaf_light' if light else 'leaf'],1)


def pumpkin(vox,stage,c):
    """One plant a tile: a vine of broad leaves over both ridges and, when ripe, one big ribbed pumpkin."""
    hill(vox,c)
    if stage=='sprout':                              # two seed leaves
        block(vox,(-1,1,-1),(2,2,2),c['vine'])
        notched(vox,(-4,2,-2),(3,1,4),c['leaf'],1); notched(vox,(1,2,-2),(3,1,4),c['leaf'],1)
        return
    block(vox,(-1,1,-6),(2,1,6),c['vine'])           # the vine: off the hill, along the far ridge and back down the tile's side
    block(vox,(-8,1,-5),(16,1,2),c['vine'])
    block(vox,(-6,1,-2),(2,1,1),c['vine']); block(vox,(-6,0,-1),(2,1,2),c['vine']); block(vox,(-6,1,1),(2,1,6),c['vine'])
    if stage=='growing':
        pad(vox,-5,-5,5,4,c); pad(vox,1,-5,5,6,c,True); pad(vox,6,-5,4,3,c)
        pad(vox,-5,1,5,6,c,True); pad(vox,-5,6,4,3,c)
        block(vox,(-1,1,1),(6,1,2),c['vine']); block(vox,(3,1,1),(2,1,6),c['vine'])
        pad(vox,4,5,5,4,c); pad(vox,2,1,4,5,c,True)
        return
    pad(vox,-5,-5,5,4,c); pad(vox,0,-6,4,3,c,True); pad(vox,5,-5,5,5,c)
    pad(vox,-5,1,5,5,c,True); pad(vox,-5,6,4,3,c)
    x0,z0=-2,-2                                      # the pumpkin: ten cells square, eight high, its corners and top stepped in
    notched(vox,(x0+1,1,z0+1),(8,1,8),c['fruit_dark'],2)
    notched(vox,(x0,2,z0),(10,1,10),c['fruit_dark'],2)
    notched(vox,(x0,3,z0),(10,5,10),c['fruit'],2)
    notched(vox,(x0+1,8,z0+1),(8,1,8),c['fruit_light'],2)
    for k in (3,6):                                  # ribs: down each side and a little way onto the top
        for y in range(2,8): put(vox,c['rib'],(x0+k,y,z0),(x0+k,y,z0+9),(x0,y,z0+k),(x0+9,y,z0+k))
        for edge in (1,2): put(vox,c['rib'],(x0+k,8,z0+edge),(x0+k,8,z0+9-edge),(x0+edge,8,z0+k),(x0+9-edge,8,z0+k))
    block(vox,(x0+4,9,z0+4),(2,1,2),c['stem_dark'])
    block(vox,(x0+4,10,z0+4),(2,1,1),c['stem'])


def kale_leaves(leaves,x,row,low,top,c,frilled):
    """The leaves about a kale stalk: a dark foot, then tall blades standing off each side of it,
    their tops frilled and lighter when the plant is ripe."""
    edge=c['frill'] if frilled else c['leaf_light']
    notched(leaves,(x-2,low,row-2),(4,1,4),c['leaf_dark'],1)
    block(leaves,(x-2,low+1,row-2),(4,top-low-1,4),c['leaf'])
    half=(low+top+1)//2
    for dz in (-3,2): block(leaves,(x-1,half,row+dz),(2,top-half,1),c['leaf']); block(leaves,(x-1,top,row+dz),(2,1,1),edge)
    for dx in (-3,2): block(leaves,(x+dx,half,row-1),(1,top-half,2),c['leaf']); block(leaves,(x+dx,top,row-1),(1,1,2),edge)
    if frilled:
        for dx,dz in CORNERS: block(leaves,(x+dx,top,row+dz),(1,2,1),edge)


def kale(vox,stage,c):
    """The tallest crop: dark blue-green leaves about a pale stalk, two plants to a row. A picking
    takes the leaves and leaves the stalk with its young top, so 'picked' is 'ripe' less its leaves."""
    for row in ROWS:
        for x in PAIR:
            if stage=='sprout':
                block(vox,(x-1,1,row-1),(2,1,2),c['leaf_dark'])
                put(vox,c['leaf_light'],(x-1,2,row-1),(x,2,row)); put(vox,c['leaf'],(x,2,row-1),(x-1,2,row))
                continue
            high=6 if stage=='growing' else 10
            block(vox,(x-1,1,row-1),(2,high,2),c['stalk'])
            for y in (1,4,7):                        # its foot and two leaf scars
                if y<high: block(vox,(x-1,y,row-1),(2,1,2),c['stalk_dark'])
            notched(vox,(x-2,high,row-2),(4,1,4),c['leaf_dark'],1)
            notched(vox,(x-2,high+1,row-2),(4,1,4),c['leaf'],1)
            block(vox,(x-1,high+2,row-1),(2,1,2),c['leaf_light'])
            if stage=='picked': continue
            leaves=Voxels()
            if stage=='growing': kale_leaves(leaves,x,row,2,7,c,False)
            else: kale_leaves(leaves,x,row,3,12,c,True)
            for point,color in leaves.cells.items(): vox.cells.setdefault(point,color)


FIELD={'radish':radish,'carrot':carrot,'turnip':turnip,'cabbage':cabbage,'onion':onion,'pumpkin':pumpkin,'kale':kale}


def field_tile(profile,name,stage):
    """One tile's model: the ridges and, for a crop, its plants at a stage."""
    table=dict(profile['soil'])
    if name in FIELD: table|=profile[name]['plant']|profile[name]['crop']
    c={role:linear(value) for role,value in table.items()}
    vox=Voxels(); ridges(vox,c)
    if name in FIELD: FIELD[name](vox,stage,c)
    return vox


def field_assets(profile,only=None):
    """The bare tilled tile and every crop's stages, at the paths the game's own data names."""
    rows=[('field','bare',read_json(FARMING)['farming']['bare_model'])]
    for key,definition in read_json(FIELD_CROPS).items():
        if key.startswith('base:flora:'): rows+=[(key.rsplit(':',1)[1],stage,path) for stage,path in definition['models'].items()]
    for name,stage,path in rows:
        if only and only not in path: continue
        vox=field_tile(profile,name,stage)
        assert min(p[1] for p in vox.cells)==0,path+' grounding'
        assert all(-8<=p[0]<8 and -8<=p[2]<8 for p in vox.cells),path+' footprint'
        if name in FIELD: assert max(p[1] for p in vox.cells)<(3 if stage=='sprout' else profile[name]['height']),path+' height'
        yield path.removeprefix('res://'),{'main':Part(vox,occlusion=_occlusion())},dict(species=name,stage=stage,integration='field_crop')


def assets(only=None):
    profile=read_json('tools/art_data/voxel_crops.json')
    for species in ('grape_vine','hops_plant','pig_tail_plant','plump_helmet'):
        data=read_json(f'data/flora/{species}.json')
        definition=next(v for k,v in data.items() if k.startswith('base:flora:'))
        for stage,settings in definition['stages'].items():
            for season,path in settings['models'].items():
                if only and only not in path: continue
                vox=crop(profile,species,stage,season)
                assert max(p[1]+1 for p in vox.cells)<=settings['clearance_height']*16,path+' clearance'
                assert min(p[1] for p in vox.cells)==0,path+' grounding'
                yield path.removeprefix('res://'),{'main':Part(vox)},dict(species=species,stage=stage,season=season,integration='art_and_data_only')
    yield from field_assets(profile['field'],only)

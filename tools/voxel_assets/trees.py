"""Hand-hewn tree silhouettes, baked on the native 1:16 object grid."""
import math
import random
from common import Voxels,Part,box,branch_blocks,linear,palette_snow,read_json

STAGES=('sapling','mature','ancient')
NEIGHBORS=((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))


def _grounded_wood(wood):
    """Discard detached tip slivers created by quantizing tapered branches."""
    pending=[min(wood.cells,key=lambda p:p[1])]
    connected={pending[0]}
    while pending:
        x,y,z=pending.pop()
        for dx,dy,dz in NEIGHBORS:
            q=(x+dx,y+dy,z+dz)
            if q in wood.cells and q not in connected:
                connected.add(q); pending.append(q)
    wood.cells={p:c for p,c in wood.cells.items() if p in connected}


def crown(vox, at, width, depth, colors, turn=0):
    """Tapered chunky lobes; broad shoulders instead of flat pucks.

    Two/four-cell leaf steps avoid a curtain of one-cell chamfer stripes.
    All dimensions are baked into native cells, never stretched at runtime.
    """
    step=4 if width>=2 else 2
    coarse=Voxels()
    for y,w,height,shade in [(-.40,.55,.20,0),(-.24,.84,.27,0),
                            (0,1,.32,1),(.23,.86,.25,1),(.40,.57,.19,2)]:
        dx=math.cos(turn)*width*y*.16; dz=math.sin(turn)*width*y*.16
        box(coarse,((at[0]+dx)/step,(at[1]+depth*y)/step,(at[2]+dz)/step),
            (width*w/step,depth*height/step,width*w*.90/step),colors[shade],cut=width*w*.16/step)
    # One offset leaf tuft breaks the repeated shoulders without surface noise.
    box(coarse,((at[0]+math.cos(turn)*width*.43)/step,(at[1]+depth*.10)/step,
                (at[2]+math.sin(turn)*width*.40)/step),
        (width*.31/step,depth*.30/step,width*.29/step),colors[2],cut=width*.045/step)
    for (x,y,z),color in coarse.cells.items():
        for dx in range(step):
            for dy in range(step):
                for dz in range(step): vox.cells[x*step+dx,y*step+dy,z*step+dz]=color


def _wood_palette(wood, bark, trunk, h, variant):
    """Long bark plates and one knot, never independently noisy cell colors."""
    dark=tuple(c*.72 for c in bark)
    light=tuple(min(1,c*1.22) for c in bark)
    knot_y=round(min(h*.28,2.6)*16)
    knot_w=max(2,round(trunk*5)); knot_h=max(3,round(trunk*7))
    for (x,y,z) in wood.cells:
        panel=(x+2*z)//max(4,round(trunk*7))
        shade=(panel*3+y//32+variant)%11
        if shade in (0,1): wood.cells[x,y,z]=dark
        elif shade==7: wood.cells[x,y,z]=light
        if z>0 and abs(x)<knot_w and abs(y-knot_y)<knot_h and (x,y,z+1) not in wood.cells:
            q=(x/knot_w)**2+((y-knot_y)/knot_h)**2
            if .28<q<.92: wood.cells[x,y,z]=dark
            elif q<=.28: wood.cells[x,y,z]=light


def _surface_fruit(leaves, accents, centers, radius, size, palette, berries=False):
    """Attach fruit to the final crown boundary, even where lobes overlap."""
    limit=math.ceil(radius*1.7*16)
    for i,(at,width,depth,angle) in enumerate(centers):
        for j in range(2 if berries else 3):
            axis=0 if (i+j)%2==0 else 2
            other=2-axis; sign=1 if (i+j)%4<2 else -1
            y=round((at[1]-depth*(.08+j*.05))*16)
            cross=round(at[other]*16)
            found=[]
            for along in range(-limit,limit):
                p=[0,y,0]; p[axis]=along; p[other]=cross
                if tuple(p) in leaves.cells: found.append(along)
            if not found: continue
            edge=max(found)+1 if sign>0 else min(found)
            spot=[at[0],(y+.5)/16,at[2]]
            spot[axis]=edge/16+sign*size*.22
            spot[other]=(cross+.5)/16
            box(accents,spot,(size,size,size),palette[(i+j)%len(palette)],cut=1/16)
            if not berries:
                box(accents,(spot[0]-.03,spot[1]+size*.36,spot[2]),
                    (size*.52,size*.26,size*.56),palette[(i+j+1)%len(palette)],cut=0)


def _blossoms(leaves, accents, centers, h, size, palette):
    for i,(at,width,depth,angle) in enumerate(centers):
        for j in range(3):
            turn=angle+j*2.1
            x=round((at[0]+math.cos(turn)*width*.25)*16)
            z=round((at[2]+math.sin(turn)*width*.23)*16)
            top=next((y for y in range(round(h*16)-1,-1,-1) if (x,y,z) in leaves.cells),None)
            if top is None: continue
            y=(top+1)/16
            spot=(x/16,y,z/16)
            box(accents,spot,(size,.25,size*.55),palette[i%len(palette)],cut=1/16)
            box(accents,spot,(size*.55,.25,size),palette[(i+1)%len(palette)],cut=1/16)
            box(accents,(spot[0],y+.125,spot[2]),(size*.32,.125,size*.32),palette[1])


def tree_layers(profile,species,stage,variant,season,picked,footprint):
    p=profile[species]; dims=p[stage]; form=p['form']
    rng=random.Random(p['seed']+100*STAGES.index(stage)+variant*997)
    h,r,trunk=dims['height'],dims['radius'],dims['trunk_radius']
    step=p['wood_step'][stage]
    bark=linear(p['bark'][STAGES.index(stage)])
    color_season='autumn' if season=='autumn_fruiting' else season
    colors=[linear(v) for v in p.get(color_season,p['summer'])]
    wood=Voxels(); leaves=Voxels(); accents=Voxels()
    def timber(a,b,r0,r1): branch_blocks(wood,a,b,r0,r1,bark,step)
    knee=(r*.035,h*form['fork_height'],r*-.025)
    shoulder=(r*form['lean'],h*.62,r*.06)
    tip=(r*(form['lean']-.08),h*.94,-r*.09)
    timber((0,0,0),knee,trunk,trunk*.73)
    timber(knee,shoulder,trunk*.73,trunk*.33)
    timber(shoulder,tip,trunk*.33,max(.0625,trunk*.08))
    for i in range(4):
        angle=i*math.tau/4+.35+variant*.17
        timber((0,trunk*.7,0),(math.cos(angle)*footprint*.43,0,math.sin(angle)*footprint*.43),
               trunk*.38,max(.0625,trunk*.10))
    centers=[]
    evergreen=species in ('pine','juniper')
    if species=='pine':
        for tier in range(dims['tiers']):
            t=tier/max(1,dims['tiers']-1)
            y=h*(.37+.51*t)
            width=r*(1.16-.89*t)
            depth=h*(.28-.10*t)
            at=(r*form['lean']*t,y,r*.07*math.sin(t*4+variant))
            crown(leaves,at,width*1.16,depth,colors[:3],tier)
            for side in range(3):
                angle=side*math.tau/3+tier*.65+variant*.5
                reach=width*(.36+rng.uniform(-.035,.035))
                center=(at[0]+math.cos(angle)*reach,y+depth*rng.uniform(-.14,.06),at[2]+math.sin(angle)*reach)
                timber((at[0],y-depth*.28,at[2]),center,trunk*.21,max(.0625,trunk*.07))
                crown(leaves,center,width*.88,depth*.74,
                      [colors[0],colors[1+(tier+side)%3],colors[3]],angle)
        crown(leaves,(tip[0],h*.955,tip[2]),r*.30,h*.09,colors[2:5],variant)
    else:
        count=dims['limbs']
        for limb in range(count):
            angle=limb*2.399+variant*.55+rng.uniform(-.17,.17)
            t=limb/max(1,count-1)
            reach=r*(.28 if evergreen else .53)*rng.uniform(.86,1.10)
            y=h*(.43+.42*t) if evergreen else h*(.55+.15*t+rng.uniform(-.025,.025))
            width=r*(1.08 if evergreen else 1.15)*rng.uniform(.91,1.06)
            depth=width*form['cluster_depth']
            if stage!='sapling': y=max(y,4+depth*.50)
            center=(math.cos(angle)*reach+shoulder[0]*.35,y,math.sin(angle)*reach)
            start_y=max(knee[1],y*.66)
            along=(start_y-knee[1])/(shoulder[1]-knee[1])
            start=(knee[0]+(shoulder[0]-knee[0])*along,start_y,
                   knee[2]+(shoulder[2]-knee[2])*along)
            fork=(center[0]*.60,y*.85,center[2]*.60)
            timber(start,fork,trunk*.38,trunk*.22)
            timber(fork,center,trunk*.22,max(.0625,trunk*.085))
            for side in (-1,1):
                end=(center[0]+math.cos(angle+side*.8)*width*.30,
                     min(h*.94,y+depth*.44),center[2]+math.sin(angle+side*.8)*width*.30)
                timber(center,end,max(.0625,trunk*.13),max(.0625,trunk*.06))
            if season!='winter' or evergreen:
                crown(leaves,center,width,depth,[colors[0],colors[1+limb%3],colors[3+limb%2]],angle)
            centers.append((center,width,depth,angle))
        if season!='winter' or evergreen:
            depth=h*(.18 if evergreen else .27)
            crown(leaves,(tip[0],h-depth*.495,tip[2]),r*(.78 if evergreen else 1.18),depth,
                  [colors[1],colors[2],colors[4]],variant)
    _wood_palette(wood,bark,trunk,h,variant)
    if species=='apple' and stage!='sapling':
        if season=='spring': _blossoms(leaves,accents,centers,h,dims['accent_size'],[linear(c) for c in p['blossom']])
        if season=='autumn_fruiting': _surface_fruit(leaves,accents,centers,r,dims['accent_size'],[linear(c) for c in p['fruit']])
    if species=='juniper' and stage!='sapling' and not picked:
        _surface_fruit(leaves,accents,centers,r,dims['accent_size'],[linear(c) for c in p['fruit']],True)
    if evergreen and season=='winter': palette_snow(leaves,set(colors),linear(p['snow']),depth=2)
    limit=round(footprint*8)
    for vox in (wood,leaves,accents):
        vox.cells={pos:c for pos,c in vox.cells.items() if 0<=pos[1]<round(h*16) and
            (stage=='sapling' or pos[1]>=64 or (-limit<=pos[0]<limit and -limit<=pos[2]<limit))}
    _grounded_wood(wood)
    return wood,leaves,accents


def tree(profile,species,stage,variant,season,picked,footprint):
    vox=Voxels()
    for layer in tree_layers(profile,species,stage,variant,season,picked,footprint): vox.update(layer)
    return vox


def pine(profile,stage,variant,season):
    footprint={'sapling':1,'mature':2,'ancient':3}[stage]
    return tree(profile,'pine',stage,variant,season,False,footprint)


def branching_tree(profile,species,stage,variant,season,picked,footprint):
    return tree(profile,species,stage,variant,season,picked,footprint)


def assets(only=None):
    profile=read_json('data/art/voxel_trees.json')
    for species in ('pine','oak','apple','juniper'):
        definition=read_json(f'data/entities/flora/{species}_tree.json')[f'base:flora:{species}_tree']
        for stage,settings in definition['stages'].items():
            for group in ('models','picked_models'):
                for season,paths in settings.get(group,{}).items():
                    for variant,path in enumerate([paths] if isinstance(paths,str) else paths):
                        if only and only not in path: continue
                        footprint=definition['placement']['footprint'][stage]
                        vox=tree(profile,species,stage,variant,season,group=='picked_models',footprint)
                        assert vox.cells and min(p[1] for p in vox.cells)==0,path
                        if stage!='sapling':
                            limit=footprint*8
                            assert all(p[1]>=64 or (-limit<=p[0]<limit and -limit<=p[2]<limit) for p in vox.cells),path+' walking clearance'
                        yield path.removeprefix('res://'),{'main':Part(vox)},dict(species=species,stage=stage,
                            season=season,variant=variant,picked=group=='picked_models')

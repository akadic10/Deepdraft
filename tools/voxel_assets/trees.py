"""Hearthblock trees (doc 256): square tiered crowns, square pine plates and stepped
square timber, baked on the native 1:16 object grid."""
import math
import random
from common import Voxels,Part,box,linear,palette_snow,read_json

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


def _upsample(vox, coarse, step):
    for (x,y,z),color in coarse.cells.items():
        for dx in range(step):
            for dy in range(step):
                for dz in range(step): vox.cells[x*step+dx,y*step+dy,z*step+dz]=color


def square_crown(vox, at, width, depth, colors, turn=0):
    """Hearthblock crown: square tiers, dark skirt below and a light cap on top,
    plus two offset square clumps that break the outline (doc 256)."""
    step=4 if width>=2 else 2
    coarse=Voxels()
    def clump(dx,dy,dz,w,hh,d,color,cut=.06):
        box(coarse,((at[0]+dx)/step,(at[1]+dy)/step,(at[2]+dz)/step),(w/step,hh/step,d/step),color,cut=w*cut/step)
    clump(0,-depth*.30,0,width*.80,depth*.22,width*.74,colors[0])
    clump(0,0,0,width,depth*.42,width*.92,colors[1])
    clump(0,depth*.30,0,width*.62,depth*.22,width*.56,colors[2])
    for side,(a,b) in enumerate(((.46,.40),(-.38,-.44))):
        angle=turn+side*2.2
        clump(math.cos(angle)*width*a,depth*(.06 if side==0 else -.10),math.sin(angle)*width*abs(b),
              width*.40,depth*.34,width*.38,colors[2 if side==0 else 1],.04)
    _upsample(vox,coarse,step)


def square_pine(vox, h, r, tiers, lean, variant, colors):
    """Hearthblock pine crown (doc 256): square bough plates, each lit on top with a
    dark underside, over a narrower core that the next plate overhangs; a small
    square spire on top. One coarse step of stagger per plate keeps it hand-made."""
    step=4 if r>=2 else 2
    unit=step/16
    coarse=Voxels()
    def slab(cx,cz,y0,y1,w,color):
        box(coarse,(cx/step,(y0+y1)/2/step,cz/step),(w/step,(y1-y0)/step,w/step),color,cut=w*.04/step)
    base,top=h*.24,h*.84
    spacing=(top-base)/tiers
    for k in range(tiers):
        t=k/max(1,tiers-1)
        w=r*1.4*(1-.62*t)
        y=base+k*spacing
        dx,dz=((1,0),(0,1),(-1,0),(0,-1))[(k+variant)%4]
        cx=r*lean*t+dx*unit; cz=dz*unit
        slab(cx,cz,y,y+spacing*.16,w,colors[0])                 # dark underside
        slab(cx,cz,y+spacing*.16,y+spacing*.62,w,colors[2])     # the lit bough plate
        slab(cx,cz,y+spacing*.62,y+spacing*1.2,w*.74,colors[1])    # core under the next plate
    w=r*1.4*.30
    slab(r*lean,0,top,top+(h-top)*.55,w,colors[3])              # a chunky square spire
    slab(r*lean,0,top+(h-top)*.55,h,w*.5,colors[4])
    _upsample(vox,coarse,step)


def square_timber(wood, a, b, r0, r1, color, step):
    """Hearthblock wood: a squared limb that steps along its path with a square
    section and flat sides, every step face-connected to the next (doc 256)."""
    coarse=Voxels()
    length=math.dist(a,b)
    count=max(2,math.ceil(length*16/step/max(1,min(r0,r1)*16/step))+1)
    for i in range(count):
        t=i/(count-1)
        c=[(a[k]+(b[k]-a[k])*t)*16/step for k in range(3)]
        half=max(.5,(r0+(r1-r0)*t)*16/step)
        lo=[math.floor(c[k]-half) for k in range(3)]; hi=[max(lo[k]+1,math.ceil(c[k]+half)) for k in range(3)]
        for x in range(lo[0],hi[0]):
            for y in range(lo[1],hi[1]):
                for z in range(lo[2],hi[2]): coarse.cells[x,y,z]=color
    _upsample(wood,coarse,step)


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
    def timber(a,b,r0,r1): square_timber(wood,a,b,r0,r1,bark,step)
    crown=square_crown
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
        square_pine(leaves,h,r,dims['tiers'],form['lean'],variant,colors)
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
                        # No baked occlusion on trees: on their large stepped faces it triples the
                        # triangles, and sun, shadow and the tiered values already give depth (doc 256).
                        yield path.removeprefix('res://'),{'main':Part(vox)},dict(species=species,stage=stage,
                            season=season,variant=variant,picked=group=='picked_models')

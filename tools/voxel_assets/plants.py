"""Hand-hewn 1:16 plants: broad foliage, attached crops and complete state families."""
import math
from common import Voxels,Part,box,translate,linear,read_json,branch as _branch,ellipsoid
import hearthblock

SEASONS=('spring','summer','autumn','winter')
RIPE={'blueberry':('summer',),'elderberry':('autumn',),'wild_strawberry':('spring','summer')}
# Hearthblock plants (doc 256), built here from notched square clumps, pads and stalks.
# The first blueberry pilot (tools/hearthblock/art/plants.mjs) is superseded by them.
HEARTHBLOCK=('blueberry','elderberry','wild_strawberry','flowers','reeds')


def _occlusion(species):
    return hearthblock.occlusion() | {'ground':0} if species in HEARTHBLOCK else None


# Crops share the older world-unit primitives. Preserve that contract; this
# revision is limited to wild shrubs, flowers and reeds.
def branch(vox,a,b,r0,r1,color):
    _branch(vox,a,b,max(.05,r0),max(.05,r1),color)


def leaf(vox,start,end,width,color):
    center=tuple((start[i]+end[i])/2 for i in range(3))
    radius=(max(width/2,abs(end[0]-start[0])*.6),.0625,max(width/2,abs(end[2]-start[2])*.6))
    ellipsoid(vox,center,radius,color,power=3)
    branch(vox,start,end,.032,.032,color)


def block(vox,lo,size,color,cut=0):
    """Native-cell cuboid, with deliberate broad corner steps in plan."""
    for x in range(lo[0],lo[0]+size[0]):
        for z in range(lo[2],lo[2]+size[2]):
            if min(x-lo[0],lo[0]+size[0]-1-x)+min(z-lo[2],lo[2]+size[2]-1-z)<cut: continue
            for y in range(lo[1],lo[1]+size[1]): vox.cells[x,y,z]=color


def stem(vox,a,b,width,color):
    """Face-connected stepped stalk, including diagonal one-cell tips."""
    a=tuple(round(v) for v in a); b=tuple(round(v) for v in b)
    previous=list(a); count=max(abs(b[i]-a[i]) for i in range(3))
    def stamp(p): block(vox,tuple(v-width//2 for v in p),(width,)*3,color)
    stamp(previous)
    for t in range(1,count+1):
        point=[round(a[i]+(b[i]-a[i])*t/count) for i in range(3)]
        for axis in (1,0,2):
            previous[axis]=point[axis]; stamp(previous)


def lobe(vox,center,size,colors,index):
    """One chunky asymmetric leaf mass, not a sphere or a stack of thin discs."""
    x,y,z=center; w,h,d=size
    low=y-h//2
    block(vox,(x-w//2+2,low,z-d//2+1),(max(3,w-3),2,max(3,d-2)),colors[0],2)
    block(vox,(x-w//2,low+2,z-d//2),(w,max(2,h-4),d),colors[index%3],3)
    # Offset upper leaf plates and a substantial shoulder interrupt flat roofs.
    block(vox,(x-w//2+1,low+h-2,z-d//2+2),(max(3,w-3),2,max(3,d-3)),colors[(index+1)%3],2)
    block(vox,(x-w//2+2,low+h-1,z-1),(max(4,w//2),3,max(3,d//2-1)),colors[2],1)
    # Two-cell bites are deliberate silhouette variation, not random cell noise.
    edge=x+w//2-2 if index%2 else x-w//2
    for pt in list(vox.cells):
        if edge<=pt[0]<edge+2 and z-2<=pt[2]<z and low+2<=pt[1]<low+h-1:
            del vox.cells[pt]


def blossom(vox,at,color,center,radius=3):
    x,y,z=at
    block(vox,(x-radius,y,z-1),(radius*2+1,2,3),color,1)
    block(vox,(x-1,y,z-radius),(3,2,radius*2+1),color,1)
    block(vox,(x-1,y+1,z-1),(3,2,3),center,1)


def broad_leaf(vox,start,end,width,color):
    """Broad pointed leaf with a stepped shoulder and a substantial midrib."""
    sx,sy,sz=start; ex,ey,ez=end
    dx,dz=ex-sx,ez-sz; length=max(1,math.hypot(dx,dz))
    ux,uz=dx/length,dz/length
    for x in range(math.floor(min(sx,ex)-width),math.ceil(max(sx,ex)+width)+1):
        for z in range(math.floor(min(sz,ez)-width),math.ceil(max(sz,ez)+width)+1):
            along=(x-sx)*ux+(z-sz)*uz
            if not 0<=along<=length: continue
            t=along/length; across=abs(-(x-sx)*uz+(z-sz)*ux)
            span=width*(.30+.70*(1-abs(2*t-1)))
            if across>span: continue
            y=round(sy+(ey-sy)*t)
            block(vox,(x,y,z),(1,2,1),color)
    stem(vox,start,end,1,color)


def _clip(vox,height):
    vox.cells={p:c for p,c in vox.cells.items() if 0<=p[1]<height}
    return vox


def _wood(profile,species,young):
    p=profile[species]; scale=p['young_scale'] if young else 1
    wood=Voxels(); crowns=[]
    forms=p['form']['crowns']
    if young and 'young_crowns' in p['form']:
        forms=p['form']['young_crowns']; scale=1
    for i,(x,y,z,w,h,d) in enumerate(forms):
        center=tuple(round(v*scale) for v in (x,y,z))
        size=tuple(max(6,round(v*scale)) for v in (w,h,d))
        if young and i>=3: break
        crowns.append((center,size))
        knee=(round(center[0]*.35),round(center[1]*.43),round(center[2]*.35))
        stem(wood,(0,0,0),knee,2 if young else 3,linear(p['bark']))
        stem(wood,knee,center,2,linear(p['bark']))
        # Visible fork tips in bare winter, connected to the same stable skeleton.
        tip=(center[0]+(2 if i%2 else -2),center[1]+size[1]//2-2,center[2]+1)
        stem(wood,center,tip,1,linear(p['bark']))
    _clip(wood,16 if young else math.floor(p['height']*16))
    return wood,crowns


def _exposed_fruit(base,profile,species,crowns):
    """Place crops against a real crown face; picking never repaints the plant."""
    fruit=Voxels(); colors=[linear(c) for c in profile[species]['fruit']]
    for i,(center,size) in enumerate(crowns):
        cx,cy,cz=center
        for j in range(2):
            # Opposing visible sides ensure berries read from every quarter-turn.
            axis=2 if (i+j)%2==0 else 0
            sign=1 if j==0 else -1
            y=cy+(1 if j==0 else -2); lateral=cx if axis==2 else cz
            candidates=[p for p in base.cells if p[1]==y and p[2 if axis==0 else 0]==lateral]
            if not candidates: continue
            anchor=max(candidates,key=lambda p:p[axis]*sign)
            location=list(anchor); location[axis]+=sign*2
            if species=='blueberry':
                block(fruit,(location[0]-1,y-1,location[2]-1),(3,3,3),colors[(i+j)%3])
                block(fruit,(location[0]-1,y+1,location[2]-1),(2,1,2),colors[1])
            else:
                # A pendant cluster of three chunky fruits, not scattered dots.
                block(fruit,(location[0]-2,y-1,location[2]-1),(4,3,3),colors[0])
                block(fruit,(location[0]-1,y-3,location[2]-1),(3,3,3),colors[2])
                block(fruit,(location[0]-2,y+1,location[2]-1),(2,1,2),colors[1])
    fruit.cells={p:c for p,c in fruit.cells.items() if p not in base.cells}
    return fruit


# ── Hearthblock plants (doc 256) ────────────────────────────────────────────────
def notched(vox,lo,size,color,n=2):
    """Square cuboid with one clean n x n notch at each corner, instead of a
    staircase of single-cell steps: the trees' corner on the plant scale."""
    x0,y0,z0=lo; w,h,d=size
    for x in range(x0,x0+w):
        for z in range(z0,z0+d):
            if (x-x0<n or x0+w-1-x<n) and (z-z0<n or z0+d-1-z<n): continue
            for y in range(y0,y0+h): vox.cells[x,y,z]=color


def _shades(colors):
    """Season colours dark to light, so a clump always has a dark skirt and a lit cap."""
    return sorted(colors,key=lambda c:.2126*c[0]+.7152*c[1]+.0722*c[2])


def square_clump(vox,center,size,colors):
    """A leaf clump in the trees' vocabulary: dark skirt, body and a lit cap."""
    x,y,z=center; w,h,d=size; low=y-h//2
    notched(vox,(x-w//2+1,low,z-d//2+1),(w-2,2,d-2),colors[0])
    notched(vox,(x-w//2,low+1,z-d//2),(w,h-2,d),colors[1])
    if min(w,d)>=10: notched(vox,(x-w//2+2,low+h-1,z-d//2+2),(w-4,2,d-4),colors[2])
    else: notched(vox,(x-w//2,low+h-2,z-d//2),(w,1,d),colors[2])   # small clumps: a lit top, no tab


def _top(vox,x,z):
    return max(p[1] for p in vox.cells if p[0]==x and p[2]==z)


def _square_shrub(profile,species,season,young):
    """Blueberry and elderberry: canes under square clumps; blossoms on the clump
    tops (blueberry bells in spring, flat elderflower umbels in spring and summer);
    ripe berries on each clump's outward face; bare forked canes in winter."""
    p=profile[species]; bark=linear(p['bark']); form=p['form']
    base=Voxels(); fruit=Voxels(); crowns=[]
    if young and 'young_crowns' in form: forms,scale=form['young_crowns'],1
    elif young: forms,scale=form['crowns'][:3],p['young_scale']
    else: forms,scale=form['crowns'],1
    for (x,y,z,w,h,d) in forms:
        c=tuple(round(v*scale) for v in (x,y,z)); s=tuple(max(6,round(v*scale)) for v in (w,h,d))
        knee=(round(c[0]*.35),round(c[1]*.45),round(c[2]*.35))
        stem(base,(0,0,0),knee,2,bark); stem(base,knee,c,2,bark)
        crowns.append((c,s))
    if season=='winter':
        for i,((x,y,z),(w,h,d)) in enumerate(crowns):
            stem(base,(x,y,z),(x+(2 if i%2 else -2),y+h//2,z+1),1,bark)
            stem(base,(x,y,z),(x+(-1 if i%2 else 1),y+h//2-2,z-2),1,bark)
        return base,fruit
    colors=_shades([linear(c) for c in p[season]])
    for center,size in crowns: square_clump(base,center,size,colors)
    if young: return base,fruit
    bloom=linear(p['blossom']); centre=linear('CEAC62')
    if species=='elderberry' and season in ('spring','summer'):
        for (x,y,z),_ in crowns:
            top=_top(base,x,z)+1
            notched(base,(x-3,top,z-3),(6,1,6),bloom,1)
            for dx,dz in ((-2,-1),(1,0),(-1,1)): base.cells[x+dx,top+1,z+dz]=centre
    if species=='blueberry' and season=='spring':
        for (x,y,z),_ in crowns:
            for dx,dz in ((-3,-2),(2,1)):
                top=_top(base,x+dx,z+dz)+1
                block(base,(x+dx,top,z+dz),(2,1,2),bloom); base.cells[x+dx,top+1,z+dz]=centre
    if season in RIPE[species]:
        berries=[linear(c) for c in p['fruit']]
        for i,((x,y,z),(w,h,d)) in enumerate(crowns):
            # Each clump's outward faces, so every cluster reads from outside the bush.
            primary=0 if abs(x)>=abs(z) else 2
            for j,(axis,row) in enumerate(((primary,y-h//2+3),(2-primary,y-h//2+4)) if species=='elderberry'
                                          else ((primary,y-1),(primary,y+2))):
                sign=1 if (x if axis==0 else z)>=0 else -1
                lane=z if axis==0 else x
                shift=0 if species=='elderberry' else (-3 if j==0 else 2)
                edge=[q[axis] for q in base.cells if q[1]==row and q[2-axis]==lane+shift]
                if not edge: continue
                a0=max(edge)+1 if sign>0 else min(edge)-2
                if species=='elderberry':      # a heavy purple umbel hanging off the clump
                    lo=[0,row-3,0]; lo[axis]=a0; lo[2-axis]=lane-2
                    size=[2,4,4] if axis==0 else [4,4,2]
                    block(fruit,tuple(lo),tuple(size),berries[0])
                    top=list(lo); top[1]=row; block(fruit,tuple(top),(size[0],1,size[2]),berries[1])
                    drip=list(lo); drip[1]-=1; drip[2-axis]+=1; block(fruit,tuple(drip),(1,1,2) if axis==0 else (2,1,1),berries[2])
                else:                           # chunky blueberries with a light top
                    lo=[0,row-1,0]; lo[axis]=a0; lo[2-axis]=lane+shift
                    block(fruit,tuple(lo),(2,2,2),berries[(i+j)%3])
                    top=list(lo); top[1]=row+1; block(fruit,tuple(top),(1,1,1),berries[1])
    fruit.cells={q:c for q,c in fruit.cells.items() if q not in base.cells}
    return base,fruit


def _square_strawberry(profile,season,young):
    """Rosettes of three square leaflet pads on runners, a plus-shaped white flower
    in spring and square red berries with a green cap hanging at the edge."""
    p=profile['wild_strawberry']; base=Voxels(); fruit=Voxels()
    colors=_shades([linear(c) for c in p[season]]); bark=linear(p['bark'])
    roots=[(0,0)] if young else [(round(x*16),round(z*16)) for x,z in p['roots']]
    winter=season=='winter'
    reach=3 if young or winter else 4
    pad=4 if young or winter else 5
    for i,(x,z) in enumerate(roots):
        stem(base,(0,0,0),(x,0,z),1,bark)
        block(base,(x,0,z),(1,3,1),colors[0])
        for j,(dx,dz) in enumerate(((1,0),(0,1),(-1,0),(0,-1))):
            if j==i%4: continue
            y=(2 if winter else 3)+(i+j)%2
            ex,ez=x+dx*reach,z+dz*reach
            stem(base,(x,2,z),(ex,y,ez),1,colors[0])
            notched(base,(ex-pad//2,y,ez-pad//2),(pad,1,pad),colors[1+(i+j)%2],1)
        if young: continue
        if season=='spring':
            fx,fz=x-1,z-1
            stem(base,(x,2,z),(fx,6,fz),1,colors[0])
            notched(base,(fx-1,7,fz-1),(3,1,3),linear(p['blossom']),1)
            base.cells[fx,7,fz]=linear(p['blossom']); base.cells[fx,8,fz]=linear('CCAA56')
            for ddx,ddz in ((-2,0),(2,0),(0,-2),(0,2)): base.cells[fx+ddx,7,fz+ddz]=linear(p['blossom'])
        if season in RIPE['wild_strawberry']:
            fx,fz=x+(2 if i%2 else -2),z+(2 if i<2 else -2)
            stem(base,(x,2,z),(fx,5,fz),1,colors[0])
            red=[linear(c) for c in p['fruit']]
            block(fruit,(fx-1,2,fz-1),(3,3,3),red[i%3])
            block(fruit,(fx,1,fz),(1,1,1),red[(i+1)%3])
            notched(fruit,(fx-1,5,fz-1),(3,1,3),colors[0],1)
    fruit.cells={q:c for q,c in fruit.cells.items() if q not in base.cells}
    return _clip(base,10),_clip(fruit,10)


def _square_leaf(vox,x,y,z,direction,color):
    """An L-shaped square leaf: two cells wide, out three cells, then a raised tip."""
    dx,dz=direction
    for k in range(1,4):
        for w in (-1,0):
            px,pz=(x+dx*k if dx>0 else x-1+dx*k,z+w) if dx else (x+w,z+dz*k if dz>0 else z-1+dz*k)
            vox.cells[px,y,pz]=color
            if k==3: vox.cells[px,y+1,pz]=color


def _square_flowers(profile,variant,season):
    p=profile['flowers']; colors=_shades([linear(c) for c in p[season]]); vox=Voxels()
    petal=linear(p['petals'][variant]); centre=linear(p['centers'][variant])
    for i,(x,z,height) in enumerate(p['arrangements'][variant]):
        x,z=round(x*16),round(z*16)
        h=3+i%2 if season=='winter' else round(height*16)-1
        jog=((1 if i%2 else -1),0) if i<2 else (0,(1 if i%2 else -1))
        mid=(x+jog[0],h//2,z+jog[1]); tx,tz=mid[0],mid[2]
        stem(vox,(x,0,z),(x,h//2,z),2,colors[0]); stem(vox,(x,h//2,z),mid,2,colors[0]); stem(vox,mid,(tx,h,tz),2,colors[0])
        if season!='winter':
            for j in range(2):
                direction=((1,0),(0,1),(-1,0),(0,-1))[(i+2*j+variant)%4]
                _square_leaf(vox,x,round(h*(.22+.26*j)),z,direction,colors[-1])
        if season=='summer' or season=='spring' and i%2==0:
            notched(vox,(tx-3,h,tz-3),(6,1,6),petal,1)
            if variant==1: notched(vox,(tx-2,h+1,tz-2),(4,1,4),petal,1)
            block(vox,(tx-1,h+1+(variant==1),tz-1),(2,1,2),centre)
        elif season=='spring':
            block(vox,(tx-1,h,tz-1),(2,2,2),petal)
        elif season=='autumn':
            notched(vox,(tx-2,h,tz-2),(4,2,4),colors[1],1)
    return _clip(vox,math.floor(p['height']*16))


def _square_reeds(profile,variant,season):
    p=profile['reeds']; colors=_shades([linear(c) for c in p[season]]); vox=Voxels()
    head=linear(p['heads'][season=='autumn'])
    for i,(x,z) in enumerate(p['stems']):
        x,z=round(x*16),round(z*16)
        h=round((p['heights'][variant]-.10*(i%3)-(.20 if season=='spring' else .34 if season=='winter' and i%2 else 0))*16)
        stem(vox,(x,0,z),(x,h-3,z),2,colors[0])
        stem(vox,(x,h-3,z),(x,h-1,z),1,colors[0])
        for j in range(1 if season=='winter' else 2):
            dx,dz=((1,0),(0,1),(-1,0),(0,-1))[(i+2*j+variant)%4]
            y=round(h*(.10+.16*j)); top=round(h*(.48+.14*j))
            ox,oz=(x+(2 if dx>0 else -3),z) if dx else (x,z+(2 if dz>0 else -3))
            for k in (0,1):                                  # out from the stalk...
                for w in (-1,0):
                    px,pz=(ox-dx*k,z+w) if dx else (x+w,oz-dz*k)
                    for yy in (y,y+1): vox.cells[px,yy,pz]=colors[-1]
            for yy in range(y,top):                          # ...then straight up
                for w in (-1,0): vox.cells[(ox,yy,z+w) if dx else (x+w,yy,oz)]=colors[-1]
            vox.cells[(ox,top,z-1) if dx else (x-1,top,oz)]=colors[-1]
        if season in ('summer','autumn') and i%2==0:
            block(vox,(x-2,h-9,z-2),(4,6,4),head)
    return _clip(vox,math.ceil(p['heights'][variant]*16))


def shrub_layers(profile,species,season,young=False):
    """Separate stable structure/foliage and removable crop for state validation."""
    p=profile[species]
    if species=='wild_strawberry':
        return _square_strawberry(profile,season,young) if species in HEARTHBLOCK else _strawberry_layers(profile,season,young)
    if species in HEARTHBLOCK:
        base,fruit=_square_shrub(profile,species,season,young)
        height=16 if young else math.floor(p['height']*16)
        return _clip(base,height),_clip(fruit,height)
    wood,crowns=_wood(profile,species,young)
    base=Voxels(); base.update(wood)
    colors=[linear(c) for c in p.get(season,p['summer'])]
    if season!='winter':
        for i,(center,size) in enumerate(crowns): lobe(base,center,size,colors,i)
        bloom_season=season=='spring' or species=='elderberry' and season=='summer'
        if bloom_season and not young:
            for i,(center,size) in enumerate(crowns):
                x,_,z=center
                y=max(pt[1] for pt in base.cells if pt[0]==x and pt[2]==z)+1
                blossom(base,(x,y,z),linear(p['blossom']),linear('CEAC62'),2 if species=='blueberry' else 3)
    height=16 if young else math.floor(p['height']*16)
    _clip(base,height)
    fruit=_exposed_fruit(base,profile,species,crowns) if not young and season in RIPE[species] else Voxels()
    return base,_clip(fruit,height)


def _strawberry_layers(profile,season,young):
    p=profile['wild_strawberry']; base=Voxels(); fruit=Voxels()
    colors=[linear(c) for c in p[season]]
    roots=[(0,0)] if young else [(round(x*16),round(z*16)) for x,z in p['roots']]
    winter=season=='winter'
    for i,(x,z) in enumerate(roots):
        crown=(x,2 if winter else 3,z)
        stem(base,(0,0,0),(x,0,z),1,linear(p['bark']))
        stem(base,(x,0,z),crown,2,colors[0])
        for j in range(3):
            angle=i*.7+j*math.tau/3
            length=4 if young or winter else 6
            end=(x+round(math.cos(angle)*length),crown[1]+1,z+round(math.sin(angle)*length))
            broad_leaf(base,crown,end,2 if young else 3,colors[(i+j)%3])
        if season=='spring' and not young:
            stem(base,crown,(x-2,6,z-1),1,colors[0])
            blossom(base,(x-2,6,z-1),linear(p['blossom']),linear('CCAA56'),2)
        if season in RIPE['wild_strawberry'] and not young:
            # Red shoulder and tapered tip with a readable green calyx.
            fx,fz=x+3,z+5
            stem(base,crown,(fx,5,fz),1,colors[0])
            block(fruit,(fx-2,3,fz-1),(4,3,3),linear(p['fruit'][i%3]),1)
            block(fruit,(fx-1,1,fz),(2,2,2),linear(p['fruit'][(i+1)%3]))
            block(fruit,(fx-1,5,fz),(2,1,2),colors[0])
    fruit.cells={pt:c for pt,c in fruit.cells.items() if pt not in base.cells}
    return _clip(base,10),_clip(fruit,10)


def shrub(profile,species,season,young=False,picked=False):
    base,fruit=shrub_layers(profile,species,season,young)
    if not picked: base.update(fruit)
    assert min(p[1] for p in base.cells)==0
    return base


def flowers(profile,variant,season):
    if 'flowers' in HEARTHBLOCK: return _square_flowers(profile,variant,season)
    p=profile['flowers']; colors=[linear(c) for c in p[season]]; vox=Voxels()
    for i,(x,z,height) in enumerate(p['arrangements'][variant]):
        x,z=round(x*16),round(z*16)
        h=3+i%2 if season=='winter' else round(height*16)-1
        lean=(-1 if i%2 else 1,1 if i<2 else -1)
        top=(x+lean[0],h,z+lean[1])
        stem(vox,(x,0,z),top,2,colors[0])
        if season!='winter':
            for j in range(2):
                start=(x,round(h*(.25+.28*j)),z); angle=i*1.5+j*2.7
                end=(x+round(math.cos(angle)*4),start[1]+1,z+round(math.sin(angle)*4))
                broad_leaf(vox,start,end,2,colors[j])
        if season=='summer' or season=='spring' and i%2==0:
            blossom(vox,top,linear(p['petals'][variant]),linear(p['centers'][variant]),3)
            if variant==1:
                block(vox,(top[0]-1,h+2,top[2]-1),(3,1,3),linear(p['petals'][variant]),1)
        elif season=='spring':
            block(vox,(top[0]-1,h,top[2]-1),(3,3,3),linear(p['petals'][variant]),1)
        elif season=='autumn':
            block(vox,(top[0]-1,h-1,top[2]-1),(3,3,3),colors[1],1)
    return _clip(vox,math.floor(p['height']*16))


def reeds(profile,variant,season):
    if 'reeds' in HEARTHBLOCK: return _square_reeds(profile,variant,season)
    p=profile['reeds']; colors=[linear(c) for c in p[season]]; vox=Voxels()
    for i,(x,z) in enumerate(p['stems']):
        x,z=round(x*16),round(z*16)
        h=round((p['heights'][variant]-.10*(i%3)-(.20 if season=='spring' else .34 if season=='winter' and i%2 else 0))*16)
        tip=(x+(1 if i%2 else -1),h-1,z)
        stem(vox,(x,0,z),tip,2,colors[0])
        for j in range(1 if season=='winter' else 2):
            at=(x,round(h*(.16+.15*j)),z); angle=i*1.7+j*2.5
            knee=(x+round(math.cos(angle)*4),at[1]+round(h*.4),z+round(math.sin(angle)*4))
            end=(knee[0]+round(math.cos(angle)*2),knee[1]+2,knee[2]+round(math.sin(angle)*2))
            stem(vox,at,knee,2,colors[j]); stem(vox,knee,end,1,colors[j])
            # Widen the middle of each blade into a broad stepped ribbon.
            offset=(1,0,0) if abs(math.sin(angle))>abs(math.cos(angle)) else (0,0,1)
            stem(vox,tuple(at[k]+offset[k] for k in range(3)),tuple(knee[k]+offset[k] for k in range(3)),2,colors[j])
        if season in ('summer','autumn') and i%2==0:
            block(vox,(tip[0]-2,h-7,z-2),(4,6,4),linear(p['heads'][season=='autumn']),1)
            block(vox,(tip[0]-1,h-7,z-1),(2,7,2),linear(p['heads'][season=='autumn']))
    return _clip(vox,math.ceil(p['heights'][variant]*16))


def pack(profile,plant,shrub_root):
    p=profile['packing']; lift=5/16 if shrub_root else 3/16
    vox=Voxels(); cloth=linear(p['cloth']); seam=linear(p['seam'])
    width=1 if shrub_root else 1.25
    box(vox,(0,lift/2,0),(width,lift,width),cloth,cut=.125 if shrub_root else .0625)
    box(vox,(0,lift-.03125,0),(width-.25,.0625,width-.25),linear(p['soil']))
    for axis in range(2):
        box(vox,(0,lift,0),(width,.0625,.0625) if axis==0 else (.0625,.0625,width),seam)
    vox.update(translate(plant,(0,lift,0)))
    return vox


def assets(only=None):
    profile=read_json('data/art/voxel_plants.json')
    for species in RIPE:
        for season in SEASONS:
            base=f'assets/models/flora/bushes/{species}/{species}'
            path=f'{base}_young_{season}.glb'
            if not only or only in path:
                yield path,{'main':Part(shrub(profile,species,season,young=True),occlusion=_occlusion(species))},dict(species=species,season=season,young=True)
            for picked in ((False,True) if season in RIPE[species] else (False,)):
                suffix=season+('_picked' if picked else '')
                for packed in (False,True):
                    path=f'{base}_{"packed_" if packed else ""}{suffix}.glb'
                    if only and only not in path: continue
                    vox=shrub(profile,species,season,picked=picked)
                    if packed: vox=pack(profile,vox,True)
                    yield path,{'main':Part(vox,occlusion=_occlusion(species))},dict(species=species,season=season,picked=picked,packed=packed,young=False)
    for variant in range(3):
        for season in SEASONS:
            for packed in (False,True):
                path=f'assets/models/flora/flowers/flowers_{variant+1}_{"packed_" if packed else ""}{season}.glb'
                if only and only not in path: continue
                vox=flowers(profile,variant,season)
                if packed: vox=pack(profile,vox,False)
                yield path,{'main':Part(vox,occlusion=_occlusion('flowers'))},dict(species='flowers',variant=variant,season=season,packed=packed)
    for variant in range(2):
        for season in SEASONS:
            path=f'assets/models/flora/reeds/reeds_{variant+1}_{season}.glb'
            if only and only not in path: continue
            yield path,{'main':Part(reeds(profile,variant,season),occlusion=_occlusion('reeds'))},dict(species='reeds',variant=variant,season=season)

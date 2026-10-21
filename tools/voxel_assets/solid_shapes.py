"""Analytic solid primitives sampled directly on the 1:16 grid, never triangles.

Profiles and beams retain flat contact planes. Paint and subtraction operate on
occupied cells; every exported face is generated later by the shared greedy baker.
"""
import math
from common import GRID,Voxels,box,ellipsoid


def _unit(v):
    length=math.sqrt(sum(x*x for x in v))
    return tuple(x/length for x in v)


def _cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])


def _scan(low,high):
    return (range(math.floor(a*GRID),math.ceil(b*GRID)) for a,b in zip(low,high))


def _hewn_color(shape,palette,du,dv,t,length):
    """Broad authored bark patches on an unequal, clipped-square timber section.

    Coordinates are local to the beam, so cut ends and plates rotate with it.
    This opt-in style leaves every historical beam and semantic palette intact.
    """
    seed=shape['hewn']
    if min(t,length-t)<1/GRID:
        edge=max(abs(du+.12),abs(dv-.1))
        role='bark' if max(abs(du),abs(dv))>.85 else 'ring' if .40<edge<.60 and dv<.35 else 'heart' if edge<.25 else 'cut'
        return palette['w:'+role]
    face=(0 if du>0 else 2) if abs(du)>abs(dv) else (1 if dv>0 else 3)
    across=dv if abs(du)>abs(dv) else du
    along=int(t*GRID)
    # Several large, offset patches instead of one constant stripe per sector.
    index=(seed+face*3)%7
    start=(3,9,5,13,2,11,7)[index]
    period=(23,31,19,29,37,27,21)[index]
    band=(along-start)%period
    role=('bark','wood_dark','bark_dark','bark')[face]
    shoulder=.2 if band in (0,6) else 0
    if -.5+shoulder<across<.4 and 0<=band<7: role='wood_dark' if face==2 else 'wood'
    if -.2<across<.5 and 2<=band<5: role='wood_light'
    if .5<across<.8 and 8<band<16: role='bark_dark'
    return palette['w:'+role]


def apply(vox,shape,palette):
    op=shape['op']; color=palette[shape['color']]
    target=Voxels()
    if op=='box' and not shape.get('yaw',0):
        box(target,shape['center'],shape['size'],color,shape.get('cut',0))
    elif op=='ellipsoid':
        ellipsoid(target,shape['center'],shape['radius'],color,shape.get('power',3))
    elif op=='box':
        center=shape['center']; half=[s/2 for s in shape['size']]
        angle=shape['yaw']; c,s=math.cos(angle),math.sin(angle)
        radius=math.hypot(half[0],half[2]); cut=shape.get('cut',0)
        ranges=_scan((center[0]-radius,center[1]-half[1],center[2]-radius),(center[0]+radius,center[1]+half[1],center[2]+radius))
        for x in ranges[0]:
            for z in ranges[2]:
                dx,dz=(x+.5)/GRID-center[0],(z+.5)/GRID-center[2]
                u,v=abs(dx*c-dz*s),abs(dx*s+dz*c)
                if u>half[0] or v>half[2] or u+v>half[0]+half[2]-cut: continue
                for y in ranges[1]:
                    if abs((y+.5)/GRID-center[1])<=half[1]: target.cells[x,y,z]=color
    elif op=='profile':
        rings=shape['rings'] # y, radius X, radius Z, centre X, centre Z
        inner=shape.get('inner',0)
        colors=[palette[key] for key in shape.get('colors',[shape['color']])]
        low=(min(r[3]-r[1] for r in rings),rings[0][0],min(r[4]-r[2] for r in rings))
        high=(max(r[3]+r[1] for r in rings),rings[-1][0],max(r[4]+r[2] for r in rings))
        xs,ys,zs=_scan(low,high)
        for y in ys:
            at=(y+.5)/GRID
            for a,b in zip(rings,rings[1:]):
                if not a[0]<=at<=b[0]: continue
                t=(at-a[0])/(b[0]-a[0]); rx,rz,cx,cz=[a[i]+(b[i]-a[i])*t for i in range(1,5)]
                for x in xs:
                    for z in zs:
                        u,v=((x+.5)/GRID-cx)/rx,((z+.5)/GRID-cz)/rz
                        distance=u*u+v*v
                        if inner*inner<=distance<=1:
                            sector=int((math.atan2(v,u)+math.pi)*len(colors)/math.tau)%len(colors)
                            target.cells[x,y,z]=colors[sector]
                break
    elif op=='beam':
        a,b=shape['a'],shape['b']; delta=[b[i]-a[i] for i in range(3)]
        length=math.sqrt(sum(v*v for v in delta)); axis=_unit(delta)
        u=_unit(_cross(axis,(0,0,1) if abs(axis[2])<.8 else (1,0,0))); v=_cross(axis,u)
        ru,rv=shape['radius']; radius=max(ru,rv)
        ranges=list(_scan([min(a[i],b[i])-radius for i in range(3)],[max(a[i],b[i])+radius for i in range(3)]))
        colors=[palette[key] for key in shape.get('colors',[shape['color']])]
        cap=palette.get(shape.get('cap',''),color)
        for x in ranges[0]:
            for y in ranges[1]:
                for z in ranges[2]:
                    p=((x+.5)/GRID-a[0],(y+.5)/GRID-a[1],(z+.5)/GRID-a[2])
                    t=sum(p[i]*axis[i] for i in range(3))
                    if not -1e-8<=t<=length+1e-8: continue
                    du,dv=sum(p[i]*u[i] for i in range(3))/ru,sum(p[i]*v[i] for i in range(3))/rv
                    if 'hewn' in shape:
                        # Flat broad faces with deliberately unequal chamfered
                        # shoulders; maximum radius and flat end planes stay put.
                        cut=1.65 if du+dv>0 else 1.8
                        if length-t<.125 and du>0 and dv>0: cut=1.45
                        if max(abs(du),abs(dv))>1 or abs(du)+abs(dv)>cut: continue
                        target.cells[x,y,z]=_hewn_color(shape,palette,du,dv,t,length)
                        continue
                    if (du*du+dv*dv>1 if shape.get('round',True) else max(abs(du),abs(dv))>1): continue
                    sector=int((math.atan2(dv,du)+math.pi)*len(colors)/math.tau)%len(colors)
                    target.cells[x,y,z]=cap if shape.get('cap') and min(t,length-t)<1/GRID else colors[sector]
    else: raise ValueError('unsupported native solid '+op)
    if 'bank_span' in shape:
        span=shape['bank_span']
        def settle(p):
            z=(p[2]+.5)/GRID
            tail=max(0,z+.5,-z-span-.5)
            return p[0],p[1]-min(2,round(tail*2/.875)),p[2]
        target.cells={settle(p):c for p,c in target.cells.items()}
    for p,c in target.cells.items():
        mode=shape.get('mode','add')
        if mode=='subtract': vox.cells.pop(p,None)
        elif mode!='paint' or p in vox.cells: vox.cells[p]=c

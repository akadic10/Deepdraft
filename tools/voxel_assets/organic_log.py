"""Bounded, deterministic bark relief and drying splits on authored log cells."""
import math
from common import read_json

PROFILE=read_json('data/art/voxel_log_detail.json')
NEIGHBORS=((1,0),(-1,0),(0,1),(0,-1))


def angle_delta(a,b):
    return (a-b+math.pi)%math.tau-math.pi


def bounds(cells):
    return tuple((min(p[i] for p in cells),max(p[i] for p in cells)+1) for i in range(3))


def split_cells(cells,profile):
    top=max(p[1] for p in cells)+1;removed=set()
    for crack in profile['cracks']:
        for a,b in zip(crack['points'],crack['points'][1:]):
            steps=max(abs(b[i]-a[i]) for i in range(2))
            for step in range(steps+1):
                x,z=(round(a[i]+(b[i]-a[i])*step/max(1,steps)) for i in range(2))
                for dx in range(crack['width']):
                    for y in range(top-crack['depth'],top):removed.add((x+dx,y,z))
    return removed&cells


def roles(source,kind):
    """Carve within the existing envelope; every output coordinate is native."""
    original=set(source);profile=PROFILE[kind];extent=bounds(original)
    bottom,top=extent[1];footprint={(x,z) for x,_,z in original}
    # Broad, connected flutes, not random isolated holes or per-cell noise.
    depths={};layer=footprint.copy()
    for depth in range(4):
        rim={p for p in layer if any((p[0]+dx,p[1]+dz) not in layer for dx,dz in NEIGHBORS)}
        depths.update({p:depth for p in rim});layer-=rim
    cells=set()
    for x,y,z in original:
        theta=math.atan2(z+.5,x+.5);dent=0.0
        for angle,width,amount,bend in profile['flutes']:
            offset=bend*math.sin((y-bottom)*.23)
            weight=max(0,1-abs(angle_delta(theta,angle+offset))/width)
            dent=max(dent,amount*weight)
        # Keep the approved maximum extents, while the surrounding rim recedes.
        extreme=x in (extent[0][0],extent[0][1]-1) or z in (extent[2][0],extent[2][1]-1)
        if extreme or depths.get((x,z),4)>=math.ceil(dent-.15):cells.add((x,y,z))
    cracked=split_cells(cells,profile);cells-=cracked
    result={};cx,cz=profile['center']
    for x,y,z in sorted(cells):
        theta=math.atan2(z+.5,x+.5)
        edge=any((x+dx,y,z+dz) not in cells for dx,dz in NEIGHBORS)
        near_split=any((x+dx,y,z+dz) in cracked for dx,dz in NEIGHBORS)
        if near_split or (x,y+1,z) in cracked:
            role='wood' if near_split else 'grain'
        elif edge:
            groove=math.sin(theta*9+.15*math.sin((y-bottom)*.35))+.35*math.sin(theta*17+(y-bottom)*.08)
            role='bark_dark' if groove>.72 else 'bark'
            for angle,height,width,reach in profile['knots']:
                q=(angle_delta(theta,angle)/width)**2+((y+.5-bottom-height*(top-bottom))/reach)**2
                if q<.35:role='wood'
                elif .55<q<1.3:role='bark_dark'
            angle,height,width,reach=profile['peel']
            if (angle_delta(theta,angle)/width)**2+((y+.5-bottom-height*(top-bottom))/reach)**2<1:role='wood'
        else:
            dx,dz=x+.5-cx,z+.5-cz;theta=math.atan2(dz,dx)
            radius=math.hypot(dx,dz)
            radius+=profile['warp']*(math.sin(3*theta+.5)+.4*math.sin(5*theta-1))*min(1,radius/6)
            role='wood' if radius<profile['heart'] else 'grain' if any(lo<=radius<hi for lo,hi in profile['bands']) else 'cut'
        result[x,y,z]=role
    if bounds(result)!=extent:raise ValueError('Organic detail changed approved log bounds')
    return result

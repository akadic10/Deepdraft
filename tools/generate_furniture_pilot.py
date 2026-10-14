"""Isolated faceted log stool, hay bed and frameless hinged door.

World-unit, unit-root closed parts. Exact semantic wood swatches preserve the
existing CraftMaterials recoloring; hay and leaves use independent colors.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import tempfile

from generate_tree_pilot import Mesh, add, sub, mul, cross, dot, unit, linear
from voxel_glb import write_glb

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/models/furniture'
PROFILE=ROOT/'data/art/furniture_pilot.json'


def face(mesh,points,outward,color):
    for i in range(1,len(points)-1):
        a,b,c=points[0],points[i],points[i+1]
        n=cross(sub(b,a),sub(c,a))
        if dot(n,outward)<0: n=mul(n,-1)
        mesh.triangle(a,b,c,n,color)


def cap(mesh, loop, center, normal, colors):
    """Concentric cut-end facets, partitioned rather than coplanar overlays."""
    previous=loop
    for scale,color in zip([.78,.57,.48],colors):
        inside=[add(center,mul(sub(p,center),scale)) for p in loop]
        for i in range(len(loop)):
            j=(i+1)%len(loop)
            mesh.quad(previous[i],previous[j],inside[j],inside[i],normal,color)
        previous=inside
    for i in range(len(loop)):
        mesh.triangle(center,previous[i],previous[(i+1)%len(loop)],normal,colors[0])


def timber(mesh, a, b, radii, palette, sides=8, top_cut=True):
    """Flat-sided timber with broad bark planes and recessed end-grain colors."""
    axis=unit(sub(b,a))
    u=unit(cross(axis,(0,0,1) if abs(axis[2])<.8 else (1,0,0)))
    v=cross(axis,u)
    loops=[]
    for center in [a,b]:
        loops.append([add(center,add(mul(u,math.cos(i*math.tau/sides)*radii[0]),mul(v,math.sin(i*math.tau/sides)*radii[1]))) for i in range(sides)])
    colors=[palette[k] for k in ['bark','wood_dark','bark','wood','bark','bark_dark','bark','wood_dark']]
    for i in range(sides):
        j=(i+1)%sides
        p,q,r,s=loops[0][i],loops[0][j],loops[1][j],loops[1][i]
        face(mesh,[p,q,r,s],sub(p,a),colors[i%len(colors)])
    for loop,center,normal in [(loops[0],a,mul(axis,-1)),(loops[1],b,axis)]:
        cap(mesh,loop,center,normal,[palette['cut'],palette['ring'],palette['heart']] if top_cut else [palette['bark']]*3)


def stool(profile,p):
    m=Mesh(); loops=[]; sides=10
    variation=[1,.98,.94,1,.97,.96,1,.93,.97,.99]
    for y,r in profile['stool_profile']:
        loops.append([(math.cos(i*math.tau/sides)*r*variation[i],y,math.sin(i*math.tau/sides)*r*variation[i]) for i in range(sides)])
    for lo,hi in zip(loops,loops[1:]):
        for i in range(sides):
            j=(i+1)%sides
            pts=[lo[i],lo[j],hi[j],hi[i]]
            normal=cross(sub(pts[1],pts[0]),sub(pts[2],pts[0]))
            if dot(normal,(lo[i][0],0,lo[i][2]))<0: normal=mul(normal,-1)
            # The same wood roles appear on whole broad bark faces.
            color=p[['bark','wood','bark','bark_dark','bark','grain','bark','wood','bark','bark_dark'][i]]
            m.quad(*pts,normal,color)
    cap(m,loops[-1],(0,.75,0),(0,1,0),[p['cut'],p['grain'],p['wood']])
    cap(m,loops[0],(0,0,0),(0,-1,0),[p['bark_dark']]*3)
    return m


def hay_mass(m,center,size,hay):
    """Irregular closed bedding: flat usable center, ragged sloping perimeter."""
    x,y,z=center; w,h,d=size
    outline=[(-.50,-.34),(-.42,-.50),(-.12,-.47),(.16,-.50),(.43,-.46),(.50,-.29),(.48,.09),(.50,.36),(.37,.49),(.04,.47),(-.21,.50),(-.43,.44),(-.50,.18)]
    low=[(x+a*w,y-h*.5,z+b*d) for a,b in outline]
    rim=[(x+a*w,y+h*.16,z+b*d) for a,b in outline]
    top=[(x+a*w*.84,y+h*.5,z+b*d*.84) for a,b in outline]
    for i in range(len(low)):
        j=(i+1)%len(low)
        normal=sub(rim[i],center); normal=(normal[0],0,normal[2])
        face(m,[low[i],low[j],rim[j],rim[i]],normal,hay[i%2])
        n=cross(sub(rim[j],rim[i]),sub(top[j],rim[i]))
        if n[1]<0: n=mul(n,-1)
        m.quad(rim[i],rim[j],top[j],top[i],n,hay[2+i%2])
        m.triangle((x,y+h*.5,z),top[i],top[j],(0,1,0),hay[2])
        m.triangle((x,y-h*.5,z),low[i],low[j],(0,-1,0),hay[0])


def bed(profile,p):
    m=Mesh(); hay=[linear(c) for c in profile['hay']]; leaves=[linear(c) for c in profile['leaves']]
    for x in [-1.45,1.45]: timber(m,(x,.18,-1.48),(x,.18,1.48),(.18,.18),p)
    for z in [-1.18,1.18]: timber(m,(-1.98,.46,z),(1.98,.46,z),(.235,.235),p)
    for x in [-1.12,-.4,.35,1.1]: timber(m,(x,.40,-1.12),(x,.40,1.12),(.067,.067),p)
    hay_mass(m,(0,.57,0),(3.42,.28,2.07),hay)
    # Broad overlapping bundles, staggered ends and edge spill read as loose
    # straw at colony zoom, rather than a rectangular upholstered mattress.
    for i,z in enumerate([-.83,-.42,0,.42,.83]):
        colors=list(hay); colors[2]=hay[2+i%2]
        hay_mass(m,((.02,-.05,.04,-.02,.01)[i],.675,z),(3.45-.08*(i%3),.15,.50),colors)
    # Separate irregular mounds of extra hay support the head; no sewn pillow.
    for x,z,w,d,h in [(-1.22,-.47,.85,.66,.19),(-1.12,.0,.99,.74,.25),(-1.25,.48,.79,.63,.21)]:
        hay_mass(m,(x,.75+h*.5,z),(w,h,d),hay)
    for i in range(20):
        x=-1.60+(i%5)*.79; z=(-.97,-.52,.49,.98)[i//5]+(.045 if i%2 else -.025)
        y=.763 if x>-.75 or abs(z)>.72 else .958
        m.box((x,y,z),(.38+.04*(i%3),.035,.072),hay[3+i%2],.012,yaw=.23*(i%3-1))
    for i,(x,z) in enumerate([(-.52,-.4),(.37,.5),(1.1,-.35),(.85,.76)]):
        center=(x,.77,z)
        ring=[(x-.16,.759,z),(x-.03,.759,z-.095),(x+.20,.759,z+.025),(x+.01,.759,z+.095)]
        for j in range(4):
            face(m,[(x,.79,z),ring[j],ring[(j+1)%4]],(0,1,0),leaves[j%3])
            face(m,[center,ring[j],ring[(j+1)%4]],(0,-1,0),leaves[0])
    return m


def door(profile,p):
    m=Mesh()
    # A thin continuous backing closes the leaf between rough split-log faces.
    m.box((0,1.81,0),(1.99,3.62,.12),p['bark_dark'],.015)
    for i,height in enumerate(profile['door_heights']):
        x=-.75+i*.5
        timber(m,(x,0,0),(x,height,0),(.245,.19),p)
    for sign in [-1,1]:
        for y in [.73,2.96]:
            m.box((0,y,sign*.247),(1.95,.24,.13),p['wood'],.035)
            for x in [-.73,.73]:
                timber(m,(x,y,sign*.27),(x,y,sign*.33),(.06,.06),p)
        # Plain wood pull: a raised grip on two wooden pins, no metal fittings.
        for y in [1.50,1.89]: timber(m,(.63,y,sign*.17),(.63,y,sign*.37),(.045,.045),p)
        m.box((.63,1.695,sign*.37),(.12,.51,.10),p['wood_light'],.025)
    return m


def validate(name,m,profile):
    edges=Counter()
    for i in range(0,len(m.indices),3):
        a,b,c=[m.positions[j] for j in m.indices[i:i+3]]
        n=cross(sub(b,a),sub(c,a))
        assert dot(n,n)>1e-14,(name,'degenerate')
        assert dot(unit(n),m.normals[m.indices[i]])>.999,(name,'normal')
        for x,y in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted(tuple(round(v,7) for v in p) for p in (x,y)))]+=1
    assert all(n==2 for n in edges.values()),(name,'closed components',Counter(edges.values()))
    w,h,d=profile['pieces'][name]['envelope']
    assert all(math.isfinite(v) for p in m.positions for v in p)
    assert all(-w*.5-1e-6<=x<=w*.5+1e-6 and -1e-6<=y<=h+1e-6 and -d*.5-1e-6<=z<=d*.5+1e-6 for x,y,z in m.positions),(name,'envelope')
    assert abs(min(p[1] for p in m.positions))<1e-6,(name,'grounded')
    assert all(0<=v<=1 for c in m.colors for v in c)


def named_leaf(path):
    raw=path.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+size]); blob=raw[28+size:]
    doc['nodes']=[{'name':'door','children':[1]},{'name':'leaf_left','mesh':0}]
    encoded=json.dumps(doc,separators=(',',':')).encode('utf-8')
    encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546C67,2,28+len(encoded)+len(blob))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(blob),0x004E4942)+blob)


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    profile=json.loads(PROFILE.read_text(encoding='utf-8'))
    palettes=json.loads((ROOT/'data/materials/craft_materials.json').read_text(encoding='utf-8'))['source_palettes']
    rows=[]
    with tempfile.TemporaryDirectory(prefix='furniture_pilot_') as temp:
        for name,builder in [('log_chair',stool),('log_bed',bed),('door',door)]:
            colors={k:linear(v) for k,v in palettes[profile['pieces'][name]['palette']]['colors'].items()}
            mesh=builder(profile,colors); validate(name,mesh,profile)
            path=(Path(temp) if args.check else DEST)/(name+'.glb')
            write_glb(path,name,mesh.arrays())
            if name=='door': named_leaf(path)
            if args.check: assert path.read_bytes()==(DEST/path.name).read_bytes(),name
            rows.append({'part':name,'triangles':len(mesh.indices)//3,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    print(json.dumps({'checked':args.check,'parts':rows},indent=2))


if __name__=='__main__': main()

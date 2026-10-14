"""Six faceted deer parts for the isolated animal art pilot.

Root scale one, linear vertex colors, existing body/neck/head/ear/hip anchors.
The reusable leg is in hip-local coordinates; all other parts share feet Y0.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, add, sub, mul, dot, cross, unit, linear
from voxel_glb import write_glb

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/models/animals/deer'
PROFILE=ROOT/'data/art/deer_pilot.json'


def loft(mesh,rings,colors,axis='y'):
    """Closed cut-corner cross sections; palette follows broad anatomical faces."""
    loops=[]
    for distance,rx,ry,offset,cut in rings:
        ring=[(-rx+cut,-ry),(rx-cut,-ry),(rx,-ry+cut),(rx,ry-cut),
              (rx-cut,ry),(-rx+cut,ry),(-rx,ry-cut),(-rx,-ry+cut)]
        loops.append([(x,distance,z+offset) if axis=='y' else (x,z+offset,distance) for x,z in ring])
    for lo,hi in zip(loops,loops[1:]):
        for i in range(8):
            pts=[lo[i],lo[(i+1)%8],hi[(i+1)%8],hi[i]]
            color=colors[i%len(colors)]
            for a,b,c in [(pts[0],pts[1],pts[2]),(pts[0],pts[2],pts[3])]:
                n=cross(sub(b,a),sub(c,a))
                if axis=='y': n=mul(n,-1)
                mesh.triangle(a,b,c,n,color)
    for loop,sign in [(loops[0],-1),(loops[-1],1)]:
        center=tuple(sum(p[k] for p in loop)/8 for k in range(3))
        n=(0,sign,0) if axis=='y' else (0,0,sign)
        for i in range(8): mesh.triangle(center,loop[i],loop[(i+1)%8],n,colors[2%len(colors)])


def branch(mesh,points,radii,color):
    loops=[]
    tangents=[]
    for i,(point,radius) in enumerate(zip(points,radii)):
        axis=unit(sub(points[min(i+1,len(points)-1)],points[max(i-1,0)]))
        side=unit(cross(axis,(1,0,0)))
        other=cross(axis,side)
        loops.append([add(point,mul(add(mul(side,math.cos(j*math.tau/8)),mul(other,math.sin(j*math.tau/8))),radius)) for j in range(8)])
        tangents.append(axis)
    for index,(lo,hi) in enumerate(zip(loops,loops[1:])):
        for i in range(8):
            a,b,c,d=lo[i],lo[(i+1)%8],hi[(i+1)%8],hi[i]
            outward=sub(a,points[index])
            for x,y,z in [(a,b,c),(a,c,d)]:
                n=cross(sub(y,x),sub(z,x))
                if dot(n,outward)<0: n=mul(n,-1)
                mesh.triangle(x,y,z,n,mul(color,(.96,1,.98,1.04)[i%4]))
    for center,loop,normal in [(points[0],loops[0],mul(tangents[0],-1)),(points[-1],loops[-1],tangents[-1])]:
        for i in range(8): mesh.triangle(center,loop[i],loop[(i+1)%8],normal,color)


def leaf(mesh,start,end,width,depth,color):
    """Pointed closed ear with flat front/back facets, without thin open planes."""
    axis=unit(sub(end,start))
    side=unit(cross((0,0,1),axis))
    center=add(start,mul(sub(end,start),.48))
    perimeter=[start,add(center,mul(side,width)),end,sub(center,mul(side,width))]
    for sign in [-1,1]:
        ridge=add(center,(0,0,depth*sign))
        for i in range(4):
            a,b=perimeter[i],perimeter[(i+1)%4]
            n=cross(sub(a,ridge),sub(b,ridge))
            if n[2]*sign<0: n=mul(n,-1)
            mesh.triangle(ridge,a,b,n,color)


def models(profile):
    p={k:linear(v) for k,v in profile['palette'].items()}
    parts={k:Mesh() for k in ['body','neck','head','ears','antlers','leg']}
    m=parts['body']
    loft(m,profile['body_rings'],[p['cream'],p['shade'],p['coat'],p['coat'],p['back'],p['coat'],p['coat'],p['shade']],axis='z')
    # Short lifted tail, cream beneath, attached within the standing footprint.
    branch(m,[(0,1.79,.66),(0,1.77,.83),(0,1.63,.96)],[.13,.11,.028],p['cream'])
    m=parts['neck']
    loft(m,profile['neck_rings'],[p['cream'],p['cream'],p['coat'],p['coat'],p['shade'],p['coat'],p['coat'],p['cream']])
    m=parts['head']
    loft(m,profile['head_rings'],[p['cream'],p['cream'],p['coat'],p['coat'],p['back'],p['coat'],p['coat'],p['cream']],axis='z')
    m.box((0,2.525,-.958),(.215,.145,.075),p['nose'],.025)
    for sign in [-1,1]:
        m.box((sign*.251,2.82,-.536),(.024,.095,.105),p['eye'],.007)
        m.box((sign*.266,2.846,-.556),(.008,.025,.024),p['glint'],.002)
    m=parts['ears']
    for sign in [-1,1]:
        leaf(m,(sign*.16,2.84,-.37),(sign*.67,3.06,-.36),.135,.055,p['back'])
        leaf(m,(sign*.265,2.895,-.41),(sign*.605,3.027,-.405),.071,.018,p['ear'])
    m=parts['antlers']
    for sign in [-1,1]:
        points=[(x*sign,y,z) for x,y,z in profile['antler_branch']]
        branch(m,points,[.07,.063,.055,.042,.012],p['antler'])
        for start,end,radius in [(points[1],(sign*.29,3.42,-.63),.043),(points[2],(sign*.51,3.66,-.52),.035)]:
            branch(m,[start,end],[radius,.012],p['antler'])
    m=parts['leg']
    # Bury the upper leg in the torso while retaining the production hip pivot.
    loft(m,[[-1.05,.074,.070,0,.023],[-.70,.067,.070,.016,.022],[-.43,.098,.098,.018,.027],[.18,.13,.12,0,.04]],
         [p['coat'],p['coat'],p['coat'],p['back'],p['shade'],p['coat'],p['coat'],p['coat']])
    # A beveled sole reaches exactly 1.25 below the unchanged hip pivot;
    # raised toe/heel edges clear the support plane as the rigid leg swings.
    loft(m,[[-1.25,.09,.045,0,.018],[-1.22,.105,.10,-.014,.032],[-1.06,.098,.097,-.01,.03],[-.97,.074,.078,0,.022]], [p['hoof']])
    return parts


def validate(name,m,profile):
    edges=Counter()
    for i in range(0,len(m.indices),3):
        ids=m.indices[i:i+3]
        a,b,c=[m.positions[j] for j in ids]
        normal=cross(sub(b,a),sub(c,a))
        assert dot(normal,normal)>1e-14,(name,'degenerate')
        assert dot(unit(normal),m.normals[ids[0]])>.999,(name,'normal')
        for a,b in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted(tuple(round(v,7) for v in p) for p in (a,b)))]+=1
    assert all(n==2 for n in edges.values()),(name,'closed components',Counter(edges.values()))
    assert all(math.isfinite(v) for p in m.positions for v in p)
    assert all(0<=v<=1 for c in m.colors for v in c)
    height=profile['leg_pivot_height'] if name=='leg' else 0
    assert min(p[1]+height for p in m.positions)>=-1e-7,(name,'ground')
    assert max(p[1]+height for p in m.positions)<profile['standing_envelope'][1]
    assert max(abs(v) for p in m.positions for v in (p[0],p[2]))<=1,(name,'footprint')
    if name=='leg': assert abs(min(p[1] for p in m.positions)+height)<1e-8


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    profile=json.loads(PROFILE.read_text(encoding='utf-8'))
    rows=[]
    with tempfile.TemporaryDirectory(prefix='deer_pilot_') as temp:
        for name,m in models(profile).items():
            validate(name,m,profile)
            path=(Path(temp) if args.check else DEST)/(name+'.glb')
            write_glb(path,name,m.arrays())
            if args.check: assert path.read_bytes()==(DEST/path.name).read_bytes(),name
            rows.append({'part':name,'triangles':len(m.indices)//3,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    print(json.dumps({'checked':args.check,'parts':rows,'assembled_triangles':sum(r['triangles']*(4 if r['part']=='leg' else 1) for r in rows)},indent=2))


if __name__=='__main__': main()

"""Six faceted boulder/scree props, using broad planar fractures rather than voxels.

One closed opaque linear-color surface, unit root and ground Y0. Historical
comparisons remain in the dated art reports. --check verifies geometry and reproduction.
"""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import tempfile

from generate_tree_pilot import Mesh, add, sub, mul, dot, cross, unit, rotate, linear
from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT/'assets/models/rocks'
PROFILE = ROOT/'data/art/ground_stones.json'


def intersection(a,b,c):
    """Intersection of three planes n dot p = d, without an external mesh library."""
    na,da = a; nb,db = b; nc,dc = c
    determinant = dot(na,cross(nb,nc))
    if abs(determinant) < 1e-9: return None
    return mul(add(add(mul(cross(nb,nc),da),mul(cross(nc,na),db)),mul(cross(na,nb),dc)),1/determinant)


def rock(mesh, size, seed, color, face_variation, top_tilt, shoulder, at=(0,0,0), yaw=0):
    """Convex rock from planar cuts: broad sides, asymmetric shoulders and basal chips.

    Every polygon is actually planar, so triangulation adds no artificial diagonal
    shading. Tilted tops are real surfaces, not painted highlights or decals.
    """
    rng = random.Random(seed)
    planes = [((0,-1,0),0),((top_tilt[0],1,top_tilt[1]),1)]
    for i in range(8):
        angle = i*math.tau/8
        normal = (math.cos(angle),0,math.sin(angle))
        distance = 1.0 if i%2 == 0 else rng.uniform(.94,1.08)
        planes.append((normal,distance))
        # The shoulder fracture starts at a different elevation on each side.
        if i%2 == 0:
            slope = shoulder*rng.uniform(.82,1.18)
            planes.append(((normal[0],slope,normal[2]),distance+slope*rng.uniform(.44,.62)))
        else:
            planes.append(((normal[0],-1.6,normal[2]),distance*rng.uniform(.80,.89)))
    vertices = []
    for a,b,c in itertools.combinations(planes,3):
        point = intersection(a,b,c)
        if point is None or any(dot(n,point) > d+1e-7 for n,d in planes): continue
        if any(dot(sub(point,other),sub(point,other)) < 1e-12 for other in vertices): continue
        vertices.append(point)
    max_y = max(p[1] for p in vertices)
    def world(point):
        scaled = (point[0]*size[0]*.5,max(0,point[1])*size[1]/max_y,point[2]*size[2]*.5)
        return add(at,rotate(scaled,yaw))
    first = len(mesh.positions)
    for index,(normal,distance) in enumerate(planes):
        face = [p for p in vertices if abs(dot(normal,p)-distance) < 1e-6]
        if len(face) < 3: continue
        center = mul(tuple(sum(p[axis] for p in face) for axis in range(3)),1/len(face))
        axis = unit(cross(normal,(0,1,0) if abs(normal[1]) < .9 else (1,0,0)))
        along = unit(cross(normal,axis))
        face.sort(key=lambda p: math.atan2(dot(sub(p,center),along),dot(sub(p,center),axis)))
        transformed = [world(p) for p in face]
        # Account for non-uniform world scaling before yawing the face normal.
        actual_normal = rotate(unit((normal[0]/(size[0]*.5),normal[1]/(size[1]/max_y),normal[2]/(size[2]*.5))),yaw)
        tint = mul(color,1+rng.uniform(-face_variation,face_variation))
        for i in range(1,len(face)-1):
            mesh.triangle(transformed[0],transformed[i],transformed[i+1],actual_normal,tint)
    return mesh.positions[first:]


def models(profile):
    palette = [linear(c) for c in profile['palette']]
    for variant,p in enumerate(profile['boulders']):
        mesh = Mesh()
        rock(mesh,p['size'],p['seed'],palette[variant],profile['face_variation'],p['top_tilt'],p['shoulder'])
        yield f'boulders/boulder_{variant+1}.glb',mesh,2.0,2.0
    for variant,clump in enumerate(profile['scree']):
        mesh = Mesh()
        mesh.stones = []
        for index,(x,z,width,height,depth,yaw) in enumerate(clump):
            points = rock(mesh,(width,height,depth),9200+variant*101+index,palette[(index+variant)%3],profile['face_variation'],(.18,-.14),1.2,(x,0,z),yaw)
            mesh.stones.append(points)
        yield f'scree/scree_{variant+1}.glb',mesh,3.0,.5


def validate(name,mesh,width,height):
    assert abs(min(p[1] for p in mesh.positions)) < 1e-8, (name,'ground')
    assert max(p[1] for p in mesh.positions) <= height+1e-7, (name,'height')
    assert max(abs(v) for p in mesh.positions for v in (p[0],p[2])) <= width*.5, (name,'footprint')
    assert all(math.isfinite(v) for p in mesh.positions for v in p)
    assert all(c[3] == 1.0 and all(0 <= v <= 1 for v in c) for c in mesh.colors)
    edges = {}
    for i in range(0,len(mesh.indices),3):
        ids = mesh.indices[i:i+3]
        a,b,c = [mesh.positions[j] for j in ids]
        n = cross(sub(b,a),sub(c,a))
        assert dot(n,n) > 1e-15 and dot(n,mesh.normals[ids[0]]) > 0, (name,'winding/degenerate face')
        for j in range(3):
            key = tuple(sorted(tuple(round(v,7) for v in mesh.positions[ids[k]]) for k in (j,(j+1)%3)))
            edges[key] = edges.get(key,0)+1
    assert all(count == 2 for count in edges.values()), (name,'closed manifold')
    # Each loose stone is individually grounded; pairs have open planar gaps.
    if hasattr(mesh,'stones'):
        bounds = []
        for points in mesh.stones:
            assert abs(min(p[1] for p in points)) < 1e-8
            bounds.append((min(p[0] for p in points),max(p[0] for p in points),min(p[2] for p in points),max(p[2] for p in points)))
        for a,b in itertools.combinations(bounds,2):
            assert a[1] < b[0] or b[1] < a[0] or a[3] < b[2] or b[3] < a[2], (name,'loose stones touch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    profile = json.loads(PROFILE.read_text(encoding='utf-8'))
    rows = []
    with tempfile.TemporaryDirectory(prefix='deepdraft_stones_') as tmp:
        for name,mesh,width,height in models(profile):
            validate(name,mesh,width,height)
            path = Path(tmp)/name if args.check else DEST/name
            write_glb(path,Path(name).stem,mesh.arrays())
            if args.check: assert path.read_bytes() == (DEST/name).read_bytes(), (name,'reproducibility')
            rows.append({'path':name,'triangles':len(mesh.indices)//3,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    if args.check:
        definitions = json.loads((ROOT/'data/entities/surface_details.json').read_text(encoding='utf-8'))
        paths = {p for key in ('base:detail:boulder','base:detail:scree') for p in definitions[key]['models']}
        assert paths == {'res://assets/models/rocks/'+row['path'] for row in rows}
    else:
        out = ROOT/'tmp/ground_stones_20261013'
        out.mkdir(parents=True,exist_ok=True)
        (out/'assets.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    print(f"GROUND_STONES_{'CHECK' if args.check else 'BUILD'}_PASS {len(rows)} models; {sum(r['triangles'] for r in rows)} triangles")


if __name__ == '__main__': main()

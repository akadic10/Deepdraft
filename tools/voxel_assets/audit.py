"""Validate complete family geometry and the exact bytes reviewed by Godot."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
from common import ROOT
from coverage import validate_coverage


def read(path):
    raw=path.read_bytes()
    assert struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw)),str(path)
    size,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4e4f534a
    doc=json.loads(raw[20:20+size]); blob=raw[28+size:]
    assert len(blob)==doc['buffers'][0]['byteLength']
    return doc,blob


def values(doc,blob,index):
    accessor=doc['accessors'][index]; view=doc['bufferViews'][accessor['bufferView']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[accessor['type']]
    fmt='<'+{5126:'f',5125:'I',5123:'H',5121:'B'}[accessor['componentType']]*width
    stride=view.get('byteStride',struct.calcsize(fmt))
    offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    return [struct.unpack_from(fmt,blob,offset+i*stride) for i in range(accessor['count'])]


def audit_family(base,family,review=None):
    manifest=json.loads((base/(family+'.json')).read_text())
    rows=manifest['assets']
    assert len({r['path'] for r in rows})==len(rows),'duplicate manifest paths'
    validate_coverage(family,[r['path'] for r in rows])
    report={'family':family,'assets':len(rows),'visual_triangles':0,'shadow_triangles':0,'bytes':0,
            'fine_shadow_fallbacks':[]}
    for row in rows:
        path=base/row['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],'stale manifest '+str(path)
        if review is not None:
            assert review.get('hashes',{}).get(row['path'])==row['sha256'],'native review does not match '+str(path)
        doc,blob=read(path)
        assert all(not any(key in n for key in ('translation','scale','rotation','matrix')) for n in doc['nodes']),'transformed source pivot'
        names=[n.get('name') for n in doc['nodes']]
        assert len(names)==len(set(names)),'Godot requires globally unique part names'
        for node in doc['nodes']:
            if 'mesh' not in node: continue
            mesh=doc['meshes'][node['mesh']]
            assert len(mesh['primitives'])==1,'multiple surfaces'
            primitive=mesh['primitives'][0]; attributes=primitive['attributes']
            vertices=values(doc,blob,attributes['POSITION'])
            normals=values(doc,blob,attributes['NORMAL'])
            colors=values(doc,blob,attributes['COLOR_0'])
            indices=[v[0] for v in values(doc,blob,primitive['indices'])]
            assert len(vertices)==len(normals)==len(colors)
            assert all(math.isfinite(v) and abs(v*16-round(v*16))<.00001 for p in vertices for v in p),'off-grid vertex'
            assert all(sum(abs(v) for v in n)==1 and all(v in (-1,0,1) for v in n) for n in normals),'non-axial normal'
            assert all(all(math.isfinite(v) and 0<=v<=1 for v in c) and c[3]==1 for c in colors),'invalid palette'
            assert len(indices)%3==0 and all(0<=i<len(vertices) for i in indices),'invalid indices'
            for start in range(0,len(indices),3):
                a,b,c=[vertices[i] for i in indices[start:start+3]]
                u=[b[i]-a[i] for i in range(3)]; v=[c[i]-a[i] for i in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                assert sum(x*x for x in cross)>0,'degenerate triangle'
            key='shadow_triangles' if node['name'].startswith('VoxelShadowProxy') else 'visual_triangles'
            report[key]+=len(indices)//3
        report['bytes']+=row['bytes']
        for part in row['parts']:
            if part['shadow'] and part['shadow']['stride']==1: report['fine_shadow_fallbacks'].append(row['path']+':'+part['name'])
    if review is not None:
        assert review['count']==len(rows) and not review['failures'],'incomplete/failed native gallery'
    report['shadow_triangle_reduction']=1-report['shadow_triangles']/report['visual_triangles']
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('family')
    parser.add_argument('--base',type=Path,default=ROOT/'tmp/voxel_migration_20261018/staged')
    parser.add_argument('--review',type=Path)
    args=parser.parse_args()
    review=json.loads(args.review.read_text()) if args.review else None
    report=audit_family(args.base,args.family,review)
    (args.base/(args.family+'_audit.json')).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__': main()

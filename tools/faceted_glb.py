"""Small offline GLB helpers for named articulated parts and retained effects."""
import copy
import json
import struct
import tempfile
from pathlib import Path
from voxel_glb import write_glb
from generate_tree_pilot import Mesh


def read(path):
    raw=Path(path).read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+size]),raw[28+size:]


def source_mesh(path,name):
    doc,blob=read(path)
    node=next(n for n in doc['nodes'] if n.get('name')==name and 'mesh' in n)
    primitive=doc['meshes'][node['mesh']]['primitives'][0]
    def values(index):
        a=doc['accessors'][index]; v=doc['bufferViews'][a['bufferView']]
        fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        stride=v.get('byteStride',struct.calcsize(fmt)*width)
        offset=v.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from('<'+fmt*width,blob,offset+i*stride) for i in range(a['count'])]
    m=Mesh(); attrs=primitive['attributes']
    m.positions=values(attrs['POSITION']); m.normals=values(attrs['NORMAL'])
    m.colors=[tuple(c[:3])+(c[3] if len(c)>3 else 1.0,) for c in values(attrs['COLOR_0'])]
    m.indices=[x[0] for x in values(primitive['indices'])]
    return m


def write_parts(path,parts):
    """Unit roots; every dictionary key becomes a named MeshInstance3D."""
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    doc={'asset':{'version':'2.0','generator':'Deepdraft faceted furniture'},'scene':0,
         'scenes':[{'nodes':[0]}],'nodes':[{'name':path.stem,'children':[]}],
         'meshes':[],'materials':[],'accessors':[],'bufferViews':[]}
    blob=b''
    with tempfile.TemporaryDirectory() as temp:
        for name,mesh in parts.items():
            part=Path(temp)/(name+'.glb'); write_glb(part,name,mesh.arrays())
            src,data=read(part)
            vi,ai,mi=len(doc['bufferViews']),len(doc['accessors']),len(doc['materials'])
            for v in src['bufferViews']:
                v['byteOffset']=v.get('byteOffset',0)+len(blob); doc['bufferViews'].append(v)
            for a in src['accessors']:
                a['bufferView']+=vi; doc['accessors'].append(a)
            m=copy.deepcopy(src['meshes'][0])
            for p in m['primitives']:
                p['attributes']={k:v+ai for k,v in p['attributes'].items()}
                p['indices']+=ai; p['material']+=mi
            doc['materials'].extend(src['materials'])
            doc['nodes'][0]['children'].append(len(doc['nodes']))
            doc['nodes'].append({'name':name,'mesh':len(doc['meshes'])})
            doc['meshes'].append(m); blob+=data
    doc['buffers']=[{'byteLength':len(blob)}]
    encoded=json.dumps(doc,separators=(',',':')).encode(); encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+
                    struct.pack('<II',len(encoded),0x4e4f534a)+encoded+
                    struct.pack('<II',len(blob),0x004e4942)+blob)

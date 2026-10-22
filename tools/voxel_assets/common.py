"""World-unit voxel authoring and named-part GLB export for production assets."""
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
from voxel_glb import Voxels, greedy_mesh_from_voxels, write_glb_meshes
from voxel_shadow import shadow_mesh

GRID = 16


def linear(value):
    channels = [int(value[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in channels)


def box(vox, center, size, color, cut=0):
    lo = [round((center[i]-size[i]/2)*GRID) for i in range(3)]
    hi = [max(lo[i]+1,round((center[i]+size[i]/2)*GRID)) for i in range(3)]
    trim = round(cut*GRID)
    for x in range(lo[0],hi[0]):
        for z in range(lo[2],hi[2]):
            if min(x-lo[0],hi[0]-1-x)+min(z-lo[2],hi[2]-1-z)<trim: continue
            for y in range(lo[1],hi[1]): vox.cells[x,y,z]=color


def ellipsoid(vox, center, radius, color, power=2):
    c = [v*GRID for v in center]
    r = [max(.55,v*GRID) for v in radius]
    for x in range(math.floor(c[0]-r[0]),math.ceil(c[0]+r[0])):
        a = abs((x+.5-c[0])/r[0])**power
        if a>1: continue
        for y in range(math.floor(c[1]-r[1]),math.ceil(c[1]+r[1])):
            remain=1-a-abs((y+.5-c[1])/r[1])**power
            if remain<=0: continue
            span=r[2]*remain**(1/power)
            for z in range(math.ceil(c[2]-span-.5),math.floor(c[2]+span-.5)+1):
                vox.cells[x,y,z]=color


def branch(vox, a, b, r0, r1, color):
    """Sample a tapered capsule analytically; no repeated ball unions."""
    a=tuple(v*GRID for v in a); b=tuple(v*GRID for v in b)
    r0=max(.6,r0*GRID); r1=max(.6,r1*GRID)
    delta=[b[i]-a[i] for i in range(3)]
    length2=sum(v*v for v in delta)
    if length2<1e-10:
        ellipsoid(vox,[v/GRID for v in a],[r0/GRID]*3,color)
        return
    radius=max(r0,r1)
    axis=max(range(3),key=lambda i:abs(delta[i]))
    others=[i for i in range(3) if i!=axis]
    u,v=others
    # A bounded slab along the dominant axis avoids scanning a huge diagonal AABB.
    for w in range(math.floor(min(a[axis],b[axis])-radius),math.ceil(max(a[axis],b[axis])+radius)):
        along=max(0,min(1,(w+.5-a[axis])/delta[axis]))
        local_r=radius*1.8+1
        cu,cv=a[u]+delta[u]*along,a[v]+delta[v]*along
        for x in range(math.floor(cu-local_r),math.ceil(cu+local_r)):
            for z in range(math.floor(cv-local_r),math.ceil(cv+local_r)):
                point=[0,0,0]; point[axis]=w; point[u]=x; point[v]=z
                rel=[point[i]+.5-a[i] for i in range(3)]
                t=max(0,min(1,sum(rel[i]*delta[i] for i in range(3))/length2))
                r=r0+(r1-r0)*t
                if sum((rel[i]-delta[i]*t)**2 for i in range(3))<=r*r:
                    vox.cells[tuple(point)]=color


def translate(vox, offset):
    delta=tuple(round(v*GRID) for v in offset)
    result=Voxels()
    result.cells={tuple(p[i]+delta[i] for i in range(3)):color for p,color in vox.cells.items()}
    return result


def palette_snow(vox, foliage_colors, snow, depth=2):
    """Recolor only the exposed top skin of foliage, retaining shape and wood."""
    tops={}
    for x,y,z in vox.cells:
        tops[x,z]=max(tops.get((x,z),y),y)
    for (x,z),top in tops.items():
        for y in range(top,top-depth,-1):
            if vox.cells.get((x,y,z)) not in foliage_colors: break
            vox.cells[x,y,z]=snow


@dataclass
class Part:
    voxels: Voxels
    shadow: bool = True
    occluders: object = None
    occlusion: object = None  # opt-in baked corner occlusion settings (voxel_occlusion.json)


def _write_doc(path, doc, blob):
    encoded=json.dumps(doc,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+
                     struct.pack('<II',len(encoded),0x4e4f534a)+encoded+
                     struct.pack('<II',len(blob),0x004e4942)+blob)


def export_asset(path, parts, stride=4, coverage=.6):
    """Each articulated name becomes a parent of its visual/proxy pair.

    A single `main` part uses the asset root as its parent. Non-casting special
    parts retain their original mesh node names (for flame-frame consumers).
    """
    path=Path(path)
    meshes={}; descriptors=[]; report=[]
    for name,part in parts.items():
        vox=part.voxels
        if not vox.cells: raise ValueError(f'{path}: {name} is empty')
        visual=greedy_mesh_from_voxels(vox,part.occluders,part.occlusion)
        if not visual[0]: raise ValueError(f'{path}: {name} has no visible surface')
        first=len(meshes)+1
        meshes[f'{name}_visual']=visual
        proxy_info=None
        children=[first]
        if part.shadow:
            proxy,proxy_info=shadow_mesh(vox,stride,coverage)
            children.append(first+1)
            meshes[f'{name}_shadow']=proxy
        descriptors.append((name,part.shadow,children))
        positions=visual[0]
        report.append({'name':name,'cells':len(vox),'visual_triangles':len(visual[3])//3,
                       **({'occlusion':True} if part.occlusion else {}),
                       'shadow':proxy_info,'min':[min(p[i] for p in positions)/GRID for i in range(3)],
                       'max':[max(p[i] for p in positions)/GRID for i in range(3)]})
    write_glb_meshes(path,path.stem,meshes,1/GRID)
    raw=path.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+size]); blob=raw[28+size:]
    doc['nodes'][0]['children']=[]
    for name,casts,children in descriptors:
        if not casts:
            doc['nodes'][children[0]]['name']=name
            # Godot retains glTF extras as metadata. Consumers can apply this
            # policy without relying on flame/overlay display names.
            doc['nodes'][children[0]]['extras']={'voxel_cast_shadow':False}
            doc['meshes'][doc['nodes'][children[0]]['mesh']]['extras']={'voxel_cast_shadow':False}
            doc['nodes'][0]['children'].append(children[0])
            continue
        doc['nodes'][children[0]]['name']='VoxelVisual'
        doc['nodes'][children[1]]['name']='VoxelShadowProxy'
        if len(parts)==1 and name=='main':
            doc['nodes'][0]['children']=children
        else:
            # Godot's glTF importer uniquifies node names across the file, not
            # only siblings. Explicit part suffixes retain pairing after import.
            doc['nodes'][children[0]]['name']='VoxelVisual__'+name
            doc['nodes'][children[1]]['name']='VoxelShadowProxy__'+name
            doc['nodes'][0]['children'].append(len(doc['nodes']))
            doc['nodes'].append({'name':name,'children':children})
    _write_doc(path,doc,blob)
    return {'parts':report,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def read_json(relative):
    return json.loads((ROOT/relative).read_text(encoding='utf-8-sig'))

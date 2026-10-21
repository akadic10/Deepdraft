"""Native voxel solids for every modular appearance and equipped tool."""
from common import Voxels,Part,linear,read_json
from micro_voxel_study.generate import solid


def surface_keys(cells):
    faces=set()
    for p in cells:
        for axis in range(3):
            u,v=[i for i in range(3) if i!=axis]
            for sign in (-1,1):
                n=list(p); n[axis]+=sign
                if tuple(n) not in cells: faces.add((axis,sign,p[axis]+(sign>0),p[u],p[v]))
    return faces


def separate_overlay(vox,head_faces):
    """Cover coincident skin/hair exterior faces with one outward color cell.

    The study could remove head cells behind its single fixed haircut. The
    production head also serves bald dwarves, so every wearable must cover its
    skin boundary without relying on holes in the shared head or a depth bias.
    """
    for attempt in range(8):
        additions={}
        for p,color in vox.cells.items():
            for axis in range(3):
                u,v=[i for i in range(3) if i!=axis]
                for sign in (-1,1):
                    n=list(p); n[axis]+=sign; n=tuple(n)
                    if n not in vox.cells and (axis,sign,p[axis]+(sign>0),p[u],p[v]) in head_faces: additions[n]=color
        if not additions: return
        vox.cells.update(additions)
    raise ValueError('overlay clearance did not converge')


def assets(only=None):
    profile=read_json('data/art/voxel_dwarves.json')
    palette={key:linear(value) for key,value in profile['palette'].items()}
    assert profile['cells_per_block']==16
    head_faces=set()
    for name,shapes in profile['parts'].items():
        if name.startswith('body/head_'):
            skin=Voxels()
            for shape in shapes: solid(skin,shape,palette)
            head_faces.update(surface_keys(skin.cells))
    for name,shapes in profile['parts'].items():
        path='assets/models/characters/dwarves/'+name+'.glb'
        if only and only not in path: continue
        vox=Voxels()
        for shape in shapes: solid(vox,shape,palette)
        if name.startswith(('hair/','beards/','eyebrows/','scars/')): separate_overlay(vox,head_faces)
        # Tiny scars are portrait overlays. Retain a pair in the reusable file;
        # the portrait owner suppresses all casting, including this proxy.
        yield path,{'main':Part(vox)},dict(part=name,baked_proportions=True,portrait_only=name.startswith('scars/'))

"""Native voxel solids for every modular appearance and equipped tool."""
from common import Voxels,Part,linear,read_json
from micro_voxel_study.generate import solid
import hearthblock



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
    # Hearthblock (doc 256) redraws every appearance part; tools keep their solids.
    art=read_json(hearthblock.DATA)['models']
    built={}
    for name,shapes in profile['parts'].items():
        if name in art: built[name]=hearthblock.model(name)
        else:
            built[name]=Voxels()
            for shape in shapes: solid(built[name],shape,palette)
    heads=[built[n].cells for n in built if n.startswith('body/head_')]
    head_faces=set().union(*(surface_keys(h) for h in heads))
    head_common=set(heads[0]).intersection(*heads[1:])
    def union(prefix): return set().union(*(built[n].cells.keys() for n in built if n.startswith(prefix)))
    body,hair_m,hair_f,beards=set(built['body/body_base'].cells),union('hair/hair_m_'),union('hair/hair_f_'),union('beards/')
    for name,vox in built.items():
        path='assets/models/characters/dwarves/'+name+'.glb'
        if only and only not in path: continue
        new=name in art
        if new and name.startswith(('hair/','beards/','eyebrows/')):
            # Any pairing must stay free of shared cells: wearables give way to the
            # torso, beards to every man's hairstyle, brows to fringes and beards.
            clip=set(body)
            if name.startswith('beards/'): clip|=hair_m
            if name.startswith('eyebrows/brows_m_'): clip|=hair_m|beards
            if name.startswith('eyebrows/brows_f_'): clip|=hair_f
            vox.cells={p:c for p,c in vox.cells.items() if p not in clip}
        if name.startswith(('hair/','beards/','eyebrows/','scars/')): separate_overlay(vox,head_faces)
        rigid=new and name.startswith(('hair/','beards/','eyebrows/','scars/','body/eyes'))
        part=Part(vox,occluders=head_common if rigid else None,occlusion=hearthblock.occlusion(name) if new else None)
        parts={'main':part}
        if new and name=='body/hand':
            # The proposal's tunic cuff is its own mesh: DwarfAgent tints the mitten
            # with the dwarf's skin and leaves the cuff's baked cloth colour alone.
            parts={'mitten':part,'cuff':Part(hearthblock.model('body/hand_cuff'),occlusion=hearthblock.occlusion('body/hand_cuff'))}
        # Tiny scars are portrait overlays. Retain a pair in the reusable file;
        # the portrait owner suppresses all casting, including this proxy.
        yield path,parts,dict(part=name,baked_proportions=True,portrait_only=name.startswith('scars/'),
                              **({'source':hearthblock.DATA} if new else {}))

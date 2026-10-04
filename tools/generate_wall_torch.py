#!/usr/bin/env python3
"""Author the wall torch at 8 voxels/block and stage a Godot lighting review."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import struct

from voxel_glb import Voxels, write_glb, _pad4
from generate_tavern_redesign import box, export_mesh, sha, rgb

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/wall_torch.glb'
FLAME_MODEL = 'assets/models/furniture/animations/wall_torch_flame.glb'
IRON = tuple(rgb(h) for h in ('292A2D', '414044', '5A5858', '77716A'))
WOOD = tuple(rgb(h) for h in ('231A13', '352419', '4A3018', '684827'))
FIRE = tuple(rgb(h) for h in ('C94717', 'ED7120', 'FFAB32', 'FFDA69', 'FFF1AF'))


def torch():
    body, flame = Voxels(), Voxels()
    # Stepped iron backplate and a stout projecting cradle. Wall surface is Z=0.
    box(body,-1,1,0,7,0,1,IRON[1])
    box(body,-2,2,1,6,0,1,IRON[2])
    box(body,-1,1,1,3,1,4,IRON[1])
    box(body,-1,1,2,4,3,5,IRON[0])
    body.cells[-1,5,0] = IRON[3]
    body.cells[0,1,0] = IRON[3]
    # Squared, charred handle, retaining a warm front face between iron bands.
    box(body,-1,1,2,8,3,5,WOOD[2])
    box(body,-1,0,3,6,4,5,WOOD[3])
    box(body,-1,1,6,8,3,5,WOOD[0])
    box(body,-2,2,3,4,2,6,IRON[1])
    box(body,-2,2,6,7,2,6,IRON[2])
    box(body,-1,1,6,7,5,6,IRON[3])
    # Open basket prongs frame the flame instead of a featureless square cap.
    for x in (-2,1):
        box(body,x,x+1,7,9,2,3,IRON[0])
        box(body,x,x+1,7,8,5,6,IRON[1])
    # Broad amber shoulders, hot pale core and an offset licking tip.
    rows = {
        7: [(-1,3),(0,3),(-1,4),(0,4)],
        8: [(x,z) for x in range(-2,2) for z in range(2,6)],
        9: [(x,z) for x in range(-2,2) for z in range(3,6)] + [(-3,4)],
        10: [(-1,3),(0,3),(-1,4),(0,4),(-1,5)],
        11: [(-1,3),(-1,4)],
    }
    for y, cells in rows.items():
        for x,z in cells:
            if (x,y,z) in body.cells:
                continue
            c = FIRE[1] if y in (7,11) else FIRE[2]
            if y==8 and x in (-1,0):
                c = FIRE[4] if z==5 else FIRE[3]
            elif y==9 and x==-1:
                c = FIRE[3]
            elif x==-3 or (x==1 and z==3):
                c = FIRE[0]
            flame.cells[x,y,z] = c
    return body, flame


def flame_frames():
    """Eight sculpted voxel silhouettes: rising tongues, split tips and collapse.

    Keep the hot base fixed in the basket and every cell within the installed
    torch's existing envelope. Only the upper flame changes shape and color.
    """
    body, baseline = torch()
    # (left shoulder, top row, next row) in integer voxel coordinates.
    silhouettes = [
        ([(-3,4)], [(-1,3),(-1,4)], [(-1,3),(0,3),(-1,4),(0,4),(-1,5)]),
        ([], [(0,4)], [(-1,3),(0,3),(-1,4),(0,4),(0,5)]),
        ([(-3,3)], [], [(-2,3),(-1,3),(-2,4),(-1,4)]),
        ([], [(-2,4),(0,4)], [(-2,3),(-2,4),(-1,4),(0,4),(0,5)]),
        ([(-3,4),(-3,5)], [(-2,4)], [(-2,3),(-1,3),(-2,4),(-1,4)]),
        ([], [], [(-1,4),(0,4),(-1,5),(0,5)]),
        ([(-3,4)], [(0,3)], [(-1,3),(0,3),(-1,4),(0,4)]),
        ([], [(-1,5)], [(-1,4),(0,4),(-1,5)]),
    ]
    frames = []
    for i,(shoulder,tip,neck) in enumerate(silhouettes):
        vox = Voxels()
        vox.cells = {p:c for p,c in baseline.cells.items() if p[1]<=8}
        row9 = [(x,z) for x in range(-2,2) for z in range(3,6)]
        if i in (2,5,7):
            row9 = [(x,z) for x,z in row9 if x in (-1,0)]
        if i==2:
            row9.append((-2,3))
        for y,row in ((9,row9+shoulder),(10,neck),(11,tip)):
            for x,z in row:
                color = FIRE[1] if y==11 else FIRE[2]
                if y==9 and x in (-1,0):
                    color = FIRE[3]
                if x==-3:
                    color = FIRE[0]
                vox.cells[x,y,z] = color
        # A drifting hot core moves through the amber body without moving its base.
        hot_x = -1 if i in (0,2,4,7) else 0
        for x in (-1,0):
            for z in (3,4,5):
                if (x,8,z) in vox.cells:
                    vox.cells[x,8,z] = FIRE[4] if x==hot_x else FIRE[3]
        if i==0:
            vox.cells = dict(baseline.cells) # original approved silhouette is frame 0
        assert not set(vox.cells)&set(body.cells)
        assert all(-3<=x<2 and 7<=y<12 and 2<=z<6 for x,y,z in vox.cells)
        # Each tongue remains attached to the hot base: no floating blocks.
        seen,todo = set(),{next(iter(vox.cells))}
        while todo:
            p = todo.pop()
            seen.add(p)
            for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
                q = tuple(p[a]+d[a] for a in range(3))
                if q in vox.cells and q not in seen:
                    todo.add(q)
        assert len(seen)==len(vox.cells), f'Disconnected flame frame {i}'
        frames.append((f'flame_{i:02d}',vox))
    assert len({tuple(sorted(v.cells)) for _,v in frames})==8
    return frames


def write_flames(path, out):
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,flame_frames(),out)


def write_parts(path, parts, out, root_name='wall_torch'):
    """Merge the existing writer's meshes, retaining named body/flame nodes."""
    doc = {'asset':{'version':'2.0','generator':f'Deepdraft {root_name.replace("_", " ")} generator'},
           'scene':0,'scenes':[{'nodes':[0]}],
           'nodes':[{'name':root_name,'children':[]}],
           'meshes':[],'materials':[],'accessors':[],'bufferViews':[]}
    blob = b''
    triangles = 0
    for name,vox in parts:
        part_path = out/'parts'/f'{name}.glb'
        mesh = export_mesh(vox)
        triangles += len(mesh[3])//3
        write_glb(part_path,name,mesh,export_scale=SCALE)
        raw = part_path.read_bytes()
        n = struct.unpack_from('<I',raw,12)[0]
        src = json.loads(raw[20:20+n])
        data = raw[28+n:]
        vi,ai,mi = len(doc['bufferViews']),len(doc['accessors']),len(doc['materials'])
        for view in src['bufferViews']:
            view['byteOffset'] += len(blob)
            doc['bufferViews'].append(view)
        for accessor in src['accessors']:
            accessor['bufferView'] += vi
            doc['accessors'].append(accessor)
        m = copy.deepcopy(src['meshes'][0])
        for p in m['primitives']:
            p['attributes'] = {k:v+ai for k,v in p['attributes'].items()}
            p['indices'] += ai
            p['material'] += mi
        doc['materials'].extend(src['materials'])
        doc['nodes'][0]['children'].append(len(doc['nodes']))
        doc['nodes'].append({'name':name,'mesh':len(doc['meshes'])})
        doc['meshes'].append(m)
        blob += data
    doc['buffers'] = [{'byteLength':len(blob)}]
    encoded = _pad4(json.dumps(doc,separators=(',',':')).encode(),b' ')
    path.write_bytes(struct.pack('<III',0x46546C67,2,28+len(encoded)+len(blob))+
                     struct.pack('<II',len(encoded),0x4E4F534A)+encoded+
                     struct.pack('<II',len(blob),0x004E4942)+blob)
    return triangles


def snapshot(out):
    path = out/'pre_import.json'
    if path.exists():
        return
    files = [*ROOT.glob('assets/**/*.glb'),*ROOT.glob('data/**/*.json'),
             *ROOT.glob('scripts/**/*.gd'),*ROOT.glob('docs/**/*.md')]
    state = {'hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in files},
             'source_text':{p.relative_to(ROOT).as_posix():p.read_text(encoding='utf-8')
                            for p in files if p.suffix!='.glb'}}
    path.write_text(json.dumps(state,indent=2)+'\n',encoding='utf-8')


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    snapshot(out)
    for folder in ('models','parts','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    body,flame = torch()
    assert not set(body.cells)&set(flame.cells)
    cells = body.cells | flame.cells
    todo,seen = {next(iter(cells))},set()
    while todo:
        p = todo.pop()
        seen.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in cells and q not in seen:
                todo.add(q)
    assert len(seen)==len(cells), 'Disconnected torch geometry'
    path = out/'models/wall_torch.glb'
    triangles = write_parts(path,[('torch_body',body),('torch_flame',flame)],out)
    bounds = [[min(p[a] for p in cells)*SCALE for a in range(3)],
              [(max(p[a] for p in cells)+1)*SCALE for a in range(3)]]
    assert bounds==[[-.375,0,0],[.25,1.5,.75]]
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    flame_path = out/'models/wall_torch_flame.glb'
    flame_triangles = write_flames(flame_path,out)
    if install:
        (ROOT/FLAME_MODEL).parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(flame_path,ROOT/FLAME_MODEL)
    for name in ('barrel','storage_shelf','wooden_table','wooden_chair','door'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','WallTorchPreview.gd','VerifyTorchShadows.gd'):
        source = ROOT/'tools'/name
        if source.exists():
            shutil.copyfile(source,out/name)
    helper = ROOT/'scripts/components/FurnitureLighting.gd'
    if helper.exists():
        shutil.copyfile(helper,out/'FurnitureLighting.gd')
    animation = ROOT/'scripts/components/FurnitureFlameAnimation.gd'
    if animation.exists():
        shutil.copyfile(animation,out/'FurnitureFlameAnimation.gd')
    terrain = ROOT/'scripts/components/TerrainLighting.gd'
    if terrain.exists():
        shutil.copyfile(terrain,out/'TerrainLighting.gd')
    definition = ROOT/'data/furniture/wall_torch.json'
    if definition.exists():
        preview_def = json.loads(definition.read_text(encoding='utf-8'))
        preview_def['light_source']['flame_animation']['model'] = 'res://models/wall_torch_flame.glb'
        (out/'wall_torch.json').write_text(json.dumps(preview_def,indent=2)+'\n',encoding='utf-8')
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft wall torch review"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1600
window/size/viewport_height=1000
window/size/window_width_override=1280
window/size/window_height_override=800
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
anti_aliasing/quality/msaa_3d=2
''',encoding='utf-8')
    (out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://WallTorchPreview.gd" id="1"]
[node name="WallTorchPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','bounds':bounds,
              'voxels':len(cells),'triangles':triangles,'connected_components':1,
              'named_meshes':['torch_body','torch_flame'],'sha256':sha(path),
              'animation_frames':8,'animation_triangles':flame_triangles,
              'animation_sha256':sha(flame_path),'animation_within_original_bounds':True}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('WALL_TORCH_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/wall_torch_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated preview directory.')
    generate(out,args.install)

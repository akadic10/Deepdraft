#!/usr/bin/env python3
"""Build the 1x1 standalone oak chair at eight voxels/block; --install adds its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/wooden_chair.glb'


def wooden_chair():
    """8x16x8 cells: +Z faces forward; the broad backrest is at -Z."""
    v = Voxels()
    # Four stout posts; rear legs continue uninterrupted into the back frame.
    for x0,x1 in ((-4,-2),(2,4)):
        box(v,x0,x1,0,15,-4,-2,OAK[2])
        box(v,x0,x1,0,10,2,4,OAK[3])
        for z0,z1 in ((-4,-2),(2,4)):
            box(v,x0,x1,0,1,z0,z1,OAK[1])
        # Small iron shoes, two cells wide, confined to the outward faces.
        box(v,x0,x1,1,2,3,4,IRON[1])
        v.cells[x0,1,3] = IRON[2]
        box(v,x0,x1,1,2,-4,-3,IRON[1])
    # Low stretchers retain clear gaps above and beneath each rail.
    box(v,-3,3,3,4,2,3,OAK[2])
    box(v,-3,3,3,4,-3,-2,OAK[2])
    for x in (-4,3):
        box(v,x,x+1,3,4,-2,2,OAK[2])
    # Thick plank seat at one block, with a shallow four-cell-wide worn hollow.
    box(v,-4,4,5,6,-3,4,OAK[1])
    box(v,-4,4,6,8,-3,4,OAK[4])
    for x in range(-4,4):
        for z in range(-3,4):
            v.cells[x,7,z] = OAK[5] if z in (-3,3) else OAK[4]
    for x in range(-2,2):
        for z in range(-1,2):
            v.cells.pop((x,7,z),None)
            v.cells[x,6,z] = OAK[5]
    box(v,-2,2,7,8,2,3,OAK[3])
    # Solid arm rails with worn tops and short iron caps on the front ends.
    for x in (-4,3):
        box(v,x,x+1,10,12,-2,4,OAK[3])
        box(v,x,x+1,11,12,-2,4,OAK[5])
        v.cells[x,10,3] = IRON[1]
        v.cells[x,11,3] = OAK[6]
    # Recessed broad back panel, framed by continuous posts and a heavy cap.
    box(v,-2,2,10,14,-4,-3,OAK[3])
    box(v,-2,2,10,11,-4,-3,OAK[2])
    box(v,-2,0,11,14,-4,-3,OAK[4])
    box(v,0,2,11,14,-4,-3,OAK[3])
    box(v,-4,4,14,16,-4,-2,OAK[3])
    box(v,-3,3,15,16,-4,-2,OAK[5])
    # Clipped cap corners and a little end grain give the silhouette a worn edge.
    for x in (-4,3):
        for z in (-4,-3):
            v.cells.pop((x,15,z),None)
    for x in (-3,2):
        v.cells[x,14,-2] = OAK[4]
        v.cells[x,12,-2] = IRON[1]
        v.cells[x,13,-2] = IRON[2]
        v.cells[x,12,-4] = IRON[1]
    return v


def validate(vox):
    assert all(-4<=x<4 and 0<=y<16 and -4<=z<4 for x,y,z in vox.cells)
    pending = {next(iter(vox.cells))}
    visited = set()
    while pending:
        p = pending.pop()
        visited.add(p)
        for delta in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+delta[a] for a in range(3))
            if q in vox.cells and q not in visited:
                pending.add(q)
    assert len(visited)==len(vox.cells), 'Disconnected chair geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('bench','wooden_table'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','ChairPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = wooden_chair()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/wooden_chair.glb'
    write_glb(path,'wooden_chair',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft standalone chair art review"
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
[ext_resource type="Script" path="res://ChairPreview.gd" id="1"]
[node name="ChairPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.5,0,-.5],[.5,2,.5]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('CHAIR_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/chair_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

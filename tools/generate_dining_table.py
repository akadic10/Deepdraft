#!/usr/bin/env python3
"""Build the 2x2 oak dining table at eight voxels/block; --install adds its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/wooden_table.glb'


def wooden_table():
    """16x12x16 cells: broad X-running planks on two stout Z-running trestles."""
    v = Voxels()
    for x0,x1 in ((-6,-3),(3,6)):
        # Wide feet and paired uprights leave readable gaps beneath the slab.
        box(v,x0,x1,0,2,-6,6,OAK[2])
        box(v,x0,x1,0,1,-6,6,OAK[1])
        for z0,z1 in ((-4,-1),(1,4)):
            box(v,x0,x1,2,8,z0,z1,OAK[3])
            box(v,x0,x0+1,2,8,z0,z1,OAK[2])
        box(v,x0,x1,8,10,-6,6,OAK[2])
        # Stepped shoulders spread load into the tabletop.
        for y,r in ((5,2),(6,3),(7,4)):
            box(v,x0,x1,y,y+1,-r,r,OAK[3])
        for z in (-6,5):
            box(v,x0,x1,1,2,z,z+1,IRON[1])
            v.cells[x0+1,1,z] = IRON[2]
    # A through-tenoned stretcher joins both trestles without filling the underside.
    box(v,-7,7,3,5,-1,1,OAK[2])
    for x in (-7,6):
        box(v,x,x+1,3,5,-1,1,OAK[4])
        v.cells[x,4,0] = OAK[1]
    # Two-cell slab, four wide planks and clipped corners. No random color noise.
    for x in range(-8,8):
        for z in range(-8,8):
            if abs(x+.5)==7.5 and abs(z+.5)==7.5:
                continue
            edge = x in (-8,7) or z in (-8,7)
            v.cells[x,10,z] = OAK[2] if edge else OAK[3]
            if abs(x+.5)+abs(z+.5)>14:
                continue
            plank = (z+8)//4
            v.cells[x,11,z] = OAK[(5,4,5,4)[plank]]
            if z in (-4,0,4) and -7<x<7:
                v.cells[x,11,z] = OAK[3]
            elif edge:
                v.cells[x,11,z] = OAK[5]
    # Long, sparse grain and a handful of worn end-grain highlights.
    for z,x0,x1,col in ((-6,-4,3,4),(-2,-2,5,5),(2,-5,1,4),(6,-1,4,5)):
        box(v,x0,x1,11,12,z,z+1,OAK[col])
    for x in (-8,7):
        for z in (-5,2,5):
            v.cells[x,11,z] = OAK[6]
    # Four short L brackets clasp the corners instead of banding the whole slab.
    for sx in (-1,1):
        for sz in (-1,1):
            cx = -7 if sx<0 else 6
            cz = -7 if sz<0 else 6
            for step in range(3):
                v.cells[cx-sx*step,11,cz] = IRON[1]
                v.cells[cx,11,cz-sz*step] = IRON[1]
            v.cells[cx,11,cz] = IRON[2]
            ex = -8 if sx<0 else 7
            ez = -8 if sz<0 else 7
            v.cells[ex,10,cz] = IRON[1]
            v.cells[cx,10,ez] = IRON[1]
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<12 and -8<=z<8 for x,y,z in vox.cells)
    pending = {next(iter(vox.cells))}
    visited = set()
    while pending:
        p = pending.pop()
        visited.add(p)
        for delta in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+delta[a] for a in range(3))
            if q in vox.cells and q not in visited:
                pending.add(q)
    assert len(visited)==len(vox.cells), 'Disconnected table geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('bench','barrel','tavern_bar','hearth'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','DiningTablePreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = wooden_table()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/wooden_table.glb'
    write_glb(path,'wooden_table',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft dining table art review"
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
[ext_resource type="Script" path="res://DiningTablePreview.gd" id="1"]
[node name="DiningTablePreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-1],[1,1.5,1]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('DINING_TABLE_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/dining_table_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

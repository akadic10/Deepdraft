#!/usr/bin/env python3
"""Export the 1x1 oak storage chest review; --install replaces its live GLB.

The asset keeps the historical storage_crate.glb filename used by the
base:furniture:storage_chest definition. Capacity and placement stay unchanged.
"""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125


def chest():
    """An eight-cell coffer with strapped lid, corner irons and front latch."""
    v = Voxels()
    # Four broad feet below a framed, inset oak body.
    for x0 in (-4,2):
        for z0 in (-3,1):
            box(v,x0,x0+2,0,1,z0,z0+2,OAK[1])
    box(v,-4,4,1,5,-3,3,OAK[3])
    box(v,-4,4,1,2,-3,3,OAK[2])
    for x in range(-3,3):
        color = OAK[4] if x<0 else OAK[3]
        for z in (-3,2):
            box(v,x,x+1,2,5,z,z+1,color)
    for x in (-4,3):
        box(v,x,x+1,2,5,-2,0,OAK[4])
        box(v,x,x+1,2,5,0,2,OAK[3])
    # Corner straps wrap both faces; broad wood panels remain exposed.
    for x in (-4,3):
        for z in (-3,2):
            box(v,x,x+1,1,5,z,z+1,IRON[1])
            v.cells[x,2,z] = IRON[2]
            inner_x = x+1 if x<0 else x-1
            v.cells[inner_x,1,z] = IRON[1]
    # Dark recessed opening under the raised lid. The hinge and latch join
    # the lid to the body, so the model stays one connected voxel component.
    box(v,-3,3,5,6,-2,2,OAK[0])
    # Two-cell-thick lid with a gently crowned, chamfered silhouette.
    for x in range(-4,4):
        for z in range(-4,4):
            if abs(x+.5)==3.5 and abs(z+.5)==3.5:
                continue
            v.cells[x,6,z] = OAK[4] if z in (-4,3) else OAK[3]
            if -2<=z<2:
                v.cells[x,7,z] = OAK[5 if z<0 else 4]
    # Twin iron straps follow the crown down to separate rear hinges.
    for x in (-3,2):
        for z in range(-4,4):
            y = 7 if -2<=z<2 else 6
            v.cells[x,y,z] = IRON[1]
        box(v,x,x+1,4,7,-4,-3,IRON[1])
        v.cells[x,5,-4] = IRON[2]
    # Quiet long-grain accents on the lid's central oak panel.
    for x in (-1,0,1):
        v.cells[x,7,-1] = OAK[4]
    v.cells[0,7,1] = OAK[5]
    # A proud two-cell-wide clasp bridges the front opening. The key slot
    # is a dark cell, readable at RTS scale without sub-voxel geometry.
    box(v,-1,1,3,7,3,4,IRON[1])
    box(v,-1,1,5,6,3,4,IRON[2])
    v.cells[0,4,3] = IRON[0]
    v.cells[-1,3,3] = IRON[0]
    return v


def validate(vox):
    assert all(-4<=x<4 and 0<=y<8 and -4<=z<4 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected chest geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/'assets/models/furniture/storage_crate.glb'
    snapshot = out/'pre_import.json'
    if not snapshot.exists():
        before = {'furniture_hashes':{p.relative_to(ROOT).as_posix():sha(p)
                  for p in sorted((ROOT/'assets/models/furniture').glob('*.glb'))},
                  'packed_hash':sha(ROOT/'assets/models/items/furniture/packed_furniture.glb'),
                  'definition':json.loads((ROOT/'data/furniture/storage_chest.json').read_text(encoding='utf-8'))}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    if not (out/'reference/storage_crate.glb').exists():
        shutil.copyfile(live,out/'reference/storage_crate.glb')
    for name in ('barrel','tavern_bar','bench'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','ChestRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = chest()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/storage_crate.glb'
    write_glb(path,'storage_crate',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft chest art review"
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
[ext_resource type="Script" path="res://ChestRedesignPreview.gd" id="1"]
[node name="ChestRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.5,0,-.5],[.5,1,.5]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'fits_existing_collision':True,
              'storage_capacity':24,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('CHEST_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/chest_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

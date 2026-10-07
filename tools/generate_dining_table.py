#!/usr/bin/env python3
"""Build the 2x2 oak dining table at eight voxels/block; --install adds its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import write_glb
from generate_tavern_redesign import export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/wooden_table.glb'


def wooden_table():
    from generate_seating_study import chair, table
    return table(2, 2)


def validate(vox):
    assert all(-8<=x<8 and 0<=y<14 and -8<=z<8 for x,y,z in vox.cells)
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
    assert bounds==[[-1,0,-1],[1,1.75,1]]
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

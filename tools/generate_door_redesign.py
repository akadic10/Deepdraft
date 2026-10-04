#!/usr/bin/env python3
"""Export the 2x1 oak double door review; --install replaces its live GLB.

The 31-cell height preserves the gap below a four-block lintel. No gameplay
definition changes: this remains walkable and seals both footprint columns.
"""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
HEIGHT = 31


def door():
    """Framed double leaves, recessed panels and ironwork on both faces."""
    v = Voxels()
    # Structural core and recessed central meeting line. Keeping this solid
    # makes the closed mesh coherent without inventing an opening animation.
    box(v,-8,8,0,HEIGHT,-1,1,OAK[3])
    box(v,-1,1,0,HEIGHT,-1,1,OAK[0])
    for z in (-2,1):
        # Heavy outside stiles and narrower inside stiles frame each leaf.
        for x0,x1 in ((-8,-6),(-2,-1),(1,2),(6,8)):
            box(v,x0,x1,0,HEIGHT,z,z+1,OAK[2])
        for x in (-7,6):
            box(v,x,x+1,1,HEIGHT-1,z,z+1,OAK[3])
        for x0,x1 in ((-8,-1),(1,8)):
            box(v,x0,x1,0,3,z,z+1,OAK[2])
            box(v,x0,x1,13,17,z,z+1,OAK[3])
            box(v,x0,x1,28,31,z,z+1,OAK[4])
            box(v,x0,x1,28,29,z,z+1,OAK[2])
            box(v,x0,x1,16,17,z,z+1,OAK[4])
        # Front/back panels sit one cell behind their framing. Two wide
        # plank tones give the leaves a readable grain without noisy striping.
        face = -1 if z<0 else 0
        for x0,x1 in ((-6,-2),(2,6)):
            for x in range(x0,x1):
                color = OAK[4 if (x-x0)<2 else 3]
                for y0,y1 in ((3,13),(17,28)):
                    box(v,x,x+1,y0,y1,face,face+1,color)
                    v.cells[x,y1-1,face] = OAK[5]
        # Three strap hinges per leaf, with tapered tips and outer knuckles.
        outside = -3 if z<0 else 2
        for y in (5,18,25):
            for side in (-1,1):
                xs = (-8,-7,-6,-5) if side<0 else (7,6,5,4)
                for x in xs:
                    box(v,x,x+1,y,y+2,z,z+1,IRON[1])
                tip = -4 if side<0 else 3
                v.cells[tip,y,z] = IRON[1]
                edge = -8 if side<0 else 7
                box(v,edge,edge+1,y-1,y+2,outside,outside+1,IRON[0])
                v.cells[xs[1],y,z] = IRON[2]
        # Paired ring pulls: dark backing plates, a real opening in each
        # three-by-four-cell ring, and a short hook above it.
        for center in (-4,3):
            box(v,center-1,center+2,11,16,z,z+1,IRON[0])
            for x in range(center-1,center+2):
                for y in range(11,15):
                    if x!=center or y in (11,14):
                        v.cells[x,y,outside] = IRON[2]
            v.cells[center,15,outside] = IRON[3]
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<HEIGHT and -3<=z<3 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected door geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/'assets/models/furniture/door.glb'
    snapshot = out/'pre_import.json'
    if not snapshot.exists():
        before = {'furniture_hashes':{p.relative_to(ROOT).as_posix():sha(p)
                  for p in sorted((ROOT/'assets/models/furniture').glob('*.glb'))},
                  'packed_hash':sha(ROOT/'assets/models/items/furniture/packed_furniture.glb'),
                  'definition':json.loads((ROOT/'data/furniture/door.json').read_text(encoding='utf-8'))}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    if not (out/'reference/door.glb').exists():
        shutil.copyfile(live,out/'reference/door.glb')
    for name in ('barrel','storage_crate'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','DoorRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = door()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/door.glb'
    write_glb(path,'door',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft door art review"
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
[ext_resource type="Script" path="res://DoorRedesignPreview.gd" id="1"]
[node name="DoorRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-.375],[1,3.875,.375]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'fits_existing_footprint':True,
              'collision_regions':[],'blocks_movement':False,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('DOOR_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/door_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

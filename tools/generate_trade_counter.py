#!/usr/bin/env python3
"""Build the 2x1 stone trade counter; --install adds its shipping GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import IRON, box, export_mesh, sha
from generate_hearth_redesign import STONE

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/trade_counter.glb'


def trade_counter():
    """16x16x8 cells: +Z customer face, -Z recessed shopkeeper face."""
    v = Voxels()
    # Two separately readable plinths, with stout dressed-stone supports.
    for x0,x1 in ((-8,-2),(2,8)):
        box(v,x0,x1,0,2,-4,4,STONE[1])
        box(v,x0,x1,1,2,-3,3,STONE[3])
        box(v,x0+1,x1-1,2,12,-3,3,STONE[2])
        box(v,x0+1,x1-1,2,11,2,3,STONE[3])
        box(v,x0,x1,11,13,-3,3,STONE[3])
        # Quiet recessed mortar courses instead of noisy per-cell variation.
        for y in (5,9):
            box(v,x0+1,x1-1,y,y+1,-3,3,STONE[1])
            box(v,x0+1,x1-1,y,y+1,-2,2,STONE[2])
    # Front apron joins the piers, with a clear gap beneath its lower edge.
    box(v,-3,3,4,12,-2,3,STONE[2])
    box(v,-3,3,4,5,-2,3,STONE[1])
    box(v,-3,3,11,12,-2,3,STONE[3])
    # Shopkeeper's shallow inset, one cell behind the apron face.
    for x in range(-2,2):
        for y in range(7,11):
            v.cells.pop((x,y,-2),None)
            v.cells[x,y,-1] = STONE[1]
    # Angular hollow carving cut into the customer-facing stone apron.
    for x,y in ((-1,9),(0,9),(-2,8),(1,8),(-2,7),(1,7),(-1,6),(0,6)):
        v.cells.pop((x,y,2),None)
        v.cells[x,y,1] = STONE[0]
    # Overhanging slab: shadowed underside, iron belt and pale beveled cap.
    box(v,-7,7,12,13,-3,3,STONE[1])
    box(v,-8,8,13,16,-4,4,STONE[3])
    for x in range(-8,8):
        for z in range(-4,4):
            if abs(x+.5)>6.5 and abs(z+.5)>2.5:
                v.cells.pop((x,15,z),None)
                continue
            v.cells[x,15,z] = STONE[4]
            if x==-1 and -2<=z<2:
                v.cells[x,15,z] = STONE[3]
    for z in (-4,3):
        box(v,-8,8,13,14,z,z+1,IRON[1])
        for x in (-6,5):
            v.cells[x,13,z] = IRON[2]
    for x in (-8,7):
        box(v,x,x+1,13,14,-4,4,IRON[1])
    # Iron shoulder straps bind the slab to each support, with quiet rivets.
    for x in (-6,5):
        for z in (-3,2):
            box(v,x,x+1,10,13,z,z+1,IRON[1])
            v.cells[x,10,z] = IRON[2]
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<16 and -4<=z<4 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected counter geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('barrel','storage_crate','tavern_bar'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','TradeCounterPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = trade_counter()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/trade_counter.glb'
    write_glb(path,'trade_counter',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft trade counter art review"
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
[ext_resource type="Script" path="res://TradeCounterPreview.gd" id="1"]
[node name="TradeCounterPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-.5],[1,2,.5]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'fits_existing_collision':True,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('TRADE_COUNTER_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/trade_counter_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

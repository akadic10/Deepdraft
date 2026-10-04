#!/usr/bin/env python3
"""Export the 1x1 open oak storage shelf review; --install replaces its live GLB.

The asset replaces storage_shelf.glb used by the
base:furniture:storage_shelf definition. Capacity and footprint stay unchanged.
"""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125


def shelf():
    """An open 8x16x8 rack; shelf tops stay at y=1 and y=8 cells."""
    v = Voxels()
    # Two broad plank decks preserve the existing item-support heights.
    for y in (0,7):
        box(v,-4,4,y,y+1,-4,4,OAK[3])
        for z0,z1,col in ((-3,-1,OAK[4]),(-1,1,OAK[3]),(1,3,OAK[4])):
            box(v,-3,3,y,y+1,z0,z1,col)
        for x in (-4,3):
            box(v,x,x+1,y,y+1,-4,4,OAK[2])
        # Quiet highlights at the exposed front/rear plank edges.
        for z in (-4,3):
            box(v,-2,2,y,y+1,z,z+1,OAK[4])
    # Full-height corner uprights, exposed grain, and short iron shoes/collars.
    for x in (-4,3):
        for z in (-4,3):
            box(v,x,x+1,0,16,z,z+1,OAK[3])
            for y in (0,1,7,14):
                v.cells[x,y,z] = IRON[1]
            for y in (2,8,15):
                v.cells[x,y,z] = OAK[5]
            for y in (4,11):
                v.cells[x,y,z] = OAK[2]
            # Oak shoulders and iron corbels stay at the outside edges,
            # leaving the eight display volumes completely unobstructed.
            xi = x+1 if x<0 else x-1
            zi = z+1 if z<0 else z-1
            for y in (6,13):
                v.cells[xi,y,z] = OAK[2]
                v.cells[x,y,zi] = OAK[2]
            for y in (5,12):
                v.cells[xi,y,z] = IRON[1]
                v.cells[x,y,zi] = IRON[1]
    # A deep framed crown is open in the centre for RTS visibility.
    for y in (14,15):
        for x in range(-4,4):
            for z in range(-4,4):
                if x in (-4,3) or z in (-4,3):
                    corner = x in (-4,3) and z in (-4,3)
                    v.cells[x,y,z] = OAK[2 if y==14 else 4]
                    if corner:
                        v.cells[x,y,z] = IRON[1] if y==14 else OAK[5]
    # Short apron returns beneath the middle deck add weight at the joints.
    for x in (-4,3):
        for z in (-3,2):
            v.cells[x,6,z] = OAK[3]
    for z in (-4,3):
        for x in (-3,2):
            v.cells[x,6,z] = OAK[3]
    return v


def validate(vox):
    assert all(-4<=x<4 and 0<=y<16 and -4<=z<4 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected shelf geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/'assets/models/furniture/storage_shelf.glb'
    if not (out/'reference/storage_shelf.glb').exists():
        shutil.copyfile(live,out/'reference/storage_shelf.glb')
    for name in ('barrel','storage_crate'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for source in ('assets/models/items/furniture/packed_furniture.glb','assets/models/items/ore/copper_ore.glb','assets/models/items/ore/iron_ore.glb','assets/models/items/stone/rough_stone.glb','assets/models/items/misc/settlement_flag.glb'):
        shutil.copyfile(ROOT/source,out/'context'/Path(source).name)
    # Preview-only manifest; runtime definitions still load through the owning controller.
    definition = json.loads((ROOT/'data/furniture/storage_shelf.json').read_text(encoding='utf-8'))
    (out/'review_storage.json').write_text(json.dumps(definition['storage'],indent=2)+'\n',encoding='utf-8')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','ShelfRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    (out/'scripts/components').mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ROOT/'scripts/components/StorageItemLayout.gd',out/'scripts/components/StorageItemLayout.gd')
    vox = shelf()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/storage_shelf.glb'
    write_glb(path,'storage_shelf',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft shelf art review"
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
[ext_resource type="Script" path="res://ShelfRedesignPreview.gd" id="1"]
[node name="ShelfRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.5,0,-.5],[.5,2,.5]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'fits_existing_collision':True,
              'storage_capacity':8,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('SHELF_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/shelf_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

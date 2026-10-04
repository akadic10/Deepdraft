#!/usr/bin/env python3
"""Author the 2x1 stone-mounted anvil and an isolated Godot art review."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import box, export_mesh, sha, rgb
from generate_hearth_redesign import STONE

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/anvil.glb'
IRON = tuple(map(rgb,('292C30','42484E','626C74','909CA4','A5B0B7')))


def anvil():
    """16x12x8 envelope: horn points -X, long working sides face +/-Z."""
    v = Voxels()
    # A low beveled plinth and a stout masonry pedestal, inset beneath the
    # projecting horn and heel so the iron silhouette stays legible.
    box(v,-5,6,0,2,-4,4,STONE[1])
    box(v,-4,5,1,3,-3,3,STONE[2])
    box(v,-3,5,3,6,-3,3,STONE[2])
    for x in (-5,5):
        for z in (-4,3):
            v.cells.pop((x,1,z),None)
    box(v,-3,5,3,4,2,3,STONE[1])
    box(v,-3,5,4,6,2,3,STONE[3])
    box(v,-3,5,5,6,-3,3,STONE[3])
    # One quiet vertical joint breaks the broad stone course.
    v.cells[1,4,2] = STONE[1]
    # Low flared feet, narrow waist and sloping shoulders. Clear undercuts
    # distinguish an anvil from a rectangular table at the RTS camera angle.
    box(v,-3,6,6,7,-3,3,IRON[1])
    box(v,-2,5,7,8,-2,2,IRON[1])
    box(v,-1,4,8,9,-2,2,IRON[1])
    box(v,-2,6,9,10,-2,2,IRON[2])
    box(v,-3,8,10,11,-3,3,IRON[2])
    box(v,-3,8,11,12,-2,2,IRON[3])
    # Worn face: a broad coherent light region, with darker beveled edges.
    box(v,-2,6,11,12,-1,1,IRON[4])
    for x,z in ((-2,0),(5,-1)):
        v.cells[x,11,z] = IRON[3]
    # The horn tapers by whole cells, with a lower tip and a lighter upper
    # shoulder. Its underside joins the left shoulder of the main body.
    box(v,-5,-2,9,10,-1,1,IRON[1])
    box(v,-6,-3,10,11,-2,2,IRON[2])
    box(v,-8,-6,10,11,-1,1,IRON[3])
    box(v,-5,-3,11,12,-1,1,IRON[3])
    # A real square hardy hole at the heel, with a dark recessed bottom.
    for y in (10,11):
        v.cells.pop((5,y,0),None)
    v.cells[5,9,0] = IRON[0]
    # Two bolted iron hold-downs on each working side grip the anvil feet.
    for x in (-2,4):
        for z in (-3,2):
            box(v,x,x+1,4,7,z,z+1,IRON[1])
            v.cells[x,4,z] = IRON[3]
            v.cells[x,6,z] = IRON[2]
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<12 and -4<=z<4 for x,y,z in vox.cells)
    todo,seen = {next(iter(vox.cells))},set()
    while todo:
        p = todo.pop();seen.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in seen:
                todo.add(q)
    assert len(seen)==len(vox.cells), 'Disconnected anvil geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('barrel','storage_crate','storage_shelf'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','AnvilPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = anvil();validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/anvil.glb'
    write_glb(path,'anvil',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft anvil art review"
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
[ext_resource type="Script" path="res://AnvilPreview.gd" id="1"]
[node name="AnvilPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-.5],[1,1.5,.5]]
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','bounds':bounds,
              'voxels':len(vox),'triangles':len(mesh[3])//3,'connected_components':1,
              'collision_size':[2,1.5,1],'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('ANVIL_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/anvil_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated preview directory.')
    generate(out,args.install)

#!/usr/bin/env python3
"""Export the shared packed-furniture crate; --install replaces only its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, rgb, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/items/furniture/packed_furniture.glb'
ROPE = tuple(map(rgb,('81613F','AE8C58','C9AC76','DDC697')))


def packed_box():
    """5x4x5 cells including the knot, retaining the original item bounds."""
    v = Voxels()
    # Solid recessed plank core. The perimeter frame stands one cell proud.
    box(v,-1,2,0,3,-1,2,OAK[2])
    for x in range(-2,3):
        for z in range(-2,3):
            v.cells[x,0,z] = OAK[2]
            v.cells[x,2,z] = OAK[4 if x<0 else 3]
    # Four squared wooden corner posts, with end grain on their top faces.
    for x in (-2,2):
        for z in (-2,2):
            v.cells[x,1,z] = OAK[4]
            v.cells[x,2,z] = OAK[5]
    # Two complete rope loops across the lid, under the base and down all
    # four sides. Quieter undersides keep the light bands readable from above.
    for a in range(-2,3):
        v.cells[a,2,0] = ROPE[2]
        v.cells[0,2,a] = ROPE[2]
        v.cells[a,0,0] = ROPE[0]
        v.cells[0,0,a] = ROPE[0]
    for y in range(3):
        for x,z in ((-2,0),(2,0),(0,-2),(0,2)):
            v.cells[x,y,z] = ROPE[1 if y<2 else 2]
    # Raised crossing and short tucked rope end. No extra carrying height.
    v.cells[0,3,0] = ROPE[3]
    v.cells[1,3,0] = ROPE[1]
    return v


def validate(vox):
    assert all(-2<=x<3 and 0<=y<4 and -2<=z<3 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected crate geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/MODEL
    snapshot = out/'pre_import.json'
    if not snapshot.exists():
        before = {'asset_hashes':{p.relative_to(ROOT).as_posix():sha(p)
                  for p in sorted((ROOT/'assets/models').rglob('*.glb'))},
                  'resources_hash':sha(ROOT/'data/entities/items/resources.json'),
                  'runtime_hashes':{p:sha(ROOT/p) for p in (
                      'scripts/systems/ItemDropManager.gd','scripts/entities/DwarfAgent.gd',
                      'scripts/components/ContainerStorageComponent.gd',
                      'scripts/systems/FurniturePlacementController.gd')},
                  'furniture_definitions':{p.name:sha(p) for p in sorted((ROOT/'data/furniture').glob('*.json'))}}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    if not (out/'reference/packed_furniture.glb').exists():
        shutil.copyfile(live,out/'reference/packed_furniture.glb')
    for name in ('barrel','storage_crate'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','PackedFurnitureRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = packed_box()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/packed_furniture.glb'
    write_glb(path,'packed_furniture',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft packed furniture art review"
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
[ext_resource type="Script" path="res://PackedFurnitureRedesignPreview.gd" id="1"]
[node name="PackedFurnitureRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.25,0,-.25],[.375,.5,.375]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'original_item_bounds_preserved':True,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PACKED_FURNITURE_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/packed_furniture_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

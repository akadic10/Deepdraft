#!/usr/bin/env python3
"""Export the shared packed-furniture crate; --install replaces only its GLB."""

# Retained only as historical source / flame-building helpers.
if __name__ == "__main__":
    from retired_voxel_art import stop
    stop()

import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, box, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/items/furniture/packed_furniture.glb'


def packed_box():
    """A closed shipping crate occupying exactly 8x8x8 cells / one block."""
    v = Voxels()
    # Closed core; one-cell recesses give the framed sides real depth.
    box(v,-3,3,0,7,-3,3,OAK[2])
    for y in range(1,7):
        plank = OAK[2 + (y // 2) % 2]
        for a in range(-3,3):
            for x,z in ((a,-3),(a,2),(-3,a),(2,a)):
                v.cells[x,y,z] = plank
    # Continuous bottom/top rails and square corner posts frame all faces.
    for a in range(-4,4):
        for b in (-4,3):
            for x,z in ((a,b),(b,a)):
                v.cells[x,0,z] = OAK[2]
                v.cells[x,7,z] = OAK[5]
    for x in (-4,3):
        for z in (-4,3):
            for y in range(1,7):
                v.cells[x,y,z] = OAK[4 if y > 1 else 3]
            v.cells[x,7,z] = OAK[6]
    # Broad lid planks inside the rim, with sparse, quiet wood grain.
    for x in range(-3,3):
        for z in range(-3,3):
            v.cells[x,6,z] = OAK[4 + ((x+3)//2)%2]
    for z in (-2,-1,0): v.cells[1,6,z] = OAK[3]
    # Stair-stepped diagonal braces remain on the same integer cube grid.
    # Adjacent corner-touching steps attach to the solid panel behind them.
    for i in range(6):
        a, y = i-3, i+1
        for x,z in ((a,-4),(a,3),(-4,a),(3,a)):
            v.cells[x,y,z] = OAK[5 if i % 3 else 4]
        v.cells[a,7,a] = OAK[5]
    # Wooden fixing pegs at each brace end distinguish them from rope bands.
    for x,z in ((-3,-4),(-3,3),(-4,-3),(3,-3)):
        v.cells[x,1,z] = OAK[1]
    for x,z in ((2,-4),(2,3),(-4,2),(3,2)):
        v.cells[x,6,z] = OAK[2]
    v.cells[-3,7,-3] = OAK[2]
    v.cells[2,7,2] = OAK[3]
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
        shutil.copyfile(ROOT/'assets/models/characters/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
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
    assert bounds==[[-.5,0,-.5],[.5,1,.5]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'envelope_voxels':[8,8,8],'grounded':True,'sha256':sha(path)}
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

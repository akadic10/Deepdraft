#!/usr/bin/env python3
"""Export a settlement standard at eight voxels/block; --install replaces its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, rgb, box, export_mesh, sha
from generate_hearth_redesign import STONE

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/items/misc/settlement_flag.glb'
CLOTH = tuple(map(rgb,('501F2B','79283A','9B3346','B54654')))
GOLD = tuple(map(rgb,('9B6528','C28E39','E3B85C')))


def flag():
    """Crimson hanging standard with an angular gold rune on both faces."""
    v = Voxels()
    # Low dressed-stone footing, broad enough to support the offset pole.
    for y in range(3):
        for x in range(-4,3):
            for z in range(-3,3):
                if (x in (-4,2) and z in (-3,2)) or (y==2 and x==2):
                    continue
                v.cells[x,y,z] = STONE[1 if y==0 else (3 if y==2 else 2)]
    # Two-cell oak shaft. Its left edge stays inside the placement tile.
    box(v,-4,-2,2,23,-1,1,OAK[2])
    box(v,-3,-2,3,23,-1,1,OAK[4])
    for y in (3,6,19):
        box(v,-4,-2,y,y+1,-2,2,IRON[1])
        v.cells[-3,y,-2] = IRON[2]
        v.cells[-3,y,1] = IRON[2]
    # Oak crossbar, capped in iron; a brass finial tops the mast.
    box(v,-4,4,21,22,-1,1,OAK[3])
    for x in (-4,3):
        box(v,x,x+1,21,22,-1,1,IRON[1])
    box(v,-4,-2,22,23,-1,1,IRON[1])
    box(v,-4,-2,23,24,-1,1,GOLD[1])
    # Two-cell cloth thickness; broad stepped folds overlap at one cell
    # across each join so the hanging cloth remains one connected surface.
    for x in range(-2,4):
        lower = (8,9,10,10,9,8)[x+2]
        z0 = 0 if x in (0,1) else -1
        for y in range(lower,21):
            color = CLOTH[1 if x in (-2,3) else (3 if x in (0,1) else 2)]
            if y==lower:
                color = GOLD[1]
            elif y==20:
                color = CLOTH[0]
            box(v,x,x+1,y,y+1,z0,z0+2,color)
    # Simple hollow lozenge: four cells wide, five high. Gold is woven
    # into the cloth faces, avoiding floating decoration or sub-voxel detail.
    rune = ('.##.','#..#','#..#','#..#','.##.')
    for row,line in enumerate(rune):
        y = 18-row
        for col,mark in enumerate(line):
            if mark!='#':
                continue
            x = col-1
            z0 = 0 if x in (0,1) else -1
            for z in (z0,z0+1):
                v.cells[x,y,z] = GOLD[2 if row<3 else 1]
    return v


def validate(vox):
    assert all(-4<=x<4 and 0<=y<24 and -4<=z<4 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected flag geometry'


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
                  'controller_hash':sha(ROOT/'scripts/systems/FlagPlacementController.gd')}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    if not (out/'reference/settlement_flag.glb').exists():
        shutil.copyfile(live,out/'reference/settlement_flag.glb')
    for name in ('barrel','storage_crate','hearth'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','FlagRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = flag()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/settlement_flag.glb'
    write_glb(path,'settlement_flag',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft settlement flag art review"
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
[ext_resource type="Script" path="res://FlagRedesignPreview.gd" id="1"]
[node name="FlagRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.5,0,-.375],[.5,3,.375]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'fits_existing_1x3x1_occupancy':True,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('FLAG_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/flag_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

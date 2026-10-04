#!/usr/bin/env python3
"""Export the 1x1 oak storage barrel review; --install replaces its live GLB."""
import argparse
import json
import math
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, export_mesh, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
RADII = (3.15,3.65,3.9,4.05,4.05,3.9,3.65,3.15)


def barrel():
    """Eight-cell oak cask with two hoops, raised chime and recessed head."""
    v = Voxels()
    staves = (3,4,3,4,3,4,2,3)
    for y,radius in enumerate(RADII):
        for x in range(-4,4):
            for z in range(-4,4):
                px,pz = x+.5,z+.5
                distance = math.hypot(px,pz)
                if distance>radius:
                    continue
                angle = (math.atan2(pz,px)+math.tau)%math.tau
                stave = int((angle+math.pi/8)/(math.pi/4))%8
                color = OAK[staves[stave]]
                if y==0:
                    color = OAK[2]
                elif y in (1,6) and distance>2.55:
                    # Full wraparound metal, with quieter dark side segments.
                    color = IRON[1] if stave%3 else IRON[0]
                elif y==7:
                    # The rim stands one voxel above the plank lid.
                    if distance<2.15:
                        continue
                    color = OAK[5 if stave%2 else 4]
                elif y==6:
                    color = OAK[5 if x<0 else 4]
                v.cells[x,y,z] = color
    # Long, restrained stave seams through the belly; no random speckling.
    for y in (3,4):
        for x,z in ((-1,3),(3,0),(-4,-1),(0,-4)):
            v.cells[x,y,z] = OAK[2]
    # A rivet on each cardinal face of both iron hoops.
    for y in (1,6):
        for x,z in ((0,3),(3,-1),(-1,-4),(-4,0)):
            v.cells[x,y,z] = IRON[2]
    # Recessed head with two broad planks and a dark, inset wooden bung.
    for z in range(-2,2):
        if (0,6,z) in v.cells:
            v.cells[0,6,z] = OAK[3]
    v.cells.pop((0,6,0))
    v.cells[0,5,0] = OAK[1]
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
    assert len(visited)==len(vox.cells),'Disconnected barrel geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/'assets/models/furniture/barrel.glb'
    snapshot = out/'pre_import.json'
    if not snapshot.exists():
        before = {'furniture_hashes':{p.relative_to(ROOT).as_posix():sha(p)
                  for p in sorted((ROOT/'assets/models/furniture').glob('*.glb'))},
                  'packed_hash':sha(ROOT/'assets/models/items/furniture/packed_furniture.glb'),
                  'definition':json.loads((ROOT/'data/furniture/barrel.json').read_text(encoding='utf-8'))}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    if not (out/'reference/barrel.glb').exists():
        shutil.copyfile(live,out/'reference/barrel.glb')
    for name in ('hearth','tavern_bar','bench'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','BarrelRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = barrel()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/barrel.glb'
    write_glb(path,'barrel',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,live)
    # Reuse the same isolated studio configuration as the tavern pair.
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft barrel art review"
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
[ext_resource type="Script" path="res://BarrelRedesignPreview.gd" id="1"]
[node name="BarrelRedesignPreview" type="Node3D"]
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
              'storage_capacity':8,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('BARREL_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/barrel_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

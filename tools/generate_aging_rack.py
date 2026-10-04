#!/usr/bin/env python3
"""Author the 2x2 oak aging rack and its isolated Godot art review."""
import argparse
import json
import math
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import box, export_mesh, sha, OAK, IRON
from generate_hearth_redesign import STONE

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/aging_rack.glb'


def aging_rack():
    """Two horizontal casks, front +Z, within a 16x16x16-cell envelope."""
    v = Voxels()
    # Two long runners, transverse ties and four stout uprights leave an open
    # undercarriage instead of turning the rack into another solid cabinet.
    for x in (-7,5):
        box(v,x,x+2,0,2,-8,8,OAK[2])
        box(v,x,x+2,2,9,-5,-3,OAK[3])
        box(v,x,x+2,2,9,3,5,OAK[3])
    for z in (-5,3):
        box(v,-7,7,1,3,z,z+2,OAK[2])
        box(v,-8,8,7,9,z,z+2,OAK[4])
        # Paired diagonal timbers meet in a strong X under each saddle rail.
        for y in range(3,7):
            dx = (y-3)*2
            for x in (-5+dx,3-dx):
                box(v,x,x+3,y,y+1,z,z+2,OAK[3])
        for x in (-7,6):
            v.cells[x,2,z+1] = IRON[2]
            v.cells[x,7,z+1] = IRON[2]
    # Barrel cells are shaded in coherent staves along their axes. Rounded
    # shoulders taper at both ends; two iron hoops wrap all the way around.
    for cx in (-4.5,4.5):
        cy = 12.5
        for z in range(-5,6):
            r = 2.65 if z in (-5,5) else (3.05 if z in (-4,4) else 3.5)
            for x in range(-8,8):
                for y in range(9,16):
                    dx,dy = x+.5-cx,y+.5-cy
                    distance = math.hypot(dx,dy)
                    if distance>r:
                        continue
                    angle = (math.atan2(dy,dx)+math.tau)%math.tau
                    stave = int((angle+math.pi/8)/(math.pi/4))%8
                    tone = (3,4,5,4,3,2,3,4)[stave]
                    color = OAK[tone]
                    if z in (-2,2) and distance>2.15:
                        color = IRON[1 if dy>=0 else 0]
                    elif z in (-5,5):
                        # Raised chime surrounds a head recessed one cell.
                        if distance<1.7:
                            continue
                        color = OAK[5 if dy>=0 else 3]
                    elif z in (-4,4) and distance<2.5:
                        color = OAK[4 if dx<0 else 3]
                        if dx==0:
                            color = OAK[2]
                    v.cells[x,y,z] = color
        # Wooden wedges grip each cask at both saddle rails.
        for z in (-5,3):
            for side in (-1,1):
                x = int(cx-.5)+side*2
                box(v,x,x+1,9,11,z,z+2,OAK[5])
        center = int(cx-.5)
        # Oak spigot, downward nozzle and a short iron handle; all in bounds.
        box(v,center,center+1,11,12,4,8,OAK[5])
        v.cells[center,10,7] = OAK[2]
        box(v,center,center+2,12,13,6,7,IRON[1])
        # Small hoop rivets on the broad top planes.
        for z in (-2,2):
            v.cells[center,15,z] = IRON[2]
    # Batch board hangs from the front saddle. Two quiet chalk marks imply
    # records without baking readable UI text or temperature frost into art.
    box(v,-2,2,5,8,5,6,OAK[1])
    box(v,-2,2,5,7,6,7,STONE[0])
    v.cells[-1,6,6] = STONE[4]
    v.cells[1,5,6] = STONE[3]
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<16 and -8<=z<8 for x,y,z in vox.cells)
    todo,seen = {next(iter(vox.cells))},set()
    while todo:
        p = todo.pop();seen.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in seen:
                todo.add(q)
    assert len(seen)==len(vox.cells),'Disconnected aging rack geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('barrel','brewing_vat','storage_shelf'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','AgingRackPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = aging_rack();validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/aging_rack.glb'
    write_glb(path,'aging_rack',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft aging rack art review"
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
[ext_resource type="Script" path="res://AgingRackPreview.gd" id="1"]
[node name="AgingRackPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-1],[1,2,1]]
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','bounds':bounds,
              'voxels':len(vox),'triangles':len(mesh[3])//3,'connected_components':1,
              'collision_size':[2,2,2],'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('AGING_RACK_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/aging_rack_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated preview directory.')
    generate(out,args.install)

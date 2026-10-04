#!/usr/bin/env python3
"""Build the 2x2 standalone brewing vat at eight voxels/block; --install adds its GLB."""
import argparse
import json
import math
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha, rgb

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/brewing_vat.glb'


# Copper derives from doc 61 copper_body/patina; liquid uses its vat surface color.
COPPER = tuple(rgb(h) for h in ('6D351C','B05828','D28D50','4A7858'))
LIQUID = tuple(rgb(h) for h in ('21140B','2A1808','3C2512','584025'))


def _inside(x,z,rx,rz):
    # The vessel sits one cell toward -Z, leaving room for its front tap.
    return ((x+.5)/rx)**2+((z+1.5)/rz)**2<=1


def brewing_vat():
    """16x16x16 envelope: open oak tub on skids, copper draw-off facing +Z."""
    v = Voxels()
    # Two broad oak skids and their cross ties reinforce the bottom of the vessel.
    for x0 in (-6,3):
        box(v,x0,x0+3,0,2,-6,4,OAK[2])
        for z0 in (-6,3):
            box(v,x0,x0+3,0,1,z0,z0+1,IRON[1])
        box(v,x0,x0+3,1,2,-5,3,OAK[3])
    for z0 in (-5,1):
        box(v,-6,6,1,3,z0,z0+2,OAK[2])
    staves = (3,4,3,3,4,3,2,3,4,3,4,3)
    for y in range(2,16):
        hoop = y in (4,5,11,12)
        rim = y>=14
        rx,rz = (8,7) if hoop or rim else ((6.5,5.5) if y==2 else (7.5,6.5))
        for x in range(-8,8):
            for z in range(-8,6):
                if not _inside(x,z,rx,rz):
                    continue
                inner = _inside(x,z,6,5)
                if y>2 and inner:
                    if y==12:
                        # One flat liquid layer, recessed three voxels below the lip.
                        color = LIQUID[1]
                    else:
                        continue
                else:
                    angle = (math.atan2(z+1.5,x+.5)+math.tau)%math.tau
                    stave = int((angle+math.pi/12)/(math.pi/6))%12
                    color = OAK[staves[stave]]
                    outer_skin = not _inside(x,z,rx-1,rz-1)
                    if hoop and outer_skin:
                        color = IRON[1] if stave%4 else IRON[0]
                    elif rim:
                        color = OAK[5 if y==15 else 3]
                        if y==15 and stave%3==0:
                            color = OAK[4]
                    elif not outer_skin:
                        color = OAK[1]
                    elif y==2:
                        color = OAK[2]
                v.cells[x,y,z] = color
    # Short grain seams keep the broad staves readable without mottled noise.
    for x,z in ((-1,4),(5,2),(-6,-4),(2,-7)):
        for y in (7,8,9):
            if (x,y,z) in v.cells:
                v.cells[x,y,z] = OAK[2]
    # Cardinal hoop rivets and a restrained reflected edge on the liquid.
    for y in (5,12):
        for x,z in ((-8,-2),(7,-1),(0,-8),(0,5)):
            if (x,y,z) in v.cells:
                v.cells[x,y,z] = IRON[2]
    for x,z in ((-3,-3),(-2,-3),(-1,-3),(2,0),(2,1)):
        if (x,12,z) in v.cells:
            v.cells[x,12,z] = LIQUID[2]
    v.cells[-2,12,-3] = LIQUID[3]
    # A square copper mounting plate, short nozzle and raised T-handle.
    box(v,-2,2,6,10,4,6,COPPER[0])
    box(v,-1,1,7,10,5,6,COPPER[1])
    box(v,-1,1,7,9,6,8,COPPER[1])
    box(v,-1,1,6,8,7,8,COPPER[0])
    box(v,-1,1,9,11,6,7,COPPER[1])
    box(v,-2,2,10,11,6,7,COPPER[2])
    v.cells[-1,8,7] = COPPER[2]
    v.cells[0,6,7] = LIQUID[0]  # dark draw-off opening
    v.cells[-2,6,5] = COPPER[3] # a single aged corner on the mounting plate
    return v


def validate(vox):
    assert all(-8<=x<8 and 0<=y<16 and -8<=z<8 for x,y,z in vox.cells)
    pending = {next(iter(vox.cells))}
    visited = set()
    while pending:
        p = pending.pop()
        visited.add(p)
        for delta in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+delta[a] for a in range(3))
            if q in vox.cells and q not in visited:
                pending.add(q)
    assert len(visited)==len(vox.cells), 'Disconnected vat geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('barrel','storage_shelf','tavern_bar'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','BrewingVatPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = brewing_vat()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/brewing_vat.glb'
    write_glb(path,'brewing_vat',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft brewing vat art review"
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
[ext_resource type="Script" path="res://BrewingVatPreview.gd" id="1"]
[node name="BrewingVatPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-1],[1,2,1]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('BREWING_VAT_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/brewing_vat_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

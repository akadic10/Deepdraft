#!/usr/bin/env python3
"""Build the oak tavern bar and matching bench at eight voxels per block.

Default: export an isolated review. --install replaces these two shipping
GLBs only; both keep their existing footprints and collision definitions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125


def rgb(value):
    return tuple(int(value[i:i+2],16)/255 for i in (0,2,4))


OAK = tuple(map(rgb, ('412A1C','5A381F','6C4528','7A5230','91633B','A67C52','B58A5A')))
IRON = tuple(map(rgb, ('302E2C','4B4844','6A6868','9A9898')))


def box(v,x0,x1,y0,y1,z0,z1,color):
    v.box(x0,x1,y0,y1,z0,z1,color,shade=False)


def tavern_bar():
    """16x8 floor cells, countertop 1.5 blocks high, tap tips at 2 blocks.

    +Z is the customer-facing panel and footrail; -Z is the serving side.
    The inset body gives the slab a real overhang inside the 2x1 footprint.
    """
    v = Voxels()
    box(v,-7,7,1,10,-3,2,OAK[1])
    # Stout end posts and broad feet, held by short iron shoes.
    for x0,x1 in ((-7,-5),(5,7)):
        box(v,x0,x1,0,11,-3,3,OAK[2])
        box(v,x0,x1,0,1,-3,3,OAK[0])
        for z in (-3,2):
            box(v,x0,x1,1,3,z,z+1,IRON[1])
            v.cells[x0,2,z] = IRON[2]
    # Two deeply framed panels, their planks deliberately broad and quiet.
    for x0,x1 in ((-5,-1),(1,5)):
        for x in range(x0,x1):
            color = OAK[3] if x-x0<2 else OAK[4]
            box(v,x,x+1,3,9,1,2,color)
        box(v,x0,x1,3,4,1,2,OAK[2])
        box(v,x0,x1,8,9,1,2,OAK[4])
    box(v,-1,1,2,10,1,3,OAK[2])
    box(v,-7,7,9,11,1,3,OAK[2])
    box(v,-7,7,1,3,1,3,OAK[1])
    # Side panels sit back from the end posts; rear has a framed serving recess.
    for x in (-7,6):
        box(v,x,x+1,3,9,-2,1,OAK[3])
        box(v,x,x+1,4,8,-1,0,OAK[4])
    box(v,-5,5,3,9,-3,-2,OAK[0])
    box(v,-5,5,3,4,-3,-2,OAK[3])
    box(v,-1,1,3,9,-3,-2,OAK[2])
    box(v,-5,5,6,7,-3,-2,OAK[3])
    # Front footrail and support elbows stay within the last row of voxels.
    box(v,-6,6,2,3,3,4,IRON[2])
    for x in (-6,5):
        box(v,x,x+1,1,3,2,4,IRON[1])
    # Two-cell-thick chamfered counter slab. Grain runs along broad planks.
    for x in range(-8,8):
        for z in range(-4,4):
            if abs(x+.5)==7.5 and abs(z+.5)==3.5:
                continue
            edge = x in (-8,7) or z in (-4,3)
            v.cells[x,10,z] = OAK[2] if edge else OAK[3]
            plank = 5 if z<0 else 4
            v.cells[x,11,z] = OAK[5] if edge else OAK[plank]
    # Sparse long grain and end grain, never per-voxel noise.
    for x in range(-5,2):
        v.cells[x,11,-1] = OAK[4]
    for x in range(-2,6):
        v.cells[x,11,1] = OAK[5]
    for x in (-8,7):
        for z in (-2,1):
            v.cells[x,11,z] = OAK[6]
    # Twin taps: wide flange, upright, projecting neck, downturned nozzle
    # and an oak lever cap. Four cells of silhouette replace the old knobs.
    for x in (-4,3):
        box(v,x-1,x+1,12,13,-3,-1,IRON[1])
        box(v,x,x+1,13,16,-2,-1,IRON[2])
        box(v,x,x+1,14,15,-1,1,IRON[3])
        v.cells[x,13,0] = IRON[1]
        v.cells[x,15,-2] = OAK[2]
        v.cells[x-1,15,-2] = OAK[4]
    return v


def bench():
    """A 16x8-cell plank seat over braced trestles, exactly one block high."""
    v = Voxels()
    for x0,x1 in ((-7,-4),(4,7)):
        for z0,z1 in ((-3,-1),(1,3)):
            box(v,x0,x1,0,6,z0,z1,OAK[2])
            box(v,x0,x1,0,1,z0,z1,OAK[1])
        box(v,x0,x1,4,6,-3,3,OAK[3])
    # Through-tenoned longitudinal stretcher, with clear space above/below.
    box(v,-7,7,2,4,-1,1,OAK[2])
    for x in (-7,6):
        box(v,x,x+1,2,4,-1,1,OAK[5])
    for x0 in (-6,4):
        for z in (-3,2):
            box(v,x0,x0+2,4,6,z,z+1,IRON[1])
            v.cells[x0,5,z] = IRON[2]
    for x in range(-8,8):
        for z in range(-4,4):
            if abs(x+.5)==7.5 and abs(z+.5)==3.5:
                continue
            edge = x in (-8,7) or z in (-4,3)
            v.cells[x,6,z] = OAK[2] if edge else OAK[3]
            v.cells[x,7,z] = OAK[5] if z<0 else OAK[4]
    for x in range(-6,1):
        v.cells[x,7,-1] = OAK[4]
    for x in range(-2,6):
        v.cells[x,7,1] = OAK[5]
    for x in (-8,7):
        for z in (-2,1):
            v.cells[x,7,z] = OAK[6]
    return v


def export_mesh(vox):
    positions,normals,colors,indices = mesh_from_voxels(vox)
    def linear(c):
        return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
    colors = [tuple(linear(c) for c in color[:3])+(1.,) for color in colors]
    return positions,normals,colors,indices


def validate(vox,height):
    assert all(-8<=x<8 and 0<=y<height and -4<=z<4 for x,y,z in vox.cells)
    todo = {next(iter(vox.cells))}
    visited = set()
    while todo:
        p = todo.pop()
        visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in visited:
                todo.add(q)
    assert len(visited)==len(vox.cells),'Disconnected geometry'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','dwarves','context','renders'):
        (out/folder).mkdir(exist_ok=True)
    snapshot = out/'pre_import.json'
    if not snapshot.exists():
        before = {'furniture_hashes':{p.relative_to(ROOT).as_posix():sha(p)
                  for p in sorted((ROOT/'assets/models/furniture').glob('*.glb'))},
                  'packed_hash':sha(ROOT/'assets/models/items/furniture/packed_furniture.glb'),
                  'definitions':{name:json.loads((ROOT/f'data/furniture/{name}.json').read_text(encoding='utf-8'))
                  for name in ('tavern_bar','bench')}}
        snapshot.write_text(json.dumps(before,indent=2)+'\n',encoding='utf-8')
    for name in ('tavern_bar','bench'):
        reference = out/f'reference/{name}.glb'
        if not reference.exists():
            shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',reference)
    for name in ('hearth','barrel'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    models = {}
    for name,builder,height in (('tavern_bar',tavern_bar,16),('bench',bench,8)):
        vox = builder()
        validate(vox,height)
        mesh = export_mesh(vox)
        path = out/f'models/{name}.glb'
        write_glb(path,name,mesh,export_scale=SCALE)
        if install:
            shutil.copyfile(path,ROOT/f'assets/models/furniture/{name}.glb')
        models[name] = {'voxels':len(vox),'triangles':len(mesh[3])//3,
                        'bounds':[[-1,0,-.5],[1,height*SCALE,.5]],
                        'connected_components':1,'fits_existing_collision':True,
                        'sha256':sha(path)}
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft tavern art review"
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
[ext_resource type="Script" path="res://TavernRedesignPreview.gd" id="1"]
[node name="TavernRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','models':models}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('TAVERN_REDESIGN_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/tavern_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

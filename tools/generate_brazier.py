#!/usr/bin/env python3
"""Author a one-tile iron brazier, stone pedestal and eight-frame voxel fire."""
import argparse
import json
import math
from pathlib import Path
import shutil

from voxel_glb import Voxels
from generate_tavern_redesign import box, export_mesh, sha
from generate_hearth_redesign import STONE
from generate_anvil import IRON
from generate_wall_torch import write_parts, FIRE

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/brazier.glb'
CLIP = 'assets/models/furniture/animations/brazier_flame.glb'


def body():
    v = Voxels()
    # Beveled dressed-stone foot, narrow pedestal, then a square iron collar.
    for x in range(-3,3):
        for z in range(-3,3):
            if abs(x+.5)+abs(z+.5)<=4:
                v.cells[x,0,z] = STONE[1]
                v.cells[x,1,z] = STONE[2]
    box(v,-2,2,2,5,-2,2,STONE[2])
    box(v,-2,2,2,3,1,2,STONE[3])
    box(v,-1,1,3,5,1,2,STONE[3])
    box(v,-2,2,5,6,-2,2,IRON[1])
    # A faceted basin widens above the pedestal. The inside is truly hollow;
    # charcoal and the animated ember bed sit below a thick rolled rim.
    for y,radius,inner in ((6,2,0),(7,3,1),(8,4,2),(9,4,3)):
        for x in range(-radius,radius):
            for z in range(-radius,radius):
                edge = max(abs(x+.5),abs(z+.5))
                if abs(x+.5)+abs(z+.5)>radius*2-2:
                    continue
                if inner and edge<inner:
                    continue
                color = IRON[1 if y<9 else 2]
                if z==radius-1 or x==-radius:
                    color = IRON[2 if y<9 else 3]
                v.cells[x,y,z] = color
    # Four short corner prongs and restrained rivets keep a dwarven silhouette.
    for x,z in ((-3,-3),(-3,2),(2,-3),(2,2)):
        v.cells[x,9,z] = IRON[2]
        v.cells[x,10,z] = IRON[1]
    for x,z in ((-2,3),(1,3),(-2,-4),(1,-4),(-4,-2),(-4,1),(3,-2),(3,1)):
        v.cells[x,9,z] = IRON[3]
    box(v,-2,2,7,8,-2,2,IRON[0])
    return v


def flame(phase=0):
    v = Voxels()
    # A fixed glowing bed touches the charcoal. Tongues rise from it and
    # shorten, lean and split, with connected voxel elbows at each bend.
    for x in range(-2,2):
        for z in range(-2,2):
            v.cells[x,8,z] = FIRE[0 if (x+z)%3==0 else 1]
    for center_x,center_z,top,offset in ((-1,-1,12,0),(0,0,14,1.5),(1,0,12,3.7)):
        tip = min(15,top+round(math.sin(phase+offset)))
        previous = None
        for y in range(9,tip+1):
            rise = (y-9)/max(1,tip-9)
            cx = center_x+round(.7*rise*math.sin(phase+offset))
            cz = center_z+round(.7*rise*math.cos(phase+offset))
            radius = 1 if y<tip-1 else 0
            cells = {(x,y,z) for x in range(cx-radius,cx+radius+1)
                     for z in range(cz-radius,cz+radius+1)}
            if previous and not any((x,y-1,z) in previous for x,_,z in cells):
                support = min(previous,key=lambda p:(p[0]-cx)**2+(p[2]-cz)**2)
                px,pz = support[0],support[2]
                cells.add((px,y,pz))
                while px!=cx:
                    px += 1 if px<cx else -1
                    cells.add((px,y,pz))
                while pz!=cz:
                    pz += 1 if pz<cz else -1
                    cells.add((px,y,pz))
            for x,_,z in sorted(cells):
                color = FIRE[2]
                if y>=tip-1:
                    color = FIRE[1]
                elif y<=10 and -1<=x<=0 and z>=0:
                    color = FIRE[4]
                elif y<=11 and abs(x)<=1:
                    color = FIRE[3]
                v.cells[x,y,z] = color
            previous = cells
    shell = body().cells
    v.cells = {p:c for p,c in v.cells.items() if p not in shell}
    return v


def brazier():
    vox = body();vox.update(flame())
    return vox


def validate(vox):
    assert all(-4<=x<4 and 0<=y<16 and -4<=z<4 for x,y,z in vox.cells)
    todo,seen = {next(iter(vox.cells))},set()
    while todo:
        p = todo.pop();seen.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in seen:
                todo.add(q)
    assert len(seen)==len(vox.cells),'Disconnected brazier geometry'


def flame_frames():
    frames = [(f'flame_{i:02}',flame(i*math.tau/8)) for i in range(8)]
    assert len({tuple(sorted(v.cells)) for _,v in frames})==8
    for _,fire in frames:
        shell = body()
        assert not set(shell.cells)&set(fire.cells)
        shell.update(fire);validate(shell)
    return frames


def write_brazier(path,out):
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,[('brazier_body',body()),('brazier_flame',flame())],out,'brazier')


def write_flames(path,out):
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,flame_frames(),out,'brazier_flame')


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('wooden_table','wooden_chair','storage_shelf'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','BrazierPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    for name in ('FurnitureLighting.gd','FurnitureFlameAnimation.gd'):
        shutil.copyfile(ROOT/'scripts/components'/name,out/name)
    definition = json.loads((ROOT/'data/furniture/brazier.json').read_text(encoding='utf-8'))
    definition['light_source']['flame_animation']['model'] = 'res://models/brazier_flame.glb'
    (out/'brazier.json').write_text(json.dumps(definition,indent=2)+'\n',encoding='utf-8')
    vox = brazier();validate(vox)
    path,clip = out/'models/brazier.glb',out/'models/brazier_flame.glb'
    triangles = write_brazier(path,out)
    frame_triangles = write_flames(clip,out)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
        (ROOT/CLIP).parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(clip,ROOT/CLIP)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft brazier art review"
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
[ext_resource type="Script" path="res://BrazierPreview.gd" id="1"]
[node name="BrazierPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    mesh = export_mesh(vox)
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-.5,0,-.5],[.5,2,.5]]
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','bounds':bounds,
              'voxels':len(vox),'triangles':triangles,'connected_components':1,
              'animation_frames':8,'animation_triangles':frame_triangles,
              'heat_units':600,'sha256':sha(path),'clip_sha256':sha(clip)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('BRAZIER_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/brazier_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated preview directory.')
    generate(out,args.install)

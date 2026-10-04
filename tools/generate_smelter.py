#!/usr/bin/env python3
"""Build the 2x2x3 stone smelter and its animated, recessed furnace fire."""
import argparse
import json
import math
from pathlib import Path
import shutil

from voxel_glb import Voxels
from generate_tavern_redesign import box, export_mesh, sha, rgb
from generate_hearth_redesign import STONE
from generate_anvil import IRON
from generate_wall_torch import write_parts

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/smelter.glb'
CLIP = 'assets/models/furniture/animations/smelter_flame.glb'
FIRE = tuple(map(rgb,('882200','D14C18','F98123','FFC13F','FFE581')))
SOOT = tuple(map(rgb,('272729','3A3737','514B49')))


def body():
    v = Voxels()
    # Broad cut-corner foundation, with room for a projecting grate at +Z.
    for x in range(-8,8):
        for z in range(-8,8):
            if abs(x+.5)+abs(z+.5)>14:
                continue
            v.cells[x,0,z] = STONE[1]
            v.cells[x,1,z] = STONE[2]
    # Thick furnace walls, recessed firebox and an open, stepped arch.
    for y in range(2,13):
        for x in range(-7,7):
            for z in range(-7,6):
                if abs(x+.5)>5.5 and z==-7:
                    continue
                opening = (abs(x+.5)<4 and 3<=y<=8) or (abs(x+.5)<3 and 9<=y<=10) or (abs(x+.5)<2 and y==11)
                if opening and z>=-3:
                    continue
                color = STONE[2]
                if y in (5,9) and (x in (-7,6) or z==-7):
                    color = STONE[1]
                elif ((x+7)//4+(z+7)//4+(y//4))%4==1:
                    color = STONE[3]
                if z==5:
                    color = STONE[3] if y not in (5,9) else STONE[2]
                # Inner lining is soot-darkened, including the rear firebox wall.
                if z==-4 and abs(x+.5)<4 and 3<=y<=10:
                    color = SOOT[1]
                if x in (-5,4) and z>=-3 and 3<=y<=8:
                    color = SOOT[2]
                v.cells[x,y,z] = color
    # Keystone and shoulder blocks emphasize the arch above the dark opening.
    box(v,-1,1,12,14,4,6,STONE[4])
    for x in (-1,0):
        for z in (-4,-3):
            v.cells.pop((x,12,z),None) # connect the firebox to the hollow flue
    for x0,x1,y0,y1 in ((-5,-4,3,9),(4,5,3,9),(-4,-3,9,11),(3,4,9,11),(-3,-2,11,12),(2,3,11,12)):
        box(v,x0,x1,y0,y1,5,6,STONE[4])
    # Iron belt around the furnace shoulders, broken cleanly at the opening.
    for x in (-7,6):
        box(v,x,x+1,10,11,-6,5,IRON[1])
        for z in (-4,2):
            v.cells[x,10,z] = IRON[3]
    box(v,-6,6,10,11,-7,-6,IRON[1])
    # Faceted iron hood tapers into a rear-set stone chimney. Hollow flue
    # continues through the hood; no glowing surface is painted on the shell.
    for y,half,zlo,zhi in ((13,7,-6,5),(14,6,-6,4),(15,5,-6,3),(16,4,-6,1)):
        for x in range(-half,half):
            for z in range(zlo,zhi):
                if -1<=x<1 and -4<=z<-2:
                    continue
                color = IRON[1 if y in (13,16) else 2]
                if x in (-half,half-1) or z==zhi-1:
                    color = IRON[2]
                v.cells[x,y,z] = color
    for y in range(17,24):
        half = 4 if y==23 else 3
        for x in range(-half,half):
            for z in range(-7 if y==23 else -6,1 if y==23 else 0):
                if -1<=x<1 and -4<=z<-2:
                    continue
                color = STONE[2] if y<21 else SOOT[2]
                if y in (18,22):
                    color = STONE[1] if y==18 else SOOT[1]
                if y==23:
                    color = SOOT[1] if abs(x+.5)<1.6 and -5<=z<-1 else SOOT[2]
                v.cells[x,y,z] = color
    # Low grate projects in front of the opening while leaving the upper
    # flame silhouettes readable. Rails are one voxel thick, at original scale.
    box(v,-5,5,2,3,5,8,IRON[0])
    for x in (-4,-1,2):
        box(v,x,x+1,3,6,6,7,IRON[1])
        v.cells[x,5,6] = IRON[2]
    for x in (-5,4):
        box(v,x,x+1,3,5,5,8,IRON[1])
    box(v,-5,5,3,4,7,8,IRON[2])
    # Charcoal supports the burning core, with dark edges around the hot bed.
    box(v,-4,4,2,3,-3,5,SOOT[0])
    return v


def flame(phase=0):
    v = Voxels()
    # Fixed embers at the bottom of every frame. The whole fire stays behind
    # the static grate and arch, inside the real hollow fire chamber.
    for x in range(-3,4):
        for z in range(0,5):
            v.cells[x,3,z] = FIRE[0 if (x+z)%3==0 else 1]
    for center,base_top,offset in ((-2,8,0),(0,10,2.1),(2,9,4.3)):
        tip = base_top+round(math.sin(phase+offset))
        previous = None
        for y in range(4,tip+1):
            rise = (y-4)/max(1,tip-4)
            cx = center+round(.65*rise*math.sin(phase+offset-rise))
            cz = 2+round(.65*rise*math.cos(phase+offset))
            radius = 1 if y<tip-1 else 0
            cells = {(x,y,z) for x in range(cx-radius,cx+radius+1)
                     for z in range(cz-radius,cz+radius+1)}
            if previous and not any((x,y-1,z) in previous for x,_,z in cells):
                # A one-voxel bend uses an elbow rather than a floating tip.
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
                    color = FIRE[3]
                elif abs(x)<=1 and z>=2 and y<7:
                    color = FIRE[4]
                elif z<=1:
                    color = FIRE[1]
                v.cells[x,y,z] = color
            previous = cells
    shell = body().cells
    v.cells = {p:c for p,c in v.cells.items() if p not in shell}
    return v


def smelter():
    vox = body();vox.update(flame())
    return vox


def validate(vox):
    assert all(-8<=x<8 and 0<=y<24 and -8<=z<8 for x,y,z in vox.cells)
    todo,seen = {next(iter(vox.cells))},set()
    while todo:
        p = todo.pop();seen.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in vox.cells and q not in seen:
                todo.add(q)
    assert len(seen)==len(vox.cells), 'Disconnected smelter geometry'


def flame_frames():
    frames = [(f'flame_{i:02}',flame(i*math.tau/8)) for i in range(8)]
    assert len({tuple(sorted(v.cells)) for _,v in frames})==8
    for _,fire in frames:
        shell = body()
        assert not set(shell.cells)&set(fire.cells)
        shell.update(fire);validate(shell)
    return frames


def write_smelter(path,out):
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,[('smelter_body',body()),('smelter_flame',flame())],out,'smelter')


def write_flames(path,out):
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,flame_frames(),out,'smelter_flame')


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('anvil','storage_shelf','storage_crate','barrel'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','SmelterPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    for name in ('FurnitureLighting.gd','FurnitureFlameAnimation.gd'):
        shutil.copyfile(ROOT/'scripts/components'/name,out/name)
    definition = json.loads((ROOT/'data/furniture/smelter.json').read_text(encoding='utf-8'))
    definition['light_source']['flame_animation']['model'] = 'res://models/smelter_flame.glb'
    (out/'smelter.json').write_text(json.dumps(definition,indent=2)+'\n',encoding='utf-8')
    vox = smelter();validate(vox)
    path,clip = out/'models/smelter.glb',out/'models/smelter_flame.glb'
    triangles = write_smelter(path,out)
    frame_triangles = write_flames(clip,out)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
        (ROOT/CLIP).parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(clip,ROOT/CLIP)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft smelter art review"
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
[ext_resource type="Script" path="res://SmelterPreview.gd" id="1"]
[node name="SmelterPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    mesh = export_mesh(vox)
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-1,0,-1],[1,3,1]]
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,
              'export_scale':SCALE,'color_encoding':'linear COLOR_0','bounds':bounds,
              'voxels':len(vox),'triangles':triangles,'connected_components':1,
              'animation_frames':8,'animation_triangles':frame_triangles,
              'sha256':sha(path),'clip_sha256':sha(clip)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('SMELTER_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/smelter_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

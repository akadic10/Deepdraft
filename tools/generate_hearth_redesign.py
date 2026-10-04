#!/usr/bin/env python3
"""Build the 2x2 hearth and its isolated, 8-voxels-per-block art review.

Exports a review under tmp/hearth_animation_preview. --install replaces
the shipping body/flame GLB and its ten-frame fire library.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125


def rgb(value):
    return tuple(int(value[i:i+2],16)/255 for i in (0,2,4))


STONE = tuple(map(rgb,('3F3938','6B6260','9B9088','ADA397','C4BEB4')))
IRON = tuple(map(rgb,('3A3838','6A6868','9A9898')))
COAL = rgb('2A2828')
EMBER = rgb('882200')
FIRE = tuple(map(rgb,('C44818','F07820','FFA830','FFDD44')))


def hearth_small():
    """Preserve the reviewed 1x1 prototype for scale comparisons."""
    v = Voxels()
    # Broad cut-corner plinth and three stone courses. The fire bowl is open
    # from above, with a four-cell interior and two-cell-thick dressed rim.
    for x in range(-4,4):
        for z in range(-4,4):
            ax,az = abs(x+.5),abs(z+.5)
            if ax+az > 6:
                continue
            inner = ax < 2 and az < 2
            v.cells[x,0,z] = STONE[1] if max(ax,az)>2 else STONE[0]
            if inner:
                v.cells[x,1,z] = COAL
                continue
            if math.hypot(ax,az) > 3.65:
                continue
            # Broad, coherent individual stones, deliberately staggered at
            # the corners. Small value shifts remain inside the stone palette.
            block = (0 if x<0 else 1)+(2 if z<0 else 0)
            for y in (1,2):
                v.cells[x,y,z] = STONE[2 if block in (0,3) else 3]
            v.cells[x,3,z] = STONE[3 if block in (0,3) else 4]
    # Quiet darker joints across the front/back faces, not per-cell noise.
    for z in (-4,3):
        for x in (-1,0):
            v.cells[x,1,z] = STONE[1]
    for x in (-4,3):
        for z in (-1,0):
            v.cells[x,2,z] = STONE[1]
    # Iron side clamps and grate with visible channels between the rails.
    for z in (-4,3):
        for x in (-3,2):
            # Clamps follow the rounded shoulder, without squaring it off.
            sz = -3 if z < 0 else 2
            v.cells[x,1,sz] = IRON[0]
            v.cells[x,2,sz] = IRON[1]
    for x in (-2,1):
        for z in range(-3,3):
            v.cells[x,2,z] = IRON[1] if z in (-3,2) else IRON[0]
    # A connected ember core, with dark char around the perimeter.
    for x,z in [(-1,-1),(0,-1),(-1,0),(0,0),(-1,1),(1,0)]:
        v.cells[x,1,z] = EMBER
        v.cells[x,2,z] = FIRE[0]
    # One central rising tongue with two lower shoulders. All flame cells
    # touch the coal bed; no floating sparks or runtime glow is required.
    flame_rows = {
        3:[(-1,-1),(0,-1),(-1,0),(0,0),(-1,1),(0,1),(1,0),(1,1)],
        4:[(-1,-1),(0,-1),(-1,0),(0,0),(-1,1),(0,1),(1,1)],
        5:[(-1,-1),(0,-1),(-1,0),(-1,1),(1,1)],
        6:[(-1,-1),(-1,0)],
        7:[(-1,-1)],
    }
    for y,cells in flame_rows.items():
        for x,z in cells:
            color = FIRE[1]
            if x == 0 and z == 0 and y <= 5:
                color = FIRE[3]
            elif (x,z) in ((-1,1),(1,1)) or y == 7:
                color = FIRE[2]
            elif x == -1 and z == -1:
                color = FIRE[0]
            v.cells[x,y,z] = color
    return v


def hearth(phase=None):
    """Author a 16x16-cell hearth with a 1-block rim and 2-block flame tip."""
    v = Voxels()
    for x in range(-8,8):
        for z in range(-8,8):
            px,pz = x+.5,z+.5
            radius = math.hypot(px,pz)
            # A broad octagonal plinth, beveled inward above the floor.
            if abs(px)+abs(pz) > 12:
                continue
            v.cells[x,0,z] = STONE[1]
            if abs(px)+abs(pz) <= 11:
                v.cells[x,1,z] = STONE[2] if radius>6.7 else STONE[1]
            if radius > 7.15:
                continue
            angle = math.atan2(pz,px)+math.pi
            lower = int(angle/(math.tau/12))
            upper = int((angle+math.pi/12)/(math.tau/12))
            if radius <= 4.4:
                # Solid stone under the char bed grounds every flame/grate.
                v.cells[x,2,z] = STONE[0]
                v.cells[x,3,z] = COAL
                continue
            for y in range(2,7):
                sector = lower if y<5 else upper
                color = STONE[2+(sector%3==1)]
                joint_phase = (angle+(0 if y<5 else math.pi/12))%(math.tau/12)
                if radius>6.2 and joint_phase < .085:
                    color = STONE[1]
                if y==4 and radius>6.6:
                    color = STONE[1] if lower%3==0 else STONE[2]
                v.cells[x,y,z] = color
            # Eight broad capstone groups on the top of the dressed rim.
            v.cells[x,7,z] = STONE[4 if (upper//2)%2==0 else 3]
            if radius < 5.1:
                v.cells[x,6,z] = STONE[1]
    # Four solid iron straps grip the octagonal shoulders. Their geometry
    # follows the stone surface and remains entirely inside the footprint.
    for sx,sz in ((-1,-1),(-1,1),(1,-1),(1,1)):
        for x,z in ((5,4),(4,5)):
            x = x if sx>0 else -x-1
            z = z if sz>0 else -z-1
            for y in range(2,6):
                if (x,y,z) in v.cells:
                    v.cells[x,y,z] = IRON[0 if y==2 else 1]
            if (x,5,z) in v.cells:
                v.cells[x,5,z] = IRON[2]
    # Recessed iron rails reach the bowl walls, with gaps exposing the coals.
    for x in (-3,-1,1,3):
        for z in range(-5,5):
            v.cells[x,4,z] = IRON[1] if z in (-5,4) else IRON[0]
    # Two charred logs, ember seams and a broad hot core under the fire.
    for z in (-2,2):
        for x in range(-4,4):
            for dz in (0,1):
                v.cells[x,5,z+dz] = COAL if x in (-4,3) else EMBER
    for x in range(-3,3):
        for z in range(-3,3):
            if (x+.5)**2+(z+.5)**2 <= 8.5:
                v.cells[x,3,z] = EMBER
                if x not in (-3,-1,1,3):
                    v.cells[x,4,z] = FIRE[0]
                v.cells[x,5,z] = FIRE[0]
    # Curving central plume and two separate shorter shoulders. Every row
    # uses the original 1/8-block cells; the larger model is not scaled up.
    fire = set()
    rows = [(5,-.5,-.5,3.2,2.8),(6,-.5,-.5,3.3,2.7),
            (7,-.5,-.5,3.0,2.5),(8,-.6,-.7,2.7,2.2),
            (9,-.8,-1,2.3,2.0),(10,-1,-1.3,2.0,1.6),
            (11,-1.2,-1.5,1.7,1.3),(12,-1.6,-1.6,1.4,1.1),
            (13,-1.8,-1.7,1.1,.85),(14,-2,-2,.8,.8),(15,-2,-2,.51,.51),
            (6,-2.5,1.3,1.8,1.6),(7,-2.8,1.5,1.6,1.4),
            (8,-3,1.7,1.4,1.2),(9,-3.3,1.8,1.1,1.0),
            (10,-3.5,2,.8,.8),(11,-4,2,.51,.51),
            (6,2,1.5,1.6,1.5),(7,2.2,1.8,1.5,1.4),
            (8,2.4,2,1.3,1.2),(9,2.7,2,1.1,1),
            (10,3,2,.9,.9),(11,3,1.7,.8,.8),(12,3,1,.51,.51)]
    if phase is not None:
        # The wide burning base stays seated in the original bowl. Above the
        # rim, three independently curling tongues rise and settle by a cell.
        animated = [row for row in rows if row[0] <= 7]
        for group, offset in ((rows[:11],0), (rows[11:17],1.9), (rows[17:],4.2)):
            top = group[-1][0]
            tip = top - (1 if offset == 0 else 0) + round(math.sin(phase+offset))
            for y in range(8,tip+1):
                source_y = 7 + (y-7)*(top-7)/(tip-7)
                a = max((row for row in group if row[0]<=source_y),key=lambda r:r[0])
                b = min((row for row in group if row[0]>=source_y),key=lambda r:r[0])
                t = (source_y-a[0])/max(1,b[0]-a[0])
                cx,cz,rx,rz = (a[k]+(b[k]-a[k])*t for k in range(1,5))
                bend = (y-7)/(tip-7)
                cx += bend*.9*math.sin(phase+offset-bend*.6)
                cz += bend*.65*math.sin(phase+offset+1.2)
                # Snap the final tip to a cell, retaining a face-connected taper.
                if y==tip:
                    _,px,pz,prx,prz = animated[-1]
                    support = [(x,z) for x in range(-5,5) for z in range(-4,5)
                               if ((x-px)/prx)**2+((z-pz)/prz)**2 <= 1]
                    cx,cz = min(support,key=lambda p:(p[0]-cx)**2+(p[1]-cz)**2)
                    rx,rz = .51,.51
                animated.append((y,cx,cz,rx,rz))
        rows = animated
    for y,cx,cz,rx,rz in rows:
        for x in range(-5,5):
            for z in range(-4,5):
                if ((x-cx)/rx)**2+((z-cz)/rz)**2 <= 1:
                    fire.add((x,y,z))
    for x,y,z in sorted(fire):
        color = FIRE[1]
        if z < -1 and x >= -1 and y < 11:
            color = FIRE[0]
        elif y>=13 or (x>=2 and z>=1) or (x<=-3 and z>=1):
            color = FIRE[2]
        if -1 <= x <= 1 and 0 <= z <= 2 and y<=9:
            color = FIRE[3] if y<=8 else FIRE[2]
        v.cells[x,y,z] = color
    return v


def hearth_parts(phase=None):
    body, flame = Voxels(), Voxels()
    for cell,color in hearth(phase).cells.items():
        (flame if color in FIRE else body).cells[cell] = color
    return body,flame


def flame_frames():
    original_body,_ = hearth_parts()
    frames = []
    for i in range(10):
        body,flame = hearth_parts(i*math.tau/10)
        assert body.cells == original_body.cells, 'Animation changed the bowl or grate'
        assert not set(body.cells)&set(flame.cells)
        combined = Voxels();combined.cells = body.cells | flame.cells
        validate(combined)
        frames.append((f'flame_{i:02}',flame))
    assert len({tuple(sorted(v.cells)) for _,v in frames})==10
    return frames


def write_hearth(path,out):
    from generate_wall_torch import write_parts
    body,flame = hearth_parts()
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,[('hearth_body',body),('hearth_flame',flame)],out,'hearth')


def write_flames(path,out):
    from generate_wall_torch import write_parts
    path.parent.mkdir(parents=True,exist_ok=True)
    return write_parts(path,flame_frames(),out,'hearth_flame')


def export_mesh(vox):
    positions,normals,colors,indices = mesh_from_voxels(vox)
    def linear(c):
        return c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4
    colors = [tuple(linear(c) for c in color[:3])+(1.,) for color in colors]
    return positions,normals,colors,indices


def validate(vox):
    cells = vox.cells
    assert all(-8 <= x < 8 and 0 <= y < 16 and -8 <= z < 8 for x,y,z in cells)
    todo = {next(iter(cells))}; visited = set()
    while todo:
        p = todo.pop(); visited.add(p)
        for d in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+d[a] for a in range(3))
            if q in cells and q not in visited:
                todo.add(q)
    assert len(visited) == len(cells), 'Disconnected geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','reference','dwarves','context','renders'):
        (out/folder).mkdir(exist_ok=True)
    live = ROOT/'assets/models/furniture/hearth.glb'
    if not (out/'reference/hearth.glb').exists():
        shutil.copyfile(live,out/'reference/hearth.glb')
    write_glb(out/'reference/hearth_1x1.glb','hearth',export_mesh(hearth_small()),export_scale=SCALE)
    for name in ('barrel','tavern_bar','bench'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','HearthRedesignPreview.gd','HearthAnimationPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    for name in ('FurnitureLighting.gd','FurnitureFlameAnimation.gd'):
        shutil.copyfile(ROOT/'scripts/components'/name,out/name)
    vox = hearth();validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/hearth.glb'
    triangles = write_hearth(path,out)
    flame_path = out/'models/hearth_flame.glb'
    flame_triangles = write_flames(flame_path,out)
    if install:
        shutil.copyfile(path,live)
        destination = ROOT/'assets/models/furniture/animations/hearth_flame.glb'
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(flame_path,destination)
    definition = json.loads((ROOT/'data/furniture/hearth.json').read_text(encoding='utf-8'))
    definition['light_source']['flame_animation']['model'] = 'res://models/hearth_flame.glb'
    (out/'hearth.json').write_text(json.dumps(definition,indent=2)+'\n',encoding='utf-8')
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft hearth art review"
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
[ext_resource type="Script" path="res://HearthAnimationPreview.gd" id="1"]
[node name="HearthAnimationPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    report = {'status':'installed' if install else 'review_export','voxels_per_block':8,'bounds':bounds,
              'voxels':len(vox.cells),'triangles':triangles,
              'named_meshes':['hearth_body','hearth_flame'],
              'animation_frames':10,'animation_triangles':flame_triangles,
              'animation_sha256':hashlib.sha256(flame_path.read_bytes()).hexdigest(),
              'color_encoding':'linear COLOR_0','connected_components':1,
              'footprint':{'width':2,'depth':2},'collision_regions':[{'min':[0,0,0],'max':[2,2,2]}],
              'fits_proposed_collision':True,'stone_rim_height':1.0,'heat_units':400,
              'prototype_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
              'live_reference_sha256':hashlib.sha256((out/'reference/hearth.glb').read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('HEARTH_PROTOTYPE_GENERATED',report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/hearth_animation_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

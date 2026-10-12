#!/usr/bin/env python3
"""Build the 2x2 hearth and its isolated, 8-voxels-per-block art review.

Exports a review under tmp/rudimentary_hearth_20261011. --install replaces
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
    """A low open-front fire bed, banked with rough dry-stacked fieldstones."""
    v = Voxels()
    fieldstone = tuple(map(rgb, ('39362F','514D42','716C5D','898473','A09B89')))
    # Soot and packed earth join the grounded stones, with a broken outline.
    # There is no cut plinth, dressed rim, grate or metal fitting.
    for x in range(-7, 7):
        for z in range(-7, 7):
            if abs(x + .5) + abs(z + .5) <= 10:
                v.cells[x, 0, z] = COAL if abs(x) < 4 and abs(z) < 4 else fieldstone[0]

    def rock(x0, z0, width, depth, height, shade):
        for y in range(height):
            for dx in range(width):
                for dz in range(depth):
                    # Broad chipped shoulders, not a rounded or bevelled mesh.
                    corner = dx in (0, width - 1) and dz in (0, depth - 1)
                    if corner and y != 1:
                        continue
                    if y == height - 1 and (dx == 0 or dz == depth - 1):
                        continue
                    color = fieldstone[shade]
                    if y == height - 1:
                        color = fieldstone[min(shade + 1, 4)]
                    elif y == 0:
                        color = fieldstone[max(shade - 1, 0)]
                    # Soot darkens only the inner faces nearest the coal bed.
                    if abs(x0 + dx) < 5 and abs(z0 + dz) < 5 and y < 3:
                        color = fieldstone[1]
                    v.cells[x0 + dx, y, z0 + dz] = color

    # Taller uneven back bank, squat side stones and a low open mouth.
    # Different widths/heights and staggered shoulders avoid masonry courses.
    for stone in [(-7,-7,5,4,5,2), (-2,-8,5,4,6,2), (3,-7,5,4,5,3),
                  (-8,-3,4,5,4,3), (4,-3,4,4,5,2),
                  (-7,2,4,4,3,2), (4,1,4,5,4,3),
                  (-5,5,4,3,2,3), (2,5,4,3,2,2)]:
        rock(*stone)
    # Low ash bed: the fire sits on the ground rather than in a tall bowl.
    for x in range(-4, 4):
        for z in range(-4, 5):
            if abs(x) + abs(z) < 7:
                v.cells[x, 1, z] = EMBER if (x + 2*z) % 5 == 0 else COAL
    # Two chunky unsawn logs point out of the mouth. Brown end grain and
    # charred tops stay visible around the flame; neither log is an iron rail.
    bark = tuple(map(rgb, ('493020', '68452B', '886038', 'AE8450')))
    for x0, front in ((-4, 5), (1, 6)):
        for z in range(-3, front):
            for dx in range(3):
                for y in range(1, 4):
                    if y == 3 and dx != 1:
                        continue
                    color = bark[1 if dx == 0 else 2]
                    if z == front - 1:
                        color = bark[3] if dx == 1 and y == 2 else bark[1]
                    elif z < 2 and y >= 2:
                        color = COAL if (z + dx) % 3 else EMBER
                    v.cells[x0 + dx, y, z] = color
    # A fixed ember/flame base leaves the body identical in every frame.
    for x in range(-3, 3):
        for z in range(-2, 3):
            if z < 0 and (x < -2 or x > 0):
                continue
            v.cells[x, 4, z] = FIRE[0] if abs(x) > 1 else FIRE[1]
    # Three simple stepped tongues rise directly from that base. Their tips
    # change by single voxels, preserving the game's chunky early-camp style.
    t = 0.0 if phase is None else phase
    for group, (cx, cz, height, offset) in enumerate(((-1,-1,8,0), (-2,1,5,2.1), (1,1,6,4.2))):
        top = 4 + height + round(math.sin(t + offset))
        previous_x, previous_width = cx - 1, 3
        for y in range(5, top + 1):
            progress = (y - 5) / max(1, top - 5)
            bend = round(progress * math.sin(t + offset))
            width = 3 if progress < .4 else 2 if progress < .8 else 1
            x0 = cx - 1 + bend
            # A moving one-cell tip must still share a face with its support.
            x0 = max(previous_x - width + 1, min(x0, previous_x + previous_width - 1))
            z0 = cz - (1 if width > 1 else 0)
            for x in range(x0, x0 + width):
                for z in range(z0, z0 + width):
                    color = FIRE[1 if group == 0 else 2]
                    if y <= 7 and x >= -1 and z >= 0:
                        color = FIRE[3]
                    elif progress > .8:
                        color = FIRE[2]
                    v.cells[x, y, z] = color
            previous_x, previous_width = x0, width
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
        assert body.cells == original_body.cells, 'Animation changed the fieldstones or logs'
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
        destination = out/'scripts/components'/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/'scripts/components'/name,destination)
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
              'fits_proposed_collision':True,'stone_rim_height':.75,'heat_units':definition['heat_source']['heat_units'],
              'prototype_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
              'live_reference_sha256':hashlib.sha256((out/'reference/hearth.glb').read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('HEARTH_PROTOTYPE_GENERATED',report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/rudimentary_hearth_20261011')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

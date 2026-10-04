#!/usr/bin/env python3
"""Approved mature oak/pine geometry and isolated review generator.

The shipping oak/pine generators reuse these builders and export_mesh for
their mature baseline summer/winter assets. This CLI writes previews only.

Run: python tools/generate_tree_redesign.py
Then import/run tmp/tree_redesign_preview with Godot. --capture saves the review.
Trees retain one voxel per block and baked scale 1.0. Authored palette values
are sRGB; only this exporter converts them to glTF's linear COLOR_0 convention.
"""
import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
NEIGHBORS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def rgb(value):
    return tuple(int(value[i:i+2], 16) / 255 for i in (0, 2, 4))


OAK = tuple(map(rgb, ('294729', '3C5E2C', '527C32', '6C963C', '87AB4F')))
PINE = tuple(map(rgb, ('203F37', '2B5140', '38674A', '4C7C51', '628F5C')))
BARK = tuple(map(rgb, ('493522', '60452C', '795637', '906D45')))
PINE_BARK = tuple(map(rgb, ('493727', '634931', '805B3A', '96704A')))
SNOW = tuple(map(rgb, ('B1C5CB', 'D3DEDC', 'EFF0E5')))


def linear(value):
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4


def branch(cells, nodes):
    """Tapered swept spheres plus a face-connected centreline, in cell centres.

    Nodes are (x,y,z,radius). The explicit spine prevents corner-only twig
    joins when the last branch segment is only one block thick.
    """
    previous = None
    for a, b in zip(nodes, nodes[1:]):
        steps = max(1, math.ceil(math.dist(a[:3], b[:3]) * 6))
        for i in range(steps + 1):
            t = i / steps
            x, y, z, radius = (a[k] + (b[k] - a[k]) * t for k in range(4))
            centre = (round(x), round(y), round(z))
            if previous is not None:
                walk = list(previous)
                for axis in (1, 0, 2):
                    while walk[axis] != centre[axis]:
                        walk[axis] += 1 if centre[axis] > walk[axis] else -1
                        if walk[1] >= 0:
                            cells.add(tuple(walk))
            previous = centre
            for vx in range(math.floor(x-radius), math.ceil(x+radius)+1):
                for vy in range(max(0, math.floor(y-radius)), math.ceil(y+radius)+1):
                    for vz in range(math.floor(z-radius), math.ceil(z+radius)+1):
                        if (vx-x)**2 + (vy-y)**2 + (vz-z)**2 <= radius**2:
                            cells.add((vx, vy, vz))


def wood_colors(cells, palette):
    result = Voxels()
    for x, y, z in sorted(cells):
        # Continuous grain and broad faces, rather than independent voxel noise.
        shade = 2 if x < 0 else 1
        if z > 0 and x <= 0:
            shade = 3 if y > 2 and (x + z) % 4 == 0 else 2
        if z < -1:
            shade = 0 if x > 0 else 1
        result.cells[x, y, z] = palette[shade]
    return result


def leaf_lobe(leaves, centre, radii, palette, lean=0.0):
    """A solid, softly squared leaf mass, with broad directional color bands."""
    cx, cy, cz = centre
    rx, ry, rz = radii
    for x in range(math.floor(cx-rx-1), math.ceil(cx+rx+1)+1):
        for y in range(math.floor(cy-ry), math.ceil(cy+ry)+1):
            for z in range(math.floor(cz-rz), math.ceil(cz+rz)+1):
                nx, ny, nz = (x-cx-lean*(y-cy))/rx, (y-cy)/ry, (z-cz)/rz
                if abs(nx)**2.35 + abs(ny)**2.35 + abs(nz)**2.35 > 1:
                    continue
                value = ny * .78 - nx * .16 + nz * .10
                shade = 0 if value < -.60 else 1 if value < -.24 else 2 if value < .20 else 3 if value < .61 else 4
                leaves.cells[x, y, z] = palette[shade]


def oak():
    wood = set()
    paths = [
        # Root flare, bent trunk and a high leader; tips all terminate in a lobe.
        [(0,0,0,1.45),(0,2,0,1.15),(0,4,0,1.15),(.5,6,0,1.05),(1,8,-1,.9),(0,11,-1,.7),(-1,14,-1,.56)],
        [(0,5,0,1.05),(-1,7,0,.95),(-3,8,0,.8),(-4,10,0,.6),(-5,12,0,.52)],
        [(-3,8,0,.7),(-4,9,2,.65),(-4,11,3,.55)],
        [(-4,10,0,.6),(-3,12,-1,.53)],
        [(.5,6,0,1.0),(2,7,1,.95),(3,9,2,.75),(4,11,2,.6),(4,13,2,.53)],
        [(3,9,2,.68),(5,10,1,.6),(6,11,0,.52)],
        [(3,9,2,.65),(2,11,4,.55),(2,12,4,.52)],
        [(1,7,-1,.9),(1,8,-2,.8),(0,10,-4,.65),(0,12,-5,.53)],
        [(0,10,-4,.6),(2,11,-4,.56),(3,12,-4,.52)],
        [(0,9,-1,.75),(-2,11,-2,.65),(-3,13,-3,.54)],
        [(0,6,0,.9),(-1,7,2,.8),(-1,9,3,.65),(-2,11,4,.55)],
        [(-1,9,3,.6),(0,10,5,.55),(1,11,5,.52)],
        [(0,11,-1,.68),(1,12,0,.6),(2,14,0,.52)],
        [(-1,13,-1,.56),(-2,14,0,.52),(-2,15,0,.51)],
    ]
    for path in paths:
        branch(wood, path)
    bark = wood_colors(wood, BARK)
    leaves = Voxels()
    # Supporting crowns and small shoulders, arranged around open
    # branch windows. The high crown is off-centre, not a sphere on a pole.
    for centre, radii, lean in [
        ((0,11,-4),(3.1,2.9,2.7),-.10),
        ((-4,10.6,0),(3.0,3.0,3.0),-.08),
        ((-2,10,4),(3.0,2.4,2.5),.12),
        ((0,11,4),(2.2,2.1,2.4),.05),
        ((4,11.7,2),(3.0,2.9,3.1),.08),
        ((-2,13,-2),(2.9,2.3,2.7),-.12),
        ((2,13,0),(2.6,2.5,2.5),.05),
        ((-1,14,0),(2.7,2.3,2.5),-.10),
    ]:
        leaf_lobe(leaves, centre, radii, OAK, lean)
    summer = Voxels()
    summer.update(leaves)
    summer.update(bark)
    return {'summer': summer, 'winter': bark}, wood, (-.5, 0, -.5)


def pine_bough(leaves, centre_y, angle, length, width, rise):
    """A broad, drooping wedge with a raised inner shoulder and a blunt tip.

    Several overlapping wedges form each broken whorl; no flat circular discs.
    """
    dx, dz = math.cos(angle), math.sin(angle)
    reach = math.ceil(length + width + 1)
    for x in range(-reach, reach+1):
        for z in range(-reach, reach+1):
            along, across = x*dx+z*dz, -x*dz+z*dx
            if along < -.6 or along > length:
                continue
            t = max(0, along/length)
            half_width = width * (1-.62*t)
            if abs(across) > half_width:
                continue
            top = centre_y + rise*(1-t) - .42*abs(across)/max(.1,half_width)
            bottom = centre_y - 1.3 + .25*(1-t)
            for y in range(math.ceil(bottom), math.floor(top)+1):
                rel = (y-bottom)/max(1,top-bottom)
                shade = 0 if rel < .18 else 1 if rel < .44 else 2 if rel < .73 else 3
                if rel > .76 and along > length*.48 and x < 1:
                    shade = 4
                leaves.cells[x,y,z] = PINE[shade]


def pine():
    wood = set()
    # Even 2x2 foot is centred directly on the origin after exporting.
    for y in range(0,7):
        for x in (-1,0):
            for z in (-1,0):
                wood.add((x,y,z))
    branch(wood, [(0,6,0,.56),(0,17,0,.56)])
    leaves = Voxels()
    for y, length, width, rise, spin, angles in [
        (6,5.1,2.1,3.3,12,(0,90,185,270)),
        (9,4.3,1.9,3.2,48,(0,96,192,275)),
        (12,3.5,1.55,3.1,7,(0,100,192,280)),
        (15,2.5,1.25,2.8,53,(0,112,240)),
    ]:
        for i, degrees in enumerate(angles):
            angle = math.radians(spin+degrees)
            branch_y = y + (.35 if i%2 else 0)
            reach = length - (.6 if i == 2 else 0)
            pine_bough(leaves, branch_y, angle, reach, width, rise)
            branch(wood, [(0,y+1,0,.56), (math.cos(angle)*reach*.7,y,math.sin(angle)*reach*.7,.51)])
    # A compact, fully foliated leader; no isolated pole between top tiers.
    for y, radius in [(16,1.5),(17,1.2),(18,.9),(19,.1)]:
        for x in range(-2,3):
            for z in range(-2,3):
                if x*x+z*z <= radius*radius:
                    leaves.cells[x,y,z] = PINE[3 if x <= 0 else 2]
    bark = wood_colors(wood, PINE_BARK)
    summer = Voxels()
    summer.update(bark)
    summer.update(leaves)
    winter = Voxels()
    winter.update(summer)
    # Snow is a recolor of coherent, upward-facing patches. It neither grows
    # extra cubes nor moves branches; every occupied cell survives the season.
    for (x,y,z), color in summer.cells.items():
        if (x,y,z) not in leaves.cells or (x,y+1,z) in summer.cells:
            continue
        # Sheltered undersides remain green; the back-right rim stays windblown.
        if x-z > 3 and y < 15:
            continue
        winter.cells[x,y,z] = SNOW[2 if y >= 12 or x < 0 else 1]
        # Small joined snow lips make patches readable from lower views.
        if (x,y-1,z) in leaves.cells and (x,y-1,z+1) not in summer.cells and (x+y)//3 % 3 != 0:
            winter.cells[x,y-1,z] = SNOW[0]
    visible_wood = wood - set(leaves.cells)
    return {'summer':summer,'winter':winter}, visible_wood, (0,0,0)


def outside_air(cells):
    low = tuple(min(p[a] for p in cells)-1 for a in range(3))
    high = tuple(max(p[a] for p in cells)+1 for a in range(3))
    queue = deque([low]); visited = {low}
    while queue:
        point = queue.popleft()
        for delta in NEIGHBORS:
            n = tuple(point[a]+delta[a] for a in range(3))
            if n in visited or n in cells or any(n[a] < low[a] or n[a] > high[a] for a in range(3)):
                continue
            visited.add(n); queue.append(n)
    return visited


def export_mesh(vox, offset):
    # Cull faces bordering sealed internal air pockets as well as solid cells.
    # This does not alter a visible silhouette or the shared mesher behavior.
    air = outside_air(vox.cells)
    p, n, c, indices = mesh_from_voxels(vox)
    positions, normals, colors, triangles = [], [], [], []
    for i in range(0,len(p),4):
        centre = [sum(p[j][a] for j in range(i,i+4))/4 for a in range(3)]
        neighbor = tuple(math.floor(centre[a]+n[i][a]*.5) for a in range(3))
        if neighbor not in air:
            continue
        first = len(positions)
        positions.extend(tuple(point[a]+offset[a] for a in range(3)) for point in p[i:i+4])
        normals.extend(n[i:i+4])
        colors.extend(tuple(linear(v) for v in color[:3])+(1.0,) for color in c[i:i+4])
        triangles.extend((first,first+1,first+2,first,first+2,first+3))
    return positions, normals, colors, triangles


def components(cells):
    pending = set(cells); sizes = []
    while pending:
        queue = [pending.pop()]; count = 0
        while queue:
            p = queue.pop(); count += 1
            for d in NEIGHBORS:
                q = tuple(p[a]+d[a] for a in range(3))
                if q in pending:
                    pending.remove(q); queue.append(q)
        sizes.append(count)
    return sorted(sizes, reverse=True)


def uses_approved_mature(stage, season, variant):
    return stage == 'mature' and season in ('summer', 'winter') and variant == 1


def prepare_preview(out):
    for folder in ('models','reference','dwarves','renders'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    # Rebuild the historical reference, even after the approved art goes live.
    # Lazy imports avoid a module-level cycle with the shipping generators.
    from generate_oak_glbs import build_legacy_oak
    from generate_pine_glbs import build_legacy_pine
    for species, builder in (('oak',build_legacy_oak),('pine',build_legacy_pine)):
        for suffix in ('','_winter'):
            name = f'{species}_mature{suffix}.glb'
            vox = builder('mature', 'winter' if suffix else 'summer', 1)
            write_glb(out/'reference'/name, Path(name).stem, mesh_from_voxels(vox))
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot',
                'eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    shutil.copyfile(ROOT/'tools/TreeRedesignPreview.gd',out/'TreeRedesignPreview.gd')
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft tree redesign study"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1600
window/size/viewport_height=1000
window/size/window_width_override=1440
window/size/window_height_override=900
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
anti_aliasing/quality/msaa_3d=2
''',encoding='utf-8')
    (out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://TreeRedesignPreview.gd" id="1"]
[node name="TreeRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')


def generate(out):
    prepare_preview(out)
    report = {'voxels_per_block':1,'color_encoding':'linear COLOR_0 from authored sRGB',
              'live_assets_changed':False,'models':{}}
    for species,builder in (('oak',oak),('pine',pine)):
        seasons, wood, offset = builder()
        assert all(seasons['summer'].cells[p] == seasons['winter'].cells[p] for p in wood)
        if species == 'pine':
            assert set(seasons['summer'].cells) == set(seasons['winter'].cells)
        else:
            assert set(seasons['winter'].cells) == wood
        for season,vox in seasons.items():
            connected = components(vox.cells)
            assert len(connected) == 1, (species,season,'disconnected cells',connected)
            name = species+'_mature'+('_winter' if season=='winter' else '')
            mesh = export_mesh(vox,offset)
            path = out/'models'/(name+'.glb')
            write_glb(path,name,mesh,export_scale=1.0)
            low = [min(p[a] for p in mesh[0]) for a in range(3)]
            high = [max(p[a] for p in mesh[0]) for a in range(3)]
            assert low[1] == 0
            assert high[1] <= (17 if species=='oak' else 20)
            report['models'][name] = {'voxels':len(vox.cells),'bounds':[low,high],
                'triangles':len(mesh[3])//3,'face_connected_components':len(connected),
                'wood_cells_stable_across_seasons':len(wood),
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/tree_redesign_preview')
    args = parser.parse_args()
    # Preview destinations are deliberately kept separate from shipping assets.
    out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory, not the project or assets directory.')
    report = generate(out)
    for name, data in report['models'].items():
        print(name, data['bounds'], str(data['triangles'])+' triangles')
    print('TREE_PROTOTYPE_GENERATED',out)


if __name__ == '__main__':
    main()

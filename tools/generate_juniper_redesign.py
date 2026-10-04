#!/usr/bin/env python3
"""Approved mature juniper geometry and its isolated seasonal review.

Run this file, then import/run tmp/juniper_redesign_preview in Godot.
The canonical juniper generator reuses this builder for the mature baseline.
This CLI writes previews only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_tree_redesign import (
    ROOT, NEIGHBORS, rgb, branch, wood_colors, leaf_lobe, export_mesh, components,
)

OFFSET = (-.5, 0, -.5)
LEAVES = tuple(map(rgb, ('294C44', '3B6255', '507A68', '72947D', '96AE90')))
BARK = tuple(map(rgb, ('493E34', '665040', '86664E', 'A38565')))
BERRIES = tuple(map(rgb, ('576D91', '738AAD', '93A5BD')))
SNOW = tuple(map(rgb, ('AEC4C9', 'D2DEDD', 'EEF0E7')))


def juniper():
    wood = set()
    # The bottom four cells stay inside the existing one-block trunk footprint.
    # All crooked wood and foliage overhangs begin above dwarf head height.
    for nodes in [
        [(0,0,0,.51),(0,3,0,.51),(0,4,0,.51),(-1,4,0,.51),(-1,6,0,.51),(0,7,0,.51),(1,9,0,.51),(1,10,0,.51)],
        [(-1,5,0,.51),(-2,5,1,.51),(-3,6,1,.51),(-3,7,1,.51)],
        [(-1,6,0,.51),(1,6,-1,.51),(3,7,-1,.51),(3,8,-1,.51)],
        [(-1,6,0,.51),(-2,7,-1,.51),(-2,9,-2,.51)],
    ]:
        branch(wood,nodes)
    bark = wood_colors(wood,BARK)
    leaves = Voxels()
    # Upright, uneven sprays, with open notches between shoulders. No discs,
    # ground-level leafy skirt or randomized holes inside a cylindrical shell.
    for centre,radii,lean in [
        ((-2.7,6.8,1.2),(1.65,2.3,1.65),-.12),
        ((2.8,7.8,-1.1),(1.55,2.45,1.55),.12),
        ((-2,8.7,-2),(1.4,2.0,1.5),-.05),
        ((1.2,9.1,.7),(1.65,2.6,1.7),.10),
    ]:
        leaf_lobe(leaves,centre,radii,LEAVES,lean)
    summer = Voxels()
    summer.update(bark)
    summer.update(leaves)
    visible_wood = wood-set(leaves.cells)
    berry_cells = set()
    # Six deliberate surface accents: readable from several sides, restrained
    # enough to stay an evergreen rather than a blue version of the apple tree.
    for anchor in [(-3,7,2),(-1,6,3),(2,9,2),(3,7,0),(-2,9,-3),(1,10,-1)]:
        candidates = [p for p in leaves.cells if p not in wood and p[1] >= 5
                      and any(tuple(p[a]+d[a] for a in range(3)) not in summer.cells
                              for d in NEIGHBORS if d[1] >= 0)
                      and all(sum(abs(p[a]-q[a]) for a in range(3)) >= 3 for q in berry_cells)]
        p = min(candidates,key=lambda p:(sum((p[a]-anchor[a])**2 for a in range(3)),p))
        berry_cells.add(p)
        summer.cells[p] = BERRIES[2 if p[1] >= 9 else 1]
    winter = Voxels()
    winter.update(summer)
    snow_cells = set()
    for (x,y,z),color in summer.cells.items():
        p = (x,y,z)
        if p not in leaves.cells or p in berry_cells or (x,y+1,z) in summer.cells:
            continue
        if x-z > 2 and y < 9:
            continue
        winter.cells[p] = SNOW[2 if y >= 9 else 1]
        snow_cells.add(p)
        below = (x,y-1,z)
        if below in leaves.cells and below not in berry_cells and (x,y-1,z+1) not in summer.cells and x < 1:
            winter.cells[below] = SNOW[0]
            snow_cells.add(below)
    return {'summer':summer,'winter':winter},visible_wood,berry_cells,snow_cells


def uses_approved_mature_juniper(stage, season, variant):
    return stage == 'mature' and season in ('summer','winter') and variant == 1


def prepare_preview(out):
    for folder in ('models','reference','dwarves','renders'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    # Lazy import preserves the historical comparison after the art goes live.
    from generate_juniper_glbs import build_legacy_juniper
    for suffix in ('','_winter'):
        name = 'juniper_mature'+suffix+'.glb'
        vox = build_legacy_juniper('mature','winter' if suffix else 'summer',1)
        write_glb(out/'reference'/name,Path(name).stem,mesh_from_voxels(vox))
    for species in ('oak','pine','apple'):
        for suffix in ('','_winter'):
            name = species+'_mature'+suffix+'.glb'
            shutil.copyfile(ROOT/'assets/models/flora/trees'/species/name,out/'models'/name)
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot',
                'eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','JuniperRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft juniper redesign study"
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
[ext_resource type="Script" path="res://JuniperRedesignPreview.gd" id="1"]
[node name="JuniperRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')


def generate(out):
    prepare_preview(out)
    models,wood,berries,snow = juniper()
    assert set(models['summer'].cells) == set(models['winter'].cells)
    assert all(models['summer'].cells[p] == models['winter'].cells[p] for p in wood|berries)
    assert snow and not (snow & (wood|berries))
    assert all(p[1] >= 4 for p in models['summer'].cells if p[0] != 0 or p[2] != 0)
    assert {p for p in models['summer'].cells if p[1] == 0} == {(0,0,0)}
    report = {'voxels_per_block':1,'color_encoding':'linear COLOR_0 from authored sRGB',
              'live_assets_changed':False,'wood_cells_visible':len(wood),
              'berry_cells':len(berries),'snow_cells':len(snow),'models':{}}
    for season,vox in models.items():
        connected = components(vox.cells)
        assert len(connected) == 1, (season,connected)
        mesh = export_mesh(vox,OFFSET)
        low = [min(p[a] for p in mesh[0]) for a in range(3)]
        high = [max(p[a] for p in mesh[0]) for a in range(3)]
        assert low[1] == 0 and high[1] == 12, (low,high)
        name = 'juniper_mature'+('_winter' if season == 'winter' else '')
        path = out/'models'/(name+'.glb')
        write_glb(path,name,mesh)
        report['models'][name] = {'voxels':len(vox.cells),'bounds':[low,high],
            'triangles':len(mesh[3])//3,'face_connected_components':len(connected),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/juniper_redesign_preview')
    out = parser.parse_args().out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    report = generate(out)
    for name,data in report['models'].items():
        print(name,data['bounds'],str(data['triangles'])+' triangles')
    print('JUNIPER_PROTOTYPE_GENERATED',out)


if __name__ == '__main__':
    main()

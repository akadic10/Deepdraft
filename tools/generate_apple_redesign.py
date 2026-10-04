#!/usr/bin/env python3
"""Approved mature apple geometry and its isolated seasonal review.

Outputs only tmp/apple_redesign_preview by default; no live registry changes.
The shipping apple generator reuses apple() and the linear-color exporter.
Uses the approved tree exporter: unit cubes, flat faces, linear vertex colors.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_tree_redesign import ROOT, rgb, branch, wood_colors, leaf_lobe, export_mesh, components, NEIGHBORS

SUMMER = tuple(map(rgb, ('344B28','4B652E','66843A','84A14D','A4B96A')))
SPRING = tuple(map(rgb, ('466237','617C40','86A04F','A3B963','BFCA86')))
AUTUMN = tuple(map(rgb, ('6C4427','93632D','B58438','CCA34D','DFC175')))
BARK = tuple(map(rgb, ('553728','704B34','895C40','A27350')))
BLOSSOM = tuple(map(rgb, ('CF8799','E8ADBB','F6D0D2','FFF0E5')))
FRUIT = tuple(map(rgb, ('A82E35','CA4038','E65C47')))
SEASONS = ('spring','summer','autumn','autumn_fruiting','winter')
OFFSET = (-.5,0,-.5)


def model_name(season):
    return 'apple_mature' + ('' if season == 'summer' else '_'+season)


def uses_approved_mature_apple(stage, season, variant):
    return stage == 'mature' and variant == 1 and season in SEASONS


def surface(cells):
    return {p for p in cells if any(tuple(p[a]+d[a] for a in range(3)) not in cells for d in NEIGHBORS)}


def blossom_patch(vox, allowed, anchor, count, used):
    """A small connected petal group following the existing canopy surface."""
    def score(p):
        return sum((p[a]-anchor[a])**2 for a in range(3)), p
    available = allowed-used
    if not available:
        return set()
    start = min(available,key=score)
    patch = {start}
    while len(patch) < count:
        candidates = {tuple(p[a]+d[a] for a in range(3)) for p in patch for d in NEIGHBORS}
        candidates &= available-patch
        candidates = {p for p in candidates if score(p)[0] <= 9}
        if not candidates:
            break
        patch.add(min(candidates,key=score))
    high = max(p[1] for p in patch)
    for p in sorted(patch):
        shade = 3 if p[1] == high else 2
        if p == min(patch,key=score):
            shade = 1
        vox.cells[p] = BLOSSOM[shade]
    return patch


def apple():
    # A low, crooked orchard scaffold. Main arms spread before rising, unlike
    # the upright oak forks. All winter wood is present in the leafy models.
    wood = set()
    for path in [
        [(0,0,0,1.45),(0,1,0,1.2),(-.35,3,0,1.05),(-1,4,0,.95),(-2,5,-1,.8),(-3,7,-2,.63),(-3,9,-2,.52)],
        [(-1,3,0,1.05),(-2,4,0,.9),(-4,5,0,.8),(-5,6,0,.65),(-5,8,-1,.52)],
        [(-4,5,0,.7),(-5,6,2,.6),(-6,7,2,.51)],
        [(-2,4,0,.9),(-2,5,2,.78),(-3,6,3,.6),(-3,8,4,.52)],
        [(-2,5,2,.65),(0,6,4,.6),(0,8,4,.52)],
        [(0,3,0,1.0),(1,4,0,.95),(3,4,0,.8),(4,6,0,.7),(5,8,0,.54)],
        [(4,6,0,.65),(4,7,2,.6),(5,8,3,.52)],
        [(3,4,0,.75),(2,5,-2,.65),(3,7,-3,.55),(4,8,-3,.52)],
        [(-1,4,0,.85),(-1,5,-2,.7),(-1,6,-4,.6),(0,8,-4,.52)],
        [(-1,6,-4,.58),(-3,7,-4,.52)],
        [(1,4,0,.85),(1,6,0,.68),(1,8,0,.58),(2,9,0,.51)],
    ]:
        branch(wood,path)
    # Keep the lowest four blocks inside the existing 3x3 trunk footprint.
    # Outward branches then clear the updated dwarf's 3.375-block visual height.
    wood = {p for p in wood if p[1] >= 4 or (abs(p[0]) <= 1 and abs(p[2]) <= 1)}
    bark = wood_colors(wood,BARK)
    leaves = Voxels()
    for centre,radii,lean in [
        ((-1,8,-3),(3.1,2.3,2.7),-.05),
        ((-4,8,0),(3.2,2.5,2.8),-.08),
        ((4,8,0),(3.1,2.5,3.3),.10),
        ((-2,7.5,3),(3.4,2.5,2.8),-.08),
        ((2,8,3),(2.7,2.1,2.6),.12),
        ((1,9,0),(2.6,2.1,2.6),.04),
    ]:
        leaf_lobe(leaves,centre,radii,SUMMER,lean)
    # Keep branch interiors as wood in every season; nothing grows on the trunk.
    for p in wood:
        leaves.cells.pop(p,None)
    models = {}
    for season,palette in [('spring',SPRING),('summer',SUMMER),('autumn',AUTUMN)]:
        v = Voxels()
        v.update(bark)
        v.cells.update({p:palette[SUMMER.index(color)] for p,color in leaves.cells.items()})
        models[season] = v
    blossom_cells = set()
    shell = surface(models['summer'].cells)
    blossom_allowed = {p for p in shell if p in leaves.cells and p[1] >= 7}
    for anchor,count in [
        ((-5,9,1),5),((-4,8,2),4),((-3,10,-1),4),((-2,9,-4),4),
        ((1,10,-2),4),((4,9,-1),5),((5,9,2),4),((2,9,3),4),
        ((-1,8,5),5),((-3,8,4),4),((3,7,4),3),
    ]:
        blossom_cells |= blossom_patch(models['spring'],blossom_allowed,anchor,count,blossom_cells)
    fruiting = Voxels()
    fruiting.update(models['autumn'])
    fruit_cells = set()
    # Authored shoulder groups, including the back. Fruit attaches to an outer
    # leaf face; harvest removes these cubes without repainting or moving leaves.
    for anchor,direction,count in [
        ((-6,9,1),(0,1,0),2),((5,9,2),(1,0,0),2),
        ((-2,8,5),(0,0,1),2),((2,9,4),(0,0,1),2),
        ((-2,9,-4),(0,0,-1),2),((4,8,-2),(1,0,0),2),
        ((-5,7,-1),(-1,0,0),2),
    ]:
        candidates = []
        for p in leaves.cells:
            q = tuple(p[a]+direction[a] for a in range(3))
            if q in fruiting.cells or not 7 <= q[1] <= 10 or abs(q[0]) > 7 or abs(q[2]) > 6:
                continue
            distance = sum((p[a]-anchor[a])**2 for a in range(3))
            if distance <= 12:
                candidates.append((distance,p,q))
        chosen = []
        while len(chosen) < count:
            available = [(distance,p,q) for distance,p,q in candidates if q not in fruiting.cells]
            if chosen:
                available = [(distance,p,q) for distance,p,q in available
                             if sum(abs(q[a]-chosen[0][a]) for a in range(3)) == 2]
            if not available:
                break
            # Diagonally staggered pairs remain distinct apples, not a red bar.
            def rank(candidate):
                distance,p,q = candidate
                stagger = 0 if chosen and abs(q[1]-chosen[0][1]) == 1 else 1
                return stagger,distance,p
            _,p,q = min(available,key=rank)
            fruiting.cells[q] = FRUIT[2 if len(chosen) == 0 and q[0] < 1 else 1]
            fruit_cells.add(q)
            chosen.append(q)
        assert len(chosen) == count, ('fruit group without support',anchor,chosen)
    models['autumn_fruiting'] = fruiting
    models['winter'] = bark
    return models,wood,blossom_cells,fruit_cells


def prepare_preview(out):
    for folder in ('models','reference','dwarves','renders'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    # Preserve historical comparisons after the approved models go live.
    from generate_apple_glbs import build_legacy_apple
    for season in SEASONS:
        name = model_name(season)+'.glb'
        legacy = build_legacy_apple('mature',season,1)
        write_glb(out/'reference'/name,model_name(season),mesh_from_voxels(legacy))
    for species in ('oak','pine'):
        for suffix in ('','_winter'):
            name = species+'_mature'+suffix+'.glb'
            shutil.copyfile(ROOT/'assets/models/flora/trees'/species/name,out/'models'/name)
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot',
                'eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','AppleRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft apple redesign study"
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
[ext_resource type="Script" path="res://AppleRedesignPreview.gd" id="1"]
[node name="AppleRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')


def generate(out):
    prepare_preview(out)
    models,wood,blossoms,fruit = apple()
    summer = models['summer'].cells
    assert all(set(models[s].cells) == set(summer) for s in ('spring','autumn'))
    assert set(models['winter'].cells) == wood
    assert set(models['autumn_fruiting'].cells)-set(models['autumn'].cells) == fruit
    assert all(models['autumn_fruiting'].cells[p] == c for p,c in models['autumn'].cells.items())
    assert all(v.cells[p] == models['winter'].cells[p] for v in models.values() for p in wood)
    assert not (fruit & wood or blossoms & wood)
    assert all(p[1] >= 4 for p in summer if abs(p[0]) > 1 or abs(p[2]) > 1)
    report = {'voxels_per_block':1,'color_encoding':'linear COLOR_0 from authored sRGB',
              'output_scope':'isolated apple prototype','wood_cells':len(wood),
              'blossom_cells':len(blossoms),'fruit_cells':len(fruit),'models':{}}
    for season in SEASONS:
        vox = models[season]
        connected = components(vox.cells)
        assert len(connected) == 1, (season,connected)
        mesh = export_mesh(vox,OFFSET)
        low = [min(p[a] for p in mesh[0]) for a in range(3)]
        high = [max(p[a] for p in mesh[0]) for a in range(3)]
        assert low[1] == 0 and high[1] <= 12, (season,low,high)
        name = model_name(season)
        path = out/'models'/(name+'.glb')
        write_glb(path,name,mesh)
        report['models'][name] = {'voxels':len(vox.cells),'bounds':[low,high],
            'triangles':len(mesh[3])//3,'face_connected_components':len(connected),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/apple_redesign_preview')
    args = parser.parse_args()
    out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    report = generate(out)
    for name,data in report['models'].items():
        print(name,data['bounds'],str(data['triangles'])+' triangles')
    print('APPLE_PROTOTYPE_GENERATED',out)


if __name__ == '__main__':
    main()

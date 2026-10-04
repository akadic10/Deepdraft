#!/usr/bin/env python3
"""Complete 1:1 tree roster: approved mature art plus saplings and ancient trees.

Canonical species generators call build_model/mesh_model/manifest. This CLI
exports an isolated review; --install also updates live GLBs and model arrays.
Existing gameplay data is preserved. Every season has matching variant order.
"""
import argparse
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, write_glb
import generate_tree_redesign as trees
import generate_apple_redesign as apples
import generate_juniper_redesign as junipers

ROOT = Path(__file__).resolve().parents[1]
SPECIES = ('oak','pine','apple','juniper')
STAGES = ('sapling','mature','ancient')
FOOTPRINTS = {'oak':(1,3,5),'pine':(1,2,3),'apple':(1,3,5),'juniper':(1,1,2)}
PALETTES = {'oak':trees.OAK,'pine':trees.PINE,'apple':apples.SUMMER,'juniper':junipers.LEAVES}
OAK_SPRING = tuple(map(trees.rgb,('3C592B','557632','719346','90AE5A','ADC47A')))
OAK_AUTUMN = tuple(map(trees.rgb,('643D27','86502C','A76B32','C18D44','D9AF66')))


def seasons_for(species,stage):
    if species in ('pine','juniper'):
        return ('summer','winter')
    return ('spring','summer','autumn','autumn_fruiting','winter') if species == 'apple' and stage != 'sapling' else ('spring','summer','autumn','winter')


def variant_count(species,stage):
    return 1 if stage == 'sapling' else 2 if species == 'juniper' else 3


def model_name(species,stage,season,variant):
    return species+'_'+stage+('' if season == 'summer' else '_'+season)+('' if variant == 1 else '_'+str(variant))


def manifest(species):
    return [(model_name(species,stage,season,variant),stage,season,variant)
            for stage in STAGES for season in seasons_for(species,stage)
            for variant in range(1,variant_count(species,stage)+1)]


def offset_for(species,stage):
    return (0,0,0) if FOOTPRINTS[species][STAGES.index(stage)] % 2 == 0 else (-.5,0,-.5)


def clone(vox):
    result = Voxels(); result.update(vox); return result


def scaffold(paths,footprint,clearance=4):
    cells = set()
    for path in paths:
        trees.branch(cells,path)
    lo = -(footprint//2); hi = lo+footprint
    return {p for p in cells if p[1] >= clearance or (lo <= p[0] < hi and lo <= p[2] < hi)}


def foliage(lobes,palette):
    leaves = Voxels()
    for centre,radii,lean in lobes:
        trees.leaf_lobe(leaves,centre,radii,palette,lean)
    return leaves


def deciduous(wood,leaves,species):
    bark_palette = trees.BARK if species == 'oak' else apples.BARK
    base_palette = PALETTES[species]
    spring = OAK_SPRING if species == 'oak' else apples.SPRING
    autumn = OAK_AUTUMN if species == 'oak' else apples.AUTUMN
    bark = trees.wood_colors(wood,bark_palette)
    result = {}
    for season,palette in [('spring',spring),('summer',base_palette),('autumn',autumn)]:
        v = clone(bark)
        v.cells.update({p:palette[base_palette.index(c)] for p,c in leaves.cells.items() if p not in wood})
        result[season] = v
    result['winter'] = bark
    return result


def add_apple_seasons(models,ancient):
    summer = models['summer'].cells
    wood = set(models['winter'].cells)
    shell = apples.surface(summer)-wood
    high = max(p[1] for p in shell)
    flower_allowed = {p for p in shell if p[1] >= high-(5 if ancient else 2)}
    used = set()
    anchors = [(-8,13,1),(-6,14,-3),(-3,15,-6),(1,15,-5),(6,14,-2),(8,12,1),
               (6,14,5),(2,13,7),(-3,13,7),(-7,12,4),(-1,17,0),(3,16,2)] if ancient else [(-1,5,1),(1,5,-1)]
    for anchor in anchors:
        used |= apples.blossom_patch(models['spring'],flower_allowed,anchor,6 if ancient else 2,used)
    if not ancient:
        return
    fruiting = clone(models['autumn'])
    picked = set()
    for anchor in anchors:
        # Two staggered apples near each shoulder; every cube directly touches
        # existing foliage, and fruit removal restores the exact autumn tree.
        candidates = []
        for p in sorted(shell):
            if p[1] < 10:
                continue
            for d in trees.NEIGHBORS:
                if d[1] < 0:
                    continue
                q = tuple(p[a]+d[a] for a in range(3))
                if q not in fruiting.cells and q[1] <= high:
                    candidates.append((sum((q[a]-anchor[a])**2 for a in range(3)),q))
        first = None
        for i in range(2):
            allowed = [(score,q) for score,q in candidates if q not in picked
                       and (first is None or sum(abs(q[a]-first[a]) for a in range(3)) == 2)]
            assert allowed, anchor
            _,q = min(allowed)
            first = q if first is None else first
            picked.add(q)
            fruiting.cells[q] = apples.FRUIT[2 if i == 0 else 1]
    models['autumn_fruiting'] = fruiting


def snowy(summer,palette,snow_palette):
    winter = clone(summer)
    leaves = {p for p,c in summer.cells.items() if c in palette}
    top = max(p[1] for p in leaves)
    for x,y,z in sorted(leaves):
        if (x,y+1,z) in summer.cells or (x-z > 3 and y < top-3):
            continue
        winter.cells[x,y,z] = snow_palette[2 if y >= top-4 or x < 0 else 1]
        below = (x,y-1,z)
        if below in leaves and (x,y-1,z+1) not in summer.cells and (x+y)//3 % 3 != 0:
            winter.cells[below] = snow_palette[0]
    return winter


def oak_age(stage):
    if stage == 'sapling':
        wood = scaffold([
            [(0,0,0,.51),(0,3,0,.51),(0,5,0,.51)],
            [(0,2,0,.51),(-1,3,0,.51),(-1,4,0,.51)],
            [(0,3,0,.51),(1,4,1,.51),(1,5,1,.51)],
        ],1,2)
        leaves = foliage([((-1,4,0),(1.6,1.6,1.5),-.1),((1,5,1),(1.5,1.6,1.5),.05),((0,5,-1),(1.5,1.6,1.5),0)],trees.OAK)
    else:
        wood = scaffold([
            [(0,0,0,2.35),(0,2,0,1.9),(0,5,0,1.6),(1,8,0,1.45),(1,11,-1,1.2),(-1,15,-1,.95),(-2,19,-1,.65),(-2,21,0,.51)],
            [(0,6,0,1.5),(-2,8,0,1.25),(-5,11,0,1.05),(-7,14,1,.8),(-8,17,1,.6),(-8,19,1,.51)],
            [(-5,11,0,.9),(-6,13,-3,.8),(-7,16,-4,.6),(-7,18,-4,.51)],
            [(-7,14,1,.8),(-6,16,4,.65),(-5,19,5,.51)],
            [(1,7,0,1.4),(3,9,1,1.15),(5,12,2,.95),(7,15,3,.72),(8,18,3,.51)],
            [(5,12,2,.9),(7,13,0,.7),(9,16,-1,.51)],
            [(3,9,1,1.1),(3,11,4,.85),(4,14,6,.7),(5,17,7,.51)],
            [(1,8,-1,1.2),(1,10,-3,1.0),(0,13,-6,.8),(-1,17,-7,.6),(-1,19,-7,.51)],
            [(0,13,-6,.8),(3,15,-6,.65),(4,18,-5,.51)],
            [(0,7,0,1.2),(-1,9,3,1.0),(-3,12,5,.8),(-3,16,7,.6),(-3,18,7,.51)],
            [(-1,15,-1,.85),(1,17,0,.7),(3,20,1,.6),(3,22,1,.51)],
            [(0,2,0,1.4),(-2,0,0,.8)],[(0,2,0,1.4),(2,0,1,.8)],
        ],5)
        leaves = foliage([
            ((-7,17,1),(4.1,3.5,3.8),-.10),((-6,17,-4),(3.7,3.4,3.5),-.1),
            ((-5,19,5),(3.7,3.3,3.6),.1),((7,18,3),(4.1,3.4,3.8),.08),
            ((8,16,-1),(3.2,3.0,3.3),.1),((4,17,7),(3.8,3.0,3.4),.05),
            ((-1,18,-7),(4.0,3.5,3.2),-.1),((3,19,-4),(3.7,3.3,3.6),.05),
            ((-3,18,7),(3.7,3.2,3.5),-.05),((-2,20,-1),(4.0,3.3,3.8),-.1),
            ((3,20,1),(3.5,3.2,3.7),.05),
        ],trees.OAK)
    return deciduous(wood,leaves,'oak')


def apple_age(stage):
    if stage == 'sapling':
        wood = scaffold([
            [(0,0,0,.51),(0,2,0,.51),(-1,3,0,.51),(-1,4,0,.51)],
            [(0,2,0,.51),(1,3,0,.51),(2,4,0,.51)],[(0,3,0,.51),(0,4,-1,.51)],
        ],1,2)
        leaves = foliage([((-1,4,0),(1.8,1.5,1.8),-.1),((2,4,0),(1.7,1.4,1.7),.1),((0,4.7,-1),(1.7,1.1,1.7),0)],apples.SUMMER)
    else:
        wood = scaffold([
            [(0,0,0,2.35),(0,2,0,1.85),(-1,4,0,1.5),(-2,6,-1,1.3),(-3,9,-2,1.0),(-4,12,-3,.75),(-4,14,-3,.51)],
            [(-1,4,0,1.5),(-3,5,0,1.2),(-6,7,0,.95),(-8,9,0,.75),(-8,12,0,.51)],
            [(-6,7,0,.9),(-7,8,3,.75),(-8,11,4,.51)],
            [(-2,5,0,1.2),(-3,7,3,1.0),(-4,9,5,.8),(-4,12,7,.51)],
            [(-3,7,3,.9),(0,9,6,.75),(0,12,7,.51)],
            [(0,4,0,1.4),(2,5,0,1.2),(5,6,0,1.0),(7,9,1,.8),(8,12,1,.51)],
            [(5,6,0,1.0),(5,8,4,.8),(6,11,6,.51)],
            [(5,6,0,.95),(4,8,-3,.75),(6,11,-4,.51)],
            [(-1,5,0,1.2),(-1,7,-3,1.0),(-2,10,-6,.75),(-1,13,-7,.51)],
            [(-2,10,-6,.7),(-5,12,-6,.51)],
            [(1,5,0,1.1),(1,8,0,.95),(0,11,1,.8),(0,14,1,.55),(1,15,1,.51)],
            [(1,8,0,.9),(3,10,2,.7),(4,13,3,.51)],
        ],5)
        leaves = foliage([
            ((-7,11,0),(4.0,3.1,3.7),-.1),((-6,11.5,4),(3.5,3.0,3.4),-.08),
            ((-3,12,6),(4.1,3.1,3.7),-.05),((2,12,6),(3.7,3.0,3.3),.08),
            ((7,12,0),(4.0,3.2,3.9),.1),((5,12,4),(3.9,3.0,3.8),.08),
            ((4,12,-4),(3.7,3.1,3.6),.08),((-2,13,-6),(4.2,3.2,3.2),-.07),
            ((-3,14,-2),(3.4,3.0,3.4),-.08),((1,14,1),(3.6,3.1,3.6),.05),
        ],apples.SUMMER)
    models = deciduous(wood,leaves,'apple')
    add_apple_seasons(models,stage == 'ancient')
    return models


def pine_age(stage):
    wood = set(); leaves = Voxels()
    if stage == 'sapling':
        trees.branch(wood,[(0,0,0,.51),(0,6,0,.51)])
        tiers = [(2.8,2.25,1.0,2.1,15),(4.5,1.6,.85,1.9,55)]
        leader = [(6,1.0),(7,0)]
    else:
        wood = scaffold([[(0,0,0,1.45),(0,5,0,1.3),(0,10,0,1.0),(0,18,0,.65),(0,25,0,.51)]],3)
        tiers = [(6,7.0,2.7,4.1,10),(10,6.0,2.45,4.0,45),(14,5.0,2.1,3.9,8),
                 (18,4.0,1.9,3.6,52),(21.5,2.9,1.5,3.1,14),(24,1.7,1.0,2.0,58)]
        leader = [(24,1.4),(25,1.0),(26,0)]
    for y,length,width,rise,spin in tiers:
        for i,degrees in enumerate((0,93,189,276)):
            angle = math.radians(spin+degrees)
            reach = length-(.5 if i == 2 else 0)
            trees.pine_bough(leaves,y,angle,reach,width,rise)
            trees.branch(wood,[(0,y+1,0,.51),(math.cos(angle)*reach*.72,y,math.sin(angle)*reach*.72,.51)])
    for y,radius in leader:
        for x in range(-2,3):
            for z in range(-2,3):
                if x*x+z*z <= radius*radius:
                    leaves.cells[x,y,z] = trees.PINE[3 if x <= 0 else 2]
    # Needle tips cover the thin branch ends; avoid isolated brown pixels in
    # the upper crown while retaining the visible central bole.
    for x,y,z in sorted(wood):
        if y >= (3 if stage == 'sapling' else 8) and (abs(x) > 1 or abs(z) > 1) and (x,y,z) not in leaves.cells:
            leaves.cells[x,y,z] = trees.PINE[2]
    summer = trees.wood_colors(wood,trees.PINE_BARK);summer.update(leaves)
    return {'summer':summer,'winter':snowy(summer,trees.PINE,trees.SNOW)}


def juniper_age(stage):
    if stage == 'sapling':
        wood = scaffold([[(0,0,0,.51),(0,2,0,.51),(0,3,0,.51)],[(0,2,0,.51),(-1,3,0,.51)]],1,2)
        lobes = [((0,3.1,0),(1.25,1.7,1.1),.08),((-1,2.8,.8),(1.0,1.2,1.0),-.1)]
        berry_count = 0
    else:
        wood = set()
        for y in range(4):
            for x in (-1,0):
                for z in (-1,0):
                    wood.add((x,y,z))
        wood |= scaffold([
            [(-.5,3,-.5,.8),(-1,5,0,.9),(-2,7,0,.85),(-1,10,0,.7),(1,12,0,.6),(1,14,0,.51)],
            [(-1,5,0,.85),(-3,6,1,.8),(-4,8,1,.65),(-4,10,1,.51)],
            [(-2,7,0,.8),(-3,9,-2,.7),(-3,12,-2,.51)],
            [(-1,8,0,.75),(1,8,-1,.7),(3,10,-2,.65),(3,12,-2,.51)],
            [(-1,9,0,.7),(0,10,2,.6),(1,12,3,.51)],
            [(1,11,0,.65),(3,12,1,.6),(4,13,1,.51)],
        ],2)
        lobes = [((-4,9,1),(2.0,2.5,1.9),-.1),((-3,12,-2),(1.9,2.7,1.8),-.08),
                 ((3,11,-2),(2.0,2.7,1.9),.12),((1,13,.3),(2.0,2.5,2.0),.1),
                 ((1,11.7,3),(1.8,2.1,1.8),.12),((4,12.4,1),(1.7,2.0,1.8),.1)]
        berry_count = 10
    leaves = foliage(lobes,junipers.LEAVES)
    summer = trees.wood_colors(wood,junipers.BARK);summer.update(leaves)
    candidates = sorted(apples.surface(summer.cells)&set(leaves.cells))
    picked = []
    for i in range(berry_count):
        angle = i*math.tau/berry_count
        anchor = (math.cos(angle)*4,10+i%4,math.sin(angle)*3)
        eligible = [p for p in candidates if p not in wood and all(sum(abs(p[a]-q[a]) for a in range(3)) >= 3 for q in picked)]
        p = min(eligible,key=lambda p:(sum((p[a]-anchor[a])**2 for a in range(3)),p))
        summer.cells[p] = junipers.BERRIES[1 if i%3 else 2];picked.append(p)
    return {'summer':summer,'winter':snowy(summer,junipers.LEAVES,junipers.SNOW)}


def mature(species):
    if species == 'oak':
        models,wood,_ = trees.oak()
        leaves = Voxels();leaves.cells = {p:c for p,c in models['summer'].cells.items() if p not in wood}
        seasonal = deciduous(wood,leaves,'oak')
        # Preserve approved summer/winter export order and bytes exactly.
        seasonal['summer'] = models['summer'];seasonal['winter'] = models['winter']
        return seasonal
    if species == 'pine':
        return trees.pine()[0]
    if species == 'apple':
        return apples.apple()[0]
    return junipers.juniper()[0]


def vary_shape(models,species,stage,variant):
    """Broaden one crown shoulder, then rotate/reflect the entire seasonal set.

    Grid-preserving transformations keep unit cubes and exact wood/fruit
    relationships. The additional solid spray changes the silhouette as well
    as its orientation; this is not per-voxel random noise.
    """
    result = {season:clone(vox) for season,vox in models.items()}
    palette = PALETTES[species]
    green = {p for p,c in models['summer'].cells.items() if c in palette}
    side = -1 if variant == 2 else 1
    edge = min(p[0] for p in green) if side < 0 else max(p[0] for p in green)
    target_y = max(p[1] for p in green)*.72
    anchor = min(green,key=lambda p:(abs(p[0]-edge)+.6*abs(p[1]-target_y)+.2*abs(p[2]),p))
    r = 2.2 if stage == 'ancient' else 1.65
    if species == 'pine':
        spray = Voxels()
        trees.pine_bough(spray,anchor[1]+.4,math.pi if side < 0 else 0,r+1,r*.65,2.5)
        extension = Voxels()
        extension.cells = {(x+anchor[0],y,z+anchor[2]):c for (x,y,z),c in spray.cells.items()}
    else:
        extension = foliage([((anchor[0]+side*.5,anchor[1]+.35,anchor[2]),(r,r*.95,r),side*.08)],palette)
    occupied = set().union(*(set(v.cells) for v in models.values()))
    additions = {p:c for p,c in extension.cells.items() if p not in occupied and p[1] >= 4}
    for season,vox in result.items():
        if season == 'winter':
            continue
        mapped = palette
        if species == 'oak':
            mapped = OAK_SPRING if season == 'spring' else OAK_AUTUMN if season == 'autumn' else palette
        elif species == 'apple':
            mapped = apples.SPRING if season == 'spring' else apples.AUTUMN if season.startswith('autumn') else palette
        vox.cells.update({p:mapped[palette.index(c)] for p,c in additions.items()})
    if species in ('pine','juniper'):
        result['winter'] = snowy(result['summer'],palette,trees.SNOW if species == 'pine' else junipers.SNOW)
    pivot = -.5 if offset_for(species,stage)[0] == 0 else 0
    for vox in result.values():
        rotated = {}
        for (x,y,z),color in vox.cells.items():
            x -= pivot;z -= pivot
            x,z = (-z,x) if variant == 2 else (-x,z)
            rotated[round(x+pivot),y,round(z+pivot)] = color
        vox.cells = rotated
    return result


@lru_cache(maxsize=None)
def models_for(species,stage,variant=1):
    if stage == 'mature':
        models = mature(species)
    else:
        models = {'oak':oak_age,'pine':pine_age,'apple':apple_age,'juniper':juniper_age}[species](stage)
    return vary_shape(models,species,stage,variant) if variant != 1 else models


def build_model(species,stage,season='summer',variant=1):
    return clone(models_for(species,stage,variant)[season])


def mesh_model(vox,species,stage):
    return trees.export_mesh(vox,offset_for(species,stage))


def validate_set(species,stage,variant,models):
    summer = models['summer'].cells
    for season,vox in models.items():
        assert len(trees.components(vox.cells)) == 1,(species,stage,variant,season,'disconnected')
        assert min(p[1] for p in vox.cells) == 0
    if species in ('oak','apple'):
        wood = models['winter'].cells
        assert all(v.cells[p] == c for v in models.values() for p,c in wood.items())
        assert set(summer) == set(models['spring'].cells) == set(models['autumn'].cells)
        if 'autumn_fruiting' in models:
            autumn = models['autumn'].cells;fruiting = models['autumn_fruiting'].cells
            assert all(fruiting[p] == c for p,c in autumn.items())
            assert all(any(tuple(p[a]+d[a] for a in range(3)) in autumn for d in trees.NEIGHBORS) for p in set(fruiting)-set(autumn))
    else:
        assert set(summer) == set(models['winter'].cells)
        assert all(models['winter'].cells[p] == c for p,c in summer.items() if c not in PALETTES[species])
    if stage != 'sapling':
        footprint = FOOTPRINTS[species][STAGES.index(stage)];lo = -(footprint//2)
        assert all(p[1] >= 4 for p in summer if not (lo <= p[0] < lo+footprint and lo <= p[2] < lo+footprint)),(species,stage,variant,'clearance')


def prepare_preview(out):
    for folder in ('models','renders','dwarves'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','ForestRedesignPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft complete forest review"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1800
window/size/viewport_height=1100
window/size/window_width_override=1440
window/size/window_height_override=880
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
anti_aliasing/quality/msaa_3d=2
''',encoding='utf-8')
    (out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://ForestRedesignPreview.gd" id="1"]
[node name="ForestRedesignPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')


def generate(out,install=False):
    prepare_preview(out)
    report = {'voxels_per_block':1,'color_encoding':'linear COLOR_0','models':{}}
    for species in SPECIES:
        folder = out/'models'/species;folder.mkdir(exist_ok=True)
        for stage in STAGES:
            for variant in range(1,variant_count(species,stage)+1):
                validate_set(species,stage,variant,models_for(species,stage,variant))
        for name,stage,season,variant in manifest(species):
            vox = build_model(species,stage,season,variant);mesh = mesh_model(vox,species,stage)
            path = folder/(name+'.glb');write_glb(path,name,mesh)
            low = [min(p[a] for p in mesh[0]) for a in range(3)];high = [max(p[a] for p in mesh[0]) for a in range(3)]
            report['models'][name] = {'species':species,'stage':stage,'season':season,'variant':variant,'bounds':[low,high],
                'voxels':len(vox.cells),'triangles':len(mesh[3])//3,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        if install:
            for path in folder.glob('*.glb'):
                shutil.copyfile(path,ROOT/'assets/models/flora/trees'/species/path.name)
            registry_path = ROOT/'data/entities/flora'/(species+'_tree.json')
            registry = json.loads(registry_path.read_text(encoding='utf-8'))
            comments = registry.get('__comment',[])
            prefix = next((i for i,line in enumerate(comments) if line.startswith('MODEL VARIANTS')),len(comments))
            registry['__comment'] = comments[:prefix] + ['MODEL VARIANTS — complete visual roster (doc 29):',
                'All stages use redesigned 1:1 models. Season arrays have matching variant counts/order.',
                'World-position hashing preserves each tree variant across seasonal changes.',
                'Placement, growth, collision and harvest values are unchanged.']
            for stage in STAGES:
                values = {}
                for season in seasons_for(species,stage):
                    paths = ['res://assets/models/flora/trees/'+species+'/'+model_name(species,stage,season,v)+'.glb' for v in range(1,variant_count(species,stage)+1)]
                    values[season] = paths[0] if len(paths) == 1 else paths
                registry['base:flora:'+species+'_tree']['stages'][stage]['models'] = values
            registry_path.write_text(json.dumps(registry,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/forest_redesign_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args();out = args.out.resolve()
    if out == ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    report = generate(out,args.install)
    for species in SPECIES:
        for stage in STAGES:
            item = report['models'][model_name(species,stage,'summer',1)]
            print(species,stage,'size',[item['bounds'][1][a]-item['bounds'][0][a] for a in range(3)],'triangles',item['triangles'])
    print('FOREST_ROSTER_GENERATED',len(report['models']),'models',out)


if __name__ == '__main__':
    main()

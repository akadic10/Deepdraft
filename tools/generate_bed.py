#!/usr/bin/env python3
"""Build the 4x2 standalone dwarven bed at eight voxels/block; --install adds its GLB."""
import argparse
import json
from pathlib import Path
import shutil

from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import OAK, IRON, box, export_mesh, sha, rgb

ROOT = Path(__file__).resolve().parents[1]
SCALE = .125
MODEL = 'assets/models/furniture/dwarf_bunk.glb'


# Linen shades derive from doc 61 cloth_undyed; teal repeats the dwarf tunic.
LINEN = tuple(rgb(h) for h in ('9F8D65','C8B888','DCD0AC','ECE3CA'))
BLANKET = tuple(rgb(h) for h in ('34544F','456E69','648C83'))


def dwarf_bunk():
    """32x16x16 cells: length on X, headboard at -X, open foot at +X."""
    v = Voxels()
    # Substantial corner posts and iron shoes. Only the head end rises above bedding.
    for x0,x1 in ((-16,-13),(13,16)):
        for z0,z1 in ((-8,-5),(5,8)):
            box(v,x0,x1,0,6,z0,z1,OAK[2])
            box(v,x0,x1,0,1,z0,z1,OAK[1])
            for z in (z0,z1-1):
                box(v,x0,x1,1,2,z,z+1,IRON[1])
                v.cells[x0+1,1,z] = IRON[2]
    # Low bed frame, long rails, and slatted support beneath the straw mattress.
    for z0,z1 in ((-8,-6),(6,8)):
        box(v,-16,16,3,6,z0,z1,OAK[3])
        box(v,-14,14,3,4,z0,z1,OAK[1])
        box(v,-14,14,5,6,z0,z1,OAK[4])
    box(v,14,16,3,6,-6,6,OAK[3])
    box(v,-16,-14,3,6,-6,6,OAK[2])
    for x in range(-12,14,4):
        box(v,x,x+2,4,5,-6,6,OAK[2])
    # Mattress: a darker woven lower band and a quiet, slightly rounded linen top.
    box(v,-14,15,5,8,-7,7,LINEN[1])
    box(v,-14,15,5,6,-7,7,LINEN[0])
    box(v,-13,14,7,8,-6,6,LINEN[2])
    for x in (-14,14):
        for z in (-7,6):
            v.cells.pop((x,7,z),None)
    # Broad pillow at the head, with clipped corners and a raised central loft.
    box(v,-13,-4,8,9,-7,7,LINEN[2])
    box(v,-12,-5,9,10,-6,6,LINEN[3])
    for x in (-13,-5):
        for z in (-7,6):
            v.cells.pop((x,8,z),None)
    # Folded wool at the foot: two layered edges and restrained pale stitching.
    box(v,8,14,8,9,-7,7,BLANKET[0])
    box(v,8,14,9,10,-7,7,BLANKET[1])
    box(v,8,9,9,10,-7,7,BLANKET[2])
    for z in range(-5,6,2):
        v.cells[12,9,z] = LINEN[1]
    # A broad framed headboard with two recessed plank panels and a small iron inlay.
    box(v,-16,-14,6,15,-8,-6,OAK[2])
    box(v,-16,-14,6,15,6,8,OAK[2])
    box(v,-16,-15,7,14,-6,6,OAK[3])
    box(v,-15,-14,7,9,-6,6,OAK[2])
    box(v,-15,-14,9,14,-1,1,OAK[2])
    for z0,z1 in ((-6,-1),(1,6)):
        box(v,-16,-15,9,13,z0,z1,OAK[4])
        box(v,-16,-15,9,10,z0,z1,OAK[3])
    box(v,-16,-14,14,16,-8,8,OAK[3])
    box(v,-16,-14,15,16,-7,7,OAK[5])
    for z in (-8,7):
        for x in (-16,-15):
            v.cells.pop((x,15,z),None)
    # Tiny stepped rune, centred across the two central cells.
    for y,z in ((10,-1),(10,0),(11,-2),(11,1),(12,-1),(12,0)):
        v.cells[-15,y,z] = IRON[1]
    for z in (-7,6):
        box(v,-14,-13,4,6,z,z+1,IRON[1])
        box(v,13,14,4,6,z,z+1,IRON[1])
    return v


def validate(vox):
    assert all(-16<=x<16 and 0<=y<16 and -8<=z<8 for x,y,z in vox.cells)
    pending = {next(iter(vox.cells))}
    visited = set()
    while pending:
        p = pending.pop()
        visited.add(p)
        for delta in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            q = tuple(p[a]+delta[a] for a in range(3))
            if q in vox.cells and q not in visited:
                pending.add(q)
    assert len(visited)==len(vox.cells), 'Disconnected bed geometry'


def generate(out,install=False):
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('models','context','dwarves','renders'):
        (out/folder).mkdir(exist_ok=True)
    for name in ('storage_crate','wooden_chair'):
        shutil.copyfile(ROOT/f'assets/models/furniture/{name}.glb',out/f'context/{name}.glb')
    shutil.copyfile(ROOT/'assets/models/items/furniture/packed_furniture.glb',out/'context/packed_furniture.glb')
    for rel in ('body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed'):
        shutil.copyfile(ROOT/'assets/dwarves'/(rel+'.glb'),out/'dwarves'/(Path(rel).name+'.glb'))
    for name in ('TreeRedesignPreview.gd','TavernRedesignPreview.gd','BedPreview.gd'):
        shutil.copyfile(ROOT/'tools'/name,out/name)
    vox = dwarf_bunk()
    validate(vox)
    mesh = export_mesh(vox)
    path = out/'models/dwarf_bunk.glb'
    write_glb(path,'dwarf_bunk',mesh,export_scale=SCALE)
    if install:
        shutil.copyfile(path,ROOT/MODEL)
    (out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft dwarven bed art review"
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
[ext_resource type="Script" path="res://BedPreview.gd" id="1"]
[node name="BedPreview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n',encoding='utf-8')
    bounds = [[min(p[a] for p in mesh[0])*SCALE for a in range(3)],
              [max(p[a] for p in mesh[0])*SCALE for a in range(3)]]
    assert bounds==[[-2,0,-1],[2,2,1]]
    report = {'status':'installed' if install else 'review_export',
              'voxels_per_block':8,'export_scale':SCALE,'color_encoding':'linear COLOR_0',
              'voxels':len(vox),'triangles':len(mesh[3])//3,'bounds':bounds,
              'connected_components':1,'sha256':sha(path)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('BED_GENERATED',json.dumps(report))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'tmp/bed_preview')
    parser.add_argument('--install',action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if out==ROOT or out.is_relative_to(ROOT/'assets'):
        parser.error('Use an isolated review directory.')
    generate(out,args.install)

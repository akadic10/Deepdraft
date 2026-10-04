#!/usr/bin/env python3
"""First dwarf redesign milestone, isolated from assets/dwarves.

Run with Python 3: tools/generate_dwarf_redesign.py
Outputs modular GLBs and a standalone Godot review project under
tmp/dwarf_redesign_preview. Live registry, appearance pools and saves are untouched.

Cells are CENTRED on integer X/Z, with Y measured from the sole. The half-voxel
XZ shift is baked before the existing GLB writer's 1/8 export scale. This makes
an odd 15-cell skull symmetric at X=0 and keeps runtime scale.x=-1 mirroring
valid. All parts still assemble at identity in a common world-space frame.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
SCALE = 0.125
SKIN = (1.0, 0.97, 0.94)
SKIN_SHADE = (0.90, 0.85, 0.81)
SKIN_RECESS = (0.67, 0.58, 0.53)
TUNIC = (0.27, 0.43, 0.41)
TUNIC_DARK = (0.20, 0.33, 0.32)
LINEN = (0.74, 0.68, 0.54)
TROUSER = (0.25, 0.27, 0.27)
LEATHER = (0.39, 0.24, 0.14)
LEATHER_LIGHT = (0.48, 0.31, 0.18)
LEATHER_DARK = (0.24, 0.16, 0.11)
SOLE = (0.15, 0.13, 0.11)
IRON = (0.64, 0.65, 0.58)


def tint_value(c, value):
    return tuple(min(1.0, channel * value) for channel in c)


def box(v, x0, x1, y0, y1, z0, z1, color):
    v.box(x0, x1, y0, y1, z0, z1, color, shade=False)


def row(v, y, width, depth, cz=0, cut=1, color=SKIN):
    """Odd-width plan with deliberately cut corners; inclusive centre cells."""
    hx, hz = width // 2, depth // 2
    for x in range(-hx, hx + 1):
        for z in range(cz - hz, cz + hz + 1):
            if (hx - abs(x)) + (hz - abs(z - cz)) >= cut:
                v.cells[x, y, z] = color


def subtract(v, *others):
    blocked = set().union(*(set(o.cells) for o in others))
    for cell in blocked:
        v.cells.pop(cell, None)
    return v


def head():
    v = Voxels()
    profile = [
        (14, 7, 5, 1, 1), (15, 11, 7, 0, 2), (16, 13, 9, 0, 2),
        (17, 15, 9, 0, 2), (18, 15, 9, 0, 2), (19, 15, 9, 0, 2),
        (20, 15, 9, 0, 2), (21, 15, 9, 0, 2), (22, 15, 9, 0, 3),
        (23, 13, 9, 0, 2), (24, 9, 7, 0, 2),
    ]
    for y,w,d,cz,cut in profile:
        row(v,y,w,d,cz,cut, SKIN_SHADE if y < 16 else SKIN)
    # Small rounded ears, recessed centre, no extra crown height.
    for sign in (-1,1):
        box(v,sign*8,sign*8+1,18,21,0,2,SKIN_SHADE)
        v.cells[sign*8,19,1] = SKIN_RECESS
        # Cheek highlights sit within the form, not on protruding plates.
        for x in (sign*3,sign*4):
            v.cells[x,18,4] = SKIN
    # Eyes sit flush inside two small sockets.
    for x in (-4,-3,3,4):
        v.cells.pop((x,20,4),None)
    # Brows are inset into the forehead instead of projecting like a visor.
    for sign in (-1,1):
        for x in (2,3,4): v.cells.pop((sign*x,21,4),None)
        v.cells.pop((sign*3,22,4),None)
    box(v,0,1,20,22,5,6,SKIN_SHADE)  # narrow bridge
    box(v,-1,2,18,20,5,6,SKIN)
    box(v,-1,2,19,20,6,7,SKIN)      # broad central nose tip
    for x in (-1,1):
        v.cells[x,18,5] = tint_value(SKIN_SHADE,.88)
    for x in (-1,0,1):
        v.cells[x,16,4] = SKIN_RECESS # unobtrusive mouth, visible without a beard
    return v


def eyes():
    v = Voxels()
    for x in (-4,4): v.cells[x,20,4] = (.94,.94,.94)
    for x in (-3,3): v.cells[x,20,4] = (.18,.18,.18)
    return v


def brows():
    v = Voxels()
    for sign in (-1,1):
        for x in (2,3,4):
            v.cells[sign*x,21,4] = (.79,.79,.79)
        v.cells[sign*3,22,4] = (.90,.90,.90)
    return v


def body():
    v = Voxels()
    row(v,5,9,5,0,1,TROUSER)
    for y in (6,7): row(v,y,11,7,0,2,TROUSER)
    row(v,8,11,7,0,2,LEATHER_DARK)
    row(v,9,9,7,0,1,TUNIC_DARK)
    for y in (10,11): row(v,y,11,7,0,2,TUNIC)
    for y in (12,13): row(v,y,11,9,0,2,TUNIC)
    row(v,14,7,5,0,1,LINEN)
    # Two clear collar folds, leaving the centre neckline readable.
    for sign in (-1,1):
        for x,y,z in ((2,13,4),(3,13,3),(1,12,4)):
            v.cells[sign*x,y,z] = LINEN
    # Belt buckle, a substantial central fastening rather than metal freckles.
    box(v,-1,2,8,9,4,5,IRON)
    v.cells[0,8,4] = LEATHER_DARK
    # Small work pouch tucked against one hip, with a shaped flap.
    box(v,3,6,6,8,3,5,LEATHER)
    box(v,3,6,8,9,3,5,LEATHER_LIGHT)
    v.cells.pop((5,6,4),None)
    v.cells[4,7,4] = LEATHER_DARK
    return subtract(v,head())


def hand():
    v = Voxels()
    box(v,7,11,8,11,-1,2,SKIN)
    box(v,7,10,11,12,-1,2,SKIN)
    box(v,6,8,9,11,2,4,SKIN)  # bent thumb; forward placement keeps an air gap to torso
    for p in ((10,8,-1),(10,10,-1),(7,11,-1)):
        v.cells.pop(p,None)
    for x in (8,9): v.cells[x,8,1] = SKIN_SHADE
    v.cells[7,9,2] = SKIN_SHADE
    return v


def foot():
    v = Voxels()
    # Five wide, seven long. The welt is shaped too, so it cannot read as a ski.
    for y in (0,1,2):
        for x in range(2,7):
            for z in range(-2,5):
                if x in (2,6) and z in (-2,4): continue
                if y == 2 and z == 4: continue
                v.cells[x,y,z] = SOLE if y == 0 else LEATHER
    box(v,3,6,3,4,-1,2,LEATHER_DARK)
    box(v,3,6,2,3,2,4,LEATHER_LIGHT)
    # Broad cuff highlight; no laces too fine to read at colony zoom.
    for x in range(3,6): v.cells[x,3,1] = LEATHER_LIGHT
    return v


def hair_tones(v):
    """Coherent locks and a parting; no per-cell random/checker highlights."""
    for x,y,z in list(v.cells):
        value=.86
        if z < -3: value=.77
        if x < 0 and y >= 24: value=.98
        if x == 2 and y >= 24 and -3 <= z <= 3: value=.66
        if y < 18: value=.78 if (y//3)%2 else .91
        v.cells[x,y,z] = (value,)*3
    return v


def hair(style):
    v = Voxels()
    # Filled outer crown before subtracting the head: covers the vertical
    # step faces as well as their tops, removing the old bare scalp rings.
    profile=[(19,17,11,3),(20,17,11,3),(21,17,11,3),(22,17,11,3),
             (23,17,11,3),(24,15,11,3),(25,13,9,2),(26,7,7,2)]
    for y,w,d,cut in profile: row(v,y,w,d,0,cut,(.86,)*3)
    # The high lock sweeps to one side, rather than forming a central knob.
    top = [(x,y,z) for x,y,z in v.cells if y == 26]
    for p in top: v.cells.pop(p)
    for x,y,z in top: v.cells[x-2,y,z] = (.98,)*3
    for x,y,z in list(v.cells):
        # Expose a shaped forehead and both ears; swept forelock is off-centre.
        front_limit = {19:-2,20:0,21:1,22:3}.get(y,5)
        if z > front_limit and abs(x) < 7:
            if not (y == 22 and -4 <= x <= -1 and z <= 4):
                v.cells.pop((x,y,z),None)
        if abs(x) >= 7 and y <= 20 and z >= 0:
            v.cells.pop((x,y,z),None)
    if style == 'swept_braid':
        # Rounded gathered nape; the braid grows out of this continuous mass.
        for y,w in ((16,7),(17,9),(18,11),(19,13),(20,13)):
            row(v,y,w,3,-5,1,(.82,)*3)
        # One visible side braid. Alternating chunky sections imply weaving.
        for y in range(13,21):
            cx = 9 if ((y-13)//2)%2 else 8
            width=1 if y == 13 else 3
            for x in range(cx-width//2,cx+width//2+1):
                for z in range(1,4):
                    if width == 3 and abs(x-cx)==1 and z==3: continue
                    v.cells[x,y,z] = (.86,)*3
        # The tie is a single dark band, not tint-resistant metal geometry.
        for x,y,z in list(v.cells):
            if y==14 and x>=5: v.cells[x,y,z]=(.57,)*3
    elif style != 'cropped':
        raise ValueError(style)
    subtract(v,head(),eyes(),brows(),body())
    hair_tones(v)
    if style == 'swept_braid':
        for x,y,z in list(v.cells):
            if y==14 and x>=5: v.cells[x,y,z]=(.57,)*3
    return v


def beard():
    v = Voxels()
    # A full rounded jaw volume, not a rectangle hung in front of the chest.
    for y,w,d,cz,cut in [(13,5,3,5,1),(14,7,5,4,2),(15,9,5,4,2),
                          (16,11,5,4,2),(17,11,3,4,1),(18,11,3,4,1)]:
        row(v,y,w,d,cz,cut,(.84,)*3)
    for sign in (-1,1):
        box(v,sign*5,sign*5+1,18,20,3,5,(.78,)*3)
        v.cells[sign*5,15,4] = (.84,)*3
        for x in (1,2,3):
            v.cells[sign*x,17,5]=(.97,)*3
            if x != 3: v.cells[sign*x,17,6]=(.93,)*3
    # A shallow opening preserves the mouth under the moustache.
    for x in (-1,0,1):
        for z in (5,6): v.cells.pop((x,16,z),None)
    for x,y,z in list(v.cells):
        if y<17:
            val=.77 if abs(x) in (2,3) and z>=5 else .88
            if y==13: val=.76
            v.cells[x,y,z]=(val,)*3
    return subtract(v,head(),eyes(),brows(),body(),hair('cropped'),hair('swept_braid'))


def parts():
    return {'head_adult':head(),'body_base':body(),'hand':hand(),'foot':foot(),
            'eyes':eyes(),'brows':brows(),'hair_cropped':hair('cropped'),
            'hair_swept_braid':hair('swept_braid'),'beard_short':beard()}


def to_mesh(v):
    p,n,c,i=mesh_from_voxels(v)
    return [(x-.5,y,z-.5) for x,y,z in p],n,c,i


def assembled_cells(p, hair_name, bearded):
    out={}
    names=['head_adult','body_base','eyes','brows',hair_name]
    if bearded: names.append('beard_short')
    for name in names:
        for key in p[name].cells:
            if key in out: raise AssertionError(f'Overlap: {name} and {out[key]} at {key}')
            out[key]=name
    for name in ('hand','foot'):
        for sign in (-1,1):
            for x,y,z in p[name].cells:
                key=(sign*x,y,z)
                if key in out: raise AssertionError(f'Overlap: {name} and {out[key]} at {key}')
                out[key]=name
    return out


def components(cells):
    rest=set(cells); sizes=[]
    while rest:
        stack=[rest.pop()]; n=0
        while stack:
            x,y,z=stack.pop(); n+=1
            for dx,dy,dz in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
                q=x+dx,y+dy,z+dz
                if q in rest: rest.remove(q); stack.append(q)
        sizes.append(n)
    return sorted(sizes,reverse=True)


def validate(p):
    report={}
    for h in ('hair_cropped','hair_swept_braid'):
        for b in (False,True):
            cells=assembled_cells(p,h,b)
            height=max(y+1 for x,y,z in cells)
            assert height==27, (h,b,height)
            assert len(components(cells))==5, (h,b,'hands and feet must stay detached',components(cells))
            report[h+('_beard' if b else '_bare')]={'height_voxels':height,'height_blocks':height*SCALE,'occupied_voxels':len(cells),'assembly_components':components(cells)}
    for name,v in p.items():
        if name not in ('eyes','brows'):
            assert len(components(v.cells))==1, (name,'disconnected',components(v.cells))
    assert max(x for x,y,z in p['head_adult'].cells if y==19 and z==0)==8 # ears
    assert max(x for x,y,z in p['head_adult'].cells if y==21 and z==0)==7 # skull
    return report


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,default=ROOT/'tmp/dwarf_redesign_preview')
    args=ap.parse_args(); out=args.out.resolve()
    live=(ROOT/'assets').resolve()
    if out==live or live in out.parents: raise SystemExit('Preview output must stay outside live assets.')
    p=parts(); report=validate(p)
    (out/'models').mkdir(parents=True,exist_ok=True)
    for name,v in p.items():
        mesh=to_mesh(v); path=out/'models'/f'{name}.glb'
        write_glb(path,name,mesh,SCALE)
        report[name]={'voxels':len(v),'triangles':len(mesh[3])//3,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    refs=['body/head_adult','body/body_base','body/eyes','body/hand','body/foot',
          'hair/hair_m_short_back','hair/hair_f_loose_long',
          'beards/beard_full_long','eyebrows/brows_m_bushy','eyebrows/brows_f_thin_arched']
    (out/'reference').mkdir(exist_ok=True)
    for ref in refs:
        if (out/'reference'/f'{ref.split("/")[-1]}.glb').exists(): continue
        shutil.copyfile(ROOT/'assets/dwarves'/f'{ref}.glb',out/'reference'/f'{ref.split("/")[-1]}.glb')
    shutil.copyfile(ROOT/'tools/DwarfRedesignPreview.gd',out/'DwarfRedesignPreview.gd')
    (out/'project.godot').write_text('''config_version=5

[application]
config/name="Deepdraft dwarf art review"
run/main_scene="res://review.tscn"

[display]
window/size/viewport_width=1600
window/size/viewport_height=900
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
textures/default_filters/use_nearest_mipmap_filter=false
anti_aliasing/quality/msaa_3d=2
''')
    (out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://DwarfRedesignPreview.gd" id="1"]

[node name="DwarfRedesignReview" type="Node3D"]
script = ExtResource("1")
''')
    (out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n')
    (out/'geometry_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if 'height_voxels' in v},indent=2))
    print(f'Wrote {len(p)} prototype GLBs to {out}. Live assets unchanged.')


if __name__=='__main__': main()

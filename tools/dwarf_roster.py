"""Approved dwarf frame and the complete save-compatible appearance roster.

Coordinates are cell centres on X/Z, sole-relative on Y. The approved adult,
short beard, cropped cap and side braid come directly from the review study.
New variants preserve that frame, the carved facial slots and the 27-cell cap.
"""
from itertools import product
import json

import generate_dwarf_redesign as base
from voxel_glb import Voxels

AGES = ['young', 'adult', 'middle', 'elder']
HAIR_MALE = ['short_back', 'shaved', 'wild_loose', 'braided_back']
HAIR_FEMALE = ['bun', 'braid_side', 'braid_long', 'short_practical', 'twin_braids',
               'half_up', 'loose_long', 'shaved_sides', 'cropped', 'wild']
BEARDS = ['full_long', 'full_braided', 'short_trimmed', 'forked',
          'mutton_chops', 'goatee', 'braided_long']
BROWS_MALE = ['thick_flat', 'bushy', 'arched', 'unibrow']
BROWS_FEMALE = ['thin_arched', 'thick_flat', 'bushy', 'sharp_angled']
SCARS = ['cheek_slash', 'brow_notch', 'nose_bridge', 'chin_split']
build_body = base.body
build_hand = base.hand
build_foot = base.foot
build_eyes = base.eyes


def build_head(age):
    if age not in AGES:
        raise ValueError(age)
    v = base.head()
    # Age is carried by intentional cheek/temple creases, not changes to the
    # shared crown or socket silhouette. Hair and brows fit all four heads.
    if age == 'young':
        for x,y,z in list(v.cells):
            if y < 16:
                v.cells[x,y,z] = (.96,.92,.88)
    elif age in ('middle', 'elder'):
        tone = .88 if age == 'middle' else .76
        for sign in (-1, 1):
            for x, y, z in ((5, 19, 4), (4, 17, 4), (3, 16, 4)):
                v.cells[sign*x, y, z] = base.tint_value(base.SKIN, tone)
            if age == 'elder':
                for x, y, z in ((5, 20, 4), (2, 18, 4), (2, 17, 4), (5, 18, 4)):
                    v.cells[sign*x, y, z] = base.tint_value(base.SKIN, .84)
    return v


def build_brows(style):
    if style not in set(BROWS_MALE + BROWS_FEMALE):
        raise ValueError(style)
    v = base.brows()
    # Every style fills the same eight inset cells. Small raised tufts supply
    # variation without restoring the old shelf across the whole forehead.
    for sign in (-1, 1):
        if style == 'thick_flat':
            for x in (2, 3, 4): v.cells[sign*x, 21, 5] = (.83,)*3
        elif style == 'bushy':
            for x, y in ((2, 21), (3, 21), (4, 21), (3, 22)):
                v.cells[sign*x, y, 5] = ((.95 if y == 22 else .82),)*3
        elif style == 'sharp_angled':
            v.cells[sign*2, 21, 5] = (.83,)*3
            v.cells[sign*3, 22, 5] = (.93,)*3
        elif style == 'thin_arched':
            v.cells[sign*2, 21, 4] = (.95,)*3
            v.cells[sign*4, 21, 4] = (.95,)*3
        elif style == 'unibrow':
            for x in (2, 3): v.cells[sign*x, 21, 5] = (.85,)*3
    if style == 'unibrow':
        base.box(v, -2, 3, 22, 23, 5, 6, (.85,)*3)
    return v


def _nape(v, bottom=16):
    for y in range(bottom, 21):
        width = min(13, 7 + 2*(y-bottom))
        base.row(v, y, width, 3, -5, 1, (.82,)*3)


def _braid(v, cx, cz, bottom, top, width=3):
    for y in range(bottom, top+1):
        center = cx + (1 if ((y-bottom)//2) % 2 else 0)
        w = 1 if y == bottom else width
        hx = w//2
        for x in range(center-hx, center+hx+1):
            for z in range(cz-1, cz+2):
                if w > 1 and abs(x-center) == hx and z == cz+1: continue
                v.cells[x, y, z] = (.84,)*3


def build_hair(style):
    if style not in set(HAIR_MALE + HAIR_FEMALE):
        raise ValueError(style)
    if style == 'braid_side':
        return base.hair('swept_braid')
    v = base.hair('cropped')
    if style in ('short_back', 'cropped'):
        return v
    if style == 'shaved':
        # A close fitted shell, with no swept crest or overhanging brim.
        for x,y,z in list(v.cells):
            if y == 26: v.cells.pop((x,y,z))
    elif style == 'shaved_sides':
        # Undercut below the swept top; the bare temples expose the skull.
        for x,y,z in list(v.cells):
            if y < 23: v.cells.pop((x,y,z))
    elif style in ('wild', 'wild_loose'):
        # Three substantial staggered locks; the highest crown stays at 27.
        for x0,y0,z0 in ((-7,23,-3),(5,22,-2),(-5,21,-5)):
            base.box(v,x0,x0+3,y0,y0+2,z0,z0+3,(.87,)*3)
        _nape(v, 16 if style == 'wild' else 18)
        if style == 'wild':
            for sign in (-1,1):
                base.box(v,sign*7,sign*7+2,16,20,-4,-1,(.84,)*3)
    elif style in ('braided_back', 'braid_long'):
        _nape(v)
        _braid(v, -1, -6, 10 if style == 'braid_long' else 13, 19, 5)
    elif style == 'twin_braids':
        _nape(v,18)
        for cx in (-7,6): _braid(v,cx,-4,11,21)
    elif style == 'bun':
        _nape(v,18)
        # A low, rounded knot behind the crown rather than a tall top hat.
        for y,w,d in ((19,3,3),(20,5,5),(21,7,5),(22,7,5),(23,5,5),(24,3,3)):
            base.row(v,y,w,d,-6,1,(.85,)*3)
    elif style in ('loose_long', 'half_up'):
        _nape(v,17)
        # Scalloped locks wrap the back, with stepped ends and real thickness.
        for cx,low in ((-5,12),(-2,10),(1,11),(4,13)):
            for y in range(low,20):
                for dx in (-1,0,1):
                    for z in (-6,-5):
                        if y == low and dx != 0: continue
                        v.cells[cx+dx,y,z] = (.82,)*3
        if style == 'half_up':
            for y,w in ((19,3),(20,5),(21,5),(22,3)):
                base.row(v,y,w,3,-7,1,(.86,)*3)
    elif style == 'short_practical':
        _nape(v,18)
    base.subtract(v,base.head(),base.eyes(),base.body(),
                  *(build_brows(s) for s in set(BROWS_MALE+BROWS_FEMALE)))
    base.hair_tones(v)
    if style in ('braid_long','braided_back','twin_braids'):
        low = {'braid_long':11,'braided_back':14,'twin_braids':12}[style]
        for x,y,z in list(v.cells):
            if y == low: v.cells[x,y,z] = (.56,)*3
    return v


def build_beard(style):
    if style not in BEARDS: raise ValueError(style)
    v = base.beard()
    if style == 'short_trimmed': return v
    if style in ('full_long','full_braided'):
        # Broad jaw gathered to a rounded tip, projecting off the tunic.
        for y,w in ((8,3),(9,5),(10,7),(11,9),(12,9),(13,9),(14,9),(15,9)):
            base.row(v,y,w,3,6,1,(.87,)*3)
        if style == 'full_braided':
            for x,y,z in list(v.cells):
                if y <= 14 and z >= 6:
                    v.cells[x,y,z] = ((.71 if (x+y//2)%4 == 0 else .93),)*3
                if y == 9: v.cells[x,y,z] = (.57,)*3
    elif style in ('forked','braided_long'):
        for sign in (-1,1):
            for y in range(8 if style=='braided_long' else 10,16):
                bottom = 8 if style=='braided_long' else 10
                cx = sign*(2 if y >= 13 else 3)
                width = 1 if y == bottom else 3
                for dx in range(-width//2+1, width//2+1):
                    for z in (5,6,7):
                        if abs(dx)==1 and z==7: continue
                        v.cells[cx+dx,y,z] = ((.77 if y%4 < 2 else .94),)*3
        if style=='braided_long':
            for x,y,z in list(v.cells):
                if y == 9: v.cells[x,y,z] = (.56,)*3
    elif style == 'goatee':
        for x,y,z in list(v.cells):
            if abs(x)>2: v.cells.pop((x,y,z))
    elif style == 'mutton_chops':
        for x,y,z in list(v.cells):
            if abs(x)<3 or y<15: v.cells.pop((x,y,z))
    return base.subtract(v,base.head(),base.eyes(),base.body(),base.brows())


def build_scar(style):
    # Thin relief painted on the face. Export compresses these cubes' Z depth
    # to 0.1 voxel; a full block would look like a growth on the new face.
    paths = {
        'cheek_slash': [(-4,19,5),(-4,18,5),(-3,17,5)],
        'brow_notch': [(4,22,5),(4,23,5)],
        'nose_bridge': [(0,20,6),(0,21,6)],
        'chin_split': [(0,15,4),(0,16,5)],
    }
    if style not in paths: raise ValueError(style)
    v = Voxels()
    for p in paths[style]: v.cells[p] = (.62,.34,.29)
    return v


def part_mesh(v, scar=False):
    mesh = base.to_mesh(v)
    if scar:
        # Map each face's vertices relative to its source cell's lower Z.
        # Use separate cubes: scars are tiny, sometimes on stepped surfaces.
        p,n,c,i = [],[],[],[]
        for cell,color in v.cells.items():
            one = Voxels(); one.cells[cell] = color
            op,on,oc,oi = base.to_mesh(one)
            z0=cell[2]-.5
            offset=len(p)
            p.extend((x,y,z0+.01+(z-z0)*.10) for x,y,z in op)
            n.extend(on); c.extend(oc); i.extend(idx+offset for idx in oi)
        return p,n,c,i
    return mesh


def manifest():
    items=[('body',f'head_{a}',lambda a=a:build_head(a)) for a in AGES]
    items += [('body','eyes',build_eyes),('body','body_base',build_body),
              ('body','hand',build_hand),('body','foot',build_foot)]
    for gender,styles in [('m',HAIR_MALE),('f',HAIR_FEMALE)]:
        items += [('hair',f'hair_{gender}_{s}',lambda s=s:build_hair(s)) for s in styles]
    items += [('beards',f'beard_{s}',lambda s=s:build_beard(s)) for s in BEARDS]
    for gender,styles in [('m',BROWS_MALE),('f',BROWS_FEMALE)]:
        items += [('eyebrows',f'brows_{gender}_{s}',lambda s=s:build_brows(s)) for s in styles]
    items += [('scars',f'scar_{s}',lambda s=s:build_scar(s)) for s in SCARS]
    return items


def validate(parts):
    """Exhaust current appearance-pool combinations before writing any asset."""
    pools=json.loads((base.ROOT/'data/entities/dwarves/appearance.json').read_text())
    count=0; heights=set()
    fixed=['body/body_base','body/eyes']
    # Intentional bilateral / mouth-separated pieces are allowed. No flakes.
    multi={'body/eyes','beards/beard_mutton_chops','beards/beard_goatee'}
    for name,v in parts.items():
        if name.startswith(('eyebrows/','scars/')) or name in multi: continue
        assert len(base.components(v.cells))==1, (name,base.components(v.cells))
    for gender,prefix in [('male','m'),('female','f')]:
        hair=[s['id'] for s in pools[gender]['hair_style']]
        brows=[s['id'] for s in pools[gender]['eyebrow_style']]
        beards=[None]+[s['id'] for s in pools[gender]['beard']['styles']] if gender=='male' else [None]
        for age,h,b,br in product(AGES,hair,beards,brows):
            names=fixed+[f'body/head_{age}',f'eyebrows/brows_{prefix}_{br}']
            if h!='bald': names.append(f'hair/hair_{prefix}_{h}')
            if b: names.append(f'beards/beard_{b}')
            cells={}
            for name in names:
                for key in parts[name].cells:
                    assert key not in cells, (name,cells.get(key),key,age,h,b,br)
                    cells[key]=name
            for name in ('hand','foot'):
                for sign in (-1,1):
                    for x,y,z in parts['body/'+name].cells:
                        key=(sign*x,y,z)
                        assert key not in cells, (name,cells.get(key),key)
                        cells[key]=name
            sizes=base.components(cells)
            assert len(sizes)==5, (age,h,b,br,sizes)
            heights.add(max(y+1 for x,y,z in cells))
            count+=1
    return {'assemblies_checked':count,'height_voxels':sorted(heights),
            'overlaps':0,'components_per_assembly':5,'part_count':len(parts)}

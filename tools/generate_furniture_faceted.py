"""Faceted production furniture, including access spans and packed forms.

Gameplay definitions remain authoritative. Named door leaves and flame meshes,
wall origins, seating surfaces and bank-relative bridge coordinates are retained.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, linear, add, sub, mul, cross
from generate_dwarf_pilot import loft, box
from generate_deer_pilot import branch
from generate_furniture_pilot import timber, face, cap
from generate_wildlife_faceted import validate
from faceted_glb import write_parts
import generate_furniture_pilot as reference
from voxel_glb import write_glb
from generate_fire_faceted import flame_mesh

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/models/furniture'
PALETTES=json.loads((ROOT/'data/materials/craft_materials.json').read_text())['source_palettes']
WOOD={k:linear(v) for k,v in PALETTES['oak_log']['colors'].items()}
PROFILE=json.loads((ROOT/'data/art/furniture_catalog.json').read_text())
P={k:linear(v) for k,v in PROFILE['palette'].items()}


def transformed(mesh,offset=(0,0,0),turn=0,scale=(1,1,1)):
    m=copy.deepcopy(mesh); c,s=math.cos(turn),math.sin(turn)
    for i,(x,y,z) in enumerate(m.positions):
        x,y,z=x*scale[0],y*scale[1],z*scale[2]
        m.positions[i]=add((x*c+z*s,y,-x*s+z*c),offset)
        x,y,z=m.normals[i]; n=(x/scale[0],y/scale[1],z/scale[2]); length=math.sqrt(sum(v*v for v in n))
        x,y,z=[v/length for v in n]; m.normals[i]=(x*c+z*s,y,-x*s+z*c)
    return m


def append(target,source):
    first=len(target.positions)
    target.positions.extend(source.positions); target.normals.extend(source.normals); target.colors.extend(source.colors)
    target.indices.extend(i+first for i in source.indices)


def beam(m,a,b,width,depth,color):
    # Square-cut joinery follows a true diagonal, without voxel stair steps.
    from generate_tree_pilot import unit
    axis=unit(sub(b,a)); u=unit(cross(axis,(0,0,1) if abs(axis[2])<.8 else (1,0,0))); v=cross(axis,u)
    rings=[]
    for p in (a,b): rings.append([add(p,add(mul(u,x*width/2),mul(v,y*depth/2))) for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]])
    for i in range(4):
        j=(i+1)%4; face(m,[rings[0][i],rings[0][j],rings[1][j],rings[1][i]],sub(rings[0][i],a),color)
    face(m,rings[0],mul(axis,-1),color); face(m,rings[1],axis,color)


def tube(m,y0,y1,outer,inner,color,center=(0,0),sides=12):
    cx,cz=center
    loops=[[(cx+math.cos(i*math.tau/sides)*r,y,cz+math.sin(i*math.tau/sides)*r) for i in range(sides)] for y,r in [(y0,outer),(y1,outer),(y0,inner),(y1,inner)]]
    for i in range(sides):
        j=(i+1)%sides; radial=(math.cos((i+.5)*math.tau/sides),0,math.sin((i+.5)*math.tau/sides))
        face(m,[loops[0][i],loops[0][j],loops[1][j],loops[1][i]],radial,color)
        face(m,[loops[2][j],loops[2][i],loops[3][i],loops[3][j]],mul(radial,-1),color)
        face(m,[loops[1][i],loops[1][j],loops[3][j],loops[3][i]],(0,1,0),color)
        face(m,[loops[0][j],loops[0][i],loops[2][i],loops[2][j]],(0,-1,0),color)


def planks(m,width,depth,top,thickness,count=4):
    for i in range(count):
        z=-depth/2+depth*(i+.5)/count
        m.box((0,top-thickness/2,z),(width,thickness,depth/count-.012),WOOD['wood_light' if i%2 else 'wood'],.035)


def table(width,depth):
    m=Mesh()
    for x in (-width/2+.4,width/2-.4):
        m.box((x,.13,0),(.34,.26,depth-.25),WOOD['wood_dark'],.042)
        m.box((x,.87,0),(.32,1.50,.42),WOOD['wood'],.045)
        m.box((x,1.40,0),(.37,.25,depth-.18),WOOD['wood_dark'],.035)
        for sign in [-1,1]: beam(m,(x,.73,0),(x,1.47,sign*(depth/2-.24)),.20,.20,WOOD['wood'])
    m.box((0,.52,0),(width-.4,.20,.22),WOOD['wood_dark'],.028)
    planks(m,width,depth,1.75,.23,max(4,round(depth/.42)))
    return m


def chair(legacy=False):
    m=Mesh(); half=.5 if legacy else 1.0; seat=.75 if legacy else .875
    for x in (-half+.10,half-.10):
        for z in (-half+.10,half-.10):
            m.box((x,seat*.47,z),(.20,seat*.94,.20),WOOD['wood'],.032)
            m.box((x,.07,z),(.198,.14,.198),P['iron_dark'],.023)
        m.box((x,.42,0),(.13,.13,half*1.75),WOOD['wood_dark'],.018)
    planks(m,half*2,half*2,seat,.20,3 if legacy else 4)
    top=2.0 if legacy else 1.375
    for x in (-half+.10,half-.10):
        m.box((x,(top+seat)/2,-half+.10),(.20,top-seat,.20),WOOD['wood'],.03)
    m.box((0,top-.14,-half+.10),(half*2,.28,.20),WOOD['wood_light'],.035)
    if legacy:
        for x in (-.22,.22): m.box((x,1.36,-.40),(.13,.97,.14),WOOD['wood'],.022)
    else:
        m.box((0,1.075,-.91),(1.90,.37,.14),WOOD['wood'],.028)
        for x in (-.94,.94):
            m.box((x,1.26,-.01),(.12,.23,1.67),WOOD['wood_light'],.027)
            m.box((x,1.025,.75),(.115,.34,.12),WOOD['wood'],.025)
    return m


def bed():
    m=Mesh()
    for x in (-1.84,1.84):
        for z in (-.84,.84):
            m.box((x,.36,z),(.32,.72,.32),WOOD['wood'],.048)
            m.box((x,.065,z),(.32,.13,.32),P['iron_dark'],.025)
    for z in (-.86,.86): m.box((0,.57,z),(4,.29,.28),WOOD['wood_light'],.04)
    for x in (-1.85,1.85): m.box((x,.55,0),(.28,.27,1.65),WOOD['wood_dark'],.035)
    m.box((.02,.83,0),(3.60,.34,1.70),P['linen'],.10)
    m.box((-1.065,1.107,0),(1.09,.286,1.66),P['linen'],.095)
    m.box((1.33,1.109,0),(.74,.282,1.73),P['blanket'],.056)
    m.box((1.0,1.242,0),(.07,.014,1.52),P['linen_shadow'],.004)
    for x in (-1.90,):
        m.box((x,1.0,0),(.20,2.0,2.0),WOOD['wood'],.045)
        m.box((x,1.87,0),(.20,.20,2.0),WOOD['wood_light'],.032)
    return m


def bench():
    m=Mesh()
    for x in (-.62,.62): timber(m,(x,.30,-.49),(x,.30,.49),(.30,.18),WOOD)
    # Cut half-trunk: a broad flat seat exactly at the authored one-block height.
    m.box((0,.77,0),(1.96,.42,1),WOOD['wood'],.13)
    m.box((0,.965,0),(1.92,.07,.86),WOOD['cut'],.025)
    for x in (-.98,.98): m.box((x,.78,0),(.04,.32,.78),WOOD['heart'],.017)
    return m


def barrel():
    m=Mesh()
    loft(m,[(0,.34,.34,0,.13),(.15,.42,.42,0,.16),(.50,.47,.47,0,.19),
            (.85,.42,.42,0,.16),(1.0,.34,.34,0,.13)],WOOD['wood'])
    # Follow the actual chamfered barrel section. Circular collars intersect
    # this square-octagonal loft at its corners and disappear on the broad faces.
    def collar(y0,y1,r0,r1,c0,c1,color):
        def ring(y,r,c):
            return [(-r+c,y,-r),(r-c,y,-r),(r,y,-r+c),(r,y,r-c),
                    (r-c,y,r),(-r+c,y,r),(-r,y,r-c),(-r,y,-r+c)]
        loops=[ring(y0,r0,c0),ring(y1,r1,c1),ring(y0,r0-.05,c0),ring(y1,r1-.05,c1)]
        for i in range(8):
            j=(i+1)%8; radial=add(loops[0][i],loops[0][j]); radial=(radial[0],0,radial[2])
            face(m,[loops[0][i],loops[0][j],loops[1][j],loops[1][i]],radial,color)
            face(m,[loops[2][j],loops[2][i],loops[3][i],loops[3][j]],mul(radial,-1),color)
            face(m,[loops[1][i],loops[1][j],loops[3][j],loops[3][i]],(0,1,0),color)
            face(m,[loops[0][j],loops[0][i],loops[2][i],loops[2][j]],(0,-1,0),color)
    collar(.17,.265,.441,.454,.163,.172,P['iron_dark'])
    collar(.735,.83,.454,.441,.172,.163,P['iron_dark'])
    collar(.938,1.0,.389,.356,.145,.13,WOOD['wood_light'])
    m.box((0,.969,0),(.49,.02,.49),WOOD['wood_light'],.035)
    return m


def chest():
    m=Mesh()
    m.box((0,.43,0),(.96,.82,.94),WOOD['wood'],.075)
    for x in (-.39,.39):
        for z in (-.39,.39): m.box((x,.085,z),(.20,.17,.20),WOOD['wood_dark'],.027)
    loft(m,[(.71,.49,.49,0,.095),(.85,.49,.47,0,.09),
            (1.0,.39,.36,0,.08)],WOOD['wood_light'])
    for x in (-.30,.30):
        m.box((x,.41,.475),(.10,.65,.042),P['iron_dark'],.014)
        m.box((x,.925,0),(.095,.07,.71),P['iron_dark'],.018)
    m.box((0,.64,.484),(.14,.23,.032),P['iron'],.012)
    m.box((0,.67,.496),(.035,.055,.008),P['iron_dark'],.003)
    return m


def shelf():
    m=Mesh()
    for x in (-.43,.43):
        for z in (-.43,.43): m.box((x,1,z),(.14,2,.14),WOOD['wood'],.025)
    for y in [.10,.56,1.04,1.52,1.94]: m.box((0,y,0),(1,.12,1),WOOD['wood_light'],.028)
    m.box((0,1.04,0),(.085,1.78,.92),WOOD['wood_dark'],.014)
    for sign in [-1,1]: beam(m,(-.37,.23,.438),(sign*.37,1.88,.438),.065,.08,WOOD['wood_dark'])
    return m


def counter(stone=False):
    m=Mesh()
    body=P['stone'] if stone else WOOD['wood']
    trim=P['stone_light'] if stone else WOOD['wood_light']
    m.box((0,.14,0),(2,.28,1),P['stone_dark'] if stone else WOOD['wood_dark'],.05)
    for x in (-.84,.84): m.box((x,.98,0),(.30,1.76,.82),body,.045)
    m.box((0,1.0,.34),(1.50,1.52,.20),body,.035)
    for y in [.38,1.11]: m.box((0,y,-.08),(1.58,.14,.78),trim,.024)
    m.box((0,1.88,0),(2,.24,1),trim,.052)
    if not stone:
        for x in (-.48,0,.48): m.box((x,1.0,.448),(.055,1.35,.036),WOOD['wood_dark'],.012)
    else:
        for x in (-.52,.52): m.box((x,1.0,.45),(.09,.88,.05),P['iron'],.018)
    return m


def workbench():
    """Rough solid stump with a broad, level axe-hewn working face."""
    profile=PROFILE['crude_workbench']
    top=json.loads((ROOT/'data/furniture/crude_workbench.json').read_text())['crafting_surface_height']
    variation=profile['radial_variation']; sides=len(variation); m=Mesh(); loops=[]
    center=(.014,top,-.012)
    for height,radius in profile['trunk_profile']:
        # The broad root flare tapers into a slightly leaning trunk. The cut
        # edge drops in two places where the axe has chipped away the bark.
        loops.append([(math.cos(i*math.tau/sides)*radius*v+center[0]*height,
                       top*height-(.035 if height>.9 and i in [2,8] else 0),
                       math.sin(i*math.tau/sides)*radius*v+center[2]*height)
                      for i,v in enumerate(variation)])
    roles=['bark','bark_dark','bark','wood_dark','bark','bark',
           'wood_dark','bark','bark_dark','bark','wood_dark','bark']
    cut=[(center[0]+math.cos(i*math.tau/sides)*profile['cut_radius']*v,top,
          center[2]+math.sin(i*math.tau/sides)*profile['cut_radius']*v)
         for i,v in enumerate(variation)]
    def split_edges(loop):
        result=[]
        for i,p in enumerate(loop):
            result.append(p)
            if i in [2,8]: result.append(add(p,mul(sub(loop[(i+1)%len(loop)],p),.07)))
        return result
    # Carry the split boundaries through every ring to keep the entire mesh
    # closed, including the underside and the chipped rim.
    loops=[split_edges(loop) for loop in loops]; cut=split_edges(cut)
    roles=[color for i,role in enumerate(roles) for color in ([role,role] if i in [2,8] else [role])]
    sides=len(cut)
    for lo,hi in zip(loops,loops[1:]):
        for i in range(sides):
            j=(i+1)%sides
            face(m,[lo[i],lo[j],hi[j],hi[i]],(lo[i][0],0,lo[i][2]),WOOD[roles[i]])
    for i in range(sides):
        j=(i+1)%sides
        face(m,[loops[-1][i],loops[-1][j],cut[j],cut[i]],(cut[i][0],1,cut[i][2]),WOOD['wood' if i in [1,2,7,8] else 'bark'])
        face(m,[(0,0,0),loops[0][j],loops[0][i]],(0,-1,0),WOOD['bark_dark'])
    # End grain and short radial splits partition the same top plane. No
    # floating overlays or grooves under the worker's material contact point.
    previous=cut
    for scale,role in profile['cut_rings']:
        inside=[add(center,mul(sub(p,center),scale)) for p in cut]
        for i in range(sides):
            j=(i+1)%sides
            color=WOOD[role]
            if scale>=.595 and i in [2,9]: color=WOOD['wood_dark']
            face(m,[previous[i],previous[j],inside[j],inside[i]],(0,1,0),color)
        previous=inside
    for i in range(sides): face(m,[center,previous[i],previous[(i+1)%sides]],(0,1,0),WOOD['heart'])
    return m


def door(width):
    parts={}
    for index in range(2 if width==4 else 1):
        w=2 if width==4 else width; center=(-1 if index==0 else 1) if width==4 else 0
        m=Mesh(); m.box((0,1.81,0),(w-.01,3.62,.12),WOOD['bark_dark'],.015)
        for i in range(w*2):
            x=-w*.5+.25+i*.5; height=[3.75,3.875,3.79][(i+index)%3]
            timber(m,(x,0,0),(x,height,0),(.245,.19),WOOD)
        for sign in [-1,1]:
            for y in [.73,2.96]:
                m.box((0,y,sign*.247),(w-.05,.24,.13),WOOD['wood'],.035)
                for x in [-w/2+.27,w/2-.27]: timber(m,(x,y,sign*.27),(x,y,sign*.33),(.06,.06),WOOD)
            pull=w/2-.37
            for y in [1.50,1.89]: timber(m,(pull,y,sign*.17),(pull,y,sign*.37),(.045,.045),WOOD)
            m.box((pull,1.695,sign*.37),(.12,.51,.10),WOOD['wood_light'],.025)
        parts['leaf_left' if index==0 else 'leaf_right']=transformed(m,(center,0,0),math.pi if index else 0)
    return parts


def ladder(height):
    m=Mesh()
    for x in [-.30,.30]: timber(m,(x,0,-.21),(x,height,-.21),(.066,.14),WOOD)
    for i in range(height*2):
        y=.32+i*.5
        timber(m,(-.36,y,-.16),(.36,y,-.16),(.07,.085),WOOD)
    return m


def bridge(span):
    m=Mesh(); profile=PROFILE['log_bridge']
    variation=profile['radial_variation']; sides=len(variation)
    for index,log in enumerate(profile['logs']):
        radius=log['radius']; x=log['x']; bend=log['bend']
        # Continuous broad bark faces follow four irregular trunk sections.
        # Only the buried bank tails slope down; the crossing's crowns stay at
        # the existing walking plane, with no pale sawn-board strip on top.
        centers=[(x,-radius-profile['buried_tail_drop'],log['near_end']),
                 (x+bend,-radius,-.5),
                 (x-bend,-radius,-span-.5),
                 (x,-radius-profile['buried_tail_drop'],-span-1-log['far_end'])]
        loops=[]
        for ring,center in enumerate(centers):
            points=[]
            for i in range(sides):
                angle=i*math.tau/sides
                r=radius*variation[i]
                # Axe cuts are slightly oblique; crowns and footprint stay fixed.
                cut_skew=(.08*r*math.cos(angle+index) if ring in [0,3] else 0)
                points.append(add(center,(math.cos(angle)*r,math.sin(angle)*r,cut_skew)))
            loops.append(points)
        for ring in range(len(loops)-1):
            for i in range(sides):
                j=(i+1)%sides
                outward=(math.cos((i+.5)*math.tau/sides),math.sin((i+.5)*math.tau/sides),0)
                role=profile['bark_roles'][(i+index*2)%sides]
                face(m,[loops[ring][i],loops[ring][j],loops[ring+1][j],loops[ring+1][i]],outward,WOOD[role])
        cut_normal=(-.08*math.cos(index),.08*math.sin(index),1)
        cap(m,loops[0],centers[0],cut_normal,[WOOD['cut'],WOOD['ring'],WOOD['heart']])
        cap(m,loops[-1],centers[-1],mul(cut_normal,-1),[WOOD['cut'],WOOD['ring'],WOOD['heart']])
    r=profile['cross_support_radius']
    for z in [0,-span-1]: timber(m,(-.48,-.46,z),(1.48,-.46,z), (r,r),WOOD)
    return m


def vat():
    m=Mesh()
    # Hollow wooden vessel with a low liquid surface and a copper tap.
    for i in range(12):
        a=i*math.tau/12+.004; b=(i+1)*math.tau/12-.004
        radii=[(.78,.12),(.94,.75),(.88,1.78),(.85,2.0)]
        loops=[[(math.cos(t)*r*scale,y,math.sin(t)*r*scale-.06)
                for t,scale in [(a,1),(b,1),(b,.83),(a,.83)]] for r,y in radii]
        color=WOOD['wood' if i%2 else 'wood_light']
        normals=[(math.cos((a+b)/2),0,math.sin((a+b)/2)),(-math.sin(b),0,math.cos(b)),
                 (-math.cos((a+b)/2),0,-math.sin((a+b)/2)),(math.sin(a),0,-math.cos(a))]
        for lo,hi in zip(loops,loops[1:]):
            for j in range(4):
                k=(j+1)%4
                face(m,[lo[j],lo[k],hi[k],hi[j]],normals[j],WOOD['wood_dark'] if j==2 else color)
        face(m,loops[0],(0,-1,0),color); face(m,loops[-1],(0,1,0),color)
    for y,r in [(.35,.855),(1.50,.915)]: tube(m,y,y+.12,r,r-.10,P['iron_dark'],(0,-.06))
    m.box((0,.10,0),(1.40,.20,1.40),WOOD['wood_dark'],.09)
    loft(m,[(1.49,.69,.69,-.06,.23),(1.53,.69,.69,-.06,.23)],P['liquid'])
    branch(m,[(0,.41,.70),(0,.41,.93),(0,.24,.93)],[.06,.06,.05],P['copper'])
    m.box((0,.515,.87),(.27,.07,.08),P['iron'],.016)
    return m


def aging_rack():
    m=Mesh()
    for x in (-.84,.84):
        m.box((x,.10,0),(.22,.20,2),WOOD['wood_dark'],.035)
        for z in (-.54,.54): m.box((x,.61,z),(.22,1.08,.22),WOOD['wood'],.032)
    for z in (-.51,.51):
        m.box((0,1.04,z),(2,.18,.24),WOOD['wood_light'],.03)
        for sign in [-1,1]: beam(m,(-.69,.28,z),(sign*.68,1.02,z),.16,.17,WOOD['wood'])
    cask=barrel()
    # Rotate Y-axis casks onto their Z axes, keeping the heads visible at front.
    for x in (-.55,.55):
        copy_cask=copy.deepcopy(cask)
        for i,(px,py,pz) in enumerate(copy_cask.positions): copy_cask.positions[i]=(x+px*.88,1.57-pz*.88,(py-.5)*1.45)
        for i,(nx,ny,nz) in enumerate(copy_cask.normals):
            n=(nx/.88,-nz/.88,ny/1.45); length=math.sqrt(sum(v*v for v in n)); copy_cask.normals[i]=tuple(v/length for v in n)
        append(m,copy_cask)
    return m


def anvil():
    m=Mesh()
    m.box((.06,.14,0),(1.32,.28,1),P['stone_dark'],.07)
    m.box((.10,.44,0),(.98,.59,.78),P['stone'],.085)
    loft(m,[(.69,.51,.34,0,.075),(.82,.40,.25,0,.07),
            (1.04,.26,.19,0,.05),(1.25,.46,.30,0,.07)],P['iron'],.13)
    m.box((.27,1.375,0),(1.45,.25,.65),P['iron_light'],.055)
    # Broad tapered horn pointing -X, joined into the anvil shoulder.
    horn=Mesh()
    from generate_deer_pilot import loft as animal_loft
    animal_loft(horn,[[-1.0,.04,.038,1.29,.012],[-.74,.15,.09,1.32,.04],
                     [-.38,.23,.13,1.345,.06]],[P['iron_light']],axis='z')
    # Horn loft was along Z; turn its longitudinal axis onto X.
    append(m,transformed(horn,turn=math.pi/2))
    for x in (-.23,.53):
        for z in (-.37,.37): m.box((x,.76,z),(.13,.28,.10),P['iron_dark'],.025)
    return m


def hearth(camp=False):
    m=Mesh(); radius=.77 if camp else .76
    for i in range(8):
        angle=i*math.tau/8+.14; height=.30 if camp else .55
        m.box((math.cos(angle)*radius,height/2,math.sin(angle)*radius),
              (.42,height,.39),P['stone_light' if i%3==0 else 'stone'],.085,yaw=angle)
    for turn in [-.39,1.03]:
        log=Mesh(); timber(log,(-.59,.15,0),(.59,.15,0),(.13,.14),WOOD)
        append(m,transformed(log,(0,.06 if camp else .17,0),turn))
    m.box((0,.08,0),(.75,.16,.68),P['soot'],.06)
    return m


def brazier():
    m=Mesh()
    loft(m,[(0,.34,.34,0,.10),(.10,.38,.38,0,.12),(.21,.24,.24,0,.08)],P['iron_dark'])
    loft(m,[(.14,.12,.12,0,.04),(.65,.105,.105,0,.035),(.80,.20,.20,0,.07)],P['iron'])
    tube(m,.81,.91,.42,.28,P['iron_dark'],sides=8)
    for i in range(8):
        a=i*math.tau/8; x,z=math.cos(a),math.sin(a)
        beam(m,(x*.30,.79,z*.30),(x*.455,1.23,z*.455),.065,.075,P['iron'])
    tube(m,1.14,1.23,.49,.42,P['iron'],sides=8)
    loft(m,[(.80,.29,.29,0,.10),(.95,.34,.34,0,.11)],P['soot'])
    return m


def smelter():
    m=Mesh()
    m.box((0,.135,0),(2,.27,2),P['stone_dark'],.13)
    m.box((0,.90,-.61),(1.70,1.53,.44),P['stone'],.08)
    for x in (-.70,.70):
        m.box((x,.88,.18),(.34,1.46,1.12),P['stone'],.068)
        m.box((x,1.0,.78),(.22,1.27,.15),P['stone_light'],.04)
    m.box((0,1.62,.12),(1.72,.25,1.35),P['stone_light'],.065)
    # Rear soot panel and grate leave the existing emissive firebox unobstructed.
    m.box((0,.88,-.373),(1.03,1.12,.04),P['soot'],.012)
    for x in [-.39,-.13,.13,.39]: m.box((x,.32,.44),(.06,.12,.78),P['iron_dark'],.014)
    loft(m,[(1.71,.84,.70,0,.14),(1.85,.69,.59,-.07,.13),
            (2.10,.42,.38,-.27,.09)],P['iron'])
    for x in (-.32,.32): m.box((x,2.54,-.29),(.18,.92,.72),P['stone'],.033)
    for z in (-.58,0): m.box((0,2.54,z),(.51,.92,.15),P['stone'],.033)
    return m


def torch(wooden=False):
    m=Mesh()
    if wooden:
        timber(m,(0,0,.49),(0,.99,.49),(.11,.105),WOOD)
        timber(m,(0,.35,.01),(0,.35,.49),(.07,.085),WOOD)
        m.box((0,.77,.49),(.29,.14,.25),P['rope'],.026)
    else:
        m.box((0,.425,.057),(.40,.85,.114),P['iron'],.045)
        beam(m,(0,.21,.10),(0,.37,.52),.12,.13,P['iron_dark'])
        timber(m,(0,.24,.48),(0,.99,.48),(.11,.11),WOOD)
        for y in [.45,.83]: m.box((0,y,.50),(.42,.13,.39),P['iron_dark'],.026)
    m.box((0,.936,.50),(.18,.125,.18),P['soot'],.027)
    return m


def packed(kind):
    m=Mesh()
    if kind=='packed_furniture':
        m.box((0,.5,0),(.93,.96,.93),WOOD['wood'],.032)
        for x in (-.43,.43):
            for z in (-.43,.43): m.box((x,.50,z),(.14,1,.14),WOOD['wood_light'],.018)
        for y in (.11,.88):
            for z in (-.465,.465): m.box((0,y,z),(.89,.15,.07),WOOD['wood_dark'],.012)
        for z in (-.472,.472): beam(m,(-.39,.20,z),(.39,.79,z),.12,.051,WOOD['wood_light'])
    else:
        width=1.5 if kind=='bridge_kit' else 1.25
        for i in range(3):
            for z in (-.25,.22): timber(m,(-width/2,.083+i*.18,z),(width/2,.083+i*.18,z),(.083,.088),WOOD)
        for x in (-.35,.35): m.box((x,.48,-.015),(.08,.13,.64),P['rope'],.017)
    return m


def flag():
    m=Mesh(); m.box((-.04,.15,0),(.91,.30,.75),P['stone'],.085)
    timber(m,(-.37,.21,0),(-.37,2.94,0),(.10,.10),WOOD)
    timber(m,(-.48,2.69,0),(.49,2.69,0),(.065,.07),WOOD)
    m.box((-.37,2.946,0),(.17,.108,.17),P['flag_mark'],.038)
    # Thick, closed hanging folds; broad gold lozenge in shallow relief.
    for i in range(4):
        x=-.16+i*.18; y0=1.04+(.0,.12,.12,.0)[i]; z=(0,.06,.07,0)[i]
        m.box((x,(2.59+y0)/2,z),(.187,2.59-y0,.092),P['flag_light' if i in [1,2] else 'flag'],.02)
    for side in [-1,1]:
        z=.132 if side==1 else -.055
        for a,b in [((.10,2.30,z),(-.11,2.06,z)),((-.11,2.06,z),(.10,1.79,z)),
                    ((.10,1.79,z),(.30,2.06,z)),((.30,2.06,z),(.10,2.30,z))]:
            beam(m,a,b,.052,.023,P['flag_mark'])
    return m


def water_stone(wet=False):
    m=Mesh()
    loft(m,[(0,.41,.40,0,.12),(.18,.50,.48,0,.14),(.74,.46,.50,0,.16),
            (1.0,.35,.34,-.035,.13)],mul(P['stone'],.72) if wet else P['stone'])
    return m


def models():
    single={'wooden_table':table(2,2),'communal_table':table(8,4),
            'wooden_chair':chair(),'wooden_chair_legacy':chair(True),'dwarf_bunk':bed(),
            'bench':bench(),'barrel':barrel(),'storage_crate':chest(),'storage_shelf':shelf(),
            'tavern_bar':counter(),'trade_counter':counter(True),'crude_workbench':workbench(),
            'brewing_vat':vat(),'aging_rack':aging_rack(),'anvil':anvil(),
            'packed_furniture':packed('packed_furniture'),'bridge_kit':packed('bridge_kit'),
            'ladder_kit':packed('ladder_kit'),'settlement_flag':flag(),
            'wet_stone':water_stone(True),'dry_stone':water_stone()}
    for height in range(1,5): single['crude_ladder_'+str(height)]=ladder(height)
    for span in range(1,6): single['log_bridge_'+str(span)]=bridge(span)
    result={name:{name:m} for name,m in single.items()}
    for width in [3,4]: result['log_door_'+str(width)]=door(width)
    for name,body,flame in [('campfire',hearth(True),'campfire_flame'),('hearth',hearth(),'hearth_flame'),
                            ('brazier',brazier(),'brazier_flame'),('smelter',smelter(),'smelter_flame'),
                            ('wall_torch',torch(),'torch_flame'),('wooden_torch',torch(True),'torch_flame')]:
        result[name]={('torch_body' if 'torch' in name else name+'_body'):body,
                      flame:flame_mesh(name)}
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true')
    args=parser.parse_args(); rows={}
    with tempfile.TemporaryDirectory() as temp:
        output=Path(temp) if args.check else DEST
        for name,parts in models().items():
            for part,m in parts.items():
                validate(name+'/'+part,m)
            path=output/(name+'.glb'); write_parts(path,parts)
            if args.check: assert path.read_bytes()==(DEST/path.name).read_bytes(),name
            positions=[p for m in parts.values() for p in m.positions]
            rows[name]={'triangles':sum(len(m.indices)//3 for m in parts.values()),'meshes':list(parts),
                        'bounds':[[min(p[i] for p in positions) for i in range(3)],[max(p[i] for p in positions) for i in range(3)]],
                        'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        profile=json.loads(reference.PROFILE.read_text())
        for name,builder in [('log_chair',reference.stool),('log_bed',reference.bed),('door',reference.door)]:
            colors={k:linear(v) for k,v in PALETTES[profile['pieces'][name]['palette']]['colors'].items()}
            mesh=builder(profile,colors); reference.validate(name,mesh,profile)
            path=output/(name+'.glb'); write_glb(path,name,mesh.arrays())
            if name=='door': reference.named_leaf(path)
            if args.check: assert path.read_bytes()==(DEST/path.name).read_bytes(),name
            rows[name]={'approved_byte_identical':True,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    print(json.dumps({'checked':args.check,'parts':rows,'effects':'faceted static frames from generate_fire_faceted.py'},indent=2))


if __name__=='__main__': main()

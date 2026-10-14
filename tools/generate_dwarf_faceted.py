"""Complete faceted dwarf roster, preserving the eight approved pilot exports.

All parts share the existing world-unit frame. --check verifies deterministic
bytes, closed components, normals, colors, anchors and the 41-part inventory.
Original comparisons are preserved in the dated art reports.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import tempfile

import generate_dwarf_pilot as pilot
from generate_tree_pilot import Mesh
from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/models/characters/dwarves'
APPROVED = {
    'body/head_adult': 'head_adult', 'body/eyes': 'eyes',
    'body/body_base': 'body_base', 'body/hand': 'hand', 'body/foot': 'foot',
    'hair/hair_m_short_back': 'hair_swept', 'beards/beard_forked': 'beard_forked',
    'eyebrows/brows_m_thick_flat': 'brows',
}
grey, loft, box = pilot.grey, pilot.loft, pilot.box


def head(age, base):
    m = copy.deepcopy(base)
    # Keep the crown, eye/lid sockets and jaw attachments common to every age.
    # Age comes from the nose/cheeks and deliberately placed shallow creases.
    if age == 'young':
        for i, (x,y,z) in enumerate(m.positions):
            if z > .65 and y < 2.54:
                m.positions[i] = (x, y, .65+(z-.65)*.82)
        # Recalculate normals after the small nose adjustment.
        recalculate_normals(m)
    if age in ('middle','elder'):
        for sign in (-1,1):
            box(m,(sign*.575,2.405,.586),(.23,.025,.018),grey(.72 if age=='middle' else .64),.005,sign*-.20)
            if age == 'elder':
                box(m,(sign*.57,2.335,.586),(.20,.022,.018),grey(.77),.004,sign*-.22)
                box(m,(sign*.34,2.865,.536),(.21,.021,.019),grey(.81),.004,sign*.06)
    return m


def recalculate_normals(m):
    for i in range(0,len(m.indices),3):
        ids=m.indices[i:i+3]
        a,b,c=[m.positions[j] for j in ids]
        n=pilot.unit(pilot.cross(pilot.sub(b,a),pilot.sub(c,a)))
        for j in ids: m.normals[j]=n


def cap(m, low=2.82, top=3.27, shade=.88):
    loft(m,[(low,.90,.60,-.015,.21),(3.06,.83,.57,-.03,.21),
            (top-.055,.58,.42,-.06,.15),(top,.29,.25,-.08,.10)],grey(shade))


def nape(m, bottom=2.23, width=.82):
    loft(m,[(bottom,width*.68,.13,-.52,.065),(2.43,width,.18,-.49,.09),
            (2.91,.86,.27,-.36,.12)],grey(.78))


def braid(m,x,z,bottom,top,width=.18):
    # Joined broad interlocking masses; few bands survive the colony camera.
    count=max(3,round((top-bottom)/.21))
    for i in range(count):
        y=bottom+(top-bottom)*(i+.5)/count
        taper=.50+.50*(i+1)/count
        box(m,(x+(.035 if i%2 else -.035),y,z),
            (width*2*taper,(top-bottom)/count+.07,.25*taper),grey(.86 if i%2 else .92),.048,
            .22 if i%2 else -.22)
    box(m,(x,bottom+.06,z),(.18,.075,.24),grey(.57),.018)


def hair(style, profile):
    m=Mesh()
    if style == 'shaved':
        loft(m,[(2.83,.878,.57,0,.20),(3.015,.73,.49,0,.18),
                (3.12,.44,.33,0,.12)],grey(.70))
        return m
    cap(m,top=3.28 if style not in ('bun','half_up') else 3.23)
    if style not in ('shaved_sides',):
        nape(m,2.20 if style in ('cropped','short_practical') else 2.10)
    for side in (-1,1):
        if style=='shaved_sides': continue
        box(m,(side*.805,2.68,-.085),(.23,.52,.77),grey(.84),.065,side*.055)
    # Deliberate parting with broad swept locks, no separate strand geometry.
    sign=-1 if style in ('braid_side','half_up','short_practical') else 1
    box(m,(sign*-.23,3.01,.446),(.94,.28,.27),grey(.98),.07,sign*.16)
    box(m,(sign*.43,3.04,.407),(.38,.22,.29),grey(.83),.06,sign*-.25)
    if style in ('wild','wild_loose'):
        for x,y,z,w,h,d,r in [(-.85,2.57,-.34,.35,.50,.44,.19),
                             (.84,2.72,-.16,.34,.44,.47,-.23),
                             (-.44,3.18,-.36,.47,.25,.40,.21)]:
            box(m,(x,y,z),(w,h,d),grey(.84),.065,r)
        if style=='wild':
            for side in (-1,1):
                loft(m,[(1.92,.18,.16,-.52,.06),(2.45,.26,.24,-.46,.08),
                        (2.77,.20,.23,-.39,.07)],grey(.82),side*.65)
    if style in ('braided_back','braid_long','twin_braids','braid_side'):
        params=profile['braids'][style]
        for x,z in params['centers']:
            braid(m,x,z,params['bottom'],2.63,params['width'])
    if style in ('bun','half_up'):
        loft(m,[(2.51,.31,.20,-.585,.08),(2.77,.46,.32,-.595,.12),
                (3.04,.39,.29,-.575,.10),(3.18,.18,.17,-.525,.06)],grey(.91))
        box(m,(0,2.66,-.887),(.49,.10,.055),grey(.64),.018)
    if style in ('loose_long','half_up'):
        loft(m,[(1.49,.51,.12,-.66,.07),(1.84,.73,.18,-.64,.09),
                (2.46,.84,.21,-.53,.12),(2.81,.80,.28,-.38,.12)],grey(.83))
        if style=='loose_long':
            for sign in (-1,1):
                loft(m,[(1.76,.14,.12,-.07,.05),(2.20,.23,.18,-.05,.08),
                        (2.79,.19,.25,-.10,.07)],grey(.9),sign*.82)
    return m


def jaw(m, bottom=1.90, shade=.82):
    loft(m,[(bottom,.38,.14,.62,.08),(2.08,.60,.18,.56,.12),
            (2.30,.58,.12,.50,.10)],grey(shade))
    for sign in (-1,1):
        box(m,(sign*.64,2.305,.395),(.20,.39,.26),grey(.78),.055,sign*.12)
        box(m,(sign*.218,2.272,.686),(.39,.155,.20),grey(.95),.045,sign*-.12)


def beard(style):
    m=Mesh()
    if style=='mutton_chops':
        for sign in (-1,1):
            loft(m,[(1.96,.16,.12,.54,.05),(2.17,.25,.18,.48,.08),
                    (2.46,.12,.14,.40,.045)],grey(.87),sign*.57)
        return m
    if style=='goatee':
        for sign in (-1,1):
            box(m,(sign*.18,2.267,.690),(.31,.13,.18),grey(.94),.036,sign*-.12)
        loft(m,[(1.76,.11,.10,.64,.04),(1.99,.23,.16,.64,.065),
                (2.18,.25,.13,.54,.06)],grey(.88))
        return m
    jaw(m,1.90 if style=='short_trimmed' else 1.78)
    if style=='short_trimmed': return m
    if style=='full_long':
        loft(m,[(1.19,.20,.09,.72,.05),(1.40,.40,.16,.72,.09),
                (1.79,.56,.20,.69,.12),(2.07,.54,.16,.61,.10)],grey(.89))
    elif style=='full_braided':
        for x in (-.28,.28): braid(m,x,.72,1.29,2.03,.20)
    elif style=='braided_long':
        braid(m,0,.73,1.12,2.04,.29)
    return m


def brows(style,female=False):
    m=Mesh()
    if style=='unibrow':
        box(m,(0,2.734,.587),(1.28,.115,.095),grey(.91),.028)
        return m
    height={'thin_arched':.065,'sharp_angled':.085,'bushy':.175}.get(style,.12)
    for sign in (-1,1):
        if style in ('thin_arched','arched','sharp_angled'):
            box(m,(sign*.34,2.731,.59),(.25,height,.09),grey(.92),.022,sign*.30)
            box(m,(sign*.55,2.741,.59),(.24,height,.09),grey(.87),.022,sign*-.22)
        else:
            box(m,(sign*.44,2.72,.589),(.43,height,.10),grey(.91),.033,sign*.08)
            if style=='bushy':
                box(m,(sign*.55,2.79,.589),(.22,.11,.11),grey(.84),.027,sign*.24)
    return m


def scar(style,profile):
    m=Mesh()
    data=profile['scars'][style]
    box(m,tuple(data['center']),tuple(data['size']),pilot.linear(profile['scar_color']),
        data['bevel'],data['roll'])
    return m


def build():
    base_profile=json.loads(pilot.PROFILE.read_text())
    profile=json.loads((ROOT/'data/art/dwarf_roster.json').read_text())
    base=pilot.build(base_profile)
    pools=json.loads((ROOT/'data/entities/dwarves/appearance.json').read_text())
    parts={key:copy.deepcopy(base[source]) for key,source in APPROVED.items()}
    for age in ('young','middle','elder'):
        parts['body/head_'+age]=head(age,base['head_adult'])
    for gender,prefix in [('male','m'),('female','f')]:
        for item in pools[gender]['hair_style']:
            style=item['id']; key=f'hair/hair_{prefix}_{style}'
            if style!='bald' and key not in parts: parts[key]=hair(style,profile)
        for item in pools[gender]['eyebrow_style']:
            style=item['id']; key=f'eyebrows/brows_{prefix}_{style}'
            if key not in parts: parts[key]=brows(style,gender=='female')
    for item in pools['male']['beard']['styles']:
        key='beards/beard_'+item['id']
        if key not in parts: parts[key]=beard(item['id'])
    for style in profile['scars']: parts['scars/scar_'+style]=scar(style,profile)
    assert len(parts)==41
    return parts,base_profile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    parts,profile=build(); rows={}
    with tempfile.TemporaryDirectory() as temp:
        for key,m in parts.items():
            pilot.validate(key.rsplit('/',1)[-1],m,profile)
            dest=(Path(temp) if args.check else DEST)/(key+'.glb')
            write_glb(dest,APPROVED.get(key,dest.stem),m.arrays())
            if args.check: assert dest.read_bytes()==(DEST/(key+'.glb')).read_bytes(),key
            rows[key]={'triangles':len(m.indices)//3,'bytes':dest.stat().st_size,
                       'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
    print(json.dumps({'checked':args.check,'parts':rows,'approved_byte_identical':list(APPROVED)},indent=2))


if __name__=='__main__': main()

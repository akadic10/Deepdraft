"""One faceted adult dwarf, isolated from the 41 shipping appearance models.

World-unit shared frame; detached hands/boots retain the live animation anchors.
Run --check for deterministic bytes, outward normals, closed components and bounds.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, add, sub, mul, cross, dot, unit, linear
from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/models/characters/dwarves"
PROFILE = ROOT / "data/art/dwarf_pilot.json"


def grey(v):
    return (v, v, v)


def loft(m, rings, color, center_x=0):
    """Closed eight-sided cut-corner form; rings = y, half x/z, z offset, cut."""
    loops = []
    for y, x, z, cz, cut in rings:
        loops.append([(center_x+a, y, b+cz) for a, b in
                      [(-x+cut,-z),(x-cut,-z),(x,-z+cut),(x,z-cut),
                       (x-cut,z),(-x+cut,z),(-x,z-cut),(-x,-z+cut)]])
    for lo, hi in zip(loops, loops[1:]):
        for i in range(8):
            a,b,c,d = lo[i],lo[(i+1)%8],hi[(i+1)%8],hi[i]
            n = cross(sub(b,a),sub(c,a))
            # The clockwise ground-plane loop faces outward with reversed winding.
            n = mul(n,-1)
            tint = mul(color, (.97,1,.97,1,.99,.97,.95,.98)[i])
            m.triangle(a,b,c,n,tint)
            n2 = mul(cross(sub(c,a),sub(d,a)),-1)
            m.triangle(a,c,d,n2,tint)
    for ring, normal in [(loops[0],(0,-1,0)),(loops[-1],(0,1,0))]:
        center = tuple(sum(p[k] for p in ring)/8 for k in range(3))
        for i in range(8):
            m.triangle(center, ring[i], ring[(i+1)%8], normal, color)


def box(m, p, size, color, bevel=.025, roll=0):
    first = len(m.positions)
    m.box(p,size,color,bevel)
    if roll:
        c,s = math.cos(roll),math.sin(roll)
        for i in range(first,len(m.positions)):
            x,y,z = sub(m.positions[i],p)
            m.positions[i] = add(p,(x*c-y*s,x*s+y*c,z))
            x,y,z = m.normals[i]
            m.normals[i] = (x*c-y*s,x*s+y*c,z)


def build(profile):
    parts = {n:Mesh() for n in ['head_adult','eyes','body_base','hand','foot','hair_swept','beard_forked','brows']}
    p = {k:linear(v) for k,v in profile['palette'].items()}
    m = parts['head_adult']
    loft(m, profile['head_rings'], grey(.96))
    for side in [-1,1]:
        box(m,(side*.91,2.40,0),(.24,.34,.30),grey(.83),.08)
        box(m,(side*.977,2.41,.07),(.065,.15,.14),grey(.66),.025)
        # Small cheek planes remain within the head's silhouette.
        box(m,(side*.54,2.36,.535),(.42,.23,.095),grey(.94),.04)
    box(m,(0,2.57,.592),(.18,.29,.20),grey(.90),.045)
    box(m,(0,2.395,.663),(.37,.25,.26),grey(.98),.065)
    box(m,(0,2.185,.501),(.34,.06,.035),grey(.36),.012)
    # Keep the sleeping-lid coordinates, with eye geometry in its own tintable part.
    m = parts['eyes']
    for side in [-1,1]:
        box(m,(side*.4375,2.5625,.575),(.275,.148,.034),grey(.25),.018)
        box(m,(side*.4375,2.5625,.60),(.232,.115,.027),grey(.99),.012)
        box(m,(side*.411,2.56,.62),(.102,.103,.020),grey(.20),.009)
        box(m,(side*.429,2.585,.632),(.028,.026,.008),grey(1),.002)
    m = parts['brows']
    for side in [-1,1]:
        box(m,(side*.44,2.709,.585),(.43,.13,.10),grey(.91),.033,side*.08)
    m = parts['body_base']
    loft(m,[(.65,.47,.29,0,.11),(.76,.62,.39,0,.15),(1.04,.64,.41,0,.15)],p['trousers'])
    loft(m,[(1.05,.58,.39,0,.13),(1.48,.70,.46,0,.17),(1.68,.65,.40,0,.15),
            (1.80,.37,.29,0,.08)],p['tunic'])
    loft(m,[(1.00,.635,.42,0,.14),(1.14,.635,.42,0,.14)],p['leather_dark'])
    # Heavy front fastening and two folded collar pieces; no tiny rivet noise.
    box(m,(0,1.072,.438),(.28,.18,.075),p['iron'],.022)
    box(m,(0,1.072,.480),(.14,.080,.018),p['leather_dark'],.008)
    for side in [-1,1]:
        box(m,(side*.235,1.68,.347),(.26,.22,.13),p['linen'],.03,side*.32)
    box(m,(.48,.92,.416),(.32,.28,.18),p['leather'],.052)
    box(m,(.48,1.045,.452),(.34,.08,.15),p['leather_light'],.02)
    m = parts['hand']
    # A substantial mitten encloses the exact existing PALM anchor.
    box(m,(1.09,1.255,.155),(.42,.40,.36),grey(.96),.072)
    box(m,(.895,1.23,.31),(.17,.23,.24),grey(.88),.048,-.16)
    m = parts['foot']
    loft(m,[(0,.29,.39,.12,.075),(.105,.30,.41,.13,.085)],p['sole'],.5)
    loft(m,[(.105,.285,.39,.13,.085),(.27,.275,.38,.12,.085),(.36,.24,.28,.04,.07)],p['leather'],.5)
    loft(m,[(.27,.20,.21,0,.045),(.48,.21,.22,0,.05)],p['leather_dark'],.5)
    box(m,(.5,.426,.215),(.33,.085,.09),p['leather_light'],.02)
    m = parts['hair_swept']
    # Broad cap plus contiguous nape/temple masses, with one off-centre swept lock.
    loft(m,[(2.82,.90,.60,-.015,.21),(3.06,.83,.57,-.03,.21),
            (3.24,.63,.45,-.06,.16),(3.32,.31,.27,-.09,.11)],grey(.88),-.035)
    loft(m,[(2.21,.62,.14,-.50,.065),(2.43,.86,.17,-.48,.09),
            (2.91,.86,.27,-.36,.12)],grey(.77))
    for side in [-1,1]:
        box(m,(side*.805,2.675,-.075),(.23,.56,.79),grey(.84),.065,side*.055)
        box(m,(side*.745,2.40,.305),(.20,.28,.20),grey(.80),.04)
    box(m,(-.24,2.967,.464),(.91,.28,.27),grey(.98),.07,.15)
    box(m,(.39,3.026,.425),(.39,.23,.29),grey(.84),.065,-.25)
    m = parts['beard_forked']
    # Jaw, separated moustache and two tapered locks. Open mouth remains readable.
    loft(m,[(1.69,.38,.15,.64,.085),(1.90,.61,.19,.61,.13),
            (2.17,.65,.19,.50,.12),(2.31,.57,.12,.50,.095)],grey(.82))
    for side in [-1,1]:
        box(m,(side*.64,2.305,.395),(.20,.39,.26),grey(.77),.055,side*.12)
        box(m,(side*.218,2.272,.686),(.39,.155,.20),grey(.95),.045,side*-.12)
        loft(m,[(1.45,.10,.085,.67,.04),(1.57,.18,.135,.69,.065),
                (1.87,.255,.16,.675,.08),(2.07,.24,.13,.62,.07)],grey(.90 if side<0 else .83),side*.225)
    return parts


def validate(name,m,profile):
    edges = Counter()
    for k in range(0,len(m.indices),3):
        ids = m.indices[k:k+3]
        a,b,c = [m.positions[i] for i in ids]
        area = cross(sub(b,a),sub(c,a))
        assert dot(area,area)>1e-14, (name,'degenerate')
        assert dot(unit(area),m.normals[ids[0]])>.999, (name,'normal')
        for u,v in [(a,b),(b,c),(c,a)]:
            u,v = tuple(round(t,6) for t in u),tuple(round(t,6) for t in v)
            edges[tuple(sorted([u,v]))]+=1
    assert all(n==2 for n in edges.values()), (name,'non-manifold',Counter(edges.values()))
    assert all(math.isfinite(v) for p in m.positions for v in p)
    assert min(p[1] for p in m.positions)>=0
    assert max(p[1] for p in m.positions)<=profile['max_visual_height']
    assert all(0<=v<=1 for c in m.colors for v in c)
    if name=='foot': assert min(p[1] for p in m.positions)==0
    if name=='hand':
        assert all(min(p[i] for p in m.positions)<profile['anchors']['palm'][i]<max(p[i] for p in m.positions) for i in range(3))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    profile=json.loads(PROFILE.read_text(encoding='utf-8'))
    from generate_dwarf_faceted import APPROVED
    destinations={v:k for k,v in APPROVED.items()}
    result={}
    with tempfile.TemporaryDirectory() as temp:
        for name,m in build(profile).items():
            validate(name,m,profile)
            path=(Path(temp) if args.check else DEST)/(destinations[name]+'.glb')
            write_glb(path,name,m.arrays())
            if args.check: assert path.read_bytes()==(DEST/(destinations[name]+'.glb')).read_bytes(), f'Stale {name}'
            result[name]={'triangles':len(m.indices)//3,'bytes':path.stat().st_size,
                          'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    print(json.dumps({'parts':result,'triangles':sum(v['triangles'] for v in result.values()),'checked':args.check},indent=2))


if __name__=='__main__': main()

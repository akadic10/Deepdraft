"""Complete articulated wildlife in the approved faceted finish; world units.

Original assets stay available for comparisons. Deer files are copied exactly
from the approved pilot. Other species retain production pivots and part IDs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
from collections import Counter
import math

from generate_tree_pilot import Mesh, cross, sub, dot, unit, linear
from generate_deer_pilot import loft, branch, leaf
from voxel_glb import write_glb

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/models/animals'


def rabbit(p):
    parts={key:Mesh() for key in ['body','head','ears']}
    m=parts['body']
    loft(m,[[-.28,.13,.17,.30,.07],[-.12,.24,.235,.35,.09],
            [.19,.27,.275,.38,.10],[.35,.18,.20,.34,.07]],
         [p['cream'],p['shade'],p['fur'],p['fur'],p['fur'],p['fur'],p['shade'],p['cream']],axis='z')
    for sign in [-1,1]:
        m.box((sign*.16,.08,-.26),(.14,.16,.30),p['cream'],.048)
        m.box((sign*.19,.10,.16),(.19,.20,.35),p['fur'],.065)
    m.box((0,.35,.382),(.25,.25,.19),p['cream'],.072)
    m=parts['head']
    loft(m,[[-.44,.115,.105,.625,.04],[-.30,.22,.19,.68,.08],
            [-.05,.22,.205,.68,.08],[.04,.125,.14,.67,.05]],
         [p['cream'],p['cream'],p['fur'],p['fur'],p['fur'],p['fur'],p['fur'],p['cream']],axis='z')
    m.box((0,.656,-.458),(.105,.064,.041),p['nose'],.015)
    for sign in [-1,1]:
        m.box((sign*.220,.750,-.26),(.027,.093,.081),p['eye'],.01)
        m.box((sign*.235,.777,-.280),(.010,.022,.019),p['glint'],.003)
    for sign,top in [(-1,1.47),(1,1.37)]:
        start=(sign*.125,.83,-.13); end=(sign*.235,top,-.14)
        leaf(parts['ears'],start,end,.085,.049,p['fur'])
        leaf(parts['ears'],(sign*.151,.94,-.174),(sign*.219,top-.095,-.17),.041,.012,p['ear'])
    return parts


def wolf(p):
    parts={key:Mesh() for key in ['body','head','ears','tail','leg']}
    m=parts['body']
    loft(m,[[-.53,.24,.29,1.02,.085],[-.32,.38,.43,1.00,.12],
            [.26,.32,.34,.985,.10],[.59,.23,.25,.92,.07]],
         [p['cream'],p['cream'],p['fur'],p['fur'],p['shade'],p['fur'],p['fur'],p['light']],axis='z')
    # Shoulder ruff stays a few broad planes instead of individual fur spikes.
    loft(m,[[.79,.26,.26,-.33,.08],[1.15,.39,.30,-.35,.10],
            [1.47,.22,.21,-.38,.07]],[p['light'],p['cream'],p['fur'],p['light']])
    m=parts['head']
    loft(m,[[-.94,.12,.105,1.215,.038],[-.68,.21,.145,1.28,.057],
            [-.51,.27,.235,1.35,.075],[-.30,.18,.205,1.34,.065]],
         [p['cream'],p['cream'],p['light'],p['fur'],p['shade'],p['fur'],p['fur'],p['light']],axis='z')
    m.box((0,1.245,-.951),(.21,.10,.058),p['nose'],.023)
    for sign in [-1,1]:
        m.box((sign*.248,1.414,-.552),(.028,.072,.094),p['eye'],.012)
        m.box((sign*.265,1.42,-.569),(.01,.045,.039),p['nose'],.004)
        leaf(parts['ears'],(sign*.145,1.51,-.40),(sign*.285,1.84,-.34),.14,.09,p['shade'])
        leaf(parts['ears'],(sign*.17,1.56,-.463),(sign*.27,1.772,-.391),.067,.013,p['ear'])
    branch(parts['tail'],[(0,.99,.49),(0,.87,.69),(0,.68,.82),(0,.61,.96)],
           [.14,.175,.14,.02],p['shade'])
    m=parts['leg']
    loft(m,[[-.58,.074,.070,0,.025],[-.35,.08,.072,.006,.027],[.12,.115,.105,0,.039]],
         [p['fur'],p['light'],p['fur'],p['shade']])
    loft(m,[[-.75,.084,.045,0,.018],[-.72,.104,.105,-.012,.03],
            [-.56,.095,.091,-.01,.029]],[p['shade']])
    return parts


def duck(p,female):
    prefix='female' if female else 'male'
    coat,breast,crown,bill=[p[prefix+'_'+k] for k in ['coat','breast','crown','bill']]
    parts={key:Mesh() for key in ['body','head','wing']}
    m=parts['body']
    loft(m,[[-.37,.12,.15,.52,.055],[-.20,.28,.24,.50,.09],
            [.14,.32,.23,.49,.10],[.34,.22,.16,.50,.065],[.48,.06,.045,.58,.021]],
         [coat,coat,coat,coat,coat,coat,coat,coat],axis='z')
    # Tapered breast and tail overlap the main hull, retaining one surface.
    loft(m,[[.38,.17,.11,-.25,.045],[.57,.22,.14,-.24,.06],
            [.77,.13,.09,-.22,.035]],[breast])
    m=parts['head']
    loft(m,[[.65,.105,.09,-.22,.033],[.84,.125,.10,-.23,.04],
            [.98,.215,.155,-.23,.060],[1.105,.145,.11,-.23,.046]],[crown])
    if not female:
        loft(m,[[.69,.116,.10,-.22,.035],[.746,.113,.10,-.22,.035]],[p['ring']])
    m.box((0,.943,-.402),(.24,.067,.19),bill,.025)
    for sign in [-1,1]:
        m.box((sign*.201,1.018,-.272),(.027,.061,.058),p['eye'],.009)
        if female: m.box((sign*.190,.976,-.22),(.026,.035,.137),breast,.01)
    m=parts['wing']
    # Shoulder-local, +X span, same sign reflection and folded-wing motion.
    # Three substantial tapered feather groups maintain a clear outer edge.
    m.box((.30,.046,0),(.60,.092,.42),coat,.041)
    m.box((.64,.046,.047),(.36,.083,.31),p['dark'],.031,yaw=-.07)
    m.box((.875,.046,.12),(.23,.065,.205),p['dark'],.026,yaw=-.15)
    m.box((.345,.089,.137),(.43,.030,.13),p['speculum'],.012)
    m.box((.345,.085,.218),(.43,.028,.043),p['ring'],.011)
    return {prefix+'_'+key:value for key,value in parts.items()}


def validate(name,m):
    edges=Counter()
    for i in range(0,len(m.indices),3):
        ids=m.indices[i:i+3]; a,b,c=[m.positions[j] for j in ids]
        normal=cross(sub(b,a),sub(c,a))
        assert dot(normal,normal)>1e-14,(name,'degenerate')
        assert dot(unit(normal),m.normals[ids[0]])>.999,(name,'normal')
        for a,b in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted(tuple(round(v,7) for v in p) for p in (a,b)))]+=1
    assert all(n==2 for n in edges.values()),(name,'open component',Counter(edges.values()))
    assert all(math.isfinite(v) for p in m.positions for v in p)
    assert all(0<=v<=1 for c in m.colors for v in c)


def build():
    profiles=json.loads((ROOT/'data/art/wildlife.json').read_text())
    colors={s:{k:linear(v) for k,v in profiles[s].items()} for s in ['rabbit','wolf','duck']}
    parts={s+'/'+k:v for s,builder in [('rabbit',rabbit),('wolf',wolf)] for k,v in builder(colors[s]).items()}
    for female in [False,True]: parts.update({'duck/'+k:v for k,v in duck(colors['duck'],female).items()})
    foot=Mesh()
    foot.box((0,.126,.025),(.073,.175,.065),colors['duck']['foot'],.019)
    # Raised toe/heel facets keep the web clear as the ground-origin foot rocks.
    loft(foot,[[0,.08,.012,0,.009],[.075,.14,.105,-.01,.035],
               [.12,.095,.075,.005,.026]],[colors['duck']['foot']])
    parts['duck/foot']=foot
    return parts


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true')
    args=parser.parse_args(); parts=build(); rows={}
    with tempfile.TemporaryDirectory() as temp:
        output=Path(temp) if args.check else DEST
        for key,m in parts.items():
            validate(key,m); path=output/(key+'.glb'); write_glb(path,path.stem,m.arrays())
            if args.check: assert path.read_bytes()==(DEST/(key+'.glb')).read_bytes(),key
            rows[key]={'triangles':len(m.indices)//3,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        import generate_deer_pilot as deer
        profile=json.loads(deer.PROFILE.read_text())
        for name,mesh in deer.models(profile).items():
            deer.validate(name,mesh,profile)
            path=output/'deer'/(name+'.glb'); write_glb(path,name,mesh.arrays())
            if args.check: assert path.read_bytes()==(DEST/'deer'/path.name).read_bytes()
            rows['deer/'+name]={'approved_byte_identical':True,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    assert len(rows)==21
    print(json.dumps({'checked':args.check,'parts':rows},indent=2))


if __name__=='__main__': main()

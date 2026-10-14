"""All remaining loose goods and joint-local work tools, under art standard 63.

Offline authoring only. --check validates closed components and exact reproduction;
--update-data changes only model paths. Retained reports preserve comparison hashes.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, linear, add, sub, mul, cross, dot, unit
from generate_ground_stones import rock
from generate_furniture_pilot import face, timber
from generate_furniture_faceted import transformed, beam, tube
from generate_wildlife_faceted import validate
from voxel_glb import write_glb
from art_asset_paths import current_path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = json.loads((ROOT/'data/art/items.json').read_text(encoding='utf-8'))
P = {k:linear(v) for k,v in PROFILE['palette'].items()}
TOOL = {k:linear(v) for k,v in json.loads((ROOT/'data/materials/craft_materials.json').read_text(encoding='utf-8'))['source_palettes']['starter_tool']['colors'].items()}


def radial(m, rings, colors, sides=8, center=(0,0), phase=math.pi/8):
    """Closed regular polygon loft. Rings are height, X radius, Z radius."""
    loops = [[(center[0]+math.cos(phase+i*math.tau/sides)*rx,y,
               center[1]+math.sin(phase+i*math.tau/sides)*rz) for i in range(sides)] for y,rx,rz in rings]
    for k,(lo,hi) in enumerate(zip(loops,loops[1:])):
        for i in range(sides):
            j=(i+1)%sides
            outward=(lo[i][0]-center[0],0,lo[i][2]-center[1])
            face(m,[lo[i],lo[j],hi[j],hi[i]],outward,colors[(i+k)%len(colors)])
    for loop,normal in [(loops[0],(0,-1,0)),(loops[-1],(0,1,0))]:
        c=(center[0],loop[0][1],center[1])
        for i in range(sides): m.triangle(c,loop[i],loop[(i+1)%sides],normal,colors[0])


def seed_shape(m, at, size, color):
    x,y,z=at; w,h,d=size
    radial(m,[(y,w*.27,d*.27),(y+h*.40,w*.5,d*.5),(y+h*.77,w*.42,d*.42),
              (y+h,w*.14,d*.14)],[color],6,(x,z))


def stone(name):
    m=Mesh(); color=linear(PROFILE['stone'][name])
    if name=='rough_stone': rock(m,(.88,.78,.80),491,color,.025,(.17,-.13),1.4)
    else:
        # Dressed blocks have broad square working faces, unlike raw fractures.
        m.box((0,.34,0),(.74,.68,.68),color,.075)
    return m


def soil(name):
    m=Mesh(); c=linear(PROFILE['soil'][name])
    rock(m,(.85,.63,.82),773,c,.03,(.10,-.13),1.8)
    for x,z,r in [(-.22,.20,.22),(.20,.24,.27),(.20,-.21,.23)]:
        rock(m,(r,.20,r),int(1000+r*100),mul(c,.94),.02,(.1,.12),1.6,(x,0,z))
    return m


def ore(name):
    base=Mesh(); colors=list(map(linear,PROFILE['ore'][name])); coal=name=='coal'
    rock(base,(.87,.86,.85),672,linear('293239' if coal else '798187'),.025,(.16,-.10),1.45)
    m=Mesh()
    # Recover the broad planar fractures before placing mineral inclusions, so
    # patches follow natural faces rather than revealing triangulation diagonals.
    groups={}
    for i in range(0,len(base.indices),3):
        ids=base.indices[i:i+3]; pts=[base.positions[j] for j in ids]
        n=base.normals[ids[0]]; c=base.colors[ids[0]][:3]
        group=groups.setdefault(tuple(round(v,7) for v in (*n,dot(n,pts[0]))),[n,c,set()])
        group[2].update(pts)
    for i,(n,c,points) in enumerate(groups.values()):
        pts=list(points); center=mul(tuple(sum(p[k] for p in pts) for k in range(3)),1/len(pts))
        axis=unit(cross(n,(0,1,0) if abs(n[1])<.9 else (1,0,0))); along=cross(n,axis)
        pts.sort(key=lambda p:math.atan2(dot(sub(p,center),along),dot(sub(p,center),axis)))
        if n[1]>-.3 and i%4!=0 and len(pts)>3:
            inside=[add(center,mul(sub(p,center),[.46,.68,.55,.72,.49,.62,.56,.65][j%8])) for j,p in enumerate(pts)]
            for j in range(len(pts)):
                q=(j+1)%len(pts); m.quad(pts[j],pts[q],inside[q],inside[j],n,c)
            # The uneven inset can be concave. Its radial centre is in the
            # kernel, so a centre fan stays inside it without overlapping faces.
            for j in range(len(inside)):
                m.triangle(center,inside[j],inside[(j+1)%len(inside)],n,colors[i%2])
        else: face(m,pts,n,c)
    return m


def gem(name):
    m=Mesh(); colors=list(map(linear,PROFILE['gems'][name])); sides=8
    rings=[(0,.15),(.11,.25),(.35,.405),(.40,.405),(.625,.245)]
    loops=[[(math.cos(i*math.tau/sides)*r,y,math.sin(i*math.tau/sides)*r) for i in range(sides)] for y,r in rings]
    for k,(lo,hi) in enumerate(zip(loops,loops[1:])):
        for i in range(sides):
            j=(i+1)%sides
            face(m,[lo[i],lo[j],hi[j],hi[i]],(lo[i][0],0,lo[i][2]),colors[[0,1,2,2][k] if i%3 else [1,2,1,3][k]])
    face(m,loops[0],(0,-1,0),colors[0]); face(m,loops[-1],(0,1,0),colors[3])
    return m


def log(name):
    m=Mesh(); c=list(map(linear,PROFILE['timber'][name]))
    palette=dict(zip(['bark_dark','bark','wood','cut','ring','heart'],c)); palette['wood_dark']=c[1]
    timber(m,(0,.29,-.37),(0,.29,.37),(.29,.29),palette)
    return m


def crate_shell():
    m=Mesh()
    m.box((0,.035,0),(.75,.07,.625),P['crate_shadow'],.015)
    for y in [.14,.29]:
        for z in [-.2825,.2825]: m.box((0,y,z),(.73,.115,.06),P['crate_board'],.012)
        for x in [-.3425,.3425]: m.box((x,y,0),(.06,.115,.54),P['crate_board'],.012)
    for x in [-.3275,.3275]:
        for z in [-.265,.265]: m.box((x,.25,z),(.095,.375,.095),P['crate_edge'],.012)
    for z in [-.281,.281]: m.box((0,.409,z),(.73,.057,.063),P['crate_edge'],.009)
    for x in [-.343,.343]: m.box((x,.409,0),(.064,.057,.51),P['crate_edge'],.009)
    return m


def produce(m,kind,x,y,z,dark,light,i=0):
    if kind=='cutting':
        beam(m,(x,y,z),(x+.018,y+.23,z-.018),.020,.021,P['stem'])
        seed_shape(m,(x-.033,y+.065,z),(.125,.055,.073),dark)
        seed_shape(m,(x+.038,y+.14,z-.013),(.13,.058,.075),light)
    elif kind=='seed':
        seed_shape(m,(x,y,z),(.13,.078,.10),dark)
        seed_shape(m,(x+.026,y+.055,z-.009),(.085,.07,.067),light)
    elif kind=='cone':
        radial(m,[(y,.047,.047),(y+.06,.074,.074),(y+.11,.052,.052),
                  (y+.15,.061,.061),(y+.23,.018,.018)],[dark,light],6,(x,z))
    elif kind=='acorn':
        seed_shape(m,(x,y,z),(.125,.145,.125),light)
        radial(m,[(y+.10,.068,.068),(y+.155,.072,.072),(y+.185,.034,.034)],[dark],6,(x,z))
        beam(m,(x,y+.17,z),(x+.015,y+.22,z),.017,.018,P['stem'])
    elif kind=='strawberry':
        radial(m,[(y,.018,.018),(y+.085,.082,.067),(y+.125,.073,.060),
                  (y+.155,.028,.027)],[dark,light],6,(x,z))
        seed_shape(m,(x,y+.142,z),(.115,.038,.12),P['leaf'])
    else:
        width=.164 if kind=='fruit' else .145; h=.15 if kind=='fruit' else .115
        seed_shape(m,(x,y,z),(width,h,width),dark if i%3 else light)
        if kind=='fruit':
            beam(m,(x,y+h-.01,z),(x+.012,y+h+.045,z),.018,.018,P['stem'])
            seed_shape(m,(x+.028,y+h,z),(.080,.026,.05),P['leaf'])


def crate(name,level):
    m=crate_shell(); kind,dark,light=PROFILE['crate_contents'][name]; dark,light=linear(dark),linear(light)
    y=[.075,.205,.335][level]
    if level:
        m.box((0,(y+.07)/2,0),(.52,y-.07,.41),dark,.025)
    locations=[(-.175,-.13),(0,.12),(.175,-.12),(-.175,.12),(.175,.12),(0,-.13),(-.175,0),(.175,0),(0,0)]
    for i,(x,z) in enumerate(locations[:[3,6,9][level]]): produce(m,kind,x,y+(i%2)*.016,z,dark,light,i)
    return m


def starter(name):
    m=Mesh(); wood,grain,bark=TOOL['wood'],TOOL['grain'],TOOL['bark']; stone=linear('7C8587')
    if name=='hunting_spear':
        beam(m,(0,.12,-1.10),(0,.12,.68),.095,.095,wood)
        # Four broad knapped faces, one connected point seated in the split shaft.
        points=[(-.155,.12,.66),(0,.04,.66),(.155,.12,.66),(0,.21,.66)]
        tip=(0,.12,1.125)
        for i in range(4): face(m,[points[i],points[(i+1)%4],tip],sub(points[i],(0,.12,.66)),stone)
        face(m,points,(0,0,-1),stone)
        m.box((0,.12,.62),(.13,.14,.20),bark,.020)
        m.box((0,.204,.63),(.11,.025,.045),grain,.006)
    elif name=='carpentry_kit':
        beam(m,(-.33,.105,-.64),(-.33,.105,.55),.10,.11,wood)
        m.box((-.33,.185,.40),(.54,.37,.31),grain,.052)
        beam(m,(.30,.10,-.65),(.30,.10,.40),.10,.10,wood)
        m.box((.30,.135,.42),(.40,.27,.40),stone,.04)
        m.box((.30,.274,.37),(.11,.025,.065),bark,.006)
    elif name=='stone_hammer':
        beam(m,(0,.16,-.54),(0,.16,.34),.105,.10,wood)
        m.box((0,.25,.24),(.80,.50,.38),stone,.09)
        m.box((0,.255,.258),(.12,.30,.41),bark,.018)
        m.box((0,.426,.24),(.15,.033,.08),grain,.008)
    else:
        beam(m,(0,.12,-.86),(0,.12,.62),.10,.105,wood)
        m.box((0,.105,.61),(.78,.21,.40),stone,.060)
        m.box((0,.218,.58),(.14,.145,.19),bark,.02)
        m.box((0,.30,.59),(.18,.03,.065),grain,.006)
    # Grounded origin, including the long spear's underside.
    return transformed(m,offset=(0,-min(p[1] for p in m.positions),0))


def drink(name):
    m=Mesh(); gin='gin' in name; h=.67 if gin else .78; r=.31 if gin else .34
    radial(m,[(0,r*.79,r*.79),(.10*h,r*.9,r*.9),(.5*h,r,r),(.90*h,r*.9,r*.9),(h,r*.79,r*.79)],
           [P['crate_board'],P['crate_shadow'],P['crate_board']],10,phase=0)
    # Hoops match the polygon body and taper along the same barrel profile.
    for y in [.16,.76]: tube(m,y*h,(y+.095)*h,r*.99,r*.82,P['iron_dark'],sides=10)
    radial(m,[(h-.018,r*.72,r*.72),(h+.012,r*.72,r*.72)],[P['crate_edge']],10,phase=0)
    mark=linear(PROFILE['drink_marks'][name])
    m.box((0,h*.50,r*.967),(.26,.24,.036),mark,.025)
    # Simple burned/wax mark: crop family and premium age read without text.
    if 'wine' in name:
        for x,y in [(-.052,.045),(.055,.045),(0,-.045)]:
            m.box((x,h*.50+y,r*.992),(.065,.065,.025),P['linen'],.017)
    elif gin:
        m.box((0,h*.50,r*.992),(.045,.15,.025),P['linen'],.009)
    else:
        m.box((0,h*.50,r*.992),(.115,.045,.025),P['linen'],.009)
    if any(prefix in name for prefix in ['aged_','vintage_','reserve_']):
        m.box((0,h*.50-.066,r*1.001),(.18,.025,.024),P['gold'],.005)
        tube(m,.89*h,.925*h,r*.875,r*.76,P['gold_dark'],sides=10)
    return m


def misc(name):
    m=Mesh()
    if name=='cloth_bolt':
        m.box((0,.15,0),(.68,.30,.48),P['linen'],.067)
        m.box((.015,.294,0),(.63,.055,.43),P['linen_shadow'],.016)
        m.box((.025,.332,0),(.59,.055,.40),P['linen'],.022)
        for x in [-.24,.24]: m.box((x,.36,0),(.045,.035,.38),P['crate_shadow'],.006)
    elif name=='water_bucket':
        radial(m,[(0,.22,.22),(.46,.285,.285)],[P['crate_board'],P['crate_shadow']],10)
        # Top water is a separate closed inset, with a raised open rim around it.
        radial(m,[(.462,.254,.254),(.465,.254,.254)],[P['water']],10)
        tube(m,.43,.49,.296,.254,P['crate_edge'],sides=10)
        tube(m,.05,.09,.24,.205,P['iron_dark'],sides=10)
        for x in [-.275,.275]: beam(m,(x,.36,0),(x,.71,0),.045,.045,P['iron_dark'])
        beam(m,(-.275,.71,0),(.275,.71,0),.065,.060,P['crate_edge'])
    elif name=='honey_jar':
        radial(m,[(0,.21,.21),(.06,.27,.27),(.37,.28,.28),(.48,.18,.18),(.53,.18,.18)],[P['clay']],10)
        radial(m,[(.505,.20,.20),(.555,.21,.21),(.58,.15,.15)],[P['honey']],10)
        m.box((0,.28,.273),(.20,.18,.031),P['linen'],.025)
        m.box((0,.28,.297),(.083,.08,.019),P['honey'],.020)
    elif name=='fossil_fragment':
        rock(m,(.72,.18,.62),992,linear('8D8B7F'),.025,(.04,-.05),1.3)
        # A broad embedded shell, laid against the rock, with three readable ribs.
        for i,(x,z,r) in enumerate([(-.14,-.05,.095),(0,0,.13),(.17,.08,.10)]):
            seed_shape(m,(x,.125,z),(r*2,.10,r*1.5),P['linen'])
    return m


def flora(name):
    m=Mesh()
    if name=='plump_helmet':
        radial(m,[(0,.14,.14),(.26,.18,.18)],[linear('B7AD8F')],8)
        radial(m,[(.20,.24,.23),(.28,.36,.34),(.43,.29,.28),(.51,.10,.10)],[linear('96778E'),linear('7F657E')],8)
    elif name=='pig_tail':
        for i in range(3):
            z=(i-1)*.105
            beam(m,(-.29,.05,z),(.22,.10,z),.04,.05,P['stem'])
            seed_shape(m,(.04,.04,z),(.29,.27,.19),linear('B6A3AA'))
        m.box((-.11,.084,0),(.075,.15,.35),P['crate_shadow'],.017)
    elif name=='hops':
        for x,y,z in [(-.13,0,-.10),(.14,0,-.08),(0,0,.14),(0,.14,0)]:
            seed_shape(m,(x,y,z),(.24,.30,.24),linear('8E9E58'))
        beam(m,(0,.28,0),(.20,.39,-.06),.033,.03,P['stem'])
    else:
        for x,y,z in [(-.13,.08,-.10),(.13,.08,-.10),(0,0,.12),(0,.25,0)]:
            seed_shape(m,(x,y,z),(.27,.25,.26),linear('74587C'))
        beam(m,(0,.43,0),(.10,.54,-.025),.033,.031,P['stem'])
    return transformed(m,offset=(0,-min(p[1] for p in m.positions),0))


def work_tool(name):
    m=Mesh(); axe=name=='felling_axe'; end=1.26 if axe else 1.75
    radial(m,[(-.25,.065,.063),(.0,.072,.067),(.70,.064,.061),(end,.083,.072)],
           [P['tool_wood']],8,phase=0)
    for y in [-.19,-.10,.55,.64]: tube(m,y,y+.061,.084,.064,P['leather'],sides=8)
    if axe:
        m.box((0,1.0625,-.105),(.27,.35,.37),P['iron_dark'],.045)
        # A flared forged blade, continuously tapered to the fixed cutting plane.
        sections=[(.015,.82,1.29,.16),(.25,.84,1.31,.13),(.58,.76,1.36,.05),(.6875,.75,1.375,.009)]
        loops=[[( -w,lo,z),(w,lo,z),(w,hi,z),(-w,hi,z)] for z,lo,hi,w in sections]
        for k,(lo,hi) in enumerate(zip(loops,loops[1:])):
            for i in range(4):
                j=(i+1)%4; pts=[lo[i],lo[j],hi[j],hi[i]]
                outward=[(0,-1,0),(1,0,0),(0,1,0),(-1,0,0)][i]
                face(m,pts,outward,P['steel_edge' if k==2 else 'iron'])
        face(m,loops[0],(0,0,-1),P['iron_dark'])
        contact=(0,1.0625,.6875)
        for i in range(4): m.triangle(contact,loops[-1][i],loops[-1][(i+1)%4],(0,0,1),P['steel_edge'])
    else:
        m.box((0,1.68,0),(.29,.29,.29),P['iron_dark'],.045)
        # Curved forged pick: rings narrow to the exact existing impact anchor.
        specs=[(-.88,1.49,.065,.045),(-.55,1.66,.12,.09),(0,1.73,.17,.14),(.38,1.67,.12,.115),(.70,1.51,.065,.075)]
        loops=[[(0,y-h,z),(w,y,z),(0,y+h,z),(-w,y,z)] for z,y,w,h in specs]
        for k,(lo,hi) in enumerate(zip(loops,loops[1:])):
            for i in range(4):
                j=(i+1)%4
                face(m,[lo[i],lo[j],hi[j],hi[i]],[(1,-1,0),(1,1,0),(-1,1,0),(-1,-1,0)][i],P['iron'])
        face(m,loops[0],(0,0,-1),P['steel_edge'])
        tip=(0,1.375,.9375)
        for i in range(4):
            face(m,[loops[-1][i],loops[-1][(i+1)%4],tip],[(1,-1,0),(1,1,0),(-1,1,0),(-1,-1,0)][i],P['steel_edge'])
    return m


def build():
    models={}
    def put(category,name,m): models[f'assets/models/items/{category}/{name}.glb']=m
    for n in PROFILE['stone']: put('stone',n,stone(n))
    for n in PROFILE['soil']: put('soil',n,soil(n))
    for n in PROFILE['ore']: put('ore',n,ore(n))
    for n in PROFILE['gems']: put('gem',n,gem(n))
    for n in PROFILE['timber']: put('wood',n,log(n))
    m=Mesh(); m.box((0,.065,0),(.22,.13,.85),P['crate_board'],.024); put('wood','oak_stave',m)
    for n in PROFILE['crate_contents']:
        for i,stage in enumerate(['low','half','full']): put('crates',n+'_'+stage,crate(n,i))
    for n in ['stone_hoe','stone_hammer','hunting_spear','carpentry_kit']: put('tools',n,starter(n))
    for n in PROFILE['drink_marks']: put('drink',n,drink(n))
    for n in ['cloth_bolt','water_bucket','honey_jar','fossil_fragment']: put('misc',n,misc(n))
    for n in ['plump_helmet','pig_tail','hops','grape']: put('flora',n,flora(n))
    m=Mesh(); radial(m,[(0,.22,.22),(.055,.22,.22)],[P['gold']],12)
    tube(m,.051,.070,.204,.178,P['gold_dark'],sides=12)
    m.box((0,.067,0),(.065,.024,.245),P['gold_dark'],.009)
    m.box((0,.067,-.035),(.19,.025,.064),P['gold_dark'],.009)
    put('currency','gold_coin',m)
    for n in ['felling_axe','mining_pickaxe']: models[f'assets/models/characters/dwarves/tools/{n}.glb']=work_tool(n)
    return models


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true'); parser.add_argument('--update-data',action='store_true')
    args=parser.parse_args(); models=build(); rows=[]
    assert len(models)==94
    with tempfile.TemporaryDirectory(prefix='deepdraft_items_') as tmp:
        for name,m in models.items():
            validate(name,m)
            if '/items/' in name:
                assert abs(min(p[1] for p in m.positions))<1e-7,(name,'ground')
                if '/tools/' not in name:
                    assert max(math.hypot(p[0],p[2]) for p in m.positions)<=.64,(name,'footprint')
                if '/crates/' in name or '/wood/' in name:
                    assert max(math.hypot(p[0],p[2]) for p in m.positions)<=.5,(name,'yaw footprint')
            path=Path(tmp)/name if args.check else ROOT/name
            write_glb(path,Path(name).stem,m.arrays())
            if args.check: assert path.read_bytes()==(ROOT/name).read_bytes(),(name,'reproduction')
            rows.append({'path':name,'triangles':len(m.indices)//3,'bytes':path.stat().st_size,
                         'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                         'min':[min(p[k] for p in m.positions) for k in range(3)],
                         'max':[max(p[k] for p in m.positions) for k in range(3)]})
    definition_file=ROOT/'data/entities/items/resources.json'
    if args.update_data:
        assert not args.check
        raw=definition_file.read_text(encoding='utf-8')
        # Compatibility with definitions written before the folder migrations.
        raw=current_path(raw)
        definition_file.write_text(raw,encoding='utf-8')
        registry=ROOT/'scripts/registries/DwarfAssets.gd'
        raw=current_path(registry.read_text(encoding='utf-8'))
        registry.write_text(raw,encoding='utf-8')
    data=json.loads(definition_file.read_text(encoding='utf-8'))
    if args.check or args.update_data:
        paths={p for v in data.values() if isinstance(v,dict) for p in [v.get('model',''),*v.get('crate_models',[])] if '/items/' in p}
        # Packed kits and water stones are owned by the furniture family.
        assert paths=={'res://'+n for n in models if '/items/' in n},(len(paths),'references')
    out=ROOT/'tmp/item_art_20261013'; out.mkdir(parents=True,exist_ok=True)
    (out/'assets.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    print(f"ITEMS_FACETED_{'CHECK' if args.check else 'BUILD'}_PASS {len(rows)} models; {sum(r['triangles'] for r in rows)} triangles")


if __name__=='__main__': main()

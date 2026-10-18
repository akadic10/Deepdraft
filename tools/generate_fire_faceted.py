"""Faceted static flames and animation libraries for all installed fire sources.

Run normally to build eleven exports; --check reproduces them in a temporary
directory and validates closed geometry, rooted frames and existing envelopes.
Furniture bodies and gameplay definitions remain owned by their existing sources.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, linear, add, sub, mul
from generate_furniture_pilot import face
from generate_wildlife_faceted import validate
from faceted_glb import write_parts

ROOT=Path(__file__).resolve().parents[1]
PROFILE=json.loads((ROOT/'data/art/fire_effects.json').read_text(encoding='utf-8'))
PALETTE={k:linear(v) for k,v in PROFILE['palette'].items()}
FURNITURE=['campfire','hearth','brazier','smelter','wall_torch','wooden_torch']


def flame_mesh(name,phase=0.0):
    profile=PROFILE['families']['wall_torch' if name=='wooden_torch' else name]
    anchor=profile['anchor']; width,height,depth=profile['size']; mesh=Mesh()
    sides=7
    for tongue in PROFILE['tongues']:
        first_vertex=len(mesh.positions)
        offset_x,offset_z=tongue['offset']; beat=phase+tongue['phase']
        reach=tongue['height']*(1+.055*math.sin(beat))
        rings=[]
        for level,radius in [(0,.68),(.17,1),(.43,.79),(.70,.45),(.90,.17)]:
            sway=level*level
            # Low vertices are identical in every frame. Curvature and a
            # small periodic height change move only the rising upper tongue.
            cx=offset_x+sway*(.21*math.sin(beat)+.14*math.sin(beat+level*2.8))
            cz=offset_z+sway*.10*math.cos(beat+level*2)
            rings.append([(anchor[0]+width*(cx+math.cos(i*math.tau/sides+.12)*tongue['width']*radius),
                           anchor[1]+height*reach*level,
                           anchor[2]+depth*(cz+math.sin(i*math.tau/sides+.12)*tongue['width']*radius))
                          for i in range(sides)])
        colors=['core','hot','gold','orange'] if tongue['core'] else ['hot','gold','orange','ember']
        for level,(lo,hi) in enumerate(zip(rings,rings[1:])):
            for i in range(sides):
                j=(i+1)%sides
                outward=(math.cos((i+.5)*math.tau/sides+.12),0,math.sin((i+.5)*math.tau/sides+.12))
                face(mesh,[lo[i],lo[j],hi[j],hi[i]],outward,PALETTE[colors[level]])
        base=(anchor[0]+width*offset_x,anchor[1],anchor[2]+depth*offset_z)
        tip=(anchor[0]+width*(offset_x+.21*math.sin(beat)+.14*math.sin(beat+2.8)),
             anchor[1]+height*reach,
             anchor[2]+depth*(offset_z+.10*math.cos(phase+tongue['phase']+2)))
        for i in range(sides):
            j=(i+1)%sides
            face(mesh,[base,rings[0][j],rings[0][i]],(0,-1,0),PALETTE['hot'])
            outward=sub(add(rings[-1][i],rings[-1][j]),mul(tip,2))
            outward=(outward[0],height*.4,outward[2])
            face(mesh,[rings[-1][i],rings[-1][j],tip],outward,PALETTE['gold' if tongue['core'] else 'orange'])
        # Smooth heat colors across the flat-shaded planes, avoiding stacked
        # horizontal color bands that make a tongue read as a solid cone.
        stops=[(0,'core'),(.42,'hot'),(1,'gold')] if tongue['core'] else [(0,'hot'),(.38,'gold'),(.82,'orange'),(1,'ember')]
        for i in range(first_vertex,len(mesh.positions)):
            level=(mesh.positions[i][1]-anchor[1])/(height*reach)
            for (low,a),(high,b) in zip(stops,stops[1:]):
                if level<=high+1e-6:
                    t=max(0,min(1,(level-low)/(high-low)))
                    mesh.colors[i]=tuple(x*(1-t)+y*t for x,y in zip(PALETTE[a],PALETTE[b]))+(1.,)
                    break
    if name=='hearth':
        # Low glowing coals share the flame's emissive material and remain
        # fixed through every frame, immediately above the charred log bed.
        for x,z in [(-.30,.19),(-.05,.29),(.23,.22),(-.20,-.10),(.14,-.07)]:
            mesh.box((x,anchor[1]+.025,z),(.18,.05,.14),PALETTE['ember'],.018)
    return mesh


def validate_frame(name,mesh):
    validate(name,mesh)
    profile=PROFILE['families']['wall_torch' if name=='wooden_torch' else name]
    lo,hi=profile['bounds']
    assert all(lo[i]-1e-6<=p[i]<=hi[i]+1e-6 for p in mesh.positions for i in range(3)),(name,'flame envelope')
    assert abs(min(p[1] for p in mesh.positions)-profile['anchor'][1])<1e-6,(name,'root')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    # Import lazily: the furniture builder calls flame_mesh for its static
    # first frames, while this command also rebuilds those six named exports.
    from generate_furniture_faceted import models
    furniture=models(); exports={}; frames=0
    for name in FURNITURE:
        definition=json.loads((ROOT/f'data/furniture/{name}.json').read_text(encoding='utf-8'))
        light=definition['light_source']; config=light['flame_animation']
        path=config['model'].removeprefix('res://')
        if path not in exports:
            count=len(config['frames']); clip={}; roots=[]
            for i,frame in enumerate(config['frames']):
                mesh=flame_mesh(name,i*math.tau/count); validate_frame(name,mesh)
                clip[frame]=mesh
                roots.append(sorted(set(p for p in mesh.positions if abs(p[1]-PROFILE['families'][name]['anchor'][1])<1e-6)))
            assert all(root==roots[0] for root in roots),'moving fire root'
            assert len({tuple(m.positions) for m in clip.values()})==count,'duplicate frame'
            exports[path]=clip; frames+=count
        static=furniture[name]
        validate_frame(name,static[light['emissive_mesh']])
        assert static[light['emissive_mesh']].arrays()==exports[path][config['frames'][0]].arrays(),name+' static/frame mismatch'
        exports[definition['model'].removeprefix('res://')]=static
    rows={}
    with tempfile.TemporaryDirectory(prefix='deepdraft_fire_') as temp:
        for path,parts in exports.items():
            dest=(Path(temp) if args.check else ROOT)/path
            write_parts(dest,parts)
            if args.check: assert dest.read_bytes()==(ROOT/path).read_bytes(),(path,'reproduction')
            rows[path]={'triangles':sum(len(m.indices)//3 for m in parts.values()),'meshes':len(parts),
                        'bytes':dest.stat().st_size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
    print(json.dumps({'checked':args.check,'static_furniture':6,'animation_libraries':5,'frames':frames,'exports':rows},indent=2))


if __name__=='__main__': main()

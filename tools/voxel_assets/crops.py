"""Art for the fourteen existing crop references; no farming gameplay is added."""
import math
from common import Voxels,Part,box,ellipsoid,linear,read_json
from plants import branch,leaf


def crop(profile,species,stage,season):
    p=profile[species]; colors={k:linear(v) for k,v in p['palette'].items()}
    vox=Voxels(); height=p['heights'][stage]
    if species=='plump_helmet':
        for i,(x,z) in enumerate(p['clump']):
            h=height*(1-i*.18)
            radius=h*.32
            box(vox,(x,h*.35,z),(.1875,h*.70,.1875),colors['stem'])
            ellipsoid(vox,(x,h*.77,z),(radius,h*.23,radius),colors['cap'],power=3)
            box(vox,(x+radius*.25,h*.94,z-radius*.25),(.125,.0625,.125),colors['speck'])
    elif species=='pig_tail_plant':
        for i,(x,z) in enumerate(p['clump']):
            tip=(x,height*(1-.12*i),z)
            branch(vox,(x,0,z),tip,.05,.05,colors['autumn' if season=='autumn' else 'stem'])
            for j in range(3):
                at=(x,height*(.25+.17*j),z)
                angle=i*2.1+j*2.4
                leaf(vox,at,(x+math.cos(angle)*.30,at[1]+.12,z+math.sin(angle)*.30),.16,colors['autumn' if season=='autumn' else 'leaf'])
            if stage=='mature':
                last=tip
                for j in range(1,7):
                    angle=j*math.pi/4
                    current=(x+.14*math.sin(angle),tip[1]+.14*(1-math.cos(angle)),z)
                    branch(vox,last,current,.06,.05,colors['fiber']); last=current
    else:
        mature=stage not in ('seedling','cutting')
        # A single authored support is part of the existing crop visual only.
        box(vox,(0,height/2,0),(.125,height,.125),colors['wood'])
        last=(0,0,0)
        turns=10 if mature else 3
        for i in range(turns):
            y=height*(i+1)/(turns+1)
            angle=i*1.8
            at=(math.cos(angle)*.14,y,math.sin(angle)*.14)
            branch(vox,last,at,.05,.05,colors['stem']); last=at
            if season=='winter': continue
            end=(at[0]+math.cos(angle)*.32,y+.10,at[2]+math.sin(angle)*.32)
            leaf(vox,at,end,.25,colors['autumn' if season=='autumn' else 'leaf'])
            if mature and i>=2 and i%2==0 and (species=='hops_plant' and stage=='mature' or species=='grape_vine' and season in ('summer','autumn')):
                for j in range(3):
                    spot=(end[0],end[1]-.10-j*.10,end[2]+.0625*(j%2))
                    ellipsoid(vox,spot,(.10,.13,.10),colors['fruit'],power=3)
            if mature and species=='grape_vine' and season=='spring' and i%2:
                box(vox,(end[0],end[1]+.04,end[2]),(.125,.0625,.125),colors['bud'])
    vox.cells={p:c for p,c in vox.cells.items() if p[1]>=0}
    return vox


def assets(only=None):
    profile=read_json('tools/art_data/voxel_crops.json')
    for species in ('grape_vine','hops_plant','pig_tail_plant','plump_helmet'):
        data=read_json(f'data/entities/flora/{species}.json')
        definition=next(v for k,v in data.items() if k.startswith('base:flora:'))
        for stage,settings in definition['stages'].items():
            for season,path in settings['models'].items():
                if only and only not in path: continue
                vox=crop(profile,species,stage,season)
                assert max(p[1]+1 for p in vox.cells)<=settings['clearance_height']*16,path+' clearance'
                assert min(p[1] for p in vox.cells)==0,path+' grounding'
                yield path.removeprefix('res://'),{'main':Part(vox)},dict(species=species,stage=stage,season=season,integration='art_and_data_only')

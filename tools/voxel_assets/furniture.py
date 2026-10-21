"""Named rigid furniture solids, shared flame frames and greedy shadow proxies."""
import math
from common import ROOT,Voxels,Part,linear,read_json
from solid_shapes import apply
from micro_voxel_study.generate import solid
import log_chair
import workbench
import log_table
import hand_hewn_timber
import log_bench
import hearthblock


def flame(name,phase=0):
    data=read_json('data/art/voxel_fire_effects.json')
    profile=data['families'][name]
    anchor=profile['anchor']; width,height,depth=profile['size']
    palette={k:linear(v) for k,v in data['palette'].items()}
    vox=Voxels(); base=round(anchor[1]*16)
    for tongue in data['tongues']:
        beat=phase+tongue['phase']; reach=tongue['height']*(1+.08*math.sin(beat))
        rows=max(2,round(height*reach*16))
        for row in range(rows):
            level=row/max(1,rows-1)
            sway=level*level
            cx=anchor[0]+width*(tongue['offset'][0]+sway*(.27*math.sin(beat)+.18*math.sin(beat+level*2.8)))
            cz=anchor[2]+depth*(tongue['offset'][1]+sway*.17*math.cos(beat+level*2))
            # Broad connected base, tapered cubic tongues; no alpha sheets.
            radius=(.68+level*1.8) if level<.18 else (1-level)**.72
            rx=max(.6,width*16*tongue['width']*radius)
            rz=max(.6,depth*16*tongue['width']*radius)
            colors=['core','hot','gold'] if tongue['core'] else ['hot','gold','orange','ember']
            color=palette[colors[min(len(colors)-1,int(level*len(colors)))]]
            # Snap centres so even a single-cell tip remains connected.
            ix,iz=round(cx*16-.5),round(cz*16-.5)
            for x in range(math.floor(ix-rx),math.ceil(ix+rx)+1):
                for z in range(math.floor(iz-rz),math.ceil(iz+rz)+1):
                    if abs((x-ix)/rx)**3+abs((z-iz)/rz)**3<=1:
                        vox.cells[x,base+row,z]=color
    lo,hi=profile['bounds']
    vox.cells={p:c for p,c in vox.cells.items() if all(round(lo[i]*16)<=p[i]<round(hi[i]*16) for i in range(3))}
    return vox


def assets(only=None):
    profile=read_json('data/art/voxel_furniture.json')
    palette={key:linear(value) for key,value in profile['palette'].items()}
    flames={}
    for name,piece in profile['pieces'].items():
        path='assets/models/furniture/'+name+'.glb'
        if only and only not in path: continue
        parts={}
        for key,shapes in piece.items():
            vox=Voxels(); occlusion=None
            for shape in shapes:
                if shape['op']=='hearthblock_vox':
                    vox.cells.update(hearthblock.model(shape['model']).cells)
                    occlusion=hearthblock.occlusion(shape['model'])
                elif shape['op']=='log_bench_vox':
                    vox.cells.update(log_bench.model().cells)
                elif shape['op']=='hand_hewn_vox':
                    vox.cells.update(hand_hewn_timber.model(shape['kind']).cells)
                elif shape['op']=='log_chair_vox':
                    vox.cells.update(log_chair.model().cells)
                elif shape['op']=='workbench_vox':
                    vox.cells.update(workbench.model(worn=shape.get('worn',True)).cells)
                elif shape['op']=='log_table_vox':
                    vox.cells.update(log_table.model().cells)
                elif shape['op']=='pilot':
                    for p in shape['shapes']: solid(vox,p,palette)
                else: apply(vox,shape,palette)
            parts[key]=Part(vox,occlusion=occlusion)
        definition_path=ROOT/('data/furniture/'+name+'.json')
        if definition_path.is_file():
            definition=read_json(str(definition_path))
            if 'light_source' in definition:
                light=definition['light_source']
                parts[light['emissive_mesh']]=Part(flame(name),shadow=False)
        metadata=dict(piece=name)
        if any(shape['op']=='hearthblock_vox' for shapes in piece.values() for shape in shapes):
            metadata['source']='data/art/voxel_hearthblock.json'
            metadata['direction']='docs/00_dev_roadmap/256_hearthblock_art_pilot.md'
        elif name in ['log_chair','log_table','board_game_table','crude_workbench']:
            metadata['source']='data/art/voxel_hand_hewn_timber.json'
            metadata['direction']='docs/60_asset_creation/64_hand_hewn_art_direction.md'
        elif name=='bench':
            metadata['source']='data/art/voxel_log_bench.json'
            metadata['direction']='docs/60_asset_creation/64_hand_hewn_art_direction.md'
        yield path,parts,metadata
    for name in ['campfire','hearth','wooden_torch']:
        definition=read_json('data/furniture/'+name+'.json')['light_source']['flame_animation']
        path=definition['model'].removeprefix('res://')
        if only and only not in path: continue
        count=len(definition['frames'])
        yield path,{frame:Part(flame(name,i*math.tau/count),shadow=False) for i,frame in enumerate(definition['frames'])},dict(effect=name,frames=count,casting=False)

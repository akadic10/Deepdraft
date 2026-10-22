"""Native voxel wildlife parts in their existing rigid-part authoring frames."""
from common import Voxels,Part,linear,read_json
from solid_shapes import solid
import hearthblock


def assets(only=None):
    profile=read_json('data/art/voxel_wildlife.json')
    palette={key:linear(value) for key,value in profile['palette'].items()}
    for name,shapes in profile['parts'].items():
        path='assets/models/animals/'+name+'.glb'
        if only and only not in path: continue
        art=read_json(hearthblock.DATA)['models']
        occlusion=None
        if name in art:    # Hearthblock (doc 256)
            vox=hearthblock.model(name); occlusion=hearthblock.occlusion(name)
        else:
            vox=Voxels()
            for shape in shapes: solid(vox,shape,palette)
        parts={'main':Part(vox,occlusion=occlusion)}
        if name in ('deer/leg','wolf/leg'):
            knee=round(read_json(f'data/entities/animals/{name.split("/")[0]}.json')['visual_pose']['knee_y']*16)
            upper=Voxels(); lower=Voxels()
            upper.cells={p:c for p,c in vox.cells.items() if p[1]>=knee}
            lower.cells={p:c for p,c in vox.cells.items() if p[1]<knee}
            parts={'Upper':Part(upper,occlusion=occlusion),'Lower':Part(lower,occlusion=occlusion)}
        yield path,parts,dict(part=name,baked_proportions=True)

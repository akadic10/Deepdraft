"""Native voxel wildlife parts in their existing rigid-part authoring frames."""
from common import Voxels,Part,linear,read_json
from micro_voxel_study.generate import solid


def assets(only=None):
    profile=read_json('data/art/voxel_wildlife.json')
    palette={key:linear(value) for key,value in profile['palette'].items()}
    for name,shapes in profile['parts'].items():
        path='assets/models/animals/'+name+'.glb'
        if only and only not in path: continue
        vox=Voxels()
        for shape in shapes: solid(vox,shape,palette)
        parts={'main':Part(vox)}
        if name in ('deer/leg','wolf/leg'):
            knee=-10 if name=='deer/leg' else -8
            upper=Voxels(); lower=Voxels()
            upper.cells={p:c for p,c in vox.cells.items() if p[1]>=knee}
            lower.cells={p:c for p,c in vox.cells.items() if p[1]<knee}
            parts={'Upper':Part(upper),'Lower':Part(lower)}
        yield path,parts,dict(part=name,baked_proportions=True)

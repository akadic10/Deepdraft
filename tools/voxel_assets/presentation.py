"""Offline-baked actor overlays; intentional non-casters with one visual mesh."""
from common import Voxels,Part,linear,read_json
from solid_shapes import solid


def assets(only=None):
    profile=read_json('data/art/voxel_presentation.json')
    palette={k:linear(v) for k,v in profile['palette'].items()}
    for name,shapes in profile['parts'].items():
        path='assets/models/presentation/'+name+'.glb'
        if only and only not in path: continue
        vox=Voxels()
        for shape in shapes: solid(vox,shape,palette)
        yield path,{'Overlay':Part(vox,shadow=False)},dict(presentation=name,shadow_exception='Tiny actor overlay; explicitly non-casting')

"""Hearthblock UI icon models (doc 259).

Icons are authored in tools/hearthblock/art/icons.mjs like any other Hearthblock
model and meshed here with baked occlusion and no shadow proxy. They are a staged
family: the GLBs are only an intermediate. tools/GenerateUiIcons.gd renders the
staged models to the PNGs the UI uses (assets/ui/icons/); no icon GLB ships.
"""
from common import Part, read_json
import built_logs
import hearthblock


def assets(only=None):
    for name, model in read_json(hearthblock.DATA)['models'].items():
        if not name.startswith('icon/'): continue
        path = 'assets/ui/icon_models/' + name.split('/', 1)[1] + '.glb'
        if only and only not in path: continue
        part = Part(hearthblock.model(name), shadow=False, occlusion=hearthblock.occlusion(name))
        yield path, {'main': part}, {'source': hearthblock.DATA, 'model': name, 'yaw': model.get('yaw', 0)}
    # Build's Wood menu (doc 275): each log in each wood, replayed from the built log's own recipe.
    for wood in built_logs.WOODS:
        for name, roles in (('log_horizontal', built_logs.log_cells('x', 1, 1, 0)), ('log_upright', built_logs.log_cells('y', 1, 1, 1))):
            path = f'assets/ui/icon_models/{name}_{wood}.glb'
            if only and only not in path: continue
            part = Part(built_logs.voxels(roles, wood), shadow=False, occlusion=hearthblock.occlusion())
            yield path, {'main': part}, {'source': 'tools/voxel_assets/built_logs.py', 'wood': wood, 'yaw': 0}

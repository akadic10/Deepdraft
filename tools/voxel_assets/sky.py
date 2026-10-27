"""Hearthblock Sky Dial pieces (doc 23, "The Sky Dial").

The pieces are authored in tools/hearthblock/art/sky.mjs like any other Hearthblock model
and meshed here with baked occlusion and no shadow proxy. Like the icons they are a staged
family: tools/GenerateUiIcons.gd renders the staged models to the layers the Sky Dial
stacks (assets/ui/sky_dial/); no sky GLB ships.
"""
from common import Part, read_json
import hearthblock


def assets(only=None):
    for name, model in read_json(hearthblock.DATA)['models'].items():
        if not name.startswith('sky/'): continue
        path = 'assets/ui/sky_models/' + name.split('/', 1)[1] + '.glb'
        if only and only not in path: continue
        part = Part(hearthblock.model(name), shadow=False, occlusion=hearthblock.occlusion(name))
        yield path, {'main': part}, {'source': hearthblock.DATA, 'model': name, 'framing': model.get('framing', 'picture'),
                                     'unshaded': model.get('unshaded', False), 'outline': model.get('outline', False)}

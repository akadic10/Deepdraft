"""Player-authored stump with semantic bark and cut-wood material roles."""
from functools import lru_cache
import hashlib
import organic_log
from pathlib import Path
from common import ROOT, Voxels, linear, read_json
from vox_source import read_models, grounded_cells, write_model

PROFILE=read_json('data/art/voxel_log_chair.json')
MATERIALS=read_json('data/materials/craft_materials.json')


@lru_cache(maxsize=1)
def source_model():
    path=ROOT/PROFILE['source']
    if hashlib.sha256(path.read_bytes()).hexdigest()!=PROFILE['sha256']:
        raise ValueError('Player log chair source changed; review source identity first')
    source=read_models(path)[0][PROFILE['model_index']]
    if source['size']!=tuple(PROFILE['size']) or len(source['cells'])!=PROFILE['cells']:
        raise ValueError('Log chair dimensions/cell count differ from approved source')
    return source


def roles():
    return organic_log.roles(grounded_cells(source_model()),'small')


def model(material_id=None):
    palette=(MATERIALS['materials'][material_id] if material_id else
             MATERIALS['source_palettes'][PROFILE['palette_source']])['colors']
    vox=Voxels();vox.cells={p:linear(palette[role]) for p,role in roles().items()}
    return vox


def export_editable(directory):
    source=source_model();sx,sy,_=source['size'];bottom=min(p[2] for p in source['cells'])
    role_cells=roles();names=['bark_dark','bark','wood','grain','cut']
    cells={(x+sx//2,sy//2-1-z,y+bottom):names.index(role)+1 for (x,y,z),role in role_cells.items()}
    for wood in ['pine','oak','juniper','applewood']:
        colors=MATERIALS['materials']['base:material:'+wood]['colors']
        palette=[tuple(bytes.fromhex(colors[name]))+(255,) for name in names]
        write_model(Path(directory)/(wood+'.vox'),source['size'],cells,palette)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vox-output',type=Path,required=True)
    args=parser.parse_args();export_editable(args.vox_output)
    print('LOG_CHAIR_VOX_VARIANTS_OK 4')

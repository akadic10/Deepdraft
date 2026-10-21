"""Player tabletop and a centered one-block log pedestal on the native 1:16 grid."""
from functools import lru_cache
import hashlib
import organic_log
from pathlib import Path
from common import ROOT,Voxels,linear,read_json
from vox_source import read_models,write_model
from log_chair import MATERIALS

PROFILE=read_json('data/art/voxel_log_table.json')


@lru_cache(maxsize=1)
def source_model():
    path=ROOT/PROFILE['source']
    if hashlib.sha256(path.read_bytes()).hexdigest()!=PROFILE['sha256']:
        raise ValueError('Log tabletop source changed; review source identity first')
    source=read_models(path)[0][PROFILE['model_index']]
    if source['size']!=tuple(PROFILE['size']) or len(source['cells'])!=PROFILE['cells']:
        raise ValueError('Log tabletop dimensions/cell count differ from approved source')
    if min(p[2] for p in source['cells'])!=PROFILE['base_height_cells']:
        raise ValueError('Pedestal height must meet the authored tabletop without a gap')
    return source


def top_cells():
    source=source_model();sx,sy,_=source['size']
    # Preserve source height as well as X/Z: the empty lower 16 layers are intentional.
    return {(x-sx//2,z,sy//2-1-y) for x,y,z in source['cells']}


def base_cells():
    diameter=PROFILE['base_diameter_cells'];radius=diameter/2
    return {(x,y,z) for x in range(-diameter//2,diameter//2)
            for z in range(-diameter//2,diameter//2) if (x+.5)**2+(z+.5)**2<=radius**2
            for y in range(PROFILE['base_height_cells'])}


def role_cells():
    result=organic_log.roles(base_cells(),'pedestal')
    result.update(organic_log.roles(top_cells(),'large'))
    return result


def model(material_id=None):
    palette=(MATERIALS['materials'][material_id] if material_id else
             MATERIALS['source_palettes'][PROFILE['palette_source']])['colors']
    vox=Voxels();vox.cells={p:linear(palette[role]) for p,role in role_cells().items()}
    return vox


def export_editable(directory):
    sx,sy,height=source_model()['size'];names=['bark_dark','bark','wood','grain','cut']
    cells={(x+sx//2,sy//2-1-z,y):names.index(role)+1 for (x,y,z),role in role_cells().items()}
    for wood in ['pine','oak','juniper','applewood']:
        colors=MATERIALS['materials']['base:material:'+wood]['colors']
        palette=[tuple(bytes.fromhex(colors[name]))+(255,) for name in names]
        write_model(Path(directory)/(wood+'.vox'),(sx,sy,height),cells,palette)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vox-output',type=Path,required=True)
    args=parser.parse_args();export_editable(args.vox_output)
    print('LOG_TABLE_VOX_VARIANTS_OK 4')

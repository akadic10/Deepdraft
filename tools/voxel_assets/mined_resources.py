"""Approved chunky stone, ore and soil, baked at the existing 1:16 size."""
from functools import lru_cache
import hashlib
from common import ROOT, Voxels, linear, read_json
from vox_source import read_models, write_model

PROFILE=read_json('data/art/voxel_items.json')
SHAPES=read_json('data/art/voxel_mined_resources.json')


@lru_cache(maxsize=1)
def source_model():
    """Archived original for provenance/recovery, no longer the active shape."""
    spec=PROFILE['mined_original_source']
    path=ROOT/spec['source']
    if hashlib.sha256(path.read_bytes()).hexdigest()!=spec['sha256']:
        raise ValueError('Mined resource source changed; review and update its recorded identity')
    models,_=read_models(path)
    model=models[spec['model_index']]
    if tuple(spec['size'])!=model['size'] or len(model['cells'])!=spec['cells']:
        raise ValueError('Mined resource source dimensions/cell count changed')
    return model


def in_box(point,box):
    return all(box[i]<=point[i]<box[i+3] for i in range(3))


@lru_cache(maxsize=3)
def shape_cells(kind):
    """Broad authored columns form solid, grounded, asymmetric joined masses."""
    spec=SHAPES['shapes'][kind]
    cells={(x-6,y,z-6) for z,row in enumerate(spec['heights'])
           for x,height in enumerate(row) for y in range(int(height,16))}
    outline={(x,z) for x,y,z in cells}
    # One shallow lower bevel avoids extruded columns while keeping a broad foot.
    cells={p for p in cells if p[1]>0 or all((p[0]+dx,p[2]+dz) in outline
           for dx,dz in ((1,0),(-1,0),(0,1),(0,-1)))}
    cells={p for p in cells if not any(in_box(p,b) for b in spec['chips'])}
    if kind=='soil':
        for a,b,c,d,e,f in SHAPES['soil_pebbles']:
            cells.update((x,y,z) for x in range(a,d) for y in range(b,e) for z in range(c,f))
    return frozenset(cells)


def color_role(name,point):
    x,y,z=point
    style=PROFILE['mined_styles'][name]
    pattern=style['pattern']
    # Material variation follows large masses. No noisy per-cell random colors.
    role='body'
    if (x>=2 and z>=1) or (x<-3 and y<4): role='shade'
    if x<1 and z<0 and y>=7: role='light'
    # Large interrupted facets add material depth to the lower broken faces.
    if -5<=x<-2 and 3<=y<5 and z>=2: role='light'
    if x>=3 and 4<=y<7 and 0<=z<3: role='body'
    if -2<=x<1 and 1<=y<3 and z>=3: role='shade'
    if pattern=='ore':
        if any(in_box(point,b) for b in SHAPES['ore_deposits']):
            return 'mineral_light' if y>=7 or (x<-2 and z>=4) else 'mineral'
    elif pattern=='soil':
        if any(in_box(point,b) for b in SHAPES['soil_pebbles']): return 'accent'
        if z>=1 and x<0 and y>=6: role='light'
    elif pattern=='coal':
        if x>=2 and y>=6: role='light'
    # The inset cleft is darker, but large outer faces retain their material color.
    if 0<=x<2 and z>=0 and y<4: role='cleft'
    return role


def model(name):
    style=PROFILE['mined_styles'][name]
    palette={role:linear(c) for role,c in style['palette'].items()}
    vox=Voxels()
    vox.cells={p:palette[color_role(name,p)] for p in sorted(shape_cells(style['shape']))}
    return vox


def export_editable(directory):
    """Editable single-model copies, centered on the original 16-cell canvas."""
    for name,style in PROFILE['mined_styles'].items():
        roles=list(style['palette'])
        cells={(x+8,7-z,y+2):1+roles.index(color_role(name,(x,y,z)))
               for x,y,z in shape_cells(style['shape'])}
        palette=[tuple(bytes.fromhex(c))+(255,) for c in style['palette'].values()]
        write_model(directory/(name+'.vox'),(16,16,16),cells,palette)


if __name__=='__main__':
    import argparse
    from pathlib import Path
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vox-output',type=Path,required=True)
    args=parser.parse_args(); export_editable(args.vox_output)
    print('MINED_VOX_VARIANTS_OK',len(PROFILE['mined_styles']))

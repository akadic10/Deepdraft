"""Player workbench outline extruded at native 1:16 resolution, with wood and wear."""
from functools import lru_cache
import hashlib
import organic_log
from pathlib import Path
from common import ROOT, Voxels, linear, read_json
from vox_source import read_models, grounded_cells, write_model
import log_chair

PROFILE=read_json('data/art/voxel_workbench.json')


@lru_cache(maxsize=1)
def source_model():
    path=ROOT/PROFILE['source']
    if hashlib.sha256(path.read_bytes()).hexdigest()!=PROFILE['sha256']:
        raise ValueError('Workbench example changed; review source identity first')
    source=read_models(path)[0][PROFILE['model_index']]
    if source['size']!=tuple(PROFILE['size']) or len(source['cells'])!=PROFILE['cells']:
        raise ValueError('Workbench dimensions/cell count differ from approved source')
    # Validate the two source slices independently before extruding their outline.
    slices={y:{(x,z) for x,z,h in source['cells'] if h==y}
            for y in {p[2] for p in source['cells']}}
    if not all(layer==next(iter(slices.values())) for layer in slices.values()):
        raise ValueError('Workbench example must have a consistent extrusion outline')
    return source


def role_cells(worn=True):
    source=grounded_cells(source_model());height=PROFILE['height_cells']
    footprint={(x,z) for x,_,z in source}
    cells=organic_log.roles({(x,y,z) for x,z in footprint for y in range(height)},'large')
    if not worn:return cells
    removed=set()
    for scar in PROFILE['scars']:
        a,b=scar['from'],scar['to'];steps=max(abs(b[i]-a[i]) for i in range(2))
        for i in range(steps+1):
            x,z=(round(a[j]+(b[j]-a[j])*i/max(1,steps)) for j in range(2))
            for dx in range(scar['width']):
                for y in range(height-scar['depth'],height):removed.add((x+dx,y,z))
    for chip in PROFILE['rim_chips']:
        lo,hi=chip['min'],chip['max']
        removed.update((x,y,z) for x in range(lo[0],hi[0]) for y in range(lo[1],hi[1]) for z in range(lo[2],hi[2]))
    removed.intersection_update(cells)
    for p in removed:del cells[p]
    for x,y,z in removed:
        for dx,dy,dz in [(1,0,0),(-1,0,0),(0,-1,0),(0,0,1),(0,0,-1)]:
            q=(x+dx,y+dy,z+dz)
            if q in cells:cells[q]='grain' if dy else 'wood'
    return cells


def model(material_id=None,worn=True):
    palette=(log_chair.MATERIALS['materials'][material_id] if material_id else
             log_chair.MATERIALS['source_palettes'][PROFILE['palette_source']])['colors']
    v=Voxels();v.cells={p:linear(palette[role]) for p,role in role_cells(worn).items()}
    return v


def export_editable(directory):
    sx,sy,_=source_model()['size'];names=['bark_dark','bark','wood','grain','cut']
    cells={(x+sx//2,sy//2-1-z,y):names.index(role)+1 for (x,y,z),role in role_cells().items()}
    for wood in ['pine','oak','juniper','applewood']:
        colors=log_chair.MATERIALS['materials']['base:material:'+wood]['colors']
        palette=[tuple(bytes.fromhex(colors[name]))+(255,) for name in names]
        write_model(Path(directory)/(wood+'.vox'),(sx,sy,PROFILE['height_cells']),cells,palette)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vox-output',type=Path,required=True)
    args=parser.parse_args();export_editable(args.vox_output)
    print('WORKBENCH_VOX_VARIANTS_OK 4')

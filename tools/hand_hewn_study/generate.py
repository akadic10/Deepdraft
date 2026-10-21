"""Rebuild the isolated timber study from the shared, accepted production design."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import struct
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/voxel_assets'))
from common import Part, Voxels, export_asset, linear, read_json
from vox_source import write_model, read_models, grounded_cells

from hand_hewn_timber import PROFILE, KINDS, roles, validate

OUT = ROOT / 'assets/models/studies/hand_hewn_timber'
EDITABLE = ROOT / 'VoxelFeed/studies/hand_hewn_timber'


def build(output,editable):
    models=roles(); validate(models)
    output.mkdir(parents=True,exist_ok=True)
    report={}
    for wood,palette in PROFILE['palettes'].items():
        for kind,cells in models.items():
            vox=Voxels();vox.cells={p:linear(palette[c]) for p,c in sorted(cells.items())}
            key=f'{kind}_{wood}'
            report[key]=export_asset(output/(key+'.glb'),{'main':Part(vox)},
                stride=PROFILE['shadow']['stride'],coverage=PROFILE['shadow']['minimum_coverage'])
            if editable:
                lo=[min(p[i] for p in cells) for i in range(3)]
                hi=[max(p[i] for p in cells)+1 for i in range(3)]
                names=list(palette)
                # Invert Z for a handedness-preserving Y-up -> VOX Z-up export.
                grid={(x-lo[0],hi[2]-1-z,y-lo[1]):names.index(c)+1 for (x,y,z),c in cells.items()}
                write_model(editable/(key+'.vox'),(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]),grid,
                    [tuple(bytes.fromhex(palette[name]))+(255,) for name in names])
    return report


def validate_files():
    """Check the actual exported files, independently of the mesh builder."""
    models=roles()
    for wood,palette in PROFILE['palettes'].items():
        for kind,cells in models.items():
            key=f'{kind}_{wood}'
            source,colors=read_models(EDITABLE/(key+'.vox'))
            restored=grounded_cells(source[0])
            assert set(restored)==set(cells),(key,'editable VOX shape')
            for p,index in restored.items():
                assert colors[index-1]==tuple(bytes.fromhex(palette[cells[p]]))+(255,),(key,'editable colors')
            raw=(OUT/(key+'.glb')).read_bytes()
            n=struct.unpack_from('<I',raw,12)[0]
            doc=json.loads(raw[20:20+n]); blob=raw[28+n:]
            for mesh in doc['meshes']:
                for primitive in mesh['primitives']:
                    accessor=doc['accessors'][primitive['attributes']['POSITION']]
                    buffer=doc['bufferViews'][accessor['bufferView']]
                    start=buffer.get('byteOffset',0)+accessor.get('byteOffset',0)
                    for i in range(accessor['count']):
                        point=struct.unpack_from('<3f',blob,start+i*buffer.get('byteStride',12))
                        assert all(v*16==round(v*16) for v in point),(key,'export grid')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            report=build(Path(tmp),None)
            for key,row in report.items():
                assert hashlib.sha256((OUT/(key+'.glb')).read_bytes()).hexdigest()==row['sha256'],key
        validate_files()
        print('HAND_HEWN_DETERMINISTIC_PASS: 20 models; exact GLB grid and editable VOX roundtrips; dimensions, connectivity, shared body, timber rotation and 5x5 seating')
    else:
        report=build(OUT,EDITABLE)
        (OUT/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({key:{'visual':v['parts'][0]['visual_triangles'],'shadow':v['parts'][0]['shadow']['triangles']}
                          for key,v in report.items() if key.endswith('_oak')},indent=2))

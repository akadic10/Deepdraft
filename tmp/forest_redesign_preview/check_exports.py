"""Audit authored/exported roster and the pre-replacement snapshot."""
import hashlib
import importlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import generate_forest_redesign as forest
from voxel_glb import write_glb

OUT = ROOT / 'tmp/forest_redesign_preview'
snapshot = json.loads((OUT / 'pre_import.json').read_text())
approved = {}
for folder in ('tree', 'apple', 'juniper'):
    approved.update(json.loads((ROOT / f'tmp/{folder}_redesign_preview/integration.json').read_text())['approved_models_imported'])

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def glb_arrays(path):
    data = path.read_bytes()
    assert struct.unpack_from('<III', data) == (0x46546c67, 2, len(data))
    length, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20+length])
    bin_length, bin_kind = struct.unpack_from('<II', data, 20+length)
    assert bin_kind == 0x004e4942 and bin_length == len(data)-28-length
    blob = data[28+length:]
    arrays = []
    for accessor in doc['accessors']:
        view = doc['bufferViews'][accessor['bufferView']]
        width = {'VEC3':3, 'VEC4':4, 'SCALAR':1}[accessor['type']]
        dtype = '<f4' if accessor['componentType'] == 5126 else '<u4'
        values = np.frombuffer(blob, dtype=dtype, count=accessor['count']*width,
                               offset=view.get('byteOffset',0)+accessor.get('byteOffset',0))
        arrays.append(values.reshape(-1,width) if width != 1 else values)
    return arrays

generated = {}
with tempfile.TemporaryDirectory(prefix='deepdraft-forest-check-') as temp:
    for species in forest.SPECIES:
        canonical = importlib.import_module(f'generate_{species}_glbs')
        assert canonical.manifest() == forest.manifest(species)
        for name, stage, season, variant in canonical.manifest():
            path = OUT / 'models' / species / (name+'.glb')
            rel = f'assets/models/flora/trees/{species}/{name}.glb'
            vox = getattr(canonical, f'build_{species}')(stage,season,variant)
            mesh = getattr(canonical, f'mesh_{species}')(vox,stage,season,variant)
            arrays = glb_arrays(path)
            for actual, expected in zip(arrays,mesh):
                assert np.array_equal(actual,np.asarray(expected,dtype=actual.dtype)), name
                assert np.isfinite(actual).all(), name
            positions,normals,colors,indices = arrays
            assert len(indices)%3 == 0 and indices.max() < len(positions)
            assert np.isin(normals,[-1,0,1]).all() and (np.abs(normals).sum(axis=1)==1).all()
            assert ((colors >= 0) & (colors <= 1)).all()
            a,b,c = positions[indices.reshape(-1,3)].transpose(1,0,2)
            assert (np.sum(np.cross(b-a,c-a)*normals[indices[::3]],axis=1)>0).all()
            repro = Path(temp) / (name+'.glb')
            write_glb(repro,name,mesh)
            assert repro.read_bytes() == path.read_bytes(), name
            generated[rel] = digest(path)

assert len(generated) == 86
assert set(snapshot['tree_hashes']) <= set(generated)
assert len(approved) == 11
assert all(generated[path] == sha for path,sha in approved.items())
changed = [path for path,sha in snapshot['tree_hashes'].items() if generated[path] != sha]
assert len(changed) == 47
assert all(path not in approved for path in changed)
report = {'models_checked':86, 'canonical_exports_reproduced':86,
          'approved_baselines_unchanged':11, 'old_models_replaced':len(changed),
          'new_seasonal_counterparts':28, 'export_arrays_valid':True,
          'deterministic_exports':True, 'generated_hashes':generated}

if '--installed' in sys.argv:
    assert {p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models/flora/trees').rglob('*.glb')} == set(generated)
    assert all(digest(ROOT/path) == sha for path,sha in generated.items())
    for species in forest.SPECIES:
        current = json.loads((ROOT/f'data/entities/flora/{species}_tree.json').read_text(encoding='utf-8'))
        original = snapshot['registries'][species]
        key = 'base:flora:'+species+'_tree'
        for stage in forest.STAGES:
            models = current[key]['stages'][stage]['models']
            assert set(models) == set(forest.seasons_for(species,stage))
            for season,paths in models.items():
                paths = [paths] if isinstance(paths,str) else paths
                assert paths == ['res://assets/models/flora/trees/'+species+'/'+forest.model_name(species,stage,season,v)+'.glb'
                                 for v in range(1,forest.variant_count(species,stage)+1)]
        def gameplay(value):
            if isinstance(value,dict):
                return {k:gameplay(v) for k,v in value.items() if not k.startswith('__') and k != 'models'}
            if isinstance(value,list):
                return [gameplay(v) for v in value]
            return value
        assert gameplay(current) == gameplay(original), species
    report['live_roster_matches_preview'] = True
    report['non_visual_registry_data_unchanged'] = True

(OUT/'export_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('FOREST_EXPORT_AUDIT_OK', {k:v for k,v in report.items() if k != 'generated_hashes'})

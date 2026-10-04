"""Audit the installed 2x2 hearth without rewriting other shipping assets."""
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
import generate_hearth_redesign as hearth
import generate_furniture_glbs as furniture
from voxel_glb import write_glb


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


live = ROOT / 'assets/models/furniture/hearth.glb'
before = json.loads((OUT / 'pre_import.json').read_text())
vox = hearth.hearth()
hearth.validate(vox)
expected = hearth.export_mesh(vox)
blob = live.read_bytes()
magic, version, length = struct.unpack_from('<4sII', blob)
assert magic == b'glTF' and version == 2 and length == len(blob)
json_len, json_kind = struct.unpack_from('<I4s', blob, 12)
assert json_kind == b'JSON'
gltf = json.loads(blob[20:20+json_len])
bin_len, bin_kind = struct.unpack_from('<I4s', blob, 20+json_len)
assert bin_kind == b'BIN\x00'
binary = blob[28+json_len:]
assert len(binary) == bin_len
arrays = []
for accessor in gltf['accessors']:
    view = gltf['bufferViews'][accessor['bufferView']]
    width = {'SCALAR':1, 'VEC3':3, 'VEC4':4}[accessor['type']]
    dtype = {5126:'<f4',5125:'<u4'}[accessor['componentType']]
    arr = np.frombuffer(binary, dtype=dtype,
                        count=accessor['count']*width,
                        offset=view.get('byteOffset',0)+accessor.get('byteOffset',0))
    arrays.append(arr.reshape(-1,width) if width > 1 else arr)
for index, (actual, source) in enumerate(zip(arrays, expected)):
    source = np.asarray(source,dtype=actual.dtype)
    if index == 0:
        source = source * hearth.SCALE
    assert np.array_equal(actual,source)
    assert np.isfinite(actual).all()
positions, normals, colors, indices = arrays
assert np.array_equal(positions.min(axis=0), [-1,0,-1])
assert np.array_equal(positions.max(axis=0), [1,2,1])
assert np.array_equal(positions*8, np.round(positions*8))
assert np.all(np.sum(np.abs(normals),axis=1)==1)
assert colors.min()>=0 and colors.max()<=1
assert indices.max()<len(positions)
triangles = positions[indices.reshape(-1,3)]
cross = np.cross(triangles[:,1]-triangles[:,0], triangles[:,2]-triangles[:,0])
assert np.all(np.sum(cross*normals[indices[::3]],axis=1)>0)
assert sha(live)==sha(OUT / 'models/hearth.glb')
assert sha(OUT/'reference/hearth.glb')==before['furniture_hashes']['assets/models/furniture/hearth.glb']
assert sha(OUT/'reference/hearth_1x1.glb')==sha(OUT/'reference/prototype_1x1/hearth.glb')

builders = {
    'barrel':furniture.build_barrel, 'storage_crate':furniture.build_storage_chest,
    'storage_shelf':furniture.build_storage_shelf, 'tavern_bar':furniture.build_tavern_bar,
    'bench':furniture.build_bench, 'door':furniture.build_door, 'hearth':furniture.build_hearth,
}
with tempfile.TemporaryDirectory(prefix='deepdraft-hearth-') as temporary:
    destination = Path(temporary)
    for name,builder in builders.items():
        path = destination/f'{name}.glb'
        write_glb(path,name,furniture.mesh_furniture(name,builder()),furniture.EXPORT_SCALE)
        shipping = ROOT/f'assets/models/furniture/{name}.glb'
        assert sha(path)==sha(shipping), f'Canonical output differs: {name}'
        if name!='hearth':
            assert sha(shipping)==before['furniture_hashes'][shipping.relative_to(ROOT).as_posix()]
    packed = destination/'packed_furniture.glb'
    write_glb(packed,'packed_furniture',furniture.mesh_from_voxels(furniture.build_packed_box()),furniture.EXPORT_SCALE)
    assert sha(packed)==sha(ROOT/'assets/models/items/furniture/packed_furniture.glb')==before['packed_hash']

definition = json.loads((ROOT/'data/furniture/hearth.json').read_text(encoding='utf-8'))
assert definition['footprint']=={'width':2,'depth':2}
assert definition['collision_regions']==[{'min':[0,0,0],'max':[2,2,2]}]
for key,value in before['hearth_definition'].items():
    if key not in ('__comment','description','footprint','collision_regions'):
        assert definition[key]==value,key
logs = {}
for name in ('review-import','review-capture','live-import','live-check'):
    log = (Path(os.environ['TEMP'])/f'deepdraft-hearth-{name}.log').read_text(encoding='utf-8')
    assert 'ERROR:' not in log,name
    if name=='review-capture':
        assert 'HEARTH_REDESIGN_REVIEW_OK' in log
    if name=='live-check':
        assert 'LIVE_HEARTH_2X2_OK' in log
    logs[name] = {'errors':0,'warnings':log.count('WARNING:')}
runtime = json.loads((OUT/'runtime_checks.json').read_text())
assert runtime['rotations_checked']==4 and runtime['installed_and_ghost_save_round_trip']
captures = sorted(p.name for p in (OUT/'renders').glob('*.png'))
assert len(captures)==9
checks = {'export_arrays_valid':True,'deterministic_export':True,'connected':True,
          'fits_live_footprint_collision':True,'canonical_exports_match_all_seven_models':True,
          'other_six_models_and_shared_packed_item_unchanged':True,
          'live_model_matches_review':True,'logs':logs,'captures':captures}
(OUT/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
integration = {'status':'installed_and_verified','model_sha256':sha(live),
               'footprint':definition['footprint'],'collision_regions':definition['collision_regions'],
               'heat_units':400,'voxels_per_block':8,'checks':checks,'runtime':runtime,
               'save_migration':'Current definition applied at saved origin; no automatic relocation.'}
(OUT/'integration.json').write_text(json.dumps(integration,indent=2)+'\n')
print('HEARTH_EXPORTS_OK',sha(live),len(vox.cells),'voxels',len(indices)//3,'triangles')

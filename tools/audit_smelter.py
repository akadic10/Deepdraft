"""Verify the smelter addition against its baseline and the canonical exporter."""
import difflib
import hashlib
import json
from pathlib import Path

import generate_furniture_glbs as furniture
from generate_smelter import smelter, validate, body, flame_frames

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'tmp/smelter_preview'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    snapshot = json.loads((OUT/'pre_import.json').read_text(encoding='utf-8'))
    old_glbs = {p:h for p,h in snapshot['hashes'].items() if p.endswith('.glb')}
    assert len(old_glbs)==155 and all(sha(ROOT/p)==h for p,h in old_glbs.items())
    added = {p.relative_to(ROOT).as_posix() for p in (ROOT/'assets').rglob('*.glb')}-set(old_glbs)
    assert added=={'assets/models/furniture/smelter.glb','assets/models/furniture/animations/smelter_flame.glb'}
    old_defs = {p:h for p,h in snapshot['hashes'].items() if p.startswith('data/furniture/')}
    assert len(old_defs)==14 and all(sha(ROOT/p)==h for p,h in old_defs.items())
    items_path = 'data/entities/items/resources.json'
    old_items = json.loads(snapshot['source_text'][items_path])
    items = json.loads((ROOT/items_path).read_text(encoding='utf-8'))
    assert all(items[k]==v for k,v in old_items.items())
    assert set(items)-set(old_items)=={'base:resources:furniture:smelter'}
    defs = [json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'data/furniture').glob('*.json')]
    assert len(defs)==15
    for definition in defs:
        assert (ROOT/definition['model'].removeprefix('res://')).is_file()
        assert items[definition['item_key']]['model']=='res://assets/models/items/furniture/packed_furniture.glb'
    validate(smelter())
    for _,fire in flame_frames():
        assert not set(body().cells)&set(fire.cells)
        assert all(z<=4 and 3<=y<=11 for x,y,z in fire.cells), 'Fire escaped the chamber'
        assert (0,12,-3) not in body().cells, 'Flue closed at roof'

    exports = OUT/'canonical_exports'
    old_file = furniture.__file__
    try:
        furniture.__file__ = str(exports/'tools/generate_furniture_glbs.py')
        furniture.main()
    finally:
        furniture.__file__ = old_file
    canonical = {}
    for exported in (exports/'assets').rglob('*.glb'):
        rel = exported.relative_to(exports).as_posix()
        assert sha(exported)==sha(ROOT/rel), f'{rel}: canonical bytes differ'
        canonical[rel] = sha(exported)
    assert len(canonical)==19
    runtime = json.loads((OUT/'runtime_checks.json').read_text(encoding='utf-8'))
    assert runtime['placeable_definitions']==15 and runtime['actual_smelter_button_dispatch']
    assert all(p['buttons']==16 and p['rows']==3 for p in runtime['build_panel_layouts'])
    assert runtime['flame_animation']['visible_frames']==8
    changed,diff = [],[]
    for rel,old in snapshot['source_text'].items():
        current = (ROOT/rel).read_text(encoding='utf-8')
        if current!=old:
            changed.append(rel)
            diff.extend(difflib.unified_diff(old.splitlines(True),current.splitlines(True),fromfile='before/'+rel,tofile='after/'+rel))
    (OUT/'session.diff').write_text(''.join(diff),encoding='utf-8')
    report = {'prior_glbs_preserved':len(old_glbs),'prior_furniture_defs_preserved':len(old_defs),
              'prior_item_definitions_preserved':True,'canonical_exports_match':len(canonical),
              'canonical_hashes':canonical,'modified_existing_sources':changed,'runtime_checks':runtime}
    (OUT/'integration.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('SMELTER_AUDIT_OK',json.dumps({k:v for k,v in report.items() if k not in ('canonical_hashes','runtime_checks')}))


if __name__=='__main__':
    main()

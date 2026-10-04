"""Audit the hearth animation against its baseline and isolated canonical export."""
import difflib
import hashlib
import json
from pathlib import Path

import generate_furniture_glbs as furniture
import generate_hearth_redesign as hearth

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'tmp/hearth_animation_preview'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    snapshot = json.loads((OUT/'pre_animation.json').read_text(encoding='utf-8'))
    old_glbs = {p:h for p,h in snapshot['hashes'].items() if p.endswith('.glb')}
    changed_glbs = [p for p,h in old_glbs.items() if sha(ROOT/p)!=h]
    assert changed_glbs == ['assets/models/furniture/hearth.glb']
    added_glbs = {p.relative_to(ROOT).as_posix() for p in (ROOT/'assets').rglob('*.glb')}-set(old_glbs)
    assert added_glbs == {'assets/models/furniture/animations/hearth_flame.glb'}
    # Compare actual authored cells/colors, not only bounds or triangle counts.
    old_source = snapshot['source_text']['tools/generate_hearth_redesign.py']
    scope = {'__name__':'baseline_hearth','__file__':str(ROOT/'tools/generate_hearth_redesign.py')}
    exec(compile(old_source,'baseline_hearth','exec'),scope)
    original = scope['hearth']()
    body,flame = hearth.hearth_parts()
    assert original.cells == body.cells | flame.cells
    for _,frame in hearth.flame_frames():
        assert not set(body.cells)&set(frame.cells)
        assert {p:c for p,c in frame.cells.items() if p[1]<=7} == {p:c for p,c in flame.cells.items() if p[1]<=7}
    path = 'data/furniture/hearth.json'
    before = json.loads(snapshot['source_text'][path])
    after = json.loads((ROOT/path).read_text(encoding='utf-8'))
    assert {k:v for k,v in before.items() if k!='__comment'} == {k:v for k,v in after.items() if k not in ('__comment','light_source')}
    # Exercise the real canonical main() in a temporary root, without replacing
    # any approved shipping asset as a side effect of verification.
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
    assert len(canonical)==16
    runtime = json.loads((OUT/'runtime_checks.json').read_text(encoding='utf-8'))
    assert runtime['flame_animation']['visible_frames']==10 and runtime['heat_units']==400
    torch = json.loads((ROOT/'tmp/wall_torch_preview/runtime_checks.json').read_text(encoding='utf-8'))
    assert torch['flame_animation']['visible_frames']==8
    changed,diff = [],[]
    for rel,old in snapshot['source_text'].items():
        current = (ROOT/rel).read_text(encoding='utf-8')
        if current!=old:
            changed.append(rel)
            diff.extend(difflib.unified_diff(old.splitlines(True),current.splitlines(True),fromfile='before/'+rel,tofile='after/'+rel))
    (OUT/'session.diff').write_text(''.join(diff),encoding='utf-8')
    report = {'other_glbs_preserved':len(old_glbs)-1,'original_hearth_cells_and_colors_preserved':True,
              'fixed_flame_base_preserved':True,'gameplay_definition_unchanged':True,
              'canonical_exports_match':len(canonical),'canonical_hashes':canonical,
              'modified_existing_source_files':changed,'runtime_checks':runtime,
              'wall_torch_regression_passed':True}
    (OUT/'integration.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('HEARTH_ANIMATION_AUDIT_OK',json.dumps({k:v for k,v in report.items() if k not in ('canonical_hashes','runtime_checks')}))


if __name__=='__main__':
    main()

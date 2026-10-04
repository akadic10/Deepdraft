"""Audit torch integration against the pre-edit snapshot and canonical exporters."""
import json
from pathlib import Path
import difflib

import generate_furniture_glbs as furniture
from generate_wall_torch import torch, write_parts, write_flames, FLAME_MODEL
from generate_tavern_redesign import sha
from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'tmp/wall_torch_preview'


def main():
    snapshot = json.loads((OUT/'pre_import.json').read_text(encoding='utf-8'))
    prior_glbs = {p:h for p,h in snapshot['hashes'].items() if p.endswith('.glb')}
    assert len(prior_glbs)==151
    assert all(sha(ROOT/p)==h for p,h in prior_glbs.items())
    prior_defs = {p:h for p,h in snapshot['hashes'].items() if p.startswith('data/furniture/')}
    assert len(prior_defs)==12 and all(sha(ROOT/p)==h for p,h in prior_defs.items())
    resource_path = 'data/entities/items/resources.json'
    old_items = json.loads(snapshot['source_text'][resource_path])
    new_items = json.loads((ROOT/resource_path).read_text(encoding='utf-8'))
    assert all(new_items[k]==v for k,v in old_items.items())
    assert set(new_items)-set(old_items)=={'base:resources:furniture:wall_torch'}
    definitions = [json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'data/furniture').glob('*.json')]
    assert len(definitions)==13
    for definition in definitions:
        assert (ROOT/definition['model'].removeprefix('res://')).is_file()
        item = new_items[definition['item_key']]
        assert item['model']=='res://assets/models/items/furniture/packed_furniture.glb'
    # Reproduce shipping bytes through the same builders/writers as main(),
    # exporting into an isolated audit directory rather than touching old assets.
    names = {'barrel':'barrel','storage_crate':'storage_chest','storage_shelf':'storage_shelf',
             'tavern_bar':'tavern_bar','bench':'bench','hearth':'hearth','door':'door',
             'trade_counter':'trade_counter','wooden_table':'wooden_table',
             'wooden_chair':'wooden_chair','dwarf_bunk':'dwarf_bunk','brewing_vat':'brewing_vat',
             'packed_furniture':'packed_box'}
    exports = OUT/'canonical_exports'
    exports.mkdir(exist_ok=True)
    canonical = {}
    for name,builder in names.items():
        vox = getattr(furniture,'build_'+builder)()
        path = exports/(name+'.glb')
        write_glb(path,name,furniture.mesh_furniture(name,vox),furniture.EXPORT_SCALE)
        shipped = ROOT/'assets/models'/('items/furniture' if name=='packed_furniture' else 'furniture')/(name+'.glb')
        assert sha(path)==sha(shipped), f'{name}: canonical bytes differ'
        canonical[name] = sha(path)
    body,flame = torch()
    path = exports/'wall_torch.glb'
    write_parts(path,[('torch_body',body),('torch_flame',flame)],exports)
    assert sha(path)==sha(ROOT/'assets/models/furniture/wall_torch.glb')
    canonical['wall_torch'] = sha(path)
    flame_path = exports/'wall_torch_flame.glb'
    write_flames(flame_path,exports)
    assert sha(flame_path)==sha(ROOT/FLAME_MODEL)
    canonical['animations/wall_torch_flame'] = sha(flame_path)
    animation_baseline = json.loads((OUT/'pre_animation.json').read_text(encoding='utf-8'))
    prior_animation_glbs = {p:h for p,h in animation_baseline['hashes'].items() if p.endswith('.glb')}
    assert len(prior_animation_glbs)==152
    assert all(sha(ROOT/p)==h for p,h in prior_animation_glbs.items())
    # Capture just this turn's source changes, preserving prior approved work.
    changed = []
    diff = []
    for rel,old in snapshot['source_text'].items():
        current = (ROOT/rel).read_text(encoding='utf-8')
        if current!=old:
            changed.append(rel)
            diff.extend(difflib.unified_diff(old.splitlines(True),current.splitlines(True),
                                           fromfile='before/'+rel,tofile='after/'+rel))
    (OUT/'session.diff').write_text(''.join(diff),encoding='utf-8')
    runtime = json.loads((OUT/'runtime_checks.json').read_text(encoding='utf-8'))
    shadows = json.loads((OUT/'shadow_checks.json').read_text(encoding='utf-8'))
    assert runtime['all_four_live_terrain_shadow_paths'] and shadows['wall_blocks_local_light']
    assert runtime['flame_animation']['visible_frames']==8
    report = {'prior_glbs_preserved':len(prior_glbs),'prior_furniture_definitions_preserved':len(prior_defs),
              'prior_item_definitions_preserved':True,'new_placeable_total':len(definitions),
              'canonical_exports_match':len(canonical),'canonical_hashes':canonical,
              'modified_prior_source_files':sorted(changed),'player_saves_touched':False,
              'gpu_terrain_shadow_check':shadows,'runtime_report':'runtime_checks.json',
              'pre_animation_glbs_preserved':len(prior_animation_glbs),
              'flame_animation':runtime['flame_animation']}
    (OUT/'integration.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('WALL_TORCH_AUDIT_OK',json.dumps({k:v for k,v in report.items() if k!='canonical_hashes'}))


if __name__=='__main__':
    main()

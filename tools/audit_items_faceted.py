"""Offline item-art audit against retained pre-conversion contracts.

Run after generate_items_faceted.py --check and Godot import. --record refreshes
measurements while preserving original non-art/reference fingerprints.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from faceted_glb import read
from art_asset_paths import current_path
from art_asset_revisions import expected_metrics

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'docs/00_dev_roadmap/concepts/155_item_conversion/audit.json'


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--record',action='store_true'); args=parser.parse_args()
    previous=json.loads(REPORT.read_text(encoding='utf-8'))
    definitions=json.loads((ROOT/'data/entities/items/resources.json').read_text(encoding='utf-8'))
    non_art={k:{x:y for x,y in v.items() if x not in ['model','crate_models']} if isinstance(v,dict) else v for k,v in definitions.items()}
    fingerprint=hashlib.sha256(json.dumps(non_art,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    assert fingerprint==previous['non_art_definitions_sha256'],'gameplay definitions changed'
    registry=(ROOT/'scripts/registries/DwarfAssets.gd').read_text(encoding='utf-8')
    # Reconstruct the approval's path spelling without changing its retained
    # fingerprint. Only the directory layout has changed since that report.
    approved_registry=registry.replace('res://assets/models/characters/dwarves/','res://assets/dwarves/faceted/').replace('/dwarves/faceted/tools/','/dwarves/tools/')
    assert hashlib.sha256(approved_registry.encode()).hexdigest()==previous['normalized_dwarf_registry_sha256'],'dwarf registry changed beyond asset paths'
    for path,sha in previous['preserved_exports'].items():
        expected=expected_metrics(path,{'sha256':sha})
        assert hashlib.sha256((ROOT/current_path(path)).read_bytes()).hexdigest()==expected['sha256'],path
    item_paths=set(); keys=[]
    for key,v in definitions.items():
        if not isinstance(v,dict): continue
        for path in [v.get('model',''),*v.get('crate_models',[])]:
            if not path: continue
            assert (ROOT/path.removeprefix('res://')).is_file(),path
            if '/models/items/' in path: item_paths.add(path.removeprefix('res://'))
        if '/models/items/' in v.get('model',''):
            keys.append(key)
            png=(ROOT/('assets/ui/items/'+key.replace(':','_')+'.png')).read_bytes()
            assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(216,180),key
    assert len(keys)==62 and len(item_paths)==92
    paths=sorted(item_paths|{'assets/models/characters/dwarves/tools/'+n+'.glb' for n in ['felling_axe','mining_pickaxe']})
    manifest=[]; missing=previous['missing_legacy']; new_items=new_tools=0
    old_items=previous['cost']['legacy_item_triangles']; old_tools=previous['cost']['legacy_tool_triangles']
    for path in paths:
        source=ROOT/path; raw=source.read_bytes(); doc,_=read(source)
        triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
        positions=[doc['accessors'][p['attributes']['POSITION']] for m in doc['meshes'] for p in m['primitives']]
        manifest.append({'path':path,'triangles':triangles,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
                         'min':[min(a['min'][i] for a in positions) for i in range(3)],'max':[max(a['max'][i] for a in positions) for i in range(3)]})
        metadata=Path(str(source)+'.import').read_text()
        dest=re.search(r'^path="res://(.+)"',metadata,re.M).group(1)
        md5=(ROOT/(dest.removesuffix('.scn')+'.md5')).read_text()
        assert 'source_md5="'+hashlib.md5(raw).hexdigest()+'"' in md5,(path,'stale import')
        if 'res://'+path not in missing:
            if '/items/' in path: new_items+=triangles
            else: new_tools+=triangles
    cost={'matched_items':69,'legacy_item_triangles':old_items,'faceted_matched_item_triangles':new_items,
          'legacy_tool_triangles':old_tools,'faceted_tool_triangles':new_tools,
          'all_new_triangles':sum(r['triangles'] for r in manifest),'all_new_bytes':sum(r['bytes'] for r in manifest)}
    if args.record:
        previous.update(manifest=manifest,cost=cost,current_import_hash_checks=94,inventory_thumbnail_checks=62)
        REPORT.write_text(json.dumps(previous,indent=2)+'\n',encoding='utf-8')
    else:
        assert {current_path(r['path']):r['sha256'] for r in previous['manifest']}=={r['path']:r['sha256'] for r in manifest},'asset fingerprints differ from retained report'
        assert previous['cost']==cost
    print('ITEMS_AUDIT_PASS',json.dumps(cost))


if __name__=='__main__': main()

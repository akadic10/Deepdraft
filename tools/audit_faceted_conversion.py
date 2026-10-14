"""Offline conversion inventory/cost audit; does not modify runtime definitions.

Original geometry costs and hashes come from the retained approval report. Gameplay JSON is
compared with the Git baseline, ignoring only art paths and source palettes.
"""
import hashlib
import json
from pathlib import Path
import subprocess
from faceted_glb import read
from art_asset_paths import current_path
from art_asset_revisions import expected_metrics

ROOT=Path(__file__).resolve().parents[1]

def metrics(path):
    doc,_=read(path)
    return {'triangles':sum(doc['accessors'][p['indices']]['count']//3
                           for m in doc['meshes'] for p in m['primitives']),
            'meshes':len(doc['meshes']),'bytes':path.stat().st_size,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def gameplay(value):
    if isinstance(value,dict):
        return {k:gameplay(v) for k,v in value.items() if k not in ['model','models','model_parts','material_palette'] and not k.startswith('__comment')}
    if isinstance(value,list): return [gameplay(v) for v in value]
    return value

def main():
    approved=json.loads((ROOT/'docs/00_dev_roadmap/concepts/154_family_conversion/audit.json').read_text())
    report={'families':{},'gameplay_definitions_unchanged':[],'approved_exports_identical':[],'recorded_art_revisions':[]}
    for family,folder in [('dwarves','assets/models/characters/dwarves'),('animals','assets/models/animals'),('furniture','assets/models/furniture')]:
        rows={}
        # Tools share the dwarf root; flame libraries share the furniture root.
        # Keep those separately owned assets outside this family inventory.
        pattern='*.glb' if family=='furniture' else '**/*.glb'
        paths={p.relative_to(ROOT/folder).as_posix():p for p in (ROOT/folder).glob(pattern)
               if not (family=='dwarves' and p.relative_to(ROOT/folder).parts[0]=='tools')}
        assert set(paths)==set(approved['families'][family]['parts']),family+' inventory changed'
        for key,path in sorted(paths.items()):
            prior=approved['families'][family]['parts'][key]
            current=metrics(path)
            rel=path.relative_to(ROOT).as_posix()
            expected=expected_metrics(rel,prior['faceted'])
            assert current==expected,str(path)
            if expected!=prior['faceted']: report['recorded_art_revisions'].append(rel)
            rows[key]={'legacy':prior['legacy'],'faceted':current}
        totals={version:{field:sum(v[version][field] for v in rows.values()) for field in ['triangles','meshes','bytes']} for version in ['legacy','faceted']}
        report['families'][family]={'models':len(rows),'totals':totals,'parts':rows}
    for path in list((ROOT/'data/furniture').glob('*.json'))+list((ROOT/'data/entities/animals').glob('*.json')):
        rel=path.relative_to(ROOT).as_posix()
        before=json.loads(subprocess.check_output(['git','show','HEAD:'+rel],cwd=ROOT,encoding='utf-8'))
        after=json.loads(path.read_text(encoding='utf-8'))
        assert gameplay(before)==gameplay(after),rel+' has non-art changes'
        report['gameplay_definitions_unchanged'].append(rel)
    report['approved_exports_identical']=[current_path(p) for p in approved['approved_exports_identical']]
    assert len(report['approved_exports_identical'])==17
    print(json.dumps(report,indent=2))

if __name__=='__main__': main()

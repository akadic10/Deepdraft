"""Exhaustive production coverage, literal references, gameplay data and save guard."""
import hashlib,json,re,zipfile
from pathlib import Path
from common import ROOT
from coverage import expected_paths
from audit import audit_family


def main():
    staged=ROOT/'tmp/voxel_migration_20261018/staged'
    families=['trees','plants','rocks','crops','dwarves','presentation','wildlife','furniture','items','construction']
    reports=[]; installed=set()
    for family in families:
        ledger=ROOT/'data/art/voxel_manifests'/f'{family}.json'
        source=json.loads(ledger.read_text())
        assert source==json.loads((staged/(family+'.json')).read_text()),family+' staged/installed manifest'
        reports.append(audit_family(staged,family))
        paths={r['path'] for r in source['assets']}
        assert paths==expected_paths(family)
        assert not installed&paths,'duplicate owners'
        installed|=paths
        for row in source['assets']:
            assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256'],row['path']
    actual={p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models').rglob('*.glb') if '/studies/' not in p.as_posix()}
    assert actual==installed,{'unowned':sorted(actual-installed),'missing':sorted(installed-actual)}
    references={}; dynamic=[]
    for folder in ('data','scripts','scenes'):
        for p in (ROOT/folder).rglob('*'):
            if p.suffix not in ('.json','.gd','.tscn','.tres'): continue
            for path in re.findall(r'res://assets/models/[^\s"\'\n]+\.glb',p.read_text(encoding='utf-8-sig')):
                if '%' in path: dynamic.append([p.relative_to(ROOT).as_posix(),path]); continue
                assert (ROOT/path.removeprefix('res://')).is_file(),[str(p),path]
                references.setdefault(path,[]).append(p.relative_to(ROOT).as_posix())
    recovery=ROOT/'tmp/voxel_migration_20261018/recovery'
    allowed={'data/entities/animals/wolf.json':{'visual_scale','visual_pose'},
             'data/entities/dwarves/proportions.json':{'body_width','head_width','description'}}
    changes={}
    with zipfile.ZipFile(recovery/'workspace_before.zip') as archive:
        for name in archive.namelist():
            if not name.startswith('data/') or name.startswith('data/art/') or not name.endswith('.json'): continue
            previous=archive.read(name); current=(ROOT/name).read_bytes()
            if previous==current: continue
            before=json.loads(previous); after=json.loads(current)
            fields={k for k in set(before)|set(after) if before.get(k)!=after.get(k)}
            assert name in allowed and fields<=allowed[name],(name,fields)
            changes[name]={k:{'before':before.get(k),'after':after.get(k)} for k in fields}
        assert (ROOT/'project.godot').read_bytes()==archive.read('project.godot')
    saves=[]
    for saved in json.loads((recovery/'player_saves/manifest.json').read_text()):
        observed=hashlib.sha256(Path(saved['source']).read_bytes()).hexdigest()
        assert observed==saved['sha256'],'original player save changed: '+saved['source']
        saves.append({'source':saved['source'],'sha256':observed,'unchanged':True})
    exceptions=[
        {'path':'scripts/components/WorkDustBurst.gd','reason':'Existing bounded noncasting cube MultiMesh dust/chips; transparency and motion are effects.'},
        {'path':'scripts/components/WaterRenderer.gd','reason':'World water/foam remains the existing tile mesh plus bounded noncasting cube MultiMesh.'},
        {'path':'scripts/entities/DuckAgent.gd','reason':'Eight noncasting wake cubes retained as a fading water effect; rigid animal parts migrated.'},
        {'path':'scripts/systems/ItemDropManager.gd','reason':'Missing-model diagnostic BoxMesh retained; production gallery records zero missing models.'},
        {'path':'scripts/components/StorageItemLayout.gd','reason':'Uniform display fitting preserves cubic proportions within storage/cargo; no geometry regeneration.'},
        {'path':'scripts/components/DwarfConstructionPose.gd','reason':'Construction hammer retains its existing uniform 1.1 presentation scale; its grid-authored impact face is verified at the world target.'},
        {'path':'assets/models/studies/','reason':'Historical study and isolated benchmark resources intentionally retained, outside production coverage.'},
    ]
    report={'models':len(installed),'families':reports,'literal_model_references':len(references),'dynamic_references':dynamic,
            'presentation_only_data_changes':changes,'original_saves':saves,'retained_exceptions':exceptions,
            'paths':sorted(installed)}
    out=ROOT/'docs/00_dev_roadmap/concepts/224_voxel_migration/final'
    out.mkdir(parents=True,exist_ok=True)
    (out/'coverage.json').write_text(json.dumps(report,indent=2)+'\n')
    print('VOXEL_FINAL_AUDIT_PASS',len(installed),'models;',len(references),'literal references; gameplay data and originals preserved')


if __name__=='__main__': main()

"""Save a recoverable migration delta without staging or committing user work."""
import argparse,hashlib,json,zipfile
from pathlib import Path
from common import ROOT


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('label')
    args=parser.parse_args()
    assert args.label.replace('_','').replace('-','').isalnum()
    out=ROOT/'tmp/voxel_migration_20261018/checkpoints'; out.mkdir(parents=True,exist_ok=True)
    target=out/(args.label+'.zip'); assert not target.exists(),'checkpoint already exists'
    rows=[]
    candidates=[ROOT/'AGENT.md']
    for folder in ('assets','data','docs','scenes','scripts','tools'):
        candidates.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    with zipfile.ZipFile(ROOT/'tmp/voxel_migration_20261018/recovery/workspace_before.zip') as before,zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=3) as archive:
        old=set(before.namelist())
        for path in sorted(candidates):
            name=path.relative_to(ROOT).as_posix()
            raw=path.read_bytes()
            if name in old and raw==before.read(name): continue
            archive.writestr(name,raw)
            rows.append({'path':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'previously_existed':name in old})
    digest=hashlib.sha256()
    with target.open('rb') as saved:
        for block in iter(lambda:saved.read(1024*1024),b''): digest.update(block)
    report={'label':args.label,'archive':str(target),'archive_sha256':digest.hexdigest(),'files':rows,'note':'Changed/new migration paths only; apply selectively over the preserved recovery snapshot. No deletion, staging or commit performed.'}
    (out/(args.label+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    print('VOXEL_CHECKPOINT_SAVED',args.label,len(rows),'files',target.stat().st_size,'compressed bytes')


if __name__=='__main__': main()

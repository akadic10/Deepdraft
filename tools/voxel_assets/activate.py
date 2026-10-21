"""Activate the exact complete family that passed the native staged gallery."""
import argparse
import json
from pathlib import Path
import shutil
from common import ROOT
from audit import audit_family


def activate(base,family,review_path):
    review=json.loads(review_path.read_text())
    report=audit_family(base,family,review)
    manifest=json.loads((base/(family+'.json')).read_text())
    for row in manifest['assets']:
        target=ROOT/row['path']; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(base/row['path'],target)
    ledger=ROOT/'data/art/voxel_manifests'; ledger.mkdir(parents=True,exist_ok=True)
    (ledger/(family+'.json')).write_text(json.dumps(manifest,indent=2)+'\n')
    (base/(family+'_audit.json')).write_text(json.dumps(report,indent=2)+'\n')
    print('VOXEL_ACTIVATED',family,len(manifest['assets']))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('family')
    parser.add_argument('--base',type=Path,default=ROOT/'tmp/voxel_migration_20261018/staged')
    parser.add_argument('--review',type=Path,required=True)
    args=parser.parse_args()
    activate(args.base,args.family,args.review)

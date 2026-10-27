"""Build staged production voxel assets; --install activates a validated family.

Run from any working directory. --check regenerates in a temporary folder and
compares with the installed production files. No gameplay definitions are written.
"""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
from common import ROOT,export_asset
from coverage import validate_coverage

FAMILIES={}
# Staged-only families: built for review, left out of 'all', never installed (icons: doc 259;
# sky: the Sky Dial's pieces, doc 23). tools/GenerateUiIcons.gd renders both to PNGs.
STAGED_ONLY={'icons','sky'}


def register_families():
    from trees import assets as tree_assets
    from plants import assets as plant_assets
    from rocks import assets as rock_assets
    from crops import assets as crop_assets
    from dwarves import assets as dwarf_assets
    from presentation import assets as presentation_assets
    from wildlife import assets as wildlife_assets
    from furniture import assets as furniture_assets
    from items import assets as item_assets
    from construction import assets as construction_assets
    from icons import assets as icon_assets
    from sky import assets as sky_assets
    FAMILIES['trees']=tree_assets
    FAMILIES['plants']=plant_assets
    FAMILIES['rocks']=rock_assets
    FAMILIES['crops']=crop_assets
    FAMILIES['dwarves']=dwarf_assets
    FAMILIES['presentation']=presentation_assets
    FAMILIES['wildlife']=wildlife_assets
    FAMILIES['furniture']=furniture_assets
    FAMILIES['items']=item_assets
    FAMILIES['construction']=construction_assets
    FAMILIES['icons']=icon_assets
    FAMILIES['sky']=sky_assets


def main():
    register_families()
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('family',choices=[*FAMILIES,'all'])
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--install',action='store_true')
    parser.add_argument('--review',type=Path,help='Required native gallery JSON for installation')
    parser.add_argument('--only',help='Optional substring of a path for authoring previews; cannot install a partial family')
    parser.add_argument('--merge',action='store_true',help='Merge this staged selection into an existing complete family manifest')
    parser.add_argument('--output',type=Path,default=ROOT/'tmp/voxel_migration_20261018/staged')
    args=parser.parse_args()
    if args.check and args.install: parser.error('choose verification or installation')
    if args.only and args.install: parser.error('partial families cannot be installed')
    if args.merge and (not args.only or args.check or args.install): parser.error('--merge requires a staged --only selection')
    if args.install and (not args.review or args.family=='all'): parser.error('install one family with its --review gallery JSON')
    if (args.install or args.check) and args.family in STAGED_ONLY: parser.error(args.family+' is staged for review only')
    families=[f for f in FAMILIES if f not in STAGED_ONLY] if args.family=='all' else [args.family]
    reports={}
    with tempfile.TemporaryDirectory(prefix='deepdraft_voxel_verify_') as temp:
        base=Path(temp) if args.check else args.output.resolve()
        for family in families:
            rows=[]; seen=set()
            for relative,parts,metadata in FAMILIES[family](only=args.only):
                if args.only and args.only not in relative: continue
                if relative in seen: raise ValueError('duplicate asset '+relative)
                seen.add(relative)
                target=base/relative
                row=export_asset(target,parts)
                row.update({'path':relative,'authoring':metadata})
                if args.check:
                    assert target.read_bytes()==(ROOT/relative).read_bytes(),'stale production asset '+relative
                rows.append(row)
                print(relative,sum(p['visual_triangles'] for p in row['parts']),'visual /',
                      sum((p['shadow'] or {}).get('triangles',0) for p in row['parts']),'shadow triangles',flush=True)
            if not rows: raise ValueError('empty selection '+family)
            if args.merge:
                previous=json.loads((base/f'{family}.json').read_text())
                validate_coverage(family,[r['path'] for r in previous['assets']])
                replacements={r['path']:r for r in rows}
                rows=[replacements.pop(r['path'],r) for r in previous['assets']]
                assert not replacements,'selection is outside the complete family'
                validate_coverage(family,[r['path'] for r in rows])
            if not args.only and family not in STAGED_ONLY: validate_coverage(family,seen)
            report={'family':family,'grid':16,'complete':not bool(args.only) or args.merge,'assets':rows}
            reports[family]=report
            if not args.check:
                name=family+('.preview' if args.only and not args.merge else '')
                (base/f'{name}.json').write_text(json.dumps(report,indent=2)+'\n')
            if args.install:
                from activate import activate
                activate(base,family,args.review)
        print('VOXEL_BUILD_OK',','.join(families),'verified' if args.check else 'installed' if args.install else 'staged',sum(len(r['assets']) for r in reports.values()),flush=True)


if __name__=='__main__': main()

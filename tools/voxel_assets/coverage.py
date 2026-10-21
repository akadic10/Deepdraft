"""Frozen migration coverage plus explicitly authored post-migration additions."""
from common import read_json


PREFIXES={
    'trees':('assets/models/flora/trees/',),
    'plants':('assets/models/flora/bushes/','assets/models/flora/flowers/','assets/models/flora/reeds/'),
    'rocks':('assets/models/rocks/',),
    'dwarves':('assets/models/characters/',),
    'wildlife':('assets/models/animals/',),
    'furniture':('assets/models/furniture/',),
    'items':('assets/models/items/',),
    'construction':('assets/models/construction/',),
}


def expected_paths(family):
    if family=='presentation': return {'assets/models/presentation/'+key+'.glb' for key in read_json('data/art/voxel_presentation.json')['parts']}
    baseline=read_json('docs/00_dev_roadmap/concepts/223_voxel_migration_plan/inventory.json')
    if family=='crops': return {r['path'] for r in baseline['missing_defined_models']}
    additions=read_json('data/art/voxel_additions.json').get(family,[])
    assert len(additions)==len(set(additions)) and all(p.startswith(PREFIXES[family]) for p in additions)
    retired=set(read_json('data/content_retirements.json')['assets'])
    return ({r['path'] for r in baseline['assets'] if r['path'].startswith(PREFIXES[family])}|set(additions))-retired


def validate_coverage(family,paths):
    expected=expected_paths(family)
    actual=set(paths)
    if expected!=actual:
        raise ValueError(f'{family}: missing {sorted(expected-actual)}; unexpected {sorted(actual-expected)}')
    return len(actual)

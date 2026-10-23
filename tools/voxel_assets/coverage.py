"""Expected model paths per family, from tools/art_data/voxel_expected.json."""
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
    if family=='presentation': return {'assets/models/presentation/'+key+'.glb' for key in read_json('tools/art_data/voxel_presentation.json')['parts']}
    paths=read_json('tools/art_data/voxel_expected.json')['families'][family]
    assert len(paths)==len(set(paths)) and (family=='crops' or all(p.startswith(PREFIXES[family]) for p in paths))
    return set(paths)


def validate_coverage(family,paths):
    expected=expected_paths(family)
    actual=set(paths)
    if expected!=actual:
        raise ValueError(f'{family}: missing {sorted(expected-actual)}; unexpected {sorted(actual-expected)}')
    return len(actual)

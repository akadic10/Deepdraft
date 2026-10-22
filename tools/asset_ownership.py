"""Keep production art owned by tools/voxel_assets: no other writer may overwrite or
recreate a model listed in a family manifest or retired in data/content_retirements.json."""
from functools import lru_cache
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


@lru_cache(maxsize=1)
def voxel_owned_paths():
    return {row['path'] for ledger in (ROOT/'data/art/voxel_manifests').glob('*.json')
            for row in json.loads(ledger.read_text())['assets']} | set(json.loads((ROOT/'data/content_retirements.json').read_text())['assets'])


def guard_legacy_write(path):
    try: relative=Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError: return
    if relative in voxel_owned_paths():
        raise RuntimeError(f'{relative} is owned by tools/voxel_assets/build.py; '
                           'another writer cannot overwrite or recreate it')

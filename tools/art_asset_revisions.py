"""Recorded follow-up art changes used by offline historical-baseline audits."""
import json
from pathlib import Path
from art_asset_paths import current_path

ROOT = Path(__file__).resolve().parents[1]


def expected_metrics(path, original):
    revisions = json.loads((ROOT/'data/art/asset_revisions.json').read_text(encoding='utf-8'))
    revision = revisions.get(current_path(path))
    if revision is None:
        return original
    # An override must identify the exact original export it supersedes. All
    # other models still match the original report; revised files also retain
    # strict geometry/byte fingerprints rather than being skipped by audits.
    assert original['sha256'] in [revision['previous_sha256'], revision['metrics']['sha256']], path
    return {**original, **revision['metrics']}

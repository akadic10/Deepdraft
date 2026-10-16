"""Retain seasonal measurements and code; never copy runtime user profiles."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "tmp/seasons_20261015"
DEST = ROOT / "docs/00_dev_roadmap/concepts/seasons_20261015"
SOURCES = [
    "scripts/components/SeasonalRefreshQueue.gd",
    "scripts/systems/WorldClock.gd",
    "scripts/systems/SurfaceFloraSpawner.gd",
    "scripts/systems/SurfaceDetailManager.gd",
    "scripts/systems/WorldRenderer.gd",
    "scripts/tests/SeasonalRefreshTest.gd",
    "scripts/tests/TreeFellingTest.gd",
    "scripts/tests/ObjectExplorerTest.gd",
    "scripts/tests/JuniperHarvestTest.gd",
    "tools/performance/SeasonBenchmark.gd",
    "tools/performance/RunSeason.ps1",
    "tools/performance/SmokeSeasonExport.gd",
    "tools/performance/CollectSeasonEvidence.py",
]


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = {"final_sources": {}, "runs": {}}
    for name in SOURCES:
        source = ROOT / name
        copy(source, DEST / "sources/final" / (name + ".txt"))
        manifest["final_sources"][name] = sha(source)
    for source in SCRATCH.glob("*.before.txt"):
        copy(source, DEST / "sources/before" / source.name)
    for source in SCRATCH.glob("*.final.txt"):
        copy(source, DEST / "sources/first_trial" / source.name)
    for run in sorted((ROOT / "tmp/performance_20261014").glob("season_*")):
        if not (run / "season.json").exists():
            continue
        for name in ["season.json", "season_frames.json", "report.json", "run.json", "run.out", "run.err"]:
            copy(run / name, DEST / "runs" / run.name / name)
        data = json.loads((run / "season.json").read_text(encoding="utf-8"))
        manifest["runs"][run.name] = {
            "frames": data["frames"], "clock": data["process"]["WorldClock"],
            "minimum_trees": data["minimum_trees"],
            "input": json.loads((run / "run.json").read_text(encoding="utf-8-sig")),
        }
    for folder in ["fixture_v1", "fixture_v2", "fixture_v3", "regressions", "regressions_final", "package"]:
        source = SCRATCH / folder
        if not source.exists():
            continue
        for item in source.iterdir():
            if item.is_file() and item.suffix in [".out", ".err", ".json", ".png"]:
                copy(item, DEST / folder / item.name)
    for name in ["package_audit.json", "RunChecks.ps1"]:
        source = SCRATCH / name
        if source.exists(): copy(source, DEST / (name + ".txt" if source.suffix == ".ps1" else name))
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(manifest["runs"], indent=2))


if __name__ == "__main__":
    collect()

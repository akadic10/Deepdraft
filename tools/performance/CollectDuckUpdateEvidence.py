"""Retain native duck-update measurements, validation and source provenance."""
import gzip
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "tmp/duck_updates_20261015"
DEST = ROOT / "docs/00_dev_roadmap/concepts/duck_updates_20261015"
RUNS = ["duck_update_before_detail", "duck_update_after_detail", "duck_update_before_plain",
        "duck_update_after_plain_a", "duck_update_after_plain_b"]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def clean_log(path):
    assert not re.search(r"^ERROR:|^SCRIPT ERROR:", path.read_text(encoding="utf-8"), re.M), path


def main():
    summary = {}
    for name in RUNS:
        source = ROOT / "tmp/performance_20261014" / name
        target = DEST / name
        run = read(source / "run.json")
        report = read(source / "report.json")
        assert run["exit_code"] == 0 and run["source_save_unchanged"]
        assert not report["lifecycle_errors"]
        clean_log(source / "run.err")
        assert "CAMERA_BENCHMARK_PASS" in (source / "run.out").read_text()
        for file in ["run.json", "report.json", "run.out", "run.err"]:
            copy(source / file, target / file)
        summary[name] = {}
        for mode, phase in report["phases"].items():
            raw_path = source / (mode + "_frames.json")
            raw = raw_path.read_bytes()
            assert len(json.loads(raw)) == phase["frames"]
            assert phase["calendar_seconds_per_hour"] == 60
            assert phase["final"]["clock"]["speed"] == 1
            assert phase["lighting_final"]["actors"] == 30
            assert phase["final"]["wildlife"] == 79
            (target / (raw_path.name + ".gz")).write_bytes(gzip.compress(raw, mtime=0))
            summary[name][mode] = {key: phase[key] for key in ["frame_ms", "gpu_ms", "detail", "process", "frames"]}
            summary[name][mode]["raw_sha256"] = sha(raw_path)
            summary[name][mode]["work_delta"] = {key: phase["final"][key]-phase["initial"][key] for key in ["mined", "built", "stored", "loose"]}
        folder = source / "instrumentation"
        if folder.exists():
            manifest = read(folder / "instrumentation.json")
            restored = read(folder / "restored.json")
            for path, info in manifest.items():
                assert info["before"] == restored[path], path
            for file in folder.iterdir(): copy(file, target / "instrumentation" / file.name)
    (DEST / "summary.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    fixtures = []
    for label in ["focused", "regressions"]:
        results = read(SCRATCH / label / "results.json")
        assert all(item["clean"] and item["exit"] == 0 for item in results)
        fixtures += results
        for file in (SCRATCH / label).rglob("*"):
            if file.is_file() and "profile" not in file.parts:
                copy(file, DEST / label / file.relative_to(SCRATCH / label))
    copy(SCRATCH / "solid_bounds.json", DEST / "solid_bounds.json")
    assert not read(SCRATCH / "solid_bounds.json")["failures"]
    differential_log = (SCRATCH / "focused/DuckQueryReuseTest/run.out").read_text(encoding="utf-8")
    differential = json.loads(next(line.removeprefix("DUCK_QUERY_REUSE_PASS ") for line in differential_log.splitlines() if line.startswith("DUCK_QUERY_REUSE_PASS ")))
    assert differential["compared_ticks"] == 1200 and not differential["failures"]
    (DEST / "query_reuse.json").write_text(json.dumps(differential, indent=2)+"\n", encoding="utf-8")
    packed = read(SCRATCH / "packed/checks.json")
    assert not packed["failures"]
    clean_log(SCRATCH / "packed/run.err")
    clean_log(SCRATCH / "startup.err")
    assert "DUCK_UPDATES_EXPORT_PASS" in (SCRATCH / "packed/run.out").read_text()
    assert "built block-face overview tiles (1024 tiles" in (SCRATCH / "startup.out").read_text()
    for file in (SCRATCH / "packed").iterdir():
        if file.is_file(): copy(file, DEST / "packed" / file.name)
    for attempt in ["packed_first", "packed_precision_diagnosis"]:
        for file in (SCRATCH / attempt).iterdir():
            if file.is_file(): copy(file, DEST / attempt / file.name)
    for file in ["package.json", "startup.out", "startup.err", "sources_before.json", "RunChecks.ps1", "RunControls.ps1", "CheckPackage.ps1"]:
        copy(SCRATCH / file, DEST / file)
    before = read(SCRATCH / "sources_before.json")
    differences = {path: {"before": value, "after": sha(ROOT / path)} for path, value in before.items() if sha(ROOT / path) != value}
    assert set(differences) == {"scripts/components/AnimalNavigation.gd", "scripts/components/DuckNavigation.gd"}, differences
    for name in ["AnimalNavigation", "DuckNavigation"]:
        copy(SCRATCH / (name + ".gd.before.txt"), DEST / (name + ".before.txt"))
        copy(ROOT / "scripts/components" / (name + ".gd"), DEST / (name + ".after.txt"))
    save = Path("C:/Users/akadi/AppData/Roaming/Godot/app_userdata/Deepdraft/saves/quicksave.json")
    assert sha(save) == sha(SCRATCH / "input_quicksave.json") == "f223eee6dfe52fefe6add9a763362640f02c439fb2f33687f550661fb9cc148b"
    package = read(SCRATCH / "package.json")
    assert sha(Path(package["zip"])) == package["zip_sha256"]
    audit = {"existing_sources_checked": len(before), "changed_sources": differences,
             "original_save_sha256": sha(save), "fixtures": fixtures, "packed": packed, "package": package}
    (DEST / "audit.json").write_text(json.dumps(audit, indent=2)+"\n", encoding="utf-8")
    print("DUCK_UPDATE_EVIDENCE_PASS", len(fixtures), "fixtures", packed["checks"], "packed checks")


if __name__ == "__main__":
    main()

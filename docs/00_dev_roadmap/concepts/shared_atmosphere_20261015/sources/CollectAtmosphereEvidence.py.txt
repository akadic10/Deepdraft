"""Retain shared-atmosphere measurements, checks and source provenance for 196."""
import gzip
import hashlib
import json
import re
import shutil
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "tmp/shared_atmosphere_20261015"
DEST = ROOT / "docs/00_dev_roadmap/concepts/shared_atmosphere_20261015"
RUNS = ["atmosphere_plain_a", "atmosphere_plain_b", "atmosphere_detail", "atmosphere_baseline_repeat"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def main():
    summary = {}
    for name in RUNS:
        source = ROOT / "tmp/performance_20261014" / name
        target = DEST / name
        meta = read(source / "run.json")
        report = read(source / "report.json")
        assert meta["exit_code"] == 0 and meta["source_save_unchanged"]
        assert not report["lifecycle_errors"]
        assert "CAMERA_BENCHMARK_PASS" in (source / "run.out").read_text(encoding="utf-8")
        assert not re.search(r"^ERROR:|^SCRIPT ERROR:", (source / "run.err").read_text(encoding="utf-8"), re.M)
        for filename in ["report.json", "run.json", "run.out", "run.err"]:
            copy(source / filename, target / filename)
        summary[name] = {}
        for mode, phase in report["phases"].items():
            raw_path = source / (mode + "_frames.json")
            raw = raw_path.read_bytes()
            rows = json.loads(raw)
            assert len(rows) == phase["frames"]
            assert phase["calendar_seconds_per_hour"] == 60
            assert phase["lighting_final"]["actors"] == 30
            assert phase["final"]["wildlife"] == 79
            (target / (raw_path.name + ".gz")).write_bytes(gzip.compress(raw, mtime=0))
            stats = {key: phase[key] for key in ["frame_ms", "gpu_ms", "render_setup_ms", "detail", "lighting_final"]}
            stats["work_delta"] = {key: phase["final"][key] - phase["initial"][key] for key in ["mined", "built", "stored", "loose"]}
            stats["clock"] = {"initial": phase["initial"]["clock"], "final": phase["final"]["clock"]}
            stats["raw_sha256"] = sha(raw_path)
            stats["pipelines"] = {key: sum(r["pipelines"][key] for r in rows) for key in rows[0]["pipelines"]}
            stats["shared_updates"] = sum(r["detail"].get("fog/shared_texture_updates", 0) for r in rows)
            stats["material_writes"] = sum(r["detail"].get("fog/material_parameter_writes", 0) for r in rows)
            stats["seconds"] = phase["seconds"]
            summary[name][mode] = stats
            if name == "atmosphere_detail":
                assert stats["shared_updates"] > 0 and stats["material_writes"] == 0
        if (source / "instrumentation").exists():
            manifest = read(source / "instrumentation/instrumentation.json")
            for path, info in manifest.items():
                assert sha(ROOT / path) == info["before"], path
            for file in (source / "instrumentation").iterdir(): copy(file, target / "instrumentation" / file.name)
    before_runs = [read(ROOT / "tmp/performance_20261014" / name / "report.json") for name in ["steady_render_plain_a", "steady_render_plain_b"]]
    comparison = {}
    for mode in summary[RUNS[0]]:
        comparison[mode] = {}
        for metric, stat in [("frame_ms", "mean"), ("frame_ms", "p95"), ("render_setup_ms", "mean"), ("gpu_ms", "mean")]:
            before = statistics.mean(r["phases"][mode][metric][stat] for r in before_runs)
            after = statistics.mean(summary[name][mode][metric][stat] for name in RUNS[:2])
            comparison[mode][metric + "/" + stat] = {"before": before, "after": after, "reduction_percent": 100 * (1 - after / before)}
    (DEST / "summary.json").write_text(json.dumps({"runs": summary, "comparison": comparison}, indent=2) + "\n", encoding="utf-8")
    before = read(SCRATCH / "production_before.json")
    differences = {path: {"before": value, "after": sha(ROOT / path)} for path, value in before.items() if sha(ROOT / path) != value}
    assert set(differences) == {"scripts/components/UndergroundLighting.gd", "scripts/shaders/underground_lighting.gdshader"}, differences
    player_save = Path("C:/Users/akadi/AppData/Roaming/Godot/app_userdata/Deepdraft/saves/quicksave.json")
    assert sha(player_save) == sha(SCRATCH / "input_quicksave.json")
    audit = {"existing_scripts_and_shaders_checked": len(before), "changed": differences, "player_save_sha256": sha(player_save), "source_hashes": {}}
    paths = ["scripts/components/UndergroundLighting.gd", "scripts/components/SceneAtmosphereData.gd", "scripts/shaders/underground_lighting.gdshader", "scripts/tests/AtmosphereSharingTest.gd",
             "tools/performance/InstrumentRendering.py", "tools/performance/SteadyRenderingBenchmark.gd", "tools/performance/RunSteadyRendering.ps1", "tools/performance/SmokeAtmosphereExport.gd", "tools/performance/CollectAtmosphereEvidence.py"]
    for path in paths:
        copy(ROOT / path, DEST / "sources" / (Path(path).name + ".txt"))
        audit["source_hashes"][path] = sha(ROOT / path)
    for name in ["production_before.json", "UndergroundLighting.gd.before.txt", "RunChecks.ps1", "RepeatBaseline.ps1", "CheckPackage.ps1"]:
        copy(SCRATCH / name, DEST / name)
    tests = read(SCRATCH / "regressions/results.json")
    assert len(tests) == 9 and all(t["clean"] for t in tests)
    copy(SCRATCH / "regressions/results.json", DEST / "regressions/results.json")
    captures = {
        "UndergroundLightingTest": ["checks.json", "unlit.png", "torches.png"],
        "TunnelEntranceTest": ["entrance_checks.json", "entrance_after.png"],
        "RoomLightingTest": ["checks.json", "closed_unlit.png", "lit_room.png"],
        "DoorLightingTest": ["checks.json"],
        "DwarfLimbLightingTest": ["after.json", "after.png", "after_torch.png"],
    }
    for test in tests:
        fixture_dir = SCRATCH / test.get("evidence_path", "regressions/" + test["test"])
        for file in fixture_dir.glob("run.*"):
            copy(file, DEST / "regressions" / test["test"] / file.name)
        for filename in captures.get(test["test"], []):
            file = fixture_dir / "captures" / filename
            copy(file, DEST / "regressions" / test["test"] / file.name)
    for file in (SCRATCH / "regressions/DwarfLimbLightingTest").glob("run.*"):
        copy(file, DEST / "regressions/DwarfLimbLightingTest/initial_profile_path_error" / file.name)
    for name in ["parity", "packed"]:
        assert not read(SCRATCH / name / "checks.json")["failures"]
        for file in (SCRATCH / name).iterdir():
            if file.is_file() and file.suffix in [".json", ".out", ".err", ".png"]: copy(file, DEST / name / file.name)
    copy(SCRATCH / "package.json", DEST / "package.json")
    startup = (SCRATCH / "startup.out").read_text(encoding="utf-8")
    assert "built block-face overview tiles (1024 tiles" in startup
    assert not re.search(r"^ERROR:|^SCRIPT ERROR:", (SCRATCH / "startup.err").read_text(encoding="utf-8"), re.M)
    for name in ["startup.out", "startup.err"]: copy(SCRATCH / name, DEST / name)
    (DEST / "audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(comparison, indent=2))
    print("SHARED_ATMOSPHERE_EVIDENCE_PASS")


if __name__ == "__main__":
    main()

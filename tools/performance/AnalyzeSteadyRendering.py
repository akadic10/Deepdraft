"""Summarize normal-speed runs and retain compact, reproducible evidence."""
import gzip
import hashlib
import json
import re
import shutil
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "tmp/steady_rendering_20261015"
DEST = ROOT / "docs/00_dev_roadmap/concepts/steady_rendering_20261015"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect():
    DEST.mkdir(parents=True, exist_ok=True)
    summary = {}
    for run in sorted((ROOT / "tmp/performance_20261014").glob("steady_render_*")):
        if not (run / "run.json").exists():
            continue
        target = DEST / "runs" / run.name
        target.mkdir(parents=True, exist_ok=True)
        for filename in ["report.json", "run.json", "run.out", "run.err"]:
            if (run / filename).exists(): shutil.copy2(run / filename, target / filename)
        report = json.loads((run / "report.json").read_text(encoding="utf-8")) if (run / "report.json").exists() else {}
        runmeta = json.loads((run / "run.json").read_text(encoding="utf-8-sig"))
        assert runmeta["exit_code"] == 0 and runmeta["source_save_unchanged"], run.name
        assert "CAMERA_BENCHMARK_PASS" in (run / "run.out").read_text(encoding="utf-8")
        assert not re.search(r"^SCRIPT ERROR:|^ERROR:", (run / "run.err").read_text(encoding="utf-8"), re.M)
        assert report["counts"]["dwarves"] == 30 and report["counts"]["wildlife"] == 79
        assert not report["lifecycle_errors"]
        assert set(report["phases"]) == {"active_static", "active_pan", "active_pan_repeat"}
        summary[run.name] = {"exit_code":runmeta["exit_code"], "source_save_unchanged":runmeta["source_save_unchanged"],
                             "resolution":report.get("resolution"), "markers":report.get("markers"), "phases":{}}
        for mode, phase in report.get("phases", {}).items():
            source = run / (mode + "_frames.json")
            raw = source.read_bytes()
            (target / (source.name + ".gz")).write_bytes(gzip.compress(raw, mtime=0))
            assert gzip.decompress((target / (source.name + ".gz")).read_bytes()) == raw
            rows = json.loads(raw)
            stats = {key:phase[key] for key in ["frames", "seconds", "frame_ms", "gpu_ms", "render_cpu_ms", "render_setup_ms", "process_ms", "draw_ms", "draw_calls", "primitives", "lighting_initial", "lighting_final"]}
            stats["top_process"] = sorted(phase["process"].items(), key=lambda kv:kv[1]["mean"], reverse=True)[:12]
            stats["detail"] = phase["detail"]
            stats["work_delta"] = {key:phase["final"][key]-phase["initial"][key] for key in ["mined", "built", "stored", "loose", "wildlife"]}
            stats["clock"] = {"initial":phase["initial"]["clock"], "final":phase["final"]["clock"], "seconds_per_hour":phase["calendar_seconds_per_hour"]}
            stats["spikes"] = sorted(rows, key=lambda row:row["frame_ms"], reverse=True)[:8]
            stats["pipeline_compilations"] = {key:sum(row["pipelines"][key] for row in rows) for key in rows[0]["pipelines"]}
            stats["raw_sha256"] = hashlib.sha256(raw).hexdigest()
            stats["raw_rows"] = len(rows)
            assert len(rows) == phase["frames"]
            assert phase["calendar_seconds_per_hour"] == 60
            assert phase["initial"]["clock"]["speed"] == 1
            assert phase["lighting_final"]["actors"] == 30 and phase["final"]["wildlife"] == 79
            summary[run.name]["phases"][mode] = stats
        if (run / "instrumentation").exists():
            for source in (run / "instrumentation").iterdir():
                shutil.copy2(source, target / source.name)
    (DEST / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    before = json.loads((SCRATCH / "production_before.json").read_text(encoding="utf-8"))
    differences = {path:{"before":value, "now":sha(ROOT/path)} for path,value in before.items() if value != sha(ROOT/path)}
    assert not differences, differences
    source_save = Path("C:/Users/akadi/AppData/Roaming/Godot/app_userdata/Deepdraft/saves/quicksave.json")
    audit = {"production_gd_files_checked":len(before), "production_sources_unchanged":not differences,
             "player_save_sha256":sha(source_save), "input_save_sha256":sha(SCRATCH/"input_quicksave.json"), "tools":{}}
    assert audit["player_save_sha256"] == audit["input_save_sha256"]
    for name in ["SteadyRenderingBenchmark.gd", "RenderProfile.gd", "InstrumentRendering.py", "RunSteadyRendering.ps1", "AnalyzeSteadyRendering.py", "FogBroadcastSwitch.gd", "FogBroadcastBenchmark.gd", "RunFogBroadcast.ps1"]:
        source = ROOT / "tools/performance" / name
        target = DEST / "sources" / (name + ".txt")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        audit["tools"][name] = sha(source)
    shutil.copy2(SCRATCH / "production_before.json", DEST / "production_sources.json")
    (DEST / "audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    intervention = ROOT / "tmp/performance_20261014/fog_broadcast_probe"
    if (intervention / "run.json").exists():
        target = DEST / "fog_intervention"
        target.mkdir(parents=True, exist_ok=True)
        for source in intervention.iterdir():
            if source.is_file() and source.suffix in [".json", ".out", ".err"]: shutil.copy2(source, target / source.name)
        for source in (intervention / "instrumentation").iterdir(): shutil.copy2(source, target / source.name)
        data = json.loads((intervention / "fog_intervention.json").read_text(encoding="utf-8"))
        meta = json.loads((intervention / "run.json").read_text(encoding="utf-8-sig"))
        assert meta["exit_code"] == 0 and meta["source_save_unchanged"]
        assert "FOG_BROADCAST_INTERVENTION_PASS" in (intervention / "run.out").read_text(encoding="utf-8")
        assert not re.search(r"^SCRIPT ERROR:|^ERROR:", (intervention / "run.err").read_text(encoding="utf-8"), re.M)
        assert data["calendar_seconds_per_hour"] == 60 and data["lighting"]["actors"] == 30
        assert data["final"]["wildlife"] == 79
        groups = {}
        for frozen in [False, True]:
            rows = [r for block in data["blocks"] if block["frozen"] == frozen for r in block["rows"]]
            stats = {"frames":len(rows)}
            for key in ["frame_ms", "process_ms", "gpu_ms", "render_setup_ms"]:
                values = sorted(r[key] for r in rows)
                stats[key] = {"mean":statistics.mean(values), "p95":values[int((len(values)-1)*.95)], "max":max(values)}
            stats["fog_cpu_mean_ms"] = statistics.mean(r["detail"].get("UndergroundLighting/_sync_fog",0) for r in rows)
            stats["fog_material_writes"] = sum(r["detail"].get("fog/material_parameter_writes",0) for r in rows)
            groups["frozen" if frozen else "live"] = stats
        assert groups["frozen"]["fog_material_writes"] == 0
        assert groups["live"]["fog_material_writes"] > 0
        groups["blocks"] = [{"index":b["index"], "frozen":b["frozen"], **{k:statistics.mean(r[k] for r in b["rows"]) for k in ["frame_ms", "gpu_ms", "render_setup_ms"]}} for b in data["blocks"]]
        groups["pipeline_compilations"] = {key:sum(r["pipelines"][key] for b in data["blocks"] for r in b["rows"]) for key in data["blocks"][0]["rows"][0]["pipelines"]}
        groups["reduction_percent"] = {"mean_frame":100*(1-groups["frozen"]["frame_ms"]["mean"]/groups["live"]["frame_ms"]["mean"]),
                                      "p95_frame":100*(1-groups["frozen"]["frame_ms"]["p95"]/groups["live"]["frame_ms"]["p95"]),
                                      "render_setup":100*(1-groups["frozen"]["render_setup_ms"]["mean"]/groups["live"]["render_setup_ms"]["mean"])}
        (target / "comparison.json").write_text(json.dumps(groups, indent=2)+"\n", encoding="utf-8")
        print("FOG_INTERVENTION",json.dumps(groups))
    archive_runs = list((DEST / "runs").iterdir())
    if (DEST / "fog_intervention/report.json").exists(): archive_runs.append(DEST / "fog_intervention")
    for run in archive_runs:
        report = json.loads((run / "report.json").read_text(encoding="utf-8"))
        if (run / "instrumentation.json").exists():
            snapshot = json.loads((run / "instrumentation.json").read_text(encoding="utf-8"))
            restored = json.loads((run / "restored.json").read_text(encoding="utf-8"))
            for path, meta in snapshot.items():
                assert report["source_hashes"][path] == meta["instrumented"]
                assert sha(run / (Path(path).name + ".instrumented.txt")) == meta["instrumented"]
                assert sha(run / meta["backup"]) == meta["before"]
                assert restored[path] == meta["before"] == sha(ROOT / path)
        else:
            for path, digest in report["source_hashes"].items():
                if path.startswith("scripts/"): assert digest == sha(ROOT / path)
    audit.update({"native_runs_passed":len(archive_runs), "normal_sampled_phases":sum(len(v["phases"]) for v in summary.values()),
                  "compressed_rows_verified":True, "instrumentation_hashes_verified":True,
                  "normal_pipeline_compilations":{key:sum(p["pipeline_compilations"][key] for r in summary.values() for p in r["phases"].values()) for key in ["canvas", "draw", "mesh", "specialization", "surface"]}})
    (DEST / "audit.json").write_text(json.dumps(audit, indent=2)+"\n", encoding="utf-8")
    print("FINAL_PROFILE_AUDIT_PASS", len(archive_runs), "native runs", audit["normal_sampled_phases"], "phases", len(before), "production files unchanged")
    for run, data in summary.items():
        print(run, data["resolution"], "exit", data["exit_code"])
        for mode, phase in data["phases"].items():
            print(" ", mode, "frame", round(phase["frame_ms"]["mean"],3), "p95", round(phase["frame_ms"]["p95"],3),
                  "max",round(phase["frame_ms"]["max"],3), "gpu",round(phase["gpu_ms"]["mean"],3), "work", phase["work_delta"])
            for key, value in phase["detail"].items():
                if not key.endswith("/calls"): print("    ", key, round(value["mean"],3), round(value["max"],3))


if __name__ == "__main__":
    collect()

"""Preserve flow-update and whole-frame timings from sequential native runs."""
import argparse
import json
import shutil
from pathlib import Path


def stats(values):
    values = sorted(values)
    count = len(values)
    return {"count": count, "mean": sum(values) / count,
            "p95": values[int((count - 1) * .95)],
            "p99": values[int((count - 1) * .99)], "max": values[-1]}


def extract(folder, output):
    report = json.loads((folder / "report.json").read_text())
    for name in ("report.json", "run.json"):
        shutil.copyfile(folder / name, output / (folder.name + "_" + name))
    result = {"run": folder.name, "flow_sha256": report["water_flow_sha256"], "phases": {}}
    for name in ("active_pan", "active_pan_repeat"):
        rows = json.loads((folder / (name + "_frames.json")).read_text())
        phase = report["phases"][name]
        active = [row for row in rows if row["process"].get("water_sim/total", 0) > 0]
        result["phases"][name] = {
            "frame_ms": phase["frame_ms"], "frames": phase["frames"], "seconds": phase["seconds"],
            "water_updates": {
                stage: stats([row["process"].get("water_sim/" + stage, 0) for row in active])
                for stage in ("total", "flow", "moisture", "changes", "sources", "notifications")},
            "water_cpu_ms_per_second": sum(row["process"]["water_sim/total"] for row in active) / phase["seconds"]}
        owners = {"WaterManager", "RoomManager", "MoistureRenderer", "DebugWorld/Renderer", "DebugWorld/WildlifeManager"}
        compact = [{"frame_ms": row["frame_ms"], "scene_ms": row["scene_ms"], "gpu_ms": row["gpu_ms"],
                    "process": {key: value for key, value in row["process"].items()
                                if key in owners or key.startswith(("water_sim/", "water_render/", "wildlife/"))}}
                   for row in rows]
        (output / (folder.name + "_" + name + ".json")).write_text(json.dumps(compact) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("before_fresh", "before_saved", "after_fresh", "after_saved", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = {name: extract(getattr(args, name), args.output)
              for name in ("before_fresh", "before_saved", "after_fresh", "after_saved")}
    (args.output / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
    for name, data in result.items():
        for phase, values in data["phases"].items():
            print(name, phase,
                  "frame mean/P95/P99/max", [round(values["frame_ms"][key], 3) for key in ("mean", "p95", "p99", "max")],
                  "water mean/P95/max", [round(values["water_updates"]["total"][key], 3) for key in ("mean", "p95", "max")],
                  "flow mean", round(values["water_updates"]["flow"]["mean"], 3))

"""Compare completed, sequential native runs. No external Python packages needed."""
import argparse
import json
from pathlib import Path


def stats(values):
    values = sorted(values)
    n = len(values)
    return {"count": n, "mean": sum(values) / n, "p95": values[int((n - 1) * .95)],
            "p99": values[int((n - 1) * .99)], "max": values[-1]}


def extract(path):
    report = json.loads((path / "report.json").read_text())
    result = {"run": str(path), "source": {k: v for k, v in report.items() if k.endswith("sha256")}, "phases": {}}
    for name in ["active_pan", "active_pan_repeat"]:
        phase = report["phases"][name]
        rows = json.loads((path / (name + "_frames.json")).read_text())
        item = {"frame_ms": phase["frame_ms"], "seconds": phase["seconds"], "frames": phase["frames"], "stages": {}}
        for stage in ["motion", "texture", "splash", "mesh", "total"]:
            values = [r["process"]["water_render/" + stage] for r in rows]
            item["stages"][stage] = {**stats(values), "cpu_ms_per_wall_second": sum(values) / phase["seconds"]}
            if stage == "motion":
                active = [v for v in values if v > .05]
                item["stages"][stage]["working_frames"] = stats(active) if active else {}
        if "water_motion" in rows[0]:
            item["motion_pending"] = stats([r["water_motion"]["pending"] for r in rows])
            item["motion_latency_ms"] = stats([r["water_motion"]["latency_ms"] for r in rows])
            item["motion_age_ms"] = stats([r["water_motion"]["age_ms"] for r in rows])
        result["phases"][name] = item
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--before-fresh", type=Path, required=True)
    parser.add_argument("--after-fresh", type=Path, required=True)
    parser.add_argument("--before-saved", type=Path, required=True)
    parser.add_argument("--after-saved", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {key: extract(getattr(args, key)) for key in ["before_fresh", "after_fresh", "before_saved", "after_saved"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    for key, run in result.items():
        for name, phase in run["phases"].items():
            print(key, name, "frame mean/P95/P99/max:", [round(phase["frame_ms"][k], 3) for k in ["mean", "p95", "p99", "max"]],
                  "motion max:", phase["stages"]["motion"]["max"], "water render max:", phase["stages"]["total"]["max"])

"""Preserve before/after frame-pacing evidence; matplotlib is needed for the chart."""
import argparse
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--additional", nargs="*", type=Path, default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    comparison = {}
    for run in [args.before, args.after, *args.additional]:
        report = json.loads((run / "report.json").read_text())
        shutil.copyfile(run / "report.json", args.output / f"{run.name}_report.json")
        shutil.copyfile(run / "run.json", args.output / f"{run.name}_run.json")
        comparison[run.name] = {
            phase: {key: data[key] for key in ["frames", "seconds", "frame_ms", "gpu_ms", "process", "water_mesh_start", "water_mesh_end", "water_mesh"] if key in data}
            for phase, data in report["phases"].items() if phase in ["active_static", "active_pan", "active_pan_repeat"]
        }
    (args.output / "comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    fig, (trace, bars) = plt.subplots(2, 1, figsize=(10, 7.5), gridspec_kw={"height_ratios": [1.4, 1]})
    fig.suptitle("Water mesh construction moves off the main thread", x=.08, ha="left", fontsize=16, weight="bold")
    fig.text(.08, .93, "Copied five-dwarf settlement · 2560×1440 · real-time native Godot runs", color="#475569")
    colors = ["#9b4a41", "#247c9a"]
    timings = []
    for run, label, color in zip([args.before, args.after], ["Before", "After"], colors):
        rows = json.loads((run / "active_pan_frames.json").read_text())
        values = np.array([row["frame_ms"] for row in rows])
        elapsed = np.cumsum(values) / 1000
        trace.plot(elapsed, values, color=color, alpha=.8, linewidth=1, label=label)
        timings.append(comparison[run.name]["active_pan"]["frame_ms"])
    trace.axhline(1000/60, color="#475569", linestyle="--", linewidth=1, label="60 FPS budget")
    trace.set(xlabel="Seconds during camera pan", ylabel="Frame interval (ms)", ylim=(0, None))
    trace.legend(loc="upper right", ncol=3)
    trace.grid(axis="y", alpha=.2)
    x = np.arange(3)
    for i, (label, timing, color) in enumerate(zip(["Before", "After"], timings, colors)):
        values = [timing[key] for key in ["mean", "p95", "p99"]]
        series = bars.bar(x+(i-.5)*.33, values, .33, label=label, color=color)
        bars.bar_label(series, labels=[f"{v:.1f}" for v in values], padding=3)
    bars.set(xticks=x, xticklabels=["Mean", "P95", "P99"], ylabel="Frame interval (ms)")
    bars.axhline(1000/60, color="#475569", linestyle="--", linewidth=1)
    bars.grid(axis="y", alpha=.2)
    bars.set_ylim(0, max(t["p99"] for t in timings)*1.2)
    for axis in [trace, bars]:
        axis.spines[["top", "right"]].set_visible(False)
    fig.text(.08, .025, "Water simulation, wildlife and visual detail remain enabled. No detailed process markers in these two runs.\nWorld state advances through sequential phases; remaining stalls still exceed the 16.7 ms frame budget.", fontsize=9, color="#475569")
    fig.subplots_adjust(left=.09, right=.97, top=.87, bottom=.13, hspace=.42)
    fig.savefig(args.output / "frame_pacing.png", dpi=160)
    fig.savefig(args.output / "frame_pacing.svg")
    plt.close(fig)
    print(json.dumps({"runs": list(comparison), "output": str(args.output)}))


if __name__ == "__main__":
    main()

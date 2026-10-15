"""Preserve native water timings, distinguishing update frames from idle frames."""
import argparse
import json
import shutil
from pathlib import Path


def stats(values):
    values = sorted(values)
    return {"count": len(values), "mean": sum(values)/len(values),
            "p95": values[int((len(values)-1)*.95)], "max": max(values)}


def main():
    parser = argparse.ArgumentParser()
    for key in ("fresh_before", "fresh_after", "saved_before", "saved_after", "output"):
        parser.add_argument(key, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    comparison = {}
    for key in ("fresh_before", "fresh_after", "saved_before", "saved_after"):
        folder = getattr(args, key)
        report = json.loads((folder / "report.json").read_text())
        for name in ("report.json", "run.json"):
            shutil.copyfile(folder / name, args.output / f"{folder.name}_{name}")
        comparison[key] = {}
        for phase in ("active_pan", "active_pan_repeat"):
            data = report["phases"][phase]
            comparison[key][phase] = {field: data[field] for field in ("frames", "seconds", "frame_ms", "process")}
            if key.startswith("fresh"):
                rows = json.loads((folder / f"{phase}_frames.json").read_text())
                updates = [r for r in rows if r["process"].get("water_sim/total", 0) > 0]
                comparison[key][phase]["active_water_frames"] = {
                    stage: stats([r["process"].get("water_sim/"+stage, 0) for r in updates])
                    for stage in ("total", "flow", "moisture", "changes", "notifications", "sources")
                }
    (args.output / "comparison.json").write_text(json.dumps(comparison, indent=2)+"\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    fig, axes = plt.subplots(1, 2, figsize=(11, 5.3))
    fig.suptitle("Water flow reuses unchanged terrain", x=.07, ha="left", fontsize=17, weight="bold")
    fig.text(.07, .89, "Native Godot · 2560×1440 · unchanged simulation ticks and transfer order", color="#475569")
    for i, (suffix, color) in enumerate((("before", "#9b4a41"), ("after", "#247c9a"))):
        values = [comparison["fresh_"+suffix][p]["active_water_frames"]["total"]["p95"] for p in ("active_pan", "active_pan_repeat")]
        bars = axes[0].bar(np.arange(2)+(i-.5)*.34, values, .34, label=suffix.capitalize(), color=color)
        axes[0].bar_label(bars, fmt="%.1f", padding=3)
        values = [comparison[world+"_"+suffix][p]["frame_ms"]["p95"] for world in ("fresh", "saved") for p in ("active_pan", "active_pan_repeat")]
        bars = axes[1].bar(np.arange(4)+(i-.5)*.34, values, .34, label=suffix.capitalize(), color=color)
        axes[1].bar_label(bars, fmt="%.1f", padding=3)
    axes[0].set(xticks=[0, 1], xticklabels=["First pan", "Later pan"], title="Water cost on frames with a water update", ylabel="P95 time (ms)")
    axes[1].set(xticks=range(4), xticklabels=["Fresh\nfirst", "Fresh\nlater", "Saved\nfirst", "Saved\nlater"], title="Whole frame during camera pan")
    axes[1].axhline(1000/60, color="#475569", linestyle="--", linewidth=1, label="60 FPS budget")
    for ax in axes:
        ax.grid(axis="y", alpha=.2)
        ax.set_axisbelow(True)
        ax.spines[["top", "right"]].set_visible(False)
        ax.set_ylim(0, ax.get_ylim()[1]*1.4)
        ax.legend(fontsize=9)
    fig.text(.07, .035, "Left: water timing excludes frames without a water update. Right: all frames. Fresh runs include detailed timers; saved runs do not.\nIndividual samples evolve the simulation; remaining spikes still exceed the 60 FPS budget.", fontsize=9, color="#475569")
    fig.subplots_adjust(left=.07, right=.98, top=.79, bottom=.21, wspace=.24)
    for ext in ("png", "svg"):
        fig.savefig(args.output / f"water_simulation.{ext}", dpi=160)
    print(json.dumps({"output": str(args.output)}))


if __name__ == "__main__":
    main()

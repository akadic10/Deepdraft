"""Archive paired native reports and plot wildlife/frame-time P95 comparisons."""
import argparse
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    for name in ("fresh_before", "fresh_after", "saved_before", "saved_after", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    reports = {}
    for name in ("fresh_before", "fresh_after", "saved_before", "saved_after"):
        folder = getattr(args, name)
        reports[name] = json.loads((folder / "report.json").read_text())
        for filename in ("report.json", "run.json"):
            shutil.copyfile(folder / filename, args.output / f"{folder.name}_{filename}")
    comparison = {
        name: {
            phase: {k: v for k, v in report["phases"][phase].items() if k in (
                "frames", "seconds", "frame_ms", "process", "navigation_cache_start", "navigation_cache_end")}
            for phase in ("active_pan", "active_pan_repeat")
        } for name, report in reports.items()
    }
    (args.output / "comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    fig.suptitle("Wildlife reuses terrain and clearance checks", x=.07, ha="left", fontsize=17, weight="bold")
    fig.text(.07, .89, "Native Godot · 2560×1440 · all animals still simulate every frame", color="#475569")
    colors = ["#9b4a41", "#247c9a"]
    for i, (label, color) in enumerate(zip(("Before", "After"), colors)):
        suffix = label.lower()
        wildlife = [comparison["fresh_" + suffix][phase]["process"]["DebugWorld/WildlifeManager"]["p95"]
                    for phase in ("active_pan", "active_pan_repeat")]
        bars = axes[0].bar(np.arange(2) + (i-.5)*.34, wildlife, .34, label=label, color=color)
        axes[0].bar_label(bars, fmt="%.1f", padding=3)
        frames = [comparison[world + "_" + suffix][phase]["frame_ms"]["p95"]
                  for world in ("fresh", "saved") for phase in ("active_pan", "active_pan_repeat")]
        bars = axes[1].bar(np.arange(4) + (i-.5)*.34, frames, .34, label=label, color=color)
        axes[1].bar_label(bars, fmt="%.1f", padding=3)
    axes[0].set(xticks=[0, 1], xticklabels=["First pan", "Later pan"], title="Fresh-world wildlife update", ylabel="P95 time (ms)")
    axes[1].set(xticks=range(4), xticklabels=["Fresh\nfirst", "Fresh\nlater", "Saved\nfirst", "Saved\nlater"], title="Whole frame during camera pan")
    axes[1].axhline(1000/60, color="#475569", linestyle="--", linewidth=1, label="60 FPS budget")
    for ax in axes:
        ax.grid(axis="y", alpha=.2)
        ax.set_axisbelow(True)
        ax.spines[["top", "right"]].set_visible(False)
        ax.set_ylim(0, ax.get_ylim()[1]*(1.4 if ax is axes[1] else 1.12))
        ax.legend(fontsize=9)
    fig.text(.07, .035, "Fresh runs include species/process timing; saved runs do not. Water mesh optimization is present on both sides.\nSequential phases evolve the world; these are individual samples, not confidence intervals or a steady-60-FPS claim.", fontsize=9, color="#475569")
    fig.subplots_adjust(left=.07, right=.98, top=.79, bottom=.2, wspace=.24)
    for ext in ("png", "svg"):
        fig.savefig(args.output / f"wildlife_performance.{ext}", dpi=160)
    plt.close(fig)
    print(json.dumps({"output": str(args.output), "runs": list(reports)}))


if __name__ == "__main__":
    main()

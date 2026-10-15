"""Summarize CameraBenchmark reports and plot frame pacing (matplotlib required)."""
import argparse
import csv
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    reports = {run.name: json.loads((run / "report.json").read_text()) for run in args.runs}
    fields = ["run", "phase", "frames", "seconds", "mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "over_50_ms", "gpu_p95_ms"]
    with (args.output / "summary.csv").open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        for label, report in reports.items():
            for phase, data in report["phases"].items():
                timing = data["frame_ms"]
                writer.writerow(dict(run=label, phase=phase, frames=data["frames"], seconds=data["seconds"],
                    mean_ms=timing["mean"], p50_ms=timing["p50"], p95_ms=timing["p95"], p99_ms=timing["p99"],
                    max_ms=timing["max"], over_50_ms=timing["over_50"], gpu_p95_ms=data["gpu_ms"]["p95"]))
    for label, report in reports.items():
        (args.output / f"{label}_report.json").write_text(json.dumps(report, indent=2) + "\n")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False, "axes.spines.right": False})
    selected = next((run for run in args.runs if run.name == "saved_control"), args.runs[0])
    report = reports[selected.name]
    fig, (trace, comparison) = plt.subplots(2, 1, figsize=(11, 8), gridspec_kw={"height_ratios": [1.05, 1]})
    fig.suptitle("Deepdraft camera stutter comes from CPU world updates", x=.07, ha="left", fontsize=17, weight="bold")
    fig.text(.07, .935, "Copied settlement · 5 dwarves · 2560×1440 · Ryzen 7 9800X3D / Radeon RX 9070 XT", color="#475569")
    rows = json.loads((selected / "active_pan_frames.json").read_text())
    frames = np.array([row["frame_ms"] for row in rows])
    elapsed = np.cumsum(frames) / 1000
    trace.plot(elapsed, frames, color="#bb3e32", linewidth=1.2, label="Frame interval")
    trace.plot(elapsed, [row["gpu_ms"] for row in rows], color="#087f8c", linewidth=1.1, label="GPU render time")
    trace.axhline(1000 / 60, color="#475569", linestyle="--", linewidth=1, label="60 FPS budget: 16.7 ms")
    trace.set(xlabel="Seconds during camera pan", ylabel="Milliseconds", ylim=(0, max(frames) * 1.08))
    trace.legend(loc="upper right", ncol=3, fontsize=9)
    trace.grid(axis="y", alpha=.18)

    cases = [("active_pan", "All systems active"), ("active_pan_no_water_render", "Water mesh updates frozen"),
             ("active_pan_no_water_sim", "Water simulation frozen"), ("active_pan_no_wildlife", "Wildlife frozen"),
             ("active_pan_no_water_and_wildlife", "Water + wildlife frozen"), ("paused_pan", "Game paused")]
    cases = [(key, label) for key, label in cases if key in report["phases"]]
    values = [report["phases"][key]["frame_ms"]["p95"] for key, _ in cases]
    bars = comparison.barh([label for _, label in cases], values, color=["#bb3e32"] + ["#4b7ca1"] * (len(cases) - 1), height=.62)
    comparison.invert_yaxis()
    comparison.axvline(1000 / 60, color="#475569", linestyle="--", linewidth=1)
    comparison.set_xlabel("95th-percentile frame interval (ms; lower is better)")
    comparison.set_xlim(0, max(values) * 1.18)
    comparison.bar_label(bars, labels=[f"{value:.1f} ms" for value in values], padding=6)
    comparison.grid(axis="x", alpha=.18)
    fig.text(.07, .025, "Freezing systems is a diagnostic control, not a proposed fix. Native engine run, VSync off, real-time delta.\nSequential phases advance the world; GPU samples may lag frame intervals. This is not a Stonehearth benchmark.", fontsize=9, color="#475569")
    fig.subplots_adjust(left=.25, right=.96, top=.88, bottom=.12, hspace=.43)
    fig.savefig(args.output / "frame_pacing.png", dpi=160)
    fig.savefig(args.output / "frame_pacing.svg")
    plt.close(fig)
    print(json.dumps({"runs": list(reports), "output": str(args.output)}))


if __name__ == "__main__":
    main()

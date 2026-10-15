"""Preserve the 30-dwarf scheduling measurements; run after isolated benchmarks."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/00_dev_roadmap/concepts/jobs30_20261014"
OUT.mkdir(parents=True, exist_ok=True)
names = ["jobs30_before", "jobs30_trace_before", "jobs30_after_v1", "jobs30_after_repeat", "jobs20_after"]
reports = {}
for name in names:
    folder = ROOT / "tmp/performance_20261014" / name
    if not (folder / "run.json").exists():
        continue
    reports[name] = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    for filename in ["report.json", "run.json", "run.out", "run.err", "colony.png"]:
        shutil.copy2(folder / filename, OUT / (name + "_" + filename))
    for trace in folder.glob("*_frames.json"):
        # Preserve full measured rows without a large uncompressed JSON file.
        with gzip.open(OUT / (name + "_" + trace.name + ".gz"), "wb") as target:
            target.write(trace.read_bytes())

(OUT / "comparison.json").write_text(json.dumps({
    name: {"phases": report["phases"], "workload": report["workload"],
           "all_work_types_progressed": report["all_work_types_progressed"]}
    for name, report in reports.items() if "trace" not in name
}, indent=2), encoding="utf-8")

scratch = ROOT / "tmp/jobs30_20261014"
for filename in ["preparation.json", "job_gate/results.json", "packed/packed_smoke.json", "packed/release_startup.json"]:
    path = scratch / filename
    if path.exists():
        shutil.copy2(path, OUT / filename.replace("/", "_"))
for folder in ["job_gate", "packed"]:
    for pattern in ["*.out", "*.err"]:
        for path in (scratch / folder).glob(pattern):
            shutil.copy2(path, OUT / (folder + "_" + path.name))

paths = ["scripts/systems/TaskManager.gd", "scripts/components/StorageComponent.gd",
         "scripts/systems/ItemDropManager.gd", "scripts/components/FurnitureFetchPlanner.gd",
         "scripts/tests/JobPreparationReuseTest.gd", "tools/performance/ColonyScalingBenchmark.gd"]
audit = {"production_and_test_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths},
         "runs": list(reports), "trace_run_excluded_from_fps_comparison": True}
if len(sys.argv) > 1:
    package = Path(sys.argv[1])
    audit["package"] = str(package)
    audit["zip_sha256"] = hashlib.sha256((ROOT / "build/windows/Deepdraft-Windows-Playtest.zip").read_bytes()).hexdigest()
(OUT / "audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
labels = ["Before", "After A", "After B"]
selected = [reports[n]["phases"]["active_pan_repeat"] for n in names if n in ["jobs30_before", "jobs30_after_v1", "jobs30_after_repeat"]]
fig, axes = plt.subplots(1, 2, figsize=(11, 4.5), layout="constrained")
for offset, metric, color, label in [(-.18, "built", "#2563eb", "Built blocks"), (.18, "stored", "#0d9488", "Stored items")]:
    bars = axes[0].bar([i+offset for i in range(3)], [v["work_after"][metric] for v in selected], width=.35, color=color, label=label)
    axes[0].bar_label(bars, padding=3)
axes[0].set_title("More work completed in the 30-dwarf yard")
axes[0].set_ylabel("Completed units after both active phases")
axes[0].set_ylim(0, 46)
for offset, metric, color, label in [(-.18, "mean", "#64748b", "Mean"), (.18, "p95", "#c2410c", "P95")]:
    bars = axes[1].bar([i+offset for i in range(3)], [v["frame_ms"][metric] for v in selected], width=.35, color=color, label=label)
    axes[1].bar_label(bars, fmt="%.1f", padding=3)
axes[1].set_title("Later camera pan remains slower")
axes[1].set_ylabel("Whole-frame milliseconds (lower is better)")
axes[1].set_ylim(0, 46)
for ax in axes:
    ax.set_xticks(range(3), labels)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(frameon=False, loc="upper left")
fig.suptitle("Scheduling progress improves; this is not an FPS win", fontsize=14)
fig.savefig(OUT / "jobs30.png", dpi=160)
plt.close(fig)
print(json.dumps(audit, indent=2))

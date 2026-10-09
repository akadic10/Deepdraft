"""Measure exported prototype voxels; no changes to live generation.

Uses bundled numpy/Pillow. Writes the study summary and compressed inline data.
The Godot export is [Y,Z,X], 64 cells per axis, byte codes 1..6 = resource order.
"""
from __future__ import annotations

import base64
import hashlib
import json
import statistics
import zlib
from collections import deque
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tmp/ore_vein_review"


def measure(raw: bytes, code: int) -> dict:
    values = np.frombuffer(raw, dtype=np.uint8)
    mask = bytearray((values == code).tobytes())
    indices = np.flatnonzero(values == code)
    components = []
    for start in indices:
        start = int(start)
        if not mask[start]:
            continue
        mask[start] = 0
        queue = deque([start])
        count = 0
        lower = [64, 64, 64]
        upper = [0, 0, 0]
        while queue:
            index = queue.popleft()
            y, rest = divmod(index, 4096)
            z, x = divmod(rest, 64)
            count += 1
            for axis, val in enumerate((x, y, z)):
                lower[axis] = min(lower[axis], val)
                upper[axis] = max(upper[axis], val)
            for inside, neighbor in ((x > 0, index - 1), (x < 63, index + 1),
                                     (z > 0, index - 64), (z < 63, index + 64),
                                     (y > 0, index - 4096), (y < 63, index + 4096)):
                if inside and mask[neighbor]:
                    mask[neighbor] = 0
                    queue.append(neighbor)
        components.append({"size": count, "extent": [b - a + 1 for a, b in zip(lower, upper)],
                           "clipped": 0 in lower or 63 in upper})
    components.sort(key=lambda c: c["size"], reverse=True)
    return {"count": len(indices), "components": len(components),
            "largest": components[0] if components else {"size": 0, "extent": [0, 0, 0], "clipped": False},
            "blocks_in_bodies_over_1000": sum(c["size"] for c in components if c["size"] > 1000),
            "isolated_blocks": sum(c["size"] == 1 for c in components), "all_components": components}


def main() -> None:
    study = json.loads((OUT / "study.json").read_text())
    assert study["passed"] and not study["failures"], study["failures"]
    baseline = json.loads((ROOT / "tmp/world_layout_review/resource_balance_after.json").read_text())
    old_by_seed = {s["seed"]: s for s in baseline["seeds"]}
    inline = {"names": study["names"], "variants": study["variants"], "seeds": [], "aggregate": {}}
    totals = {v: [0] * 6 for v in study["variants"]}
    heldout = {v: [0] * 6 for v in study["variants"]}
    largest = {v: [[] for _ in range(6)] for v in study["variants"]}
    for seed in study["seeds"]:
        old = old_by_seed[seed["seed"]]
        assert seed["geography_hash"] == old["geography_sha256"]
        assert seed["box"]["origin"] == old["vein_box"]["origin"]
        assert seed["sample"]["current"] == [old["sample"]["counts"]["base:terrain:ore:" + n] for n in study["names"]]
        entry = {"seed": seed["seed"], "origin": seed["box"]["origin"], "volumes": {}, "metrics": {}}
        seed["metrics"] = {}
        for variant in study["variants"]:
            raw = (OUT / f"{seed['seed']}_{variant}.bin").read_bytes()
            assert len(raw) == 64 ** 3 and max(raw) <= 6
            assert hashlib.sha256(raw.hex().encode()).hexdigest() == seed["box"]["sha256"][variant]
            entry["volumes"][variant] = base64.b64encode(zlib.compress(raw, 9)).decode()
            seed["metrics"][variant] = [measure(raw, code) for code in range(1, 7)]
            entry["metrics"][variant] = [{k: v for k, v in m.items() if k != "all_components"}
                                           for m in seed["metrics"][variant]]
            for i, name in enumerate(study["names"]):
                totals[variant][i] += seed["sample"][variant][i]
                if seed["seed"] in study["held_out_seeds"]:
                    heldout[variant][i] += seed["sample"][variant][i]
                largest[variant][i].append(seed["metrics"][variant][i]["largest"]["size"])
                if variant == "current":
                    expected = old["vein_box"]["components"].get("base:terrain:ore:" + name, [])
                    actual = seed["metrics"][variant][i]
                    assert actual["count"] == old["vein_box"]["counts"]["base:terrain:ore:" + name]
                    assert actual["largest"]["size"] == max([c["size"] for c in expected], default=0)
        inline["seeds"].append(entry)
        print("Measured", seed["seed"], flush=True)
    aggregate = {v: {"counts": totals[v], "heldout_counts": heldout[v],
                      "median_largest": [statistics.median(values) for values in largest[v]]}
                 for v in study["variants"]}
    study["aggregate"] = aggregate
    inline["aggregate"] = aggregate
    (OUT / "analysis.json").write_text(json.dumps(study, indent=2) + "\n")
    (OUT / "inline_data.json").write_text(json.dumps(inline, separators=(",", ":")))
    print(json.dumps(aggregate, indent=2))
    print("Inline data bytes", (OUT / "inline_data.json").stat().st_size)


if __name__ == "__main__":
    main()

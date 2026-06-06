#!/usr/bin/env python3
"""
Generate Deepdraft juniper GLBs — narrow columnar 1:1 evergreen.

Tree convention: 1:1 (1 voxel = 1 block, scale 1.0; doc 61). Juniper is a tall,
narrow columnar evergreen shrub-tree: a dense dark blue-green column with a
rounded top, much narrower than oak/apple, dotted with dusty blue-grey berries.
Two seasons only (evergreen): summer baseline, winter snow-dusted. Footprint
1×1 (mature) / 2×2 (ancient). Centred on trunk at X=Z=0, base at Y=0.
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

VOX_PER_BLOCK = 1


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)

JUN_TOP   = _c(0x5A8246)
JUN_MID   = _c(0x3C6232)
JUN_DARK  = _c(0x274421)
BERRY     = _c(0x556488)
BERRY_HI  = _c(0x6E7CA0)
SNOW      = _c(0xEAF0F4)
SNOW_SH   = _c(0xCAD6DE)
TR_MID    = _c(0x5E4128)
TR_DK     = _c(0x3E2A18)


def vary(color, amt, rng):
    f = 1.0 + rng.uniform(-amt, amt)
    return tuple(max(0.0, min(1.0, c * f)) for c in color)


def needle(upper, rng):
    pal = [JUN_TOP, JUN_MID] if upper else [JUN_MID, JUN_DARK, JUN_DARK]
    return vary(rng.choice(pal), 0.06, rng)


def radius_at(y, H, rmid, base_taper):
    """Columnar profile: slim base, full body, rounded top."""
    top_round = max(2.0, rmid + 1)
    if y >= H - top_round:                       # dome top
        dy = y - (H - top_round)
        return math.sqrt(max(0.0, top_round * top_round - dy * dy)) * (rmid / top_round)
    if y < base_taper:                            # slim near the ground
        return rmid * (0.45 + 0.55 * y / max(1, base_taper))
    return rmid


def build_juniper(stage, season="summer", variant=1):
    cfg = {
        "sapling": dict(H=5,  rmid=1, base=1),
        "mature":  dict(H=12, rmid=2, base=3),
        "ancient": dict(H=16, rmid=3, base=4),
    }[stage]
    rng = random.Random(f"jun1:{stage}:{season}:{variant}")
    v = Voxels()
    H = cfg["H"]
    rmid = cfg["rmid"] * (0.85 if variant == 2 else 1.0)
    lean = 0.06 if variant == 2 else 0.0

    # thin trunk core (mostly hidden)
    for y in range(0, H - 1):
        v.set(int(round(lean * y)), y, 0, vary(TR_DK if rng.random() < 0.5 else TR_MID, 0.05, rng))

    for y in range(0, H):
        r = radius_at(y, H, rmid, cfg["base"])
        if r < 0.4:
            continue
        cx = lean * y
        pad = int(r) + 1
        for x in range(int(cx) - pad, int(cx) + pad + 1):
            for z in range(-pad, pad + 1):
                d = math.hypot(x - cx, z)
                rr = r + rng.uniform(-0.35, 0.25)
                if d > rr + 0.5:
                    if d < rr + 1.4 and rng.random() < 0.12:   # ragged sprigs
                        v.set(x, y, z, needle(False, rng))
                    continue
                if d < r * 0.45 and rng.random() < 0.10:        # light interior pockets
                    continue
                v.set(x, y, z, needle(y > H * 0.55, rng))

    # berries: dusty blue dots on the surface (mature/ancient)
    if stage != "sapling":
        for (x, y, z), c in list(v.cells.items()):
            exposed = any((x + dx, y + dy, z + dz) not in v.cells
                          for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)))
            if exposed and c[1] >= c[0] and 1 < y < H - 2 and rng.random() < 0.06:
                v.cells[(x, y, z)] = vary(BERRY if rng.random() < 0.7 else BERRY_HI, 0.05, rng)

    if season == "winter":
        adds = {}
        for (x, y, z), c in list(v.cells.items()):
            if (x, y + 1, z) in v.cells:
                continue
            if c[1] >= c[0] and c[2] < 0.5 and rng.random() < 0.55:   # frost needles, not berries
                adds[(x, y, z)] = vary(SNOW if rng.random() < 0.8 else SNOW_SH, 0.04, rng)
        v.cells.update(adds)
    return v


def manifest():
    out = []
    for s in ("sapling", "mature", "ancient"):
        if s == "sapling":
            out += [("juniper_sapling", s, "summer", 1), ("juniper_sapling_winter", s, "winter", 1)]
        else:
            out += [(f"juniper_{s}", s, "summer", 1), (f"juniper_{s}_2", s, "summer", 2),
                    (f"juniper_{s}_winter", s, "winter", 1)]
    return out


def main():
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "assets" / "models" / "flora" / "trees" / "juniper"
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, stage, season, variant in manifest():
        vox = build_juniper(stage, season, variant)
        mesh = mesh_from_voxels(vox)
        size = write_glb(out_dir / f"{name}.glb", name, mesh)
        total += size
        h = max(y for _, y, _ in vox.cells) + 1
        xs = [x for x, _, _ in vox.cells]
        w = max(xs) - min(xs) + 1
        print("%-26s %-7s %-6s H%2d W%2d  %5d vox %6d tris %6.1f KB" % (
            name, stage, season, h, w, len(vox), len(mesh[3]) // 3, size / 1024))
    print("\nWrote %d juniper GLBs (%.2f MB) at 1 vox/block." % (len(manifest()), total / 1024 / 1024))


if __name__ == "__main__":
    main()

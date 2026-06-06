#!/usr/bin/env python3
"""
Generate Deepdraft pine GLBs — simple Stonehearth-style stepped conifer.

ART CONVENTION (2026-06-06): trees are authored 1:1 — 1 voxel = 1 game block
(VOX_PER_BLOCK = 1), rendered at scale 1.0. This matches Stonehearth's tree
pipeline (their trees render at scale 1.0, one model voxel per terrain block) and
the chunky "Voxel Trees" look. Characters/items stay at 8 voxels/block (their own
import scale). See docs/60_asset_creation/61_voxel_art_guide.md.

A pine is a stepped cone: a bare reddish trunk at the base, a stack of flat needle
whorls (widest at the bottom, narrowing in steps) with 1-block gaps that let the
trunk peek through, and a pointed apex. Engine lighting (PER_PIXEL) does the
face shading, so colours stay to a few simple greens.

Models are authored centred on the trunk at X=Z=0, base at Y=0 (matches
SurfaceFloraSpawner._instance_tree). Sizes: ancient 27 / mature 20 / sapling 8
blocks tall (docs/00_dev_roadmap/13_flora_scatter_pine.md §5.1).
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

VOX_PER_BLOCK = 1  # keep SurfaceFloraSpawner.voxels_per_block in sync


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)

PINE_TOP  = _c(0x7CB342)
PINE_MID  = _c(0x558B2F)
PINE_DARK = _c(0x33691E)

WIN_TOP   = _c(0x5E7D4A)
WIN_MID   = _c(0x466138)
WIN_DARK  = _c(0x314A29)

SNOW      = _c(0xEAF0F4)
SNOW_SH   = _c(0xCAD6DE)

TRUNK_HI  = _c(0x9A5E38)
TRUNK_MID = _c(0x7A4A2B)
TRUNK_DK  = _c(0x542F18)


def vary(color, amt, rng):
    f = 1.0 + rng.uniform(-amt, amt)
    return tuple(max(0.0, min(1.0, c * f)) for c in color)


def needle(season, lit, rng):
    if season == "winter":
        pal = [WIN_TOP, WIN_MID] if lit else [WIN_MID, WIN_DARK]
    else:
        pal = [PINE_TOP, PINE_MID] if lit else [PINE_MID, PINE_DARK]
    return vary(rng.choice(pal), 0.06, rng)


def bark(rng):
    r = rng.random()
    base = TRUNK_DK if r < 0.30 else (TRUNK_HI if r < 0.48 else TRUNK_MID)
    return vary(base, 0.05, rng)


def add_trunk(v, H, tw, top_y, rng):
    off = -(tw // 2)
    for y in range(0, top_y):
        for x in range(off, off + tw):
            for z in range(off, off + tw):
                v.set(x, y, z, bark(rng))
    for y in range(top_y, H - 1):   # thin core, peeks through the whorl gaps
        v.set(0, y, 0, bark(rng))


def add_tier(v, cy, r, thick, season, rng, droop):
    for x in range(-r - 1, r + 2):
        for z in range(-r - 1, r + 2):
            d = math.hypot(x, z)
            rr = r + rng.uniform(-0.45, 0.30)
            if d > rr + 0.5:
                continue
            yoff = -1 if (droop and r >= 3 and d > r * 0.6) else 0
            for k in range(thick):
                yy = cy - k + yoff
                if yy < 1:
                    continue
                if d > r * 0.7 and rng.random() < 0.20:   # ragged rim
                    continue
                lit = (k == 0 and yoff == 0) and rng.random() < 0.7
                v.set(x, yy, z, needle(season, lit, rng))


def add_apex(v, y0, H, season, rng):
    for y in range(y0, H):
        r = 1 if y < H - 1 else 0
        for x in range(-r, r + 1):
            for z in range(-r, r + 1):
                if abs(x) + abs(z) > r:
                    continue
                v.set(x, y, z, needle(season, True, rng))


def frost(v, rng, amount=0.6):
    cells = v.cells
    adds = {}
    for (x, y, z), c in list(cells.items()):
        if (x, y + 1, z) in cells:
            continue
        if c[1] >= c[0] and c[1] >= c[2]:   # greenish = needles
            if rng.random() < amount:
                adds[(x, y, z)] = vary(SNOW if rng.random() < 0.8 else SNOW_SH, 0.04, rng)
    cells.update(adds)


STAGES = {
    "sapling": dict(H=8,  base_r=2, tw=1, n=3, bare=2),
    "mature":  dict(H=20, base_r=4, tw=2, n=6, bare=3),
    "ancient": dict(H=27, base_r=7, tw=3, n=8, bare=4),
}
VARIANTS = {
    1: dict(rmul=1.00, dn=0),
    2: dict(rmul=0.90, dn=0),
    3: dict(rmul=1.05, dn=1),
}


def build_pine(stage, season="summer", variant=1):
    p = STAGES[stage]
    vt = VARIANTS[variant]
    rng = random.Random(f"pine1:{stage}:{season}:{variant}")
    v = Voxels()

    H = p["H"]
    base_r = max(1.0, p["base_r"] * vt["rmul"])
    n = max(2, p["n"] + vt["dn"])
    bare = p["bare"]
    droop = stage != "sapling"

    add_trunk(v, H, p["tw"], bare + 1, rng)

    top_cy = bare
    for i in range(n):
        frac = i / (n - 1)
        cy = bare + int(round((H - 2 - bare) * frac))
        r = max(1, int(round(base_r * (1.0 - 0.92 * frac))))
        thick = 2 if (frac < 0.45 and stage != "sapling") else 1
        add_tier(v, cy, r, thick, season, rng, droop)
        top_cy = cy

    add_apex(v, top_cy, H, season, rng)

    if season == "winter":
        frost(v, rng)

    return v


def manifest():
    out = []
    for stage in ("sapling", "mature", "ancient"):
        for var in range(1, (1 if stage == "sapling" else 3) + 1):
            out.append((f"pine_{stage}{'' if var == 1 else '_%d' % var}", stage, "summer", var))
        for var in range(1, (1 if stage == "sapling" else 2) + 1):
            out.append((f"pine_{stage}_winter{'' if var == 1 else '_%d' % var}", stage, "winter", var))
    return out


def main():
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "assets" / "models" / "flora" / "trees" / "pine"
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, stage, season, variant in manifest():
        vox = build_pine(stage, season, variant)
        mesh = mesh_from_voxels(vox)
        size = write_glb(out_dir / f"{name}.glb", name, mesh)
        total += size
        h = max(y for _, y, _ in vox.cells) + 1
        xs = [x for x, _, _ in vox.cells]
        w = max(xs) - min(xs) + 1
        print("%-26s %-7s %-6s v%d  H%2d W%2d blk  %5d vox %6d tris %6.1f KB" % (
            name, stage, season, variant, h, w, len(vox), len(mesh[3]) // 3, size / 1024))
    print("\nWrote %d pine GLBs (%.2f MB) at 1 vox/block." % (len(manifest()), total / 1024 / 1024))
    print("Reminder: SurfaceFloraSpawner.voxels_per_block must be %s." % VOX_PER_BLOCK)


if __name__ == "__main__":
    main()

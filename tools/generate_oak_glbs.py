#!/usr/bin/env python3
"""
Generate Deepdraft oak GLBs — big gnarled 1:1 deciduous hardwood.

Tree convention: 1:1 (1 voxel = 1 block, scale 1.0; doc 61). Oak is the largest
broadleaf — taller and broader than apple, with an irregular multi-lobe canopy
(gnarled, ancient-feeling), dark grey-brown bark, NO blossom or fruit. Four
seasons: spring (fresh light green), summer, autumn (gold/rust), winter (bare
gnarled branches). Centred on trunk at X=Z=0, base at Y=0.
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

VOX_PER_BLOCK = 1


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)

LEAF_TOP  = _c(0x6FA83A)
LEAF_MID  = _c(0x4C822C)
LEAF_DARK = _c(0x2F5A1E)
SPR_TOP   = _c(0xA5CE6A)
SPR_MID   = _c(0x82B840)
AU_GOLD   = _c(0xD8901E)
AU_RUST   = _c(0xA84B16)
AU_DARK   = _c(0x6E3312)
TR_HI     = _c(0x6E5236)
TR_MID    = _c(0x4E3A24)
TR_DK     = _c(0x332416)
BRANCH    = _c(0x3E2C1A)


def vary(color, amt, rng):
    f = 1.0 + rng.uniform(-amt, amt)
    return tuple(max(0.0, min(1.0, c * f)) for c in color)


def leaf_color(season, upper, rng):
    if season == "spring":
        pal = [SPR_TOP, SPR_MID] if upper else [SPR_MID, LEAF_MID]
    elif season == "autumn":
        pal = [AU_GOLD, AU_GOLD, AU_RUST] if upper else [AU_RUST, AU_DARK]
    else:
        pal = [LEAF_TOP, LEAF_MID] if upper else [LEAF_MID, LEAF_DARK]
    return vary(rng.choice(pal), 0.07, rng)


def bark(rng):
    r = rng.random()
    base = TR_DK if r < 0.32 else (TR_HI if r < 0.5 else TR_MID)
    return vary(base, 0.05, rng)


def add_trunk(v, top_y, trunk_w, bare, flare, rng):
    for y in range(0, top_y):
        w = trunk_w
        if flare and y < 3:
            w = trunk_w + (flare if y == 0 else (flare - 1 if y == 1 else max(0, flare - 2)))
        o = -(w // 2)
        for x in range(o, o + w):
            for z in range(o, o + w):
                v.set(x, y, z, bark(rng))


def _line(v, p0, p1, cf, rng):
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    steps = int(max(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))) + 1
    for s in range(steps + 1):
        t = s / max(1, steps)
        v.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t),
              round(z0 + (z1 - z0) * t), cf(rng))


def add_branches(v, start_y, top_y, reach, n, rng):
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.4, 0.4)
        ex, ez = math.cos(ang) * reach, math.sin(ang) * reach
        ey = top_y + rng.uniform(-1.5, 1.0)
        _line(v, (0, start_y, 0), (ex, ey, ez), lambda r: vary(BRANCH, 0.06, r), rng)
        for _ in range(2):
            fx = ex + math.cos(ang + rng.uniform(-1, 1)) * reach * 0.35
            fz = ez + math.sin(ang + rng.uniform(-1, 1)) * reach * 0.35
            _line(v, (ex * 0.6, (start_y + ey) / 2, ez * 0.6), (fx, ey + rng.uniform(0, 2), fz),
                  lambda r: vary(BRANCH, 0.06, r), rng)


def add_canopy(v, cy, R, season, rng):
    ry = R * 0.78
    lobes = [(0.0, float(cy), 0.0, float(R), ry, float(R))]
    nlobes = 3 if R >= 6 else 2
    for i in range(nlobes):
        ang = 2 * math.pi * i / nlobes + rng.uniform(-0.5, 0.5)
        ox = math.cos(ang) * R * 0.45
        oz = math.sin(ang) * R * 0.45
        oy = cy + rng.uniform(0.0, 0.35) * R
        lr = R * rng.uniform(0.52, 0.7)
        lobes.append((ox, oy, oz, lr, lr * 0.8, lr))
    rmax = int(R) + 2
    for x in range(-rmax, rmax + 1):
        for y in range(int(cy - ry - 2), int(cy + ry + 3)):
            for z in range(-rmax, rmax + 1):
                inside = False
                deep = False
                for (ox, oy, oz, lx, ly, lz) in lobes:
                    e = ((x - ox) / lx) ** 2 + ((y - oy) / ly) ** 2 + ((z - oz) / lz) ** 2
                    if e <= 1.0 + rng.uniform(-0.10, 0.10):
                        inside = True
                        if e < 0.4:
                            deep = True
                if not inside:
                    continue
                if deep and rng.random() < 0.14:
                    continue
                v.set(x, y, z, leaf_color(season, y > cy, rng))
    # bobbly protruding cubes
    bumps = {}
    for (x, y, z), c in list(v.cells.items()):
        if c[0] > c[1] and c[2] < 0.4 and c[0] < 0.6:   # skip brown trunk voxels
            continue
        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1)):
            n = (x + dx, y + dy, z + dz)
            if n in v.cells or n in bumps:
                continue
            if rng.random() < 0.17:
                bumps[n] = leaf_color(season, dy >= 0, rng)
    v.cells.update(bumps)


STAGES = {
    "sapling": dict(H=7,  cy=4,  R=2,  trunk_w=1, bare=2, flare=0),
    "mature":  dict(H=16, cy=11, R=6,  trunk_w=2, bare=5, flare=1),
    "ancient": dict(H=24, cy=16, R=10, trunk_w=3, bare=6, flare=2),
}
VMUL = {1: 1.00, 2: 0.90, 3: 1.08}


def build_oak(stage, season="summer", variant=1):
    p = STAGES[stage]
    rng = random.Random(f"oak1:{stage}:{season}:{variant}")
    v = Voxels()
    R = max(1, int(round(p["R"] * VMUL[variant])))
    cy = p["cy"]
    if season == "winter":
        add_trunk(v, p["bare"] + 2, p["trunk_w"], p["bare"], p["flare"], rng)
        add_branches(v, p["bare"], cy + int(R * 0.6), R, 4 if stage != "sapling" else 3, rng)
    else:
        add_trunk(v, cy, p["trunk_w"], p["bare"], p["flare"], rng)
        add_canopy(v, cy, R, season, rng)
    return v


def manifest():
    out = []
    for s in ("sapling", "mature", "ancient"):
        if s == "sapling":
            out += [("oak_sapling_spring", s, "spring", 1), ("oak_sapling", s, "summer", 1),
                    ("oak_sapling_autumn", s, "autumn", 1), ("oak_sapling_winter", s, "winter", 1)]
        else:
            out += [(f"oak_{s}_spring", s, "spring", 1),
                    (f"oak_{s}", s, "summer", 1), (f"oak_{s}_2", s, "summer", 2), (f"oak_{s}_3", s, "summer", 3),
                    (f"oak_{s}_autumn", s, "autumn", 1), (f"oak_{s}_autumn_2", s, "autumn", 2),
                    (f"oak_{s}_winter", s, "winter", 1)]
    return out


def main():
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "assets" / "models" / "flora" / "trees" / "oak"
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, stage, season, variant in manifest():
        vox = build_oak(stage, season, variant)
        mesh = mesh_from_voxels(vox)
        size = write_glb(out_dir / f"{name}.glb", name, mesh)
        total += size
        h = max(y for _, y, _ in vox.cells) + 1
        xs = [x for x, _, _ in vox.cells]
        w = max(xs) - min(xs) + 1
        print("%-26s %-7s %-7s H%2d W%2d  %5d vox %6d tris %6.1f KB" % (
            name, stage, season, h, w, len(vox), len(mesh[3]) // 3, size / 1024))
    print("\nWrote %d oak GLBs (%.2f MB) at 1 vox/block." % (len(manifest()), total / 1024 / 1024))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Generate Deepdraft apple GLBs — chunky 1:1 deciduous fruit tree.

Same tree convention as pine: authored 1:1 (1 voxel = 1 block, scale 1.0; see
docs/60_asset_creation/61_voxel_art_guide.md). Style target: the chunky "Voxel
Trees" look — a broad rounded canopy of big cubes with a bobbly/protruding-cube
surface, a red-brown flared trunk, two-tone greens. Apples are shorter and
broader than the conifers.

Seasons: spring (blossom), summer (leafy), autumn (gold/rust), autumn_fruiting
(autumn + red apples, fruit-harvest overlay), winter (bare branches, no leaves).

Centred on the trunk at X=Z=0, base at Y=0. Sizes (blocks): ancient ~19 tall /
~17 wide, mature ~13 / ~11, sapling ~6 / ~5.
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

VOX_PER_BLOCK = 1


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)

LEAF_TOP  = _c(0x8BC34A)
LEAF_MID  = _c(0x689F38)
LEAF_DARK = _c(0x3F6F24)
SPR_TOP   = _c(0xC5E87B)
SPR_MID   = _c(0x9CCC55)
BLOSSOM   = [_c(0xF8D7E6), _c(0xFFFFFF), _c(0xF4B6C8), _c(0xFFDCEB)]
AU_GOLD   = _c(0xF0B733)
AU_RUST   = _c(0xC96A22)
AU_DARK   = _c(0x864018)
APPLE     = [_c(0xF0182D), _c(0xD20F26), _c(0xFF3B2F)]
TR_HI     = _c(0x9A5E38)
TR_MID    = _c(0x7A4A2B)
TR_DK     = _c(0x542F18)
BRANCH    = _c(0x5A3920)


def vary(color, amt, rng):
    f = 1.0 + rng.uniform(-amt, amt)
    return tuple(max(0.0, min(1.0, c * f)) for c in color)


def leaf_color(season, upper, rng):
    if season == "spring":
        pal = [SPR_TOP, SPR_MID] if upper else [SPR_MID, LEAF_MID]
    elif season in ("autumn", "autumn_fruiting"):
        pal = [AU_GOLD, AU_GOLD, AU_RUST] if upper else [AU_RUST, AU_DARK]
    else:  # summer
        pal = [LEAF_TOP, LEAF_MID] if upper else [LEAF_MID, LEAF_DARK]
    return vary(rng.choice(pal), 0.07, rng)


def bark(rng):
    r = rng.random()
    base = TR_DK if r < 0.30 else (TR_HI if r < 0.48 else TR_MID)
    return vary(base, 0.05, rng)


def _trunk_offset(y, top_y, bend_x, bend_z):
    if top_y <= 3:
        return 0, 0
    ox = bend_x if y > top_y * 0.45 else 0
    oz = bend_z if y > top_y * 0.68 else 0
    return ox, oz


def add_trunk(v, top_y, trunk_w, bare, flare, rng):
    bend_x = -1 if rng.random() < 0.5 else 1
    bend_z = -1 if rng.random() < 0.5 else 1
    for y in range(0, top_y):
        w = trunk_w
        if flare and y < 2:
            w = trunk_w + (flare if y == 0 else flare - 1)
        o = -(w // 2)
        ox, oz = _trunk_offset(y, top_y, bend_x, bend_z)
        for x in range(o, o + w):
            for z in range(o, o + w):
                v.set(x + ox, y, z + oz, bark(rng))


def _line(v, p0, p1, color_fn, rng):
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    steps = int(max(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))) + 1
    for s in range(steps + 1):
        t = s / max(1, steps)
        v.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t),
              round(z0 + (z1 - z0) * t), color_fn(rng))


def add_branches(v, start_y, top_y, reach, n, rng):
    """Bare winter branch structure fanning up and out from the trunk top."""
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.4, 0.4)
        ex = math.cos(ang) * reach
        ez = math.sin(ang) * reach
        ey = top_y + rng.uniform(-1, 1)
        _line(v, (0, start_y, 0), (ex, ey, ez), lambda r: vary(BRANCH, 0.06, r), rng)
        # one fork near the tip
        fx = ex + math.cos(ang + 0.6) * reach * 0.3
        fz = ez + math.sin(ang + 0.6) * reach * 0.3
        _line(v, (ex * 0.7, (start_y + ey) / 2, ez * 0.7), (fx, ey + 1, fz),
              lambda r: vary(BRANCH, 0.06, r), rng)


def add_canopy(v, cy, rx, ry, rz, season, rng):
    fruiting = season == "autumn_fruiting"
    # Low, broad orchard canopy: flatter bottom, wider side-to-side than front-to-back.
    for x in range(-rx - 1, rx + 2):
        for y in range(cy - ry - 1, cy + ry + 2):
            for z in range(-rz - 1, rz + 2):
                skew = 0.15 if x > 0 else -0.10
                e = ((x + skew * z) / rx) ** 2 + ((y - cy) / ry) ** 2 + (z / rz) ** 2
                if e > 1.0 + rng.uniform(-0.12, 0.10):
                    continue
                if e < 0.40 and rng.random() < 0.14:   # small interior pockets
                    continue
                if y < cy - ry * 0.65 and rng.random() < 0.45:
                    continue
                v.set(x, y, z, leaf_color(season, y > cy, rng))
    cells = list(v.cells.items())
    # bobbly protruding cubes on the surface
    bumps = {}
    for (x, y, z), c in cells:
        if c[0] > 0.55 and c[2] > 0.30 and c[0] > c[1]:
            continue  # skip trunk voxels (reddish)
        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1)):
            n = (x + dx, y + dy, z + dz)
            if n in v.cells or n in bumps:
                continue
            if rng.random() < 0.16:
                bumps[n] = leaf_color(season, dy >= 0, rng)
    v.cells.update(bumps)
    # season dressing on the outer/upper surface
    if season == "spring":
        for (x, y, z), c in list(v.cells.items()):
            if (x, y + 1, z) not in v.cells and y > cy - ry * 0.35 and rng.random() < 0.24:
                v.cells[(x, y, z)] = vary(rng.choice(BLOSSOM), 0.04, rng)
    if fruiting:
        clusters = max(8, int(rx * rz * 0.45))
        candidates = []
        for (x, y, z), c in list(v.cells.items()):
            below_open = (x, y - 1, z) not in v.cells
            outer = abs(x) > rx * 0.35 or abs(z) > rz * 0.35
            if y < cy + ry * 0.45 and y > cy - ry * 0.95 and outer and below_open:
                candidates.append((x, y, z))
        rng.shuffle(candidates)
        for x, y, z in candidates[:clusters]:
            color = vary(rng.choice(APPLE), 0.04, rng)
            v.cells[(x, y, z)] = color
            if rng.random() < 0.55:
                v.cells[(x, y - 1, z)] = color
            if rng.random() < 0.35:
                v.cells[(x + (1 if x < 0 else -1), y, z)] = color


STAGES = {
    "sapling": dict(H=6,  cy=4,  rx=3, ry=2, trunk_w=1, bare=2, flare=0),
    "mature":  dict(H=12, cy=8,  rx=6, ry=3, trunk_w=2, bare=4, flare=1),
    "ancient": dict(H=17, cy=11, rx=9, ry=5, trunk_w=3, bare=5, flare=2),
}
# variant radius multipliers (summer 1-3, autumn 1-2; spring/winter/fruiting use 1)
VMUL = {1: 1.00, 2: 0.90, 3: 1.07}


def build_apple(stage, season="summer", variant=1):
    p = STAGES[stage]
    rng = random.Random(f"apple1:{stage}:{season}:{variant}")
    v = Voxels()
    rx = max(1, int(round(p["rx"] * VMUL[variant])))
    rz = max(1, int(round(p["rx"] * 0.82 * VMUL[variant])))
    ry = p["ry"]
    cy = p["cy"]

    if season == "winter":
        add_trunk(v, p["bare"] + 2, p["trunk_w"], p["bare"], p["flare"], rng)
        add_branches(v, p["bare"], cy + ry - 1, rx, 3 if stage != "ancient" else 4, rng)
    else:
        add_trunk(v, cy, p["trunk_w"], p["bare"], p["flare"], rng)
        add_canopy(v, cy, rx, ry, rz, season, rng)
    return v


def manifest():
    out = []
    for stage in ("sapling", "mature", "ancient"):
        if stage == "sapling":
            out += [("apple_sapling_spring", stage, "spring", 1),
                    ("apple_sapling", stage, "summer", 1),
                    ("apple_sapling_autumn", stage, "autumn", 1),
                    ("apple_sapling_winter", stage, "winter", 1)]
        else:
            s = stage
            out += [(f"apple_{s}_spring", s, "spring", 1),
                    (f"apple_{s}", s, "summer", 1),
                    (f"apple_{s}_2", s, "summer", 2),
                    (f"apple_{s}_3", s, "summer", 3),
                    (f"apple_{s}_autumn", s, "autumn", 1),
                    (f"apple_{s}_autumn_2", s, "autumn", 2),
                    (f"apple_{s}_autumn_fruiting", s, "autumn_fruiting", 1),
                    (f"apple_{s}_winter", s, "winter", 1)]
    return out


def main():
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "assets" / "models" / "flora" / "trees" / "apple"
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, stage, season, variant in manifest():
        vox = build_apple(stage, season, variant)
        mesh = mesh_from_voxels(vox)
        size = write_glb(out_dir / f"{name}.glb", name, mesh)
        total += size
        h = max(y for _, y, _ in vox.cells) + 1
        xs = [x for x, _, _ in vox.cells]
        w = max(xs) - min(xs) + 1
        print("%-30s %-7s %-16s H%2d W%2d  %5d vox %6d tris %6.1f KB" % (
            name, stage, season, h, w, len(vox), len(mesh[3]) // 3, size / 1024))
    print("\nWrote %d apple GLBs (%.2f MB) at 1 vox/block." % (len(manifest()), total / 1024 / 1024))


if __name__ == "__main__":
    main()

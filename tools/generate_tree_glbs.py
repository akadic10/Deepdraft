#!/usr/bin/env python3
"""
Generate Deepdraft tree GLBs.

The tree assets use the same simple GLB structure as the procedural dwarf
parts: one flat-shaded mesh with POSITION, NORMAL, COLOR_0, and indices.
Coordinates are authored in MagicaVoxel-style voxel units; Godot import scale
handles conversion to world units.
"""

import argparse
import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb


OAK_LIGHT = (0xA6 / 255, 0x7C / 255, 0x52 / 255)
OAK_MID = (0x7A / 255, 0x52 / 255, 0x30 / 255)
OAK_DARK = (0x4E / 255, 0x30 / 255, 0x18 / 255)
OAK_GREY = (0x6E / 255, 0x62 / 255, 0x58 / 255)

LEAF_SUMMER = (0x6E / 255, 0xAE / 255, 0x35 / 255)
LEAF_SUMMER_HI = (0xB8 / 255, 0xE6 / 255, 0x48 / 255)
LEAF_SHADOW = (0x2E / 255, 0x52 / 255, 0x18 / 255)
LEAF_SPRING = (0x8A / 255, 0xCA / 255, 0x3E / 255)
LEAF_SPRING_HI = (0xC8 / 255, 0xF0 / 255, 0x50 / 255)
LEAF_AUTUMN_GOLD = (0xC8 / 255, 0x88 / 255, 0x20 / 255)
LEAF_AUTUMN_RUST = (0xA0 / 255, 0x48 / 255, 0x18 / 255)
LEAF_WINTER_BARE = (0x5C / 255, 0x48 / 255, 0x30 / 255)


def vary(color, amount, rng):
    f = 1.0 + rng.uniform(-amount, amount)
    return tuple(max(0.0, min(1.0, c * f)) for c in color)


def choose_leaf(season, rng, top=False):
    if season == "spring":
        palette = [LEAF_SPRING, LEAF_SPRING, LEAF_SUMMER, LEAF_SPRING_HI if top else LEAF_SHADOW]
    elif season == "autumn":
        palette = [LEAF_AUTUMN_GOLD, LEAF_AUTUMN_GOLD, LEAF_AUTUMN_RUST, LEAF_SHADOW]
    else:
        palette = [LEAF_SUMMER, LEAF_SUMMER, LEAF_SUMMER_HI if top else LEAF_SUMMER, LEAF_SHADOW]
    return vary(rng.choice(palette), 0.10, rng)


def bark_color(age, y, rng):
    base = OAK_GREY if age == "ancient" and rng.random() < 0.28 else OAK_MID
    if rng.random() < 0.20:
        base = OAK_LIGHT
    if rng.random() < 0.22 or y % 7 in (0, 1):
        base = OAK_DARK
    return vary(base, 0.06, rng)


def add_trunk(v, cx, cz, width, height, age, rng):
    half = width // 2
    for y in range(height):
        twist = int(round(math.sin(y * 0.23) * (1 if age == "ancient" else 0.5)))
        taper = 1 if y > height * 0.72 and width > 6 else 0
        x0 = cx - half + twist + taper
        x1 = cx + half + twist - taper
        z0 = cz - half - twist // 2 + taper
        z1 = cz + half - twist // 2 - taper
        for x in range(x0, x1):
            for z in range(z0, z1):
                if rng.random() < 0.035 and 0 < x - x0 < x1 - x0 - 1:
                    continue
                v.set(x, y, z, bark_color(age, y, rng))

    flare = 4 if age == "ancient" else 3
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)):
        length = flare + (2 if age == "ancient" and abs(dx) + abs(dz) == 1 else 0)
        for i in range(length):
            h = max(1, flare - i)
            x0 = cx + dx * (half - 1 + i)
            z0 = cz + dz * (half - 1 + i)
            v.box(x0 - 1, x0 + 2, 0, h, z0 - 1, z0 + 2, OAK_DARK)


def add_branch(v, start, end, thickness, color, rng):
    x, y, z = start
    ex, ey, ez = end
    steps = max(abs(ex - x), abs(ey - y), abs(ez - z), 1)
    for i in range(steps + 1):
        t = i / steps
        px = round(x + (ex - x) * t)
        py = round(y + (ey - y) * t)
        pz = round(z + (ez - z) * t)
        r = max(1, thickness - i // 11)
        c = vary(color, 0.07, rng)
        v.box(px - r, px + r + 1, py - r, py + r + 1, pz - r, pz + r + 1, c)


def add_leaf_cluster(v, cx, cy, cz, rx, ry, rz, season, rng):
    x0, x1 = math.floor(cx - rx), math.ceil(cx + rx) + 1
    y0, y1 = math.floor(cy - ry), math.ceil(cy + ry) + 1
    z0, z1 = math.floor(cz - rz), math.ceil(cz + rz) + 1
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                nx = abs((x + 0.5 - cx) / max(rx, 1))
                ny = abs((y + 0.5 - cy) / max(ry, 1))
                nz = abs((z + 0.5 - cz) / max(rz, 1))
                # Superellipsoid: rounder than a box, squarer than a sphere.
                d = nx ** 3.4 + ny ** 3.0 + nz ** 3.4
                if d > 1.0:
                    continue
                shell = d > 0.62
                if shell and rng.random() < 0.09:
                    continue
                if not shell and rng.random() < 0.018:
                    continue
                top = y >= cy + ry * 0.33
                color = choose_leaf(season, rng, top=top)
                if y < cy - ry * 0.35 and rng.random() < 0.55:
                    color = vary(LEAF_SHADOW, 0.08, rng)
                v.set(x, y, z, color)


def add_leaf_block(v, box, season, rng, carve=1):
    x0, x1, y0, y1, z0, z1 = box
    add_leaf_cluster(
        v,
        (x0 + x1) / 2,
        (y0 + y1) / 2,
        (z0 + z1) / 2,
        max(1, (x1 - x0) / 2),
        max(1, (y1 - y0) / 2),
        max(1, (z1 - z0) / 2),
        season,
        rng,
    )


def add_leaf_sprigs(v, cx, cy, cz, rx, ry, rz, season, rng, count):
    for _ in range(count):
        face = rng.choice(("x", "z", "top"))
        if face == "top":
            x = round(cx + rng.uniform(-rx * 0.55, rx * 0.55))
            y = round(cy + ry + rng.uniform(-1, 1))
            z = round(cz + rng.uniform(-rz * 0.55, rz * 0.55))
        elif face == "x":
            x = round(cx + rng.choice((-1, 1)) * rng.uniform(rx * 0.72, rx * 1.05))
            y = round(cy + rng.uniform(-ry * 0.45, ry * 0.55))
            z = round(cz + rng.uniform(-rz * 0.6, rz * 0.6))
        else:
            x = round(cx + rng.uniform(-rx * 0.6, rx * 0.6))
            y = round(cy + rng.uniform(-ry * 0.45, ry * 0.55))
            z = round(cz + rng.choice((-1, 1)) * rng.uniform(rz * 0.72, rz * 1.05))
        size = rng.choice((1, 1, 1, 2))
        v.box(x, x + size, y, y + size, z, z + size, choose_leaf(season, rng, top=True), shade=False)


def add_hanging_leaf_pad(v, cx, cy, cz, rx, rz, season, rng):
    for x in range(round(cx - rx), round(cx + rx) + 1):
        for z in range(round(cz - rz), round(cz + rz) + 1):
            nx = abs((x + 0.5 - cx) / max(rx, 1))
            nz = abs((z + 0.5 - cz) / max(rz, 1))
            if nx ** 2.8 + nz ** 2.8 > 1.0:
                continue
            depth = 1 + (1 if rng.random() < 0.35 else 0)
            for y in range(cy - depth, cy + 1):
                if rng.random() < 0.14:
                    continue
                color = choose_leaf(season, rng, top=False)
                if y < cy:
                    color = vary(LEAF_SHADOW, 0.08, rng)
                v.set(x, y, z, color)


def add_oak_canopy(v, stage, season, variant, rng):
    if stage == "mature":
        clusters = [
            (12, 29, 12, 9.4, 5.2, 9.4),
            (5, 31, 12, 6.7, 4.9, 6.9),
            (19, 31, 12, 6.7, 4.9, 6.9),
            (12, 31, 5, 6.9, 4.8, 6.7),
            (12, 31, 19, 6.9, 4.8, 6.7),
            (4, 25, 5, 5.6, 4.0, 5.6),
            (20, 25, 19, 5.6, 4.0, 5.6),
            (5, 24, 20, 5.4, 3.8, 5.4),
            (19, 24, 4, 5.4, 3.8, 5.4),
            (12, 38, 12, 7.8, 5.8, 7.8),
            (7, 42, 9, 5.1, 4.6, 5.1),
            (17, 42, 15, 5.1, 4.6, 5.1),
            (12, 48, 12, 5.6, 4.8, 5.6),
        ]
        if variant == 2:
            clusters[1] = (5, 32, 13, 6.9, 4.9, 6.2)
            clusters[4] = (12, 32, 19, 6.3, 4.8, 5.8)
            clusters[10] = (9, 43, 9, 5.2, 4.6, 5.2)
        elif variant == 3:
            clusters[2] = (18, 32, 11, 6.1, 5.0, 6.8)
            clusters[3] = (13, 32, 5, 6.0, 4.9, 6.4)
            clusters[12] = (13, 48, 13, 5.8, 4.8, 5.8)
    else:
        clusters = [
            (20, 42, 20, 14.8, 6.5, 14.8),
            (8, 45, 19, 9.4, 5.8, 9.0),
            (32, 45, 21, 9.4, 5.8, 9.0),
            (20, 45, 8, 9.0, 5.7, 9.4),
            (20, 45, 32, 9.0, 5.7, 9.4),
            (5, 37, 8, 7.5, 4.8, 7.4),
            (35, 37, 32, 7.5, 4.8, 7.4),
            (8, 36, 35, 7.4, 4.7, 7.5),
            (32, 36, 5, 7.4, 4.7, 7.5),
            (20, 55, 20, 11.2, 7.5, 11.2),
            (12, 61, 13, 7.4, 5.6, 7.4),
            (28, 61, 27, 7.4, 5.6, 7.4),
            (20, 70, 20, 7.0, 5.4, 7.0),
        ]
        if variant == 2:
            clusters[1] = (8, 46, 18, 9.6, 5.8, 8.6)
            clusters[4] = (19, 46, 32, 8.4, 5.8, 9.0)
            clusters[10] = (13, 62, 12, 7.4, 5.6, 6.8)
        elif variant == 3:
            clusters[2] = (31, 46, 20, 8.8, 6.0, 9.0)
            clusters[3] = (21, 46, 8, 9.2, 5.8, 8.4)
            clusters[12] = (21, 70, 21, 7.2, 5.4, 7.2)

    for cx, cy, cz, rx, ry, rz in clusters:
        add_leaf_cluster(v, cx, cy, cz, rx, ry, rz, season, rng)
        add_leaf_sprigs(v, cx, cy, cz, rx, ry, rz, season, rng, 14 if stage == "ancient" else 8)
        if cy < (48 if stage == "ancient" else 34):
            add_hanging_leaf_pad(v, cx, round(cy - ry * 0.72), cz, rx * 0.78, rz * 0.78, season, rng)


def clamp_voxels(v, width, height, depth):
    for key in list(v.cells):
        x, y, z = key
        if x < 0 or x >= width or y < 0 or y >= height or z < 0 or z >= depth:
            v.cells.pop(key, None)


def build_oak(stage, season="summer", variant=1):
    rng = random.Random(f"oak:{stage}:{season}:{variant}")
    v = Voxels()

    if stage == "sapling":
        add_trunk(v, 4, 4, 3, 12, "mature", rng)
        if season != "winter":
            add_leaf_block(v, (1, 7, 10, 16, 1, 7), season, rng, carve=1)
            add_leaf_block(v, (2, 6, 12, 16, 2, 6), season, rng, carve=1)
        else:
            add_branch(v, (4, 9, 4), (2, 14, 4), 1, LEAF_WINTER_BARE, rng)
            add_branch(v, (4, 10, 4), (6, 14, 5), 1, LEAF_WINTER_BARE, rng)
        clamp_voxels(v, 8, 16, 8)
        return v

    mature = stage == "mature"
    size = 24 if mature else 40
    cx = cz = size // 2
    trunk_width = 7 if mature else 12
    trunk_height = 31 if mature else 45
    age = "mature" if mature else "ancient"
    add_trunk(v, cx, cz, trunk_width, trunk_height, age, rng)

    if mature:
        branch_specs = [
            ((cx, 22, cz), (3, 30, 12), 2),
            ((cx, 23, cz), (21, 31, 12), 2),
            ((cx, 24, cz), (12, 31, 3), 2),
            ((cx, 24, cz), (12, 32, 21), 2),
            ((cx, 29, cz), (7, 39, 8), 1),
            ((cx, 30, cz), (17, 40, 16), 1),
            ((cx, 28, cz), (12, 45, 12), 1),
        ]
    else:
        branch_specs = [
            ((cx, 32, cz), (3, 44, 20), 3),
            ((cx, 33, cz), (37, 45, 20), 3),
            ((cx, 34, cz), (20, 45, 3), 3),
            ((cx, 34, cz), (20, 46, 37), 3),
            ((cx, 42, cz), (8, 58, 10), 2),
            ((cx, 43, cz), (32, 58, 29), 2),
            ((cx, 43, cz), (21, 65, 21), 2),
        ]
    for start, end, thickness in branch_specs:
        add_branch(v, start, end, thickness, OAK_DARK if season == "winter" else OAK_MID, rng)

    if season == "winter":
        # Bare winter oaks keep a few squared-off twig pads, but no green leaf
        # clumps. These also extend to the seasonal collision footprint.
        for _, end, thickness in branch_specs:
            x, y, z = end
            v.box(x - thickness, x + thickness + 1, y, y + 2, z - thickness, z + thickness + 1, LEAF_WINTER_BARE)
        if mature:
            v.box(cx - 1, cx + 2, 48, 56, cz - 1, cz + 2, LEAF_WINTER_BARE)
        else:
            v.box(cx - 2, cx + 3, 70, 80, cz - 2, cz + 3, LEAF_WINTER_BARE)
    else:
        add_oak_canopy(v, stage, season, variant, rng)

    clamp_voxels(v, 24 if mature else 40, 56 if mature else 80, 24 if mature else 40)
    return v


def oak_manifest():
    return [
        ("oak_sapling", "sapling", "summer", 1),
        ("oak_sapling_spring", "sapling", "spring", 1),
        ("oak_sapling_autumn", "sapling", "autumn", 1),
        ("oak_sapling_winter", "sapling", "winter", 1),
        ("oak_mature", "mature", "summer", 1),
        ("oak_mature_2", "mature", "summer", 2),
        ("oak_mature_3", "mature", "summer", 3),
        ("oak_mature_spring", "mature", "spring", 1),
        ("oak_mature_autumn", "mature", "autumn", 1),
        ("oak_mature_autumn_2", "mature", "autumn", 2),
        ("oak_mature_winter", "mature", "winter", 1),
        ("oak_ancient", "ancient", "summer", 1),
        ("oak_ancient_2", "ancient", "summer", 2),
        ("oak_ancient_3", "ancient", "summer", 3),
        ("oak_ancient_spring", "ancient", "spring", 1),
        ("oak_ancient_autumn", "ancient", "autumn", 1),
        ("oak_ancient_autumn_2", "ancient", "autumn", 2),
        ("oak_ancient_winter", "ancient", "winter", 1),
    ]


def main():
    ap = argparse.ArgumentParser(description="Generate Deepdraft tree GLBs.")
    ap.add_argument("--species", choices=["oak"], default="oak")
    ap.add_argument("--out", default=None, help="output directory for generated oak GLBs")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    out_dir = Path(args.out) if args.out else repo / "assets" / "models" / "flora" / "trees" / "oak"

    total = 0
    for name, stage, season, variant in oak_manifest():
        vox = build_oak(stage, season, variant)
        mesh = mesh_from_voxels(vox)
        path = out_dir / f"{name}.glb"
        size = write_glb(path, name, mesh)
        total += size
        print(f"{name:24s} {stage:7s} {season:7s} v{variant} {len(vox):6d} vox {len(mesh[3]) // 3:7d} tris {size:9d} B")

    print(f"\nWrote {len(oak_manifest())} oak GLBs ({total / 1024 / 1024:.2f} MB) to {out_dir}")


if __name__ == "__main__":
    main()

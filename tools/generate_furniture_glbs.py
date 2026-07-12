#!/usr/bin/env python3
"""
Generate Deepdraft storage-furniture GLBs — doc 19 Phase 1.

Three placed forms + three item forms (the doc 19 three-form model: the item
form is the carryable drop dwarves fetch and haul; the placed form is what
stands in the world; the GHOST is the placed form rendered translucent at
runtime — no separate ghost asset).

MATERIAL RULE (Alen, 2026-07-11 — doc 61 §1): furniture is WOODWORK. All three
pieces are wood-bodied with iron accents; stone appears nowhere here.

CONVENTIONS (doc 61 §5.7 / 41b): items-class assets — 8 voxels per block, the
0.125 scale BAKED into exported vertex positions, Godot import Root Scale
stays 1.0. Authored centred on X=Z=0 with the base at Y=0 (the drop/dwarf
convention; the placement controller positions the node at the cell centre).

DETERMINISM: fixed seed; every run regenerates byte-identical files.

Outputs (paths must match data/furniture/*.json "model" and
data/entities/items/resources.json "model" fields):
  assets/models/furniture/{barrel,storage_crate,storage_shelf}.glb   (placed)
  assets/models/items/furniture/{barrel,storage_chest,storage_shelf}.glb (item)
Review sheet: tmp/furniture_review/furniture_sheet.png
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

EXPORT_SCALE = 0.125
SEED = 1919


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)


def _scale_c(c, f):
    return (min(1.0, c[0] * f), min(1.0, c[1] * f), min(1.0, c[2] * f))


# ── Doc 61 master palette ─────────────────────────────────────────────────────
OAK_LIGHT   = _c(0xA67C52)
OAK_MID     = _c(0x7A5230)
OAK_DARK    = _c(0x4E3018)
PLANK       = _c(0x8C6840)
PLANK_DARK  = _c(0x5A3E20)
IRON_DULL   = _c(0x6A6868)
IRON_HI     = _c(0x9A9898)
IRON_DARK   = _c(0x3A3838)


def _wood_jitter(rng, base):
    """Mild per-voxel value variation so wood never flat-fills (doc 61 §7)."""
    return _scale_c(base, rng.uniform(0.93, 1.07))


# ── Barrel — placed form, 1×1×1 block (8×8×8) ────────────────────────────────
# Doc 61 §5.4: classic fat barrel, oak staves, iron bands, bung hole on top.

BARREL_RADII = [2.9, 3.4, 3.8, 4.0, 4.0, 3.8, 3.4, 2.9]   # bulge profile
BARREL_BANDS = (1, 6)                                       # iron band rows


def build_barrel(height=8, radii=None, bands=None, bung=True):
    rng = random.Random(SEED)
    radii = radii or BARREL_RADII
    bands = bands if bands is not None else BARREL_BANDS
    v = Voxels()
    half = 8 // 2
    for y in range(height):
        r = radii[y]
        for x in range(-half, half):
            for z in range(-half, half):
                if math.hypot(x + 0.5, z + 0.5) > r:
                    continue
                if y in bands:
                    col = IRON_HI if abs(x + 0.5) > r - 1.2 or abs(z + 0.5) > r - 1.2 else IRON_DULL
                else:
                    # Vertical staves: alternate light/mid by angle sector.
                    ang = math.atan2(z + 0.5, x + 0.5)
                    sector = int((ang + math.pi) / (math.pi / 4)) % 2
                    col = _wood_jitter(rng, OAK_LIGHT if sector else OAK_MID)
                v.cells[(x, y, z)] = col
    if bung:
        top = height - 1
        v.cells[(0, top, 0)] = OAK_DARK          # bung hole, 1-voxel dark indent
    return v


# ── Chest / crate — placed form, 1×1×1 block (8×7×8 body + ajar lid) ─────────
# Doc 61 §5.4: plank seams, iron corner brackets, lid slightly ajar.

def build_storage_chest(size=8, mini=False):
    rng = random.Random(SEED + 1)
    v = Voxels()
    half = size // 2
    body_h = size - 2                      # body top leaves room for the lid
    for x in range(-half, half):
        for z in range(-half, half):
            for y in range(0, body_h):
                seam = (y % 3 == 2)        # horizontal plank seam rows
                col = _wood_jitter(rng, PLANK_DARK if seam else PLANK)
                v.cells[(x, y, z)] = col
    # Interior shadow where the ajar lid exposes the inside.
    for z in range(-half, half):
        v.cells[(-half, body_h - 1, z)] = _scale_c(PLANK_DARK, 0.55)
    # Iron corner brackets (bottom and top of the body).
    for cx in (-half, half - 1):
        for cz in (-half, half - 1):
            for y in list(range(0, 2)) + list(range(body_h - 2, body_h)):
                v.cells[(cx, y, cz)] = IRON_DULL
    # Lid: 1 voxel thick, slid one voxel toward +X (ajar).
    lid_shift = 0 if mini else 1
    for x in range(-half + lid_shift, half + lid_shift):
        if x >= half:                      # never exceed the block envelope
            continue
        for z in range(-half, half):
            col = _wood_jitter(rng, PLANK)
            if x in (-half + lid_shift, half - 1) or z in (-half, half - 1):
                col = _wood_jitter(rng, PLANK_DARK)
            v.cells[(x, body_h, z)] = col
    return v


# ── Storage shelf — placed form, 1×1×2 blocks (8×16×8) ───────────────────────
# Doc 19 §4 Phase 1 spec (material rule): heavy wood uprights, two plank
# levels, iron brackets, solid back panel (wall side, -Z), anchor surfaces
# clear of the uprights. Items render at runtime on the anchor points.

SHELF_H = 16
SHELF_LEVEL_Y = (0, 7)      # slab rows; items sit on top of each (y=1 and y=8)


def build_storage_shelf():
    rng = random.Random(SEED + 2)
    v = Voxels()
    half = 4
    # Base plinth + mid shelf slab + top cap: full-footprint planks.
    for slab_y in (SHELF_LEVEL_Y[0], SHELF_LEVEL_Y[1], SHELF_H - 1):
        for x in range(-half, half):
            for z in range(-half, half):
                edge = x in (-half, half - 1) or z in (-half, half - 1)
                v.cells[(x, slab_y, z)] = _wood_jitter(rng, PLANK_DARK if edge else PLANK)
    # Corner posts, full height — chunky dwarven uprights.
    for cx in (-half, half - 1):
        for cz in (-half, half - 1):
            for y in range(SHELF_H):
                v.cells[(cx, y, cz)] = _wood_jitter(rng, OAK_MID)
    # Back panel (the wall side, -Z): solid planks between the posts.
    for x in range(-half + 1, half - 1):
        for y in range(SHELF_H):
            seam = (y % 4 == 3)
            v.cells[(x, y, -half)] = _wood_jitter(rng, PLANK_DARK if seam else OAK_DARK)
    # Iron brackets under the mid shelf and top cap, against the posts.
    for cx in (-half, half - 1):
        for y in (SHELF_LEVEL_Y[1] - 1, SHELF_H - 2):
            v.cells[(cx, y, -half + 1)] = IRON_DULL
            v.cells[(cx, y, half - 2)] = IRON_DULL
    return v


# ── Item forms — mini versions (the carryable drop, ~half-block) ─────────────

def build_barrel_item():
    return build_barrel(height=5, radii=[1.6, 1.9, 2.1, 1.9, 1.6], bands=(2,), bung=True)


def build_chest_item():
    return build_storage_chest(size=5, mini=True)


def build_shelf_item():
    """Flat bundle of shelf parts: two short posts lashed to plank slabs —
    reads as 'shelf kit', not a shrunken shelf."""
    rng = random.Random(SEED + 3)
    v = Voxels()
    for y in (0, 1):                          # two stacked plank slabs 6×2×3
        for x in range(-3, 3):
            for z in range(-1, 2):
                v.cells[(x, y, z)] = _wood_jitter(rng, PLANK if y else PLANK_DARK)
    for x in (-2, 1):                          # two posts laid across the top
        for z in range(-1, 2):
            v.cells[(x, 2, z)] = _wood_jitter(rng, OAK_MID)
    v.cells[(-3, 2, 0)] = IRON_DULL            # bracket fittings tied on
    v.cells[(2, 2, 0)] = IRON_DULL
    return v


# ── Review sheet (the render_dwarf_qa painter view, self-contained) ───────────

PX = 6


def _render(vox, view):
    from PIL import Image, ImageDraw
    cells = vox.cells
    if view == "front":
        pts = sorted(((z, x, y, c) for (x, y, z), c in cells.items()))
        pts = [(x, y, c, d) for (d, x, y, c) in pts]
    elif view == "side":
        pts = sorted(((x, z, y, c) for (x, y, z), c in cells.items()))
        pts = [(z, y, c, d) for (d, z, y, c) in pts]
    elif view == "top":
        pts = sorted(((y, x, z, c) for (x, y, z), c in cells.items()))
        pts = [(x, z, c, d) for (d, x, z, c) in pts]
    us = [p[0] for p in pts]
    vs = [p[1] for p in pts]
    u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
    d0 = min(p[3] for p in pts)
    span = max(1, max(p[3] for p in pts) - d0)
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", ((u1 - u0 + 1) * PX, (v1 - v0 + 1) * PX), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for u, vy, c, d in pts:
        f = 0.78 + 0.22 * ((d - d0) / span)
        col = tuple(int(min(1.0, ch * f) * 255) for ch in c) + (255,)
        px, py = (u - u0) * PX, (v1 - vy) * PX
        draw.rectangle([px, py, px + PX - 1, py + PX - 1], fill=col)
    return img


def _sheet(pieces, out_png):
    from PIL import Image, ImageDraw
    pad, label_h = 14, 16
    cols = []
    for name, vox in pieces:
        views = [_render(vox, v) for v in ("front", "side", "top")]
        w = sum(im.width for im in views) + pad * 2
        h = max(im.height for im in views) + label_h
        cols.append((name, views, w, h))
    sheet = Image.new("RGBA", (sum(c[2] for c in cols) + pad,
                               max(c[3] for c in cols) + pad * 2), (30, 32, 36, 255))
    draw = ImageDraw.Draw(sheet)
    x = pad
    for name, views, w, h in cols:
        draw.text((x, 4), name, fill=(220, 220, 220, 255))
        vx = x
        for im in views:
            sheet.alpha_composite(im, (vx, pad + label_h + (h - label_h - im.height)))
            vx += im.width + 2
        x += w
    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    return out_png


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    root = Path(__file__).resolve().parent.parent
    placed_dir = root / "assets" / "models" / "furniture"
    item_dir = root / "assets" / "models" / "items" / "furniture"

    placed = [
        ("barrel", build_barrel()),
        ("storage_crate", build_storage_chest()),
        ("storage_shelf", build_storage_shelf()),
    ]
    items = [
        ("barrel", build_barrel_item()),
        ("storage_chest", build_chest_item()),
        ("storage_shelf", build_shelf_item()),
    ]

    total = 0
    for name, vox in placed:
        size = write_glb(placed_dir / f"{name}.glb", name, mesh_from_voxels(vox), EXPORT_SCALE)
        print(f"  furniture/{name + '.glb':22s} {len(vox):4d} voxels  {size:6d} B")
        total += size
    for name, vox in items:
        size = write_glb(item_dir / f"{name}.glb", f"{name}_item", mesh_from_voxels(vox), EXPORT_SCALE)
        print(f"  items/furniture/{name + '.glb':16s} {len(vox):4d} voxels  {size:6d} B")
        total += size

    sheet = _sheet(
        [(f"{n} (placed)", v) for n, v in placed] + [(f"{n} (item)", v) for n, v in items],
        root / "tmp" / "furniture_review" / "furniture_sheet.png")
    print(f"furniture set complete ({total / 1024:.1f} KB); review sheet -> {sheet}")


if __name__ == "__main__":
    main()
                                                                                                                                                                                                  
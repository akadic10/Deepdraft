#!/usr/bin/env python3
"""
Generate Deepdraft ore-drop GLBs — one shared rock lump, per-ore colored flecks.

ART DIRECTION (Alen, 2026-06-10, Stonehearth-style reference):
  Every metal ore drop is the SAME chunky rock shape with the same fleck
  pattern of surface voxel patches. Only the fleck COLORS change per ore type
  (copper orange, gold yellow, ...). This makes ore drops instantly comparable
  at RTS zoom: shape says "ore chunk", color says which ore.
  (A separate gold-nugget item existed briefly and was cut — Alen, 2026-06-10:
  gold ore is enough; no second gold item.)

CANONICAL SHAPE (Alen-authored, 2026-06-10): the rock body is hand-built in
  Voxelator and lives in tools/ore_base_shape.obj — an 8x8x8, fully
  octahedrally-symmetric rounded cube (identical from all six faces AND under
  90-degree rotations; layer profile 4x4 / 6x6 / 8x8 x4 / 6x6 / 4x4). This
  generator PARSES that OBJ and solid-fills its interior (304 voxels; the
  authored file is a hollow shell) — to change the shape, re-export the OBJ
  from Voxelator and rerun. No procedural shape math, no erosion: the authored
  geometry IS the silhouette. It occupies the full one-block envelope
  (1.0 x 1.0 x 1.0 world units); a drop never exceeds the block it came from.

CONVENTIONS (doc 61 / 41b): items are characters-class assets — 8 voxels per
  block, the 0.125 scale BAKED into exported vertex positions (dwarf-generator
  convention), Godot import Root Scale stays 1.0. Authored centred on X=Z=0
  with the base at Y=0.

  Fleck colors come from data/terrain/terrain_blocks.json ore hex values where
  they read well on grey stone (silver brightened, tin green-pushed — recorded
  in doc 61 §5.7) so drops visually match the terrain veins they came from.

DETERMINISM: a fixed seed drives erosion, body color variation, and fleck
  growth, so every run regenerates byte-identical shapes for all ores.

Outputs (paths must match data/entities/items/resources.json "model" fields):
  assets/models/items/ore/{copper_ore,tin_ore,iron_ore,silver_ore,coal,gold_ore}.glb
  assets/models/items/stone/rough_stone.glb
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb

EXPORT_SCALE = 0.125          # 8 voxels = 1 block (characters/items class, doc 61)
SEED = 4242                   # fixed: identical lump + fleck pattern every run


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)


def _scale(c, f):
    return (min(1.0, c[0] * f), min(1.0, c[1] * f), min(1.0, c[2] * f))


# ── Stone body — cool blue-greys matching the mountain rock bands ─────────────
STONE_LIGHT = _c(0x9AA3AA)
STONE_MID   = _c(0x7C858C)
STONE_DARK  = _c(0x5A626A)

# ── Per-ore fleck colors: (main, shadow) ─────────────────────────────────────
ORES = {
    "copper_ore": (_c(0xC87533), _c(0x8F4E1E)),   # terrain copper
    "tin_ore":    (_c(0xA9C49A), _c(0x74906A)),   # terrain tin, green pushed for read on grey
    "iron_ore":   (_c(0x7A5C45), _c(0x52392A)),   # terrain iron
    "silver_ore": (_c(0xE9EEF6), _c(0xAAB2C2)),   # terrain silver, brightened to pop on grey
    "gold_ore":   (_c(0xE8B820), _c(0xA87810)),   # doc 61 gold_bright/gold_mid family
}

# Coal is all-dark (Alen, 2026-06-10): NO grey stone body — the whole lump is
# dark greys and blacks. Same authored shape; body banded in the dark trio,
# fleck patches rendered as even darker seams for surface texture.
COAL_LIGHT = _c(0x39434B)
COAL_MID   = _c(0x252D33)
COAL_DARK  = _c(0x161C21)
COAL_SEAM      = _c(0x0E1318)
COAL_SEAM_DARK = _c(0x070B0E)

# ── Canonical shape: parse the authored OBJ, solid-fill the interior ─────────

BASE_SHAPE_OBJ = Path(__file__).resolve().parent / "ore_base_shape.obj"


def _load_base_shape(path):
    """Voxelizes Voxelator's axis-aligned unit-quad OBJ export back into grid
    cells, then solid-fills each column between its outermost Y boundaries
    (the authored file is a hollow shell; a solid body lets the mesher cull
    every interior face). Returns cells with base at y=0, centred on x=z=0
    (x,z shifted to -4..3 for the 8-wide shape — the project entity origin
    convention)."""
    verts, tris = [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "v":
                verts.append((float(p[1]), float(p[2]), float(p[3])))
            elif p[0] == "f":
                tris.append([int(t.split("/")[0]) - 1 for t in p[1:4]])

    # Collect Y-perpendicular faces per XZ column; fill min..max plane span.
    ycross = {}
    for t in tris:
        vs = [verts[i] for i in t]
        if len({v[1] for v in vs}) == 1:
            key = (int(min(v[0] for v in vs)), int(min(v[2] for v in vs)))
            ycross.setdefault(key, set()).add(int(vs[0][1]))
    cells = set()
    for (cx, cz), ys in ycross.items():
        for y in range(min(ys), max(ys)):
            cells.add((cx, y, cz))

    # Normalize: base at y=0, x/z centred on the origin.
    x0 = min(c[0] for c in cells)
    y0 = min(c[1] for c in cells)
    z0 = min(c[2] for c in cells)
    sx = max(c[0] for c in cells) - x0 + 1
    sz = max(c[2] for c in cells) - z0 + 1
    ox = x0 + sx // 2
    oz = z0 + sz // 2
    return set((x - ox, y - y0, z - oz) for (x, y, z) in cells)


def _exposure(cell, cells):
    x, y, z = cell
    n = 0
    for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        if (x + dx, y + dy, z + dz) not in cells:
            n += 1
    return n


def _surface(cells):
    return [c for c in cells if _exposure(c, cells) >= 1]


def _grow_patch(seed_cell, surface_set, taken, size, rng):
    """BFS blob of `size` surface voxels from seed (skips voxels already in a
    patch). Wraps edges/corners naturally — the reference's L-shaped patches."""
    patch = [seed_cell]
    taken.add(seed_cell)
    frontier = [seed_cell]
    while frontier and len(patch) < size:
        x, y, z = frontier.pop(rng.randrange(len(frontier)))
        nbs = [(x + dx, y + dy, z + dz)
               for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                                  (0, -1, 0), (0, 0, 1), (0, 0, -1))]
        rng.shuffle(nbs)
        for nb in nbs:
            if nb in surface_set and nb not in taken and len(patch) < size:
                patch.append(nb)
                taken.add(nb)
                frontier.append(nb)
    return patch


def _seed_toward(direction, surface, ry):
    """Surface voxel most aligned with a unit direction from the lump centre."""
    cx, cy, cz = 0.0, float(ry), 0.0
    best, best_d = None, -1e9
    for (x, y, z) in surface:
        vx, vy, vz = x - cx, y - cy, z - cz
        ln = math.sqrt(vx * vx + vy * vy + vz * vz) or 1.0
        d = (vx * direction[0] + vy * direction[1] + vz * direction[2]) / ln
        if d > best_d:
            best, best_d = (x, y, z), d
    return best


def build_rock_template():
    """Builds the shared geometry ONCE: (body_cells, body_color_of, fleck_patches).
    Every ore reuses it; only fleck colors differ."""
    rng = random.Random(SEED)
    cells = _load_base_shape(BASE_SHAPE_OBJ)
    ry = (max(c[1] for c in cells) + 1) // 2

    # Body colors: height-banded greys + mild per-voxel variation (top reads lit,
    # underside shadowed — baked, matching doc 61's highlight/shadow rule).
    body_color = {}
    top_y = max(c[1] for c in cells)
    for c in sorted(cells):                    # sorted -> deterministic rng draw order
        f = c[1] / top_y
        if f > 0.72:
            base = STONE_LIGHT
        elif f > 0.30:
            base = STONE_MID
        else:
            base = STONE_DARK
        body_color[c] = _scale(base, rng.uniform(0.95, 1.05))

    # Fleck patches: fixed directions around the lump so several show from any
    # camera angle; two big corner wraps + smaller chunks (the reference look).
    surface_set = set(_surface(cells))
    directions = [
        ((0.90, 0.30, 0.70), 7),     # right-front flank — big corner wrap
        ((-0.90, -0.35, 0.55), 6),   # left-front, low — visible in iso view
        ((0.35, -0.60, 0.85), 5),    # front-bottom corner wrap
        ((-0.55, 0.85, -0.35), 3),   # top-back chunk
        ((0.20, -0.55, -0.95), 4),   # back-bottom (visible when rotated)
    ]
    taken = set()
    patches = []
    for direction, size in directions:
        seed_cell = _seed_toward(direction, [s for s in surface_set if s not in taken], ry)
        if seed_cell is None:
            continue
        patches.append(_grow_patch(seed_cell, surface_set, taken, size, rng))
    return cells, body_color, patches


def build_ore(template, main, shadow):
    cells, body_color, patches = template
    v = Voxels()
    for c, col in body_color.items():
        v.cells[c] = col
    for patch in patches:
        mean_y = sum(p[1] for p in patch) / len(patch)
        for p in patch:
            v.cells[p] = main if p[1] >= mean_y else shadow
    return v


def build_rough_stone(template):
    """Plain stone drop (Alen, 2026-06-10): the same authored shape, banded
    greys only — no fleck patches. Dropped by mined rock blocks; the player's
    future void-fill / construction material."""
    cells, body_color, _patches = template
    v = Voxels()
    for c, col in body_color.items():
        v.cells[c] = col
    return v


def build_coal(template):
    """All-dark variant: same shape and patch pattern, no stone greys anywhere.
    Body re-banded in the dark trio; patches become near-black seams."""
    cells, _body_color, patches = template
    rng = random.Random(SEED + 3)
    v = Voxels()
    top_y = max(c[1] for c in cells)
    for c in sorted(cells):
        f = c[1] / top_y
        base = COAL_LIGHT if f > 0.72 else (COAL_MID if f > 0.30 else COAL_DARK)
        v.cells[c] = _scale(base, rng.uniform(0.95, 1.05))
    for patch in patches:
        mean_y = sum(p[1] for p in patch) / len(patch)
        for p in patch:
            v.cells[p] = COAL_SEAM if p[1] >= mean_y else COAL_SEAM_DARK
    return v


def main():
    out_dir = Path(__file__).resolve().parent.parent / "assets" / "models" / "items" / "ore"
    template = build_rock_template()

    total = 0
    for name, (main_c, shadow_c) in ORES.items():
        v = build_ore(template, main_c, shadow_c)
        size = write_glb(out_dir / f"{name}.glb", name, mesh_from_voxels(v), EXPORT_SCALE)
        print(f"  {name + '.glb':24s} {len(v):4d} voxels  {size:6d} B")
        total += size

    v = build_coal(template)
    size = write_glb(out_dir / "coal.glb", "coal", mesh_from_voxels(v), EXPORT_SCALE)
    print(f"  {'coal.glb':24s} {len(v):4d} voxels  {size:6d} B")
    total += size

    stone_dir = out_dir.parent / "stone"
    v = build_rough_stone(template)
    size = write_glb(stone_dir / "rough_stone.glb", "rough_stone", mesh_from_voxels(v), EXPORT_SCALE)
    print(f"  {'stone/rough_stone.glb':24s} {len(v):4d} voxels  {size:6d} B")
    total += size

    print(f"ore drop set complete -> {out_dir}  ({total / 1024:.1f} KB)")


if __name__ == "__main__":
    main()

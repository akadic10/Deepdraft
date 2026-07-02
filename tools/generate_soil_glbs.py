#!/usr/bin/env python3
"""
Generate Deepdraft soil-drop GLBs — the SAME rock lump as stone, coloured brown.

ART DIRECTION (Alen, 2026-06-26): soil drops use the EXACT shape of the stone
drop (rough_stone) — the hand-authored 8x8x8 octahedral rock lump from
tools/ore_base_shape.obj — only recoloured into earthy browns, one ramp per
soil type. At RTS zoom the shape reads "chunk of dug material", the colour says
which soil. This supersedes the earlier "low mound" attempt and doc 61 §5.7's
"soil = low mound" note (updated alongside this change): in play the mound did
not read as well as a recoloured stone chunk beside the real stone drops.

Like rough_stone, soil is PLAIN banded body colour — NO fleck patches. The
shape is shared (build_rock_template) so soil and stone are silhouette-identical
and instantly comparable in the pit. Fixed seed -> byte-identical regeneration.

CONVENTIONS (doc 61 / 41b): items class — 8 voxels per block, the 0.125 scale
BAKED into exported vertex positions (dwarf-generator convention); Godot import
Root Scale stays 1.0; never hand-edit .import. Centred X=Z, base at Y=0, full
one-block envelope (a drop never exceeds the block it came from).

Colour ramps derive from the terrain soil hex in terrain_blocks.json; dark and
cave are pushed darker / browner than the near-olive terrain values so the three
soils read apart (same readability-push the ore set used — doc 61 §5.7):
  light_soil #918154 (sandy pale)   dark_soil #807147 (clay)   cave_soil #6B4C2A (rich)

Outputs (paths must match data/entities/items/resources.json "model" fields):
  assets/models/items/soil/{light_soil,dark_soil,cave_soil}.glb
"""

import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb
from generate_ore_glbs import build_rock_template

EXPORT_SCALE = 0.125          # 8 voxels = 1 block (items class, doc 61)
SEED = 7311                   # fixed: identical per-voxel shading every run


def _c(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)


def _scale(c, f):
    return (min(1.0, c[0] * f), min(1.0, c[1] * f), min(1.0, c[2] * f))


# ── Per-soil brown ramps (light/mid/dark) — mirrors the stone grey trio ──────
# mid = terrain hex where it still reads; dark/cave pushed for contrast.
SOILS = {
    "light_soil": (_c(0xB0A06E), _c(0x918154), _c(0x6B5C3A)),
    "dark_soil":  (_c(0x7A6743), _c(0x5E4E32), _c(0x43381F)),
    "cave_soil":  (_c(0x8A6238), _c(0x6B4C2A), _c(0x4A331C)),
}


def build_soil(cells, ramp):
    """The rough_stone recipe (banded body, no flecks) with a brown ramp:
    top voxels light, middle mid, base dark, plus mild per-voxel variation so
    the flat-tinted lump still reads as a 3D voxel form (doc 61 shading rule)."""
    light, mid, dark = ramp
    rng = random.Random(SEED)
    v = Voxels()
    top_y = max(c[1] for c in cells)
    for c in sorted(cells):               # sorted -> deterministic rng draw order
        f = c[1] / top_y
        base = light if f > 0.72 else (mid if f > 0.30 else dark)
        v.cells[c] = _scale(base, rng.uniform(0.95, 1.05))
    return v


def main():
    out_dir = Path(__file__).resolve().parent.parent / "assets" / "models" / "items" / "soil"
    out_dir.mkdir(parents=True, exist_ok=True)
    cells, _body_color, _patches = build_rock_template()   # shared stone lump

    total = 0
    for name, ramp in SOILS.items():
        v = build_soil(cells, ramp)
        size = write_glb(out_dir / f"{name}.glb", name, mesh_from_voxels(v), EXPORT_SCALE)
        print(f"  {name + '.glb':22s} {len(v):4d} voxels  {size:6d} B")
        total += size

    print(f"soil drop set complete -> {out_dir}  ({total / 1024:.1f} KB)")


if __name__ == "__main__":
    main()

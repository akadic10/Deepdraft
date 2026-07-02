#!/usr/bin/env python3
"""
render_dwarf_qa.py — assembled-dwarf QA renders for the doc-15/17 regen pipeline
================================================================================

Builds fully assembled dwarfs from generate_dwarf_glb's voxel builders (with the
runtime tint multiply simulated per part) and renders orthographic front / side /
back views into one contact sheet PNG for review — the doc-15 QA step, without
opening Godot.

The previous QA renders (tmp/dwarf_visual_qa) were produced by an ad-hoc script
that never landed in the repo; this one is kept (same lesson as the pine
generator, doc 13).

Run:  python3 tools/render_dwarf_qa.py [--out PNG]   (default: tmp/dwarf_regen_preview/qa_sheet.png)
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

import generate_dwarf_glb as gen

# Runtime tints — mirror scripts/registries/DwarfAssets.gd.
SKIN_TONES = {
    "pale":   (0.96, 0.84, 0.77),
    "medium": (0.85, 0.65, 0.50),
    "tan":    (0.71, 0.50, 0.35),
    "dark":   (0.42, 0.28, 0.18),
}
HAIR_COLORS = {
    "black":      (0.10, 0.08, 0.08),
    "brown":      (0.42, 0.26, 0.14),
    "auburn":     (0.58, 0.25, 0.10),
    "red":        (0.78, 0.22, 0.08),
    "blonde":     (0.88, 0.76, 0.44),
    "white":      (0.92, 0.92, 0.92),
}
EYE_COLORS = {
    "grey":  (0.55, 0.60, 0.62),
    "blue":  (0.25, 0.55, 0.85),
    "brown": (0.48, 0.30, 0.12),
    "amber": (0.82, 0.55, 0.10),
}

BG = (32, 34, 38, 255)
SCALE = 10  # px per voxel


def tinted(vox: "gen.Voxels", tint) -> "gen.Voxels":
    out = gen.Voxels()
    for k, c in vox.cells.items():
        out.cells[k] = (c[0] * tint[0], c[1] * tint[1], c[2] * tint[2])
    return out


def mirrored(vox: "gen.Voxels") -> "gen.Voxels":
    out = gen.Voxels()
    vox.mirror_x_into(out)
    return out


def assemble(gender, age, hair, beard, brows, scar, skin, hair_c, eye_c) -> "gen.Voxels":
    """Compose one dwarf in the shared frame, simulating the runtime tints.
    Body and feet are BAKED (doc 17 clothes/boots decision) — no tint."""
    v = gen.Voxels()
    skin_t = SKIN_TONES[skin]
    hair_t = HAIR_COLORS[hair_c]
    eye_t = EYE_COLORS[eye_c]

    v.update(tinted(gen.build_body(), (1, 1, 1)))          # baked clothes
    foot = gen.build_foot()                                 # baked boots
    v.update(foot)
    v.update(mirrored(foot))
    hand = tinted(gen.build_hand(), skin_t)
    v.update(hand)
    v.update(mirrored(hand))
    v.update(tinted(gen.build_head(age), skin_t))
    v.update(tinted(gen.build_eyes(), eye_t))
    if hair and hair != "bald":
        v.update(tinted(gen.build_hair(hair), hair_t))
    if gender == "male" and beard:
        v.update(tinted(gen.build_beard(beard), hair_t))
    if brows:
        v.update(tinted(gen.build_brows(brows), hair_t))
    if scar:
        v.update(gen.build_scar(scar))                     # baked
    return v


def render(vox: "gen.Voxels", view: str) -> Image.Image:
    """Orthographic painter view: 'front' (+Z toward viewer), 'side' (+X toward
    viewer, face pointing right), 'back' (-Z toward viewer)."""
    cells = vox.cells
    if view == "front":
        proj = sorted(((z, x, y, c) for (x, y, z), c in cells.items()))
        pts = [(x, y, c, d) for (d, x, y, c) in proj]
    elif view == "side":
        proj = sorted(((x, z, y, c) for (x, y, z), c in cells.items()))
        pts = [(z, y, c, d) for (d, z, y, c) in proj]
    elif view == "back":
        proj = sorted(((-z, -x, y, c) for (x, y, z), c in cells.items()))
        pts = [(nx, y, c, d) for (d, nx, y, c) in proj]
    else:
        raise ValueError(view)

    us = [p[0] for p in pts]
    vs = [p[1] for p in pts]
    u0, u1 = min(us), max(us)
    v0, v1 = min(vs), max(vs)
    d0 = min(p[3] for p in pts)
    d1 = max(p[3] for p in pts)
    span = max(1, d1 - d0)

    img = Image.new("RGBA", ((u1 - u0 + 1) * SCALE, (v1 - v0 + 1) * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for u, vy, c, d in pts:  # sorted far -> near; near paints last
        f = 0.78 + 0.22 * ((d - d0) / span)  # cheap depth light toward the viewer
        col = (int(min(1.0, c[0] * f) * 255),
               int(min(1.0, c[1] * f) * 255),
               int(min(1.0, c[2] * f) * 255), 255)
        px = (u - u0) * SCALE
        py = (v1 - vy) * SCALE
        draw.rectangle([px, py, px + SCALE - 1, py + SCALE - 1], fill=col)
    return img


ROSTER = [
    # label,            gender,   age,     hair,             beard,          brows,          scar,          skin,    hair_c,  eye_c
    ("adult m",         "male",   "adult", "short_back",     "full_long",    "bushy",        None,          "medium", "brown",  "amber"),
    ("young m",         "male",   "young", "wild_loose",     "goatee",       "thick_flat",   None,          "pale",   "red",    "blue"),
    ("middle m",        "male",   "middle", "braided_back",  "full_braided", "unibrow",      "cheek_slash", "tan",    "black",  "brown"),
    ("elder m",         "male",   "elder", "shaved",         "braided_long", "bushy",        None,          "dark",   "white",  "grey"),
    ("adult f bun",     "female", "adult", "bun",            None,           "thin_arched",  None,          "medium", "blonde", "blue"),
    ("adult f loose",   "female", "adult", "loose_long",     None,           "sharp_angled", None,          "pale",   "auburn", "grey"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = Path(args.out) if args.out else repo / "tmp" / "dwarf_regen_preview" / "qa_sheet.png"

    fronts = []
    for spec in ROSTER:
        label, rest = spec[0], spec[1:]
        fronts.append((label, render(assemble(*rest), "front")))
    extras = [
        ("adult m side", render(assemble(*ROSTER[0][1:]), "side")),
        ("adult m back", render(assemble(*ROSTER[0][1:]), "back")),
        ("adult f side", render(assemble(*ROSTER[4][1:]), "side")),
        ("adult f back", render(assemble(*ROSTER[4][1:]), "back")),
    ]

    pad, label_h = 14, 18
    row1_h = max(im.height for _, im in fronts)
    row2_h = max(im.height for _, im in extras)
    row1_w = sum(im.width for _, im in fronts) + pad * (len(fronts) + 1)
    row2_w = sum(im.width for _, im in extras) + pad * (len(extras) + 1)
    sheet = Image.new("RGBA", (max(row1_w, row2_w),
                               row1_h + row2_h + label_h * 2 + pad * 3), BG)
    draw = ImageDraw.Draw(sheet)

    def paste_row(items, y, row_h):
        x = pad
        for label, im in items:
            sheet.paste(im, (x, y + (row_h - im.height)), im)  # bottom-aligned
            draw.text((x, y + row_h + 2), label, fill=(220, 220, 210, 255))
            x += im.width + pad
    paste_row(fronts, pad, row1_h)
    paste_row(extras, pad + row1_h + label_h + pad, row2_h)

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()

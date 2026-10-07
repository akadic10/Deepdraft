#!/usr/bin/env python3
"""
Generate Deepdraft storage-furniture GLBs — doc 19 Phase 1.

Three placed forms + ONE shared item form (the doc 19 three-form model: the
item form is the carryable drop dwarves fetch and haul; the placed form is
what stands in the world; the GHOST is the placed form rendered translucent
at runtime — no separate ghost asset).

ONE-BOX RULE (Alen, 2026-07-11 — the ore one-shape rule applied to
furniture): EVERY packed furniture item uses the SAME generic box — a plank
crate with rope lashing. At RTS zoom the box says "packed furniture"; the
ghost you placed says which piece it becomes. All resources.json furniture
item defs point at the single packed_furniture.glb.

MATERIAL RULE (Alen, 2026-07-11 — doc 61 §1): furniture is WOODWORK. All three
pieces are wood-bodied with iron accents; stone appears nowhere here.

SHELF REDESIGN (art doc 41, Alen 2026-10-01): the ground shelf now delegates
its open oak/iron frame to generate_shelf_redesign.py. The earlier reservation
for Alen to hand-author it is superseded by this requested replacement.
Its 1x1 footprint, 2-block height and eight visible storage slots are retained.

CONVENTIONS (doc 61 §5.7 / 41b): items-class assets — 8 voxels per block, the
0.125 scale BAKED into exported vertex positions, Godot import Root Scale
stays 1.0. Authored centred on X=Z=0 with the base at Y=0 (the drop/dwarf
convention; the placement controller positions the node at the cell centre).
Multi-block footprints (2×1) are centred the same way — the footprint's own
centre sits at X=0, so a 2-wide piece spans X -8..7 (16 voxels), not 0..15.

DETERMINISM: fixed seed; every run regenerates byte-identical files.

DOC 21 ADDITION (2026-08-03, tavern furniture): tavern_bar (2×1, wood — a
deliberate break from trade_counter's stone, per the furniture-is-woodwork
rule), bench (2×1, wood, no backrest), and hearth (1×1, stone ring + iron
grate + embers — the material-rule exception applied to industrial/utility
anchors, same bucket as trade_counter and workshop bodies). All three use the
same packed_furniture.glb item form (one-box rule still applies).

DOC 30 UPDATE (2026-10-01): the hearth is now a 2x2 stone bowl, with a
1-block rim and 2-block flame tip at the same 8 voxels/block. Its authored
colors are converted to linear COLOR_0 locally; other furniture is unchanged.
The 2026-10-02 fire follow-up exports named body/flame meshes and a separate
ten-frame flame library, shared by installed hearths at runtime.

DOC 31 UPDATE (2026-10-01): tavern_bar and bench use the matching oak/iron
redesign in generate_tavern_redesign, with local linear COLOR_0 conversion.
Both fit their existing 2x1 footprints; bar height is 2, bench height is 1.

DOC 32 ART UPDATE (2026-10-01): the storage barrel uses the tavern oak/iron
palette and linear COLOR_0 export, with a recessed head and two dark hoops.
Its 1x1x1 envelope and eight-item storage definition are unchanged.

DOC 33 ART UPDATE (2026-10-01): storage_crate.glb is the redesigned oak
chest, with a crowned strapped lid, hinges and front clasp. It retains the
1x1x1 envelope and 24-item capacity and uses the same local linear colors.

DOC 34 ART UPDATE (2026-10-01): the double door uses framed oak panels,
strap hinges and ring pulls on both faces, with local linear COLOR_0.
Its 2x1 footprint and 31-cell height are unchanged; hardware spans six cells
in depth. Empty collision regions preserve passage and room sealing.

DOC 36 ART UPDATE (2026-10-01): the shared packed crate uses framed oak,
recessed panels and rope loops with a raised knot. Its original 5x4x5-cell
envelope is unchanged. It now uses the same local linear COLOR_0 export.

DOC 37 ART ADDITION (2026-10-01): the trade counter is a 2x1 stone/iron
industrial anchor, 2 blocks tall. It uses local linear COLOR_0 and the
same packed crate. Its shop/trading fields remain future integration data.

DOC 38 ART ADDITION (2026-10-01): the dining table is a 2x2 oak/iron piece,
1.5 blocks tall, using the tavern palette and local linear COLOR_0.

DOC 39 ART ADDITION (2026-10-01): the standalone wooden chair has a 1x1
footprint, 2-block backrest and 1-block seat rim, in matching oak/iron.

DOC 50 DINING REVISION (2026-10-05): personal table 2x2x1.75, communal
table 8x4x1.75 with eight optional chair positions, chair 2x2x1.375 with a
.875 seat. Supersedes docs 38/39 geometry; old saved chairs retain a legacy GLB.

DOC 40 ART ADDITION (2026-10-01): the 4x2 dwarven bed has a 1-block mattress,
2-block headboard and raised linen pillow/folded blanket, in the same scale.

DOC 42 ART ADDITION (2026-10-02): the 2x2 brewing vat has an open oak rim,
recessed liquid, iron hoops and copper tap, within a 2-block height.

DOC 43 ART ADDITION (2026-10-02): wall_torch has separate body/flame meshes,
1.5-block height and a wall-facing rear plane at Z=0. Its emitter is a
runtime child, not part of the GLB. Thirteen placed forms + one packed item.

DOC 22 ADDITION (2026-08-03, doors — the sealed-room/temperature prerequisite):
door (originally 1×1, thin plank plane, EMPTY collision_regions in door.json —
must stay walkable). Also uses packed_furniture.glb for its item form. RESIZED
2026-08-06 (doc 22b) to 2×1, ~4 blocks tall, as a double-leaf plank door — the
original single tile read too small next to 3-tall dwarves.

Outputs (paths must match data/furniture/*.json "model" and
data/entities/items/resources.json "model" fields):
  assets/models/furniture/{barrel,storage_crate,storage_shelf}.glb   (placed, doc 19)
  assets/models/furniture/{tavern_bar,bench,hearth}.glb              (placed, doc 21)
  assets/models/furniture/door.glb                                   (placed, doc 22)
  assets/models/furniture/trade_counter.glb                           (placed, art doc 37)
  assets/models/furniture/wooden_table.glb                            (placed, art doc 38)
  assets/models/furniture/wooden_chair.glb                            (placed, art doc 39)
  assets/models/furniture/dwarf_bunk.glb                              (placed, art doc 40)
  assets/models/furniture/brewing_vat.glb                             (placed, art doc 42)
  assets/models/furniture/aging_rack.glb                              (placed, art doc 46)
  assets/models/furniture/brazier.glb                                 (placed, art doc 47)
  assets/models/items/furniture/packed_furniture.glb                 (shared item)
Review sheet: tmp/furniture_review/furniture_sheet.png
"""

import math
import random
from pathlib import Path

from generate_dwarf_glb import Voxels, mesh_from_voxels, write_glb
import generate_hearth_redesign as hearth_art
import generate_tavern_redesign as tavern_art
import generate_barrel_redesign as barrel_art
import generate_chest_redesign as chest_art
import generate_door_redesign as door_art
import generate_packed_furniture_redesign as packed_art
import generate_trade_counter as trade_art
import generate_dining_table as table_art
import generate_chair as chair_art
import generate_seating_study as dining_art
import generate_bed as bed_art
import generate_shelf_redesign as shelf_art
import generate_brewing_vat as vat_art
import generate_anvil as anvil_art
import generate_smelter as smelter_art
import generate_aging_rack as aging_art
import generate_brazier as brazier_art

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

# Doc 21 additions — stone + ember tones for the hearth (the material-rule
# exception; everything else in this file stays wood per the 2026-07-11 rule).
STONE_HI    = _c(0xC4BEB4)
STONE_MID   = _c(0x9B9088)
STONE_DARK  = _c(0x6B6260)
EMBER_GLOW  = _c(0x882200)
FLAME_CORE  = _c(0xFFDD44)


def _wood_jitter(rng, base):
    """Mild per-voxel value variation so wood never flat-fills (doc 61 §7)."""
    return _scale_c(base, rng.uniform(0.93, 1.07))


# ── Barrel — placed form, 1×1×1 block (8×8×8) ────────────────────────────────
# Doc 61 §5.4: classic fat barrel, oak staves, iron bands, bung hole on top.

BARREL_RADII = [2.9, 3.4, 3.8, 4.0, 4.0, 3.8, 3.4, 2.9]   # bulge profile
BARREL_BANDS = (1, 6)                                       # iron band rows


def build_legacy_barrel(height=8, radii=None, bands=None, bung=True):
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

def build_legacy_storage_chest(size=8, mini=False):
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
# GROUND shelf (Alen, 2026-07-11): open and symmetric from all four sides —
# no back panel. Heavy wood uprights, two plank levels, iron brackets, anchor
# surfaces clear of the uprights. Legacy model retained for reference (replaced in art doc 41).

SHELF_H = 16
SHELF_LEVEL_Y = (0, 7)      # slab rows; items sit on top of each (y=1 and y=8)


def build_legacy_storage_shelf():
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
    # Iron brackets under the mid shelf and top cap, against the posts —
    # on both Z faces (symmetric, no front/back distinction).
    for cx in (-half, half - 1):
        for y in (SHELF_LEVEL_Y[1] - 1, SHELF_H - 2):
            v.cells[(cx, y, -half + 1)] = IRON_DULL
            v.cells[(cx, y, half - 2)] = IRON_DULL
    return v


# ── Tavern Bar — placed form, 2×1 blocks (16×12×8 voxel envelope) ────────────
# Doc 61 §5.4 / doc 21: oak-panelled counter body, overhanging plank
# countertop, iron rail + tap fittings. WOOD, not stone — deliberately
# distinct from the stone Trade Counter (material rule, 2026-07-11: the bar
# is furniture dwarves use, not an industrial anchor).

def build_legacy_tavern_bar():
    rng = random.Random(SEED + 4)
    v = Voxels()
    x0, x1 = -8, 8      # 16 voxels wide (2 blocks), footprint centred on X=0
    z0, z1 = -4, 4       # 8 voxels deep (1 block)
    body_h = 12           # counter body height; leaves headroom for the slab
    # Body: plank panel, horizontal seam every 3 rows (chest convention).
    for x in range(x0, x1):
        for z in range(z0, z1):
            for y in range(0, body_h):
                seam = (y % 3 == 2)
                v.cells[(x, y, z)] = _wood_jitter(rng, PLANK_DARK if seam else PLANK)
    # Squat oak leg posts at both ends, full depth.
    for x in list(range(x0, x0 + 2)) + list(range(x1 - 2, x1)):
        for z in range(z0, z1):
            for y in range(0, 2):
                v.cells[(x, y, z)] = _wood_jitter(rng, OAK_DARK)
    # Iron rail along the front top edge of the body.
    for x in range(x0, x1):
        v.cells[(x, body_h - 1, z0)] = IRON_DULL
    # Countertop slab, overhangs the body by 1 voxel on every side.
    for x in range(x0 - 1, x1 + 1):
        for z in range(z0 - 1, z1 + 1):
            for y in (body_h, body_h + 1):
                edge = x in (x0 - 1, x1) or z in (z0 - 1, z1)
                v.cells[(x, y, z)] = _wood_jitter(rng, OAK_MID if edge else OAK_LIGHT)
    # Tap fittings: two iron knobs on the countertop.
    for tx in (x0 + 4, x1 - 5):
        v.cells[(tx, body_h + 2, 0)] = IRON_HI
    return v


# ── Bench — placed form, 2×1 blocks (16×8×8 voxel envelope) ──────────────────
# Doc 61 §5.4 / doc 21: long dwarven bench, thick-legged, no backrest (the
# feature that distinguishes it from wooden_chair).

def build_legacy_bench():
    rng = random.Random(SEED + 5)
    v = Voxels()
    x0, x1 = -8, 8
    z0, z1 = -4, 4
    leg_h = 5
    # Four 2×2 leg posts, one at each corner.
    for lx in (x0, x0 + 1, x1 - 2, x1 - 1):
        for lz in (z0, z0 + 1, z1 - 2, z1 - 1):
            for y in range(0, leg_h):
                v.cells[(lx, y, lz)] = _wood_jitter(rng, OAK_MID)
    # Seat slab, two plank rows thick, dark seam down the centre length.
    for x in range(x0, x1):
        for z in range(z0, z1):
            for y in (leg_h, leg_h + 1):
                seam = (z == 0)
                v.cells[(x, y, z)] = _wood_jitter(rng, PLANK_DARK if seam else PLANK)
    return v


# ── Hearth — placed form, 1×1 block (8×8×8 voxel envelope) ───────────────────
# Doc 61 §5.4 / doc 21: stone fire-ring, iron grate, glowing embers. STONE is
# a deliberate material-rule exception (industrial/utility anchor, same
# bucket as the Trade Counter and workshop bodies — open fire belongs on
# stone). heat_source.heat_units in hearth.json is data-only until doc 34
# lands; this model carries no light-emitting node (mesh only, same
# convention as the wall torch — the scene builder adds the light).

HEARTH_OUTER_R = 3.6
HEARTH_INNER_R = 2.0


def build_legacy_hearth():
    v = Voxels()
    half = 4
    for x in range(-half, half):
        for z in range(-half, half):
            d = math.hypot(x + 0.5, z + 0.5)
            if d > HEARTH_OUTER_R:
                continue
            if d > HEARTH_INNER_R:
                v.cells[(x, 0, z)] = STONE_MID
                v.cells[(x, 1, z)] = STONE_HI
            else:
                v.cells[(x, 0, z)] = EMBER_GLOW if (x + z) % 2 == 0 else FLAME_CORE
    # Iron grate bars crossing over the embers.
    for x in range(-1, 2):
        v.cells[(x, 1, 0)] = IRON_DULL
    for z in range(-1, 2):
        v.cells[(0, 1, z)] = IRON_DULL
    return v


def build_barrel():
    return barrel_art.barrel()


def build_storage_chest():
    return chest_art.chest()


def build_tavern_bar():
    return tavern_art.tavern_bar()


def build_bench():
    return tavern_art.bench()


def build_hearth():
    return hearth_art.hearth()


def build_door():
    return door_art.door()


def build_packed_box():
    return packed_art.packed_box()


def build_trade_counter():
    return trade_art.trade_counter()


def build_wooden_table():
    return table_art.wooden_table()


def build_communal_table():
    return dining_art.table(8, 4)


def build_wooden_chair():
    return chair_art.wooden_chair()


def build_dwarf_bunk():
    return bed_art.dwarf_bunk()


def build_storage_shelf():
    return shelf_art.shelf()


def build_brewing_vat():
    return vat_art.brewing_vat()


def build_anvil():
    return anvil_art.anvil()


def build_smelter():
    return smelter_art.smelter()


def build_aging_rack():
    return aging_art.aging_rack()


def build_brazier():
    return brazier_art.brazier()


def mesh_furniture(name,vox):
    if name in ('barrel','storage_crate','storage_shelf','tavern_bar','bench','door','packed_furniture','trade_counter','wooden_table','communal_table','wooden_chair','dwarf_bunk','brewing_vat','anvil','aging_rack'):
        return tavern_art.export_mesh(vox)
    return hearth_art.export_mesh(vox) if name == 'hearth' else mesh_from_voxels(vox)


# ── Legacy door — placed form, 2×1 block (16×31×2 voxel envelope) ───────
# Doc 61 §5.4 / doc 22 / doc 22b (RESIZED 2026-08-06, Alen playtest feedback):
# a double-leaf plank door, 2 blocks wide x ~4 blocks tall, centred in the cell
# depth. COLLISION_REGIONS IS EMPTY in door.json — this piece must stay
# walkable, so the model is deliberately thin (2 voxels) rather than filling
# the block. Two leaves split by a dark centre seam column, hinges on each
# leaf's outer edge, handles near the centre seam — reads as a proper double
# door at 2-wide instead of one slab stretched to fit.

DOOR_W = 16   # 2 blocks wide (8 voxels/block); spans X -8..7
DOOR_H = 31   # just under 4 blocks — leaves a frame gap at the top
DOOR_SEAM = _c(0x3A2810)   # dark gap colour between the two leaves


def build_legacy_door():
    rng = random.Random(SEED + 7)
    v = Voxels()
    x0, x1 = -DOOR_W // 2, DOOR_W // 2   # -8..7
    for x in range(x0, x1):
        if x in (-1, 0):
            # Centre seam: the visible gap between the two door leaves.
            for y in range(0, DOOR_H):
                for z in (-1, 0):
                    v.cells[(x, y, z)] = DOOR_SEAM
            continue
        for y in range(0, DOOR_H):
            seam = (y % 4 == 3)
            for z in (-1, 0):
                v.cells[(x, y, z)] = _wood_jitter(rng, PLANK_DARK if seam else PLANK)
    # Iron hinges down each leaf's outer edge (3 per leaf, evenly spread).
    for y in (3, 15, 27):
        v.cells[(x0, y, -1)] = IRON_DULL
        v.cells[(x1 - 1, y, -1)] = IRON_DULL
    # Handles near the centre seam, one per leaf, standing-height.
    v.cells[(-2, 12, -1)] = IRON_HI
    v.cells[(1, 12, -1)] = IRON_HI
    return v


# ── Item form — ONE shared packed box (Alen, 2026-07-11) ─────────────────────

ROPE = _c(0xA09060)   # doc 61 rope_natural


def build_legacy_packed_box():
    """The generic packed-furniture crate: a stout plank box with rope
    lashing crossing the top and sides — reads as "boxed goods in transit",
    distinct from the iron-bracketed storage chest. ~5×4×5 voxels (well
    inside a half-block), used by EVERY furniture item def."""
    rng = random.Random(SEED + 3)
    v = Voxels()
    half = 2   # x/z in -2..2 (5 wide)
    for x in range(-half, half + 1):
        for z in range(-half, half + 1):
            for y in range(0, 4):
                seam = (y == 2)
                v.cells[(x, y, z)] = _wood_jitter(rng, PLANK_DARK if seam else PLANK)
    # Rope lashing: two crossing straps over the top and down the sides.
    for x in range(-half, half + 1):
        v.cells[(x, 3, 0)] = ROPE
        v.cells[(x, 0, 0)] = _scale_c(ROPE, 0.85)
    for z in range(-half, half + 1):
        v.cells[(0, 3, z)] = ROPE
        v.cells[(0, 0, z)] = _scale_c(ROPE, 0.85)
    for y in range(0, 4):                      # straps down all four faces
        v.cells[(-half, y, 0)] = ROPE
        v.cells[(half, y, 0)] = ROPE
        v.cells[(0, y, -half)] = ROPE
        v.cells[(0, y, half)] = ROPE
    # Knot on top where the straps cross.
    v.cells[(0, 3, 0)] = _scale_c(ROPE, 1.12)
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
        ("tavern_bar", build_tavern_bar()),
        ("bench", build_bench()),
        ("hearth", build_hearth()),
        ("door", build_door()),
        ("trade_counter", build_trade_counter()),
        ("wooden_table", build_wooden_table()),
        ("communal_table", build_communal_table()),
        ("wooden_chair", build_wooden_chair()),
        ("dwarf_bunk", build_dwarf_bunk()),
        ("brewing_vat", build_brewing_vat()),
        ("anvil", build_anvil()),
        ("smelter", build_smelter()),
        ("aging_rack", build_aging_rack()),
        ("brazier", build_brazier()),
    ]
    box = build_packed_box()

    total = 0
    for name, vox in placed:
        if name == 'hearth':
            from generate_hearth_redesign import write_hearth, write_flames as write_hearth_flames
            path = placed_dir / 'hearth.glb'
            write_hearth(path,root / 'tmp' / 'furniture_review')
            size = path.stat().st_size
            flame_path = placed_dir / 'animations' / 'hearth_flame.glb'
            write_hearth_flames(flame_path,root / 'tmp' / 'furniture_review')
            total += flame_path.stat().st_size
            print('  furniture/animations/hearth_flame.glb  10 animation frames')
        elif name == 'brazier':
            path = placed_dir / 'brazier.glb'
            brazier_art.write_brazier(path,root / 'tmp' / 'furniture_review')
            size = path.stat().st_size
            flame_path = placed_dir / 'animations' / 'brazier_flame.glb'
            brazier_art.write_flames(flame_path,root / 'tmp' / 'furniture_review')
            total += flame_path.stat().st_size
            print('  furniture/animations/brazier_flame.glb  8 animation frames')
        elif name == 'smelter':
            path = placed_dir / 'smelter.glb'
            smelter_art.write_smelter(path,root / 'tmp' / 'furniture_review')
            size = path.stat().st_size
            flame_path = placed_dir / 'animations' / 'smelter_flame.glb'
            smelter_art.write_flames(flame_path,root / 'tmp' / 'furniture_review')
            total += flame_path.stat().st_size
            print('  furniture/animations/smelter_flame.glb  8 animation frames')
        else:
            size = write_glb(placed_dir / f"{name}.glb", name, mesh_furniture(name,vox), EXPORT_SCALE)
        print(f"  furniture/{name + '.glb':22s} {len(vox):4d} voxels  {size:6d} B")
        total += size
    size = write_glb(item_dir / "packed_furniture.glb", "packed_furniture",
                     mesh_furniture('packed_furniture',box), EXPORT_SCALE)
    print(f"  items/furniture/packed_furniture.glb {len(box):4d} voxels  {size:6d} B")
    total += size

    # This placed piece needs named body/flame meshes for selective emission.
    from generate_wall_torch import torch, write_parts, write_flames
    torch_body, torch_flame = torch()
    torch_path = placed_dir / "wall_torch.glb"
    write_parts(torch_path, [("torch_body", torch_body), ("torch_flame", torch_flame)],
                root / "tmp" / "furniture_review")
    size = torch_path.stat().st_size
    total += size
    torch_body.update(torch_flame)
    placed.append(("wall_torch", torch_body))
    print(f"  furniture/wall_torch.glb     {len(torch_body):4d} voxels  {size:6d} B")
    flame_path = placed_dir / "animations" / "wall_torch_flame.glb"
    write_flames(flame_path, root / "tmp" / "furniture_review")
    total += flame_path.stat().st_size
    print(f"  furniture/animations/wall_torch_flame.glb  8 animation frames")

    sheet = _sheet(
        [(f"{n} (placed)", v) for n, v in placed] + [("packed box (item)", box)],
        root / "tmp" / "furniture_review" / "furniture_sheet.png")
    print(f"furniture set complete ({total / 1024:.1f} KB); review sheet -> {sheet}")


if __name__ == "__main__":
    main()

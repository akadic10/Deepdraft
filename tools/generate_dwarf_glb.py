#!/usr/bin/env python3
"""
generate_dwarf_glb.py  —  Deepdraft modular dwarf asset generator
==================================================================

Produces the ~41 modular dwarf body-part GLBs specified in
docs/40_economy_colony/41b_dwarf_appearance_glb.md.

WHY THIS EXISTS
---------------
Dwarves are assembled at runtime from interchangeable mesh parts (head /
eyes / hair / beard / brows / scar / body / hand / foot). Rather than author
each part by hand in MagicaVoxel, this script builds every part procedurally
from a voxel description and exports a GLB in the exact format the rest of the
project uses (see any tree under assets/models/flora/):

    * single mesh, single primitive, triangle mode
    * attributes POSITION (VEC3 f32), NORMAL (VEC3 f32), COLOR_0 (VEC4 f32)
    * one material named "vertex_color_unlit"
    * authored in MagicaVoxel voxel units, exported in Godot units
      (8 voxels = 1 game block, so positions are multiplied by 0.125)
    * flat normals, indexed triangles

SHARED COORDINATE FRAME (the important bit)
-------------------------------------------
41b's runtime hierarchy attaches every part at its parent's local origin with
NO per-part offset:

    DwarfAgent
      MeshHead   (head_[age].glb)        <- identity transform
        MeshEyes / MeshHair / MeshBeard / MeshBrows / MeshScar  <- identity
      MeshBody   (body_base.glb)         <- identity transform
      MeshHandL / MeshHandR / MeshFootL / MeshFootR             <- identity

Because nothing is repositioned, every GLB must be authored in ONE absolute
frame describing the whole dwarf. We model the entire dwarf once in voxel
coordinates, then emit each part as its own GLB in Godot world units while
keeping the shared coordinates. Dropping each mesh in at (0,0,0) reassembles a
coherent dwarf automatically.

Frame convention:
    X : left(-) / right(+), centred on 0
    Y : up, 0 at the soles of the feet
    Z : back(-) / front(+), centred on 0   (face looks toward +Z)
Visual height target ~26 voxels = 3.3 game blocks (41b / doc 61).

COLOUR / TINT STRATEGY (doc 17 rework, 2026-07-02)
--------------------------------------------------
Tinted-at-runtime parts (head, hands, eyes, hair, beard, brows) are authored in
a near-white GRAYSCALE value gradient (top faces lighter, recesses darker): the
runtime multiply preserves the shading while the tint supplies the hue.

BAKED parts carry literal colours and must NOT be tinted at runtime:
  * scars (as before)
  * body_base — now a CLOTHED torso (doc 17 §1 decision: clothes baked, overlay
    parts later): tunic, dark belt band, trouser pelvis, tunic collar. No skin
    shows on the body, so the skin tint no longer applies to it.
  * foot — now a leather BOOT with a dark sole band (boots-by-default).
DwarfAgent._apply_tints must tint body/feet with WHITE (keep the standard
material, leave baked colours alone) once these assets land.

Run:  python3 tools/generate_dwarf_glb.py            (writes assets/dwarves/)
      python3 tools/generate_dwarf_glb.py --out DIR  (custom output root)
"""

import argparse
import json
import os
import struct
from pathlib import Path

EXPORT_SCALE = 0.125  # 8 authored voxels = 1 Godot/world unit

# ---------------------------------------------------------------------------
# Voxel container
# ---------------------------------------------------------------------------

class Voxels:
    """A set of unit voxels keyed by integer (x,y,z) -> (r,g,b) in 0..1."""

    def __init__(self):
        self.cells = {}

    def set(self, x, y, z, color):
        self.cells[(int(round(x)), int(round(y)), int(round(z)))] = color

    def box(self, x0, x1, y0, y1, z0, z1, color, shade=True):
        """Fill an inclusive-exclusive voxel box [x0,x1) x [y0,y1) x [z0,z1).

        If shade is True a mild top-lighter / bottom-darker value gradient is
        applied so flat-tinted parts still read as 3D voxel forms.
        """
        x0, x1 = sorted((int(x0), int(x1)))
        y0, y1 = sorted((int(y0), int(y1)))
        z0, z1 = sorted((int(z0), int(z1)))
        span = max(1, y1 - y0 - 1)
        for x in range(x0, x1):
            for y in range(y0, y1):
                for z in range(z0, z1):
                    c = color
                    if shade:
                        # +/-12% value across the height of this box
                        f = 0.88 + 0.24 * ((y - y0) / span)
                        c = (min(1.0, color[0] * f),
                             min(1.0, color[1] * f),
                             min(1.0, color[2] * f))
                    self.cells[(x, y, z)] = c

    def mirror_x_into(self, other):
        """Copy this set mirrored across X=0 into `other` (for symmetric pairs)."""
        for (x, y, z), c in self.cells.items():
            other.cells[(-x - 1, y, z)] = c

    def update(self, other):
        self.cells.update(other.cells)

    def __len__(self):
        return len(self.cells)


# ---------------------------------------------------------------------------
# Greedy-free cube mesher (per-voxel exposed faces only)
# ---------------------------------------------------------------------------

# face -> (normal, 4 corner offsets CCW when viewed from outside)
_FACES = {
    (+1, 0, 0): ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    (-1, 0, 0): ((-1, 0, 0), [(0, 0, 1), (0, 1, 1), (0, 1, 0), (0, 0, 0)]),
    (0, +1, 0): ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    (0, -1, 0): ((0, -1, 0), [(0, 0, 1), (0, 0, 0), (1, 0, 0), (1, 0, 1)]),
    (0, 0, +1): ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    (0, 0, -1): ((0, 0, -1), [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)]),
}


def mesh_from_voxels(vox: Voxels):
    """Return (positions, normals, colors, indices) for the exposed surface."""
    cells = vox.cells
    positions, normals, colors, indices = [], [], [], []
    nextv = 0
    for (x, y, z), color in cells.items():
        for (dx, dy, dz), (normal, corners) in _FACES.items():
            if (x + dx, y + dy, z + dz) in cells:
                continue  # interior face, skip
            base = nextv
            for cx, cy, cz in corners:
                positions.append((x + cx, y + cy, z + cz))
                normals.append(normal)
                colors.append((color[0], color[1], color[2], 1.0))
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
            nextv += 4
    return positions, normals, colors, indices


# ---------------------------------------------------------------------------
# GLB writer (matches the project's existing flora GLBs)
# ---------------------------------------------------------------------------

def _pad4(b: bytes, fill=b"\x00") -> bytes:
    while len(b) % 4:
        b += fill
    return b


def write_glb(path: Path, name: str, mesh, export_scale: float = 1.0):
    positions, normals, colors, indices = mesh
    if not positions:
        raise ValueError(f"{name}: empty mesh")

    scaled_positions = [
        (p[0] * export_scale, p[1] * export_scale, p[2] * export_scale)
        for p in positions
    ]

    pos_b = b"".join(struct.pack("<3f", *p) for p in scaled_positions)
    nrm_b = b"".join(struct.pack("<3f", *n) for n in normals)
    col_b = b"".join(struct.pack("<4f", *c) for c in colors)
    idx_b = b"".join(struct.pack("<I", i) for i in indices)

    blob = b""
    views = []

    def add_view(data, target=None):
        nonlocal blob
        offset = len(blob)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        blob += _pad4(data)
        return len(views) - 1

    v_pos = add_view(pos_b, 34962)
    v_nrm = add_view(nrm_b, 34962)
    v_col = add_view(col_b, 34962)
    v_idx = add_view(idx_b, 34963)

    mins = [min(p[i] for p in scaled_positions) for i in range(3)]
    maxs = [max(p[i] for p in scaled_positions) for i in range(3)]

    gltf = {
        "asset": {"version": "2.0", "generator": "Deepdraft dwarf part generator"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{
            "name": name,
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
                "indices": 3,
                "material": 0,
                "mode": 4,
            }],
        }],
        "materials": [{
            "name": "vertex_color_unlit",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0,
                "roughnessFactor": 1,
            },
        }],
        "accessors": [
            {"bufferView": v_pos, "componentType": 5126, "count": len(positions),
             "type": "VEC3", "min": [float(m) for m in mins], "max": [float(m) for m in maxs]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": v_col, "componentType": 5126, "count": len(colors), "type": "VEC4"},
            {"bufferView": v_idx, "componentType": 5125, "count": len(indices), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }

    json_b = _pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    bin_b = _pad4(blob)
    total = 12 + 8 + len(json_b) + 8 + len(bin_b)

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_b), 0x4E4F534A))   # 'JSON'
        f.write(json_b)
        f.write(struct.pack("<II", len(bin_b), 0x004E4942))    # 'BIN\0'
        f.write(bin_b)
    return total


# ---------------------------------------------------------------------------
# Neutral authoring values
#   Tinted parts: near-white grayscale (hue comes from the runtime tint).
#   Baked parts : literal colour.
# ---------------------------------------------------------------------------

SKIN_NEUTRAL = (0.97, 0.93, 0.90)   # head/hands (tinted by skin_tone)
SKIN_GROOVE  = (0.74, 0.70, 0.67)   # finger grooves — colour break survives tint
HAIR_NEUTRAL = (0.95, 0.95, 0.95)   # hair / beard / brows (tinted by hair_color)
EYE_WHITE    = (1.00, 1.00, 1.00)   # iris (tinted by eye_color)
EYE_PUPIL    = (0.18, 0.18, 0.18)   # stays dark after tint multiply
SCAR_BAKED   = (0.74, 0.46, 0.40)   # scar overlay (not tinted at runtime)

# Baked clothing colours (doc 17 §1; muted, doc 61 palette family).
CLOTH_TUNIC  = (0.55, 0.46, 0.32)   # undyed wool tunic
TROUSER      = (0.30, 0.26, 0.22)   # grey-brown trousers
BELT_DARK    = (0.23, 0.15, 0.09)   # dark leather belt band
BUCKLE_IRON  = (0.62, 0.61, 0.60)   # iron_dull buckle voxels
BOOT_LEATHER = (0.42, 0.24, 0.11)   # leather_brown boots
BOOT_SOLE    = (0.16, 0.13, 0.11)   # dark sole band

# ---------------------------------------------------------------------------
# Anatomy layout constants (shared voxel frame — doc 17 hearthling ratios)
#
# Stack (voxels):  boots 0..4 | air gap 4..6 | trousers 6..9 | belt 9..10 |
#                  tunic 10..15 | collar 15..16 | head 16..27 (crown-stepped)
# Head is 14 wide vs the 8-wide chest (~1.75x, hearthling head dominance);
# the 10-wide trouser pelvis sits WIDER than the chest (squat dwarf stance).
# Total ~27 voxels = ~3.4 blocks visual; logical height stays 3 (doc 41).
# ---------------------------------------------------------------------------

HEAD_Y0, HEAD_Y1 = 16, 27      # head vertical span (incl. the stepped crown)
HEAD_X0, HEAD_X1 = -7, 7       # 14 wide — the dominant silhouette element
HEAD_Z0, HEAD_Z1 = -4, 5       # face plane at z = HEAD_Z1 (front, +Z)
FACE_Z = HEAD_Z1               # 5 — protrusion layer (nose, brow ridge)
EYE_Y = 21                     # eye row
CROWN_Y = HEAD_Y1 - 2          # main head mass ends here; 2 stepped crown rows above


# ---------------------------- BODY GROUP -----------------------------------

def _chamfer_side_and_bottom_edges(v, x0, x1, y0, y1, z0, z1):
    """1-voxel chamfer (hearthling read) on the 4 vertical and 4 bottom edges
    of a box. Top edges are left alone — the stepped crown rounds those."""
    for y in range(y0, y1):
        for (x, z) in ((x0, z0), (x0, z1 - 1), (x1 - 1, z0), (x1 - 1, z1 - 1)):
            v.cells.pop((x, y, z), None)
    for x in range(x0, x1):
        for z in (z0, z1 - 1):
            v.cells.pop((x, y0, z), None)
    for z in range(z0, z1):
        for x in (x0, x1 - 1):
            v.cells.pop((x, y0, z), None)


def build_head(age):
    """Hearthling-ratio head (doc 17 §0/§1): dominant 14-wide mass, 1-voxel
    edge chamfers, a double-stepped crown, and a protruding 2x2x1 nose.
    Age tiers differ by jowl/brow/chin voxels on the shared base."""
    v = Voxels()
    # main mass (crown rows added separately)
    v.box(HEAD_X0, HEAD_X1, HEAD_Y0, CROWN_Y, HEAD_Z0, HEAD_Z1, SKIN_NEUTRAL)
    _chamfer_side_and_bottom_edges(v, HEAD_X0, HEAD_X1, HEAD_Y0, CROWN_Y, HEAD_Z0, HEAD_Z1)
    # double-stepped crown (each row inset 1 more — the rounded dome read)
    v.box(HEAD_X0 + 1, HEAD_X1 - 1, CROWN_Y, CROWN_Y + 1, HEAD_Z0 + 1, HEAD_Z1 - 1, SKIN_NEUTRAL)
    v.box(HEAD_X0 + 2, HEAD_X1 - 2, CROWN_Y + 1, HEAD_Y1, HEAD_Z0 + 2, HEAD_Z1 - 2, SKIN_NEUTRAL)
    # brow ridge (proud forehead) on the protrusion layer
    v.box(-5, 5, EYE_Y + 1, EYE_Y + 2, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    # protruding nose block, 2 wide x 2 tall x 1 deep (doc 17 §1)
    v.box(-1, 1, EYE_Y - 2, EYE_Y, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    # ears
    v.box(HEAD_X0 - 1, HEAD_X0, EYE_Y - 1, EYE_Y + 1, -1, 1, SKIN_NEUTRAL)
    v.box(HEAD_X1, HEAD_X1 + 1, EYE_Y - 1, EYE_Y + 1, -1, 1, SKIN_NEUTRAL)
    if age in ("middle", "elder"):
        # cheek jowls widen the lower face
        v.box(HEAD_X0 - 1, HEAD_X0, HEAD_Y0 + 1, EYE_Y - 1, 0, 3, SKIN_NEUTRAL)
        v.box(HEAD_X1, HEAD_X1 + 1, HEAD_Y0 + 1, EYE_Y - 1, 0, 3, SKIN_NEUTRAL)
    if age == "elder":
        # heavier brow shelf above the ridge
        v.box(-5, 5, EYE_Y + 2, EYE_Y + 3, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    if age == "young":
        # rounder, slightly narrower chin (deepen the bottom chamfer)
        for z in range(HEAD_Z0 + 1, HEAD_Z1 - 1):
            v.cells.pop((HEAD_X0 + 1, HEAD_Y0, z), None)
            v.cells.pop((HEAD_X1 - 2, HEAD_Y0, z), None)
    return v


def build_eyes():
    v = Voxels()
    for sx in (-4, 2):            # left / right eyes, 2 voxels wide each
        v.box(sx, sx + 2, EYE_Y, EYE_Y + 1, FACE_Z, FACE_Z + 1, EYE_WHITE, shade=False)
        # a darker pupil voxel pushed one cell in front (inner side of each eye)
        v.set(sx + 1 if sx < 0 else sx, EYE_Y, FACE_Z + 1, EYE_PUPIL)
    return v


def build_body():
    """CLOTHED compact torso (doc 17 §1, hearthling model, colours BAKED):
    trouser pelvis WIDER than the tunic chest (squat stance), dark belt band
    with iron buckle, shoulder notches, tunic collar as the short neck.
    Still no arms, legs, or connector geometry — ever (doc 41 contract)."""
    v = Voxels()
    # trousers / pelvis — 10 wide vs the 8-wide chest
    v.box(-5, 5, 6, 9, -3, 3, TROUSER)
    # dark belt band (crisp, unshaded) + protruding iron buckle voxels
    v.box(-5, 5, 9, 10, -3, 3, BELT_DARK, shade=False)
    v.set(-1, 9, 3, BUCKLE_IRON)
    v.set(0, 9, 3, BUCKLE_IRON)
    # tunic torso
    v.box(-4, 4, 10, 15, -3, 3, CLOTH_TUNIC)
    # shoulder notches — 1-voxel steps at the top outer corners
    for z in range(-3, 3):
        v.cells.pop((-4, 14, z), None)
        v.cells.pop((3, 14, z), None)
    # tunic collar = the short neck (clothed; skin never shows on the body)
    v.box(-2, 2, 15, 16, -1, 2, CLOTH_TUNIC)
    return v


def build_hand():
    """Right floating mitten hand (x>0), skin-tinted; left mirrored at runtime.
    Hearthling-derived (doc 17 §0 adoption rule): palm slab + thumb mass on the
    body side, finger grooves as notches/colour breaks — NO joints."""
    v = Voxels()
    # palm slab, detached from the torso by a visible air gap
    v.box(7, 10, 7, 11, -2, 2, SKIN_NEUTRAL)
    # thumb mass on the inner (body) side, toward the front
    v.box(6, 7, 8, 10, 0, 2, SKIN_NEUTRAL)
    # finger grooves on the outer-bottom edge: two notches -> three fingertips
    v.cells.pop((9, 7, -1), None)
    v.cells.pop((9, 7, 1), None)
    # colour-break groove lines above the notches (darker value survives tint)
    v.cells[(9, 8, -1)] = SKIN_GROOVE
    v.cells[(9, 8, 1)] = SKIN_GROOVE
    return v


def build_foot():
    """Right floating BOOT (x>0), colours BAKED; left mirrored at runtime.
    Hearthling silhouette (doc 17 §0): stepped heel, forward toe step, darker
    sole band, short ankle cuff. No ankle/leg connector geometry."""
    v = Voxels()
    # boot body
    v.box(2, 6, 1, 3, -2, 4, BOOT_LEATHER)
    # stepped heel (lower, pokes backward)
    v.box(2, 6, 1, 2, -3, -2, BOOT_LEATHER)
    # forward toe step (lower, pokes forward)
    v.box(2, 6, 1, 2, 4, 6, BOOT_LEATHER)
    # short ankle cuff
    v.box(3, 5, 3, 4, -1, 2, BOOT_LEATHER)
    # dark sole band under everything (crisp)
    v.box(2, 6, 0, 1, -3, 6, BOOT_SOLE, shade=False)
    return v


# ---------------------------- HAIR GROUP -----------------------------------

def _ring(v, y, x0, x1, z0, z1, ix0, ix1, iz0, iz1, color):
    """One voxel row filling the outer rect minus the inner rect (crown drape)."""
    for x in range(x0, x1):
        for z in range(z0, z1):
            if ix0 <= x < ix1 and iz0 <= z < iz1:
                continue
            v.cells[(x, y, z)] = color


def _scalp(v, top_extra=0):
    """Cap draped over the double-stepped crown: a top slab over the inner
    step plus rings hugging each step edge, so hair follows the dome."""
    v.box(HEAD_X0 + 2, HEAD_X1 - 2, HEAD_Y1, HEAD_Y1 + 1 + top_extra,
          HEAD_Z0 + 2, HEAD_Z1 - 2, HAIR_NEUTRAL)
    _ring(v, HEAD_Y1 - 1, HEAD_X0 + 1, HEAD_X1 - 1, HEAD_Z0 + 1, HEAD_Z1 - 1,
          HEAD_X0 + 2, HEAD_X1 - 2, HEAD_Z0 + 2, HEAD_Z1 - 2, HAIR_NEUTRAL)
    _ring(v, HEAD_Y1 - 2, HEAD_X0, HEAD_X1, HEAD_Z0, HEAD_Z1,
          HEAD_X0 + 1, HEAD_X1 - 1, HEAD_Z0 + 1, HEAD_Z1 - 1, HAIR_NEUTRAL)


_HAIR_FORBIDDEN = None


def _hair_forbidden_cells():
    """Cells hair may never occupy: any head tier's own geometry (mass, crown,
    nose, ridge, ears, jowls), the eyes, the brow-part zone, and the beard
    envelope on the face. Hair boxes may be authored generously; subtracting
    this set guarantees no coincident-face z-fighting between parts.
    (The old 8-wide frame shipped WITH such overlaps — latent z-fights.)"""
    forb = set()
    for age in AGES:
        forb |= set(build_head(age).cells)
    forb |= set(build_eyes().cells)
    for x in range(-5, 5):
        for y in range(HEAD_Y0, EYE_Y + 1):          # beard envelope (face)
            for z in (FACE_Z, FACE_Z + 1):
                forb.add((x, y, z))
        for y in range(EYE_Y + 1, EYE_Y + 3):        # brow-part zone
            forb.add((x, y, FACE_Z + 1))
    return forb


def _subtract_forbidden(v):
    global _HAIR_FORBIDDEN
    if _HAIR_FORBIDDEN is None:
        _HAIR_FORBIDDEN = _hair_forbidden_cells()
    for k in list(v.cells):
        if k in _HAIR_FORBIDDEN:
            v.cells.pop(k)


def build_hair(style):
    v = Voxels()
    if style == "shaved":
        # thin stubble cap hugging the crown steps
        _scalp(v)
        return v
    if style == "bald":
        return v  # caller should not emit a file for this

    # --- MALE styles ---
    if style == "short_back":
        _scalp(v)
        v.box(HEAD_X0, HEAD_X1, HEAD_Y0 + 3, HEAD_Y1 + 1, HEAD_Z0 - 1, HEAD_Z0 + 1, HAIR_NEUTRAL)
    elif style == "wild_loose":
        _scalp(v, top_extra=1)
        v.box(HEAD_X0 - 1, HEAD_X1 + 1, HEAD_Y0 + 1, HEAD_Y1 + 2, HEAD_Z0 - 1, HEAD_Z0 + 1, HAIR_NEUTRAL)
        v.box(HEAD_X0 - 1, HEAD_X0, HEAD_Y0 + 2, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
        v.box(HEAD_X1, HEAD_X1 + 1, HEAD_Y0 + 2, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
    elif style == "braided_back":
        _scalp(v)
        # a thick braid running down the back (-Z)
        v.box(-1, 1, HEAD_Y0 - 6, HEAD_Y1, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)

    # --- FEMALE styles ---
    elif style == "bun":
        _scalp(v)
        v.box(-2, 2, CROWN_Y - 1, CROWN_Y + 2, HEAD_Z0 - 2, HEAD_Z0, HAIR_NEUTRAL)
    elif style == "braid_side":
        _scalp(v)
        v.box(HEAD_X1, HEAD_X1 + 1, HEAD_Y0 - 5, HEAD_Y1, 0, 2, HAIR_NEUTRAL)
    elif style == "braid_long":
        _scalp(v)
        v.box(-1, 1, HEAD_Y0 - 9, HEAD_Y1, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)
    elif style == "short_practical":
        _scalp(v)
        v.box(HEAD_X0, HEAD_X1, HEAD_Y0 + 4, HEAD_Y1 + 1, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)
    elif style == "twin_braids":
        _scalp(v)
        v.box(HEAD_X0, HEAD_X0 + 1, HEAD_Y0 - 5, HEAD_Y1, 0, 2, HAIR_NEUTRAL)
        v.box(HEAD_X1 - 1, HEAD_X1, HEAD_Y0 - 5, HEAD_Y1, 0, 2, HAIR_NEUTRAL)
    elif style == "half_up":
        _scalp(v, top_extra=1)
        v.box(HEAD_X0, HEAD_X1, HEAD_Y0, HEAD_Y0 + 4, HEAD_Z0 - 1, HEAD_Z0 + 1, HAIR_NEUTRAL)
    elif style == "loose_long":
        _scalp(v)
        v.box(HEAD_X0 - 1, HEAD_X0, HEAD_Y0 - 6, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
        v.box(HEAD_X1, HEAD_X1 + 1, HEAD_Y0 - 6, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
        v.box(HEAD_X0, HEAD_X1, HEAD_Y0 - 6, HEAD_Y0, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)
    elif style == "shaved_sides":
        _scalp(v)
        # mohawk-ish crest, kept on the crown's inner (top) footprint
        v.box(-1, 1, HEAD_Y1, HEAD_Y1 + 2, HEAD_Z0 + 2, HEAD_Z1 - 2, HAIR_NEUTRAL)
    elif style == "cropped":
        _scalp(v)
        v.box(HEAD_X0, HEAD_X1, CROWN_Y - 1, CROWN_Y, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)
    elif style == "wild":
        _scalp(v, top_extra=2)
        v.box(HEAD_X0 - 1, HEAD_X1 + 1, HEAD_Y0, HEAD_Y1 + 3, HEAD_Z0 - 1, HEAD_Z1 + 1, HAIR_NEUTRAL)
        # carve interior to leave a shell (keeps file small + reads as messy)
        inner = [(x, y, z) for (x, y, z) in list(v.cells)
                 if HEAD_X0 <= x < HEAD_X1 and HEAD_Z0 <= z < HEAD_Z1 and y < HEAD_Y1]
        for k in inner:
            v.cells.pop(k, None)
        _scalp(v, top_extra=2)
    else:
        raise ValueError(f"unknown hair style {style}")
    _subtract_forbidden(v)
    return v


# ---------------------------- BEARD GROUP ----------------------------------

def _pop_nose_overlap(v):
    """Remove beard cells coinciding with the protruding nose block — the
    beard wraps around it (moustache read) instead of z-fighting it."""
    for x in range(-1, 1):
        for y in range(EYE_Y - 2, EYE_Y):
            v.cells.pop((x, y, FACE_Z), None)


def build_beard(style):
    v = Voxels()
    chin_y = HEAD_Y0          # 16
    jaw_x0, jaw_x1 = -5, 5    # spans most of the 14-wide face
    if style == "full_long":
        v.box(jaw_x0, jaw_x1, chin_y - 8, EYE_Y - 1, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
        v.box(jaw_x0, jaw_x1, chin_y - 8, chin_y, FACE_Z - 1, FACE_Z + 2, HAIR_NEUTRAL)
    elif style == "full_braided":
        v.box(jaw_x0, jaw_x1, chin_y - 4, EYE_Y - 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
        # two braids hanging lower
        v.box(-2, -1, chin_y - 9, chin_y - 4, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
        v.box(1, 2, chin_y - 9, chin_y - 4, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
    elif style == "short_trimmed":
        v.box(jaw_x0, jaw_x1, chin_y - 2, EYE_Y - 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    elif style == "forked":
        v.box(jaw_x0, jaw_x1, chin_y - 2, EYE_Y - 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
        v.box(-3, -1, chin_y - 7, chin_y - 2, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
        v.box(1, 3, chin_y - 7, chin_y - 2, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
    elif style == "mutton_chops":
        v.box(jaw_x0, jaw_x0 + 2, chin_y - 1, EYE_Y, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
        v.box(jaw_x1 - 2, jaw_x1, chin_y - 1, EYE_Y, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    elif style == "goatee":
        v.box(-1, 1, chin_y - 4, EYE_Y - 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    elif style == "braided_long":
        v.box(jaw_x0, jaw_x1, chin_y - 3, EYE_Y - 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
        v.box(-2, -1, chin_y - 12, chin_y - 3, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
        v.box(1, 2, chin_y - 12, chin_y - 3, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
    else:
        raise ValueError(f"unknown beard style {style}")
    _pop_nose_overlap(v)
    return v


# ---------------------------- EYEBROW GROUP --------------------------------

def build_brows(style):
    v = Voxels()
    y = EYE_Y + 1
    z = FACE_Z + 1
    if style == "thick_flat":
        v.box(-5, -1, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 5, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "bushy":
        v.box(-5, -1, y, y + 2, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 5, y, y + 2, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "arched":
        v.box(-5, -1, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 5, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.set(-3, y + 1, z, HAIR_NEUTRAL)
        v.set(2, y + 1, z, HAIR_NEUTRAL)
    elif style == "unibrow":
        v.box(-5, 5, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "thin_arched":
        v.set(-5, y, z, HAIR_NEUTRAL); v.set(-4, y + 1, z, HAIR_NEUTRAL)
        v.set(-3, y + 1, z, HAIR_NEUTRAL); v.set(-2, y, z, HAIR_NEUTRAL)
        v.set(4, y, z, HAIR_NEUTRAL); v.set(3, y + 1, z, HAIR_NEUTRAL)
        v.set(2, y + 1, z, HAIR_NEUTRAL); v.set(1, y, z, HAIR_NEUTRAL)
    elif style == "sharp_angled":
        v.set(-5, y, z, HAIR_NEUTRAL); v.set(-4, y, z, HAIR_NEUTRAL)
        v.set(-3, y, z, HAIR_NEUTRAL); v.set(-2, y + 1, z, HAIR_NEUTRAL)
        v.set(4, y, z, HAIR_NEUTRAL); v.set(3, y, z, HAIR_NEUTRAL)
        v.set(2, y, z, HAIR_NEUTRAL); v.set(1, y + 1, z, HAIR_NEUTRAL)
    else:
        raise ValueError(f"unknown brow style {style}")
    return v


# ---------------------------- SCAR GROUP -----------------------------------

def build_scar(kind):
    v = Voxels()
    # Cheek/chin scars sit on the protrusion layer (touching the face plane);
    # brow/nose scars sit one further out, over the ridge/nose protrusions.
    z_face = FACE_Z
    z_ridge = FACE_Z + 1
    if kind == "cheek_slash":
        v.set(-5, EYE_Y - 1, z_face, SCAR_BAKED)
        v.set(-5, EYE_Y - 2, z_face, SCAR_BAKED)
        v.set(-4, EYE_Y - 3, z_face, SCAR_BAKED)
    elif kind == "brow_notch":
        v.set(3, EYE_Y + 1, z_ridge, SCAR_BAKED)
        v.set(3, EYE_Y + 2, z_ridge, SCAR_BAKED)
    elif kind == "nose_bridge":
        v.set(0, EYE_Y, z_ridge, SCAR_BAKED)
        v.set(-1, EYE_Y, z_ridge, SCAR_BAKED)
    elif kind == "chin_split":
        v.set(0, HEAD_Y0 + 1, z_face, SCAR_BAKED)
        v.set(0, HEAD_Y0 + 2, z_face, SCAR_BAKED)
    else:
        raise ValueError(f"unknown scar {kind}")
    return v


# ---------------------------------------------------------------------------
# Asset manifest -> (subdir, filename, builder)
# ---------------------------------------------------------------------------

HAIR_MALE = ["short_back", "shaved", "wild_loose", "braided_back"]
HAIR_FEMALE = ["bun", "braid_side", "braid_long", "short_practical", "twin_braids",
               "half_up", "loose_long", "shaved_sides", "cropped", "wild"]
BEARDS = ["full_long", "full_braided", "short_trimmed", "forked",
          "mutton_chops", "goatee", "braided_long"]
BROWS_MALE = ["thick_flat", "bushy", "arched", "unibrow"]
BROWS_FEMALE = ["thin_arched", "thick_flat", "bushy", "sharp_angled"]
SCARS = ["cheek_slash", "brow_notch", "nose_bridge", "chin_split"]
AGES = ["young", "adult", "middle", "elder"]


def manifest():
    items = []
    # body group
    for age in AGES:
        items.append(("body", f"head_{age}", lambda a=age: build_head(a)))
    items.append(("body", "eyes", build_eyes))
    items.append(("body", "body_base", build_body))
    items.append(("body", "hand", build_hand))
    items.append(("body", "foot", build_foot))
    # hair
    for s in HAIR_MALE:
        items.append(("hair", f"hair_m_{s}", lambda s=s: build_hair(s)))
    for s in HAIR_FEMALE:
        items.append(("hair", f"hair_f_{s}", lambda s=s: build_hair(s)))
    # beards
    for s in BEARDS:
        items.append(("beards", f"beard_{s}", lambda s=s: build_beard(s)))
    # eyebrows
    for s in BROWS_MALE:
        items.append(("eyebrows", f"brows_m_{s}", lambda s=s: build_brows(s)))
    for s in BROWS_FEMALE:
        items.append(("eyebrows", f"brows_f_{s}", lambda s=s: build_brows(s)))
    # scars
    for s in SCARS:
        items.append(("scars", f"scar_{s}", lambda s=s: build_scar(s)))
    return items


def main():
    ap = argparse.ArgumentParser(description="Generate Deepdraft dwarf part GLBs.")
    ap.add_argument("--out", default=None,
                    help="output root (default: <repo>/assets/dwarves)")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    out_root = Path(args.out) if args.out else repo / "assets" / "dwarves"

    total_files = 0
    total_bytes = 0
    for subdir, name, builder in manifest():
        vox = builder()
        mesh = mesh_from_voxels(vox)
        path = out_root / subdir / f"{name}.glb"
        size = write_glb(path, name, mesh, export_scale=EXPORT_SCALE)
        total_files += 1
        total_bytes += size
        tris = len(mesh[3]) // 3
        print(f"  {subdir:9s}/{name:24s}  {len(vox):4d} vox  {tris:5d} tris  {size:6d} B")

    print(f"\nWrote {total_files} GLBs ({total_bytes/1024:.1f} KB) to {out_root}")
    print("Reminder: generated dwarf GLBs already bake 0.125 scale; keep Godot Root Scale = 1.0.")


if __name__ == "__main__":
    main()

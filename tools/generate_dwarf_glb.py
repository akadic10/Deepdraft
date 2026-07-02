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
HAIR_NEUTRAL = (0.90, 0.90, 0.90)   # hair / beard / brows (tinted by hair_color)
HAIR_LIGHT   = (1.00, 1.00, 1.00)   # scattered highlight voxels (two-tone read)
HAIR_DARK    = (0.80, 0.80, 0.80)   # scattered shadow voxels
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

def _shade(color, f):
    return (min(1.0, color[0] * f), min(1.0, color[1] * f), min(1.0, color[2] * f))


def _rounded_row(v, y, x0, x1, z0, z1, cut, color):
    """One y row of a rounded solid: fill [x0,x1) x [z0,z1) in PLAN, skipping
    cells whose manhattan depth into a corner is < cut — the octagonal plan
    that makes hearthling masses read round (verified from head.qb)."""
    for x in range(x0, x1):
        for z in range(z0, z1):
            dx = min(x - x0, x1 - 1 - x)
            dz = min(z - z0, z1 - 1 - z)
            if dx + dz < cut:
                continue
            v.cells[(x, y, z)] = color


# Head silhouette profile, scanned from stonehearth male head.qb: octagonal
# plan (corner cut 3 in the mass), jaw tapering IN at the bottom (2 rows) and
# the crown stepping IN at the top (3 rows) — round at both ends, never a cube.
# Per row: (y, inset, corner_cut). z-inset is capped at 2 (the head is only 9
# deep; a full inset would pinch the profile).
_HEAD_PROFILE = [
    (16, 2, 2),   # jaw bottom
    (17, 1, 2),   # jaw
    (18, 0, 3), (19, 0, 3), (20, 0, 3), (21, 0, 3), (22, 0, 3), (23, 0, 3),
    (24, 0, 3),   # mass
    (25, 1, 2),   # crown step 1
    (26, 2, 2),   # crown step 2
    (27, 3, 1),   # top plate
]


def build_head(age):
    """Hearthling-shaped head (scanned from P:/stonehearth head.qb): rounded
    octagonal plan, tapered jaw AND crown, eye sockets carved into the face
    (the eyes part sits flush inside them), proud nose + brow ridge, ears.
    Age tiers differ by jowl/brow/chin voxels on the shared base."""
    v = Voxels()
    for (y, inset, cut) in _HEAD_PROFILE:
        zi = min(inset, 2)
        f = 0.88 + 0.24 * ((y - HEAD_Y0) / float(HEAD_Y1 - HEAD_Y0 - 1))
        _rounded_row(v, y, HEAD_X0 + inset, HEAD_X1 - inset,
                     HEAD_Z0 + zi, HEAD_Z1 - zi, cut, _shade(SKIN_NEUTRAL, f))
    # eye sockets — carved one deep into the face plane; build_eyes fills them
    for sx in (-4, 2):
        for x in range(sx, sx + 2):
            v.cells.pop((x, EYE_Y, HEAD_Z1 - 1), None)
    # brow ridge (proud forehead) on the protrusion layer, shading the sockets
    v.box(-5, 5, EYE_Y + 1, EYE_Y + 2, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    # protruding nose block, 2 wide x 2 tall x 1 deep, right under the eyes
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
        # rounder, slightly narrower chin (deepen the jaw taper)
        for z in range(HEAD_Z0 + 2, HEAD_Z1 - 2):
            v.cells.pop((HEAD_X0 + 2, HEAD_Y0, z), None)
            v.cells.pop((HEAD_X1 - 3, HEAD_Y0, z), None)
    return v


def build_eyes():
    """Fills the carved sockets flush (hearthling model): iris cell tinted by
    eye_color, pupil cell inward, both at the face plane — no pasted-on look."""
    v = Voxels()
    z = HEAD_Z1 - 1   # inside the socket, flush with the face
    for sx, pupil_x in ((-4, -3), (2, 2)):
        for x in range(sx, sx + 2):
            v.cells[(x, EYE_Y, z)] = EYE_PUPIL if x == pupil_x else EYE_WHITE
    return v


def build_body():
    """CLOTHED compact torso (doc 17 §1, hearthling model, colours BAKED):
    trouser pelvis WIDER than the tunic chest (squat stance), dark belt band
    with iron buckle, shoulder notches, tunic collar as the short neck.
    Still no arms, legs, or connector geometry — ever (doc 41 contract)."""
    v = Voxels()
    # trousers / pelvis — 10 wide vs the 8-wide waist, rounded plan corners
    _rounded_row(v, 6, -5, 5, -3, 3, 2, _shade(TROUSER, 0.88))
    _rounded_row(v, 7, -5, 5, -3, 3, 1, _shade(TROUSER, 0.96))
    _rounded_row(v, 8, -5, 5, -3, 3, 1, _shade(TROUSER, 1.04))
    # dark belt band (crisp, unshaded) + protruding iron buckle voxels
    _rounded_row(v, 9, -5, 5, -3, 3, 1, BELT_DARK)
    v.set(-1, 9, 3, BUCKLE_IRON)
    v.set(0, 9, 3, BUCKLE_IRON)
    # tunic waist -> chest (slight taper in, then the chest fills out)
    _rounded_row(v, 10, -4, 4, -3, 3, 1, _shade(CLOTH_TUNIC, 0.90))
    _rounded_row(v, 11, -4, 4, -3, 3, 1, _shade(CLOTH_TUNIC, 0.94))
    _rounded_row(v, 12, -4, 4, -3, 4, 1, _shade(CLOTH_TUNIC, 0.98))   # chest curve (+Z)
    _rounded_row(v, 13, -4, 4, -3, 4, 1, _shade(CLOTH_TUNIC, 1.02))
    # shoulder plate — flares WIDER than the chest (hearthling slope), rounded
    _rounded_row(v, 14, -5, 5, -3, 3, 2, _shade(CLOTH_TUNIC, 1.06))
    _rounded_row(v, 15, -4, 4, -3, 3, 2, _shade(CLOTH_TUNIC, 1.10))
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
    # round the outer corners (top edge of the fist)
    for z in (-2, 1):
        v.cells.pop((9, 10, z), None)
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
    # round the toe cap and heel corners (hearthling boot read)
    for x in (2, 5):
        v.cells.pop((x, 2, 4), None)     # toe-top corners... nothing at z4/y2 edge case-safe
        v.cells.pop((x, 1, 5), None)     # toe front corners
        v.cells.pop((x, 1, -3), None)    # heel back corners
    # dark sole band under everything (crisp)
    v.box(2, 6, 0, 1, -3, 6, BOOT_SOLE, shade=False)
    return v


# ---------------------------- HAIR GROUP -----------------------------------

_HEAD_TOPS = None


def _head_top_map():
    """(x,z) -> topmost head y, from the shared base head (adult, no jowls).
    The scalp shrink-wraps this map, so hair follows the rounded dome exactly
    whatever the head profile is — no hand-kept ring math."""
    global _HEAD_TOPS
    if _HEAD_TOPS is None:
        tops = {}
        for (x, y, z) in build_head("adult").cells:
            key = (x, z)
            if y > tops.get(key, -99):
                tops[key] = y
        _HEAD_TOPS = tops
    return _HEAD_TOPS


def _scalp(v, top_extra=0):
    """Cap shrink-wrapped over the crown dome (hearthling hair model): one
    voxel (plus top_extra on the peak) above every dome-region column."""
    for (x, z), ty in _head_top_map().items():
        if ty < CROWN_Y - 1:
            continue   # dome region only — skips ears, nose, ridge, jaw
        thick = 1 + (top_extra if ty >= HEAD_Y1 - 1 else 0)
        for k in range(1, thick + 1):
            v.cells[(x, ty + k, z)] = HAIR_NEUTRAL


def _two_tone(v):
    """Hearthling hair is two-tone: lighter highlight voxels scattered on
    top-exposed cells (position-hashed, deterministic). The values survive the
    runtime hair tint multiply as value variation."""
    for (x, y, z) in list(v.cells):
        if (x, y + 1, z) in v.cells:
            continue
        h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
        if h % 4 == 0:
            v.cells[(x, y, z)] = HAIR_LIGHT
        elif h % 4 == 1:
            v.cells[(x, y, z)] = HAIR_DARK


_FORBIDDEN_CORE = None    # head (all tiers) + eyes + brow-part zone
_FORBIDDEN_BEARD_ENV = None   # the face zone reserved for beard parts


def _forbidden_sets():
    """Cells other parts may never occupy. CORE = any head tier's geometry
    (mass, crown, nose, ridge, ears, jowls), the eyes, and the brow-part
    zone. BEARD_ENV = the face zone reserved for beards (hair also avoids
    it). Boxes may be authored generously; subtraction guarantees no
    coincident-face z-fighting between parts. (The old 8-wide frame shipped
    WITH such overlaps — latent z-fights.)"""
    global _FORBIDDEN_CORE, _FORBIDDEN_BEARD_ENV
    if _FORBIDDEN_CORE is None:
        core = set()
        for age in AGES:
            core |= set(build_head(age).cells)
        core |= set(build_eyes().cells)
        core |= set(build_body().cells)   # collar/shoulders — beards drape AROUND
        env = set()
        for x in range(-6, 6):
            for y in range(HEAD_Y0 - 1, EYE_Y + 1):      # beard envelope
                for z in (FACE_Z, FACE_Z + 1):
                    env.add((x, y, z))
            for y in range(EYE_Y + 1, EYE_Y + 3):        # brow-part zone
                core.add((x, y, FACE_Z + 1))
        _FORBIDDEN_CORE, _FORBIDDEN_BEARD_ENV = core, env
    return _FORBIDDEN_CORE, _FORBIDDEN_BEARD_ENV


def _subtract_forbidden(v, for_beard=False):
    core, env = _forbidden_sets()
    forb = core if for_beard else (core | env)
    for k in list(v.cells):
        if k in forb:
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
    _two_tone(v)
    return v


# ---------------------------- BEARD GROUP ----------------------------------

def _beard_crescent(v, hang_y, with_chops=True):
    """The hearthling beard shape (scanned from beard.qb): a crescent hugging
    the jaw — cheek panels rising toward the ears, a band across the lower
    face with a MOUTH NOTCH, under-chin fill, and a front curtain hanging to
    hang_y with a rounded tip."""
    if with_chops:
        for sx0, sx1 in ((-6, -3), (3, 6)):     # cheek panels up the sides
            v.box(sx0, sx1, 17, EYE_Y, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    v.box(-6, 6, 16, 19, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)   # lower-face band
    for x in range(-2, 2):                       # the mouth notch
        v.cells.pop((x, 18, FACE_Z), None)
    v.box(-4, 4, 15, 16, 3, FACE_Z + 1, HAIR_NEUTRAL)        # under-chin fill (front of collar)
    if hang_y < 15:
        v.box(-5, 5, hang_y + 1, 16, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
        v.box(-4, 4, hang_y, hang_y + 1, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)  # rounded tip


def build_beard(style):
    v = Voxels()
    if style == "full_long":
        _beard_crescent(v, 9)
    elif style == "full_braided":
        _beard_crescent(v, 13)
        v.box(-3, -2, 8, 13, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)   # hanging braids
        v.box(2, 3, 8, 13, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
    elif style == "short_trimmed":
        _beard_crescent(v, 15)
    elif style == "forked":
        _beard_crescent(v, 14)
        v.box(-5, -2, 9, 14, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)   # two forks
        v.box(2, 5, 9, 14, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    elif style == "mutton_chops":
        for sx0, sx1 in ((-6, -3), (3, 6)):      # cheek panels only
            v.box(sx0, sx1, 16, EYE_Y, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)
    elif style == "goatee":
        v.box(-2, 2, 15, 18, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)   # chin patch
        v.box(-1, 1, 11, 15, FACE_Z, FACE_Z + 1, HAIR_NEUTRAL)   # hanging point
        v.box(-2, 2, 15, 16, 3, FACE_Z, HAIR_NEUTRAL)            # under-chin
    elif style == "braided_long":
        _beard_crescent(v, 14)
        v.box(-3, -2, 4, 14, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)   # long braids
        v.box(2, 3, 4, 14, FACE_Z, FACE_Z + 2, HAIR_NEUTRAL)
    else:
        raise ValueError(f"unknown beard style {style}")
    _subtract_forbidden(v, for_beard=True)
    _two_tone(v)
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

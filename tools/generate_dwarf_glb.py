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
    * coordinates in MagicaVoxel voxel units (8 voxels = 1 game block)
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
voxel frame describing the whole dwarf. We model the entire dwarf once, then
emit each part as its own GLB while keeping the shared coordinates. Dropping
each mesh in at (0,0,0) reassembles a coherent dwarf automatically.

Frame convention:
    X : left(-) / right(+), centred on 0
    Y : up, 0 at the soles of the feet
    Z : back(-) / front(+), centred on 0   (face looks toward +Z)
Visual height target ~26 voxels = 3.3 game blocks (41b / doc 61).

COLOUR / TINT STRATEGY
----------------------
41b tints head, body, eyes, hair, beard and brows at runtime via a shader that
multiplies COLOR_0 by a `tint` uniform. So those parts are authored in a
near-white GRAYSCALE value gradient (top faces lighter, recesses darker): the
multiply preserves the shading while the tint supplies the hue. Parts that are
NOT tinted at runtime (hands, feet, scars) are baked with a literal colour.

Run:  python3 tools/generate_dwarf_glb.py            (writes assets/dwarves/)
      python3 tools/generate_dwarf_glb.py --out DIR  (custom output root)
"""

import argparse
import json
import os
import struct
from pathlib import Path

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


def write_glb(path: Path, name: str, mesh):
    positions, normals, colors, indices = mesh
    if not positions:
        raise ValueError(f"{name}: empty mesh")

    pos_b = b"".join(struct.pack("<3f", *p) for p in positions)
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

    mins = [min(p[i] for p in positions) for i in range(3)]
    maxs = [max(p[i] for p in positions) for i in range(3)]

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

SKIN_NEUTRAL = (0.97, 0.93, 0.90)   # head + body_base (tinted by skin_tone)
HAIR_NEUTRAL = (0.95, 0.95, 0.95)   # hair / beard / brows (tinted by hair_color)
EYE_WHITE    = (1.00, 1.00, 1.00)   # iris (tinted by eye_color)
EYE_PUPIL    = (0.18, 0.18, 0.18)   # stays dark after tint multiply
SKIN_BAKED   = (0.82, 0.62, 0.48)   # hands/feet (not tinted at runtime)
SCAR_BAKED   = (0.74, 0.46, 0.40)   # scar overlay (not tinted at runtime)

# ---------------------------------------------------------------------------
# Anatomy layout constants (shared voxel frame)
# ---------------------------------------------------------------------------

HEAD_Y0, HEAD_Y1 = 19, 27      # head cube vertical span
HEAD_X0, HEAD_X1 = -4, 4
HEAD_Z0, HEAD_Z1 = -3, 4       # face plane at z = HEAD_Z1 (front, +Z)
FACE_Z = HEAD_Z1               # 4
EYE_Y = 23                     # eye row


# ---------------------------- BODY GROUP -----------------------------------

def build_head(age):
    """Age tiers differ by wrinkle/jowl voxels; all share the base cube."""
    v = Voxels()
    # core head cube
    v.box(HEAD_X0, HEAD_X1, HEAD_Y0, HEAD_Y1, HEAD_Z0, HEAD_Z1, SKIN_NEUTRAL)
    # brow ridge (slightly proud forehead) on the face plane
    v.box(-3, 3, EYE_Y + 1, EYE_Y + 2, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    # broad nose
    v.box(-1, 1, EYE_Y - 1, EYE_Y + 1, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    # ears
    v.box(HEAD_X0 - 1, HEAD_X0, EYE_Y - 1, EYE_Y + 1, -1, 1, SKIN_NEUTRAL)
    v.box(HEAD_X1, HEAD_X1 + 1, EYE_Y - 1, EYE_Y + 1, -1, 1, SKIN_NEUTRAL)
    if age in ("middle", "elder"):
        # cheek jowls widen the lower face
        v.box(HEAD_X0 - 1, HEAD_X0, HEAD_Y0, EYE_Y - 1, 0, 3, SKIN_NEUTRAL)
        v.box(HEAD_X1, HEAD_X1 + 1, HEAD_Y0, EYE_Y - 1, 0, 3, SKIN_NEUTRAL)
    if age == "elder":
        # heavier brow + balder dome implied by a taller forehead block
        v.box(-3, 3, EYE_Y + 2, EYE_Y + 3, FACE_Z, FACE_Z + 1, SKIN_NEUTRAL)
    if age == "young":
        # rounder, slightly smaller chin
        for z in range(HEAD_Z0, HEAD_Z1):
            v.cells.pop((HEAD_X0, HEAD_Y0, z), None)
            v.cells.pop((HEAD_X1 - 1, HEAD_Y0, z), None)
    return v


def build_eyes():
    v = Voxels()
    for sx in (-2, 1):            # left / right eye sockets
        v.box(sx, sx + 1, EYE_Y, EYE_Y + 1, FACE_Z, FACE_Z + 1, EYE_WHITE, shade=False)
        # a darker pupil voxel pushed one deeper-front cell
        v.set(sx, EYE_Y, FACE_Z + 1, EYE_PUPIL)
    return v


def build_body():
    """Torso + legs + arms in one mesh (hands/feet are separate parts)."""
    v = Voxels()
    # legs (stout, two columns), y 2..9
    v.box(-4, -1, 2, 9, -2, 2, SKIN_NEUTRAL)
    v.box(1, 4, 2, 9, -2, 2, SKIN_NEUTRAL)
    # torso, broad, y 9..18
    v.box(-5, 5, 9, 18, -3, 3, SKIN_NEUTRAL)
    # shoulders + arms down the sides, y 8..17
    v.box(-7, -5, 8, 17, -2, 2, SKIN_NEUTRAL)
    v.box(5, 7, 8, 17, -2, 2, SKIN_NEUTRAL)
    # neck, y 18..19
    v.box(-2, 2, 18, 19, -1, 2, SKIN_NEUTRAL)
    return v


def build_hand():
    """Right hand (x>0). Left is the mirror, produced at write time."""
    v = Voxels()
    v.box(5, 8, 5, 8, -2, 2, SKIN_BAKED)   # at the lower end of the right arm
    return v


def build_foot():
    """Right foot (x>0). Left is the mirror."""
    v = Voxels()
    v.box(1, 4, 0, 2, -2, 4, SKIN_BAKED)   # extends forward (+Z) past the ankle
    return v


# ---------------------------- HAIR GROUP -----------------------------------

def _scalp(v, top_extra=0):
    """Cap over the crown of the head."""
    v.box(HEAD_X0, HEAD_X1, HEAD_Y1, HEAD_Y1 + 1 + top_extra, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)


def build_hair(style):
    v = Voxels()
    if style == "shaved":
        # thin stubble cap only
        v.box(HEAD_X0, HEAD_X1, HEAD_Y1, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
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
        v.box(-2, 2, HEAD_Y1, HEAD_Y1 + 3, HEAD_Z0 - 2, HEAD_Z0, HAIR_NEUTRAL)
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
        v.box(-1, 1, HEAD_Y1, HEAD_Y1 + 2, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)  # mohawk-ish crest
    elif style == "cropped":
        v.box(HEAD_X0, HEAD_X1, HEAD_Y1, HEAD_Y1 + 1, HEAD_Z0, HEAD_Z1, HAIR_NEUTRAL)
        v.box(HEAD_X0, HEAD_X1, HEAD_Y1 - 1, HEAD_Y1, HEAD_Z0 - 1, HEAD_Z0, HAIR_NEUTRAL)
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
    return v


# ---------------------------- BEARD GROUP ----------------------------------

def build_beard(style):
    v = Voxels()
    chin_y = HEAD_Y0          # 19
    jaw_x0, jaw_x1 = -3, 3
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
    return v


# ---------------------------- EYEBROW GROUP --------------------------------

def build_brows(style):
    v = Voxels()
    y = EYE_Y + 1
    z = FACE_Z + 1
    if style == "thick_flat":
        v.box(-3, -1, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 3, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "bushy":
        v.box(-3, -1, y, y + 2, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 3, y, y + 2, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "arched":
        v.box(-3, -1, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.box(1, 3, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
        v.set(-2, y + 1, z, HAIR_NEUTRAL)
        v.set(1, y + 1, z, HAIR_NEUTRAL)
    elif style == "unibrow":
        v.box(-3, 3, y, y + 1, z, z + 1, HAIR_NEUTRAL, shade=False)
    elif style == "thin_arched":
        v.set(-3, y, z, HAIR_NEUTRAL); v.set(-2, y + 1, z, HAIR_NEUTRAL); v.set(-1, y, z, HAIR_NEUTRAL)
        v.set(2, y, z, HAIR_NEUTRAL); v.set(1, y + 1, z, HAIR_NEUTRAL); v.set(0, y, z, HAIR_NEUTRAL)
    elif style == "sharp_angled":
        v.set(-3, y, z, HAIR_NEUTRAL); v.set(-2, y, z, HAIR_NEUTRAL); v.set(-1, y + 1, z, HAIR_NEUTRAL)
        v.set(2, y, z, HAIR_NEUTRAL); v.set(1, y, z, HAIR_NEUTRAL); v.set(0, y + 1, z, HAIR_NEUTRAL)
    else:
        raise ValueError(f"unknown brow style {style}")
    return v


# ---------------------------- SCAR GROUP -----------------------------------

def build_scar(kind):
    v = Voxels()
    z = FACE_Z + 1
    if kind == "cheek_slash":
        v.set(-3, EYE_Y - 1, z, SCAR_BAKED)
        v.set(-3, EYE_Y - 2, z, SCAR_BAKED)
        v.set(-2, EYE_Y - 2, z, SCAR_BAKED)
    elif kind == "brow_notch":
        v.set(2, EYE_Y + 1, z, SCAR_BAKED)
        v.set(2, EYE_Y + 2, z, SCAR_BAKED)
    elif kind == "nose_bridge":
        v.set(0, EYE_Y, z, SCAR_BAKED)
        v.set(0, EYE_Y + 1, z, SCAR_BAKED)
    elif kind == "chin_split":
        v.set(0, HEAD_Y0, z, SCAR_BAKED)
        v.set(0, HEAD_Y0 + 1, z, SCAR_BAKED)
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
        size = write_glb(path, name, mesh)
        total_files += 1
        total_bytes += size
        tris = len(mesh[3]) // 3
        print(f"  {subdir:9s}/{name:24s}  {len(vox):4d} vox  {tris:5d} tris  {size:6d} B")

    print(f"\nWrote {total_files} GLBs ({total_bytes/1024:.1f} KB) to {out_root}")
    print("Reminder: set GLB import Root Scale = 0.0625 in Godot (doc 61 §3).")


if __name__ == "__main__":
    main()

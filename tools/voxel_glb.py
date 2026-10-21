"""Shared voxel container, exposed-face mesher, and GLB writer.

Cells use integer minimum corners. Character centering is applied by the
dwarf exporter; other asset generators retain their existing frame.
"""
import json
import struct
import tempfile
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


def _corner_levels(front, corners, u, v, solid):
    """Classic voxel corner occlusion for one face: 0 (both sides solid) .. 3 (open).

    `front` is the empty cell the face looks into; each corner checks the two
    side cells and the diagonal cell beside it in that layer.
    """
    levels = []
    for corner in corners:
        su = 1 if corner[u] else -1
        sv = 1 if corner[v] else -1
        side_u = list(front); side_u[u] += su
        side_v = list(front); side_v[v] += sv
        diagonal = list(side_u); diagonal[v] += sv
        a, b, c = solid(tuple(side_u)), solid(tuple(side_v)), solid(tuple(diagonal))
        levels.append(0 if a and b else 3 - (a + b + c))
    return tuple(levels)


def greedy_mesh_from_voxels(vox: Voxels, occluders=(), occlusion=None):
    """Merge exposed, coplanar, identically colored cell faces into rectangles.

    Geometry and colors match mesh_from_voxels exactly. This is opt-in so the
    historical generators retain byte-for-byte output. Sorting makes the result
    independent of cell insertion order. Optional occluders are cells in other
    rigidly attached parts (e.g. hair/head), never independently moving limbs.
    No smooth normals or voxel nodes.

    `occlusion` (opt-in) bakes corner occlusion into vertex colors:
    {'curve': [l0, l1, l2, l3], 'ground': y, 'wall': z}. Cells below `ground`
    or behind `wall` count as solid for shading only, never for face culling.
    Faces merge only when color and all four corner levels agree, which keeps
    the interpolated shading exact; the quad diagonal follows the brighter pair.
    """
    positions, normals, colors, indices, shades = [], [], [], [], []
    cells = vox.cells
    occupied = cells if not occluders else cells.keys() | set(occluders)
    curve = occlusion['curve'] if occlusion else None
    ground = occlusion.get('ground') if occlusion else None
    wall = occlusion.get('wall') if occlusion else None

    def solid(p):
        return p in occupied or (ground is not None and p[1] < ground) or (wall is not None and p[2] < wall)

    for direction, (normal, corners) in _FACES.items():
        axis = next(i for i, v in enumerate(direction) if v)
        u, v = [i for i in range(3) if i != axis]
        planes = {}
        dx, dy, dz = direction
        for cell, color in cells.items():
            neighbor = (cell[0]+dx, cell[1]+dy, cell[2]+dz)
            if neighbor in occupied:
                continue
            plane = cell[axis] + (1 if direction[axis] > 0 else 0)
            key = tuple(color)
            if curve:
                key = (key, _corner_levels(neighbor, corners, u, v, solid))
            planes.setdefault(plane, {})[(cell[u], cell[v])] = key
        for plane, mask in sorted(planes.items()):
            for start in sorted(mask):
                if start not in mask:
                    continue
                color = mask[start]
                x, y = start
                width = 1
                while mask.get((x + width, y)) == color:
                    width += 1
                height = 1
                while all(mask.get((x + dx, y + height)) == color for dx in range(width)):
                    height += 1
                for dx in range(width):
                    for dy in range(height):
                        del mask[(x + dx, y + dy)]
                origin, size = [0, 0, 0], [1, 1, 1]
                origin[axis] = plane - (1 if direction[axis] > 0 else 0)
                origin[u], origin[v] = x, y
                size[u], size[v] = width, height
                base = len(positions)
                levels = None
                if curve:
                    color, levels = color
                for index, corner in enumerate(corners):
                    positions.append(tuple(origin[i] + corner[i] * size[i] for i in range(3)))
                    normals.append(normal)
                    if levels:
                        shade = curve[levels[index]]
                        shades.append(shade)
                        colors.append((color[0] * shade, color[1] * shade, color[2] * shade, 1.0))
                    else:
                        colors.append((*color[:3], 1.0))
                if levels and levels[0] + levels[2] < levels[1] + levels[3]:
                    indices.extend([base + 1, base + 2, base + 3, base + 1, base + 3, base])
                else:
                    indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    if curve:
        # TEXCOORD_1.x carries each vertex's shade so runtime wood recoloring can
        # match the unshaded swatch exactly (value ramps collide once darkened).
        return positions, normals, colors, indices, shades
    return positions, normals, colors, indices


# ---------------------------------------------------------------------------
# GLB writer (matches the project's existing flora GLBs)
# ---------------------------------------------------------------------------

def _pad4(b: bytes, fill=b"\x00") -> bytes:
    while len(b) % 4:
        b += fill
    return b


def write_glb(path: Path, name: str, mesh, export_scale: float = 1.0):
    from asset_ownership import guard_legacy_write
    guard_legacy_write(path)
    positions, normals, colors, indices = mesh[:4]
    shades = mesh[4] if len(mesh) > 4 else None
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
    v_shade = add_view(b"".join(struct.pack("<2f", s, 0.0) for s in shades), 34962) if shades else None

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
    if shades:
        gltf["meshes"][0]["primitives"][0]["attributes"]["TEXCOORD_1"] = len(gltf["accessors"])
        gltf["accessors"].append({"bufferView": v_shade, "componentType": 5126, "count": len(shades), "type": "VEC2"})

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


def write_glb_meshes(path: Path, name: str, meshes: dict, export_scale: float = 1.0):
    """Export named sibling meshes at identity under one shared asset/pivot.

    Reuse the single-mesh encoder so legacy exports remain byte-for-byte stable.
    Callers assign semantic node names; glTF has no shadow-only rendering flag.
    """
    doc = {'asset': {'version': '2.0', 'generator': 'Deepdraft voxel asset'},
           'scene': 0, 'scenes': [{'nodes': [0]}],
           'nodes': [{'name': name, 'children': []}], 'meshes': [],
           'materials': [], 'accessors': [], 'bufferViews': []}
    blob = b''
    with tempfile.TemporaryDirectory(prefix='voxel_glb_') as temp:
        for index, (part_name, mesh) in enumerate(meshes.items()):
            part = Path(temp) / (str(index) + '.glb')
            write_glb(part, part_name, mesh, export_scale)
            raw = part.read_bytes()
            size = struct.unpack_from('<I', raw, 12)[0]
            source = json.loads(raw[20:20 + size])
            data = raw[28 + size:]
            view_offset = len(doc['bufferViews'])
            accessor_offset = len(doc['accessors'])
            material_offset = len(doc['materials'])
            for view in source['bufferViews']:
                view['byteOffset'] += len(blob)
                doc['bufferViews'].append(view)
            for accessor in source['accessors']:
                accessor['bufferView'] += view_offset
                doc['accessors'].append(accessor)
            part_mesh = source['meshes'][0]
            for primitive in part_mesh['primitives']:
                primitive['attributes'] = {k: v + accessor_offset for k, v in primitive['attributes'].items()}
                primitive['indices'] += accessor_offset
                primitive['material'] += material_offset
            doc['materials'].extend(source['materials'])
            doc['nodes'][0]['children'].append(len(doc['nodes']))
            doc['nodes'].append({'name': part_name, 'mesh': len(doc['meshes'])})
            doc['meshes'].append(part_mesh)
            blob += data
    doc['buffers'] = [{'byteLength': len(blob)}]
    encoded = _pad4(json.dumps(doc, separators=(',', ':')).encode(), b' ')
    total = 28 + len(encoded) + len(blob)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, total) +
                     struct.pack('<II', len(encoded), 0x4E4F534A) + encoded +
                     struct.pack('<II', len(blob), 0x004E4942) + blob)
    return total



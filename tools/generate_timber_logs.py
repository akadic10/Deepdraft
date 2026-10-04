"""Generate the four raw timber drops at 8 voxels/block, inside one tile.

One connected bark-covered log with cut end grain; no processed planks/staves.
Colors are authored in sRGB then exported as linear vertex colors, matching
ItemDropManager's existing material. Root scale remains 1.0.
"""
from pathlib import Path
import math

from voxel_glb import Voxels, mesh_from_voxels, write_glb

ROOT = Path(__file__).resolve().parents[1]
PALETTES = {
    # Bark shadow/mid/highlight, sapwood, ring, heartwood.
    "oak_log": ("4E3018", "6C4528", "91633B", "C69B65", "9C7044", "B08351"),
    "pine_log": ("523922", "7A5230", "B08050", "DABE84", "AE8C54", "CCAA6D"),
    # Pink apple heartwood and red-brown juniper follow the item descriptions.
    "apple_wood": ("4A3932", "6E6258", "91806C", "C99C81", "9F6B55", "B87F66"),
    "juniper_log": ("493021", "75472D", "A47148", "C6A074", "8C5639", "AD714B"),
}


def linear_rgb(value):
    def channel(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    return tuple(channel(value[i:i + 2]) for i in (0, 2, 4))


def log_mesh(name, colors):
    v = Voxels()
    palette = tuple(map(linear_rgb, colors))
    # Six cells long, five wide, five high: a heavy, chamfered round log.
    # Centre X/Z exactly at zero, with its flat lower edge resting at Y=0.
    for z in range(-3, 3):
        for x in range(-2, 3):
            for y in range(5):
                if x * x + (y - 2) ** 2 > 5:
                    continue
                # Long bark ridges, not random checkerboard surface noise.
                color = palette[2 if y >= 3 else 1]
                if x == 0 and y == 4 or x == -2 and z < 1 or y == 0:
                    color = palette[0]
                if z in (-3, 2) and abs(x) <= 1 and 1 <= y <= 3:
                    color = palette[4 if max(abs(x), abs(y - 2)) == 1 else 5]
                    if y == 3 or x == -1:
                        color = palette[3]
                # A small contrasting knot on the upper side of hardwoods.
                if name in ("oak_log", "juniper_log") and x == 1 and y == 4 and z == 0:
                    color = palette[0]
                v.set(x, y, z, color)
    positions, normals, vertex_colors, indices = mesh_from_voxels(v)
    positions = [(x - .5, y, z) for x, y, z in positions]
    # Every horizontal vertex remains inside a radius of half a tile, even
    # with the loose-item system's arbitrary yaw. Stored logs never overhang.
    assert all(math.hypot(x / 8, z / 8) <= .5 for x, y, z in positions)
    assert min(y for x, y, z in positions) == 0
    return positions, normals, vertex_colors, indices


if __name__ == "__main__":
    for name, colors in PALETTES.items():
        mesh = log_mesh(name, colors)
        path = ROOT / f"assets/models/items/wood/{name}.glb"
        write_glb(path, name, mesh, export_scale=.125)
        print(f"{name}: 0.625 x 0.625 x 0.75 units; fits one 1x1 tile at every yaw")

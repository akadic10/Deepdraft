"""Finished gem drops: one stepped voxel jewel in six bright palettes.

Authored in the eight-units-per-block item frame, baked scale 0.125, grounded
at Y=0. Only exposed unit-cube faces, like the other project items. Linear
vertex colours supply broad bands and small square glints at RTS zoom; the
item registry supplies light-dependent gloss. No processing stage or textures.
Run with Python from any directory; output is deterministic.
"""
from math import sqrt
from pathlib import Path

from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb

ROOT = Path(__file__).resolve().parents[1]
# Shadow, body, bright band, crown, square glint. Jade stays softer and warmer
# than emerald; diamond has cool reflections with a warm white crown.
PALETTES = {
    "jade": ("245C45", "53AD79", "91DDA2", "B2E5B2", "E2F4CC"),
    "amethyst": ("492473", "8950BE", "B789EC", "D5B0F3", "F0DCFF"),
    "ruby": ("6F1234", "CC2452", "F65F79", "F9909C", "FFE0D6"),
    "sapphire": ("192E78", "345ED1", "669FFA", "A2C6FF", "E1EDFF"),
    "emerald": ("064C3C", "13966B", "38DCA1", "80ECC0", "D6FFDC"),
    "diamond": ("567F9C", "A4D4E8", "D6F5FF", "FFF6DE", "FFFFFF"),
}


def gem_mesh(palette):
    palette = list(map(linear_rgb, palette))
    voxels = Voxels()
    # Five real voxel layers: narrow grounded base, broad clipped shoulders,
    # flat stepped crown. Every edge stays on the same 1/8-block grid as dwarves.
    for y, radius in enumerate((1, 2, 3, 3, 2)):
        for x in range(-radius, radius):
            for z in range(-radius, radius):
                # Remove the outer corner cubes, never bevel their faces.
                if radius == 3 and x in (-3, 2) and z in (-3, 2):
                    continue
                band = (0, 1, 1, 1, 2)[y]
                if y in (2, 3) and x < 0 and z >= 0:
                    band = 2
                if y == 4 and x < 0 and z >= 0:
                    band = 3
                if (x, y, z) in ((-2, 4, 1), (-2, 3, 1)):
                    band = 4
                voxels.set(x, y, z, palette[band])
    positions, normals, colours, indices = mesh_from_voxels(voxels)
    assert min(p[1] for p in positions) == 0
    assert max(sqrt(p[0]**2+p[2]**2) for p in positions)*.125 < .5
    assert all(sum(abs(x) for x in n) == 1 for n in normals)
    assert all(x == int(x) for p in positions for x in p)
    return positions, normals, colours, indices


if __name__ == "__main__":
    for name, palette in PALETTES.items():
        mesh = gem_mesh(palette)
        path = ROOT / "assets/models/items/gem" / f"{name}_raw.glb"
        write_glb(path, name, mesh, export_scale=.125)
        print(f"{name}: {len(mesh[3])//3} triangles; 6x5x6 voxels; 0.75x0.625x0.75 blocks")

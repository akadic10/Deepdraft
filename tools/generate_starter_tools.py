"""Four iron-free starter tools, lying flat for storage and carrying.

Eight voxels per block, baked scale, linear vertex colours and no colliders.
The split wooden sockets are pegged; no hidden iron, leather or rope inputs.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb

ROOT = Path(__file__).resolve().parents[1]
WOOD, GRAIN, DARK, STONE, EDGE, ROCK = map(linear_rgb, (
    "94643F", "C39B67", "65462F", "7C8587", "B1B6AF", "535E63"))


def shaft(v, x, z0, z1):
    v.box(x, x+1, 0, 1, z0, z1, WOOD, shade=False)
    for z in range(z0+1, z1, 3):
        v.set(x, 0, z, GRAIN)


def hoe():
    v = Voxels()
    shaft(v, 0, -7, 5)
    v.box(-1, 2, 0, 2, 3, 5, DARK, shade=False)
    v.box(-3, 4, 1, 2, 4, 6, STONE, shade=False)
    v.box(-2, 3, 0, 1, 6, 7, EDGE, shade=False)
    v.set(0, 2, 4, GRAIN)
    return v


def spear():
    v = Voxels()
    shaft(v, 0, -8, 5)
    v.box(-1, 2, 0, 1, 4, 6, DARK, shade=False)
    v.box(-1, 2, 0, 2, 6, 8, STONE, shade=False)
    v.box(0, 1, 0, 1, 8, 10, EDGE, shade=False)
    v.set(0, 1, 6, ROCK)
    v.set(0, 1, 5, GRAIN)
    return v


def hammer():
    v = Voxels()
    shaft(v, 0, -5, 3)
    v.box(-3, 4, 0, 3, 1, 4, ROCK, shade=False)
    v.box(-2, 3, 2, 3, 1, 4, STONE, shade=False)
    v.box(-3, -2, 1, 2, 1, 4, EDGE, shade=False)
    v.box(0, 1, 0, 4, 1, 2, WOOD, shade=False)
    v.set(0, 3, 1, GRAIN)
    return v


def kit():
    v = Voxels()
    # Distinct mallet and adze side by side, one counted kit.
    shaft(v, -3, -5, 3)
    v.box(-5, 0, 0, 3, 1, 4, WOOD, shade=False)
    v.box(-5, -4, 0, 3, 1, 4, GRAIN, shade=False)
    v.box(-3, -2, 2, 3, 1, 4, DARK, shade=False)
    shaft(v, 3, -4, 5)
    v.box(2, 5, 0, 2, 3, 5, DARK, shade=False)
    v.box(2, 5, 1, 2, 4, 6, STONE, shade=False)
    v.box(2, 5, 0, 1, 6, 7, EDGE, shade=False)
    v.set(3, 2, 4, GRAIN)
    return v


if __name__ == "__main__":
    out = ROOT / "assets/models/items/tools"
    out.mkdir(parents=True, exist_ok=True)
    for name, make in [("stone_hoe", hoe), ("hunting_spear", spear),
                       ("carpentry_kit", kit), ("stone_hammer", hammer)]:
        v = make()
        positions, normals, colours, indices = mesh_from_voxels(v)
        # Grounded Y=0; center the long shaft on each storage cell.
        zs = [p[2] for p in positions]
        zmid = (min(zs)+max(zs))/2
        mesh = ([(x-.5, y, z-zmid) for x,y,z in positions], normals, colours, indices)
        write_glb(out / f"{name}.glb", name, mesh, export_scale=.125)
        print(f"{name}: {len(v)} voxels")

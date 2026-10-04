"""One reusable crate silhouette, 16 voxels/block, three visible fill levels.

Run with --update-data to register the authored crate presentations. Crates
are automatic packaging, never a craftable input or a separate inventory item.
"""
from pathlib import Path
import argparse
import json
import math

from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb

ROOT = Path(__file__).resolve().parents[1]
# Item identity stays in resources.json. These are art recipes, not game rules.
CONTENTS = {
    "apple": ("fruit", "B94835", "DE6942"),
    "blueberry": ("berry", "405F9C", "778BBC"),
    "elderberry": ("berry", "543B68", "84608E"),
    "juniper_berry": ("berry", "576D91", "93A5BD"),
    "wild_strawberry": ("strawberry", "B73537", "E76750"),
    "apple_seed": ("seed", "603922", "9A653D"),
    "juniper_seed": ("seed", "916D44", "C4A573"),
    "pig_tail_seed": ("seed", "98864E", "C6B974"),
    "oak_acorn": ("acorn", "AE773D", "D1A268"),
    "pine_cone": ("cone", "664128", "A77A49"),
    "blueberry_cutting": ("cutting", "3F6845", "739754"),
    "elderberry_cutting": ("cutting", "48643D", "94A958"),
    "grape_cutting": ("cutting", "4C6339", "889B4D"),
    "hops_cutting": ("cutting", "65823B", "A6B95C"),
    "strawberry_cutting": ("cutting", "386448", "6F9650"),
}


def shell():
    v = Voxels()
    shadow, board, edge = map(linear_rgb, ("624A35", "957552", "BB9569"))
    v.box(-6, 6, 0, 1, -5, 5, shadow, shade=False)
    for y in (1, 4):
        for z in (-5, 4):
            v.box(-6, 6, y, y+2, z, z+1, board, shade=False)
        for x in (-6, 5):
            v.box(x, x+1, y, y+2, -5, 5, board, shade=False)
    # Thick corner uprights and a clean open rim keep the surrounding world's
    # chunky wood language, despite the finer contents grid.
    for x in (-6, 4):
        for z in (-5, 3):
            v.box(x, x+2, 1, 7, z, z+2, edge, shade=False)
    for z in (-5, 4):
        v.box(-6, 6, 6, 7, z, z+1, edge, shade=False)
    for x in (-6, 5):
        v.box(x, x+1, 6, 7, -5, 5, edge, shade=False)
    return v


def piece(v, kind, x, y, z, dark, light):
    stem = linear_rgb("594430")
    leaf = linear_rgb("64854A")
    if kind == "fruit":
        v.box(x-1, x+2, y, y+2, z, z+2, dark, shade=False)
        v.box(x, x+2, y+2, y+3, z, z+2, light, shade=False)
        v.set(x, y+3, z, stem)
        v.set(x+1, y+3, z, leaf)
    elif kind == "acorn":
        v.box(x, x+2, y, y+2, z, z+2, light, shade=False)
        v.box(x, x+2, y+2, y+3, z, z+2, dark, shade=False)
        v.set(x, y+3, z, stem)
    elif kind == "cone":
        for h in range(4):
            v.box(x, x+2, y+h, y+h+1, z, z+2, light if h % 2 else dark, shade=False)
        v.set(x, y+4, z, dark)
    elif kind == "cutting":
        v.box(x, x+1, y, y+4, z, z+1, stem, shade=False)
        v.box(x-1, x+1, y+1, y+2, z-1, z+2, dark, shade=False)
        v.box(x, x+2, y+3, y+4, z, z+2, light, shade=False)
    elif kind == "strawberry":
        v.set(x, y, z, dark)
        v.box(x, x+2, y+1, y+3, z, z+2, light, shade=False)
        v.set(x+1, y+3, z, leaf)
    elif kind == "berry":
        v.box(x, x+2, y, y+2, z, z+2, dark, shade=False)
        v.set(x, y+1, z, light)
    else:
        v.box(x, x+1, y, y+1, z, z+2, dark, shade=False)
        v.set(x, y+1, z, light)
        v.set(x+1, y, z+1, light)


def crate_mesh(name, level):
    v = shell()
    kind, a, b = CONTENTS[name]
    dark, light = linear_rgb(a), linear_rgb(b)
    # A representative surface, not 24 literal miniature objects. Fill levels
    # intentionally exaggerate shape and color at ordinary RTS viewing distance.
    top = (1, 3, 5)[level]
    if level > 0:
        v.box(-4, 4, 1, top, -3, 4, dark, shade=False)
    locations = [(-3,-2),(0,0),(2,2),(-3,2),(2,-2),(0,-3),(-3,0),(2,0),(0,2)]
    for i, (x, z) in enumerate(locations[:(3, 6, 9)[level]]):
        piece(v, kind, x, top + (i % 2 if level == 2 else 0), z, dark, light)
    mesh = mesh_from_voxels(v)
    assert all(math.hypot(x/16, z/16) <= .5 for x,y,z in mesh[0])
    assert min(y for x,y,z in mesh[0]) == 0
    return mesh


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--update-data", action="store_true")
    args = parser.parse_args()
    for name in CONTENTS:
        for level, suffix in enumerate(("low", "half", "full")):
            path = ROOT / f"assets/models/items/crates/{name}_{suffix}.glb"
            write_glb(path, name + "_crate", crate_mesh(name, level), export_scale=1/16)
    if args.update_data:
        path = ROOT / "data/entities/items/resources.json"
        # Keep existing formatting/order and edit only the opted-in item defs.
        raw = path.read_text(encoding="utf-8")
        data = json.loads(raw)
        for key, definition in data.items():
            name = key.split(":")[-1]
            if name not in CONTENTS or not isinstance(definition, dict):
                continue
            old = '    "model": ' + json.dumps(definition["model"]) + ','
            models = [f"res://assets/models/items/crates/{name}_{suffix}.glb" for suffix in ("low", "half", "full")]
            new = '    "model": ' + json.dumps(models[0]) + ',\n    "crate_capacity": 24,\n    "crate_models": ' + json.dumps(models) + ','
            if "crate_capacity" not in definition:
                raw = raw.replace(old, new, 1)
        path.write_text(raw, encoding="utf-8")
    print(f"Generated {len(CONTENTS)*3} crate models; shared 0.75 x 0.625 tile footprint, 1/16 voxel scale.")

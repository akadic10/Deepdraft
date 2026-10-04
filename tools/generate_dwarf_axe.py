"""Dwarf work axe, eight voxels per block, origin at the lower hand grip.

The handle runs along +Y and the cutting edge faces +Z. Colors are linear
vertex colors, using the normal lit material; this is a tool visual, not loot.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb

ROOT = Path(__file__).resolve().parents[1]


def axe():
    v = Voxels()
    wood, grain, leather, iron, edge, dark = map(linear_rgb, (
        "A2794D", "C39B67", "66432D", "7D8A8E", "CFD6D1", "465158"))
    # Stout wooden haft with a wrapped lower grip and a small butt cap.
    v.box(0,1,-2,10,0,1,wood,shade=False)
    for y in range(-1,3):
        v.set(0,y,0,leather if y % 2 else grain)
    v.box(-1,1,-2,-1,0,1,dark,shade=False)
    # Forged eye, poll, and broad single cutting blade. The stepped blade
    # flares vertically as it widens, so it reads as an axe at RTS distance.
    v.box(-1,2,7,10,-1,2,dark,shade=False)
    v.box(-1,2,7,10,1,3,iron,shade=False)
    v.box(-1,2,6,11,3,5,iron,shade=False)
    v.box(0,1,6,11,5,6,edge,shade=False)
    v.set(0,9,-1,iron)
    v.set(0,10,0,grain)
    positions, normals, colors, indices = mesh_from_voxels(v)
    # Half-cell centering places the shaft exactly through the hand grip.
    return [(x-.5,y,z-.5) for x,y,z in positions], normals, colors, indices


if __name__ == "__main__":
    write_glb(ROOT / "assets/dwarves/tools/felling_axe.glb", "felling_axe", axe(), export_scale=.125)
    print("Felling axe: 8 voxels/block, baked scale .125, lower grip origin, +Y haft, +Z blade.")

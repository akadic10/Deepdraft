"""Implicit long-haft mining pick: 8 voxels/block, lower grip origin, +Z point."""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb
from generate_timber_logs import linear_rgb

ROOT = Path(__file__).resolve().parents[1]


def pickaxe():
    v = Voxels()
    wood, grain, leather, iron, edge, dark = map(linear_rgb, (
        "A2794D", "C39B67", "66432D", "7D8A8E", "CFD6D1", "465158"))
    v.box(0,1,-2,14,0,1,wood,shade=False)
    for y in range(-1,4):
        v.set(0,y,0,leather if y % 2 else grain)
    v.box(-1,1,-2,-1,0,1,dark,shade=False)
    v.box(-1,2,12,15,-1,2,dark,shade=False)
    # Broad central eye, stepped curved point, and shorter opposing chisel.
    v.box(-1,2,13,15,2,4,iron,shade=False)
    v.box(0,1,12,14,4,6,iron,shade=False)
    v.box(0,1,11,13,6,7,iron,shade=False)
    v.box(0,1,10,12,7,8,edge,shade=False)
    v.box(-1,2,13,15,-4,-1,iron,shade=False)
    v.box(-1,2,12,14,-6,-4,iron,shade=False)
    v.box(-1,2,11,13,-7,-6,edge,shade=False)
    v.set(0,14,0,grain)
    positions, normals, colors, indices = mesh_from_voxels(v)
    return [(x-.5,y,z-.5) for x,y,z in positions], normals, colors, indices


if __name__ == "__main__":
    write_glb(ROOT / "assets/dwarves/tools/mining_pickaxe.glb", "mining_pickaxe", pickaxe(), export_scale=.125)
    print("Mining pick: .125 baked scale, lower grip origin, +Y haft, +Z point.")

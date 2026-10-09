"""Split rails, pegged rungs and axe scars, at eight voxels per block."""
from pathlib import Path
from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import box, export_mesh, OAK

ROOT = Path(__file__).resolve().parents[1]

def ladder(height):
    vox = Voxels()
    for x in (-3, 2):
        box(vox, x, x+1, 0, height*8, -3, -1, OAK[2])
        for y in range(height*8):
            vox.cells[x, y, -2] = OAK[3 if y % 7 < 4 else 1]
        for y in range(5, height*8, 11):
            vox.cells.pop((x, y, -3), None)
    for y in range(2, height*8, 4):
        box(vox, -3, 3, y, y+1, -2, 0, OAK[4])
        for x in (-3, 2): vox.cells[x, y, 0] = OAK[1]
    return vox

if __name__ == '__main__':
    out = ROOT / 'assets/models/furniture/crude_ladder_4.glb'
    write_glb(out, 'crude_ladder_4', export_mesh(ladder(4)), export_scale=.125)
    # Disassembled rails and rungs form a compact carryable bundle. Same wood,
    # no invented metal fittings or invisible full-height item in the hands.
    bundle = Voxels()
    for y in (0, 2, 4):
        box(bundle, -5, 5, y, y+2, -2, 2, OAK[2+y//2])
    for x in (-3, 2): box(bundle, x, x+1, 6, 7, -3, 3, OAK[1])
    write_glb(ROOT / 'assets/models/items/furniture/crude_ladder.glb', 'ladder_section', export_mesh(bundle), export_scale=.125)

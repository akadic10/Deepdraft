"""Axe-hewn log decks and a pegged timber kit, eight voxels per block."""

# Retained only as historical source / flame-building helpers.
if __name__ == "__main__":
    from retired_voxel_art import stop
    stop()

from pathlib import Path
from voxel_glb import Voxels, write_glb
from generate_tavern_redesign import box, export_mesh, OAK

ROOT = Path(__file__).resolve().parents[1]

def deck(span):
    vox = Voxels()
    # Origin is the centre of the left near-bank tile; forward is -Z.
    # The top is flush with the banks. Four broad split logs form the deck.
    for log in range(4):
        x = -4 + log * 4
        box(vox, x, x+4, -3, 0, -(span+1)*8-4, 4, OAK[2])
        box(vox, x+1, x+3, -4, -3, -(span+1)*8-4, 4, OAK[1])
        for z in range(-(span+1)*8-4, 4):
            for dx in range(4):
                vox.cells[x+dx, -1, z] = OAK[2 if dx == 0 else 3 if (z+log*3) % 17 < 14 else 4]
            if z % 11 == log:
                vox.cells[x, -1, z] = OAK[1]
        # Pale square end grain and a darker heart, no round polygons.
        for z in (-(span+1)*8-4, 3):
            box(vox, x, x+4, -3, -1, z, z+1, OAK[4])
            vox.cells[x+1, -2, z] = OAK[2]
    # Cross ties sit underneath, leaving the whole walking width clear.
    for z in (0, -(span+1)*8):
        box(vox, -4, 12, -5, -3, z-1, z+1, OAK[1])
        for x in (-3, 0, 4, 8, 10): vox.cells[x, -1, z] = OAK[1]
    # Bury the landing tails slightly: coplanar log/terrain tops would flicker.
    for x in range(-4, 12):
        for z in list(range(-4, 4)) + list(range(-(span+1)*8-4, -span*8-4)):
            vox.cells.pop((x, -1, z), None)
    return vox

if __name__ == '__main__':
    for span in range(1, 6):
        write_glb(ROOT / f'assets/models/furniture/log_bridge_{span}.glb',
                  f'log_bridge_{span}', export_mesh(deck(span)), export_scale=.125)
    kit = Voxels()
    for z in (-4, 0):
        box(kit, -6, 6, 0, 3, z, z+3, OAK[2])
        box(kit, -6, 6, 3, 4, z, z+3, OAK[4])
    for x in (-4, 3): box(kit, x, x+1, 4, 5, -4, 3, OAK[1])
    write_glb(ROOT / 'assets/models/items/furniture/log_bridge.glb',
              'log_bridge_kit', export_mesh(kit), export_scale=.125)

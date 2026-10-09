"""Small seasonal wildflower clumps: eight voxels/block, baked scale, no colliders."""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/models/details/flowers'
SEASONS = ('spring', 'summer', 'autumn', 'winter')
# Same rooted stems in every season. Gaps expose the ground between rosettes.
GROUPS = [
    [(-4,-3,4), (2,-2,6), (-1,3,5), (4,4,3)],
    [(-3,-4,5), (3,-2,4), (-4,2,3), (2,4,6)],
    [(-4,-2,3), (1,-4,5), (4,2,6), (-1,4,4)],
]
PETALS = ('E8D8C8', '9D83A5', 'C8B888')  # Cream, muted heather, straw.


def color(hex_color):
    rgb = [int(hex_color[i:i+2], 16) / 255 for i in (0,2,4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055)**2.4 for c in rgb)


def clump(variant, season):
    v = Voxels()
    leaf = color('6AA040' if season == 'spring' else '4A7A2C' if season == 'summer' else '88774A')
    stem = color('5C4830' if season in ('autumn', 'winter') else '2E5218')
    for i, (x,z,h) in enumerate(GROUPS[variant]):
        height = min(h, 2) if season == 'winter' else h
        for y in range(height):
            v.set(x, y, z, stem)
        if season != 'winter':
            for dx,dz in [(-1,0),(1,0),(0,1)]:
                v.set(x+dx, 0, z+dz, leaf)
            v.set(x+(-1 if i % 2 else 1), 2, z, leaf)
        if season == 'summer' or (season == 'spring' and i % 2 == 0):
            for dx,dz in [(-1,0),(1,0),(0,-1),(0,1)]:
                v.set(x+dx, height, z+dz, color(PETALS[variant]))
            v.set(x, height, z, color('C88820'))
        else:
            v.set(x, height-1, z, color('A09060' if season == 'autumn' else '5C4830') if season != 'spring' else leaf)
    return v


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for season in SEASONS:
        for variant in range(3):
            name = f'flowers_{variant+1}_{season}'
            vox = clump(variant, season)
            write_glb(OUT / f'{name}.glb', name, mesh_from_voxels(vox), .125)
            print(name, len(vox))

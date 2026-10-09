"""The same seasonal flower stems and petals, carried with a wrapped root mat."""
from generate_flowers import OUT, SEASONS, clump, color
from voxel_glb import Voxels, mesh_from_voxels, write_glb

for variant in range(3):
    for season in SEASONS:
        vox = Voxels()
        for (x,y,z), rgb in clump(variant, season).cells.items():
            vox.set(x, y+3, z, rgb)
        for y in range(3):
            for x in range(-5,6):
                for z in range(-5,6):
                    if x*x+z*z > (29 if y else 21): continue
                    rgb = '705233' if y == 2 else 'AB8C5E'
                    if x == 0 or z == 0: rgb = '59452B'
                    vox.set(x,y,z,color(rgb))
        name = f'flowers_{variant+1}_packed_{season}'
        write_glb(OUT / f'{name}.glb', name, mesh_from_voxels(vox), .125)
        print(name, len(vox))

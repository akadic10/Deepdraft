"""Whole mature shrubs with a wrapped root ball, all seasons and picked states."""
from generate_shrubs import OUT, SEASONS, RIPE, plant, color
from voxel_glb import Voxels, mesh_from_voxels, write_glb

for species in RIPE:
    for season in SEASONS:
        for picked in ([False, True] if season in RIPE[species] else [False]):
            vox = Voxels()
            for (x,y,z), rgb in plant(species, season, picked).cells.items():
                vox.set(x, y+4, z, rgb)
            for y in range(4):
                radius = 2 if y in (0,3) else 3
                for x in range(-radius, radius+1):
                    for z in range(-radius, radius+1):
                        if x*x+z*z <= radius*radius+1:
                            rgb = (.43,.32,.20) if y == 3 else (.67,.55,.37)
                            if x == 0 or z == 0: rgb = (.35,.27,.17)
                            vox.set(x,y,z,color(rgb))
            name = f'{species}_packed_{season}' + ('_picked' if picked else '')
            write_glb(OUT/species/f'{name}.glb', name, mesh_from_voxels(vox), .125)
            print(name, len(vox))

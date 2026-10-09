"""Young berry plants: seasonal, fruit-free voxel art at baked 0.125 scale."""
from generate_shrubs import OUT, RIPE, SEASONS, color, line, mound
from voxel_glb import Voxels, mesh_from_voxels, write_glb


def young(species, season):
    vox = Voxels()
    wood = (.39, .29, .23)
    winter = season == 'winter'
    autumn = season == 'autumn'
    if species == 'wild_strawberry':
        # One rooted rosette with a short runner, well below the mature patch.
        line(vox, (0, 0, 0), (2, 0, 1), wood)
        line(vox, (0, 0, 0), (0, 2, 0), wood)
        if not winter:
            leaf = (.55, .36, .24) if autumn else (.38, .56, .29) if season == 'spring' else (.30, .51, .25)
            for x, z in ([(-2, 0), (1, 2)] if season == 'spring' else [(-2, 0), (1, -2), (1, 2)]):
                mound(vox, x, 1, z, 1, 1, 1, leaf)
        else:
            vox.set(2, 1, 1, color((.39, .34, .25)))
    else:
        elder = species == 'elderberry'
        tips = [(-2, 7, -1), (2, 8, 0), (0, 10, 2)] if elder else [(-2, 4, -1), (2, 5, 0), (0, 6, 2)]
        for i, tip in enumerate(tips):
            line(vox, (0, 0, 0), tip, wood)
            if winter:
                vox.set(tip[0], tip[1], tip[2], color((.53, .40, .30)))
                continue
            leaf = ((.56, .50, .26) if elder else (.59, .31, .23)) if autumn else (.37, .55, .29) if season == 'spring' else (.29, .45, .29)
            mound(vox, *tip, 1 if season == 'spring' else 2, 1, 1, leaf)
    return vox


if __name__ == '__main__':
    for species in RIPE:
        for season in SEASONS:
            name = f'{species}_young_{season}'
            vox = young(species, season)
            write_glb(OUT / species / f'{name}.glb', name, mesh_from_voxels(vox), .125)
            print(name, len(vox))

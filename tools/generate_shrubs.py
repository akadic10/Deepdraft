"""Seasonal wild shrubs, centered at ground Y0; eight voxels per world block.

Ripe and picked versions share stems/leaves. No textures, runtime scaling or
colliders. Legacy shrub-stage meshes are retained; generate_young_shrubs.py
authors the seasonal young plants used by the live cutting-growth system.
"""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/models/flora/bushes'
SEASONS = ('spring', 'summer', 'autumn', 'winter')
RIPE = {'blueberry': ('summer',), 'elderberry': ('autumn',),
        'wild_strawberry': ('spring', 'summer')}


def color(rgb, factor=1):
    rgb = [min(1, c * factor) for c in rgb]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055)**2.4 for c in rgb)


def line(v, a, b, rgb):
    steps = max(abs(b[i] - a[i]) for i in range(3))
    for j in range(steps + 1):
        v.set(*(round(a[i] + (b[i] - a[i]) * j / max(1, steps)) for i in range(3)), color(rgb))


def mound(v, cx, cy, cz, rx, ry, rz, rgb):
    for x in range(cx-rx, cx+rx+1):
        for y in range(max(0, cy-ry), cy+ry+1):
            for z in range(cz-rz, cz+rz+1):
                if ((x-cx)/(rx+.3))**2 + ((y-cy)/(ry+.3))**2 + ((z-cz)/(rz+.3))**2 <= 1:
                    v.set(x, y, z, color(rgb, .90 + .15*(y-cy+ry)/max(1,2*ry) + ((x*7+z*11)%5)*.012))


def plant(species, season, picked=False):
    v = Voxels()
    autumn = season == 'autumn'
    winter = season == 'winter'
    ripe = season in RIPE[species] and not picked
    wood = (.39, .29, .23)
    if species == 'elderberry':
        # Tall, open crown on several arching stems. Flat flower/fruit umbels.
        crowns = [(-5,12,-3), (4,14,-2), (-2,16,3), (5,10,5), (-5,9,4)]
        for i, (x,y,z) in enumerate(crowns):
            line(v, (0,0,0), (x//2,y-5,z//2), wood)
            line(v, (x//2,y-5,z//2), (x,y,z), wood)
            line(v, (x,y-3,z), (x+2,y-1,z-2), wood)
            if winter: continue
            leaf = (.56,.53,.25) if autumn else (.36,.52,.28) if season == 'spring' else (.27,.43,.24)
            radius = 2 if season == 'spring' else 3
            mound(v,x,y,z,radius,2,radius,leaf)
            mound(v,x-2,y-2,z+1,2,1,2,leaf)
            if season == 'summer' or ripe or (season == 'spring' and i % 2 == 0):
                fruit = (.35,.22,.42) if ripe else (.91,.86,.64)
                for dx,dz in [(-1,0),(0,-1),(1,0),(0,1)]:
                    v.set(x+dx,y+3,z+dz,color(fruit,1+(i%2)*.04))
    elif species == 'blueberry':
        # Dense rounded low shrub with a branching woody center.
        crowns = [(-3,6,-2), (3,7,-2), (-2,8,3), (3,5,3), (0,10,0)]
        for i,(x,y,z) in enumerate(crowns):
            line(v,(0,0,0),(x,y,z),wood)
            line(v,(x,y-2,z),(x+2,y,z-2),wood)
            if winter: continue
            leaf = (.62,.30,.22) if autumn else (.39,.57,.32) if season == 'spring' else (.31,.46,.33)
            mound(v,x,y,z,3,2,3,leaf)
            if ripe:
                for dx,dy,dz in [(-2,1,-1),(1,2,0),(0,1,2)]:
                    v.set(x+dx,y+dy,z+dz,color((.31,.38,.65),1+(i%3)*.06))
            elif season == 'spring':
                v.set(x-2,y+1,z-2,color((.90,.81,.70)))
    else:
        # Separate trifoliate rosettes linked by ground-hugging runners.
        leaf = (.57,.35,.22) if autumn else (.25,.48,.23)
        for i,(x,z) in enumerate([(-3,-3),(3,-2),(-2,3),(3,4)]):
            line(v,(0,0,0),(x,0,z),wood)
            line(v,(x,0,z),(x,2,z),wood)
            if winter:
                v.set(x,1,z,color((.38,.32,.23)))
                continue
            for dx,dz in ([(-2,0),(1,2)] if autumn else [(-2,0),(1,-2),(1,2)]):
                mound(v,x+dx,2,z+dz,1,1,1,leaf)
            if ripe:
                v.set(x,3,z,color((.79,.22,.20)))
                v.set(x,2,z,color((.66,.18,.16)))
            if season == 'spring':
                v.set(x-1,4,z+1,color((.95,.92,.79)))
    return v


if __name__ == '__main__':
    for species in RIPE:
        folder = OUT / species
        folder.mkdir(parents=True, exist_ok=True)
        for season in SEASONS:
            for picked in ([False, True] if season in RIPE[species] else [False]):
                name = f'{species}_{season}' + ('_picked' if picked else '')
                vox = plant(species,season,picked)
                write_glb(folder / f'{name}.glb',name,mesh_from_voxels(vox),.125)
                print(name,len(vox))
        name = f'{species}_shrub'
        small = Voxels()
        for (x,y,z), rgb in plant(species,'summer',True).cells.items():
            small.set(round(x*.6), round(y*.6), round(z*.6), rgb)
        write_glb(folder / f'{name}.glb',name,mesh_from_voxels(small),.125)

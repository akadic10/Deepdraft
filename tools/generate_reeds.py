"""Two grounded reed clumps, four seasons, eight voxels/block and linear colors."""
from pathlib import Path
from voxel_glb import Voxels, mesh_from_voxels, write_glb

OUT = Path(__file__).resolve().parents[1] / 'assets/models/details/reeds'
SEASONS = ('spring', 'summer', 'autumn', 'winter')
ROOTS = [(-2,-2), (2,-1), (-1,2), (2,3)]


def color(rgb):
    values = [int(rgb[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in values)


def line(v, a, b, shade):
    steps = max(abs(b[i]-a[i]) for i in range(3))
    for n in range(steps+1):
        v.set(*(round(a[i]+(b[i]-a[i])*n/max(1,steps)) for i in range(3)),color(shade))


def clump(variant, season):
    v = Voxels()
    dormant = season == 'winter'
    stalk = 'A09060' if season in ('autumn','winter') else '4A7A2C'
    leaf = 'C8B888' if season == 'autumn' else '88774A' if dormant else '6AA040' if season == 'spring' else '4A7A2C'
    for i, (x,z) in enumerate(ROOTS):
        height = (8 if variant == 0 else 12) + i % 3
        if season == 'spring': height -= 2
        if dormant and i % 2: height -= 3
        line(v,(x,0,z),(x,height,z),stalk)
        # Ascending pointed blades, with visible gaps between rooted stems.
        for direction in [-1,1]:
            if dormant and direction == 1: continue
            base = height//3 if direction == -1 else height//2
            line(v,(x,base,z),(x+direction*2,base+2,z),leaf)
            line(v,(x+direction*2,base+2,z),(x+direction*3,base+4,z+direction),leaf)
        if season in ('summer','autumn') and i % 2 == 0:
            for y in range(height-1,height+2):
                for dx in (0,1): v.set(x+dx,y,z,color('7A5230' if season == 'summer' else 'B08050'))
        elif dormant and i == 0:
            v.set(x,height,z,color('A09060'))
    return v


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    for season in SEASONS:
        for variant in range(2):
            name = f'reeds_{variant+1}_{season}'
            vox = clump(variant,season)
            write_glb(OUT/f'{name}.glb',name,mesh_from_voxels(vox),.125)
            print(name,len(vox))

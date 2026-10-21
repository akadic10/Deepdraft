"""Accepted hand-hewn timber shapes; the concept remains the higher visual target."""
from collections import deque
from functools import lru_cache
from pathlib import Path
from common import ROOT, Voxels, linear, read_json
from vox_source import write_model

PROFILE = read_json('data/art/voxel_hand_hewn_timber.json')
KINDS = ('dining_table', 'log_stool', 'game_table', 'workbench', 'timber')

def inside(x, z, polygon):
    hit = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > z) != (b[1] > z) and x < (b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:
            hit = not hit
    return hit


def footprint(polygon):
    return {(x,z) for x in range(min(p[0] for p in polygon), max(p[0] for p in polygon))
            for z in range(min(p[1] for p in polygon), max(p[1] for p in polygon))
            if inside(x+.5,z+.5,polygon)}


def depths(outline):
    result = {}; pending = deque()
    for p in sorted(outline):
        if any((p[0]+dx,p[1]+dz) not in outline for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]):
            result[p] = 0; pending.append(p)
    while pending:
        x,z = pending.popleft()
        for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
            p = x+dx,z+dz
            if p in outline and p not in result:
                result[p] = result[x,z]+1; pending.append(p)
    return result


def stroke(points, width=1):
    result=set()
    for a,b in zip(points,points[1:]):
        n=max(abs(a[i]-b[i]) for i in range(2))
        for i in range(n+1):
            x,z=[round(a[j]+(b[j]-a[j])*i/max(1,n)) for j in range(2)]
            for dx in range(width):
                for dz in range(width): result.add((x+dx,z+dz))
    return result


def bark_panel(x,z,large):
    """Unequal, staggered plates wrap around each side of the log."""
    tangent=x if abs(z)>abs(x) else z
    side=(1 if z>0 else 3) if abs(z)>abs(x) else (0 if x>0 else 2)
    if side in (1,2): tangent=-tangent-1
    cuts=PROFILE['bark']['large_cuts' if large else 'small_cuts'][side]
    index=next(i for i in range(len(cuts)-1) if cuts[i]<=tangent<cuts[i+1])
    plate=PROFILE['bark']['plates'][(index+side*3)%len(PROFILE['bark']['plates'])]
    return tangent-cuts[index],cuts[index+1]-cuts[index],plate


def log_shape(outline_key, bottom, height, end_grain=True):
    outline=footprint(PROFILE[outline_key]); depth=depths(outline)
    large=outline_key in ('large_outline','bench_outline')
    patches=[(footprint(p['outline']),p['role']) for p in PROFILE['large_patches' if large else 'small_patches']]
    cells={}
    for x,z in sorted(outline):
        offset,span,plate=bark_panel(x,z,large)
        for y in range(bottom,bottom+height):
            local=y-bottom
            # Short clefts and chipped shoulders, not full-height fluting. The
            # inner solid core, exact envelope and central contacts are retained.
            start=plate['cleft'][0]*height//8
            stop=plate['cleft'][1]*height//8
            seam=1 if local>(start+stop)//2 and span>=5 else 0
            if depth[x,z]==0 and offset==seam and start<=local<stop:
                continue
            if plate['chip'] and depth[x,z]<(2 if large else 1) and offset in (0,1) and local>=height-plate['chip']:
                continue
            role=plate['tone']
            if offset==seam and start-1<=local<=stop: role='bark_dark'
            patch_start,patch_stop=[v*height//8 for v in plate['patch']]
            shoulder=1 if local in (patch_start,patch_stop-1) and span>=5 else 0
            if 1+shoulder<=offset<span-1 and patch_start<=local<patch_stop:
                role='bark_light' if plate['tone']=='bark_dark' else 'peel'
            if end_grain and (local==height-1 or local==0):
                if depth[x,z]>=(2 if large else 1):
                    role='cut'
                    for points,color in patches:
                        if (x,z) in points: role=color
                else:
                    role=plate['tone']
            cells[x,y,z]=role
    if end_grain:
        lines=PROFILE['large_grain' if large else 'small_grain']
        for line in lines:
            for x,z in stroke(line):
                for y in (bottom,bottom+height-1):
                    if (x,y,z) in cells and depth.get((x,z),0)>2: cells[x,y,z]='grain'
        if large:
            knot=footprint([[6,-12],[10,-13],[13,-10],[12,-7],[8,-6],[6,-8]])
            for x,z in knot:
                cells[x,bottom+height-1,z]='grain'
            for x,z in footprint([[8,-11],[11,-11],[11,-8],[8,-8]]):
                cells[x,bottom+height-1,z]='knot'
    # Exposed shoulders show cut fibre instead of the dark internal filler.
    if end_grain:
        for x,z in sorted(outline):
            for y in range(bottom+height-2,bottom+height-4,-1):
                if (x,y,z) in cells and (x,y+1,z) not in cells:
                    cells[x,y,z]='cut_shade' if depth[x,z]>0 else 'bark_light'
                    break
    return cells


def carve(cells, scars, top):
    for scar in scars:
        for x,z in stroke(scar['points'],scar['width']):
            for y in range(top-scar['depth'],top): cells.pop((x,y,z),None)
            p=x,top-scar['depth']-1,z
            if p in cells: cells[p]='crack'


@lru_cache(maxsize=1)
def roles():
    dims=PROFILE['dimensions']
    stool=log_shape('stool_outline',0,dims['stool_height'])
    carve(stool,PROFILE['small_crack'],dims['stool_height'])
    base=log_shape('pedestal_outline',0,dims['pedestal_height'],False)
    top=dims['pedestal_height']+dims['slab_height']
    table=log_shape('large_outline',dims['pedestal_height'],dims['slab_height'])
    carve(table,PROFILE['large_crack'],top); table.update(base)
    game=dict(table)
    board=PROFILE['game']
    for x,z in [(x,z) for x in range(-board['extent'],board['extent']) for z in range(-board['extent'],board['extent'])
                if x in board['grid_lines'] or z in board['grid_lines']]:
        if (x,top-1,z) in game: game[x,top-1,z]='knot'
    for x,z,color in board['pieces']:
        for dx in range(-1,3):
            for dz in range(-1,3):
                # Preserve the established one-cell counter height and contacts.
                if (x+dx,top-1,z+dz) not in game: raise ValueError('Unsupported game piece')
                game[x+dx,top,z+dz]=color
    bench=log_shape('bench_outline',0,dims['bench_height'])
    carve(bench,PROFILE['large_crack']+PROFILE['bench_scars'],dims['bench_height'])
    # Exact rigid quarter-turn: same colored log as the stool, still grounded.
    timber={(x,z+7,6-y):c for (x,y,z),c in stool.items()}
    return dict(zip(KINDS,[table,stool,game,bench,timber]))


def connected(cells):
    pending=[next(iter(cells))]; seen=set(pending)
    for x,y,z in pending:
        for dx,dy,dz in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]:
            p=x+dx,y+dy,z+dz
            if p in cells and p not in seen: seen.add(p);pending.append(p)
    return len(seen)==len(cells)


def validate(models):
    top=PROFILE['dimensions']['pedestal_height']+PROFILE['dimensions']['slab_height']
    expected={'dining_table':(46,top,46),'game_table':(46,top+1,46),'log_stool':(14,14,14),
              'timber':(14,14,14),'workbench':(46,16,46)}
    for key,cells in models.items():
        size=tuple(max(p[i] for p in cells)+1-min(p[i] for p in cells) for i in range(3))
        assert size==expected[key],(key,size)
        assert min(p[1] for p in cells)==0
        assert connected(cells),f'{key}: disconnected occupied component'
    a=models['dining_table']; b=models['game_table']
    assert {p for p in b if p[1]<top}==set(a),'Game changes table geometry'
    assert all(b[p]==c for p,c in a.items() if p[1]!=top-1),'Game changes table sides/base'
    assert len([p for p in b if p[1]==top])==6*16
    assert {(x,z+7,6-y):c for (x,y,z),c in models['log_stool'].items()}==models['timber']
    # Chair envelopes at cardinal +/-2 stay entirely in the approved 5x5 region.
    for dx,dz in [(2,0),(-2,0),(0,2),(0,-2)]:
        assert all(-2.5 <= x/16+dx < 2.5 and -2.5 <= z/16+dz < 2.5 for x,y,z in models['log_stool'])


def model(kind, material_id=None):
    wood=(material_id or 'base:material:oak').rsplit(':',1)[-1]
    palette=PROFILE['palettes'][wood]
    vox=Voxels()
    vox.cells={p:linear(palette[role]) for p,role in sorted(roles()[kind].items())}
    return vox


def export_editable(directory):
    for wood,palette in PROFILE['palettes'].items():
        for kind,cells in roles().items():
            lo=[min(p[i] for p in cells) for i in range(3)]
            hi=[max(p[i] for p in cells)+1 for i in range(3)]
            names=list(palette)
            grid={(x-lo[0],hi[2]-1-z,y-lo[1]):names.index(role)+1 for (x,y,z),role in cells.items()}
            write_model(Path(directory)/(kind+'_'+wood+'.vox'),(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]),grid,
                        [tuple(bytes.fromhex(palette[name]))+(255,) for name in names])

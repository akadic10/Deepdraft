"""Two-cell chibi split-log bench, using the established hand-hewn wood roles."""
from functools import lru_cache
from pathlib import Path
from common import Voxels, linear, read_json
from hand_hewn_timber import PROFILE as TIMBER, footprint, depths, stroke
from vox_source import write_model

PROFILE = read_json('data/art/voxel_log_bench.json')


@lru_cache(maxsize=1)
def roles():
    cells = {}
    # Cross-log feet have flat ground contacts, clipped shoulders and real cut
    # ends. Their upper cells interlock with the curved underside of the seat.
    for support in PROFILE['supports']:
        section = footprint(support['outline'])
        depth = depths(section)
        cx = support['x']
        for x, y in sorted(section):
            for z in range(support['z_min'], support['z_max']):
                role = 'bark_dark' if x < -1 else 'bark'
                if 1 <= x <= 3 and 2 <= y < 7 and -4 <= z < 3:
                    role = 'peel'
                if z in (support['z_min'], support['z_max']-1) and depth[x,y] > 0:
                    role = 'cut_shade' if y < 3 else 'cut'
                    if (x,y) in {(-2,3),(-2,4),(-1,5),(0,5),(1,4),(1,2),(0,2)}:
                        role = 'grain'
                cells[x+cx,y,z] = role

    outline = footprint(PROFILE['seat_outline'])
    depth = depths(outline)
    top = PROFILE['seat_top']
    patches = [(patch['side'], footprint(patch['outline']), patch['role']) for patch in PROFILE['bark_patches']]
    top_patches = [(footprint(patch['outline']),patch['role']) for patch in PROFILE['top_patches']]
    for x,z in sorted(outline):
        for y in range(PROFILE['seat_bottom'],top):
            if depth[x,z] < PROFILE['underside_inset'][y-PROFILE['seat_bottom']]:
                continue
            role = 'bark' if y >= 10 else 'bark_dark'
            for side, points, color in patches:
                if z*side >= 3 and (x,y) in points:
                    role = color
            # Broad end grain on the sawn half-log ends, with incomplete arcs.
            if abs(x+.5) >= 14 and abs(z+.5) <= 4.5 and y >= 11:
                role = 'cut'
                if (z,y) in {(-4,13),(-3,12),(-2,11),(-1,11),(0,11),(2,12),(3,13),(-1,14),(0,13),(1,13)}:
                    role = 'grain'
            if y == top-1 and depth[x,z] >= 1:
                role = 'cut'
                for points,color in top_patches:
                    if (x,z) in points: role = color
            cells[x,y,z] = role

    # Long cut fibres belong on a split surface; rings belong on its ends.
    for line in PROFILE['top_grain']:
        for x,z in stroke(line):
            if (x,top-1,z) in cells and depth.get((x,z),0) >= 2:
                cells[x,top-1,z] = 'grain'
    for x,z in footprint(PROFILE['knot_outline']):
        if (x,top-1,z) in cells: cells[x,top-1,z] = 'knot'
    for split in PROFILE['split']:
        for x,z in stroke(split['points'],split['width']):
            for y in range(top-split['depth'],top): cells.pop((x,y,z),None)
            floor = x,top-split['depth']-1,z
            if floor in cells: cells[floor] = 'crack'
    for chip in PROFILE['chips']:
        lo,hi = chip['min'],chip['max']
        for x in range(lo[0],hi[0]):
            for y in range(lo[1],hi[1]):
                for z in range(lo[2],hi[2]): cells.pop((x,y,z),None)
        for x in range(lo[0],hi[0]):
            for z in range(lo[2],hi[2]):
                p = x,lo[1]-1,z
                if p in cells: cells[p] = 'cut_shade'
    return cells


def model(material_id='base:material:oak'):
    palette = TIMBER['palettes'][material_id.rsplit(':',1)[-1]]
    result = Voxels()
    result.cells = {p:linear(palette[role]) for p,role in sorted(roles().items())}
    return result


def export_editable(directory):
    cells = roles()
    lo = [min(p[i] for p in cells) for i in range(3)]
    hi = [max(p[i] for p in cells)+1 for i in range(3)]
    for wood,palette in TIMBER['palettes'].items():
        names = list(palette)
        grid = {(x-lo[0],hi[2]-1-z,y-lo[1]):names.index(role)+1 for (x,y,z),role in cells.items()}
        write_model(Path(directory)/('log_bench_'+wood+'.vox'),(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]),grid,
                    [tuple(bytes.fromhex(palette[name]))+(255,) for name in names])

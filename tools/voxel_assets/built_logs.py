"""Built logs (doc 275): the loose log stretched to fill its block, as pieces the game picks
from a log's neighbours (scripts/components/BuiltLogs.gd).

The loose log (`log()` in hearthblock_goods.py) is the Tier 1 stool on its side: a 12 x 12 bark
body with clipped corners, bark plates one cell proud, and at each end a bark rim, a cut face,
one square growth ring off centre, the pith and a drying split. A built log keeps that recipe
at block size (owner, 2026-10-26: "stretched just a little to hit the edges"):
- the body is 16 x 16, so it reaches every face of its block; its corners clip 3 cells deep;
- the plates are lighter bark, flush with the face, with a one-cell groove cut round them;
- the end is the loose log's, scaled up.

Pieces, each in four plate variants (`_p0` to `_p3`), cells in their block from 0 to 15:
- `h<lo><hi>`: a log lying along X, its -X and +X ends open (1, end grain) or joined (0);
- `u<lo><hi>`: a log standing up, its foot and top open or joined;
- `j<lo><hi><zlo><zhi>`: a joint whose top log lies along X with those ends, over a lower log
  along Z that comes in from -Z (zlo), +Z (zhi) or both. The lower log keeps only fresh-cut
  shoulders in the top log's corners, where the dwarves notched it.
The game turns a piece a quarter for logs along Z, and picks the top log by layer. The model is
in the hand-hewn source palette; CraftMaterials recolours it for each wood, as it does furniture.
"""
from common import Voxels, linear, read_json
import hearthblock

N = 16          # cells along a block edge
CLIP = 3        # the corners' depth (the loose log's 2 at 12 cells)
WOODS = {'oak': 'base:material:oak', 'pine': 'base:material:pine',
         'juniper': 'base:material:juniper', 'apple': 'base:material:applewood'}
# The stool's four plates (proposal.mjs), scaled to the block: (along from, along to, across from,
# across to) on the top, one side, the bottom and the other side.
PLATES = [(3, 11, 5, 11), (2, 9, 6, 12), (4, 11, 4, 9), (3, 10, 3, 8)]
SLIDES = (-2, 1, -1, 2)
RING = (3, 10, 4, 11)   # the growth ring's square, off centre: across u, then v
PITH = (6, 7)
VARIANTS = 4
ROLES = ('bark_dark', 'bark', 'bark_light', 'wood_top', 'grain', 'pith', 'riven')


def colours(wood=None):
    """Hewn roles in this wood's colours, as the loose log maps them; with no wood, the hand-hewn
    source palette itself, which CraftMaterials recolours in the game."""
    hewn = read_json(hearthblock.DATA)['palettes']['hewn']
    if wood is None: return {role: linear(hewn[role]) for role in ROLES}
    craft = read_json('data/materials/craft_materials.json')
    source = {h.upper(): k for k, h in craft['source_palettes']['hand_hewn_timber']['colors'].items()}
    target = craft['materials'][WOODS[wood]]['colors']
    return {role: linear(target[source[hewn[role].upper()]]) for role in ROLES}


def inside(u, v):
    return 0 <= u < N and 0 <= v < N and min(u, N - 1 - u) + min(v, N - 1 - v) >= CLIP


def place(axis, a, u, v):
    """A log's own cell (along, across, up) in its block. A lying log's v is up."""
    if axis == 'x': return (a, v, u)
    if axis == 'z': return (u, v, a)
    return (u, a, v)


def log_cells(axis, open_lo, open_hi, variant):
    """One block of log along `axis`: bark body, plates, and end grain on its open ends."""
    cells = {}
    for a in range(N):
        for u in range(N):
            for v in range(N):
                if inside(u, v): cells[a, u, v] = 'bark'
    # One plate a face, lighter bark in a cut groove; each variant leaves one face bare and
    # turns and slides the rest, so neighbouring blocks differ.
    for i, (fixed, level) in enumerate((('v', N - 1), ('u', N - 1), ('v', 0), ('u', 0))):
        if (variant + i) % 4 == 3: continue
        a0, a1, w0, w1 = PLATES[(i + variant) % 4]
        slide = SLIDES[(i + variant) % 4]
        a0, a1 = max(2, a0 + slide), min(N - 2, a1 + slide)
        if (i + variant) % 2: w0, w1 = N - w1, N - w0
        for a in range(a0 - 1, a1 + 1):
            for w in range(w0 - 1, w1 + 1):
                key = (a, w, level) if fixed == 'v' else (a, level, w)
                if key not in cells: continue
                if a in (a0 - 1, a1) or w in (w0 - 1, w1): del cells[key]
                else: cells[key] = 'bark_light'
    for end, opened in ((0, open_lo), (N - 1, open_hi)):
        if not opened: continue
        inward = 1 if end == 0 else -1
        for u in range(N):
            for v in range(N):
                if not inside(u, v): continue
                rim = not all(inside(u + du, v + dv) for du, dv in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                role = 'bark' if rim else 'wood_top'
                u0, u1, v0, v1 = RING
                if not rim and u0 <= u < u1 and v0 <= v < v1 and (u in (u0, u1 - 1) or v in (v0, v1 - 1)): role = 'grain'
                if (u, v) == PITH: role = 'pith'
                cells[end, u, v] = role
        # The drying split: from beside the pith out through the rim, then down the side.
        for u in range(PITH[0] + 2, N): cells.pop((end, u, PITH[1] + 1), None)
        for step in range(1, 5): cells.pop((end + inward * step, N - 1, PITH[1] + 1), None)
    return {place(axis, a, u, v): role for (a, u, v), role in cells.items()}


def joint_cells(top_lo, top_hi, arm_lo, arm_hi, variant):
    """The top log along X, whole; the lower log along Z only as cut shoulders on its arms' sides."""
    cells = log_cells('x', top_lo, top_hi, variant)
    for cell in log_cells('z', False, False, variant):
        if cell in cells: continue
        if (cell[2] < N // 2 and arm_lo) or (cell[2] >= N // 2 and arm_hi): cells[cell] = 'riven'
    return cells


def pieces():
    """Every piece name and its cells as roles."""
    result = {}
    for variant in range(VARIANTS):
        for lo in (0, 1):
            for hi in (0, 1):
                result[f'h{lo}{hi}_p{variant}'] = log_cells('x', lo, hi, variant)
                result[f'u{lo}{hi}_p{variant}'] = log_cells('y', lo, hi, variant)
                for zlo, zhi in ((1, 0), (0, 1), (1, 1)):
                    result[f'j{lo}{hi}{zlo}{zhi}_p{variant}'] = joint_cells(lo, hi, zlo, zhi, variant)
    return result


def voxels(roles, wood=None):
    paint = colours(wood)
    v = Voxels()
    v.cells = {cell: paint[role] for cell, role in sorted(roles.items())}
    return v

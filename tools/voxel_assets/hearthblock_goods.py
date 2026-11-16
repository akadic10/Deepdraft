"""Hearthblock stockpile goods (doc 256): the stored goods the game has today, in the
furniture's and trees' square vocabulary.

Mined stone, soil and ore are chunky square fragments with a split; gems are square
crystal clusters; logs are the Tier 1 stool on its side in each wood's colours;
produce, seeds and cuttings sit in an axe-hewn crate at three fill levels, and so do
the Farmer's seven vegetables, each laid to be told from the rest from above (doc 309),
and the log torches, the one piece of furniture kept 24 to a crate; the
Worker's tools have worked stone heads lashed to their hafts, the Ranger's kit is
its two tools crossed and lashed where they cross, and the Blacksmith's copper
tools are the copper bar's own metal on the same hafts. Every good keeps its
kind's footprint, so carrying, crate storage, stockpile tiles and the tool rack's
hooks are unchanged. Goods the game does not have yet (drinks, staves, cloth,
honey, ...) stay in items.py.
"""
from common import Voxels, linear, read_json
import hearthblock

ITEMS = read_json('tools/art_data/voxel_items.json')
TOOL = {k: linear(v) for k, v in read_json('data/materials/craft_materials.json')['source_palettes']['starter_tool']['colors'].items()}
WOOD = {k: linear(v) for k, v in dict(riven='C08A4E', riven_dark='9A6A38', chop='7A512E', bark='5C3B26',
                                      bark_light='7B5336', bark_dark='3E2819', rope='CFAB69', rope_dark='9F7E45').items()}
# The starter tools' heads are the benches' worked stone (doc 301; write_data.WORKED_STONE): a dark
# skin, lit on top, and pale fresh stone where it was ground to an edge or worn by striking.
STONE = {k: linear(v) for k, v in dict(skin='5D6166', top='6C7075', dark='45494D', fresh='9EA3A6', fresh_dark='85898C').items()}
# The fishing rod's line and float (tools/hearthblock/art/dwarves.mjs), for the Ranger's kit.
ROD = {k: linear(v) for k, v in dict(line='E9DFC6', float_wood='E2CA97', float_red='B6452E', float_dark='7B2E20').items()}
# The copper tools' metal is the copper bar's own colours. A tool is the bar's body on its dark
# shade, and only what was ground or filed is the bar's light: at the sky's midday that light is as
# pale as pine, so a blade drawn in it reads as wood.
COPPER = {k: linear(v) for k, v in ITEMS['metal']['copper_bar'].items()}


def notched(v, lo, hi, color, n=1):
    """Cuboid [lo, hi) with an n x n notch at each vertical edge: the trees' corner."""
    for x in range(lo[0], hi[0]):
        for z in range(lo[2], hi[2]):
            if (x - lo[0] < n or hi[0] - 1 - x < n) and (z - lo[2] < n or hi[2] - 1 - z < n): continue
            for y in range(lo[1], hi[1]): v.cells[x, y, z] = color


def paint(v, lo, hi, color):
    for p in list(v.cells):
        if all(lo[i] <= p[i] < hi[i] for i in range(3)): v.cells[p] = color


def carve(v, lo, hi):
    for p in list(v.cells):
        if all(lo[i] <= p[i] < hi[i] for i in range(3)): del v.cells[p]


def round_z(v, lo, hi, color):
    """Cuboid [lo, hi) lying along Z with its four long edges cut: round in section."""
    for x in range(lo[0], hi[0]):
        for y in range(lo[1], hi[1]):
            if x in (lo[0], hi[0] - 1) and y in (lo[1], hi[1] - 1): continue
            for z in range(lo[2], hi[2]): v.cells[x, y, z] = color


def _exposed(v, p):
    return any((p[0] + d[0], p[1] + d[1], p[2] + d[2]) not in v.cells
               for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))


# ── Mined goods: 12 x 12 x 12 fragments ─────────────────────────────────────────
def mined(name):
    """A broken square chunk: a tall block and a lower one on a wide base, a crack
    down the front, lit tops and dark undersides. Ores carry stepped seams and raised
    nuggets; soils are softer stepped mounds with grit on top; coal glints."""
    style = ITEMS['mined_styles'][name]; c = {k: linear(h) for k, h in style['palette'].items()}
    v = Voxels()
    if style['shape'] == 'soil':
        notched(v, (-6, 0, -6), (6, 5, 6), c['body'], 2)
        notched(v, (-5, 5, -4), (5, 8, 5), c['body'], 2)
        notched(v, (-3, 8, -2), (3, 10, 3), c['body'], 1)
        notched(v, (2, 5, -6), (5, 7, -3), c['body'], 1)           # a slumped side lump
        paint(v, (-6, 0, -6), (6, 2, 6), c['shade'])
        for p in list(v.cells):
            if (p[0], p[1] + 1, p[2]) not in v.cells: v.cells[p] = c['light']
        for x, y, z in ((-4, 4, 3), (3, 4, 4), (1, 7, -3), (-2, 9, 1), (4, 6, -5), (-5, 4, -4)):
            if (x, y, z) in v.cells: v.cells[x, y, z] = c['accent']
        return v
    notched(v, (-6, 0, -5), (6, 5, 6), c['body'], 2)               # wide base
    notched(v, (-5, 5, -4), (2, 11, 5), c['body'], 1)              # the tall chunk, off centre
    notched(v, (2, 5, -3), (6, 9, 3), c['body'], 1)                # a lower chunk beside it
    notched(v, (-4, 11, -2), (0, 12, 2), c['body'], 0)             # a chip on top
    carve(v, (-2, 6, 2), (-1, 11, 5))                              # a crack down the front
    carve(v, (5, 3, 4), (6, 5, 6)); carve(v, (-6, 3, -5), (-4, 5, -3))   # broken corners
    paint(v, (-6, 0, -5), (6, 2, 6), c['shade'])
    for p in list(v.cells):
        if (p[0], p[1] + 1, p[2]) not in v.cells: v.cells[p] = c['light']
        elif p[0] in (-3, -1) and 6 <= p[1] < 11 and 2 <= p[2] < 5 and _exposed(v, p): v.cells[p] = c['cleft']
    if 'accent' in c:
        for x, y, z in ((-6, 2, 1), (5, 6, -2), (-5, 8, 3), (1, 9, -4)):
            if (x, y, z) in v.cells: v.cells[x, y, z] = c['accent']
    if 'mineral' in c:
        seams = [(-5, 2, 5), (-4, 2, 5), (-4, 3, 5), (-3, 3, 5), (-3, 4, 5), (-2, 4, 5), (-1, 4, 5),
                 (-5, 6, 4), (-5, 7, 4), (-4, 7, 4), (-4, 8, 4), (-3, 8, 4),
                 (5, 2, -1), (5, 3, -1), (5, 3, 0), (5, 4, 0), (5, 4, 1),
                 (5, 6, -2), (5, 7, -2), (5, 7, -1), (5, 8, -1),
                 (1, 6, 4), (1, 7, 4), (1, 7, 3), (1, 8, 3), (1, 9, 3),
                 (-6, 2, -2), (-6, 3, -2), (-6, 3, -1), (-6, 4, -1), (-6, 4, 0),
                 (1, 2, 5), (2, 2, 5), (2, 3, 5), (3, 3, 5), (3, 4, 5), (4, 4, 5),
                 (-5, 7, -3), (-5, 8, -3), (-5, 8, -2), (-5, 9, -2), (-5, 10, -1), (-5, 10, 0),
                 (3, 6, 2), (3, 7, 2), (4, 7, 2), (4, 8, 2), (5, 8, 2),
                 (2, 2, -5), (3, 2, -5), (3, 3, -5), (4, 3, -5), (4, 4, -5)]
        for x, y, z in seams:                                       # two-cell stepped seams
            for q in ((x, y, z), (x, y - 1, z)):
                if q in v.cells: v.cells[q] = c['mineral']
        for lo, hi in (((3, 9, -2), (5, 10, 0)), ((0, 11, -1), (2, 12, 1)), ((2, 5, 3), (4, 6, 5)), ((-2, 5, -5), (0, 6, -4))):
            for x in range(lo[0], hi[0]):
                for y in range(lo[1], hi[1]):
                    for z in range(lo[2], hi[2]): v.cells[x, y, z] = c['mineral_light']   # raised nuggets
    else:
        for x, y, z in ((-3, 11, 1), (4, 8, 1), (-5, 4, 5)):
            if (x, y, z) in v.cells: v.cells[x, y, z] = c['light']   # coal glints
    return v


# ── Gems: square crystal clusters ───────────────────────────────────────────────
def gem(colors):
    """Three square crystals with stepped points on a small foot, dark to light."""
    cs = [linear(h) for h in colors]
    v = Voxels()
    notched(v, (-4, 0, -3), (4, 1, 3), cs[0], 1)
    for lo, hi, tip, body, face in (((-2, 0, -2), (2, 9, 2), ((-1, 9, -1), (1, 11, 1)), cs[1], cs[3]),
                                    ((2, 0, -3), (5, 6, 0), ((3, 6, -2), (4, 8, -1)), cs[1], cs[3]),
                                    ((-5, 0, 0), (-2, 5, 3), ((-4, 5, 1), (-3, 7, 2)), cs[0], cs[2])):
        notched(v, lo, hi, body, 0)
        notched(v, tip[0], tip[1], cs[2], 0)
        paint(v, (hi[0] - 1, lo[1] + 1, lo[2]), (hi[0], hi[1], hi[2]), face)         # a lit facet
        paint(v, (lo[0], hi[1] - 1, lo[2]), (hi[0], hi[1], hi[2]), cs[2])
    v.cells[0, 11, 0] = cs[4]; v.cells[3, 8, -2] = cs[4]; v.cells[-4, 7, 1] = cs[3]
    return v


# ── Metal: the Blacksmith's copper (doc 297) ────────────────────────────────────
def metal(name):
    """A copper bar is a rough casting from the smelter's stone mould, wider at the foot, its
    top lit and its ends dark."""
    c = {k: linear(h) for k, h in ITEMS['metal'][name].items()}
    v = Voxels()
    notched(v, (-7, 0, -3), (7, 2, 3), c['body'], 1)
    notched(v, (-6, 2, -2), (6, 4, 2), c['body'], 0)
    paint(v, (-6, 3, -2), (6, 4, 2), c['light']); paint(v, (-7, 0, -3), (7, 1, 3), c['shade'])
    paint(v, (-7, 0, -3), (-6, 4, 3), c['shade']); paint(v, (6, 0, -3), (7, 4, 3), c['shade'])
    v.cells[-3, 3, -1] = c['body']; v.cells[2, 3, 0] = c['body']    # the casting's pocks
    return v


# ── Logs: the Tier 1 stool on its side ──────────────────────────────────────────
def log(material_id):
    """The axe-hewn stool on its side, cut end toward the front, in this wood's own
    colours, so stored logs match the furniture and the square trees."""
    hewn = read_json(hearthblock.DATA)['palettes']['hewn']
    craft = read_json('data/materials/craft_materials.json')
    source = {h.upper(): k for k, h in craft['source_palettes']['hand_hewn_timber']['colors'].items()}
    target = craft['materials'][material_id]['colors']
    v = Voxels()
    for (x, y, z), role in log_roles().items():
        v.cells[x, z + 7, y - 7] = linear(target[source[hewn[role].upper()]])
    return v


def log_roles():
    """The stool without its root flare: the cut top and bark rim repeat at the other
    end, so a stored log shows end grain at both ends."""
    stool = hearthblock.roles('stool')
    roles = {p: r for p, r in stool.items() if p[1] >= 2}
    roles.update({(x, 13 - y, z): r for (x, y, z), r in stool.items() if y >= 12})
    return roles


# ── Planks: the Carpenter's sawn boards ─────────────────────────────────────────
def wood_roles(material_id):
    """The furniture palette's wood roles in this wood's own colours, as log() recolours them."""
    hewn = read_json(hearthblock.DATA)['palettes']['hewn']
    craft = read_json('data/materials/craft_materials.json')
    source = {h.upper(): k for k, h in craft['source_palettes']['hand_hewn_timber']['colors'].items()}
    target = craft['materials'][material_id]['colors']
    return {role: linear(target[source[h.upper()]]) for role, h in hewn.items() if h.upper() in source}


PLANK = ((-5, 0, -7), (5, 4, 7))   # ten cells wide, four thick, as long as the log it was sawn from


def plank(material_id):
    """One thick board sawn from a log with the copper pull saw (the owner, 2026-11-13), lying
    along Z as a log does, in this wood's own colours. Every face is sawn and every corner is
    square: no bark, no riven grain and no chopped steps, which are the camp's hewn work. Its
    face is as pale as a log's cut end, and the saw's strokes run across it, where a riven face's
    lines run along; each stroke stops short of the edges, so the board stays one piece. Both
    ends show the log's square rings, cut through below the pith. The strokes are three steps darker than the face: at the sky's
    midday a line one step darker is gone."""
    c = wood_roles(material_id)
    lo, hi = PLANK
    v = Voxels()
    notched(v, lo, hi, c['riven'], 0)
    paint(v, lo, (hi[0], 1, hi[2]), c['grain'])                   # dark underneath
    paint(v, (lo[0], 3, lo[2]), hi, c['wood_top'])                # the sawn face
    for z, x0, x1 in ((-4, -4, 3), (0, -3, 4), (3, -4, 3)):       # the saw's strokes across it
        paint(v, (x0, 3, z), (x1, 4, z + 1), c['riven_dark'])
    for z in (lo[2], hi[2] - 1):                                  # square-cut ends: the log's square rings, cut through
        paint(v, (lo[0], 0, z), (hi[0], 3, z + 1), c['wood_top'])
        paint(v, (-3, 0, z), (3, 1, z + 1), c['grain'])
        for x in (-3, 2): paint(v, (x, 1, z), (x + 1, 3, z + 1), c['grain'])
        paint(v, (-1, 2, z), (1, 3, z + 1), c['grain'])
    return v


# ── Crates: split slats on bark corner posts, lashed with rope ──────────────────
def shell():
    v = Voxels()
    notched(v, (-5, 0, -4), (5, 1, 4), WOOD['riven_dark'], 0)
    for x0 in (-6, 4):
        for z0 in (-5, 3):
            notched(v, (x0, 0, z0), (x0 + 2, 7, z0 + 2), WOOD['bark'], 0)
            paint(v, (x0, 6, z0), (x0 + 2, 7, z0 + 2), WOOD['bark_light'])
            paint(v, (x0, 4, z0), (x0 + 2, 5, z0 + 2), WOOD['rope'])
    for y0 in (1, 4):
        for z in (-5, 4):
            notched(v, (-4, y0, z), (4, y0 + 2, z + 1), WOOD['riven'], 0)
            paint(v, (-4, y0, z), (4, y0 + 1, z + 1), WOOD['riven_dark'])
        for x in (-6, 5):
            notched(v, (x, y0, -3), (x + 1, y0 + 2, 3), WOOD['riven'], 0)
            paint(v, (x, y0, -3), (x + 1, y0 + 1, 3), WOOD['riven_dark'])
    for x, y, z in ((-1, 2, -5), (2, 5, 4), (5, 2, 0), (-6, 5, 1)): v.cells[x, y, z] = WOOD['chop']
    return v


def lay_fish(v, style, x, y, z, along, facing):
    """One fish lying flank-up (doc 289): seven cells along `along` from (x, y, z) and three
    rows across, back, side and belly. A one-cell snout, the head with its eye, three body
    cells carrying the style's marks, a one-cell wrist and a forked tail; `facing` +1 puts the
    snout first. A mark is [body cell, row] in the style's `mark` colour, or [body cell, row,
    colour key] in another of its colours (the trout's red spot)."""
    marks = {(mark[0], mark[1]): mark[2] if len(mark) > 2 else 'mark' for mark in style['marks']}
    for i in range(7):
        step = i if facing > 0 else 6 - i
        for r, row in enumerate(('back', 'side', 'belly')):
            if step in (0, 5) and row != 'side': continue
            if step == 6 and row == 'side': continue
            role = 'tail' if step == 6 else 'eye' if step == 1 and row == 'side' else row
            if 2 <= step <= 4 and (step - 2, row) in marks: role = marks[(step - 2, row)]
            v.cells[(x + i, y, z + r) if along == 'x' else (x + r, y, z + i)] = linear(style[role])


# ── Vegetables (doc 309): what a Farmer pulls from a field ──────────────────────
# A stockpile is read from above and from far off, so each vegetable is laid to show that camera
# its own colours in its own pattern: no two crates differ by colour alone.
def bed(v, top, color):
    """The goods rest on a bed of themselves, up to `top`."""
    notched(v, (-4, 1, -3), (4, top, 3), color, 0)


def lay(v, piece, at, axis='x', sign=1):
    """Sets a piece drawn in its own cells (along, up, across) into the crate at `at`, lying along
    X or Z and pointing `sign`."""
    for (a, u, b), color in piece.items():
        v.cells[(at[0] + sign * a, at[1] + u, at[2] + b) if axis == 'x' else (at[0] + b, at[1] + u, at[2] + sign * a)] = color


def ball(body, under, top):
    """A round root three cells across: a cross of five cells under and over a square of nine."""
    piece = {(a, 1, b): body for a in (-1, 0, 1) for b in (-1, 0, 1)}
    for a, b in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        piece[a, 0, b] = under; piece[a, 2, b] = top
    return piece


def radishes(v, c, level):
    """Round red roots in two rows, root tips outward and leaves gathered down the middle: a green
    spine between red flanks, a white tip at each root."""
    y = [2, 4, 6][level]
    bed(v, y, c['dark'])
    def radish(red):
        piece = {(a, u, b): red for a in (0, 1) for u in (0, 1) for b in (0, 1)}
        piece[2, 0, 1] = c['tip']                                  # the root's white tip
        piece[-1, 0, 0] = piece[-1, 0, 1] = c['leaf']              # its leaves
        return piece
    rows = [[(-2, -3, -1), (1, -1, 1), (-2, 0, -1)], [(-2, -3, -1), (1, -2, 1), (-2, 0, -1), (1, 1, 1)],
            [(-2, -3, -1), (1, -3, 1), (-2, -1, -1), (1, -1, 1), (-2, 1, -1), (1, 1, 1)]][level]   # (x, z, the way its root points)
    for i, (x, z, sign) in enumerate(rows):
        riding = level == 2 and i % 4 in (1, 2)                    # in a full crate every other root rides a cell higher, in a deeper red
        lay(v, radish(c['deep'] if riding else c['light']), (x, y + riding, z), 'x', sign)
    high = 1 + (level == 2)
    if level: notched(v, (-1, y, -3), (1, y + high, 3), c['leaf'], 0)   # past a few roots their leaves fill the middle,
    for x, z in ((-1, -3), (0, -2), (-1, -1), (0, 0), (-1, 1), (0, 2)):   # with a frilled ridge
        if v.cells.get((x, y, z)) == c['leaf']: v.cells[x, y + high, z] = c['leaf_light']


def carrots(v, c, level):
    """Long tapered roots side by side, their green tops together at one end: orange bars that
    thin to a point, and a band of leaves."""
    y = [2, 4, 6][level]
    bed(v, y, c['dark'])
    def carrot(orange, thin):
        piece = {(a, u, b): orange for a in (2, 3, 4) for u in (0, 1) for b in (0, 1)}   # the shoulder
        piece[5, 0, thin] = piece[5, 1, thin] = piece[6, 0, thin] = orange               # thinning
        piece[7, 0, thin] = c['tip']                                                     # to its point
        for a in (0, 1):
            for b in (0, 1): piece[a, 0, b] = c['leaf']            # its top
        piece[0, 1, thin] = piece[1, 1, 1 - thin] = c['leaf_light']
        return piece
    lay(v, carrot(c['light'], 0), (-4, y, -3))
    lay(v, carrot(c['light'], 1), (-4, y, 1))
    if level >= 1: lay(v, carrot(c['deep'], 0), (-4, y + 1, -1))   # one more rides between them
    if level == 2:
        lay(v, carrot(c['deep'], 1), (-4, y, -1))
        lay(v, carrot(c['light'], 1), (-4, y + 2, -2)); lay(v, carrot(c['light'], 0), (-4, y + 2, 0))
        lay(v, carrot(c['deep'], 0), (-4, y + 3, -1))


# Round roots lie six to a layer, each clear of the next, and two more ride in the hollows of a full crate.
ROUND_SITES = [(-3, -2), (0, 1), (3, -2), (-3, 1), (3, 1), (0, -2)]
ROUND_TOP = [(-2, 0), (1, -1)]


def turnips(v, c, level):
    """Round white roots, each tipped a different way: a white flank, a purple shoulder over one
    side and a green stub of leaves on it."""
    y = [2, 4, 6][level]
    bed(v, y, c['dark'])
    def turnip():
        piece = ball(c['flank'], c['dark'], c['light'])
        for cell in piece:
            if cell[0] == -1 or cell == (0, 2, 0): piece[cell] = c['shoulder'] if cell[1] else c['shoulder_dark']
        piece[-1, 3, 0] = c['leaf']
        return piece
    ways = [('x', 1), ('z', -1), ('x', -1), ('z', -1), ('z', 1), ('z', 1), ('x', 1), ('x', -1)]   # the way each root points
    sites = ROUND_SITES[:[3, 6, 6][level]] + (ROUND_TOP if level == 2 else [])
    for i, (x, z) in enumerate(sites):
        lay(v, turnip(), (x, y + (i >= 6), z), *ways[i])


def cabbage_head(v, x, y, z, c):
    """One head, four cells across with its corners off: dark outer leaves round a pale heart."""
    notched(v, (x, y, z), (x + 4, y + 3, z + 4), c['light'], 1)
    paint(v, (x, y, z), (x + 4, y + 1, z + 4), c['dark'])
    notched(v, (x + 1, y + 3, z + 1), (x + 3, y + 4, z + 3), c['crown'], 0)


def cabbages(v, c, level):
    """Big pale heads, two across a crate: each a rounded square of outer leaves round a paler
    heart. A full crate carries a third on top."""
    y = [1, 4, 5][level]
    bed(v, y, c['dark'])
    cabbage_head(v, -4, y, -3, c); cabbage_head(v, 0, y, -2, c)
    if level == 2: cabbage_head(v, -2, y + 2, -1, c)


def onions(v, c, level):
    """Golden bulbs, round, each with its dry neck: standing, or tumbled on its side."""
    y = [2, 4, 6][level]
    bed(v, y, c['dark'])
    ways = [None, ('x', 1), None, ('z', 1), ('x', -1), None, None, ('z', -1)]
    sites = ROUND_SITES[:[3, 6, 6][level]] + (ROUND_TOP if level == 2 else [])
    for i, (x, z) in enumerate(sites):
        bulb = ball(c['light'] if i % 2 else c['deep'], c['dark'], c['sheen'] if i % 2 else c['light'])
        bulb[(0, 3, 0) if ways[i] is None else (2, 1, 0)] = c['neck']
        lay(v, bulb, (x, y + (i >= 6), z), *(ways[i] or ('x', 1)))


def pumpkin(v, x, y, z, c):
    """One pumpkin: a squat ribbed round five cells across, a domed top and a dry stem."""
    notched(v, (x, y, z), (x + 5, y + 3, z + 5), c['light'], 1)
    notched(v, (x + 1, y + 3, z + 1), (x + 4, y + 4, z + 4), c['crown'], 0)
    paint(v, (x, y, z), (x + 5, y + 1, z + 5), c['dark'])
    for rib in (1, 3): paint(v, (x + rib, y, z), (x + rib + 1, y + 4, z + 5), c['rib'])
    v.cells[x + 2, y + 4, z + 2] = c['stem']; v.cells[x + 2, y + 5, z + 2] = c['stem_light']; v.cells[x + 3, y + 4, z + 2] = c['stem']


def pumpkins(v, c, level):
    """Great orange pumpkins: one sits in a crate, two fill it from side to side and a third rides
    on them."""
    if level == 0: pumpkin(v, -3, 1, -3, c)
    else: pumpkin(v, -5, 1, -3, c); pumpkin(v, 0, 1, -2, c)
    if level == 2: pumpkin(v, -3, 4, -3, c)


def kale(v, c, level):
    """Bunches lying in the crate, stalks together at one end and the leaves fanning out: dark
    frilled blades with a pale rib."""
    y = [2, 4, 6][level]
    bed(v, y, c['dark'])
    def bunch():
        piece = {}
        for a, half in ((2, 2), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3)):
            for b in range(-half, half): piece[a, 0, b] = c['light']
        for a, b in ((2, -2), (3, 2), (4, -3), (5, 2), (6, -3), (7, 1), (7, -1), (5, -1), (3, 0)):   # the frill: curled edges stand up
            piece[a, 1, b] = c['frill']
        for a in (0, 1):
            for b in (-1, 0): piece[a, 0, b] = c['rib']            # the stalks, cut together
        for a, b in ((2, 0), (3, 0), (4, 0), (2, -1), (3, -2), (4, 1)): piece[a, 0, b] = c['rib']   # their ribs run out into the leaves
        return piece
    lay(v, bunch(), (-4, y, 0)); lay(v, bunch(), (3, y + 1, 0), 'x', -1)   # two bunches, head to foot
    if level >= 1: lay(v, bunch(), (-4, y + 2, 0))
    if level == 2: lay(v, bunch(), (0, y + 3, -3), 'z', 1)


VEGETABLES = dict(radish=radishes, carrot=carrots, turnip=turnips, cabbage=cabbages, onion=onions, pumpkin=pumpkins, kale=kale)


# ── Log torches: the one piece of furniture kept 24 to a crate ───────────────────
def torches(v, char, binding, level):
    """Unlit log torches lying along the crate, three abreast and head to tail: a stick two cells
    square with its lit side up, a fibre binding standing a cell proud of it, and a charred tip.
    A low crate shows one layer, a half crate a second on it, and a full one two more heaped on
    top. The sticks are the starter tools' wood (`starter_tool`), so a crate of pine torches
    shows pine as a pine haft does; the binding is the crate's own rope."""
    piece = {}
    for a in range(8):
        for b in range(2):
            if a == 7: piece[a, 0, b] = piece[a, 1, b] = char
            elif a >= 5:
                piece[a, 0, b] = WOOD['rope_dark']
                piece[a, 1, b] = piece[a, 2, b] = WOOD['rope_dark'] if a == 5 else binding
            else:
                piece[a, 0, b] = TOOL['bark']; piece[a, 1, b] = TOOL['grain'] if b == 0 else TOOL['wood']
    notched(v, (-4, 1, -3), (4, 2, 3), TOOL['bark'], 0)            # the layer underneath, in shadow
    for layer in range(level + 1):
        heaped = layer == 2
        for row, z in enumerate((-2, 0) if heaped else (-3, -1, 1)):
            heads_right = (row + layer) % 2 == 0
            lay(v, piece, (-4 if heads_right else 3, 2 + 2 * layer, z), 'x', 1 if heads_right else -1)


def crate(name, level):
    v = shell(); kind, dark, light = ITEMS['crate_contents'][name]; dark, light = linear(dark), linear(light)
    joinery = dict(v.cells)
    if kind == 'torch':
        torches(v, dark, light, level)
        v.cells.update(joinery)
        return v
    if kind in VEGETABLES:
        colors = {k: linear(h) for k, h in ITEMS['vegetable_styles'][name].items()} | dict(dark=dark, light=light)
        VEGETABLES[kind](v, colors, level)
        v.cells.update(joinery)
        return v
    if kind == 'fish':
        # Whole fish lie flat, so they sit a level higher than round goods to show over the
        # slats (the low crate is the stored good's picture); two head to tail, and a third
        # across the top of a full crate.
        style = ITEMS['fish_styles'][name]
        y = [3, 4, 6][level]
        notched(v, (-4, 1, -3), (4, y, 3), dark, 0)
        for x, dy, z, along, facing in [(-4, 0, -3, 'x', 1), (-3, 0, 0, 'x', -1), (1, 1, -4, 'z', 1)][:[2, 2, 3][level]]:
            lay_fish(v, style, x, y + dy, z, along, facing)
        v.cells.update(joinery)
        return v
    y = [2, 4, 6][level]
    notched(v, (-4, 1, -3), (4, y, 3), dark, 0)                  # the goods rest on a bed of themselves
    stem, leaf = linear(ITEMS['palette']['stem']), linear(ITEMS['palette']['leaf'])
    sites = [(-3, -2), (0, 0), (2, 1), (-3, 1), (2, -2), (0, -3), (-1, 2), (3, -1), (-2, -1)]
    for i, (x, z) in enumerate(sites[:[3, 6, 9][level]]):
        c = dark if i % 3 else light
        if kind == 'cutting':
            notched(v, (x, y, z), (x + 1, y + 4, z + 1), stem, 0)
            notched(v, (x - 1, y + 2, z), (x, y + 3, z + 2), dark, 0)
            notched(v, (x + 1, y + 3, z - 1), (x + 2, y + 4, z + 1), light, 0)
        elif kind == 'cone':                                     # a stepped square cone
            notched(v, (x - 1, y, z - 1), (x + 1, y + 1, z + 1), dark, 0)
            notched(v, (x - 1, y + 1, z - 1), (x + 1, y + 2, z + 1), light, 0)
            notched(v, (x - 1, y + 2, z - 1), (x + 1, y + 3, z + 1), dark, 0)
            v.cells[x, y + 3, z] = light
        elif kind == 'acorn':                                    # square nut under a darker cap
            notched(v, (x - 1, y, z - 1), (x + 1, y + 2, z + 1), light, 0)
            notched(v, (x - 1, y + 2, z - 1), (x + 1, y + 3, z + 1), dark, 0)
            v.cells[x, y + 3, z] = stem
        elif kind == 'seed':
            notched(v, (x - 1, y, z - 1), (x + 1, y + 1, z + 1), c, 0)
            v.cells[x, y + 1, z] = light
        elif kind == 'fruit':                                    # square apples with a stem
            notched(v, (x - 1, y, z - 1), (x + 2, y + 3, z + 2), c, 0)
            v.cells[x, y + 3, z] = stem; v.cells[x + 1, y + 3, z] = leaf
        elif kind == 'strawberry':
            notched(v, (x - 1, y, z - 1), (x + 1, y + 2, z + 1), c, 0)
            notched(v, (x - 1, y + 2, z - 1), (x + 1, y + 3, z + 1), leaf, 0)
        else:                                                    # berries: chunky cubes, lit on top
            notched(v, (x - 1, y, z - 1), (x + 1, y + 2, z + 1), c, 0)
            v.cells[x, y + 2, z] = light
    v.cells.update(joinery)
    return v


# ── Tool goods: stone and copper heads bound on with rope ────────────────────────
def slant(v, low, high, color, top=None, w=2):
    """A haft lying aslant on the ground, w cells wide and high: from x low[0] at z low[1] to
    x high[0] in the row before z high[1], stepping sideways a cell at a time, one straight run
    of cells to each step. `top` lights its upper face. Returns where it lies at a given z."""
    (xa, za), (xb, zb) = low, high
    def at(z): return xa + (2 * (xb - xa) * (z - za) + zb - 1 - za) // (2 * (zb - 1 - za))   # the nearest cell, a half going up
    start = za
    for z in range(za + 1, zb + 1):
        if z < zb and at(z) == at(start): continue
        notched(v, (at(start), 0, start), (at(start) + w, w, z), color, 0)
        if top is not None: paint(v, (at(start), w - 1, start), (at(start) + w, w, z), top)
        start = z
    return at


def cast(v, lo, hi):
    """A piece of copper: the bar's body on a dark foot."""
    notched(v, lo, hi, COPPER['body'], 0)
    paint(v, lo, (hi[0], lo[1] + 1, hi[2]), COPPER['shade'])


def pick_arm(v, lo, hi, ridge):
    """One length of a cast pick head lying on its side: two cells thick, with a ridge one cell
    proud along z ridge[0]..ridge[1] and shade under the ridge's inner side."""
    cast(v, lo, (hi[0], 2, hi[2]))
    paint(v, (lo[0], 1, lo[2]), (hi[0], 2, ridge[0]), COPPER['shade'])
    notched(v, (lo[0], 2, ridge[0]), (hi[0], 3, ridge[1]), COPPER['body'], 0)


def cord(v, x0, z0, z1):
    """Cord wound round a handle two cells square: rope with a darker turn every third cell."""
    paint(v, (x0, 0, z0), (x0 + 2, 2, z1), WOOD['rope'])
    for z in range(z0 + 1, z1, 3): paint(v, (x0, 0, z), (x0 + 2, 2, z + 1), WOOD['rope_dark'])


def copper_chisel(v, low, high):
    """A copper chisel three cells square lying aslant from low to high (slant's own points): its
    low end burred over by the maul, its high end flaring and thinning to an edge ground bright."""
    at = slant(v, low, high, COPPER['body'], w=3)
    for z in range(low[1], high[1]): paint(v, (at(z), 0, z), (at(z) + 3, 1, z + 1), COPPER['shade'])
    x, z = low
    cast(v, (x - 1, 0, z - 1), (x + 4, 3, z + 1))                            # the burr
    paint(v, (x - 1, 1, z - 1), (x + 4, 3, z), COPPER['light'])
    x, z = at(high[1] - 1), high[1]
    carve(v, (x, 2, z - 3), (x + 3, 3, z))                                   # thinning
    cast(v, (x - 1, 0, z - 3), (x + 4, 2, z))                                # and flaring
    notched(v, (x - 1, 0, z), (x + 4, 1, z + 1), COPPER['light'], 0)         # to its edge


def starter(name):
    wood, grain, bark = TOOL['wood'], TOOL['grain'], TOOL['bark']
    stone, light, shade, fresh, bevel = STONE['skin'], STONE['top'], STONE['dark'], STONE['fresh'], STONE['fresh_dark']
    rope, rope_dark = WOOD['rope'], WOOD['rope_dark']
    copper, bright, dull = COPPER['body'], COPPER['light'], COPPER['shade']
    v = Voxels()
    def haft(z0, z1, x0=-1): notched(v, (x0, 0, z0), (x0 + 2, 2, z1), wood, 0); paint(v, (x0, 1, z0), (x0 + 2, 2, z1), grain)
    # A tool good lies along Z with its head toward +Z, thin enough to carry and no longer than the
    # tool rack's hook is high (39 cells, the Ranger's kit): a rack hangs a tool by its head end.
    if name == 'ranger_kit':
        # The Ranger's kit (the owner's pick, 2026-11-11): its two tools crossed on the ground and
        # lashed where they cross, heads together, so from above a kit is an X. The stone-tipped
        # spear and the peeled rod cross at a shallow angle. The spear's haft is plain wood, so it
        # reads darker than the rod; its point is knapped pale along both edges.
        slant(v, (-5, -17), (2, 11), wood)
        paint(v, (-5, 0, -17), (-3, 2, -15), bark)
        notched(v, (1, 0, 10), (5, 3, 14), stone, 1)             # a stepped square point
        notched(v, (2, 0, 14), (4, 2, 17), stone, 0)
        paint(v, (1, 2, 10), (5, 3, 14), light)
        for x in (1, 4): paint(v, (x, 0, 11), (x + 1, 3, 13), bevel)
        paint(v, (2, 0, 16), (4, 2, 17), bevel); v.cells[3, 1, 17] = fresh
        notched(v, (1, 0, 8), (5, 3, 10), rope, 0)
        thick = slant(v, (4, -17), (-1, 4), grain)               # the rod: peeled and thick below,
        paint(v, (3, 0, -17), (6, 2, -13), bark)                 # a bark butt,
        slim = slant(v, (-1, 4), (-3, 22), grain, w=1)           # slim above, past the point
        paint(v, (thick(-6), 0, -6), (thick(-6) + 2, 2, -5), wood)   # its knots
        for z in (10, 15): paint(v, (slim(z), 0, z), (slim(z) + 1, 1, z + 1), wood)
        v.cells[-3, 0, 21] = rope
        round_z(v, (0, 0, -12), (4, 3, -7), ROD['line'])         # the line wound on the rod
        notched(v, (-5, 0, 20), (-3, 1, 21), ROD['line'], 0)     # out to the float, tied on beside
        notched(v, (-6, 1, 13), (-5, 2, 15), ROD['float_wood'], 0)
        round_z(v, (-7, 0, 15), (-4, 3, 18), ROD['float_wood'])
        paint(v, (-7, 0, 17), (-4, 3, 18), ROD['float_red'])
        notched(v, (-6, 1, 18), (-5, 2, 21), ROD['float_red'], 0); v.cells[-6, 1, 20] = ROD['float_dark']
        notched(v, (-2, 0, 0), (3, 3, 3), rope, 0)               # lashed where they cross
        for z in (0, 2): paint(v, (-2, 2, z), (3, 3, z + 1), rope_dark)
    elif name == 'stone_hammer':
        # A head a hand could swing, across a haft long enough to hold. The haft's end is let into
        # the head and bound there: a rope ring behind it, a band over it. Both striking faces are
        # worn pale (doc 301).
        haft(-12, 3)
        paint(v, (-1, 0, -11), (1, 2, -7), rope)                  # the grip binding
        notched(v, (-5, 0, 0), (5, 5, 5), stone, 0)
        notched(v, (-4, 5, 1), (4, 6, 4), stone, 0)
        paint(v, (-5, 4, 0), (5, 5, 5), light); paint(v, (-4, 5, 1), (4, 6, 4), light)
        paint(v, (-5, 0, 0), (-4, 5, 5), fresh); paint(v, (4, 0, 0), (5, 5, 5), fresh)
        notched(v, (-2, 0, -2), (2, 3, 0), rope, 0); paint(v, (-2, 0, -1), (2, 3, 0), rope_dark)
        paint(v, (-1, 2, 0), (1, 6, 5), rope); paint(v, (-1, 5, 2), (1, 6, 3), rope_dark)
    # The Blacksmith's copper tools (doc 306): each is one copper bar and one log, so its metal holds
    # no more cells than the bar and its haft takes the log's wood. A first copper age: cast in a
    # stone mould and hammered with a stone, plain and thick.
    elif name == 'copper_pick':
        # The stone pick's own outline cast in copper: one bar pointed at both ends, seated across
        # the haft's top and lashed there. It lies on its side, so from above it is a pick.
        haft(-15, 15)
        paint(v, (-1, 0, -14), (1, 2, -10), rope)                 # the grip binding
        for s in (1, -1):
            def span(a, b): return (a, b) if s > 0 else (-b, -a)
            a, b = span(0, 4); pick_arm(v, (a, 0, 9), (b, 2, 13), (10, 12))      # thick at the eye,
            a, b = span(4, 6); pick_arm(v, (a, 0, 8), (b, 2, 12), (9, 11))       # the arms dropping
            a, b = span(6, 8); pick_arm(v, (a, 0, 7), (b, 2, 10), (8, 9))        # and thinning
            a, b = span(8, 9); notched(v, (a, 0, 6), (b, 2, 8), bright, 0)       # to a point ground bright
        notched(v, (-2, 0, 8), (2, 3, 14), rope, 0)               # lashed over the eye
        for z in (10, 12): paint(v, (-2, 0, z), (2, 3, z + 1), rope_dark)
    elif name == 'copper_saw':
        # A Japanese pull saw (the owner, 2026-11-13), a ryoba: a long straight handle wound with
        # cord and, in line with it, a thin blade that widens to its end, fine teeth down one edge
        # and coarse teeth down the other. Two cells shorter than a rack's hook is high.
        haft(-17, -1)
        cord(v, -1, -14, -4)
        notched(v, (-2, 0, -4), (2, 3, -1), rope, 0); paint(v, (-2, 0, -3), (2, 3, -2), rope_dark)   # the blade's tang bound into the split end
        notched(v, (-1, 0, -1), (1, 1, 2), dull, 0)               # the neck
        for z0, z1, half in ((2, 3, 2), (3, 11, 3), (11, 20, 4)):
            notched(v, (-half, 0, z0), (half, 1, z1), copper, 0)
            for z in range(max(z0, 3), z1):
                v.cells[-half, 0, z] = v.cells[half - 1, 0, z] = dull   # the bevels' shade
                if z % 2 == 1: v.cells[-half - 1, 0, z] = bright  # fine teeth, filed bright
                if z % 4 != 2: v.cells[half, 0, z] = bright       # coarse teeth
    elif name == 'copper_chisel':
        # The copper chisel crossed with the hammerstone maul that strikes it and lashed where they
        # cross, as the Ranger's kit is. The maul is the Stonemason's own, on its side: a
        # hammerstone at the haft's side, its haft aslant below the stone.
        copper_chisel(v, (-7, -12), (3, 12))
        slant(v, (6, -14), (-2, 4), wood, grain)                  # the maul's haft
        notched(v, (-2, 0, 4), (0, 2, 12), wood, 0); paint(v, (-2, 1, 4), (0, 2, 12), grain)
        paint(v, (6, 0, -14), (8, 2, -12), bark)
        notched(v, (-10, 1, 3), (-2, 7, 11), stone, 0); notched(v, (-9, 0, 5), (-3, 8, 9), stone, 0)   # the hammerstone
        paint(v, (-10, 6, 3), (-2, 8, 11), light); paint(v, (-10, 0, 3), (-2, 2, 11), shade)
        paint(v, (-10, 1, 3), (-9, 7, 11), fresh); paint(v, (-10, 2, 5), (-9, 6, 9), bevel)            # its striking face worn pale
        paint(v, (-5, 0, 3), (-3, 8, 11), rope); paint(v, (-5, 0, 3), (-4, 8, 11), rope_dark)          # one band round the stone by the haft
        notched(v, (-3, 0, 5), (0, 3, 10), rope, 0)                                                    # and rope round the haft behind it
        for z in (6, 8): paint(v, (-3, 0, z), (0, 3, z + 1), rope_dark)
        notched(v, (-3, 0, -3), (3, 4, 2), rope, 0)               # lashed where they cross
        for z in (-2, 0): paint(v, (-3, 3, z), (3, 4, z + 1), rope_dark)
    elif name == 'copper_hoe':
        # The owner's pick (2026-11-13, option B of doc 306's sheet): a blade lashed under the haft's
        # bent knee, as the carpentry kit's adze was. It lies on its side, the blade on edge and
        # sweeping back, so from above it is a hoe's own profile.
        haft(-14, 11, -7)
        paint(v, (-7, 0, -13), (-5, 2, -9), rope)                 # the grip binding
        notched(v, (-5, 0, 9), (-1, 2, 11), wood, 0); paint(v, (-5, 1, 9), (-1, 2, 11), grain)   # the knee: a branch crook
        cast(v, (-5, 0, 6), (-1, 6, 9)); cast(v, (-1, 0, 5), (3, 6, 8)); cast(v, (3, 0, 4), (7, 6, 6))   # the blade under it, sweeping back and thinning
        notched(v, (7, 0, 4), (8, 6, 5), bright, 0)               # to an edge ground bright
        notched(v, (-4, 0, 6), (-2, 7, 11), rope, 0); paint(v, (-3, 0, 6), (-2, 7, 11), rope_dark)   # lashed under the knee
    else:
        raise ValueError('no tool good ' + name)
    return v

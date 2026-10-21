"""Hearthblock stockpile goods (doc 256): the stored goods the game has today, in the
furniture's and trees' square vocabulary.

Mined stone, soil and ore are chunky square fragments with a split; gems are square
crystal clusters; logs are the Tier 1 stool on its side in each wood's colours;
produce, seeds and cuttings sit in an axe-hewn crate at three fill levels; starter
tools have square stone heads lashed to their hafts. Every good keeps its previous
footprint, so carrying, crate storage and stockpile tiles are unchanged. Goods the
game does not have yet (drinks, staves, cloth, honey, ...) stay in items.py.
"""
from common import Voxels, linear, read_json
import hearthblock

ITEMS = read_json('data/art/voxel_items.json')
TOOL = {k: linear(v) for k, v in read_json('data/materials/craft_materials.json')['source_palettes']['starter_tool']['colors'].items()}
WOOD = {k: linear(v) for k, v in dict(riven='C08A4E', riven_dark='9A6A38', chop='7A512E', bark='5C3B26',
                                      bark_light='7B5336', bark_dark='3E2819', rope='CFAB69', rope_dark='9F7E45').items()}
STONE = {k: linear(v) for k, v in dict(stone='7C8587', stone_light='9EA6A6', stone_dark='5E676B').items()}


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


def crate(name, level):
    v = shell(); kind, dark, light = ITEMS['crate_contents'][name]; dark, light = linear(dark), linear(light)
    joinery = dict(v.cells)
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


# ── Starter tools: square stone heads lashed with rope ──────────────────────────
def starter(name):
    wood, grain, bark = TOOL['wood'], TOOL['grain'], TOOL['bark']
    stone, light, shade = STONE['stone'], STONE['stone_light'], STONE['stone_dark']
    rope = WOOD['rope']
    v = Voxels()
    def haft(z0, z1): notched(v, (-1, 0, z0), (1, 2, z1), wood, 0); paint(v, (-1, 1, z0), (1, 2, z1), grain)
    if name == 'hunting_spear':
        haft(-17, 11)
        notched(v, (-2, 0, 10), (2, 3, 14), stone, 1)            # a stepped square point
        notched(v, (-1, 0, 14), (1, 2, 17), stone, 0); v.cells[0, 1, 17] = light
        paint(v, (-2, 2, 10), (2, 3, 14), light)
        notched(v, (-2, 0, 8), (2, 3, 10), rope, 0)
        notched(v, (-1, 0, -17), (1, 2, -15), bark, 0)
    elif name == 'carpentry_kit':
        for x in (-5, 4): notched(v, (x, 0, -10), (x + 2, 2, 9), wood, 0)
        notched(v, (-9, 0, 4), (-1, 6, 9), grain, 1)             # the mallet head
        paint(v, (-9, 5, 4), (-1, 6, 9), wood)
        notched(v, (2, 0, 4), (9, 4, 10), stone, 1)              # the adze blade
        paint(v, (2, 3, 4), (9, 4, 10), light); paint(v, (2, 0, 9), (9, 4, 10), shade)
        notched(v, (-7, 0, -3), (8, 3, -1), rope, 0)             # a rope binding the bundle
    elif name == 'stone_hammer':
        haft(-10, 5)
        notched(v, (-6, 0, 0), (6, 8, 7), stone, 2)
        paint(v, (-6, 7, 0), (6, 8, 7), light); paint(v, (-6, 0, 0), (6, 2, 7), shade)
        notched(v, (-2, 0, -2), (2, 3, 0), rope, 0)
        notched(v, (-1, 8, 2), (1, 9, 5), rope, 0)
    else:                                                        # stone hoe
        haft(-14, 9)
        notched(v, (-6, 0, 8), (6, 3, 13), stone, 1)
        paint(v, (-6, 2, 8), (6, 3, 13), light); paint(v, (-6, 0, 12), (6, 3, 13), shade)
        notched(v, (-2, 0, 6), (2, 3, 8), rope, 0)
        notched(v, (-1, 3, 9), (1, 4, 12), rope, 0)
    return v

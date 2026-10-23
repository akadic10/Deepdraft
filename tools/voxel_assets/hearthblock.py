"""Hearthblock pilot solids, replayed from the proposal's authoring logs.

`tools/art_data/voxel_hearthblock.json` holds each model's operations exactly as the
proposal recorded them. Replay keeps role names until the end so the result can
be compared cell for cell with the proposal, then maps roles to linear colors.
"""
from common import Voxels, linear, read_json

DATA = 'tools/art_data/voxel_hearthblock.json'
OCCLUSION = 'tools/art_data/voxel_occlusion.json'


def _span(lo, hi): return range(lo, hi)


def _edge(a, lo, hi): return min(a - lo, hi - 1 - a)


def replay(cells, ops):
    """Apply proposal operations to a {cell: role} dict; None roles carve air."""
    def put(p, role):
        if role is None: cells.pop(p, None)
        else: cells[p] = role
    for entry in ops:
        op = entry[0]
        if op == 'mirror_x':
            side = {}
            replay(side, entry[1])
            cells.update(side)
            cells.update({(-x-1, y, z): role for (x, y, z), role in side.items()})
            continue
        args, role = entry[1], (entry[2] if len(entry) > 2 else None)
        if op in ('box', 'air'):
            x0, x1, y0, y1, z0, z1 = args
            for x in _span(x0, x1):
                for y in _span(y0, y1):
                    for z in _span(z0, z1): put((x, y, z), None if op == 'air' else role)
        elif op == 'cutbox':
            x0, x1, y0, y1, z0, z1, n = args
            for x in _span(x0, x1):
                for z in _span(z0, z1):
                    if _edge(x, x0, x1) + _edge(z, z0, z1) < n: continue
                    for y in _span(y0, y1): put((x, y, z), role)
        elif op == 'cutbox_x':
            x0, x1, y0, y1, z0, z1, n = args
            for y in _span(y0, y1):
                for z in _span(z0, z1):
                    if _edge(y, y0, y1) + _edge(z, z0, z1) < n: continue
                    for x in _span(x0, x1): put((x, y, z), role)
        elif op == 'cutbox_z':
            x0, x1, y0, y1, z0, z1, n = args
            for x in _span(x0, x1):
                for y in _span(y0, y1):
                    if _edge(x, x0, x1) + _edge(y, y0, y1) < n: continue
                    for z in _span(z0, z1): put((x, y, z), role)
        elif op == 'paint':
            x0, x1, y0, y1, z0, z1 = args
            for x in _span(x0, x1):
                for y in _span(y0, y1):
                    for z in _span(z0, z1):
                        if (x, y, z) in cells: cells[x, y, z] = role
        elif op == 'ring':
            x0, x1, y, z0, z1 = args
            for x in _span(x0, x1): put((x, y, z0), role); put((x, y, z1-1), role)
            for z in _span(z0, z1): put((x0, y, z), role); put((x1-1, y, z), role)
        else:
            raise ValueError('unknown Hearthblock operation ' + op)
    return cells


def roles(name):
    """Proposal cells for one model after its pilot edits (dropped roles, extra ops, offset, clips)."""
    model = read_json(DATA)['models'][name]
    ops = [op for op in model['ops'] if not (op[0] != 'mirror_x' and len(op) > 2 and op[2] in model.get('drop', []))]
    ops += model.get('extra', [])   # pilot additions after the proposal's own operations
    cells = replay({}, ops)
    dx, dy, dz = model.get('offset', [0, 0, 0])
    cells = {(x+dx, y+dy, z+dz): role for (x, y, z), role in cells.items()}
    # The proposal drew each dwarf as one model, so later layers overwrote shared
    # cells. Separate in-game parts drop the cells a later layer owns instead.
    for other in model.get('clip', []):
        for p in roles(other): cells.pop(p, None)
    return cells


def model(name):
    data = read_json(DATA)
    colors = {role: linear(value) for role, value in data['palettes'][data['models'][name]['palette']].items()}
    vox = Voxels()
    vox.cells = {p: colors[role] for p, role in sorted(roles(name).items())}
    return vox


def occlusion(name=None):
    """Baked corner occlusion settings: the shared curve plus optional solid ground/wall."""
    settings = dict(read_json(OCCLUSION))
    settings.pop('__comment', None)
    if name: settings.update(read_json(DATA)['models'][name].get('occlusion', {}))
    return settings

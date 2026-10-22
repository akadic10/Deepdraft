"""Analytic solid primitives sampled directly on the 1:16 grid, never triangles.

apply() handles boxes, ellipsoids and turned profiles (the wet and dry stones and the
placeholder goods); solid() evaluates the cell-coordinate shape lists in the dwarf,
wildlife and presentation profiles. Every exported face is generated later by the
shared greedy baker.
"""
import math
from common import GRID,Voxels,box,ellipsoid


def _scan(low,high):
    return (range(math.floor(a*GRID),math.ceil(b*GRID)) for a,b in zip(low,high))


def apply(vox,shape,palette):
    op=shape['op']; color=palette[shape['color']]
    target=Voxels()
    if op=='box':
        box(target,shape['center'],shape['size'],color,shape.get('cut',0))
    elif op=='ellipsoid':
        ellipsoid(target,shape['center'],shape['radius'],color,shape.get('power',3))
    elif op=='profile':
        rings=shape['rings'] # y, radius X, radius Z, centre X, centre Z
        inner=shape.get('inner',0)
        colors=[palette[key] for key in shape.get('colors',[shape['color']])]
        low=(min(r[3]-r[1] for r in rings),rings[0][0],min(r[4]-r[2] for r in rings))
        high=(max(r[3]+r[1] for r in rings),rings[-1][0],max(r[4]+r[2] for r in rings))
        xs,ys,zs=_scan(low,high)
        for y in ys:
            at=(y+.5)/GRID
            for a,b in zip(rings,rings[1:]):
                if not a[0]<=at<=b[0]: continue
                t=(at-a[0])/(b[0]-a[0]); rx,rz,cx,cz=[a[i]+(b[i]-a[i])*t for i in range(1,5)]
                for x in xs:
                    for z in zs:
                        u,v=((x+.5)/GRID-cx)/rx,((z+.5)/GRID-cz)/rz
                        distance=u*u+v*v
                        if inner*inner<=distance<=1:
                            sector=int((math.atan2(v,u)+math.pi)*len(colors)/math.tau)%len(colors)
                            target.cells[x,y,z]=colors[sector]
                break
    else: raise ValueError('unsupported native solid '+op)
    vox.cells.update(target.cells)


def solid(vox, shape, palette):
    """Cell-coordinate shapes (box, cutbox, ellipsoid, taper, branch) used by the
    dwarf, wildlife and presentation profiles. Evaluates cell centres, so every
    exported surface stays on the integer grid."""
    op, args, color_id = shape
    color = palette[color_id]
    if op == 'box':
        vox.box(*args, color, shade=False)
        return
    if op == 'cutbox':
        x0, x1, y0, y1, z0, z1, cut = args
        for x in range(x0, x1):
            for z in range(z0, z1):
                if min(x - x0, x1 - x - 1) + min(z - z0, z1 - z - 1) < cut:
                    continue
                for y in range(y0, y1): vox.cells[x, y, z] = color
        return
    if op == 'ellipsoid':
        cx, cy, cz, rx, ry, rz, power = args
        for x in range(math.floor(cx - rx), math.ceil(cx + rx)):
            for y in range(math.floor(cy - ry), math.ceil(cy + ry)):
                remainder = 1 - abs((x + .5 - cx) / rx) ** power - abs((y + .5 - cy) / ry) ** power
                if remainder <= 0: continue
                for z in range(math.floor(cz - rz), math.ceil(cz + rz)):
                    if abs((z + .5 - cz) / rz) ** power <= remainder:
                        vox.cells[x, y, z] = color
        return
    if op == 'taper':
        # Octagonal horizontal silhouette; terrace size controls broad boughs.
        cx, cz, y0, y1, r0, r1, terrace = args
        for y in range(y0, y1):
            t = ((y - y0) // terrace * terrace) / max(1, y1 - y0 - 1)
            r = max(.5, r0 + (r1 - r0) * t)
            for x in range(math.floor(cx - r), math.ceil(cx + r)):
                for z in range(math.floor(cz - r), math.ceil(cz + r)):
                    dx, dz = abs(x + .5 - cx), abs(z + .5 - cz)
                    if max(dx, dz) <= r and dx + dz <= r * 1.5:
                        vox.cells[x, y, z] = color
        return
    if op == 'branch':
        a, b, r0, r1 = args
        distance = math.dist(a, b)
        steps = max(1, math.ceil(distance * 2))
        for i in range(steps + 1):
            t = i / steps
            center = [a[k] + (b[k] - a[k]) * t for k in range(3)]
            r = r0 + (r1 - r0) * t
            solid(vox, ['ellipsoid', [*center, r, r, r, 3], color_id], palette)
        return
    raise ValueError(op)

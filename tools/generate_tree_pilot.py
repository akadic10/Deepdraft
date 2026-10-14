"""Build the complete clustered tree family without changing gameplay.

Closed, flat-shaded bevel clusters and tapered limbs, inspired by study pass 2.
One mesh/material per GLB, deterministic variants, shared wood across seasons.
Run normally to write assets, --check to verify reproducibility and contracts.
Historical comparisons are retained in the dated art reports.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import tempfile

from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "data/art/tree_pilot.json"
DEST = ROOT / "assets/models/flora/trees"


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, b): return tuple(x * b for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def unit(a): return mul(a, 1 / math.sqrt(dot(a, a)))
def rotate(a, yaw): return (a[0]*math.cos(yaw)+a[2]*math.sin(yaw), a[1], -a[0]*math.sin(yaw)+a[2]*math.cos(yaw))
def linear(hex_value):
    values = [int(hex_value[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in values)


class Mesh:
    def __init__(self):
        self.positions, self.normals, self.colors, self.indices = [], [], [], []
        self.wood = []
        self.snow = None

    def triangle(self, a, b, c, normal, color, wood=False):
        if dot(cross(sub(b, a), sub(c, a)), normal) < 0: b, c = c, b
        normal = unit(normal)
        # Snow is a face treatment on the same closed canopy, never a floating cap.
        if self.snow and not wood and normal[1] > .5:
            color = tuple(v*.18+s*.82 for v, s in zip(color, self.snow))
        base = len(self.positions)
        self.positions.extend((a, b, c))
        self.normals.extend([normal]*3)
        self.colors.extend([(*color, 1.0)]*3)
        self.indices.extend((base, base+1, base+2))
        if wood: self.wood.extend((a, b, c))

    def quad(self, a, b, c, d, normal, color, wood=False):
        self.triangle(a, b, c, normal, color, wood)
        self.triangle(a, c, d, normal, color, wood)

    def box(self, at, size, color, bevel, yaw=0):
        half = mul(size, .5)
        radius = min(bevel, min(half)*.7)
        axes = [(1,0,0), (0,1,0), (0,0,1)]
        def world(p): return add(at, rotate(p, yaw))
        for i in range(3):
            j, k = (i+1)%3, (i+2)%3
            for sign in (-1, 1):
                n = mul(axes[i], sign)
                p, u, v = mul(n, half[i]), mul(axes[j], half[j]-radius), mul(axes[k], half[k]-radius)
                self.quad(world(sub(sub(p,u),v)), world(sub(add(p,u),v)), world(add(add(p,u),v)), world(add(sub(p,u),v)), rotate(n,yaw), color)
        for i in range(3):
            for j in range(i+1,3):
                k = 3-i-j
                for a in (-1,1):
                    for b in (-1,1):
                        p = add(mul(axes[i],a*half[i]),mul(axes[j],b*(half[j]-radius)))
                        q = add(mul(axes[i],a*(half[i]-radius)),mul(axes[j],b*half[j]))
                        along = mul(axes[k],half[k]-radius)
                        n = rotate(unit(add(mul(axes[i],a),mul(axes[j],b))),yaw)
                        self.quad(world(sub(p,along)),world(add(p,along)),world(add(q,along)),world(sub(q,along)),n,color)
        for x in (-1,1):
            for y in (-1,1):
                for z in (-1,1):
                    inner = tuple(s*(h-radius) for s,h in zip((x,y,z),half))
                    self.triangle(world(add(inner,(x*radius,0,0))),world(add(inner,(0,y*radius,0))),world(add(inner,(0,0,z*radius))),rotate(unit((x,y,z)),yaw),color)

    def log(self, a, b, r1, r2, color):
        axis = unit(sub(b,a))
        side = unit(cross(axis,(1,0,0) if abs(axis[1]) > .9 else (0,1,0)))
        other = cross(axis,side)
        for i in range(8):
            def radial(n): return add(mul(side,math.cos(n*math.tau/8)),mul(other,math.sin(n*math.tau/8)))
            u, v = radial(i), radial(i+1)
            # Actual tapered-side normal preserves flat planes in production light.
            p,q,s,t = add(a,mul(u,r1)),add(a,mul(v,r1)),add(b,mul(v,r2)),add(b,mul(u,r2))
            if a[1] == 0: # Ground-facing trunk cap stays exactly on the terrain.
                p,q = (p[0],0,p[2]),(q[0],0,q[2])
            normal = unit(cross(sub(q,p),sub(s,p)))
            if dot(normal,add(u,v)) < 0: normal = mul(normal,-1)
            tint = mul(color,(.88,1,.95,1.08)[i%4])
            self.quad(p,q,s,t,normal,tint,True)
            self.triangle(b,t,s,axis,color,True)
            self.triangle(a,q,p,mul(axis,-1),color,True)

    def arrays(self): return self.positions,self.normals,self.colors,self.indices


def build_fruiting_tree(profile, species, stage, variant, season, footprint, picked):
    """Spreading orchard crowns and crooked junipers, with attached seasonal accents."""
    p, dims = profile[species], profile[species][stage]
    rng = random.Random(p['seed'] + 100*['sapling','mature','ancient'].index(stage) + variant*997)
    h, radius, trunk = dims['height'], dims['radius'], dims['trunk_radius']
    mesh = Mesh()
    palette_season = 'autumn' if season == 'autumn_fruiting' else season
    palette = [linear(c) for c in p.get(palette_season,p['summer'])]
    bark = linear(p['bark'][['sapling','mature','ancient'].index(stage)])
    evergreen = species == 'juniper'
    if evergreen and season == 'winter': mesh.snow = linear(p['snow'])
    knee_y = h*.34 if stage == 'sapling' else max(4.3,h*.29)
    knee = (trunk*.06,knee_y,-trunk*.04)
    shoulder = (radius*(.20 if evergreen else -.08),h*.66,radius*.08)
    leader = (radius*(.34 if evergreen else .05),h*.94,-radius*.12)
    mesh.log((0,0,0),knee,trunk,trunk*.65,bark)
    mesh.log(knee,shoulder,trunk*.65,trunk*.34,bark)
    mesh.log(shoulder,leader,trunk*.34,trunk*.09,bark)
    for i in range(5):
        angle = i*math.tau/5+.25
        mesh.log((0,trunk*.9,0),(math.cos(angle)*footprint*.40,trunk*.12,math.sin(angle)*footprint*.40),trunk*.28,trunk*.08,bark)
    accents = []
    if evergreen:
        for limb in range(dims['limbs']):
            t = limb/(dims['limbs']-1)
            angle = limb*2.35+rng.uniform(-.24,.24)+variant*.5
            y = h*(.43+.40*t)
            spread = radius*(.84-.40*t)
            attach = (shoulder[0]*min(1,y/shoulder[1]),y,shoulder[2]*min(1,y/shoulder[1]))
            end = add(attach,(math.cos(angle)*spread,h*.045,math.sin(angle)*spread))
            # Branch bases follow the piecewise bent leader, rather than float beside it.
            start_a,start_b = (knee,shoulder) if y < shoulder[1] else (shoulder,leader)
            f = (y-start_a[1])/(start_b[1]-start_a[1])
            attach = add(start_a,mul(sub(start_b,start_a),f))
            mesh.log(attach,end,trunk*.28,trunk*.07,bark)
            for clump in range(3):
                centre = add(attach,mul(sub(end,attach),.35+clump*.32))
                width = radius*(.78-.20*t)*rng.uniform(.90,1.1)
                size = (width,h*(.145-.025*t),width*.87)
                mesh.box(centre,size,palette[(limb+clump)%5],width*.12,angle+.15*clump)
                if clump == 2: accents.append((centre,size,angle))
        mesh.box((leader[0],h*.925,leader[2]),(radius*.56,h*.15,radius*.54),palette[3],radius*.065,.35)
    else:
        for limb in range(dims['limbs']):
            angle = limb*math.tau/dims['limbs']+.35+rng.uniform(-.21,.21)
            reach = radius*rng.uniform(.74,1.0)
            centre = (math.cos(angle)*reach,h*rng.uniform(.66,.79),math.sin(angle)*reach*.82)
            fork = (centre[0]*.59,max(knee_y+.45,centre[1]*.80),centre[2]*.59)
            mesh.log(knee,fork,trunk*.38,trunk*.20,bark)
            mesh.log(fork,centre,trunk*.20,trunk*.075,bark)
            for twig in range(3):
                turn = angle+(twig-1)*.65
                end = add(centre,(math.cos(turn)*radius*.23,h*(.07+.018*twig),math.sin(turn)*radius*.20))
                mesh.log(centre,end,trunk*.08,trunk*.025,bark)
            exposed = None
            for clump in range(5):
                pos = add(centre,(rng.uniform(-.20,.20)*radius,rng.uniform(-.025,.06)*h,rng.uniform(-.20,.20)*radius))
                width = radius*rng.uniform(.51,.66)
                size = (width,width*.60,width*.94)
                yaw = rng.uniform(-.45,.45)
                if season != 'winter': mesh.box(pos,size,palette[(limb+clump)%5],width*.12,yaw)
                if exposed is None or pos[1]+size[1]*.5 > exposed[0][1]+exposed[1][1]*.5:
                    exposed = (pos,size,yaw)
            accents.append(exposed)
        if season != 'winter':
            mesh.box((leader[0],h*.91,leader[2]),(radius*.72,h*.18,radius*.64),palette[3],radius*.08,.27)
            mesh.box((-radius*.24,h*.84,radius*.1),(radius*.72,h*.19,radius*.69),palette[2],radius*.08,-.20)
            mesh.box((radius*.25,h*.84,-radius*.12),(radius*.65,h*.18,radius*.63),palette[4],radius*.08,.35)
    # Structural mesh is identical across foliage seasons/crop states. Accents
    # are appended last; picked fruit never removes wood or leaves.
    mesh.base_positions = mesh.positions.copy()
    mesh.base_colors = mesh.colors.copy()
    mesh.snow = None
    accent = dims['accent_size']
    for index,(centre,size,yaw) in enumerate(accents):
        if species == 'apple' and season == 'spring':
            flowers = [linear(c) for c in p['blossom']]
            for flower in range(2 if stage == 'sapling' else 3):
                offsets = [(-.65,.20),(.55,.35),(.0,-.60)]
                dx,dz = offsets[flower]
                at = add(centre,rotate((dx*accent,size[1]*.5-accent*.08,dz*accent),yaw))
                for dx,dz in ((-.29,0),(.29,0),(0,-.29),(0,.29)):
                    mesh.box(add(at,(dx*accent,0,dz*accent)),(accent*.60,accent*.24,accent*.60),flowers[(index+flower)%2],accent*.09,yaw)
                mesh.box(add(at,(0,accent*.04,0)),(accent*.25,accent*.22,accent*.25),flowers[2],accent*.05,yaw)
        ripe = stage != 'sapling' and not picked and (evergreen or season == 'autumn_fruiting')
        if ripe:
            fruit_colors = [linear(c) for c in p['fruit']]
            # Side clusters intersect the foliage face so no fruit floats loose.
            for side in (-1,1):
                at = add(centre,rotate((side*size[0]*.29,-size[1]*.14,size[2]*.5+accent*.20),yaw))
                if evergreen:
                    for j in range(3):
                        offset = rotate(((j%2)*accent*.68,(j//2)*accent*.65,0),yaw)
                        mesh.box(add(at,offset),(accent,accent*.93,accent),fruit_colors[(index+j)%3],accent*.20,yaw)
                else:
                    mesh.box(at,(accent,accent*.92,accent*.91),fruit_colors[(index+side)%3],accent*.20,yaw)
    return mesh


def validate_geometry(mesh, species, stage, footprint, height):
    assert abs(min(p[1] for p in mesh.positions)) < 1e-8
    assert max(p[1] for p in mesh.positions) <= height+.001, (species,stage,max(p[1] for p in mesh.positions),height)
    assert all(all(math.isfinite(v) for v in p) for p in mesh.positions)
    if stage != 'sapling':
        assert all(abs(p[0]) <= footprint/2+.001 and abs(p[2]) <= footprint/2+.001 for p in mesh.positions if p[1] < 3.99), (species,stage,'low overhang')
    assert max(abs(v) for p in mesh.positions for v in (p[0],p[2])) < 16


def build(profile, species, stage, variant, season, footprint, picked=False):
    if species in ('apple','juniper'):
        mesh = build_fruiting_tree(profile,species,stage,variant,season,footprint,picked)
        validate_geometry(mesh,species,stage,footprint,profile[species][stage]['height'])
        return mesh
    p, dims = profile[species], profile[species][stage]
    rng = random.Random(p['seed'] + 100*['sapling','mature','ancient'].index(stage) + variant*997)
    h, radius, trunk = dims['height'],dims['radius'],dims['trunk_radius']
    mesh = Mesh()
    bark = linear(p['bark'][['sapling','mature','ancient'].index(stage)])
    palette = [linear(c) for c in p.get(season,p.get('summer'))]
    if species == 'pine' and season == 'winter': mesh.snow = linear(p['snow'])
    lean = (rng.uniform(-.12,.12)*trunk,0,rng.uniform(-.12,.12)*trunk)
    # Broad base fills the existing logical trunk. Low roots never obstruct a
    # walkable neighboring cell. Trunk ends and upper branches remain connected.
    crotch = (lean[0],h*(.49 if species == 'pine' else .34),lean[2])
    mesh.log((0,0,0),crotch,trunk,trunk*.68,bark)
    tip = (lean[0]*1.8,h*.96,lean[2]*1.8)
    mesh.log(crotch,tip,trunk*.68,trunk*.1,bark)
    for i in range(5):
        angle = i*math.tau/5+.25
        root_radius = footprint*.40
        mesh.log((0,trunk*.9,0),(math.cos(angle)*root_radius,trunk*.12,math.sin(angle)*root_radius),trunk*.3,trunk*.1,bark)
    if species == 'pine':
        tiers = dims['tiers']
        for tier in range(tiers):
            t = tier/(tiers-1)
            y = h*(.28+.60*t)
            spread = radius*(1-.80*t)
            count = max(4,dims['limbs']-int(t*3))
            for limb in range(count):
                angle = limb*math.tau/count+tier*.7+rng.uniform(-.13,.13)
                direction = (math.cos(angle),0,math.sin(angle))
                end = add(mul(direction,spread),(lean[0],y,lean[2]))
                mesh.log((lean[0],y+h*.065,lean[2]),end,trunk*(.19-.08*t),trunk*.065,bark)
                for clump in range(2):
                    width = radius*(.47-.22*t)*rng.uniform(.9,1.1)
                    centre = add(mul(direction,spread*(.44+.45*clump)),(lean[0],y+h*(.015-clump*.018),lean[2]))
                    mesh.box(centre,(width,width*.8,width*1.18),palette[(limb+clump+tier)%len(palette)],width*.12,angle)
            width = max(radius*.33,spread*.90)
            mesh.box((lean[0],y+h*.055,lean[2]),(width,h*.10,width),palette[(tier+2)%len(palette)],width*.12,tier*.3)
        mesh.box((tip[0],h*.955,tip[2]),(radius*.22,h*.09,radius*.24),palette[3],radius*.045,.3)
    else:
        # The radial scaffold remains in winter. Each fork actually meets its
        # parent limb; all seasonal leaf masses use the exact same seeded layout.
        for limb in range(dims['limbs']):
            angle = limb*math.tau/dims['limbs']+.3+rng.uniform(-.14,.14)
            reach = radius*rng.uniform(.73,1.0)
            centre = (math.cos(angle)*reach,h*rng.uniform(.62,.77),math.sin(angle)*reach)
            fork = (centre[0]*.63,centre[1]*.81,centre[2]*.63)
            mesh.log(crotch,fork,trunk*.38,trunk*.21,bark)
            mesh.log(fork,centre,trunk*.21,trunk*.08,bark)
            for twig in range(3):
                turn = angle+(twig-1)*.65
                end = add(centre,(math.cos(turn)*radius*.25,h*(.07+.02*twig),math.sin(turn)*radius*.25))
                mesh.log(centre,end,trunk*.09,trunk*.025,bark)
            # Fewer, larger clusters on saplings; no tiny leaf confetti at RTS zoom.
            for clump in range(5 if stage == 'sapling' else 7):
                pos = add(centre,(rng.uniform(-.24,.24)*radius,rng.uniform(-.035,.10)*h,rng.uniform(-.24,.24)*radius))
                width = radius*rng.uniform(.47,.65)
                yaw = rng.uniform(-.5,.5)
                color = palette[(limb+clump)%len(palette)]
                if season != 'winter': mesh.box(pos,(width,width*.8,width),color,width*.12,yaw)
        if season != 'winter':
            # Interlocking crown masses avoid a single oversized central block.
            mesh.box((lean[0],h*.91,lean[2]),(radius*.68,h*.18,radius*.62),palette[3],radius*.08,.2)
            mesh.box((lean[0]-radius*.25,h*.83,lean[2]+radius*.16),(radius*.75,h*.20,radius*.68),palette[2],radius*.08,-.27)
            mesh.box((lean[0]+radius*.23,h*.85,lean[2]-radius*.21),(radius*.68,h*.18,radius*.72),palette[4],radius*.08,.43)
    # Check real geometry, not only metadata: ground contacts, walk corridor,
    # finite normals, opaque colors and conservative flight/picking bounds.
    mesh.base_positions = mesh.positions.copy()
    validate_geometry(mesh,species,stage,footprint,h)
    return mesh


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    profile = json.loads(PROFILE.read_text(encoding='utf-8'))
    report = []
    with tempfile.TemporaryDirectory() as temp:
        for species in ('pine','oak','apple','juniper'):
            defs = json.loads((ROOT/f'data/entities/flora/{species}_tree.json').read_text(encoding='utf-8'))[f'base:flora:{species}_tree']
            for stage, data in defs['stages'].items():
                woods, shapes, crops = {}, {}, {}
                roster = [(season,paths,False) for season,paths in data['models'].items()]
                roster += [(season,paths,True) for season,paths in data.get('picked_models',{}).items()]
                for season, paths, picked in roster:
                    if isinstance(paths,str): paths = [paths]
                    for index,path in enumerate(paths):
                        mesh = build(profile,species,stage,index,season,defs['placement']['footprint'][stage],picked)
                        if index in woods: assert mesh.wood == woods[index], 'season changed branch structure'
                        woods[index] = mesh.wood
                        if season != 'winter' or species in ('pine','juniper'):
                            if index in shapes: assert mesh.base_positions == shapes[index], 'season changed canopy geometry'
                            shapes[index] = mesh.base_positions
                        if species == 'juniper':
                            if picked:
                                original = crops[(index,season)]
                                assert mesh.positions == original.base_positions and mesh.colors == original.base_colors, 'picking changed wood/leaves'
                                assert len(original.positions) > len(mesh.positions), 'ripe berries missing'
                            else: crops[(index,season)] = mesh
                        filename = Path(path).name
                        dest = DEST/species/filename
                        target = Path(temp)/filename if args.check else dest
                        write_glb(target,filename.removesuffix('.glb'),mesh.arrays())
                        if args.check: assert target.read_bytes() == dest.read_bytes(), f'{dest} is not reproducible'
                        report.append({'file':str(dest.relative_to(ROOT)).replace('\\','/'),'triangles':len(mesh.indices)//3,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    print(json.dumps({'models':len(report),'min_triangles':min(r['triangles'] for r in report),'max_triangles':max(r['triangles'] for r in report),'mode':'verified' if args.check else 'generated'},indent=2))


if __name__ == '__main__': main()

"""Author all 76 surface plant models in the approved clustered low-poly style.

One closed, opaque, linear vertex-color surface per asset, in world units.
Leaves and petals are solid faceted shapes; no alpha cards or extra materials.
Historical comparison images and metrics remain in the dated art reports.
Run --check for geometry, crop/packing contracts and byte reproducibility.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import tempfile

from generate_tree_pilot import Mesh, add, sub, mul, dot, cross, unit, linear, rotate
from voxel_glb import write_glb

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/models/flora"
PROFILE = ROOT / "data/art/surface_vegetation.json"
SEASONS = ("spring", "summer", "autumn", "winter")
RIPE = {"blueberry": ("summer",), "elderberry": ("autumn",), "wild_strawberry": ("spring", "summer")}


def leaf(mesh, start, end, width, color, thickness=.035):
    """Closed eight-triangle leaf: a central ridge with four tapered edges."""
    axis = sub(end, start)
    side = unit((-axis[2], 0, axis[0]))
    middle = add(start, mul(axis, .46))
    left, right = add(middle, mul(side, width*.5)), sub(middle, mul(side, width*.5))
    top, bottom = add(middle, (0, thickness, 0)), sub(middle, (0, thickness*.45, 0))
    ring = [start, left, end, right]
    for tip in (top, bottom):
        for i in range(4):
            a, b = ring[i], ring[(i+1)%4]
            normal = cross(sub(b,a), sub(tip,a))
            center = mul(add(add(a,b),tip), 1/3)
            if dot(normal, sub(center,middle)) < 0: normal = mul(normal,-1)
            mesh.triangle(a,b,tip,normal,color)


def flower(mesh, at, radius, color, center, petals=5):
    for i in range(petals):
        angle = math.tau*i/petals+.2
        end = add(at,(math.cos(angle)*radius,.025,math.sin(angle)*radius))
        leaf(mesh,at,end,radius*.90,color,.033)
    mesh.box(add(at,(0,.027,0)),(radius*.45,.060,radius*.45),center,.014,.2)


def shrub(profile, species, season, young=False, picked=False):
    p = profile[species]
    mesh = Mesh()
    bark = linear(p['bark'])
    palette = [linear(c) for c in p.get(season,p['summer'])]
    accents = []
    if species == 'wild_strawberry':
        roots = [(0,0)] if young else [(-.34,-.31),(.29,-.26),(-.27,.30),(.35,.32)]
        for i,(x,z) in enumerate(roots):
            crown = (x,.17 if season != 'winter' else .10,z)
            if x or z: mesh.log((0,0,0),(x,.045,z),.025,.017,bark)
            mesh.log((x,0,z),crown,.026,.019,bark)
            for j in range(3):
                angle = i*.7+j*math.tau/3
                tip = add(crown,(math.cos(angle)*.34,.10 if season != 'winter' else .04,math.sin(angle)*.34))
                leaf(mesh,crown,tip,.27,palette[(i+j)%3],.05)
            if season == 'spring' and not young:
                at = add(crown,(-.05,.20,.02))
                mesh.log(crown,at,.018,.010,palette[0])
                flower(mesh,at,.105,linear(p['blossom']),linear('C4A85E'))
            accents.append((add(crown,(.10,-.065,.16)),(.16,.20,.16),i*.6))
    else:
        elder = species == 'elderberry'
        if young:
            crowns = [(-.30,.68,-.13),(.28,.84,-.04),(0,1.14,.22)]
        elif elder:
            crowns = [(-.60,1.43,-.36),(.49,1.73,-.22),(-.19,2.04,.18),(.59,1.25,.44),(-.53,1.05,.45)]
        else:
            crowns = [(-.36,.71,-.23),(.38,.81,-.19),(-.25,1.04,.33),(.35,.67,.36),(0,1.24,0)]
        for i,center in enumerate(crowns):
            knee = (center[0]*.55,center[1]*.53,center[2]*.55)
            mesh.log((0,0,0),knee,.050 if elder else .040,.028,bark)
            mesh.log(knee,center,.028,.014,bark)
            angle = i*2.18
            width = .68 if elder else .72
            size = (width,.27 if elder else .42,width*.80)
            for j in range(3):
                turn = angle+j*math.tau/3
                offset = (math.cos(turn)*width*.23,.035*j,math.sin(turn)*width*.23)
                end = add(center,offset)
                mesh.log(center,add(end,(0,.11,0)),.018,.007,bark)
                if season != 'winter':
                    mesh.box(end,mul(size,.86 if young else 1),palette[(i+j)%3],width*.13,turn)
                    if j != 1:
                        # Attached to exposed upper/outside crown edges; fruit must
                        # remain readable from all four placement rotations.
                        spot = add(end,rotate((size[0]*.46,size[1]*.33,size[2]*.22),turn))
                        accents.append((spot,(.13,.13,.13) if not elder else (.105,.10,.105),turn))
            if season in (('spring','summer') if elder else ('spring',)) and not young:
                bloom = add(center,(-.10,.23 if elder else .29,-.02))
                mesh.log(center,bloom,.014,.008,bark)
                if elder:
                    # Broad, shallow umbels are a different silhouette from fruit.
                    for j in range(5):
                        turn = j*math.tau/5
                        spot = add(bloom,(math.cos(turn)*.12,.01*(j%2),math.sin(turn)*.12))
                        mesh.box(spot,(.15,.06,.14),linear(p['blossom']),.022,turn)
                else:
                    for j in range(2):
                        mesh.box(add(bloom,(.085*j,0,0)),(.085,.105,.085),linear(p['blossom']),.022,angle)
    # Crop state only appends/removes fruit. Scaffold/foliage/blooms are identical.
    mesh.base_positions = mesh.positions.copy()
    mesh.base_colors = mesh.colors.copy()
    if not young and not picked and season in RIPE[species]:
        for i,(at,size,angle) in enumerate(accents):
            for j in range(2 if species == 'wild_strawberry' else 3):
                offset = (j%2*size[0]*.70,(j//2)*size[1]*.72,0)
                mesh.box(add(at,offset),size,linear(p['fruit'][(i+j)%3]),size[0]*.22,angle)
    if young:
        scale = p['young_scale']
        mesh.positions = [mul(v,scale) for v in mesh.positions]
    return mesh


def flowers(profile, variant, season):
    p = profile['flowers']
    mesh = Mesh()
    palette = [linear(c) for c in p[season]]
    arrangements = [ [(-.40,-.31,.51),(.22,-.20,.76),(-.12,.33,.65),(.39,.38,.43)],
                     [(-.30,-.39,.65),(.33,-.20,.52),(-.38,.20,.43),(.22,.39,.77)],
                     [(-.40,-.20,.43),(.10,-.39,.64),(.40,.21,.78),(-.12,.39,.52)] ]
    for i,(x,z,height) in enumerate(arrangements[variant]):
        winter = season == 'winter'
        h = .20+.035*(i%2) if winter else height
        bottom,top = (x,0,z),(x+.035*(i%2),h,z+.02)
        mesh.log(bottom,top,.022,.012,palette[0])
        if not winter:
            for j in range(2):
                start = (x,h*(.29+.26*j),z)
                angle = i*1.5+j*2.7
                end = add(start,(math.cos(angle)*.19,.09,math.sin(angle)*.19))
                leaf(mesh,start,end,.12,palette[j],.026)
        if season == 'summer' or (season == 'spring' and i%2 == 0):
            flower(mesh,top,.17 if variant != 1 else .145,linear(p['petals'][variant]),linear(p['centers'][variant]),5 if variant != 1 else 4)
        elif season == 'spring':
            mesh.box(top,(.07,.11,.07),linear(p['petals'][variant]),.021)
        elif season == 'autumn':
            mesh.box(top,(.09,.10,.08),palette[1],.025,i)
    return mesh


def reeds(profile, variant, season):
    p = profile['reeds']
    mesh = Mesh()
    palette = [linear(c) for c in p[season]]
    for i,(x,z) in enumerate([(-.25,-.25),(.23,-.12),(-.12,.23),(.23,.34)]):
        h = p['heights'][variant]-.10*(i%3)
        if season == 'spring': h -= .20
        if season == 'winter' and i%2: h -= .34
        tip = (x+.04*(i%2),h,z)
        mesh.log((x,0,z),tip,.025,.014,palette[0])
        for j in range(1 if season == 'winter' else 2):
            start = (x,h*(.18+.15*j),z)
            angle = i*1.7+j*2.5
            end = add(start,(math.cos(angle)*.30,h*.53,math.sin(angle)*.30))
            leaf(mesh,start,end,.13,palette[j],.034)
        if season in ('summer','autumn') and i%2 == 0:
            # Cattail occupies the upper stem instead of extending the envelope.
            mesh.box((tip[0],h-.14,z),(.14,.29,.14),linear(p['heads'][season=='autumn']),.044,i*.4)
    return mesh


def pack(profile, plant, shrub_root):
    mesh = Mesh()
    p = profile['packing']
    lift = .34 if shrub_root else .22
    # Same exact plant, translated above a closed soil/cloth bundle.
    mesh.positions = [add(v,(0,lift,0)) for v in plant.positions]
    mesh.normals,mesh.colors,mesh.indices = plant.normals.copy(),plant.colors.copy(),plant.indices.copy()
    width = 1.00 if shrub_root else 1.22
    if shrub_root:
        mesh.log((0,0,0),(0,lift*.52,0),.35,.60,linear(p['cloth']))
        mesh.log((0,lift*.52,0),(0,lift-.018,0),.60,.51,linear(p['cloth']))
        mesh.log((0,lift-.032,0),(0,lift,0),.49,.49,linear(p['soil']))
    else:
        mesh.box((0,lift*.5,0),(width,lift,width),linear(p['cloth']),.07,.0)
        mesh.box((0,lift-.027,0),(width-.16,.055,width-.16),linear(p['soil']),.025)
    # Crossed fabric ties reach over the soil, then continue down the wrap sides.
    for axis in (0,1):
        size = (width-.08,.04,.052) if axis == 0 else (.052,.04,width-.08)
        mesh.box((0,lift+.012,0),size,linear(p['seam']),.012)
        if not shrub_root:
            for sign in (-1,1):
                at = (sign*width*.5,lift*.5,0) if axis == 0 else (0,lift*.5,sign*width*.5)
                size = (.025,lift*.67,.052) if axis == 0 else (.052,lift*.67,.025)
                mesh.box(at,size,linear(p['seam']),.008)
    return mesh


def models(profile):
    for species in RIPE:
        for season in SEASONS:
            base = f"bushes/{species}/{species}"
            yield f"{base}_young_{season}.glb", shrub(profile,species,season,young=True), 1.0
            for picked in ((False,True) if season in RIPE[species] else (False,)):
                suffix = season+('_picked' if picked else '')
                plant = shrub(profile,species,season,picked=picked)
                yield f"{base}_{suffix}.glb",plant,profile[species]['height']
                yield f"{base}_packed_{suffix}.glb",pack(profile,plant,True),profile[species]['height']+.34
    for variant in range(3):
        for season in SEASONS:
            plant = flowers(profile,variant,season)
            yield f"flowers/flowers_{variant+1}_{season}.glb",plant,profile['flowers']['height']
            yield f"flowers/flowers_{variant+1}_packed_{season}.glb",pack(profile,plant,False),profile['flowers']['height']+.22
    for variant in range(2):
        for season in SEASONS:
            yield f"reeds/reeds_{variant+1}_{season}.glb",reeds(profile,variant,season),2.0


def check_mesh(name,mesh,height):
    assert abs(min(p[1] for p in mesh.positions)) < 1e-7, (name,'ground')
    assert max(p[1] for p in mesh.positions) <= height+.001, (name,'height')
    limit = 1.5 if name.startswith('bushes') else .75
    assert max(abs(v) for p in mesh.positions for v in (p[0],p[2])) <= limit, (name,'envelope')
    assert len(mesh.positions) == len(mesh.normals) == len(mesh.colors)
    assert all(math.isfinite(v) for p in mesh.positions for v in p)
    assert all(c[3] == 1 and all(0 <= x <= 1 for x in c) for c in mesh.colors)
    # Every individually authored primitive is closed, with matching edges after
    # welding positions. Coincident/intersecting solids are legal foliage clusters.
    edges = {}
    for i in range(0,len(mesh.indices),3):
        ids = mesh.indices[i:i+3]
        a,b,c = [mesh.positions[n] for n in ids]
        normal = cross(sub(b,a),sub(c,a))
        assert dot(normal,normal) > 1e-15, (name,'degenerate face')
        assert dot(normal,mesh.normals[ids[0]]) > 0, (name,'winding')
        for j in range(3):
            key = tuple(sorted(tuple(round(v,7) for v in mesh.positions[ids[n]]) for n in (j,(j+1)%3)))
            edges[key] = edges.get(key,0)+1
    assert all(count%2 == 0 for count in edges.values()), (name,'open edge')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    profile = json.loads(PROFILE.read_text(encoding='utf-8'))
    rows = []
    with tempfile.TemporaryDirectory(prefix='deepdraft_vegetation_') as temporary:
        for name,mesh,height in models(profile):
            check_mesh(name,mesh,height)
            destination = Path(temporary)/name if args.check else DEST/name
            write_glb(destination,Path(name).stem,mesh.arrays())
            if args.check: assert destination.read_bytes() == (DEST/name).read_bytes(), (name,'not reproducible')
            rows.append({'path':name,'triangles':len(mesh.indices)//3,'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest()})
    assert len(rows) == 76
    for species,seasons in RIPE.items():
        for season in seasons:
            ripe,picked = shrub(profile,species,season),shrub(profile,species,season,picked=True)
            assert ripe.base_positions == picked.positions and ripe.base_colors == picked.colors
            assert len(ripe.positions) > len(picked.positions)
        for season in SEASONS:
            plant = shrub(profile,species,season)
            packed = pack(profile,plant,True)
            assert packed.positions[:len(plant.positions)] == [add(v,(0,.34,0)) for v in plant.positions]
            young = shrub(profile,species,season,young=True)
            young_picked = shrub(profile,species,season,young=True,picked=True)
            assert young.positions == young_picked.positions and young.colors == young_picked.colors
    for variant in range(3):
        for season in SEASONS:
            plant = flowers(profile,variant,season)
            packed = pack(profile,plant,False)
            assert packed.positions[:len(plant.positions)] == [add(v,(0,.22,0)) for v in plant.positions]
            assert packed.colors[:len(plant.colors)] == plant.colors
    # Resolve the actual live roster, including ItemDropManager's fallback paths.
    definitions = [ROOT/f'data/entities/flora/{s}_bush.json' for s in RIPE]
    definitions += [ROOT/'data/entities/surface_details.json',ROOT/'data/entities/items/resources.json']
    live = set()
    def collect(value):
        if isinstance(value,str) and value.endswith('.glb'):
            prefix = 'res://assets/models/flora/'
            if value.startswith(tuple(prefix+family+'/' for family in ('bushes','flowers','reeds'))):
                live.add(value.removeprefix(prefix))
            assert not any(old in value for old in ('/flora/vegetation/','/details/flowers/','/details/reeds/')), ('legacy live reference',value)
        elif isinstance(value,dict):
            for child in value.values(): collect(child)
        elif isinstance(value,list):
            for child in value: collect(child)
    for definition in definitions: collect(json.loads(definition.read_text(encoding='utf-8')))
    assert live == {row['path'] for row in rows}, ('registry/asset roster mismatch',live.symmetric_difference(row['path'] for row in rows))
    print(f"VEGETATION_ART_{'CHECK' if args.check else 'BUILD'}_PASS {len(rows)} models; {sum(r['triangles'] for r in rows)} total triangles")
    if not args.check:
        report = ROOT/'tmp/vegetation_art_20261013'
        report.mkdir(parents=True,exist_ok=True)
        (report/'assets.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__': main()

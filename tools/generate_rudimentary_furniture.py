"""Rough log fence, hinged gate and games scratched into cut logs."""
import argparse
import math
import tempfile
from pathlib import Path
from generate_furniture_faceted import Mesh, WOOD, P, timber, face, validate, write_parts

ROOT = Path(__file__).resolve().parents[1]
POST_HEIGHT = 1.3
RAIL_HEIGHTS = (.45, 1.0)


def fence(gate=False):
    post = Mesh()
    timber(post, (0, 0, 0), (0, POST_HEIGHT, 0), (.11, .12), WOOD)
    if gate:
        from generate_furniture_faceted import transformed
        rails = Mesh()
        for y in RAIL_HEIGHTS:
            timber(rails, (-.86,y,0), (.86,y,0), (.075,.085), WOOD)
        for x in [-.84, .84]:
            timber(rails, (x,.28,0), (x,1.15,0), (.075,.085), WOOD)
        timber(rails, (-.81,.35,.02), (.81,1.08,.02), (.065,.07), WOOD)
        return {'post_left': transformed(post,(-1,0,0)),
                'post_right': transformed(post,(1,0,0)), 'leaf_left': rails}
    return {'post': post}


def fence_rails():
    m = Mesh()
    for y in RAIL_HEIGHTS:
        timber(m, (-.5,y,0), (.5,y,0), (.075,.085), WOOD)
    return {'rails': m}


def game_table():
    m = Mesh()
    # A single squat section of trunk. Broad bark faces, a flared base and
    # chipped cut rim give this the same starter construction as the workbench.
    radial = [1, .96, 1.02, .94, .99, 1, .95, 1.01, .96, .98, 1.02, .95]
    roles = ['bark', 'bark_dark', 'bark', 'wood_dark', 'bark', 'bark',
             'wood_dark', 'bark', 'bark_dark', 'bark', 'bark', 'wood_dark']
    loops = []
    for y, radius in [(0, 1.37), (.16, 1.34), (.64, 1.25), (.74, 1.28)]:
        loops.append([(math.cos(i*math.tau/12)*radius*r,
                       y-(.045 if y == .74 and i in [2, 7, 10] else 0),
                       math.sin(i*math.tau/12)*radius*r) for i, r in enumerate(radial)])
    cut = [(math.cos(i*math.tau/12)*1.16*r, .78,
            math.sin(i*math.tau/12)*1.16*r) for i, r in enumerate(radial)]
    for lo, hi in zip(loops, loops[1:]):
        for i in range(12):
            j = (i+1) % 12
            face(m, [lo[i], lo[j], hi[j], hi[i]], (lo[i][0], 0, lo[i][2]), WOOD[roles[i]])
    for i in range(12):
        j = (i+1) % 12
        face(m, [loops[-1][i], loops[-1][j], cut[j], cut[i]],
             (cut[i][0], 1, cut[i][2]), WOOD['wood' if i in [2, 7, 10] else 'bark'])
        face(m, [(0, 0, 0), loops[0][j], loops[0][i]], (0, -1, 0), WOOD['bark_dark'])
    # Narrow end-grain rings leave a broad, unpolished playing surface.
    previous = cut
    for scale, role in [( .92, 'cut'), (.90, 'ring'), (.68, 'cut'), (.66, 'ring'), (.30, 'cut'), (.28, 'ring')]:
        inside = [(x*scale, y, z*scale) for x, y, z in cut]
        for i in range(12):
            j = (i+1) % 12
            face(m, [previous[i], previous[j], inside[j], inside[i]], (0, 1, 0), WOOD[role])
        previous = inside
    for i in range(12):
        face(m, [(0, .78, 0), previous[i], previous[(i+1) % 12]], (0, 1, 0), WOOD['cut'])
    # Uneven charcoal marks directly on the log; no fitted board or joinery.
    for axis in [0, 1]:
        for i, drift in enumerate([.012, -.016, .006, -.009, .018]):
            t = -.72+i*.36
            m.box((t if axis == 0 else drift, .784, drift if axis == 0 else t),
                  (.022 if axis == 0 else 1.53, .008, 1.53 if axis == 0 else .022),
                  P['soot'], .002, yaw=drift)
    # Unequal pebbles collected for two sides of the game, not turned tokens.
    for i, (x, z, dark) in enumerate([(-.54,-.54,True),(.18,-.54,True),(.54,-.18,True),
                                     (-.18,.18,False),(-.54,.54,False),(.54,.54,False)]):
        m.box((x,.815,z),(.17+.02*(i%2),.07,.15+.025*(i%3)),
              P['stone_dark' if dark else 'stone_light'],.028,yaw=i*.63)
    return {'board_game_table': m}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    dest = ROOT/'assets/models/furniture'
    with tempfile.TemporaryDirectory() as temporary:
        for name, parts in {'log_fence': fence(), 'log_gate': fence(True),
                            'parts/log_fence_rails': fence_rails(),
                            'board_game_table': game_table()}.items():
            for part, mesh in parts.items(): validate(name+'/'+part, mesh)
            path = (Path(temporary) if args.check else dest)/(name+'.glb')
            path.parent.mkdir(parents=True, exist_ok=True)
            write_parts(path, parts)
            if args.check: assert path.read_bytes() == (dest/(name+'.glb')).read_bytes(), name
            print(name, sum(len(m.indices)//3 for m in parts.values()), 'triangles', 'verified' if args.check else 'written')


if __name__ == '__main__': main()
